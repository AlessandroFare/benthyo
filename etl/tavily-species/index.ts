import 'dotenv/config';
import { logger, logJobSummary } from '../shared/logger';
import { RateLimiter } from '../shared/rate-limiter';
import { getSupabase } from '../shared/supabase';
import { isMainModule } from '../shared/cli';

const TAVILY_API = process.env.TAVILY_API_URL ?? 'https://api.tavily.com/search';
const TAVILY_API_KEY = process.env.TAVILY_API_KEY;
const MAX_SPECIES = Number(process.env.TAVILY_SPECIES_MAX ?? 100);

const limiter = new RateLimiter({ minIntervalMs: 1000 });

interface TavilyResult {
  title?: string;
  url?: string;
  content?: string;
  images?: string[];
}

interface TavilyResponse {
  results?: TavilyResult[];
  images?: string[];
}

async function searchSpeciesImage(scientificName: string): Promise<string | null> {
  const response = await limiter.fetch(TAVILY_API, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      api_key: TAVILY_API_KEY,
      query: `${scientificName} marine species underwater photo`,
      search_depth: 'basic',
      include_images: true,
      max_results: 5,
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Tavily HTTP ${response.status}: ${body.slice(0, 200)}`);
  }

  const data = (await response.json()) as TavilyResponse;
  const topLevelImage = data.images?.find(isImageUrl);
  if (topLevelImage) return topLevelImage;

  for (const result of data.results ?? []) {
    const image = result.images?.find(isImageUrl);
    if (image) return image;
  }

  return null;
}

function isImageUrl(url: string | undefined): url is string {
  if (!url) return false;
  return /\.(jpg|jpeg|png|webp)(\?|$)/i.test(url) || url.includes('inaturalist') || url.includes('wikimedia');
}

export async function runTavilySpeciesEtl(): Promise<void> {
  const startedAt = Date.now();

  if (!TAVILY_API_KEY) {
    logger.warn(
      'TAVILY_API_KEY not set — skipping Tavily species image ETL. Get a key at https://www.tavily.com',
    );
    return;
  }

  logger.info('Starting Tavily species image enrichment');

  const supabase = getSupabase();
  const { data: species, error } = await supabase
    .from('species')
    .select('id, scientific_name, image_url')
    .is('image_url', null)
    .limit(MAX_SPECIES);

  if (error) {
    throw new Error(`Failed to load species: ${error.message}`);
  }

  let updated = 0;
  let skipped = 0;
  const errors: string[] = [];

  for (const row of species ?? []) {
    try {
      const imageUrl = await searchSpeciesImage(row.scientific_name as string);
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
  }

  logJobSummary('tavily-species', {
    processed: species?.length ?? 0,
    upserted: updated,
    skipped,
    errors,
  });

  logger.info(`Tavily species ETL finished in ${Date.now() - startedAt}ms`);
}

if (isMainModule(import.meta.url)) {
  runTavilySpeciesEtl().catch((err) => {
    logger.error('Tavily species ETL failed', {
      error: err instanceof Error ? err.message : String(err),
    });
    process.exit(1);
  });
}
