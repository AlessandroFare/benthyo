import 'dotenv/config';
import { logger, logJobSummary } from '../shared/logger';
import { paginate, RateLimiter } from '../shared/rate-limiter';
import { getSupabase, upsertBatch } from '../shared/supabase';
import { isMainModule } from '../shared/cli';

/**
 * OBIS-SEAMAP ETL — marine megafauna (turtles, marine mammals, seabirds).
 * SEAMAP data is ingested via the same OBIS v3 API, filtered by the
 * SEAMAP dataset ID. This keeps the pipe consistent with etl/obis/ and
 * lets us deduplicate on source,external_id.
 *
 * https://seamap.env.duke.edu
 */
const OBIS_API = 'https://api.obis.org/v3';

const SEAMAP_DATASET_ID = 'd372cbce-85b8-4c03-a70a-5d9a00c3b792';

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

const MEDITERRANEAN_WKT = 'POLYGON((-6 30, 36 30, 36 46, -6 46, -6 30))';
const limiter = new RateLimiter({ minIntervalMs: 300 });

async function fetchSeamapPage(offset: number, limit: number): Promise<SeamapOccurrence[]> {
  const params = new URLSearchParams({
    geometry: MEDITERRANEAN_WKT,
    datasetid: SEAMAP_DATASET_ID,
    size: String(limit),
    start: String(offset),
  });
  const url = `${OBIS_API}/occurrence?${params}`;
  const data = await limiter.fetchJson<ObisSearchResponse>(url);
  return data.results ?? [];
}

export async function runSeamapEtl(): Promise<void> {
  const startedAt = Date.now();
  logger.info('Starting SEAMAP Mediterranean occurrence ETL');

  const maxRecords = Number(process.env.SEAMAP_MAX_RECORDS ?? 1500);
  const pageSize = 200;

  const occurrences = await paginate(
    async (offset, limit) => {
      const page = await fetchSeamapPage(offset, Math.min(limit, pageSize));
      if (offset + page.length >= maxRecords) {
        return page.slice(0, Math.max(0, maxRecords - offset));
      }
      return page;
    },
    pageSize,
    Math.ceil(maxRecords / pageSize),
  );

  logger.info(`Fetched ${occurrences.length} SEAMAP occurrences`);

  const supabase = getSupabase();
  const systemUserId = process.env.ETL_SYSTEM_USER_ID;
  if (!systemUserId) {
    throw new Error('ETL_SYSTEM_USER_ID is required for sighting imports');
  }

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
      p_radius_km: 50,
    });

    const siteId = nearestSite?.[0]?.id;
    if (!siteId) continue;

    const depth = occ.minimumDepthInMeters ?? occ.maximumDepthInMeters;

    sightingRows.push({
      user_id: systemUserId,
      dive_site_id: siteId,
      species_id: null,
      observed_at: occ.date_start ?? new Date().toISOString(),
      depth_m: depth,
      count: occ.individualCount ?? 1,
      confidence_level: 'likely',
      source: 'seamap',
      external_id: occ.id,
      notes: `Imported from SEAMAP ${occ.id}`,
    });
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
