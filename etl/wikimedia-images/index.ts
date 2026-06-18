import 'dotenv/config';
import { logger, logJobSummary } from '../shared/logger';
import { RateLimiter } from '../shared/rate-limiter';
import { getSupabase } from '../shared/supabase';
import { isMainModule } from '../shared/cli';

const COMMONS_API = process.env.COMMONS_API_URL ?? 'https://commons.wikimedia.org/w/api.php';
const BATCH_SIZE = Number(process.env.WIKIMEDIA_BATCH_SIZE ?? 100);
const MAX_SPECIES = Number(process.env.WIKIMEDIA_MAX_SPECIES ?? 500);
const USER_AGENT = process.env.WIKIMEDIA_USER_AGENT ?? 'OceanLog/1.0 (https://oceanlog.app; contact@oceanlog.app)';

const limiter = new RateLimiter({ minIntervalMs: 200 });

// Whitelist of acceptable CC licenses. Anything not in this set is
// rejected — even if Wikimedia returns a URL. This is the licensing
// guardrail for the data moat: we only redistribute CC0/CC-BY images.
const ALLOWED_LICENSES = new Set<string>([
  'CC0',
  'CC0-1.0',
  'PD',
  'PD-OLD',
  'PD-OLD-70',
  'PD-1923',
  'PD-US',
  'PD-US-URAA',
  'CC-BY-1.0',
  'CC-BY-2.0',
  'CC-BY-2.5',
  'CC-BY-3.0',
  'CC-BY-4.0',
  'CC-BY-SA-1.0',
  'CC-BY-SA-2.0',
  'CC-BY-SA-2.5',
  'CC-BY-SA-3.0',
  'CC-BY-SA-4.0',
]);

interface SearchResponse {
  query?: {
    search?: Array<{ title: string }>;
  };
}

interface ImageInfoResponse {
  query?: {
    pages?: Record<
      string,
      {
        imageinfo?: Array<{
          url: string;
          width?: number;
          height?: number;
          extmetadata?: Record<string, { value?: string }>;
        }>;
      }
    >;
  };
}

interface ParsedImage {
  url: string;
  width: number;
  height: number;
  license: string;
  attribution: string;
}

async function searchCommons(query: string): Promise<string[]> {
  const params = new URLSearchParams({
    action: 'query',
    list: 'search',
    srsearch: query,
    srnamespace: '6', // File namespace
    srlimit: '5',
    format: 'json',
  });
  const url = `${COMMONS_API}?${params.toString()}`;
  const data = await limiter.fetchJson<SearchResponse>(url, {
    headers: { 'User-Agent': USER_AGENT },
  });
  return (data.query?.search ?? []).map((s) => s.title);
}

async function fetchImageInfo(fileTitle: string): Promise<ParsedImage | null> {
  const params = new URLSearchParams({
    action: 'query',
    prop: 'imageinfo',
    iiprop: 'url|extmetadata|size',
    titles: fileTitle,
    format: 'json',
  });
  const url = `${COMMONS_API}?${params.toString()}`;
  const data = await limiter.fetchJson<ImageInfoResponse>(url, {
    headers: { 'User-Agent': USER_AGENT },
  });
  const pages = data.query?.pages ?? {};
  const firstKey = Object.keys(pages)[0];
  if (!firstKey) return null;
  const info = pages[firstKey].imageinfo?.[0];
  if (!info?.url) return null;

  const licenseShort =
    info.extmetadata?.['LicenseShortName']?.value ??
    info.extmetadata?.['licensename']?.value ??
    '';
  const artist =
    info.extmetadata?.['Artist']?.value ??
    info.extmetadata?.['author']?.value ??
    '';

  return {
    url: info.url,
    width: info.width ?? 0,
    height: info.height ?? 0,
    license: licenseShort.trim(),
    attribution: stripHtml(artist).trim(),
  };
}

function stripHtml(s: string): string {
  return s.replace(/<[^>]+>/g, '').trim();
}

function isAcceptable(parsed: ParsedImage): boolean {
  if (parsed.width < 600) return false;
  if (parsed.height < 400) return false;
  return ALLOWED_LICENSES.has(parsed.license);
}

export async function runWikimediaImagesEtl(): Promise<void> {
  const startedAt = Date.now();
  logger.info('Starting Wikimedia Commons image backfill');

  const supabase = getSupabase();
  const { data: species, error } = await supabase
    .from('species')
    .select('id, scientific_name, common_name, common_name_it, common_name_es, image_url')
    .is('image_url', null)
    .limit(MAX_SPECIES);

  if (error) throw new Error(`Failed to load species: ${error.message}`);

  let updated = 0;
  let skipped = 0;
  const errors: string[] = [];

  for (const row of species ?? []) {
    const sci = row.scientific_name as string;
    // Build a search query that's likely to match marine-life photos.
    const query = `${sci} marine fish underwater photo`;
    try {
      const titles = await searchCommons(query);
      if (titles.length === 0) {
        skipped += 1;
        continue;
      }
      // Try the first 3 candidates. We want the largest image with an
      // acceptable license; we sort by (width * height) descending.
      const candidates: ParsedImage[] = [];
      for (const t of titles.slice(0, 3)) {
        const info = await fetchImageInfo(t);
        if (info && isAcceptable(info)) candidates.push(info);
      }
      if (candidates.length === 0) {
        skipped += 1;
        continue;
      }
      candidates.sort((a, b) => b.width * b.height - a.width * a.height);
      const best = candidates[0];

      const { error: updateError } = await supabase
        .from('species')
        .update({
          image_url: best.url,
          image_license: best.license,
          image_source: 'wikimedia_commons',
          image_attribution: best.attribution,
        })
        .eq('id', row.id);

      if (updateError) {
        errors.push(`${sci}: ${updateError.message}`);
        skipped += 1;
      } else {
        updated += 1;
      }
    } catch (err) {
      errors.push(`${sci}: ${err instanceof Error ? err.message : String(err)}`);
      skipped += 1;
    }
    if ((updated + skipped) % BATCH_SIZE === 0) {
      logger.info(
        `Wikimedia progress: ${updated} updated, ${skipped} skipped`,
      );
    }
  }

  logJobSummary('wikimedia-images', {
    processed: species?.length ?? 0,
    upserted: updated,
    skipped,
    errors,
  });
  logger.info(`Wikimedia Commons ETL finished in ${Date.now() - startedAt}ms`);
}

if (isMainModule(import.meta.url)) {
  runWikimediaImagesEtl().catch((err) => {
    logger.error('Wikimedia Commons ETL failed', {
      error: err instanceof Error ? err.message : String(err),
    });
    process.exit(1);
  });
}
