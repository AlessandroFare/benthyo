import 'dotenv/config';
import { logger, logJobSummary } from '../shared/logger';
import { RateLimiter } from '../shared/rate-limiter';
import {
  buildOverpassQuery,
  geographyPoint,
  normalizeAccessType,
  normalizeCountryCode,
  normalizeDifficulty,
  normalizeSiteType,
  OVERPASS_REGIONS,
  slugify,
  uniqueSlug,
  type DiveSiteRow,
  type OverpassRegion,
} from '../shared/dive-site-utils';
import { upsertBatch } from '../shared/supabase';
import { isMainModule } from '../shared/cli';

/**
 * Overpass API endpoints. The primary is tried first; on HTTP 504/429 we
 * retry on the next mirror. All are free public instances.
 */
const OVERPASS_MIRRORS = [
  process.env.OVERPASS_API_URL ?? 'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
  'https://overpass-api.de/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
  'https://overpass.private.coffee/api/interpreter',
];

interface OverpassElement {
  type: 'node' | 'way' | 'relation';
  id: number;
  lat?: number;
  lon?: number;
  center?: { lat: number; lon: number };
  tags?: Record<string, string>;
}

interface OverpassResponse {
  elements: OverpassElement[];
}

/**
 * Some Overpass regions span huge bounding boxes that cause HTTP 504 timeouts
 * on the public Overpass servers. Split them into smaller sub-bboxes that are
 * queried independently and their results merged.
 */
function splitRegionIfNeeded(region: OverpassRegion): OverpassRegion[] {
  // Pacific: 140°→-120° longitude = 260° span. Split into 3 vertical slices.
  if (region.name === 'pacific') {
    return [
      { name: 'pacific_west',  south: -30, west: 140, north: 30, east: 180 },
      { name: 'pacific_central', south: -30, west: -180, north: 30, east: -150 },
      { name: 'pacific_east',  south: -30, west: -150, north: 30, east: -120 },
    ];
  }
  // Caribbean can also be slow on some servers, but 504 is rare there.
  return [region];
}

function countryFromTags(tags: Record<string, string>): string {
  const iso = tags['ISO3166-1:alpha2'] ?? tags['addr:country'];
  return normalizeCountryCode(iso);
}

function inferSiteTypeFromTags(tags: Record<string, string>): string {
  // Check structured OSM tags first (more reliable than name/description heuristics)
  const seamarkType = tags['seamark:type'] ?? '';
  if (seamarkType === 'wreck' || tags.historic === 'wreck') return 'wreck';
  if (seamarkType === 'rock' || seamarkType === 'underwater_rock') return 'pinnacle';

  const sport = tags.sport ?? '';
  if (sport === 'freediving') return 'other'; // open water / blue water

  const hint = `${tags.name ?? ''} ${tags.description ?? ''} ${tags['description:en'] ?? ''}`.toLowerCase();
  if (hint.includes('wreck') || hint.includes('relitto') || hint.includes('epave')) return 'wreck';
  if (hint.includes('wall') || hint.includes('drop-off') || hint.includes('paroi')) return 'wall';
  if (hint.includes('cave') || hint.includes('grotta') || hint.includes('caverne')) return 'cave';
  if (hint.includes('pinnacle') || hint.includes('seamount') || hint.includes('pinnacolo')) return 'pinnacle';
  if (hint.includes('muck') || hint.includes('sand') || hint.includes('sabbia')) return 'muck';
  return 'reef';
}

function mapElement(
  el: OverpassElement,
  region: OverpassRegion,
  seenSlugs: Set<string>,
): DiveSiteRow | null {
  const tags = el.tags ?? {};
  const name = tags.name ?? tags['name:en'];
  if (!name) return null;

  const lat = el.lat ?? el.center?.lat;
  const lon = el.lon ?? el.center?.lon;
  if (lat == null || lon == null) return null;

  const baseSlug = slugify(name);
  const slug = uniqueSlug(baseSlug, String(el.id), seenSlugs);
  const hint = `${tags.description ?? ''} ${tags['description:en'] ?? ''}`;
  // OSM wreck nodes use seamark:depth for the depth to the keel / deck
  const rawDepth = tags['seamark:depth'] ?? tags.depth ?? tags.max_depth;
  const depthMax = Number.isFinite(Number(rawDepth)) && Number(rawDepth) > 0
    ? Number(rawDepth)
    : 30;
  const depthMin = Number(tags.min_depth ?? tags['seamark:depth:minimum'] ?? 0);

  return {
    name,
    slug,
    description: tags.description ?? tags['description:en'] ?? null,
    location: geographyPoint(lon, lat),
    country_code: countryFromTags(tags),
    region: tags['addr:state'] ?? tags['addr:region'] ?? tags['addr:city'] ?? region.name,
    depth_min: Number.isFinite(depthMin) ? depthMin : 0,
    depth_max: Number.isFinite(depthMax) ? depthMax : 30,
    difficulty: normalizeDifficulty(undefined, hint),
    site_type: normalizeSiteType(inferSiteTypeFromTags(tags)),
    access_type: normalizeAccessType(undefined, hint),
    verified: false,
    metadata: {
      source: 'overpass',
      region: region.name,
      osm_type: el.type,
      osm_id: el.id,
      tags,
    },
  };
}

/**
 * Overpass limiter: 3s between requests, NO retries on 429/503.
 * The fetchWithRetry function handles mirror failover instead.
 */
const limiter = new RateLimiter({ minIntervalMs: 3000, maxRetries: 0, baseBackoffMs: 0 });

async function fetchRegion(region: OverpassRegion): Promise<OverpassElement[]> {
  const subRegions = splitRegionIfNeeded(region);
  const allElements: OverpassElement[] = [];

  for (const sub of subRegions) {
    const label = subRegions.length > 1 ? `${region.name} (${sub.name})` : region.name;
    const elements = await fetchWithRetry(sub, label);
    allElements.push(...elements);
  }

  if (subRegions.length > 1) {
    logger.info(`Overpass ${region.name}: ${allElements.length} total elements (${subRegions.length} sub-queries)`);
  }
  return allElements;
}

/**
 * Fetch a single sub-region, retrying on alternative Overpass mirrors in
 * case of HTTP 504 (gateway timeout) or 429 (rate limited).
 */
async function fetchWithRetry(region: OverpassRegion, label: string): Promise<OverpassElement[]> {
  const query = buildOverpassQuery(region);
  logger.info(`Overpass query: ${label}`);

  let lastError: Error | null = null;

  for (let attempt = 0; attempt < OVERPASS_MIRRORS.length; attempt++) {
    const endpoint = OVERPASS_MIRRORS[attempt];
    try {
      const response = await limiter.fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: `data=${encodeURIComponent(query)}`,
      });

      if (response.status === 504 || response.status === 429) {
        logger.warn(`Overpass ${label}: HTTP ${response.status} on ${endpoint}, trying next mirror…`);
        lastError = new Error(`Overpass API error (${label}): HTTP ${response.status}`);
        continue;
      }

      if (!response.ok) {
        throw new Error(`Overpass API error (${label}): HTTP ${response.status}`);
      }

      const data = (await response.json()) as OverpassResponse;
      logger.info(`Overpass ${label}: ${data.elements.length} elements`);
      return data.elements;
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      logger.warn(`Overpass ${label}: failed on ${endpoint}: ${message}, trying next mirror…`);
      lastError = err instanceof Error ? err : new Error(message);
      // Continue to next mirror
    }
  }

  throw lastError ?? new Error(`Overpass ${label}: all mirrors failed`);
}

export async function runOverpassEtl(): Promise<void> {
  const startedAt = Date.now();
  logger.info('Starting Overpass dive site ETL (global regions)');

  const regionFilter = process.env.OVERPASS_REGIONS?.split(',').map((r) => r.trim()).filter(Boolean);
  const regions = regionFilter?.length
    ? OVERPASS_REGIONS.filter((r) => regionFilter.includes(r.name))
    : OVERPASS_REGIONS;

  const seenSlugs = new Set<string>();
  const siteRows: DiveSiteRow[] = [];
  let processed = 0;
  const errors: string[] = [];

  for (const region of regions) {
    try {
      const elements = await fetchRegion(region);
      processed += elements.length;
      for (const el of elements) {
        const row = mapElement(el, region, seenSlugs);
        if (row) siteRows.push(row);
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      errors.push(`${region.name}: ${message}`);
      logger.warn(`Overpass region failed: ${region.name}`, { error: message });
    }
  }

  const result = await upsertBatch(
    'dive_sites',
    siteRows as unknown as Record<string, unknown>[],
    'slug',
  );

  logJobSummary('overpass', {
    processed,
    upserted: result.upserted,
    skipped: result.skipped,
    errors: [...errors, ...result.errors],
  });

  logger.info(`Overpass ETL finished in ${Date.now() - startedAt}ms`);
}

if (isMainModule(import.meta.url)) {
  runOverpassEtl().catch((err) => {
    logger.error('Overpass ETL failed', {
      error: err instanceof Error ? err.message : String(err),
    });
    process.exit(1);
  });
}
