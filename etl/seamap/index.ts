/**
 * OBIS-SEAMAP ETL — v2 (global scope).
 *
 * v2 changes:
 *  - Replaced Mediterranean-only polygon with global marine regions.
 *  - Now uses resolveRegions() like GBIF/OBIS/iNat.
 *  - Controlled by SEAMAP_REGIONS env var.
 */

import 'dotenv/config';
import { logger, logJobSummary } from '../shared/logger';
import { paginate, RateLimiter } from '../shared/rate-limiter';
import { getSupabase, upsertBatch } from '../shared/supabase';
import { isMainModule } from '../shared/cli';
import {
  assertSystemUserExists,
  normalizeCount,
  normalizeDepth,
  normalizeObservedAt,
} from '../shared/occurrence';
import { resolveRegions } from '../shared/marine-regions';

const OBIS_API = 'https://api.obis.org/v3';

// Higher taxa that constitute OBIS-SEAMAP's marine-megafauna scope.
const MEGAFAUNA_TAXA = [
  'Cetacea',          // whales & dolphins
  'Pinnipedia',       // seals
  'Sirenia',          // manatees/dugongs
  'Testudines',       // sea turtles
  'Procellariiformes',// tubenose seabirds
  'Suliformes',       // gannets/cormorants
  'Elasmobranchii',   // sharks, rays, skates
] as const;

interface SeamapOccurrence {
  id: string;
  scientificName?: string;
  decimalLatitude?: number;
  decimalLongitude?: number;
  date_start?: string;
  individualCount?: number;
  minimumDepthInMeters?: number;
  maximumDepthInMeters?: number;
  species?: string;
  genus?: string;
  family?: string;
  class?: string;
  phylum?: string;
  kingdom?: string;
  taxonID?: string;
}

interface ObisSearchResponse {
  total: number;
  results: SeamapOccurrence[];
}

const limiter = new RateLimiter({ minIntervalMs: 300 });

async function fetchSeamapPage(
  regionWkt: string,
  taxon: string,
  offset: number,
  limit: number,
): Promise<SeamapOccurrence[]> {
  const params = new URLSearchParams({
    geometry: regionWkt,
    scientificname: taxon,
    size: String(limit),
    start: String(offset),
  });
  const url = `${OBIS_API}/occurrence?${params}`;
  const data = await limiter.fetchJson<ObisSearchResponse>(url);
  return data.results ?? [];
}

export async function runSeamapEtl(): Promise<void> {
  const startedAt = Date.now();
  logger.info('Starting SEAMAP (OBIS megafauna) global occurrence ETL (v2)');

  const regions = resolveRegions('SEAMAP_REGIONS');
  logger.info(`SEAMAP regions: ${regions.map((r) => r.name).join(', ')}`);

  const maxRecords = Number(process.env.SEAMAP_MAX_RECORDS ?? 5000);
  const pageSize = 200;
  const perQuery = Math.max(pageSize, Math.ceil(maxRecords / (regions.length * MEGAFAUNA_TAXA.length)));

  const byId = new Map<string, SeamapOccurrence>();

  for (const region of regions) {
    for (const taxon of MEGAFAUNA_TAXA) {
      const page = await paginate(
        async (offset, limit) => {
          const rows = await fetchSeamapPage(region.wkt, taxon, offset, Math.min(limit, pageSize));
          if (offset + rows.length >= perQuery) {
            return rows.slice(0, Math.max(0, perQuery - offset));
          }
          return rows;
        },
        pageSize,
        Math.ceil(perQuery / pageSize),
      );
      for (const occ of page) {
        if (occ.id) byId.set(occ.id, occ);
      }
      logger.info(`SEAMAP ${taxon} (${region.name}): ${page.length} occurrences`);
    }
  }
  const occurrences = [...byId.values()];

  logger.info(`Fetched ${occurrences.length} SEAMAP megafauna occurrences across ${regions.length} regions`);

  const supabase = getSupabase();
  const systemUserId = process.env.ETL_SYSTEM_USER_ID;
  if (!systemUserId) {
    throw new Error('ETL_SYSTEM_USER_ID is required for sighting imports');
  }
  await assertSystemUserExists(supabase, systemUserId);

  const speciesRows: Record<string, unknown>[] = [];
  const sightingRows: Record<string, unknown>[] = [];
  const occById = new Map<string, SeamapOccurrence>();

  for (const occ of occurrences) {
    if (!occ.scientificName || occ.decimalLatitude == null || occ.decimalLongitude == null) continue;
    occById.set(occ.id, occ);

    const aphiaMatch = (occ.taxonID ?? '').match(/taxname:(\d+)/);
    const wormsId = aphiaMatch ? Number(aphiaMatch[1]) : undefined;

    speciesRows.push({
      scientific_name: occ.scientificName,
      kingdom: occ.kingdom ?? 'Animalia',
      phylum: occ.phylum,
      class_name: occ.class,
      family: occ.family,
      genus: occ.genus,
      ...(wormsId ? { worms_id: wormsId } : {}),
      metadata: { source: 'seamap', seamap_id: occ.id, taxon_id: occ.taxonID },
    });

    const { data: nearestSite } = await supabase.rpc('nearby_dive_sites', {
      p_lat: occ.decimalLatitude,
      p_lng: occ.decimalLongitude,
      p_radius_km: 30,
    });

    const siteId = nearestSite?.[0]?.id;

    const observedAt = normalizeObservedAt(occ.date_start);
    if (!observedAt) continue;

    const depth = normalizeDepth(occ.minimumDepthInMeters ?? occ.maximumDepthInMeters);

    const sighting: Record<string, unknown> = {
      user_id: systemUserId,
      dive_site_id: siteId ?? null,
      species_id: null,
      observed_at: observedAt,
      depth_m: depth,
      count: normalizeCount(occ.individualCount),
      confidence_level: 'likely',
      source: 'seamap',
      external_id: occ.id,
      notes: `Imported from SEAMAP ${occ.id}`,
    };
    if (!siteId) {
      sighting.location = `SRID=4326;POINT(${occ.decimalLongitude} ${occ.decimalLatitude})`;
    }
    sightingRows.push(sighting);
  }

  const speciesResult = await upsertBatch('species', speciesRows, 'scientific_name');

  const scientificNames = [...new Set(speciesRows.map((r) => r.scientific_name as string))];
  const { data: speciesLookup } = await supabase
    .from('species')
    .select('id, scientific_name')
    .in('scientific_name', scientificNames);

  const idByName = new Map((speciesLookup ?? []).map((s) => [s.scientific_name as string, s.id as string]));

  const resolvedSightings = sightingRows
    .map((row) => {
      const occ = occById.get(row.external_id as string);
      const scientificName = occ?.scientificName;
      const speciesId = scientificName ? idByName.get(scientificName) : undefined;
      return speciesId ? { ...row, species_id: speciesId } : null;
    })
    .filter(Boolean) as Record<string, unknown>[];

  const sightingResult = await upsertBatch('sightings', resolvedSightings, 'source,external_id');

  logJobSummary('seamap', {
    processed: occurrences.length,
    upserted: speciesResult.upserted + sightingResult.upserted,
    skipped: speciesResult.skipped + sightingResult.skipped,
    errors: [...speciesResult.errors, ...sightingResult.errors],
  });

  logger.info(`SEAMAP ETL finished in ${Date.now() - startedAt}ms`);
}

if (isMainModule(import.meta.url)) {
  runSeamapEtl().catch((err) => {
    logger.error('SEAMAP ETL failed', { error: err instanceof Error ? err.message : String(err) });
    process.exit(1);
  });
}
