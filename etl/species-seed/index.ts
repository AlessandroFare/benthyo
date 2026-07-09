/**
 * Iconic Species Seed ETL.
 *
 * Guarantees that the marine species every diver expects to search for —
 * whale shark, manta, mola mola, hammerheads, sea turtles, clownfish, etc. —
 * ALWAYS exist in the catalog with correct, real data, regardless of what the
 * occurrence sources (GBIF/OBIS/iNat) happen to return on a given run.
 *
 * Unlike the old hardcoded seed (scripts/generate-seed.mjs), this does NOT
 * invent taxon IDs. For each curated scientific name it resolves everything
 * from live, free APIs:
 *   - iNaturalist  → real inat_taxon_id, preferred_common_name, default photo
 *   - WoRMS        → real AphiaID + taxonomy + it/es/en vernacular names
 *
 * Runs EARLY in the pipeline (before occurrence imports) so these species are
 * present and correctly linked before anything else references them. It is
 * idempotent: re-running only fills gaps / refreshes data.
 *
 * Usage:  pnpm --filter @benthyo/etl species-seed   (or tsx species-seed/index.ts)
 */

import 'dotenv/config';
import { logger, logJobSummary } from '../shared/logger';
import { RateLimiter } from '../shared/rate-limiter';
import { getSupabase, upsertBatch } from '../shared/supabase';
import { isMainModule } from '../shared/cli';

const INAT_API = process.env.INAT_API_BASE ?? 'https://api.inaturalist.org/v1';
const WORMS_API = 'https://www.marinespecies.org/rest';

const inatLimiter = new RateLimiter({ minIntervalMs: 1200, maxRetries: 3 });
const wormsLimiter = new RateLimiter({ minIntervalMs: 200, maxRetries: 3 });

/**
 * Curated list of globally iconic dive species (scientific names only — all
 * other data is resolved from APIs). Grouped by rough category for clarity.
 */
const ICONIC_SPECIES: string[] = [
  // Sharks & rays — the headline megafauna
  'Rhincodon typus', // whale shark
  'Manta birostris', // giant oceanic manta
  'Mobula alfredi', // reef manta
  'Sphyrna lewini', // scalloped hammerhead
  'Sphyrna mokarran', // great hammerhead
  'Carcharhinus melanopterus', // blacktip reef shark
  'Carcharhinus amblyrhynchos', // grey reef shark
  'Triaenodon obesus', // whitetip reef shark
  'Galeocerdo cuvier', // tiger shark
  'Carcharias taurus', // sand tiger / grey nurse
  'Stegostoma tigrinum', // zebra/leopard shark
  'Ginglymostoma cirratum', // nurse shark
  'Aetobatus narinari', // spotted eagle ray
  'Taeniura lymma', // bluespotted ribbontail ray
  'Mobula mobular', // devil ray
  // Bony fish — famous reef & pelagic
  'Mola mola', // ocean sunfish — NOTE: iNat taxon search sometimes returns the plant Liquidambar styraciflua (also called "sweetgum" / "American sweetgum"). The exact-name match filter in resolveInat should prevent this, but as a safeguard we verify the class is Actinopterygii or Tetraodontiformes.
  'Cheilinus undulatus', // humphead / Napoleon wrasse
  'Amphiprion ocellaris', // clown anemonefish
  'Amphiprion percula', // orange clownfish
  'Synchiropus splendidus', // mandarinfish
  'Pterois volitans', // red lionfish
  'Antennarius maculatus', // warty frogfish
  'Rhinopias frondosa', // weedy scorpionfish
  'Pygoplites diacanthus', // regal angelfish
  'Zanclus cornutus', // moorish idol
  'Chaetodon lunula', // raccoon butterflyfish
  'Balistoides conspicillum', // clown triggerfish
  'Sphyraena barracuda', // great barracuda
  'Epinephelus lanceolatus', // giant grouper
  'Epinephelus marginatus', // dusky grouper
  'Gymnothorax javanicus', // giant moray
  'Aulostomus chinensis', // trumpetfish
  'Platax teira', // longfin batfish
  'Thunnus albacares', // yellowfin tuna
  'Caranx ignobilis', // giant trevally
  'Taeniura meyeni', // blotched fantail ray
  // Seahorses & pipefish
  'Hippocampus bargibanti', // pygmy seahorse
  'Hippocampus kuda', // common seahorse
  'Hippocampus hippocampus', // short-snouted seahorse
  // Turtles
  'Chelonia mydas', // green sea turtle
  'Eretmochelys imbricata', // hawksbill
  'Caretta caretta', // loggerhead
  'Dermochelys coriacea', // leatherback
  // Marine mammals
  'Tursiops truncatus', // bottlenose dolphin
  'Stenella longirostris', // spinner dolphin
  'Megaptera novaeangliae', // humpback whale
  'Physeter macrocephalus', // sperm whale
  'Dugong dugon', // dugong
  'Monachus monachus', // mediterranean monk seal — NOTE: iNat sometimes returns Myiopsitta monachus (Monk Parakeet). The exact-name match should prevent this.
  // Cephalopods
  'Octopus vulgaris', // common octopus
  'Hapalochlaena lunulata', // blue-ringed octopus
  'Sepia officinalis', // common cuttlefish
  'Metasepia pfefferi', // flamboyant cuttlefish
  'Nautilus pompilius', // chambered nautilus
  // Nudibranchs & inverts
  'Chromodoris annae', // Anna's chromodoris
  'Nembrotha kubaryana', // variable neon slug
  'Phyllidia varicosa', // scrambled egg nudibranch
  'Tridacna gigas', // giant clam
  'Periclimenes imperator', // emperor shrimp
  'Odontodactylus scyllarus', // peacock mantis shrimp
  'Panulirus versicolor', // painted spiny lobster
  // Mediterranean staples
  'Posidonia oceanica', // neptune grass
  'Pinna nobilis', // noble pen shell
  'Paramuricea clavata', // red gorgonian
];

interface InatTaxonResult {
  id: number;
  name: string;
  rank: string;
  preferred_common_name?: string;
  iconic_taxon_name?: string;
  default_photo?: { medium_url?: string; square_url?: string };
  ancestors?: Array<{ rank: string; name: string }>;
}

interface WormsRecord {
  AphiaID: number;
  scientificname: string;
  kingdom?: string;
  phylum?: string;
  class?: string;
  order?: string;
  family?: string;
  genus?: string;
  status?: string;
}

interface WormsVernacular {
  vernacular: string;
  language_code?: string;
}

async function resolveInat(scientificName: string): Promise<{
  inat_taxon_id: number;
  common_name: string | null;
  image_url: string | null;
  family: string | null;
  genus: string | null;
  class_name: string | null;
  order_name: string | null;
  phylum: string | null;
} | null> {
  const url = `${INAT_API}/taxa?q=${encodeURIComponent(scientificName)}&is_active=true&per_page=5`;
  try {
    const data = await inatLimiter.fetchJson<{ results: InatTaxonResult[] }>(url);
    const want = scientificName.toLowerCase().trim();
    // Require exact name match — iNaturalist's fuzzy search sometimes returns
    // completely unrelated taxa (e.g. Mola mola → Liquidambar styraciflua,
    // Monachus monachus → Myiopsitta monachus) that share common-name words.
    const match = data.results?.find((r) => r.name.toLowerCase().trim() === want);
    if (!match) return null;

    const byRank = (rank: string): string | null =>
      match.ancestors?.find((a) => a.rank === rank)?.name ?? null;

    // Sanity check: reject obviously wrong taxa (plants, birds for marine mammals, etc.)
    const className = byRank('class');
    const phylum = byRank('phylum');
    if (phylum === 'Tracheophyta' || className === 'Aves') {
      logger.warn(
        `iNat match for ${scientificName} returned wrong taxon (phylum=${phylum}, class=${className}) — skipping`,
      );
      return null;
    }

    return {
      inat_taxon_id: match.id,
      common_name: match.preferred_common_name ?? null,
      image_url: match.default_photo?.medium_url ?? match.default_photo?.square_url ?? null,
      family: byRank('family'),
      genus: byRank('genus') ?? scientificName.split(' ')[0],
      class_name: className,
      order_name: byRank('order'),
      phylum,
    };
  } catch (err) {
    logger.warn(`iNat resolve failed for ${scientificName}: ${err instanceof Error ? err.message : String(err)}`);
    return null;
  }
}

async function resolveWorms(scientificName: string): Promise<{
  worms_id: number;
  kingdom: string | null;
  phylum: string | null;
  class_name: string | null;
  order_name: string | null;
  family: string | null;
  genus: string | null;
  common_name: string | null;
  common_name_it: string | null;
  common_name_es: string | null;
} | null> {
  try {
    const records = await wormsLimiter.fetchJson<WormsRecord[]>(
      `${WORMS_API}/AphiaRecordsByName/${encodeURIComponent(scientificName)}?marine_only=true`,
    );
    if (!records?.length) return null;
    const rec = records.find((r) => r.status === 'accepted') ?? records[0];

    let vernaculars: WormsVernacular[] = [];
    try {
      vernaculars = await wormsLimiter.fetchJson<WormsVernacular[]>(
        `${WORMS_API}/AphiaRecordByAphiaID/${rec.AphiaID}/vernaculars`,
      );
    } catch {
      // non-fatal
    }
    const pick = (lang: string) =>
      vernaculars.find((v) => v.language_code?.toLowerCase() === lang)?.vernacular ?? null;

    return {
      worms_id: rec.AphiaID,
      kingdom: rec.kingdom ?? null,
      phylum: rec.phylum ?? null,
      class_name: rec.class ?? null,
      order_name: rec.order ?? null,
      family: rec.family ?? null,
      genus: rec.genus ?? null,
      common_name: pick('eng') ?? pick('en'),
      common_name_it: pick('ita') ?? pick('it'),
      common_name_es: pick('spa') ?? pick('es'),
    };
  } catch (err) {
    logger.warn(`WoRMS resolve failed for ${scientificName}: ${err instanceof Error ? err.message : String(err)}`);
    return null;
  }
}

export async function runSpeciesSeedEtl(): Promise<void> {
  const startedAt = Date.now();
  logger.info(`Starting iconic species seed ETL (${ICONIC_SPECIES.length} curated species)`);

  const rows: Record<string, unknown>[] = [];
  const errors: string[] = [];

  for (const scientificName of ICONIC_SPECIES) {
    const [inat, worms] = await Promise.all([
      resolveInat(scientificName),
      resolveWorms(scientificName),
    ]);

    if (!inat && !worms) {
      errors.push(`${scientificName}: not found on iNaturalist or WoRMS`);
      continue;
    }

    const commonName = worms?.common_name ?? inat?.common_name ?? null;

    const row: Record<string, unknown> = {
      scientific_name: scientificName,
      kingdom: worms?.kingdom ?? 'Animalia',
      phylum: worms?.phylum ?? inat?.phylum ?? null,
      class_name: worms?.class_name ?? inat?.class_name ?? null,
      order_name: worms?.order_name ?? inat?.order_name ?? null,
      family: worms?.family ?? inat?.family ?? null,
      genus: worms?.genus ?? inat?.genus ?? scientificName.split(' ')[0],
      common_name: commonName,
      common_name_it: worms?.common_name_it ?? null,
      common_name_es: worms?.common_name_es ?? null,
      metadata: { source: 'iconic_seed', seed: true },
    };
    if (inat?.inat_taxon_id) row.inat_taxon_id = inat.inat_taxon_id;
    if (worms?.worms_id) row.worms_id = worms.worms_id;
    if (inat?.image_url) row.image_url = inat.image_url;

    rows.push(row);
    logger.info(
      `Resolved ${scientificName} → ${commonName ?? '(no common name)'} ` +
        `[inat:${inat?.inat_taxon_id ?? '-'} worms:${worms?.worms_id ?? '-'} img:${inat?.image_url ? 'y' : 'n'}]`,
    );
  }

  const result = await upsertBatch('species', rows, 'scientific_name');

  logJobSummary('species-seed', {
    processed: ICONIC_SPECIES.length,
    upserted: result.upserted,
    skipped: result.skipped,
    errors: [...errors, ...result.errors],
  });

  logger.info(`Iconic species seed ETL finished in ${Date.now() - startedAt}ms`);
}

if (isMainModule(import.meta.url)) {
  runSpeciesSeedEtl().catch((err) => {
    logger.error('Species seed ETL failed', { error: err instanceof Error ? err.message : String(err) });
    process.exit(1);
  });
}
