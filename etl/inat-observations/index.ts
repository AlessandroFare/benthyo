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

/**
 * iNaturalist Research-Grade Observations ETL — Mediterranean marine species.
 *
 * Pulls only `quality_grade=research` observations (community-verified, GPS-
 * accurate, species-level ID) from the iNaturalist v1 REST API, restricted to:
 *
 *   - The Mediterranean bounding box (swlat=30, swlng=-6, nelat=46, nelng=36)
 *   - Marine / aquatic higher taxa (fish, elasmobranchi, cephalopods,
 *     echinoderms, cnidarians, nudibranchia, marine reptiles, marine mammals)
 *   - `photos=true` so every sighting has at least one image
 *   - `captive=false` (wild observations only)
 *
 * iNaturalist API: https://api.inaturalist.org/v1/observations
 * Rate limit: ≤ 100 req/min for anonymous, we use 1 500 ms inter-request gap.
 *
 * Data flow:
 *   1. For each marine taxon group, fetch pages of observations.
 *   2. Deduplicate by `uuid` (iNat's stable cross-call ID).
 *   3. Upsert species rows (scientific_name, inat_taxon_id, taxonomy).
 *   4. For each observation, call nearby_dive_sites() to find the closest site.
 *   5. Upsert sightings with source='inat' and external_id=obs.uuid.
 *
 * source='inat' keeps the dedup constraint (source, external_id) distinct from
 * GBIF/OBIS records that may share the same observation via cross-source linking.
 */

const INAT_API = process.env.INAT_API_BASE ?? 'https://api.inaturalist.org/v1';

// Mediterranean bounding box
const MED_BBOX = { swlat: 30, swlng: -6, nelat: 46, nelng: 36 };

/**
 * iNaturalist taxon IDs for marine groups in the Mediterranean.
 * These are the stable numeric IDs from iNaturalist, not GBIF keys.
 *
 *   47178  Actinopterygii (ray-finned fish)
 *   505527 Elasmobranchii (sharks, rays)
 *   47549  Mollusca (cephalopods, nudibranchs, bivalves)
 *   1228   Echinodermata
 *   47534  Cnidaria (jellyfish, corals, anemones)
 *   47119  Mammalia (marine mammals subset via location filter)
 *   39532  Testudines (sea turtles)
 *   47158  Crustacea (malacostraca — lobster, crab, shrimp)
 */
const MARINE_TAXON_GROUPS: Array<{ id: number; label: string; maxRecords: number }> = [
  { id: 47178,  label: 'Actinopterygii',   maxRecords: 2000 },
  { id: 505527, label: 'Elasmobranchii',   maxRecords: 500  },
  { id: 47549,  label: 'Mollusca',         maxRecords: 800  },
  { id: 1228,   label: 'Echinodermata',    maxRecords: 600  },
  { id: 47534,  label: 'Cnidaria',         maxRecords: 500  },
  { id: 47119,  label: 'Mammalia',         maxRecords: 300  },
  { id: 39532,  label: 'Testudines',       maxRecords: 200  },
  { id: 47158,  label: 'Crustacea',        maxRecords: 600  },
];

const MAX_COORD_ACCURACY_M = 500; // research-grade iNat obs usually < 500 m

interface InatTaxon {
  id: number;
  name: string;
  rank: string;
  preferred_common_name?: string;
  ancestry?: string; // slash-separated ancestor taxon IDs
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

// 1 500 ms gap to stay comfortably under anonymous rate limit (100 req/min)
const limiter = new RateLimiter({ minIntervalMs: 1500, maxRetries: 5 });

async function fetchObsPage(
  taxonId: number,
  page: number,
  perPage: number,
): Promise<InatObservation[]> {
  const params = new URLSearchParams({
    taxon_id: String(taxonId),
    quality_grade: 'research',
    captive: 'false',
    photos: 'true',
    swlat: String(MED_BBOX.swlat),
    swlng: String(MED_BBOX.swlng),
    nelat: String(MED_BBOX.nelat),
    nelng: String(MED_BBOX.nelng),
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
  logger.info('Starting iNaturalist research-grade observations ETL (Mediterranean)');

  const supabase = getSupabase();
  const systemUserId = process.env.ETL_SYSTEM_USER_ID;
  if (!systemUserId) throw new Error('ETL_SYSTEM_USER_ID is required');
  await assertSystemUserExists(supabase, systemUserId);

  const globalMaxOverride = process.env.INAT_OBS_MAX_RECORDS
    ? Number(process.env.INAT_OBS_MAX_RECORDS)
    : null;

  const PER_PAGE = 200; // iNat API max per_page
  const byUuid = new Map<string, InatObservation>();
  let totalFetched = 0;

  // Phase 1: collect all observations across taxon groups
  for (const group of MARINE_TAXON_GROUPS) {
    const maxRecords = globalMaxOverride ?? group.maxRecords;
    const maxPages = Math.ceil(maxRecords / PER_PAGE);
    logger.info(`iNat observations: fetching ${group.label} (max ${maxRecords})`);

    let pageNum = 1;
    const groupObs = await paginate(
      async (offset) => {
        const page = await fetchObsPage(group.id, pageNum, PER_PAGE);
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
    logger.info(`iNat ${group.label}: ${groupObs.length} fetched, ${skippedAccuracy} skipped (low accuracy)`);
    totalFetched += groupObs.length;
  }

  const observations = [...byUuid.values()];
  logger.info(`iNat: ${observations.length} unique research-grade observations after dedup`);

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

  // Phase 3: match to dive sites + build sighting rows
  const sightingRows: Record<string, unknown>[] = [];

  for (const obs of observations) {
    const speciesId = idByInatId.get(obs.taxon!.id);
    if (!speciesId) continue;

    const { data: nearestSite } = await supabase.rpc('nearby_dive_sites', {
      p_lat: obs.latitude!,
      p_lng: obs.longitude!,
      p_radius_km: 15, // iNat research-grade is GPS-accurate; 15 km is appropriate
    });
    const siteId = nearestSite?.[0]?.id;
    if (!siteId) continue;

    const observedAt = normalizeObservedAt(obs.observed_on);
    if (!observedAt) continue;

    const photoUrl = obs.photos?.[0]?.url?.replace(/square\./, 'medium.') ?? null;

    sightingRows.push({
      user_id: systemUserId,
      dive_site_id: siteId,
      species_id: speciesId,
      observed_at: observedAt,
      depth_m: normalizeDepth(obs.depth),
      count: normalizeCount(obs.individual_count),
      confidence_level: 'verified', // research-grade = community-verified
      source: 'inat',
      external_id: obs.uuid,
      notes: `Imported from iNaturalist observation ${obs.id}`,
      ...(photoUrl ? { photo_urls: [photoUrl] } : {}),
    });
  }

  const sightingResult = await upsertBatch('sightings', sightingRows, 'source,external_id');

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
