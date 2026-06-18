import 'dotenv/config';
import { logger, logJobSummary } from '../shared/logger';
import { RateLimiter } from '../shared/rate-limiter';
import { getSupabase } from '../shared/supabase';
import { isMainModule } from '../shared/cli';

const INAT_API = process.env.INAT_API_BASE ?? 'https://api.inaturalist.org/v1';
const BATCH_SIZE = Number(process.env.INAT_IMAGE_BATCH_SIZE ?? 50);
const MAX_SPECIES = Number(process.env.INAT_IMAGE_MAX_SPECIES ?? 500);

const limiter = new RateLimiter({ minIntervalMs: 1500 });

interface InatTaxon {
  id: number;
  default_photo?: {
    medium_url?: string;
    square_url?: string;
  };
}

interface InatTaxaResponse {
  results: InatTaxon[];
}

async function fetchTaxonPhoto(taxonId: number): Promise<string | null> {
  const url = `${INAT_API}/taxa/${taxonId}`;
  const data = await limiter.fetchJson<InatTaxaResponse>(url);
  const taxon = data.results?.[0];
  return taxon?.default_photo?.medium_url ?? taxon?.default_photo?.square_url ?? null;
}

export async function runInaturalistImageEtl(): Promise<void> {
  const startedAt = Date.now();
  logger.info('Starting iNaturalist species image backfill');

  const supabase = getSupabase();
  const { data: species, error } = await supabase
    .from('species')
    .select('id, scientific_name, inat_taxon_id, image_url')
    .is('image_url', null)
    .not('inat_taxon_id', 'is', null)
    .limit(MAX_SPECIES);

  if (error) {
    throw new Error(`Failed to load species: ${error.message}`);
  }

  let updated = 0;
  let skipped = 0;
  const errors: string[] = [];

  for (const row of species ?? []) {
    const taxonId = row.inat_taxon_id as number;
    try {
      const imageUrl = await fetchTaxonPhoto(taxonId);
      if (!imageUrl) {
        skipped += 1;
        continue;
      }

      const { error: updateError } = await supabase
        .from('species')
        .update({ image_url: imageUrl })
        .eq('id', row.id);

      if (updateError) {
        errors.push(`${row.scientific_name}: ${updateError.message}`);
        skipped += 1;
      } else {
        updated += 1;
      }
    } catch (err) {
      errors.push(
        `${row.scientific_name}: ${err instanceof Error ? err.message : String(err)}`,
      );
      skipped += 1;
    }

    if ((updated + skipped) % BATCH_SIZE === 0) {
      logger.info(`iNaturalist image progress: ${updated} updated, ${skipped} skipped`);
    }
  }

  logJobSummary('inaturalist-images', {
    processed: species?.length ?? 0,
    upserted: updated,
    skipped,
    errors,
  });

  logger.info(`iNaturalist image ETL finished in ${Date.now() - startedAt}ms`);
}

if (isMainModule(import.meta.url)) {
  runInaturalistImageEtl().catch((err) => {
    logger.error('iNaturalist image ETL failed', {
      error: err instanceof Error ? err.message : String(err),
    });
    process.exit(1);
  });
}
