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

/**
 * Optional Dive Number embed API import.
 *
 * Dive Number (https://divenumber.com/free_dive_site_map) provides a free embed
 * widget for dive centers. Register a professional account, copy your API key
 * from the dashboard, and set DIVENUMBER_API_KEY.
 *
 * The data endpoint is configurable via DIVENUMBER_API_URL because Dive Number
 * serves region-scoped data per API key (not a global open bulk API).
 * OpenDiveMap (etl/opendivemap) is the recommended open global source.
 */
const API_KEY = process.env.DIVENUMBER_API_KEY;
const API_URL =
  process.env.DIVENUMBER_API_URL ?? 'https://divenumber.com/api/v1/sites';

const limiter = new RateLimiter({ minIntervalMs: 500 });

interface DiveNumberSite {
  id?: string | number;
  name?: string;
  title?: string;
  lat?: number;
  lng?: number;
  lon?: number;
  latitude?: number;
  longitude?: number;
  country?: string;
  country_code?: string;
  description?: string;
  max_depth?: number;
  depth?: number;
  type?: string;
  entry?: string;
}

interface DiveNumberResponse {
  sites?: DiveNumberSite[];
  data?: DiveNumberSite[];
}

function extractCoords(site: DiveNumberSite): { lat: number; lon: number } | null {
  const lat = site.lat ?? site.latitude;
  const lon = site.lng ?? site.lon ?? site.longitude;
  if (lat == null || lon == null) return null;
  return { lat, lon };
}

function mapSite(site: DiveNumberSite, index: number, seenSlugs: Set<string>): DiveSiteRow | null {
  const name = (site.name ?? site.title)?.trim();
  const coords = extractCoords(site);
  if (!name || !coords) return null;

  const hint = site.description ?? name;
  const baseSlug = slugify(name);
  const suffix = String(site.id ?? index);
  const slug = uniqueSlug(`dn-${baseSlug}`, suffix, seenSlugs);
  const depthMax = Number(site.max_depth ?? site.depth ?? 30);

  return {
    name,
    slug,
    description: site.description ?? null,
    location: geographyPoint(coords.lon, coords.lat),
    country_code: normalizeCountryCode(site.country_code ?? site.country),
    region: null,
    depth_min: 0,
    depth_max: Number.isFinite(depthMax) ? depthMax : 30,
    difficulty: normalizeDifficulty(undefined, hint),
    site_type: normalizeSiteType(site.type),
    access_type: normalizeAccessType(site.entry, hint),
    verified: false,
    metadata: {
      source: 'divenumber',
      divenumber_id: site.id ?? null,
    },
  };
}

export async function runDiveNumberEtl(): Promise<void> {
  const startedAt = Date.now();

  if (!API_KEY) {
    logger.warn(
      'DIVENUMBER_API_KEY not set — skipping Dive Number ETL. Register free at https://divenumber.com/free_dive_site_map',
    );
    return;
  }

  logger.info('Starting Dive Number dive site ETL');

  const url = `${API_URL}?apiKey=${encodeURIComponent(API_KEY)}`;
  const response = await limiter.fetch(url);

  if (!response.ok) {
    const body = await response.text();
    logger.warn('Dive Number API unavailable — set DIVENUMBER_API_URL if your dashboard uses a different endpoint', {
      status: response.status,
      sample: body.slice(0, 200),
    });
    return;
  }

  const payload = (await response.json()) as DiveNumberSite[] | DiveNumberResponse;
  const sites = Array.isArray(payload) ? payload : (payload.sites ?? payload.data ?? []);
  logger.info(`Dive Number returned ${sites.length} sites`);

  const seenSlugs = new Set<string>();
  const siteRows: DiveSiteRow[] = [];

  sites.forEach((site, index) => {
    const row = mapSite(site, index, seenSlugs);
    if (row) siteRows.push(row);
  });

  const result = await upsertBatch(
    'dive_sites',
    siteRows as unknown as Record<string, unknown>[],
    'slug',
  );

  logJobSummary('divenumber', {
    processed: sites.length,
    upserted: result.upserted,
    skipped: result.skipped,
    errors: result.errors,
  });

  logger.info(`Dive Number ETL finished in ${Date.now() - startedAt}ms`);
}

if (isMainModule(import.meta.url)) {
  runDiveNumberEtl().catch((err) => {
    logger.error('Dive Number ETL failed', {
      error: err instanceof Error ? err.message : String(err),
    });
    process.exit(1);
  });
}
