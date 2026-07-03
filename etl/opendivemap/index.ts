import 'dotenv/config';
import { logger, logJobSummary } from '../shared/logger';
import { RateLimiter, paginate } from '../shared/rate-limiter';
import {
  geographyPoint,
  normalizeAccessType,
  normalizeCountryCode,
  normalizeDifficulty,
  normalizeSiteType,
  uniqueSlug,
  type DiveSiteRow,
} from '../shared/dive-site-utils';
import { upsertBatch } from '../shared/supabase';
import { isMainModule } from '../shared/cli';

const API_BASE = process.env.OPENDIVEMAP_API_URL ?? 'https://api.opendivemap.com/v1';
const PAGE_SIZE = Number(process.env.OPENDIVEMAP_PAGE_SIZE ?? 500);
const MAX_SITES = Number(process.env.OPENDIVEMAP_MAX_SITES ?? 10000);

// Fetch marine sites only: ocean environment + all saltwater topologies.
// Setting environment=ocean excludes lakes, rivers, springs, quarries, pools.
// Not filtering by topology so we get all marine types (reef, wall, wreck, etc.)
const OCEAN_FILTER = 'ocean';

const limiter = new RateLimiter({ minIntervalMs: 300 });

interface OpenDiveMapFeature {
  type: 'Feature';
  geometry: { type: 'Point'; coordinates: [number, number] };
  properties: {
    id: string;
    name: string;
    country_code?: string;
    country_name?: string;
    environment?: string;
    topologies?: string[];
    max_depth?: number;
    entry?: string;
    tags?: Record<string, unknown>;
  };
}

interface OpenDiveMapResponse {
  features: OpenDiveMapFeature[];
  numberMatched?: number;
}

async function fetchPage(offset: number, limit: number): Promise<OpenDiveMapFeature[]> {
  const params = new URLSearchParams({
    limit: String(limit),
    offset: String(offset),
    environment: OCEAN_FILTER, // marine sites only — excludes lakes, rivers, springs, pools
  });
  const country = process.env.OPENDIVEMAP_COUNTRY;
  const bbox = process.env.OPENDIVEMAP_BBOX;
  if (country) params.set('country', country);
  if (bbox) params.set('bbox', bbox);

  const url = `${API_BASE}/sites?${params}`;
  const data = await limiter.fetchJson<OpenDiveMapResponse>(url);
  return data.features ?? [];
}

function mapFeature(feature: OpenDiveMapFeature, seenSlugs: Set<string>): DiveSiteRow | null {
  const props = feature.properties;
  const [lon, lat] = feature.geometry.coordinates;
  if (!props.name || !Number.isFinite(lon) || !Number.isFinite(lat)) return null;

  const tags = props.tags ?? {};

  // Prefer structured description fields, fall back to wildlife/notes tags
  const description: string | null =
    (typeof tags.description === 'string' ? tags.description : null) ??
    (typeof tags.description_wildlife === 'string' ? tags.description_wildlife : null) ??
    (typeof tags.notes === 'string' ? tags.notes : null);

  // OpenDiveMap v1 exposes depth in properties.max_depth (preferred) and as a
  // tag. min_depth is available in tags when reported by the contributor.
  const depthMax = Number(props.max_depth ?? tags.max_depth ?? tags.depth_max ?? 30);
  const depthMin = Number(tags.min_depth ?? tags.depth_min ?? 0);

  // Use the first (most-specific) topology; ODM v1 supports all our site_type values
  // plus: artificial_reef, blue_hole, cavern, kelp_forest, channel, open_water.
  // normalizeSiteType handles the ODM extras correctly.
  const topology = props.topologies?.[0];

  const slug = uniqueSlug(`odm-${props.id}`, props.id, seenSlugs);
  const hint = `${description ?? ''} ${topology ?? ''} ${props.name}`;

  // Hero image: ODM exposes it in tags.thumbnail or tags.image
  const heroImage =
    (typeof tags.thumbnail === 'string' ? tags.thumbnail : null) ??
    (typeof tags.image === 'string' ? tags.image : null);

  return {
    name: props.name,
    slug,
    description,
    location: geographyPoint(lon, lat),
    country_code: normalizeCountryCode(props.country_code),
    region: props.country_name ?? (typeof tags.region === 'string' ? tags.region : null),
    depth_min: Number.isFinite(depthMin) && depthMin >= 0 ? depthMin : 0,
    depth_max: Number.isFinite(depthMax) && depthMax > 0 ? depthMax : 30,
    difficulty: normalizeDifficulty(
      typeof tags.difficulty === 'string' ? tags.difficulty : undefined,
      hint,
    ),
    site_type: normalizeSiteType(topology),
    access_type: normalizeAccessType(props.entry, hint),
    verified: false,
    metadata: {
      source: 'opendivemap',
      opendivemap_id: props.id,
      environment: props.environment,
      topologies: props.topologies,
      tags,
      hero_image: heroImage,
    },
  };
}

export async function runOpenDiveMapEtl(): Promise<void> {
  const startedAt = Date.now();
  logger.info('Starting OpenDiveMap dive site ETL', { api: API_BASE });

  const maxPages = Math.ceil(MAX_SITES / PAGE_SIZE);
  const features = await paginate(fetchPage, PAGE_SIZE, maxPages);
  logger.info(`OpenDiveMap returned ${features.length} features`);

  const seenSlugs = new Set<string>();
  const siteRows: DiveSiteRow[] = [];

  for (const feature of features) {
    const row = mapFeature(feature, seenSlugs);
    if (row) siteRows.push(row);
  }

  const result = await upsertBatch(
    'dive_sites',
    siteRows as unknown as Record<string, unknown>[],
    'slug',
  );

  logJobSummary('opendivemap', {
    processed: features.length,
    upserted: result.upserted,
    skipped: result.skipped,
    errors: result.errors,
  });

  logger.info(`OpenDiveMap ETL finished in ${Date.now() - startedAt}ms`);
}

if (isMainModule(import.meta.url)) {
  runOpenDiveMapEtl().catch((err) => {
    logger.error('OpenDiveMap ETL failed', {
      error: err instanceof Error ? err.message : String(err),
    });
    process.exit(1);
  });
}
