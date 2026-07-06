import 'dotenv/config';
import { logger, logJobSummary } from '../shared/logger';
import { RateLimiter } from '../shared/rate-limiter';
import { getSupabase, upsertBatch } from '../shared/supabase';
import { isMainModule } from '../shared/cli';

const WORMS_API = 'https://www.marinespecies.org/rest';

interface WormsAphiaRecord {
  AphiaID: number;
  scientificname: string;
  valid_AphiaID?: number;
  valid_name?: string;
  kingdom?: string;
  phylum?: string;
  class?: string;
  order?: string;
  family?: string;
  genus?: string;
  status?: string;
}

interface WormsVernacular {
  vernacular: string;
  language_code?: string;
}

const limiter = new RateLimiter({ minIntervalMs: 150 });

async function searchByScientificName(name: string): Promise<WormsAphiaRecord | null> {
  const params = new URLSearchParams({ scientificname: name });
  const url = `${WORMS_API}/AphiaRecordsByName/${encodeURIComponent(name)}?${params}`;
  try {
    const results = await limiter.fetchJson<WormsAphiaRecord[]>(url);
    if (results.length === 0) return null;
    const accepted = results.find((r) => r.status === 'accepted');
    return accepted ?? results[0];
  } catch {
    return null;
  }
}

async function fetchVernaculars(aphiaId: number): Promise<WormsVernacular[]> {
  const url = `${WORMS_API}/AphiaRecordByAphiaID/${aphiaId}/vernaculars`;
  try {
    return await limiter.fetchJson<WormsVernacular[]>(url);
  } catch {
    return [];
  }
}

function pickVernacular(vernaculars: WormsVernacular[], lang: string): string | undefined {
  return vernaculars.find((v) => v.language_code?.toLowerCase() === lang)?.vernacular;
}

export async function runWormsEtl(): Promise<void> {
  const startedAt = Date.now();
  logger.info('Starting WoRMS species taxonomy ETL');

  const supabase = getSupabase();

  // Cap and batch size are configurable. WoRMS is polite-rate-limited, so the
  // default cap keeps a single nightly run bounded while still covering the
  // whole freshly-imported catalog over a couple of runs.
  const maxSpecies = Number(process.env.WORMS_MAX ?? 4000);
  const batchSize = Number(process.env.WORMS_BATCH_SIZE ?? 500);

  const errors: string[] = [];
  let processed = 0;
  let upserted = 0;
  let notFound = 0;

  // Cursor pagination by id. We advance past every row we look at (found or
  // not) so "not found on WoRMS" rows — which keep worms_id NULL — never cause
  // an infinite loop, unlike a fixed `.limit()` that would re-select them.
  let cursor = '00000000-0000-0000-0000-000000000000';

  while (processed < maxSpecies) {
    const remaining = Math.min(batchSize, maxSpecies - processed);
    const { data: species, error } = await supabase
      .from('species')
      .select('id, scientific_name, worms_id')
      .is('worms_id', null)
      .gt('id', cursor)
      .order('id', { ascending: true })
      .limit(remaining);

    if (error) throw new Error(`Failed to load species: ${error.message}`);
    if (!species || species.length === 0) break;

    const speciesRows: Record<string, unknown>[] = [];

    for (const sp of species) {
      cursor = sp.id as string;
      processed += 1;

      const record = await searchByScientificName(sp.scientific_name);
      if (!record) {
        notFound += 1;
        errors.push(`${sp.scientific_name}: not found on WoRMS`);
        continue;
      }

      let vernaculars: WormsVernacular[] = [];
      try {
        vernaculars = await fetchVernaculars(record.AphiaID);
      } catch {
        // non-fatal
      }

      speciesRows.push({
        scientific_name: sp.scientific_name,
        worms_id: record.AphiaID,
        kingdom: record.kingdom ?? 'Animalia',
        phylum: record.phylum,
        class_name: record.class,
        order_name: record.order,
        family: record.family,
        genus: record.genus,
        common_name: pickVernacular(vernaculars, 'eng') ?? pickVernacular(vernaculars, 'en'),
        common_name_it: pickVernacular(vernaculars, 'ita') ?? pickVernacular(vernaculars, 'it'),
        common_name_es: pickVernacular(vernaculars, 'spa') ?? pickVernacular(vernaculars, 'es'),
        metadata: {
          source: 'worms',
          valid_aphia_id: record.valid_AphiaID,
          valid_name: record.valid_name,
        },
      });
    }

    if (speciesRows.length > 0) {
      const result = await upsertBatch('species', speciesRows, 'scientific_name');
      upserted += result.upserted;
      errors.push(...result.errors);
    }

    logger.info(`WoRMS progress: ${processed} processed, ${upserted} enriched, ${notFound} not-found`);

    if (species.length < remaining) break; // reached the end of the null set
  }

  if (processed === 0) {
    logger.info('No species missing worms_id — nothing to do');
  }

  logJobSummary('worms', {
    processed,
    upserted,
    skipped: notFound,
    errors,
  });

  logger.info(`WoRMS ETL finished in ${Date.now() - startedAt}ms`);
}

if (isMainModule(import.meta.url)) {
  runWormsEtl().catch((err) => {
    logger.error('WoRMS ETL failed', { error: err instanceof Error ? err.message : String(err) });
    process.exit(1);
  });
}
