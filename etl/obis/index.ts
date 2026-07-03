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

const OBIS_API = 'https://api.obis.org/v3';

interface ObisOccurrence {
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
  results: ObisOccurrence[];
}

const MEDITERRANEAN_WKT = 'POLYGON((-6 30, 36 30, 36 46, -6 46, -6 30))';
const limiter = new RateLimiter({ minIntervalMs: 300 });

async function fetchObisPage(offset: number, limit: number): Promise<ObisOccurrence[]> {
  const params = new URLSearchParams({
    geometry: MEDITERRANEAN_WKT,
    size: String(limit),
    start: String(offset),
  });

  const url = `${OBIS_API}/occurrence?${params}`;
  const data = await limiter.fetchJson<ObisSearchResponse>(url);
  return data.results ?? [];
}

export async function runObisEtl(): Promise<void> {
  const startedAt = Date.now();
  logger.info('Starting OBIS Mediterranean occurrence ETL');

  const maxRecords = Number(process.env.OBIS_MAX_RECORDS ?? 3000);
  const pageSize = 200;

  const occurrences = await paginate(
    async (offset, limit) => {
      const page = await fetchObisPage(offset, Math.min(limit, pageSize));
      if (offset + page.length >= maxRecords) {
        return page.slice(0, Math.max(0, maxRecords - offset));
      }
      return page;
    },
    pageSize,
    Math.ceil(maxRecords / pageSize),
  );

  logger.info(`Fetched ${occurrences.length} OBIS occurrences`);

  const supabase = getSupabase();
  const systemUserId = process.env.ETL_SYSTEM_USER_ID;
  if (!systemUserId) {
    throw new Error('ETL_SYSTEM_USER_ID is required for sighting imports');
  }
  await assertSystemUserExists(supabase, systemUserId);

  const speciesRows: Record<string, unknown>[] = [];
  const sightingRows: Record<string, unknown>[] = [];
  const occById = new Map<string, ObisOccurrence>();

  for (const occ of occurrences) {
    if (!occ.scientificName || occ.decimalLatitude == null || occ.decimalLongitude == null) {
      continue;
    }
    occById.set(occ.id, occ);

    // Parse the WoRMS AphiaID from the URN-style taxonID when present.
    // OBIS exposes the WoRMS taxon identifier as a URN like
    //   urn:lsid:marinespecies.org:taxname:123456
    // The trailing digits are the AphiaID. This lets us write to
    // species.worms_id at the same time as scientific_name, so a
    // subsequent WoRMS upsert by scientific_name still works.
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
      metadata: { source: 'obis', obis_id: occ.id, taxon_id: occ.taxonID },
    });

    const { data: nearestSite } = await supabase.rpc('nearby_dive_sites', {
      p_lat: occ.decimalLatitude,
      p_lng: occ.decimalLongitude,
      p_radius_km: 30,
    });

    const siteId = nearestSite?.[0]?.id;
    if (!siteId) continue;

    const observedAt = normalizeObservedAt(occ.date_start);
    if (!observedAt) continue; // observed_at is NOT NULL; skip undatable rows

    const depth = normalizeDepth(
      occ.minimumDepthInMeters != null
        ? occ.minimumDepthInMeters
        : occ.maximumDepthInMeters,
    );

    sightingRows.push({
      user_id: systemUserId,
      dive_site_id: siteId,
      species_id: null,
      observed_at: observedAt,
      depth_m: depth,
      count: normalizeCount(occ.individualCount),
      confidence_level: 'likely',
      source: 'obis',
      external_id: occ.id,
      notes: `Imported from OBIS ${occ.id}`,
    });
  }

  const speciesResult = await upsertBatch('species', speciesRows, 'scientific_name');

  const scientificNames = [...new Set(speciesRows.map((r) => r.scientific_name as string))];
  const { data: speciesLookup } = await supabase
    .from('species')
    .select('id, scientific_name')
    .in('scientific_name', scientificNames);

  const idByName = new Map(
    (speciesLookup ?? []).map((s) => [s.scientific_name as string, s.id as string]),
  );

  // FIX (P-Data-2 from the audit):
  //   The previous implementation used `speciesRows.find(...)` inside a
  //   `.map()` over `sightingRows` — an O(N²) scan that always returned
  //   the FIRST species row in the array, regardless of which sighting
  //   we were processing. That was a real correctness bug: most OBIS
  //   sightings were being dropped because their species was not the
  //   first one in the array. We now resolve via the pre-built
  //   `occById` map in O(1) per row.
  const resolvedSightings = sightingRows
    .map((row) => {
      const occ = occById.get(row.external_id as string);
      const scientificName = occ?.scientificName;
      const speciesId = scientificName ? idByName.get(scientificName) : undefined;
      return speciesId ? { ...row, species_id: speciesId } : null;
    })
    .filter(Boolean) as Record<string, unknown>[];

  const sightingResult = await upsertBatch(
    'sightings',
    resolvedSightings,
    'source,external_id',
  );

  logJobSummary('obis', {
    processed: occurrences.length,
    upserted: speciesResult.upserted + sightingResult.upserted,
    skipped: speciesResult.skipped + sightingResult.skipped,
    errors: [...speciesResult.errors, ...sightingResult.errors],
  });

  logger.info(`OBIS ETL finished in ${Date.now() - startedAt}ms`);
}

if (isMainModule(import.meta.url)) {
  runObisEtl().catch((err) => {
    logger.error('OBIS ETL failed', { error: err instanceof Error ? err.message : String(err) });
    process.exit(1);
  });
}
