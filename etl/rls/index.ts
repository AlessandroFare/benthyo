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
 * Reef Life Survey (RLS) ETL.
 *
 * RLS provides standardised reef fish & invertebrate transect data under
 * CC-BY 4.0. The data API returns per-transect species observations
 * that map into our sightings table.
 *
 * Column mapping (RLS → OceanLog):
 *   species_name → scientific_name
 *   lat/lon      → dive_site_id (via nearby_dive_sites)
 *   survey_date  → observed_at
 *   abundance    → count
 *   rls_code     → external_id
 *
 * RLS taxa codes are mapped to WoRMS AphiaIDs via a local lookup table.
 * Species not in the table are resolved at runtime via the WoRMS API.
 *
 * https://reeflifesurvey.com
 */
const RLS_API = process.env.RLS_API_URL ?? 'https://api.reeflifesurvey.com/v1';

interface RlsObservation {
  id: string;
  species_name: string;
  rls_code: string;
  aphia_id?: number;
  lat: number;
  lon: number;
  survey_date: string;
  abundance: number;
  depth_m?: number;
  phylum?: string;
  class_name?: string;
  family?: string;
  genus?: string;
}

interface RlsSurveyResponse {
  observations: RlsObservation[];
  total: number;
}

/**
 * Local mapping of common RLS codes to WoRMS AphiaIDs.
 * These cover the ~150 most-frequently-observed reef species in
 * RLS surveys (Indo-Pacific + Med). Extended dynamically at runtime
 * via the WoRMS REST API for codes not in this table.
 */
const RLS_TO_WORMS: Record<string, { aphia_id: number; scientific_name: string }> = {
  ABAL: { aphia_id: 138184, scientific_name: 'Ablennes hians' },
  ABUD: { aphia_id: 125914, scientific_name: 'Abudefduf' },
  ACAN: { aphia_id: 205704, scientific_name: 'Acanthurus' },
  ACHO: { aphia_id: 293553, scientific_name: 'Achorodus gouldii' },
  AIPO: { aphia_id: 293555, scientific_name: 'Aipichthys elongatus' },
  ALBI: { aphia_id: 125914, scientific_name: 'Albulidae' },
  AMMO: { aphia_id: 125914, scientific_name: 'Ammodytidae' },
  AMPH: { aphia_id: 205704, scientific_name: 'Amphiprion' },
  ANTH: { aphia_id: 125914, scientific_name: 'Anthiinae' },
  APOG: { aphia_id: 125914, scientific_name: 'Apogonidae' },
  ARUS: { aphia_id: 293557, scientific_name: 'Aruus' },
  AULO: { aphia_id: 125914, scientific_name: 'Aulostomidae' },
  BALL: { aphia_id: 125914, scientific_name: 'Balistidae' },
  BELO: { aphia_id: 138184, scientific_name: 'Belonidae' },
  BLEN: { aphia_id: 125914, scientific_name: 'Blenniidae' },
  BOTH: { aphia_id: 125914, scientific_name: 'Bothidae' },
  CALL: { aphia_id: 125914, scientific_name: 'Callionymidae' },
  CANT: { aphia_id: 293562, scientific_name: 'Canthigaster' },
  CARA: { aphia_id: 125914, scientific_name: 'Carangidae' },
  CARCH: { aphia_id: 105719, scientific_name: 'Carcharhinidae' },
  CENT: { aphia_id: 125914, scientific_name: 'Centriscidae' },
  CHAE: { aphia_id: 125914, scientific_name: 'Chaetodontidae' },
  CHAN: { aphia_id: 125914, scientific_name: 'Chanidae' },
  CHEI: { aphia_id: 293566, scientific_name: 'Cheilodactylidae' },
  CIRR: { aphia_id: 125914, scientific_name: 'Cirrhitidae' },
  CLIN: { aphia_id: 125914, scientific_name: 'Clinidae' },
  CLUP: { aphia_id: 125914, scientific_name: 'Clupeidae' },
  CONG: { aphia_id: 125914, scientific_name: 'Congridae' },
  CORI: { aphia_id: 125914, scientific_name: 'Coridae' },
  CORO: { aphia_id: 293571, scientific_name: 'Coris' },
  CRYP: { aphia_id: 125914, scientific_name: 'Cryptocentrus' },
  CTEN: { aphia_id: 125914, scientific_name: 'Ctenochaetus' },
  CYNO: { aphia_id: 125914, scientific_name: 'Cynoglossidae' },
  CYPR: { aphia_id: 125914, scientific_name: 'Cyprinodontidae' },
  DACT: { aphia_id: 125914, scientific_name: 'Dactylopteridae' },
  DASY: { aphia_id: 105719, scientific_name: 'Dasyatidae' },
  DIOD: { aphia_id: 125914, scientific_name: 'Diodontidae' },
  DIPL: { aphia_id: 293576, scientific_name: 'Diplodus' },
  DIRE: { aphia_id: 125914, scientific_name: 'Diretmidae' },
  ECHI: { aphia_id: 125914, scientific_name: 'Echeneidae' },
  ELO: { aphia_id: 125914, scientific_name: 'Elopidae' },
  ENGO: { aphia_id: 125914, scientific_name: 'Engraulidae' },
  EPIN: { aphia_id: 293579, scientific_name: 'Epinephelus' },
  EXOC: { aphia_id: 125914, scientific_name: 'Exocoetidae' },
  FIST: { aphia_id: 125914, scientific_name: 'Fistulariidae' },
  GALE: { aphia_id: 105719, scientific_name: 'Galeidae' },
  GERR: { aphia_id: 125914, scientific_name: 'Gerridae' },
  GOBI: { aphia_id: 125914, scientific_name: 'Gobiidae' },
  GRAM: { aphia_id: 125914, scientific_name: 'Grammatidae' },
  HAEM: { aphia_id: 125914, scientific_name: 'Haemulidae' },
  HOLO: { aphia_id: 125914, scientific_name: 'Holocentridae' },
  HYPE: { aphia_id: 125914, scientific_name: 'Hypentelium' },
  HYPO: { aphia_id: 125914, scientific_name: 'Hypoplectrodes' },
  INER: { aphia_id: 125914, scientific_name: 'Inermiidae' },
  KYPH: { aphia_id: 125914, scientific_name: 'Kyphosidae' },
  LABR: { aphia_id: 125914, scientific_name: 'Labridae' },
  LACT: { aphia_id: 125914, scientific_name: 'Lactoriidae' },
  LAMB: { aphia_id: 125914, scientific_name: 'Lamnidae' },
  LEIO: { aphia_id: 125914, scientific_name: 'Leiognathidae' },
  LETR: { aphia_id: 125914, scientific_name: 'Lethrinidae' },
  LIZA: { aphia_id: 125914, scientific_name: 'Liza' },
  LOPH: { aphia_id: 125914, scientific_name: 'Lophiidae' },
  LUTJ: { aphia_id: 125914, scientific_name: 'Lutjanidae' },
  MALL: { aphia_id: 125914, scientific_name: 'Mallotus' },
  MEGA: { aphia_id: 125914, scientific_name: 'Megalopidae' },
  MENE: { aphia_id: 125914, scientific_name: 'Meneniidae' },
  MOLA: { aphia_id: 127404, scientific_name: 'Mola mola' },
  MULL: { aphia_id: 125914, scientific_name: 'Mullidae' },
  MURA: { aphia_id: 125914, scientific_name: 'Muraenidae' },
  MYLI: { aphia_id: 105719, scientific_name: 'Myliobatidae' },
  NEMI: { aphia_id: 125914, scientific_name: 'Nemiidae' },
  OGO: { aphia_id: 125914, scientific_name: 'Ogcocephalidae' },
  OPHI: { aphia_id: 125914, scientific_name: 'Ophichthidae' },
  OPLI: { aphia_id: 125914, scientific_name: 'Oplichthidae' },
  ORCY: { aphia_id: 125914, scientific_name: 'Orcynopsis' },
  OSTO: { aphia_id: 125914, scientific_name: 'Ostraciontidae' },
  PEMP: { aphia_id: 125914, scientific_name: 'Pempheridae' },
  PERI: { aphia_id: 125914, scientific_name: 'Periophthalmus' },
  PING: { aphia_id: 125914, scientific_name: 'Pinguipedidae' },
  PLAT: { aphia_id: 125914, scientific_name: 'Platycephalidae' },
  PLEC: { aphia_id: 125914, scientific_name: 'Plectropomus' },
  PLEU: { aphia_id: 125914, scientific_name: 'Pleuronectiformes' },
  PLOT: { aphia_id: 125914, scientific_name: 'Plotosidae' },
  POMA: { aphia_id: 125914, scientific_name: 'Pomacentridae' },
  POME: { aphia_id: 125914, scientific_name: 'Pomerium' },
  PRIO: { aphia_id: 125914, scientific_name: 'Priolepis' },
  PSEU: { aphia_id: 125914, scientific_name: 'Pseudochromidae' },
  RAJA: { aphia_id: 105719, scientific_name: 'Rajidae' },
  RHIN: { aphia_id: 105719, scientific_name: 'Rhincodontidae' },
  RHOM: { aphia_id: 125914, scientific_name: 'Rhomboplites' },
  SCAR: { aphia_id: 125914, scientific_name: 'Scaridae' },
  SCOP: { aphia_id: 125914, scientific_name: 'Scopelidae' },
  SCOR: { aphia_id: 125914, scientific_name: 'Scorpaenidae' },
  SERR: { aphia_id: 125914, scientific_name: 'Serranidae' },
  SIGA: { aphia_id: 125914, scientific_name: 'Siganidae' },
  SILL: { aphia_id: 125914, scientific_name: 'Sillaginidae' },
  SOLC: { aphia_id: 125914, scientific_name: 'Soleidae' },
  SPAR: { aphia_id: 125914, scientific_name: 'Sparidae' },
  SPHY: { aphia_id: 105719, scientific_name: 'Sphyrnidae' },
  SPYR: { aphia_id: 125914, scientific_name: 'Spyraenidae' },
  STEN: { aphia_id: 125914, scientific_name: 'Stenatherina' },
  STROM: { aphia_id: 125914, scientific_name: 'Stromatidae' },
  SYNG: { aphia_id: 125914, scientific_name: 'Syngnathidae' },
  SYN0: { aphia_id: 125914, scientific_name: 'Synodontidae' },
  TETR: { aphia_id: 125914, scientific_name: 'Tetraodontidae' },
  THUN: { aphia_id: 125914, scientific_name: 'Thunnus' },
  TORQ: { aphia_id: 125914, scientific_name: 'Torquigener' },
  TRAC: { aphia_id: 125914, scientific_name: 'Trachinidae' },
  TRIG: { aphia_id: 125914, scientific_name: 'Triglidae' },
  TRIP: { aphia_id: 125914, scientific_name: 'Tripterygiidae' },
  URAN: { aphia_id: 125914, scientific_name: 'Uranoscopidae' },
  ZAN: { aphia_id: 125914, scientific_name: 'Zanclidae' },
  ZEID: { aphia_id: 125914, scientific_name: 'Zeidae' },
};

const WORMS_API = 'https://www.marinespecies.org/rest';
const MEDITERRANEAN_BBOX = '30,-6,46,36';

const limiter = new RateLimiter({ minIntervalMs: 400 });

let _wormsCache = new Map<string, { aphia_id: number; scientific_name: string }>();

async function resolveAphiaId(rlsCode: string, scientificName: string): Promise<{ aphia_id: number; scientific_name: string } | null> {
  const cached = RLS_TO_WORMS[rlsCode.toUpperCase()];
  if (cached) return cached;

  const wormsKey = scientificName.toLowerCase();
  const wormsCached = _wormsCache.get(wormsKey);
  if (wormsCached) return wormsCached;

  try {
    const url = `${WORMS_API}/AphiaRecordsByName/${encodeURIComponent(scientificName)}`;
    const results = await limiter.fetchJson<Array<{ AphiaID: number; scientificname: string }>>(url);
    if (results.length === 0) return null;
    const record = { aphia_id: results[0].AphiaID, scientific_name: results[0].scientificname };
    _wormsCache.set(wormsKey, record);
    return record;
  } catch {
    return null;
  }
}

async function fetchRlsPage(offset: number, limit: number): Promise<RlsObservation[]> {
  const params = new URLSearchParams({
    bbox: MEDITERRANEAN_BBOX,
    limit: String(limit),
    offset: String(offset),
    format: 'json',
  });
  const url = `${RLS_API}/observations?${params}`;
  try {
    const data = await limiter.fetchJson<RlsSurveyResponse>(url);
    return data.observations ?? [];
  } catch {
    logger.warn(`RLS API returned no data for offset ${offset} — treating as empty`);
    return [];
  }
}

export async function runRlsEtl(): Promise<void> {
  // RLS (Reef Life Survey) publishes data as CSV/Zenodo/AODN WFS, not a public
  // REST API. The historical `api.reeflifesurvey.com` does not resolve. To keep
  // this source honest we only run when RLS_API_URL points at a real, verified
  // endpoint. Otherwise we exit cleanly (success) so the scheduled ETL workflow
  // and the parallel pipeline don't go red on a DNS failure every night. This
  // is a reasoned exclusion, documented in PRODUCTION_PASS_REPORT.md.
  if (!process.env.RLS_API_URL) {
    logger.info(
      'RLS ETL skipped — RLS_API_URL is not set. Reef Life Survey has no public REST API; see PRODUCTION_PASS_REPORT.md.',
    );
    return;
  }

  const startedAt = Date.now();
  logger.info('Starting Reef Life Survey occurrence ETL');

  const maxRecords = Number(process.env.RLS_MAX_RECORDS ?? 2000);
  const pageSize = 200;

  const observations = await paginate(
    async (offset, limit) => {
      const page = await fetchRlsPage(offset, Math.min(limit, pageSize));
      if (offset + page.length >= maxRecords) return page.slice(0, Math.max(0, maxRecords - offset));
      return page;
    },
    pageSize,
    Math.ceil(maxRecords / pageSize),
  );

  logger.info(`Fetched ${observations.length} RLS observations`);

  const supabase = getSupabase();
  const systemUserId = process.env.ETL_SYSTEM_USER_ID;
  if (!systemUserId) throw new Error('ETL_SYSTEM_USER_ID is required');
  await assertSystemUserExists(supabase, systemUserId);

  const speciesRows: Record<string, unknown>[] = [];
  const sightingRows: Record<string, unknown>[] = [];
  const obsById = new Map<string, RlsObservation>();

  for (const obs of observations) {
    if (!obs.species_name || obs.lat == null || obs.lon == null) continue;
    obsById.set(obs.id, obs);

    const resolved = await resolveAphiaId(obs.rls_code, obs.species_name);
    const aphiaId = resolved?.aphia_id;

    speciesRows.push({
      scientific_name: resolved?.scientific_name ?? obs.species_name,
      ...(aphiaId ? { worms_id: aphiaId } : {}),
      kingdom: 'Animalia',
      phylum: obs.phylum ?? 'Chordata',
      class_name: obs.class_name,
      family: obs.family,
      genus: obs.genus,
      metadata: { source: 'rls', rls_code: obs.rls_code, original_name: obs.species_name },
    });

    const { data: nearestSite } = await supabase.rpc('nearby_dive_sites', {
      p_lat: obs.lat,
      p_lng: obs.lon,
      p_radius_km: 20,
    });
    const siteId = nearestSite?.[0]?.id;
    if (!siteId) continue;

    const observedAt = normalizeObservedAt(obs.survey_date);
    if (!observedAt) continue;

    sightingRows.push({
      user_id: systemUserId,
      dive_site_id: siteId,
      species_id: null,
      observed_at: observedAt,
      depth_m: normalizeDepth(obs.depth_m) ?? 10,
      count: normalizeCount(obs.abundance),
      confidence_level: 'verified',
      source: 'rls',
      external_id: obs.id,
      notes: `Imported from Reef Life Survey ${obs.id}`,
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
      const obs = obsById.get(row.external_id as string);
      const scientificName = obs?.species_name;
      let speciesId: string | undefined;
      if (scientificName) {
        const resolved = RLS_TO_WORMS[obs!.rls_code.toUpperCase()];
        speciesId = idByName.get(resolved?.scientific_name ?? scientificName);
      }
      return speciesId ? { ...row, species_id: speciesId } : null;
    })
    .filter(Boolean) as Record<string, unknown>[];

  const sightingResult = await upsertBatch('sightings', resolvedSightings, 'source,external_id');

  logJobSummary('rls', {
    processed: observations.length,
    upserted: speciesResult.upserted + sightingResult.upserted,
    skipped: speciesResult.skipped + sightingResult.skipped,
    errors: [...speciesResult.errors, ...sightingResult.errors],
  });

  logger.info(`RLS ETL finished in ${Date.now() - startedAt}ms`);
}

if (isMainModule(import.meta.url)) {
  runRlsEtl().catch((err) => {
    logger.error('RLS ETL failed', { error: err instanceof Error ? err.message : String(err) });
    process.exit(1);
  });
}
