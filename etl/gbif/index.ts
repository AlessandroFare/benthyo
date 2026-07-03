import 'dotenv/config';
import type { ConservationStatus } from '@benthyo/types';
import { logger, logJobSummary } from '../shared/logger';
import { paginate, RateLimiter } from '../shared/rate-limiter';
import { getSupabase, upsertBatch } from '../shared/supabase';
import { isMainModule } from '../shared/cli';

const GBIF_API = 'https://api.gbif.org/v1';
const MEDITERRANEAN_WKT =
  'POLYGON((-6 30, 36 30, 36 46, -6 46, -6 30))';

interface GbifOccurrence {
  key: number;
  scientificName?: string;
  speciesKey?: number;
  decimalLatitude?: number;
  decimalLongitude?: number;
  eventDate?: string;
  individualCount?: number;
  depth?: number;
  countryCode?: string;
  basisOfRecord?: string;
}

interface GbifSearchResponse {
  results: GbifOccurrence[];
  count: number;
  endOfRecords: boolean;
}

interface GbifSpeciesMatch {
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

const limiter = new RateLimiter({ minIntervalMs: 250 });

function mapConservationStatus(iucn?: string): ConservationStatus | null {
  if (!iucn) return null;
  const map: Record<string, ConservationStatus> = {
    LC: 'LC',
    NT: 'NT',
    VU: 'VU',
    EN: 'EN',
    CR: 'CR',
    DD: 'DD',
    NE: 'NE',
  };
  return map[iucn.toUpperCase()] ?? null;
}

async function fetchOccurrences(limit: number, offset: number): Promise<GbifOccurrence[]> {
  const params = new URLSearchParams();
  params.append('geometry', MEDITERRANEAN_WKT);
  params.append('hasCoordinate', 'true');
  params.append('hasGeospatialIssue', 'false');
  params.append('basisOfRecord', 'HUMAN_OBSERVATION');
  params.append('basisOfRecord', 'MACHINE_OBSERVATION');
  params.append('limit', String(limit));
  params.append('offset', String(offset));

  const url = `${GBIF_API}/occurrence/search?${params}`;
  const data = await limiter.fetchJson<GbifSearchResponse>(url);
  return data.results ?? [];
}

async function matchSpecies(scientificName: string): Promise<GbifSpeciesMatch | null> {
  const params = new URLSearchParams({ name: scientificName, kingdom: 'Animalia' });
  const url = `${GBIF_API}/species/match?${params}`;
  try {
    return await limiter.fetchJson<GbifSpeciesMatch>(url);
  } catch {
    return null;
  }
}

export async function runGbifEtl(): Promise<void> {
  const startedAt = Date.now();
  logger.info('Starting GBIF Mediterranean occurrence ETL');

  const maxRecords = Number(process.env.GBIF_MAX_RECORDS ?? 5000);
  const pageSize = 300;

  const occurrences = await paginate(
    async (offset, limit) => {
      const page = await fetchOccurrences(Math.min(limit, pageSize), offset);
      if (offset + page.length >= maxRecords) {
        return page.slice(0, Math.max(0, maxRecords - offset));
      }
      return page;
    },
    pageSize,
    Math.ceil(maxRecords / pageSize),
  );

  logger.info(`Fetched ${occurrences.length} GBIF occurrences`);

  const speciesCache = new Map<string, GbifSpeciesMatch>();
  const speciesRows: Record<string, unknown>[] = [];
  const pendingSightings: Array<{ occ: GbifOccurrence; row: Record<string, unknown> }> = [];
  const errors: string[] = [];

  const supabase = getSupabase();
  const systemUserId = process.env.ETL_SYSTEM_USER_ID;

  if (!systemUserId) {
    throw new Error('ETL_SYSTEM_USER_ID is required for sighting imports');
  }

  for (const occ of occurrences) {
    if (!occ.scientificName || occ.decimalLatitude == null || occ.decimalLongitude == null) {
      continue;
    }

    let match = speciesCache.get(occ.scientificName);
    if (!match) {
      match = (await matchSpecies(occ.scientificName)) ?? undefined;
      if (match) speciesCache.set(occ.scientificName, match);
    }

    const gbifKey = match?.usageKey ?? occ.speciesKey;
    if (gbifKey) {
      speciesRows.push({
        scientific_name: match?.scientificName ?? occ.scientificName,
        gbif_taxon_key: gbifKey,
        kingdom: match?.kingdom ?? 'Animalia',
        phylum: match?.phylum,
        class_name: match?.class,
        order_name: match?.order,
        family: match?.family,
        genus: match?.genus,
        conservation_status: mapConservationStatus(match?.iucnRedListCategory ?? undefined),
        metadata: { source: 'gbif', gbif_occurrence_key: occ.key },
      });
    }

    const { data: nearestSite } = await supabase.rpc('nearby_dive_sites', {
      p_lat: occ.decimalLatitude,
      p_lng: occ.decimalLongitude,
      p_radius_km: 25,
    });

    const siteId = nearestSite?.[0]?.id;
    if (!siteId) continue;

    pendingSightings.push({
      occ,
      row: {
        user_id: systemUserId,
        dive_site_id: siteId,
        observed_at: occ.eventDate ?? new Date().toISOString(),
        depth_m: occ.depth,
        count: occ.individualCount ?? 1,
        confidence_level: 'likely',
        source: 'gbif',
        external_id: String(occ.key),
        notes: `Imported from GBIF occurrence ${occ.key}`,
      },
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

  const resolvedSightings = pendingSightings
    .map(({ occ, row }) => {
      const speciesId = idByName.get(occ.scientificName!);
      return speciesId ? { ...row, species_id: speciesId } : null;
    })
    .filter(Boolean) as Record<string, unknown>[];

  const sightingResult = await upsertBatch(
    'sightings',
    resolvedSightings,
    'source,external_id',
  );

  const summary = {
    processed: occurrences.length,
    upserted: speciesResult.upserted + sightingResult.upserted,
    skipped: speciesResult.skipped + sightingResult.skipped,
    errors: [...speciesResult.errors, ...sightingResult.errors, ...errors],
  };

  logJobSummary('gbif', summary);
  logger.info(`GBIF ETL finished in ${Date.now() - startedAt}ms`);
}

if (isMainModule(import.meta.url)) {
  runGbifEtl().catch((err) => {
    logger.error('GBIF ETL failed', { error: err instanceof Error ? err.message : String(err) });
    process.exit(1);
  });
}
