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

type GeoCircle = { type: 'Point'; coordinates: [number, number]; radiusKm: number };

interface RegionConfig {
  customGeolocation: GeoCircle;
  searches: string[];
}

const REGION_CONFIGS: Record<string, RegionConfig> = {
  europe: {
    customGeolocation: { type: 'Point', coordinates: [7.2684, 43.7009], radiusKm: 150 },
    searches: ['scuba diving center', 'PADI dive shop', 'diving school', 'dive shop'],
  },
  asia: {
    customGeolocation: { type: 'Point', coordinates: [115.092, -8.3405], radiusKm: 150 },
    searches: ['scuba diving center', 'PADI dive shop', 'diving school', 'dive shop'],
  },
  americas: {
    customGeolocation: { type: 'Point', coordinates: [-86.8515, 21.1619], radiusKm: 150 },
    searches: ['scuba diving center', 'PADI dive shop', 'diving school', 'dive shop'],
  },
  africa: {
    customGeolocation: { type: 'Point', coordinates: [33.8116, 27.2579], radiusKm: 150 },
    searches: ['scuba diving center', 'PADI dive shop', 'diving school', 'dive shop'],
  },
  oceania: {
    customGeolocation: { type: 'Point', coordinates: [145.771, -16.9203], radiusKm: 150 },
    searches: ['scuba diving center', 'PADI dive shop', 'diving school', 'dive shop'],
  },
};

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

interface ActorInput {
  searchStringsArray: string[];
  maxCrawledPlacesPerSearch: number;
  language: string;
  skipClosedPlaces: boolean;
  locationQuery?: string;
  customGeolocation?: GeoCircle;
  scrapePlaceDetailPage: boolean;
  includeWebResults: boolean;
  scrapeDirectories: boolean;
  maxReviews: number;
  maxImages: number;
  scrapeContacts: boolean;
  scrapeReviewsPersonalData: boolean;
  scrapeSocialMediaProfiles: Record<string, boolean>;
}

async function startActorRun(
  searches: string[],
  geo: { customGeolocation: GeoCircle } | { locationQuery: string },
): Promise<string> {
  const maxPlaces = Number(process.env.APIFY_MAX_PLACES_PER_SEARCH ?? 20);
  const maxCostUsd = process.env.APIFY_MAX_COST_PER_REGION_USD ?? '0.9';
  const url = `${APIFY_BASE}/acts/${ACTOR_ID}/runs?token=${APIFY_TOKEN}&maxTotalChargeUsd=${maxCostUsd}`;

  const input: ActorInput = {
    searchStringsArray: searches,
    maxCrawledPlacesPerSearch: maxPlaces,
    language: 'en',
    skipClosedPlaces: true,
    ...geo,
    scrapePlaceDetailPage: false,
    includeWebResults: false,
    scrapeDirectories: false,
    maxReviews: 0,
    maxImages: 0,
    scrapeContacts: false,
    scrapeReviewsPersonalData: false,
    scrapeSocialMediaProfiles: {
      facebooks: false,
      instagrams: false,
      youtubes: false,
      tiktoks: false,
      twitters: false,
    },
  };

  const response = await limiter.fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(input),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Apify run start failed: HTTP ${response.status} ${body.slice(0, 200)}`);
  }

  const data = (await response.json()) as { data: { id: string } };
  return data.data.id;
}

async function waitForRun(runId: string): Promise<string | null> {
  const maxWaitMs = Number(process.env.APIFY_RUN_TIMEOUT_MS ?? 600_000);
  const started = Date.now();

  while (Date.now() - started < maxWaitMs) {
    const url = `${APIFY_BASE}/actor-runs/${runId}?token=${APIFY_TOKEN}`;
    const data = await limiter.fetchJson<{
      data: { status: string; defaultDatasetId: string; statusMessage?: string };
    }>(url);
    const { status, defaultDatasetId, statusMessage } = data.data;
    if (status === 'SUCCEEDED') return defaultDatasetId;
    if (status === 'ABORTED') {
      logger.warn(`Apify run ${runId} aborted (likely cost cap)`, { statusMessage });
      return defaultDatasetId;
    }
    if (status === 'FAILED' || status === 'TIMED-OUT') {
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

function isDiveRelated(categoryName?: string): boolean {
  if (!categoryName) return false;
  const lower = categoryName.toLowerCase();
  return lower.includes('dive') || lower.includes('scuba');
}

function mapPlace(place: ApifyPlace, index: number, seenSlugs: Set<string>): DiveSiteRow | null {
  const name = place.title?.trim();
  const lat = place.location?.lat;
  const lng = place.location?.lng;
  if (!name || lat == null || lng == null) return null;
  if (!isDiveRelated(place.categoryName)) return null;

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

async function runSingleRegion(
  label: string,
  geo: { customGeolocation: GeoCircle } | { locationQuery: string },
  searches: string[],
): Promise<{ processed: number; upserted: number; skipped: number; errors: string[] }> {
  logger.info(`Apify run for region: ${label}`, { ...geo, searches: searches.length });
  const runId = await startActorRun(searches, geo);
  logger.info(`Apify run started: ${runId}`);
  const datasetId = await waitForRun(runId);
  if (!datasetId) { logger.warn(`Region "${label}" aborted before producing data`); return { processed: 0, upserted: 0, skipped: 0, errors: [] }; }
  const places = await fetchDatasetItems(datasetId);
  logger.info(`Region "${label}" returned ${places.length} places`);
  const seenSlugs = new Set<string>();
  const siteRows: DiveSiteRow[] = [];
  let rejected = 0;
  places.forEach((place, index) => {
    if (!isDiveRelated(place.categoryName)) { rejected++; return; }
    const row = mapPlace(place, index, seenSlugs);
    if (row) siteRows.push(row);
  });
  if (rejected > 0) logger.info(`Region "${label}": ${rejected} places filtered out (not dive-related)`);
  const result = await upsertBatch(
    'dive_sites',
    siteRows as unknown as Record<string, unknown>[],
    'slug',
  );
  logger.info(`Region "${label}": ${result.upserted} upserted, ${result.skipped} skipped`);
  return { processed: places.length, upserted: result.upserted, skipped: result.skipped, errors: result.errors };
}

export async function runApifyGoogleMapsEtl(): Promise<void> {
  const startedAt = Date.now();
  if (!APIFY_TOKEN) {
    logger.warn(
      'APIFY_TOKEN not set — skipping Google Maps ETL. Get a free token at https://apify.com',
    );
    return;
  }

  const regionRaw = process.env.APIFY_SEARCH_REGION;
  if (regionRaw) {
    const regions = regionRaw.split('|').map((s) => s.trim().toLowerCase()).filter(Boolean);
    if (regions.length === 0) {
      logger.warn('APIFY_SEARCH_REGION is set but empty — skipping');
      return;
    }
    const invalid = regions.filter((r) => !REGION_CONFIGS[r]);
    if (invalid.length > 0) {
      logger.warn(`Unknown region(s) in APIFY_SEARCH_REGION: ${invalid.join(', ')}`, {
        known: Object.keys(REGION_CONFIGS),
      });
      return;
    }
    let totalProcessed = 0;
    let totalUpserted = 0;
    let totalSkipped = 0;
    const totalErrors: string[] = [];
    for (const region of regions) {
      const config = REGION_CONFIGS[region];
      const result = await runSingleRegion(region, { customGeolocation: config.customGeolocation }, config.searches);
      totalProcessed += result.processed;
      totalUpserted += result.upserted;
      totalSkipped += result.skipped;
      totalErrors.push(...result.errors);
    }
    logJobSummary('apify-google-maps', {
      processed: totalProcessed,
      upserted: totalUpserted,
      skipped: totalSkipped,
      errors: totalErrors,
    });
    logger.info(`Apify Google Maps ETL finished in ${Date.now() - startedAt}ms`);
    return;
  }

  const searches = parseSearchList();
  const locationQuery = process.env.APIFY_SEARCH_LOCATION ?? '';
  logger.info('Starting Apify Google Maps dive site ETL (legacy)', { searches: searches.length, locationQuery });
  const result = await runSingleRegion('default', { locationQuery }, searches);
  logJobSummary('apify-google-maps', result);
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
