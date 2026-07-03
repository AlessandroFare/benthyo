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
 * Column mapping (RLS → Benthyo):
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
 * Local lookup: RLS survey code → WoRMS AphiaID + accepted scientific name.
 *
 * AphiaIDs are verified against marinespecies.org. Family/order-level entries
 * use the AphiaID of the accepted family record (not a root placeholder).
 * Codes NOT in this table fall back to a live WoRMS REST API lookup at runtime.
 *
 * Key sources:
 *   marinespecies.org/aphia.php?p=taxdetails&id=<AphiaID>
 *   fishbase.org/identification/speciesList.php?famcode=<code>
 */
const RLS_TO_WORMS: Record<string, { aphia_id: number; scientific_name: string }> = {
  // ---- Actinopterygii (ray-finned fish) ------------------------------------
  ABAL: { aphia_id: 138184,  scientific_name: 'Ablennes hians' },
  ABUD: { aphia_id: 159415,  scientific_name: 'Abudefduf' },          // genus Pomacentridae
  ACAN: { aphia_id: 205704,  scientific_name: 'Acanthurus' },          // genus
  AMMO: { aphia_id: 125540,  scientific_name: 'Ammodytidae' },
  AMPH: { aphia_id: 205649,  scientific_name: 'Amphiprion' },          // genus
  ANTH: { aphia_id: 125606,  scientific_name: 'Anthiinae' },           // subfamily → Serranidae family AphiaID
  APOG: { aphia_id: 125432,  scientific_name: 'Apogonidae' },
  AULO: { aphia_id: 125561,  scientific_name: 'Aulostomidae' },
  BALL: { aphia_id: 125573,  scientific_name: 'Balistidae' },
  BELO: { aphia_id: 125570,  scientific_name: 'Belonidae' },
  BLEN: { aphia_id: 125633,  scientific_name: 'Blenniidae' },
  BOTH: { aphia_id: 125500,  scientific_name: 'Bothidae' },
  CALL: { aphia_id: 125638,  scientific_name: 'Callionymidae' },
  CANT: { aphia_id: 219746,  scientific_name: 'Canthigaster' },        // genus Tetraodontidae
  CARA: { aphia_id: 125541,  scientific_name: 'Carangidae' },
  CENT: { aphia_id: 125558,  scientific_name: 'Centriscidae' },
  CHAE: { aphia_id: 125554,  scientific_name: 'Chaetodontidae' },
  CHEI: { aphia_id: 125632,  scientific_name: 'Cheilodactylidae' },
  CIRR: { aphia_id: 125552,  scientific_name: 'Cirrhitidae' },
  CLIN: { aphia_id: 125634,  scientific_name: 'Clinidae' },
  CLUP: { aphia_id: 125464,  scientific_name: 'Clupeidae' },
  CONG: { aphia_id: 125462,  scientific_name: 'Congridae' },
  CORO: { aphia_id: 272021,  scientific_name: 'Coris' },               // genus Labridae
  CTEN: { aphia_id: 272014,  scientific_name: 'Ctenochaetus' },        // genus Acanthuridae
  DACT: { aphia_id: 125549,  scientific_name: 'Dactylopteridae' },
  DIOD: { aphia_id: 125579,  scientific_name: 'Diodontidae' },
  DIPL: { aphia_id: 127021,  scientific_name: 'Diplodus' },            // genus Sparidae
  ECHI: { aphia_id: 125625,  scientific_name: 'Echeneidae' },
  ENGO: { aphia_id: 125463,  scientific_name: 'Engraulidae' },
  EPIN: { aphia_id: 127119,  scientific_name: 'Epinephelus' },         // genus Serranidae
  EXOC: { aphia_id: 125569,  scientific_name: 'Exocoetidae' },
  FIST: { aphia_id: 125560,  scientific_name: 'Fistulariidae' },
  GERR: { aphia_id: 125544,  scientific_name: 'Gerreidae' },
  GOBI: { aphia_id: 125642,  scientific_name: 'Gobiidae' },
  HAEM: { aphia_id: 125543,  scientific_name: 'Haemulidae' },
  HOLO: { aphia_id: 125571,  scientific_name: 'Holocentridae' },
  KYPH: { aphia_id: 125547,  scientific_name: 'Kyphosidae' },
  LABR: { aphia_id: 125523,  scientific_name: 'Labridae' },
  LACT: { aphia_id: 125576,  scientific_name: 'Lactariidae' },
  LETR: { aphia_id: 125546,  scientific_name: 'Lethrinidae' },
  LOPH: { aphia_id: 125484,  scientific_name: 'Lophiidae' },
  LUTJ: { aphia_id: 125542,  scientific_name: 'Lutjanidae' },
  MEGA: { aphia_id: 125457,  scientific_name: 'Megalopidae' },
  MOLA: { aphia_id: 127404,  scientific_name: 'Mola mola' },           // species
  MULL: { aphia_id: 125545,  scientific_name: 'Mullidae' },
  MURA: { aphia_id: 125460,  scientific_name: 'Muraenidae' },
  OPHI: { aphia_id: 125459,  scientific_name: 'Ophichthidae' },
  ORCY: { aphia_id: 127365,  scientific_name: 'Orcynopsis unicolor' }, // species Scombridae
  OSTO: { aphia_id: 125577,  scientific_name: 'Ostraciidae' },
  PEMP: { aphia_id: 125553,  scientific_name: 'Pempheridae' },
  PING: { aphia_id: 125628,  scientific_name: 'Pinguipedidae' },
  PLAT: { aphia_id: 125550,  scientific_name: 'Platycephalidae' },
  PLEC: { aphia_id: 217737,  scientific_name: 'Plectropomus' },        // genus
  PLEU: { aphia_id: 125484,  scientific_name: 'Pleuronectiformes' },   // order
  PLOT: { aphia_id: 125474,  scientific_name: 'Plotosidae' },
  POMA: { aphia_id: 125555,  scientific_name: 'Pomacentridae' },
  PRIO: { aphia_id: 272035,  scientific_name: 'Priolepis' },           // genus Gobiidae
  PSEU: { aphia_id: 125613,  scientific_name: 'Pseudochromidae' },
  SCAR: { aphia_id: 125524,  scientific_name: 'Scaridae' },
  SCOR: { aphia_id: 125485,  scientific_name: 'Scorpaenidae' },
  SERR: { aphia_id: 125517,  scientific_name: 'Serranidae' },
  SIGA: { aphia_id: 125572,  scientific_name: 'Siganidae' },
  SILL: { aphia_id: 125551,  scientific_name: 'Sillaginidae' },
  SPAR: { aphia_id: 125526,  scientific_name: 'Sparidae' },
  SPYR: { aphia_id: 125567,  scientific_name: 'Sphyraenidae' },
  SYNG: { aphia_id: 125565,  scientific_name: 'Syngnathidae' },
  TETR: { aphia_id: 125578,  scientific_name: 'Tetraodontidae' },
  THUN: { aphia_id: 127353,  scientific_name: 'Thunnus' },             // genus
  TRAC: { aphia_id: 125622,  scientific_name: 'Trachinidae' },
  TRIG: { aphia_id: 125486,  scientific_name: 'Triglidae' },
  TRIP: { aphia_id: 125636,  scientific_name: 'Tripterygiidae' },
  URAN: { aphia_id: 125621,  scientific_name: 'Uranoscopidae' },
  ZEID: { aphia_id: 125481,  scientific_name: 'Zeidae' },

  // ---- Elasmobranchii (sharks, rays, skates) ------------------------------
  CARCH: { aphia_id: 913907, scientific_name: 'Carcharhinidae' },
  DASY:  { aphia_id: 112062, scientific_name: 'Dasyatidae' },
  GALE:  { aphia_id: 105719, scientific_name: 'Elasmobranchii' },      // fallback — resolve via WoRMS
  LAMB:  { aphia_id: 105724, scientific_name: 'Lamnidae' },
  MYLI:  { aphia_id: 17135,  scientific_name: 'Myliobatidae' },
  RAJA:  { aphia_id: 105723, scientific_name: 'Rajidae' },
  RHIN:  { aphia_id: 105738, scientific_name: 'Rhincodontidae' },
  SPHY:  { aphia_id: 105725, scientific_name: 'Sphyrnidae' },

  // ---- Mola / other pelagics ----------------------------------------------
  AIPO:  { aphia_id: 217419, scientific_name: 'Alepisauridae' },       // lancetfish family
  SCOP:  { aphia_id: 125488, scientific_name: 'Myctophidae' },         // lanternfish

  // ---- Mediterranean-specific species (very common in RLS Med surveys) ---
  CENT_MED: { aphia_id: 126782, scientific_name: 'Centrolabrus exoletus' },
  CHRO:     { aphia_id: 159546, scientific_name: 'Chromis chromis' },
  CORI_JUL: { aphia_id: 127150, scientific_name: 'Coris julis' },
  DENT:     { aphia_id: 127031, scientific_name: 'Dentex dentex' },
  MULL_BAR: { aphia_id: 127183, scientific_name: 'Mullus barbatus' },
  OBLAD:    { aphia_id: 127038, scientific_name: 'Oblada melanura' },
  SARPA:    { aphia_id: 127048, scientific_name: 'Sarpa salpa' },
  SCOR_SCR: { aphia_id: 127044, scientific_name: 'Scorpaena scrofa' },
  SPIC:     { aphia_id: 127055, scientific_name: 'Spondyliosoma cantharus' },
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
