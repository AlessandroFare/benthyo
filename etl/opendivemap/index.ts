import 'dotenv/config';
import { logger, logJobSummary } from '../shared/logger';
import { RateLimiter, paginate } from '../shared/rate-limiter';
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

const API_BASE = process.env.OPENDIVEMAP_API_URL ?? 'https://api.opendivemap.com/v1';
const PAGE_SIZE = Number(process.env.OPENDIVEMAP_PAGE_SIZE ?? 500);
const MAX_SITES = Number(process.env.OPENDIVEMAP_MAX_SITES ?? 5000);

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
  const description =
    (typeof tags.description === 'string' ? tags.description : null) ??
    (typeof tags.description_wildlife === 'string' ? tags.description_wildlife : null);

  const topology = props.topologies?.[0];
  const slug = uniqueSlug(`odm-${props.id}`, props.id, seenSlugs);
  const depthMax = Number(props.max_depth ?? tags.max_depth ?? 30);
  const depthMin = Number(tags.min_depth ?? 0);
  const hint = `${description ?? ''} ${props.name}`;

  return {
    name: props.name,
    slug,
    description,
    location: geographyPoint(lon, lat),
    country_code: normalizeCountryCode(props.country_code),
    region: props.country_name ?? null,
    depth_min: Number.isFinite(depthMin) ? depthMin : 0,
    depth_max: Number.isFinite(depthMax) ? depthMax : 30,
    difficulty: normalizeDifficulty(undefined, hint),
    site_type: normalizeSiteType(topology),
    access_type: normalizeAccessType(props.entry, hint),
    verified: false,
    metadata: {
      source: 'opendivemap',
      opendivemap_id: props.id,
      environment: props.environment,
      topologies: props.topologies,
      tags,
      hero_image: typeof tags.thumbnail === 'string' ? tags.thumbnail : null,
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
