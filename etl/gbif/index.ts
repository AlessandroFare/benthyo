/**
 * GBIF Occurrence ETL — v3 (global scope + marine-only taxa).
 *
 * v3 changes:
 *  - Replaced Mediterranean-only polygon with 11 global marine regions
 *    (Caribbean, Red Sea, Indian Ocean, Southeast Asia, Pacific, etc.)
 *    controlled by GBIF_REGIONS env var (default: all regions).
 *  - Replaced Reptilia (225) → Testudines (793) to exclude lizards/snakes.
 *  - Split Mollusca (212) → Cephalopoda (760) + Bivalvia (137) to exclude
 *    terrestrial snails/gastropods that contaminated v2.
 *  - Added depth filter per region (max depth = region-specific).
 *  - Added GBIF_MAX_RECORDS_PER_REGION env var for per-region budgets.
 *  - Post-import: attempts iNaturalist taxon lookup to populate common_name
 *    for species that came from GBIF without a common name.
 */

import 'dotenv/config';
import type { ConservationStatus } from '@benthyo/types';
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
import { resolveRegions, type MarineRegion } from '../shared/marine-regions';

const GBIF_API = 'https://api.gbif.org/v1';

/**
 * GBIF higher-taxon keys for STRICTLY MARINE groups.
 *
 * v2 had Reptilia (225) → terrestrial lizards/snakes contaminated the catalog.
 * v2 had Mollusca (212) → terrestrial snails (Cornu aspersum etc.) contaminated.
 * v3 uses only marine sub-taxa.
 *
 * Key mapping:
 *  - 204       Actinopterygii (bony fish) — all marine
 *  - 11592253  Elasmobranchii (sharks, rays, skates) — all marine
 *  - 793       Testudines (turtles) — replaces Reptilia; mostly marine in coastal regions
 *  - 733       Mammalia — includes dolphins/whales via coastal filter
 *  - 760       Cephalopoda (octopus, squid, cuttlefish) — all marine
 *  - 137       Bivalvia (clams, mussels, scallops) — all marine
 *  - 1065      Echinodermata (sea stars, urchins) — all marine
 *  - 43        Cnidaria (jellyfish, corals, anemones) — all marine
 *  - 756       Crustacea / Malacostraca — predominantly marine at coasts
 */
// Per-region record budgets per taxon group. Roughly doubled from v3 now
// that site-linking is a single set-based query (migration 063) instead of
// one REST round-trip per occurrence — the previous bottleneck that made
// larger budgets impractical. Override globally with GBIF_MAX_RECORDS_PER_REGION.
const MARINE_TAXON_KEYS: Array<{ key: number; label: string; maxRecords: number }> = [
  { key: 204,       label: 'Actinopterygii',   maxRecords: 4000 },
  { key: 11592253,  label: 'Elasmobranchii',   maxRecords: 1500 },
  { key: 793,       label: 'Testudines',        maxRecords: 600  },
  { key: 733,       label: 'Mammalia',          maxRecords: 800  },
  { key: 760,       label: 'Cephalopoda',       maxRecords: 800  },
  { key: 137,       label: 'Bivalvia',          maxRecords: 800  },
  { key: 1065,      label: 'Echinodermata',     maxRecords: 1000 },
  { key: 43,        label: 'Cnidaria',          maxRecords: 800  },
  { key: 756,       label: 'Crustacea',         maxRecords: 800  },
];

const MAX_COORD_UNCERTAINTY_M = 1000;
const MAX_DEPTH_M = 300;

interface GbifOccurrence {
  key: number;
  scientificName?: string;
  speciesKey?: number;
  decimalLatitude?: number;
  decimalLongitude?: number;
  eventDate?: string;
  individualCount?: number;
  depth?: number;
  coordinateUncertaintyInMeters?: number;
  basisOfRecord?: string;
  iucnRedListCategory?: string;
}

interface GbifSearchResponse {
  results: GbifOccurrence[];
  count: number;
  endOfRecords: boolean;
}

interface GbifSpeciesInfo {
  usageKey?: number;
  scientificName?: string;
  canonicalName?: string;
  kingdom?: string;
  phylum?: string;
  class?: string;
  order?: string;
  family?: string;
  genus?: string;
  iucnRedListCategory?: string;
}

function mapConservationStatus(iucn?: string): ConservationStatus | null {
  if (!iucn) return null;
  const map: Record<string, ConservationStatus> = {
    LC: 'LC', NT: 'NT', VU: 'VU', EN: 'EN', CR: 'CR', DD: 'DD', NE: 'NE',
  };
  return map[iucn.toUpperCase()] ?? null;
}

const limiter = new RateLimiter({ minIntervalMs: 200, maxRetries: 5 });

async function fetchOccurrencePage(
  region: MarineRegion,
  taxonKey: number,
  offset: number,
  limit: number,
): Promise<GbifOccurrence[]> {
  const params = new URLSearchParams();
  params.append('geometry', region.wkt);
  params.append('taxonKey', String(taxonKey));
  params.append('hasCoordinate', 'true');
  params.append('hasGeospatialIssue', 'false');
  params.append('coordinateUncertaintyInMeters', `0,${MAX_COORD_UNCERTAINTY_M}`);
  params.append('basisOfRecord', 'HUMAN_OBSERVATION');
  params.append('basisOfRecord', 'MACHINE_OBSERVATION');
  params.append('occurrenceStatus', 'PRESENT');
  params.append('limit', String(limit));
  params.append('offset', String(offset));

  const url = `${GBIF_API}/occurrence/search?${params}`;
  const data = await limiter.fetchJson<GbifSearchResponse>(url);
  return data.results ?? [];
}

async function fetchSpeciesInfo(speciesKey: number): Promise<GbifSpeciesInfo | null> {
  try {
    return await limiter.fetchJson<GbifSpeciesInfo>(`${GBIF_API}/species/${speciesKey}`);
  } catch {
    return null;
  }
}

// ── iNaturalist common-name lookup (post-import enrichment) ──

const INAT_API = process.env.INAT_API_BASE ?? 'https://api.inaturalist.org/v1';
const inatLimiter = new RateLimiter({ minIntervalMs: 800, maxRetries: 3 });

interface InatTaxonResult {
  id: number;
  name: string;
  preferred_common_name?: string;
}

async function lookupInatCommonName(
  scientificName: string,
): Promise<{ inat_taxon_id: number; common_name: string | null } | null> {
  const url = `${INAT_API}/taxa?q=${encodeURIComponent(scientificName)}&rank=species&is_active=true&per_page=3`;
  try {
    const data = await inatLimiter.fetchJson<{ results: InatTaxonResult[] }>(url);
    if (!data.results?.length) return null;
    // Exact name match (case-insensitive)
    const want = scientificName.toLowerCase().trim();
    const match = data.results.find((r) => r.name.toLowerCase().trim() === want);
    if (!match) return null;
    return {
      inat_taxon_id: match.id,
      common_name: match.preferred_common_name ?? null,
    };
  } catch {
    return null;
  }
}

// ── Main run ──

export async function runGbifEtl(): Promise<void> {
  const startedAt = Date.now();
  logger.info('Starting GBIF global occurrence ETL (v3 — global + marine-only taxa)');

  const supabase = getSupabase();
  const systemUserId = process.env.ETL_SYSTEM_USER_ID;
  if (!systemUserId) throw new Error('ETL_SYSTEM_USER_ID is required');
  await assertSystemUserExists(supabase, systemUserId);

  const regions = resolveRegions('GBIF_REGIONS');
  logger.info(`GBIF regions: ${regions.map((r) => r.name).join(', ')}`);

  const perRegionOverride = process.env.GBIF_MAX_RECORDS_PER_REGION
    ? Number(process.env.GBIF_MAX_RECORDS_PER_REGION)
    : null;

  const speciesCache = new Map<number, GbifSpeciesInfo>();
  const speciesRows: Record<string, unknown>[] = [];
  const pendingSightings: Array<{ occ: GbifOccurrence; speciesKey: number; region: MarineRegion }> = [];
  const errors: string[] = [];

  let totalFetched = 0;

  for (const region of regions) {
    logger.info(`GBIF: region ${region.name}`);
    for (const taxonGroup of MARINE_TAXON_KEYS) {
      const maxRecords = perRegionOverride ?? taxonGroup.maxRecords;
      const pageSize = 300;

      const occurrences = await paginate(
        async (offset, limit) => {
          const page = await fetchOccurrencePage(
            region,
            taxonGroup.key,
            offset,
            Math.min(limit, pageSize),
          );
          if (offset + page.length >= maxRecords) {
            return page.slice(0, Math.max(0, maxRecords - offset));
          }
          return page;
        },
        pageSize,
        Math.ceil(maxRecords / pageSize),
      );

      totalFetched += occurrences.length;

      for (const occ of occurrences) {
        if (!occ.scientificName || occ.decimalLatitude == null || occ.decimalLongitude == null) {
          continue;
        }
        if (occ.depth != null && occ.depth > MAX_DEPTH_M) continue;

        const key = occ.speciesKey;
        if (!key) continue;

        if (!speciesCache.has(key)) {
          const info = await fetchSpeciesInfo(key);
          if (info) speciesCache.set(key, info);
        }

        const info = speciesCache.get(key);
        if (!info) continue;

        speciesRows.push({
          scientific_name: info.canonicalName ?? info.scientificName ?? occ.scientificName,
          gbif_taxon_key: key,
          kingdom: info.kingdom ?? 'Animalia',
          phylum: info.phylum,
          class_name: info.class,
          order_name: info.order,
          family: info.family,
          genus: info.genus,
          conservation_status: mapConservationStatus(info.iucnRedListCategory ?? occ.iucnRedListCategory),
          metadata: {
            source: 'gbif',
            gbif_occurrence_key: occ.key,
            taxon_group: taxonGroup.label,
            region: region.name,
          },
        });

        pendingSightings.push({ occ, speciesKey: key, region });
      }
    }
  }

  logger.info(`GBIF: ${totalFetched} total occurrences, ${speciesRows.length} species candidates`);

  // Upsert species
  const speciesResult = await upsertBatch('species', speciesRows, 'scientific_name');

  // Build scientific_name → DB id map
  const scientificNames = [...new Set(speciesRows.map((r) => r.scientific_name as string))];
  const { data: speciesLookup } = await supabase
    .from('species')
    .select('id, scientific_name, gbif_taxon_key')
    .in('scientific_name', scientificNames);

  const idByGbifKey = new Map<number, string>();
  const idByName = new Map<string, string>();
  for (const sp of speciesLookup ?? []) {
    idByName.set(sp.scientific_name as string, sp.id as string);
    if (sp.gbif_taxon_key) idByGbifKey.set(sp.gbif_taxon_key as number, sp.id as string);
  }

  // ── Sightings ──
  const sightingRows: Record<string, unknown>[] = [];

  for (const { occ, speciesKey } of pendingSightings) {
    const info = speciesCache.get(speciesKey);
    const name = info?.canonicalName ?? info?.scientificName ?? occ.scientificName ?? '';
    const speciesId = idByGbifKey.get(speciesKey) ?? idByName.get(name);
    if (!speciesId) continue;

    const observedAt = normalizeObservedAt(occ.eventDate);
    if (!observedAt) continue;

    // Site linking is deferred: we always store the raw location and set
    // dive_site_id = null. A single set-based query (matchSightingsToSites)
    // links every row to its nearest dive site after the bulk insert,
    // instead of one nearby_dive_sites RPC per occurrence.
    sightingRows.push({
      user_id: systemUserId,
      dive_site_id: null,
      species_id: speciesId,
      observed_at: observedAt,
      depth_m: normalizeDepth(occ.depth),
      count: normalizeCount(occ.individualCount),
      confidence_level: 'likely',
      source: 'gbif',
      external_id: String(occ.key),
      location: `SRID=4326;POINT(${occ.decimalLongitude!} ${occ.decimalLatitude!})`,
      notes: `Imported from GBIF occurrence ${occ.key}`,
    });
  }

  const sightingResult = await upsertBatch('sightings', sightingRows, 'source,external_id');

  // Link all freshly-imported GBIF sightings to nearby dive sites in one
  // indexed query (replaces per-occurrence RPC calls).
  await matchSightingsToSites(supabase, 'gbif', 20);

  // ── Post-import: iNaturalist common-name enrichment ──
  // Species imported from GBIF have no common_name. We look each one up on
  // iNaturalist (free API, same as inat-taxon-lookup ETL) to get both
  // inat_taxon_id and preferred_common_name.
  const { data: namelessSpecies } = await supabase
    .from('species')
    .select('id, scientific_name')
    .is('common_name', null)
    .not('scientific_name', 'is', null)
    .limit(200);

  let enriched = 0;
  if (namelessSpecies && namelessSpecies.length > 0) {
    logger.info(`GBIF: enriching common names for ${namelessSpecies.length} species via iNaturalist`);
    for (const sp of namelessSpecies) {
      try {
        const match = await lookupInatCommonName(sp.scientific_name as string);
        if (!match) continue;
        const update: Record<string, unknown> = { inat_taxon_id: match.inat_taxon_id };
        if (match.common_name) update.common_name = match.common_name;
        await supabase.from('species').update(update).eq('id', sp.id);
        enriched += 1;
      } catch {
        // non-fatal
      }
    }
    logger.info(`GBIF: enriched ${enriched} species with common names`);
  }

  logJobSummary('gbif', {
    processed: totalFetched,
    upserted: speciesResult.upserted + sightingResult.upserted,
    skipped: speciesResult.skipped + sightingResult.skipped,
    errors: [...speciesResult.errors, ...sightingResult.errors, ...errors],
  });
  logger.info(`GBIF ETL finished in ${Date.now() - startedAt}ms`);
}

if (isMainModule(import.meta.url)) {
  runGbifEtl().catch((err) => {
    logger.error('GBIF ETL failed', { error: err instanceof Error ? err.message : String(err) });
    process.exit(1);
  });
}
