/**
 * Dive Site Discovery ETL — v2 (LLM enumeration + Nominatim geocoding).
 *
 * The core problem: there is no free API listing every named dive site on
 * Earth. Map data (OSM/Overpass, OpenDiveMap) only covers a fraction, and
 * Google Maps crawling (Apify) is paid. The most effective zero-budget way to
 * enumerate *real* dive sites is exactly how a human would: ask a knowledgeable
 * source to list the diving destinations of a region, then the named sites at
 * each destination, then look up where each one is.
 *
 * Pipeline (all zero-cost):
 *   1. ENUMERATE — for every marine region, the OpenCode Zen LLM
 *      (deepseek-v4-flash-free) lists well-known diving destinations
 *      (e.g. "Malapascua", "Dahab", "Tulamben").
 *   2. EXPAND — for each destination, the LLM lists real, named dive sites
 *      with type / difficulty / depth / short description.
 *   3. GEOCODE — each site is resolved to coordinates via Nominatim
 *      (OpenStreetMap), biased to the region's bounding box so names like
 *      "Blue Hole" land in the right place.
 *   4. (optional) COMMONS — Wikimedia Commons geosearch adds extra candidate
 *      names from geotagged underwater photos, fed through the same geocoder.
 *
 * Discovered sites are stored unverified (verified=false, metadata.source =
 * 'dive_site_discovery') so moderators can review before they go public.
 *
 * Requires OPENCODE_ZEN_API_KEY (see etl/shared/llm.ts). Without it the step
 * logs a warning and no-ops instead of failing the pipeline.
 *
 * Usage:
 *   DISCOVERY_REGIONS=southeast_asia,red_sea pnpm dive-site-discovery
 *   DISCOVERY_REGIONS=all DISCOVERY_USE_COMMONS=1 pnpm dive-site-discovery
 */

import 'dotenv/config';
import { z } from 'zod';
import { logger, logJobSummary } from '../shared/logger';
import { RateLimiter } from '../shared/rate-limiter';
import { getSupabase, upsertBatch } from '../shared/supabase';
import { isMainModule } from '../shared/cli';
import { generateJson, isLlmConfigured, llmLabel } from '../shared/llm';
import { geocode } from '../shared/geocode';
import {
  geographyPoint,
  normalizeAccessType,
  normalizeCountryCode,
  normalizeDifficulty,
  normalizeSiteType,
  slugify,
  uniqueSlug,
  type DiveSiteRow,
} from '../shared/dive-site-utils';
import { resolveRegions, type MarineRegion } from '../shared/marine-regions';

// ── Config ──────────────────────────────────────────────────────────

const MAX_DESTINATIONS = Number(process.env.DISCOVERY_MAX_DESTINATIONS ?? 25);
const MAX_SITES_PER_DEST = Number(process.env.DISCOVERY_MAX_SITES_PER_DEST ?? 20);
const USE_COMMONS = process.env.DISCOVERY_USE_COMMONS === '1';
const COMMONS_API = process.env.COMMONS_API_URL ?? 'https://commons.wikimedia.org/w/api.php';
const USER_AGENT =
  process.env.WIKIMEDIA_USER_AGENT ?? 'Benthyo/1.0 (https://benthyo.com; contact@benthyo.com)';
const MAX_COMMONS_PHOTOS = Number(process.env.DISCOVERY_COMMONS_PHOTOS ?? 40);

/**
 * Human-readable context for each region so the LLM enumerates the right
 * geography. Keyed by MarineRegion.name (see shared/marine-regions.ts).
 */
const REGION_HINTS: Record<string, string> = {
  caribbean: 'the Caribbean Sea (Cozumel, Bonaire, Roatán, Belize, Cayman Islands, Bahamas, Turks & Caicos)',
  red_sea: 'the Red Sea (Egypt — Sharm el-Sheikh, Dahab, Marsa Alam, Hurghada; Sudan)',
  indian_ocean: 'the tropical Indian Ocean (Maldives, Sri Lanka, Andaman Islands, Thailand — Similan/Phuket)',
  southeast_asia: 'Southeast Asia (Indonesia — Bali, Komodo, Raja Ampat, Lembeh; Philippines — Malapascua, Anilao, Tubbataha; Malaysia — Sipadan)',
  australia_nz: 'Australia & New Zealand (Great Barrier Reef, Ningaloo, Poor Knights Islands)',
  pacific: 'the tropical Pacific (Palau, Micronesia — Chuuk/Truk, Fiji, French Polynesia, Hawaii, Galápagos)',
  mediterranean: 'the Mediterranean Sea (Italy, Malta, Croatia, Greece, Spain, France, Cyprus, Egypt north coast)',
  north_atlantic: 'the North Atlantic (Azores, Canary Islands, Florida, Caribbean fringe, US East Coast wrecks)',
  nordic: 'Nordic & northern European waters (Norway, Iceland — Silfra, Scotland — Scapa Flow)',
  east_africa: 'East Africa & western Indian Ocean (Mozambique, Tanzania — Zanzibar/Mafia, Kenya, South Africa — Sodwana/Aliwal, Seychelles, Mauritius)',
  japan_korea: 'Japan & Korea (Okinawa, Izu Peninsula, Jeju)',
};

// ── LLM schemas ─────────────────────────────────────────────────────

const DestinationsSchema = z.object({
  destinations: z
    .array(
      z.object({
        name: z.string().describe('Dive destination / area, e.g. "Malapascua"'),
        country: z.string().describe('Country name'),
      }),
    )
    .describe('Well-known scuba diving destinations in the region'),
});

const SitesSchema = z.object({
  sites: z
    .array(
      z.object({
        name: z.string().describe('The specific named dive site'),
        site_type: z
          .enum(['reef', 'wall', 'wreck', 'cave', 'pinnacle', 'muck', 'other'])
          .nullable(),
        difficulty: z
          .enum(['beginner', 'intermediate', 'advanced', 'technical'])
          .nullable(),
        depth_min: z.number().nullable(),
        depth_max: z.number().nullable(),
        access_type: z.enum(['shore', 'boat', 'liveaboard']).nullable(),
        description: z.string().nullable(),
      }),
    )
    .describe('Real, named dive sites at this destination'),
});

type LlmSite = z.infer<typeof SitesSchema>['sites'][number];

interface SiteCandidate {
  name: string;
  destination: string;
  country: string;
  region: MarineRegion;
  llm: LlmSite | null;
  discoverySource: 'llm' | 'commons';
}

// ── Approach 1: LLM enumeration ─────────────────────────────────────

async function enumerateDestinations(region: MarineRegion): Promise<Array<{ name: string; country: string }>> {
  const hint = REGION_HINTS[region.name] ?? region.name.replace(/_/g, ' ');
  const result = await generateJson(DestinationsSchema, {
    system:
      'You are a scuba-diving domain expert with encyclopedic knowledge of dive travel. ' +
      'You only list REAL, well-documented diving destinations. Never invent places.',
    prompt:
      `List up to ${MAX_DESTINATIONS} well-known scuba diving destinations or areas in ${hint}. ` +
      'Prefer destinations famous for named dive sites. Return distinct places (towns, islands, ' +
      'marine parks), not individual dive sites.',
    temperature: 0.3,
  });
  return result.destinations.slice(0, MAX_DESTINATIONS);
}

async function enumerateSites(
  destination: string,
  country: string,
  region: MarineRegion,
): Promise<SiteCandidate[]> {
  const result = await generateJson(SitesSchema, {
    system:
      'You are a scuba-diving domain expert. You list ONLY real, named dive sites that actually ' +
      'exist at the given destination. Never invent site names. If unsure about a numeric field, use null.',
    prompt:
      `List up to ${MAX_SITES_PER_DEST} real, named scuba dive sites at ${destination}, ${country}. ` +
      'For each: the exact site name divers use, its type, typical difficulty, min/max depth in metres, ' +
      'usual access (shore/boat/liveaboard) and a one-sentence description.',
    temperature: 0.3,
  });

  return result.sites.slice(0, MAX_SITES_PER_DEST).map((site) => ({
    name: site.name,
    destination,
    country,
    region,
    llm: site,
    discoverySource: 'llm' as const,
  }));
}

// ── Approach 2 (optional): Wikimedia Commons geosearch ──────────────

interface CommonsPage {
  pageid: number;
  title: string;
}

const commonsLimiter = new RateLimiter({ minIntervalMs: 400 });

async function commonsCandidateNames(region: MarineRegion): Promise<string[]> {
  const params = new URLSearchParams({
    action: 'query',
    list: 'geosearch',
    gsbbox: [region.bbox.nelat, region.bbox.swlng, region.bbox.swlat, region.bbox.nelng].join('|'),
    gsnamespace: '6',
    gslimit: String(MAX_COMMONS_PHOTOS),
    format: 'json',
    origin: '*',
  });
  try {
    const data = await commonsLimiter.fetchJson<{ query?: { geosearch?: CommonsPage[] } }>(
      `${COMMONS_API}?${params}`,
      { headers: { 'User-Agent': USER_AGENT } },
    );
    const titles = (data.query?.geosearch ?? [])
      .map((p) => p.title.replace(/^File:/, '').replace(/\.[a-z0-9]+$/i, ''))
      .filter((t) => /dive|dived|diving|scuba|reef|wreck|underwater/i.test(t));
    return [...new Set(titles)];
  } catch (err) {
    logger.warn(`Commons geosearch failed for ${region.name}: ${err instanceof Error ? err.message : String(err)}`);
    return [];
  }
}

// ── Main run ────────────────────────────────────────────────────────

export async function runDiveSiteDiscoveryEtl(): Promise<void> {
  const startedAt = Date.now();
  logger.info('Starting dive site discovery ETL (v2 — LLM enumeration + Nominatim)');

  if (!isLlmConfigured()) {
    logger.warn(
      'Skipping dive-site-discovery: OPENCODE_ZEN_API_KEY not set. ' +
        'Set it to enable LLM-backed site discovery.',
    );
    logJobSummary('dive-site-discovery', { processed: 0, upserted: 0, skipped: 0, errors: [] });
    return;
  }
  logger.info(`LLM: ${llmLabel()}`);

  const supabase = getSupabase();
  const regions = resolveRegions('DISCOVERY_REGIONS');
  logger.info(`Discovery regions: ${regions.map((r) => r.name).join(', ')}`);

  // Load existing sites for dedup (by slug and normalised name).
  const { data: existingSites } = await supabase.from('dive_sites').select('slug, name');
  const seenSlugs = new Set((existingSites ?? []).map((s) => s.slug as string));
  const seenNames = new Set(
    (existingSites ?? []).map((s) => (s.name as string).toLowerCase().trim()),
  );
  logger.info(`Existing: ${seenSlugs.size} dive sites already in DB`);

  // Phase 1 + 2: enumerate candidates.
  const candidates: SiteCandidate[] = [];
  const errors: string[] = [];

  for (const region of regions) {
    let destinations: Array<{ name: string; country: string }> = [];
    try {
      destinations = await enumerateDestinations(region);
      logger.info(`${region.name}: ${destinations.length} destinations`);
    } catch (err) {
      const msg = `enumerateDestinations(${region.name}): ${err instanceof Error ? err.message : String(err)}`;
      errors.push(msg);
      logger.warn(msg);
      continue;
    }

    for (const dest of destinations) {
      try {
        const sites = await enumerateSites(dest.name, dest.country, region);
        for (const c of sites) {
          const key = c.name.toLowerCase().trim();
          if (seenNames.has(key)) continue;
          seenNames.add(key);
          candidates.push(c);
        }
      } catch (err) {
        errors.push(`enumerateSites(${dest.name}): ${err instanceof Error ? err.message : String(err)}`);
      }
    }

    // Optional: augment with Wikimedia Commons candidate names.
    if (USE_COMMONS) {
      const names = await commonsCandidateNames(region);
      for (const name of names) {
        const key = name.toLowerCase().trim();
        if (seenNames.has(key)) continue;
        seenNames.add(key);
        candidates.push({
          name,
          destination: region.name.replace(/_/g, ' '),
          country: '',
          region,
          llm: null,
          discoverySource: 'commons',
        });
      }
    }
  }

  logger.info(`Total unique candidate sites: ${candidates.length}`);

  // Phase 3: geocode + build rows.
  const siteRows: DiveSiteRow[] = [];
  let geocoded = 0;
  let skippedNoCoords = 0;

  for (const cand of candidates) {
    const query = cand.country
      ? `${cand.name}, ${cand.destination}, ${cand.country}`
      : `${cand.name}, ${cand.destination}`;
    const place = await geocode(query, cand.region.bbox);

    if (!place) {
      // Without coordinates the site is not useful for map / proximity search.
      skippedNoCoords += 1;
      continue;
    }
    geocoded += 1;

    const baseSlug = slugify(`disc-${cand.name}`);
    const slug = uniqueSlug(baseSlug, String(siteRows.length), seenSlugs);
    const hint = [cand.llm?.description, cand.llm?.site_type, cand.destination]
      .filter(Boolean)
      .join(' ');

    siteRows.push({
      name: cand.name,
      slug,
      description: cand.llm?.description ?? null,
      location: geographyPoint(place.lng, place.lat),
      country_code: normalizeCountryCode(place.countryCode ?? undefined),
      region: cand.destination,
      depth_min: cand.llm?.depth_min ?? 0,
      depth_max: cand.llm?.depth_max ?? 30,
      difficulty: normalizeDifficulty(cand.llm?.difficulty ?? undefined, hint),
      site_type: normalizeSiteType(cand.llm?.site_type ?? 'other'),
      access_type: normalizeAccessType(cand.llm?.access_type ?? undefined, hint),
      verified: false,
      metadata: {
        source: 'dive_site_discovery',
        discovery_source: cand.discoverySource,
        destination: cand.destination,
        geocoded_name: place.displayName,
        llm_enriched: cand.llm != null,
      },
    });
  }

  logger.info(`Geocoded ${geocoded}/${candidates.length} candidates (${skippedNoCoords} skipped: no coords)`);

  if (siteRows.length === 0) {
    logJobSummary('dive-site-discovery', {
      processed: candidates.length,
      upserted: 0,
      skipped: skippedNoCoords,
      errors,
    });
    logger.info('No new dive sites discovered');
    return;
  }

  const result = await upsertBatch(
    'dive_sites',
    siteRows as unknown as Record<string, unknown>[],
    'slug',
  );

  logJobSummary('dive-site-discovery', {
    processed: candidates.length,
    upserted: result.upserted,
    skipped: result.skipped + skippedNoCoords,
    errors: [...errors, ...result.errors],
  });

  logger.info(`Dive site discovery ETL finished in ${Date.now() - startedAt}ms`);
}

if (isMainModule(import.meta.url)) {
  runDiveSiteDiscoveryEtl().catch((err) => {
    logger.error('Dive site discovery ETL failed', {
      error: err instanceof Error ? err.message : String(err),
    });
    process.exit(1);
  });
}
