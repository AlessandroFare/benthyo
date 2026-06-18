import 'dotenv/config';
import { logger, logJobSummary } from '../shared/logger';
import { RateLimiter } from '../shared/rate-limiter';
import { getSupabase, upsertBatch } from '../shared/supabase';
import { isMainModule } from '../shared/cli';

const INAT_API = process.env.INAT_API_BASE ?? 'https://api.inaturalist.org/v1';
const BATCH_SIZE = Number(process.env.INAT_TAXON_BATCH_SIZE ?? 100);
const MAX_SPECIES = Number(process.env.INAT_TAXON_MAX_SPECIES ?? 1000);
const MIN_SCORE = Number(process.env.INAT_TAXON_MIN_SCORE ?? 90);

const limiter = new RateLimiter({ minIntervalMs: 1500 });

interface InatTaxon {
  id: number;
  name: string;
  rank: string;
  is_active: boolean;
  matched_term: string;
}

interface InatTaxaResponse {
  total_results?: number;
  results: InatTaxon[];
}

interface Match {
  inat_taxon_id: number;
  scientific_name: string;
  score: number;
}

async function lookupTaxa(scientificName: string): Promise<Match | null> {
  const url = `${INAT_API}/taxa?q=${encodeURIComponent(scientificName)}&rank=species&is_active=true&per_page=5`;
  try {
    const data = await limiter.fetchJson<InatTaxaResponse>(url);
    if (!data.results?.length) return null;
    // Pick the highest-scoring exact-name match. iNaturalist returns a
    // `matched_term`; we want a match where the canonical name equals
    // our scientific name (case-insensitive).
    const want = scientificName.toLowerCase().trim();
    let bestExact: InatTaxon | null = null;
    let bestScore = 0;
    for (const r of data.results) {
      if (r.name.toLowerCase().trim() === want) {
        if (!bestExact || r.id === r.id) bestExact = r;
      }
      // iNaturalist doesn't return a score in /v1/taxa; estimate
      // confidence by ranking.
      bestScore = Math.max(bestScore, data.results.indexOf(r) === 0 ? 100 : 90);
    }
    if (!bestExact) return null;
    if (bestScore < MIN_SCORE) return null;
    return {
      inat_taxon_id: bestExact.id,
      scientific_name: bestExact.name,
      score: bestScore,
    };
  } catch {
    return null;
  }
}

export async function runInatTaxonLookupEtl(): Promise<void> {
  const startedAt = Date.now();
  logger.info('Starting iNaturalist taxon lookup (resolve inat_taxon_id)');

  const supabase = getSupabase();
  const { data: species, error } = await supabase
    .from('species')
    .select('id, scientific_name, inat_taxon_id')
    .is('inat_taxon_id', null)
    .not('scientific_name', 'is', null)
    .limit(MAX_SPECIES);

  if (error) throw new Error(`Failed to load species: ${error.message}`);

  let updated = 0;
  let skipped = 0;
  const errors: string[] = [];

  for (const row of species ?? []) {
    const scientificName = row.scientific_name as string;
    try {
      const match = await lookupTaxa(scientificName);
      if (!match) {
        skipped += 1;
        continue;
      }
      const { error: updateError } = await supabase
        .from('species')
        .update({ inat_taxon_id: match.inat_taxon_id })
        .eq('id', row.id);
      if (updateError) {
        errors.push(`${scientificName}: ${updateError.message}`);
        skipped += 1;
      } else {
        updated += 1;
      }
    } catch (err) {
      errors.push(
        `${scientificName}: ${err instanceof Error ? err.message : String(err)}`,
      );
      skipped += 1;
    }
    if ((updated + skipped) % BATCH_SIZE === 0) {
      logger.info(
        `iNaturalist taxon lookup progress: ${updated} updated, ${skipped} skipped`,
      );
    }
  }

  logJobSummary('inat-taxon-lookup', {
    processed: species?.length ?? 0,
    upserted: updated,
    skipped,
    errors,
  });

  logger.info(`iNaturalist taxon lookup ETL finished in ${Date.now() - startedAt}ms`);
}

if (isMainModule(import.meta.url)) {
  runInatTaxonLookupEtl().catch((err) => {
    logger.error('iNaturalist taxon lookup ETL failed', {
      error: err instanceof Error ? err.message : String(err),
    });
    process.exit(1);
  });
}

// Also export the upsert helper so wikimedia-images.ts can re-use the
// species table writes. The intent: keep the data layer thin.
export { upsertBatch };
