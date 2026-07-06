/**
 * iNaturalist Research-Grade Observations ETL — v2 (global scope).
 *
 * v2 changes:
 *  - Replaced Mediterranean-only bbox with 11 global marine regions.
 *  - Fixed Echinodermata taxon ID (was incorrectly sharing Mollusca's 47549).
 *  - Added iNat taxon IDs for marine gastropods (Nudibranchia, etc.) to
 *    recover mollusk groups dropped by the Cephalopoda/Bivalvia-only GBIF fix.
 *  - Controlled by INAT_OBS_REGIONS env var.
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

const INAT_API = process.env.INAT_API_BASE ?? 'https://api.inaturalist.org/v1';

/**
 * iNaturalist taxon IDs for marine groups (global).
 *
 * Fixes in v2:
 *  - Echinodermata was 47549 (same as Mollusca! bug) → fixed to 47548.
 *  - Added Nudibranchia (47113) to recover marine gastropod diversity.
 *  - Added Cephalopoda (47459) as separate group.
 *
 * IDs:
 *   47178  Actinopterygii (ray-finned fish)
 *   505527 Elasmobranchii (sharks, rays)
 *   47459  Cephalopoda (octopus, squid)
 *   47113  Nudibranchia (nudibranchs)
 *   47548  Echinodermata (sea stars, urchins) — was 47549 in v1 (bug)
 *   47534  Cnidaria (jellyfish, corals, anemones)
 *   47119  Mammalia (marine mammals via location filter)
 *   39532  Testudines (sea turtles)
 *   47158  Malacostraca (crabs, lobsters, shrimp)
 */
const MARINE_TAXON_GROUPS: Array<{ id: number; label: string; maxRecords: number }> = [
  { id: 47178,  label: 'Actinopterygii',   maxRecords: 2000 },
  { id: 505527, label: 'Elasmobranchii',   maxRecords: 500  },
  { id: 47459,  label: 'Cephalopoda',      maxRecords: 400  },
  { id: 47113,  label: 'Nudibranchia',     maxRecords: 400  },
  { id: 47548,  label: 'Echinodermata',    maxRecords: 600  },
  { id: 47534,  label: 'Cnidaria',         maxRecords: 500  },
  { id: 47119,  label: 'Mammalia',         maxRecords: 300  },
  { id: 39532,  label: 'Testudines',       maxRecords: 200  },
  { id: 47158,  label: 'Malacostraca',     maxRecords: 600  },
];

const MAX_COORD_ACCURACY_M = 500;

interface InatTaxon {
  id: number;
  name: string;
  rank: string;
  preferred_common_name?: string;
  ancestry?: string;
  iconic_taxon_name?: string;
  wikipedia_url?: string;
}

interface InatObservation {
  uuid: string;
  id: number;
  quality_grade: string;
  observed_on?: string;
  observed_time_zone?: string;
  latitude?: number | null;
  longitude?: number | null;
  positional_accuracy?: number | null;
  depth?: number | null;
  individual_count?: number | null;
  captive?: boolean;
  taxon?: InatTaxon;
  taxon_geoprivacy?: string;
  photos?: Array<{ url?: string }>;
}

interface InatObsResponse {
  total_results: number;
  results: InatObservation[];
}

const limiter = new RateLimiter({ minIntervalMs: 1500, maxRetries: 5 });

async function fetchObsPage(
  taxonId: number,
  bbox: { swlat: number; swlng: number; nelat: number; nelng: number },
  page: number,
  perPage: number,
): Promise<InatObservation[]> {
  const params = new URLSearchParams({
    taxon_id: String(taxonId),
    quality_grade: 'research',
    captive: 'false',
    photos: 'true',
    swlat: String(bbox.swlat),
    swlng: String(bbox.swlng),
    nelat: String(bbox.nelat),
    nelng: String(bbox.nelng),
    per_page: String(perPage),
    page: String(page),
    order: 'desc',
    order_by: 'created_at',
  });

  const url = `${INAT_API}/observations?${params}`;
  const data = await limiter.fetchJson<InatObsResponse>(url);
  return data.results ?? [];
}

export async function runInatObservationsEtl(): Promise<void> {
  const startedAt = Date.now();
  logger.info('Starting iNaturalist research-grade observations ETL (v2 — global)');

  const supabase = getSupabase();
  const systemUserId = process.env.ETL_SYSTEM_USER_ID;
  if (!systemUserId) throw new Error('ETL_SYSTEM_USER_ID is required');
  await assertSystemUserExists(supabase, systemUserId);

  const regions = resolveRegions('INAT_OBS_REGIONS');
  logger.info(`iNat regions: ${regions.map((r) => r.name).join(', ')}`);

  const globalMaxOverride = process.env.INAT_OBS_MAX_RECORDS
    ? Number(process.env.INAT_OBS_MAX_RECORDS)
    : null;

  const PER_PAGE = 200;
  const byUuid = new Map<string, InatObservation>();
  let totalFetched = 0;

  // Phase 1: collect all observations across regions × taxon groups
  for (const region of regions) {
    for (const group of MARINE_TAXON_GROUPS) {
      const maxRecords = globalMaxOverride ?? group.maxRecords;
      const maxPages = Math.ceil(maxRecords / PER_PAGE);

      let pageNum = 1;
      const groupObs = await paginate(
        async (offset) => {
          const page = await fetchObsPage(group.id, region.bbox, pageNum, PER_PAGE);
          pageNum += 1;
          if (offset + page.length >= maxRecords) {
            return page.slice(0, Math.max(0, maxRecords - offset));
          }
          return page;
        },
        PER_PAGE,
        maxPages,
      );

      let skippedAccuracy = 0;
      for (const obs of groupObs) {
        if (!obs.latitude || !obs.longitude || !obs.taxon) continue;
        if (obs.positional_accuracy != null && obs.positional_accuracy > MAX_COORD_ACCURACY_M) {
          skippedAccuracy++;
          continue;
        }
        if (!obs.uuid) continue;
        byUuid.set(obs.uuid, obs);
      }
      totalFetched += groupObs.length;
    }
  }

  const observations = [...byUuid.values()];
  logger.info(`iNat: ${observations.length} unique research-grade observations across ${regions.length} regions`);

  // Phase 2: build species rows
  const speciesRows: Record<string, unknown>[] = [];
  const obsById = new Map<string, InatObservation>();

  for (const obs of observations) {
    const taxon = obs.taxon!;
    obsById.set(obs.uuid, obs);

    speciesRows.push({
      scientific_name: taxon.name,
      inat_taxon_id: taxon.id,
      common_name: taxon.preferred_common_name ?? null,
      kingdom: 'Animalia',
      metadata: {
        source: 'inat',
        inat_taxon_id: taxon.id,
        iconic_taxon: taxon.iconic_taxon_name,
        wikipedia_url: taxon.wikipedia_url ?? null,
      },
    });
  }

  const speciesResult = await upsertBatch('species', speciesRows, 'scientific_name');

  // Build inat_taxon_id → DB species.id lookup
  const inatIds = [...new Set(speciesRows.map((r) => r.inat_taxon_id as number))];
  const { data: speciesLookup } = await supabase
    .from('species')
    .select('id, inat_taxon_id')
    .in('inat_taxon_id', inatIds);

  const idByInatId = new Map<number, string>(
    (speciesLookup ?? []).map((s) => [s.inat_taxon_id as number, s.id as string]),
  );

  // Phase 3: build sighting rows. Site linking is deferred to a single
  // set-based query (matchSightingsToSites) instead of one nearby_dive_sites
  // RPC per observation. Crucially, observations WITHOUT a nearby dive site
  // are no longer discarded — they keep their GPS-accurate location and are
  // linked in bulk (or clustered into open-water sites by reconciliation).
  const sightingRows: Record<string, unknown>[] = [];

  for (const obs of observations) {
    const speciesId = idByInatId.get(obs.taxon!.id);
    if (!speciesId) continue;

    const observedAt = normalizeObservedAt(obs.observed_on);
    if (!observedAt) continue;

    const photoUrl = obs.photos?.[0]?.url?.replace(/square\./, 'medium.') ?? null;

    sightingRows.push({
      user_id: systemUserId,
      dive_site_id: null,
      species_id: speciesId,
      observed_at: observedAt,
      depth_m: normalizeDepth(obs.depth),
      count: normalizeCount(obs.individual_count),
      confidence_level: 'verified',
      source: 'inat',
      external_id: obs.uuid,
      location: `SRID=4326;POINT(${obs.longitude!} ${obs.latitude!})`,
      notes: `Imported from iNaturalist observation ${obs.id}`,
      ...(photoUrl ? { photo_urls: [photoUrl] } : {}),
    });
  }

  const sightingResult = await upsertBatch('sightings', sightingRows, 'source,external_id');

  // Link all freshly-imported iNaturalist sightings to nearby dive sites.
  await matchSightingsToSites(supabase, 'inat', 15);

  logJobSummary('inat-observations', {
    processed: totalFetched,
    upserted: speciesResult.upserted + sightingResult.upserted,
    skipped: speciesResult.skipped + sightingResult.skipped,
    errors: [...speciesResult.errors, ...sightingResult.errors],
  });

  logger.info(`iNat observations ETL finished in ${Date.now() - startedAt}ms`);
}

if (isMainModule(import.meta.url)) {
  runInatObservationsEtl().catch((err) => {
    logger.error('iNat observations ETL failed', {
      error: err instanceof Error ? err.message : String(err),
    });
    process.exit(1);
  });
}
