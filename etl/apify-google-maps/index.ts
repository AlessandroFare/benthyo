import 'dotenv/config';
import { logger, logJobSummary } from '../shared/logger';
import { RateLimiter } from '../shared/rate-limiter';
import {
  geographyPoint,
  normalizeAccessType,
  normalizeCountryCode,
  normalizeDifficulty,
  normalizeSiteType,
  slugify,
  uniqueSlug,
  type DiveSiteRow,
} from '../shared/dive-site-utils';
import { upsertBatch } from '../shared/supabase';
import { isMainModule } from '../shared/cli';

const APIFY_TOKEN = process.env.APIFY_TOKEN;
const ACTOR_ID = process.env.APIFY_GOOGLE_MAPS_ACTOR ?? 'compass~crawler-google-places';
const APIFY_BASE = 'https://api.apify.com/v2';

/** Regional Google Maps search queries for dive sites. */
const DEFAULT_SEARCHES = [
  'scuba diving sites Norway',
  'scuba diving sites Sweden',
  'scuba diving sites Mediterranean',
  'scuba diving sites Red Sea',
  'scuba diving sites Caribbean',
  'scuba diving sites Indonesia',
  'scuba diving sites Philippines',
  'scuba diving sites Australia',
  'scuba diving sites Hawaii',
  'scuba diving sites Mexico',
];

interface ApifyPlace {
  title?: string;
  categoryName?: string;
  address?: string;
  location?: { lat?: number; lng?: number };
  description?: string;
  url?: string;
  countryCode?: string;
}

const limiter = new RateLimiter({ minIntervalMs: 1000 });

function parseSearchList(): string[] {
  const raw = process.env.APIFY_GOOGLE_SEARCHES;
  if (!raw) return DEFAULT_SEARCHES;
  return raw.split('|').map((s) => s.trim()).filter(Boolean);
}

async function startActorRun(searches: string[]): Promise<string> {
  const maxPlaces = Number(process.env.APIFY_MAX_PLACES_PER_SEARCH ?? 30);
  const url = `${APIFY_BASE}/acts/${ACTOR_ID}/runs?token=${APIFY_TOKEN}`;

  const response = await limiter.fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      searchStringsArray: searches,
      maxCrawledPlacesPerSearch: maxPlaces,
      language: 'en',
      skipClosedPlaces: true,
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Apify run start failed: HTTP ${response.status} ${body.slice(0, 200)}`);
  }

  const data = (await response.json()) as { data: { id: string } };
  return data.data.id;
}

async function waitForRun(runId: string): Promise<string> {
  const maxWaitMs = Number(process.env.APIFY_RUN_TIMEOUT_MS ?? 600_000);
  const started = Date.now();

  while (Date.now() - started < maxWaitMs) {
    const url = `${APIFY_BASE}/actor-runs/${runId}?token=${APIFY_TOKEN}`;
    const data = await limiter.fetchJson<{ data: { status: string; defaultDatasetId: string } }>(
      url,
    );
    const status = data.data.status;
    if (status === 'SUCCEEDED') return data.data.defaultDatasetId;
    if (status === 'FAILED' || status === 'ABORTED' || status === 'TIMED-OUT') {
      throw new Error(`Apify run ${runId} ended with status ${status}`);
    }
    await sleep(5000);
  }

  throw new Error(`Apify run ${runId} timed out after ${maxWaitMs}ms`);
}

async function fetchDatasetItems(datasetId: string): Promise<ApifyPlace[]> {
  const url = `${APIFY_BASE}/datasets/${datasetId}/items?token=${APIFY_TOKEN}&clean=true&format=json`;
  return limiter.fetchJson<ApifyPlace[]>(url);
}

function mapPlace(place: ApifyPlace, index: number, seenSlugs: Set<string>): DiveSiteRow | null {
  const name = place.title?.trim();
  const lat = place.location?.lat;
  const lng = place.location?.lng;
  if (!name || lat == null || lng == null) return null;

  const hint = `${place.description ?? ''} ${place.categoryName ?? ''} ${name}`;
  const baseSlug = slugify(name);
  const slug = uniqueSlug(`gmaps-${baseSlug}`, String(index), seenSlugs);

  return {
    name,
    slug,
    description: place.description ?? null,
    location: geographyPoint(lng, lat),
    country_code: normalizeCountryCode(place.countryCode),
    region: place.address ?? null,
    depth_min: 0,
    depth_max: 30,
    difficulty: normalizeDifficulty(undefined, hint),
    site_type: normalizeSiteType(undefined),
    access_type: normalizeAccessType(undefined, hint),
    verified: false,
    metadata: {
      source: 'apify_google_maps',
      google_maps_url: place.url,
      category: place.categoryName,
      address: place.address,
    },
  };
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function runApifyGoogleMapsEtl(): Promise<void> {
  const startedAt = Date.now();

  if (!APIFY_TOKEN) {
    logger.warn(
      'APIFY_TOKEN not set — skipping Google Maps ETL. Get a free token at https://apify.com',
    );
    return;
  }

  const searches = parseSearchList();
  logger.info('Starting Apify Google Maps dive site ETL', { searches: searches.length });

  const runId = await startActorRun(searches);
  logger.info(`Apify run started: ${runId}`);

  const datasetId = await waitForRun(runId);
  const places = await fetchDatasetItems(datasetId);
  logger.info(`Apify returned ${places.length} places`);

  const seenSlugs = new Set<string>();
  const siteRows: DiveSiteRow[] = [];

  places.forEach((place, index) => {
    const row = mapPlace(place, index, seenSlugs);
    if (row) siteRows.push(row);
  });

  const result = await upsertBatch(
    'dive_sites',
    siteRows as unknown as Record<string, unknown>[],
    'slug',
  );

  logJobSummary('apify-google-maps', {
    processed: places.length,
    upserted: result.upserted,
    skipped: result.skipped,
    errors: result.errors,
  });

  logger.info(`Apify Google Maps ETL finished in ${Date.now() - startedAt}ms`);
}

if (isMainModule(import.meta.url)) {
  runApifyGoogleMapsEtl().catch((err) => {
    logger.error('Apify Google Maps ETL failed', {
      error: err instanceof Error ? err.message : String(err),
    });
    process.exit(1);
  });
}
