import 'dotenv/config';
import { logger, logJobSummary } from '../shared/logger';
import { getSupabase, upsertBatch } from '../shared/supabase';
import { readParquet } from '../shared/parquet';
import { isMainModule } from '../shared/cli';

/**
 * FishBase / SeaLifeBase species-enrichment ETL.
 *
 * FishBase (fish) and SeaLifeBase (all other aquatic life) are the
 * authoritative, free, expert-curated references for marine species biology.
 * Their old REST API (`fishbase.ropensci.org`) is dead; the current canonical
 * distribution is a set of static Parquet table snapshots on source.coop. This
 * source reads them directly with a dependency-free Parquet reader — no API
 * key, no native/duckdb dependency, "zero budget".
 *
 * It enriches our `species` rows with:
 *   - real depth ranges (DepthRangeShallow / DepthRangeDeep → min/max_depth_m)
 *   - habitat descriptor (DemersPelag, e.g. "reef-associated", "pelagic-oceanic")
 *     plus the marine/brackish/freshwater environment flags
 *   - typical max length (Length → typical_length_cm)
 *   - multilingual common names (English / Italian / Spanish) from comnames
 *
 * Enrichment is fill-when-empty for name/depth/length columns so curated seed
 * and WoRMS values are never clobbered; FishBase raw values are always mirrored
 * into `metadata.fishbase` regardless, so nothing is lost. The join key is the
 * `Genus species` binomial (case-insensitive), matched against our
 * `species.scientific_name`.
 */

const DATA_BASE =
  process.env.FISHBASE_DATA_BASE ?? 'https://data.source.coop/cboettig/fishbase';

type Server = 'fb' | 'slb';

const SERVER_DIRS: Record<Server, string> = {
  fb: `fb/${process.env.FISHBASE_FB_VERSION ?? 'v24.07'}`,
  slb: `slb/${process.env.FISHBASE_SLB_VERSION ?? 'v24.07'}`,
};

// Which servers to ingest. FishBase covers fish; SeaLifeBase covers everything
// else (inverts, mammals, reptiles), so both are enabled by default.
function selectedServers(): Server[] {
  const raw = process.env.FISHBASE_SERVERS;
  if (!raw) return ['fb', 'slb'];
  const map: Record<string, Server> = { fishbase: 'fb', fb: 'fb', sealifebase: 'slb', slb: 'slb' };
  return raw
    .split(',')
    .map((s) => map[s.trim().toLowerCase()])
    .filter((s): s is Server => Boolean(s));
}

interface FbSpeciesRaw {
  SpecCode: number;
  Genus: string | null;
  Species: string | null;
  FBname: string | null;
  DemersPelag: string | null;
  Fresh: number | null;
  Brack: number | null;
  Saltwater: number | null;
  DepthRangeShallow: number | null;
  DepthRangeDeep: number | null;
  Length: number | null;
}

interface FbComnameRaw {
  SpecCode: number;
  ComName: string | null;
  Language: string | null;
  PreferredName: number | null;
  NameType: string | null;
}

interface FishBaseEntry {
  server: Server;
  specCode: number;
  fbName: string | null;
  habitat: string | null;
  environment: string[];
  depthShallow: number | null;
  depthDeep: number | null;
  length: number | null;
}

interface CommonNames {
  en?: string;
  it?: string;
  es?: string;
}

const LANGUAGES: Record<string, keyof CommonNames> = {
  English: 'en',
  Italian: 'it',
  Spanish: 'es',
};

/** "Thunnus thynnus" → normalized "thunnus thynnus" for case-insensitive joins. */
function normalizeName(name: string): string {
  return name.trim().toLowerCase().replace(/\s+/g, ' ');
}

function environmentFlags(raw: FbSpeciesRaw): string[] {
  const env: string[] = [];
  if (raw.Saltwater) env.push('marine');
  if (raw.Brack) env.push('brackish');
  if (raw.Fresh) env.push('freshwater');
  return env;
}

function toNumberOrNull(value: unknown): number | null {
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

/** Load a server's species table into a name → entry map + specCode index. */
async function loadServer(
  server: Server,
  speciesByName: Map<string, FishBaseEntry>,
  relevantSpecCodes: Set<string>,
): Promise<number> {
  const url = `${DATA_BASE}/${SERVER_DIRS[server]}/parquet/species.parquet`;
  const rows = await readParquet<FbSpeciesRaw>(url, [
    'SpecCode',
    'Genus',
    'Species',
    'FBname',
    'DemersPelag',
    'Fresh',
    'Brack',
    'Saltwater',
    'DepthRangeShallow',
    'DepthRangeDeep',
    'Length',
  ]);

  let indexed = 0;
  for (const row of rows) {
    if (!row.Genus || !row.Species || row.SpecCode == null) continue;
    const key = normalizeName(`${row.Genus} ${row.Species}`);
    // FishBase (fish) is loaded first and wins over SeaLifeBase on collision.
    if (speciesByName.has(key)) continue;
    speciesByName.set(key, {
      server,
      specCode: row.SpecCode,
      fbName: row.FBname,
      habitat: row.DemersPelag,
      environment: environmentFlags(row),
      depthShallow: toNumberOrNull(row.DepthRangeShallow),
      depthDeep: toNumberOrNull(row.DepthRangeDeep),
      length: toNumberOrNull(row.Length),
    });
    relevantSpecCodes.add(`${server}:${row.SpecCode}`);
    indexed += 1;
  }
  return indexed;
}

/** Load a server's comnames table into a `${server}:${specCode}` → names map. */
async function loadComnames(
  server: Server,
  relevantSpecCodes: Set<string>,
  namesByKey: Map<string, CommonNames>,
): Promise<void> {
  const url = `${DATA_BASE}/${SERVER_DIRS[server]}/parquet/comnames.parquet`;
  const rows = await readParquet<FbComnameRaw>(url, [
    'SpecCode',
    'ComName',
    'Language',
    'PreferredName',
    'NameType',
  ]);

  for (const row of rows) {
    if (!row.ComName || !row.Language || row.SpecCode == null) continue;
    const lang = LANGUAGES[row.Language];
    if (!lang) continue;
    const key = `${server}:${row.SpecCode}`;
    if (!relevantSpecCodes.has(key)) continue;

    const existing = namesByKey.get(key) ?? {};
    // Prefer the flagged PreferredName; otherwise keep the first vernacular seen.
    if (!existing[lang] || row.PreferredName === 1) {
      existing[lang] = row.ComName.trim();
      namesByKey.set(key, existing);
    }
  }
}

export async function runFishbaseEtl(): Promise<void> {
  const startedAt = Date.now();
  logger.info('Starting FishBase/SeaLifeBase species-enrichment ETL');

  const supabase = getSupabase();
  const servers = selectedServers();

  // 1. Build in-memory lookups from the Parquet snapshots (downloaded once).
  const speciesByName = new Map<string, FishBaseEntry>();
  const relevantSpecCodes = new Set<string>();
  for (const server of servers) {
    const n = await loadServer(server, speciesByName, relevantSpecCodes);
    logger.info(`FishBase ${server}: indexed ${n} species`);
  }

  const namesByKey = new Map<string, CommonNames>();
  for (const server of servers) {
    await loadComnames(server, relevantSpecCodes, namesByKey);
  }
  logger.info(
    `FishBase lookups ready: ${speciesByName.size} species, ${namesByKey.size} common-name sets`,
  );

  // 2. Cursor-paginate our species and enrich matches. Each lookup is an
  //    in-memory map hit (no network), so processing the whole catalog is
  //    cheap; only the upsert writes cost anything.
  const maxSpecies = Number(process.env.FISHBASE_MAX ?? 100000);
  const batchSize = Number(process.env.FISHBASE_BATCH_SIZE ?? 1000);

  const errors: string[] = [];
  let processed = 0;
  let matched = 0;
  let upserted = 0;
  let cursor = '00000000-0000-0000-0000-000000000000';

  while (processed < maxSpecies) {
    const remaining = Math.min(batchSize, maxSpecies - processed);
    const { data: species, error } = await supabase
      .from('species')
      .select(
        'id, scientific_name, common_name, common_name_it, common_name_es, min_depth_m, max_depth_m, typical_length_cm, metadata',
      )
      .gt('id', cursor)
      .order('id', { ascending: true })
      .limit(remaining);

    if (error) throw new Error(`Failed to load species: ${error.message}`);
    if (!species || species.length === 0) break;

    const updates: Record<string, unknown>[] = [];

    for (const sp of species) {
      cursor = sp.id as string;
      processed += 1;

      const normalized = normalizeName(String(sp.scientific_name));
      let entry = speciesByName.get(normalized);
      // Fallback: strip anything past the binomial (subspecies / authorship).
      if (!entry) {
        const tokens = normalized.split(' ');
        if (tokens.length > 2) entry = speciesByName.get(`${tokens[0]} ${tokens[1]}`);
      }
      if (!entry) continue;
      matched += 1;

      const names = namesByKey.get(`${entry.server}:${entry.specCode}`) ?? {};
      const update = buildUpdate(sp, entry, names);
      if (update) updates.push(update);
    }

    if (updates.length > 0) {
      const result = await upsertBatch('species', updates, 'scientific_name');
      upserted += result.upserted;
      errors.push(...result.errors);
    }

    logger.info(`FishBase progress: ${processed} processed, ${matched} matched, ${upserted} enriched`);

    if (species.length < remaining) break;
  }

  logJobSummary('fishbase', {
    processed,
    upserted,
    skipped: processed - matched,
    errors,
  });

  logger.info(`FishBase ETL finished in ${Date.now() - startedAt}ms`);
}

/**
 * Build a partial upsert payload for one species, or null if FishBase adds
 * nothing new. Name/depth/length columns are fill-when-empty (curated + WoRMS
 * values win); metadata always records the FishBase provenance.
 */
function buildUpdate(
  sp: Record<string, unknown>,
  entry: FishBaseEntry,
  names: CommonNames,
): Record<string, unknown> | null {
  const enName = (sp.common_name as string | null) ?? entry.fbName ?? names.en ?? null;
  const itName = (sp.common_name_it as string | null) ?? names.it ?? null;
  const esName = (sp.common_name_es as string | null) ?? names.es ?? null;
  const minDepth = (sp.min_depth_m as number | null) ?? entry.depthShallow;
  const maxDepth = (sp.max_depth_m as number | null) ?? entry.depthDeep;
  const length = (sp.typical_length_cm as number | null) ?? entry.length;

  const existingMeta = (sp.metadata as Record<string, unknown> | null) ?? {};
  const fishbaseMeta = {
    server: entry.server === 'fb' ? 'fishbase' : 'sealifebase',
    spec_code: entry.specCode,
    habitat: entry.habitat,
    environment: entry.environment,
    depth_shallow_m: entry.depthShallow,
    depth_deep_m: entry.depthDeep,
    max_length_cm: entry.length,
  };

  const changed =
    enName !== (sp.common_name ?? null) ||
    itName !== (sp.common_name_it ?? null) ||
    esName !== (sp.common_name_es ?? null) ||
    minDepth !== (sp.min_depth_m ?? null) ||
    maxDepth !== (sp.max_depth_m ?? null) ||
    length !== (sp.typical_length_cm ?? null) ||
    JSON.stringify((existingMeta as Record<string, unknown>).fishbase) !==
      JSON.stringify(fishbaseMeta);

  if (!changed) return null;

  return {
    scientific_name: sp.scientific_name,
    common_name: enName,
    common_name_it: itName,
    common_name_es: esName,
    min_depth_m: minDepth,
    max_depth_m: maxDepth,
    typical_length_cm: length,
    metadata: {
      ...existingMeta,
      habitat: entry.habitat ?? (existingMeta as Record<string, unknown>).habitat ?? null,
      fishbase: fishbaseMeta,
    },
  };
}

if (isMainModule(import.meta.url)) {
  runFishbaseEtl().catch((err) => {
    logger.error('FishBase ETL failed', {
      error: err instanceof Error ? err.message : String(err),
    });
    process.exit(1);
  });
}
