/**
 * OBIS Occurrence ETL — v2 (global scope + marine taxa filtering).
 *
 * v2 changes:
 *  - Replaced Mediterranean-only polygon with global marine regions.
 *  - Added taxon filtering: only fetches known marine groups instead of
 *    all organisms in the bounding box (the root cause of terrestrial
 *    contamination in v1).
 *  - Controlled by OBIS_REGIONS env var.
 */

import 'dotenv/config';
import { logger, logJobSummary } from '../shared/logger';
import { paginate, RateLimiter } from '../shared/rate-limiter';
import { getSupabase, upsertBatch } from '../shared/supabase';
import { isMainModule } from '../shared/cli';
import {
  assertSystemUserExists,
  matchSightingsToSites,
  normalizeCount,
  normalizeDepth,
  normalizeObservedAt,
} from '../shared/occurrence';
import { resolveRegions } from '../shared/marine-regions';

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

/**
 * Marine higher-taxa to query OBIS with.
 *
 * OBIS v3 supports the `scientificname` parameter which filters to occurrences
 * belonging to that taxon. Using this per-taxon approach instead of a single
 * unfiltered query prevents terrestrial species from entering the pipeline.
 *
 * Elasmobranchii (sharks/rays) included separately because OBIS returns
 * them under both Chondrichthyes and Elasmobranchii depending on the dataset.
 */
const MARINE_TAXA = [
  'Actinopterygii',    // bony fish
  'Elasmobranchii',    // sharks, rays
  'Testudines',        // turtles (marine in coastal regions)
  'Cetacea',           // whales & dolphins
  'Cephalopoda',       // octopus, squid, cuttlefish
  'Bivalvia',          // clams, mussels, scallops
  'Echinodermata',     // sea stars, urchins, sea cucumbers
  'Cnidaria',          // jellyfish, corals, anemones
  'Malacostraca',      // crabs, lobsters, shrimp
];

const limiter = new RateLimiter({ minIntervalMs: 300, timeoutMs: 120_000 });

async function fetchObisPage(
  regionWkt: string,
  taxon: string,
  offset: number,
  limit: number,
): Promise<ObisOccurrence[]> {
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

export async function runObisEtl(): Promise<void> {
  const startedAt = Date.now();
  logger.info('Starting OBIS global occurrence ETL (v2 — global + marine taxa)');

  const regions = resolveRegions('OBIS_REGIONS');
  logger.info(`OBIS regions: ${regions.map((r) => r.name).join(', ')}`);

  // Raised from 8000 now that site-linking is a single set-based query
  // (migration 063) rather than one RPC per occurrence. Override with
  // OBIS_MAX_RECORDS.
  const maxRecords = Number(process.env.OBIS_MAX_RECORDS ?? 24000);
  const pageSize = 200;
  // Spread budget across regions × taxa
  const perQuery = Math.max(pageSize, Math.ceil(maxRecords / (regions.length * MARINE_TAXA.length)));

  const byId = new Map<string, ObisOccurrence>();

  for (const region of regions) {
    for (const taxon of MARINE_TAXA) {
      const page = await paginate(
        async (offset, limit) => {
          const rows = await fetchObisPage(region.wkt, taxon, offset, Math.min(limit, pageSize));
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
    }
  }

  const occurrences = [...byId.values()];
  logger.info(`OBIS: fetched ${occurrences.length} unique occurrences across ${regions.length} regions`);

  const supabase = getSupabase();
  const systemUserId = process.env.ETL_SYSTEM_USER_ID;
  if (!systemUserId) throw new Error('ETL_SYSTEM_USER_ID is required');
  await assertSystemUserExists(supabase, systemUserId);

  const speciesRows: Record<string, unknown>[] = [];
  const sightingRows: Record<string, unknown>[] = [];
  const occById = new Map<string, ObisOccurrence>();

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
      metadata: { source: 'obis', obis_id: occ.id, taxon_id: occ.taxonID },
    });

    const observedAt = normalizeObservedAt(occ.date_start);
    if (!observedAt) continue;

    const depth = normalizeDepth(
      occ.minimumDepthInMeters != null ? occ.minimumDepthInMeters : occ.maximumDepthInMeters,
    );

    // Site linking deferred to a single set-based query after insert
    // (matchSightingsToSites). Always store location so both the batch
    // matcher and open-water reconciliation can link the row.
    sightingRows.push({
      user_id: systemUserId,
      dive_site_id: null,
      species_id: null,
      observed_at: observedAt,
      depth_m: depth,
      count: normalizeCount(occ.individualCount),
      confidence_level: 'likely',
      source: 'obis',
      external_id: occ.id,
      location: `SRID=4326;POINT(${occ.decimalLongitude} ${occ.decimalLatitude})`,
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

  const resolvedSightings = sightingRows
    .map((row) => {
      const occ = occById.get(row.external_id as string);
      const scientificName = occ?.scientificName;
      const speciesId = scientificName ? idByName.get(scientificName) : undefined;
      return speciesId ? { ...row, species_id: speciesId } : null;
    })
    .filter(Boolean) as Record<string, unknown>[];

  const sightingResult = await upsertBatch('sightings', resolvedSightings, 'source,external_id');

  // Link all freshly-imported OBIS sightings to nearby dive sites in one query.
  await matchSightingsToSites(supabase, 'obis', 20);

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
