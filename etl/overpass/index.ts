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

const OVERPASS_API = process.env.OVERPASS_API_URL ?? 'https://overpass-api.de/api/interpreter';

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

const limiter = new RateLimiter({ minIntervalMs: 3000 });

function countryFromTags(tags: Record<string, string>): string {
  const iso = tags['ISO3166-1:alpha2'] ?? tags['addr:country'];
  return normalizeCountryCode(iso);
}

function inferSiteTypeFromTags(tags: Record<string, string>): string {
  const hint = `${tags.name ?? ''} ${tags.description ?? ''}`.toLowerCase();
  if (hint.includes('wreck')) return 'wreck';
  if (hint.includes('wall')) return 'wall';
  if (hint.includes('cave')) return 'cave';
  if (hint.includes('pinnacle')) return 'pinnacle';
  if (hint.includes('muck')) return 'muck';
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
  const depthMax = Number(tags.depth ?? tags.max_depth ?? 30);
  const depthMin = Number(tags.min_depth ?? 0);

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

async function fetchRegion(region: OverpassRegion): Promise<OverpassElement[]> {
  const query = buildOverpassQuery(region);
  logger.info(`Overpass query: ${region.name}`);

  const response = await limiter.fetch(OVERPASS_API, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `data=${encodeURIComponent(query)}`,
  });

  if (!response.ok) {
    throw new Error(`Overpass API error (${region.name}): HTTP ${response.status}`);
  }

  const data = (await response.json()) as OverpassResponse;
  logger.info(`Overpass ${region.name}: ${data.elements.length} elements`);
  return data.elements;
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
