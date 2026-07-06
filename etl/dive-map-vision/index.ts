/**
 * Dive Map Vision ETL — mine dive-site names out of dive maps found online.
 *
 * The most complete lists of dive sites are NOT in any database: they are in
 * the dive-shop maps that show up when you search "<place> dive sites" in an
 * image search — hand-drawn island maps with every named site around it
 * (e.g. the classic Malapascua maps with Gato Island, Monad Shoal, Lapus
 * Lapus, Ka Osting...). This ETL automates exactly what a human does:
 *
 *   1. DESTINATIONS — from DIVE_MAP_DESTINATIONS env, or LLM-enumerated per
 *      marine region (shared with dive-site-discovery). A deterministic
 *      daily rotation walks the full list over successive nightly runs, so
 *      over time every destination on Earth gets covered at bounded cost.
 *   2. IMAGE SEARCH — DuckDuckGo Images (free, no key; Tavily fallback) for
 *      "<destination> dive sites map"-style queries.
 *   3. VISION EXTRACTION — Groq Llama 4 Scout (free tier) reads each image;
 *      if it is a dive map, it returns the site names printed on it plus any
 *      extra hints (travel time, notable species like "thresher shark").
 *   4. VOTING — names are normalised and counted across all maps of the same
 *      destination. A name on 2+ independent maps is very likely real.
 *   5. VALIDATE + ENRICH — one text-LLM call per destination confirms the
 *      names are real dive sites (they came from OCR, so hallucination risk
 *      is low, but boat names / village names get filtered here) and adds
 *      type / difficulty / depth / description.
 *   6. GEOCODE — Nominatim, biased near the destination. Sites missing from
 *      OSM (most of them — that's the point of this ETL) are anchored near
 *      the destination with a small deterministic offset and marked
 *      coords_precision='destination_approx' so moderators can refine them.
 *
 * Discovered sites are stored unverified (verified=false, metadata.source =
 * 'dive_map_vision') with the evidence image URLs kept in metadata, so a
 * moderator can open the exact map the name came from.
 *
 * Requires GROQ_API_KEY (vision). OPENCODE_ZEN_API_KEY enables destination
 * enumeration + enrichment; without it, set DIVE_MAP_DESTINATIONS explicitly.
 *
 * Usage:
 *   DIVE_MAP_DESTINATIONS="Malapascua,Philippines;Dahab,Egypt" pnpm dive-map-vision
 *   DIVE_MAP_REGIONS=southeast_asia DIVE_MAP_MAX_DESTINATIONS=5 pnpm dive-map-vision
 */

import 'dotenv/config';
import { z } from 'zod';
import { logger, logJobSummary } from '../shared/logger';
import { getSupabase, upsertBatch } from '../shared/supabase';
import { isMainModule } from '../shared/cli';
import { generateJson, isLlmConfigured, llmLabel } from '../shared/llm';
import { extractJsonFromImage, isVisionConfigured, visionLabel } from '../shared/vision';
import { searchImages, type ImageSearchResult } from '../shared/image-search';
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
import { resolveRegions } from '../shared/marine-regions';
import {
  destinationsFromEnv,
  enumerateDestinations,
  type Destination,
} from '../shared/destinations';

// ── Config ──────────────────────────────────────────────────────────

/** Destinations processed per run (each costs image search + N vision calls). */
const MAX_DESTINATIONS = Number(process.env.DIVE_MAP_MAX_DESTINATIONS ?? 8);
/** Images analysed per destination. */
const IMAGES_PER_DEST = Number(process.env.DIVE_MAP_IMAGES_PER_DEST ?? 6);
/** Minimum cross-map votes to keep a site (1 = trust single maps). */
const MIN_VOTES = Number(process.env.DIVE_MAP_MIN_VOTES ?? 1);
/** LLM-enumerated destinations per region (pre-rotation pool size). */
const DESTS_PER_REGION = Number(process.env.DIVE_MAP_DESTS_PER_REGION ?? 15);

const SEARCH_QUERIES = ['dive sites map', 'dive site map diving'];

// ── Vision schema: what we read off a dive map image ───────────────

const MapExtractionSchema = z.object({
  is_dive_map: z.boolean(),
  location_label: z.string().nullable().optional(),
  sites: z
    .array(
      z.object({
        name: z.string(),
        travel_time_minutes: z.number().nullable().optional(),
        depth_hint: z.string().nullable().optional(),
        notable_species: z.array(z.string()).nullable().optional(),
      }),
    )
    .default([]),
});

type MapExtraction = z.infer<typeof MapExtractionSchema>;

// ── Enrichment schema: validate + describe extracted names ─────────

const EnrichmentSchema = z.object({
  sites: z.array(
    z.object({
      name: z.string(),
      is_real_dive_site: z.boolean(),
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
  ),
});

type EnrichedSite = z.infer<typeof EnrichmentSchema>['sites'][number];

// ── Aggregation ─────────────────────────────────────────────────────

interface VotedSite {
  /** Canonical display name (the most common raw spelling). */
  name: string;
  /** Normalised key used for voting/dedup. */
  key: string;
  votes: number;
  travelTimeMinutes: number | null;
  depthHint: string | null;
  notableSpecies: string[];
  evidenceImages: string[];
  sourcePages: string[];
}

/** Normalise a site name for voting: case/punct/parenthetical-insensitive. */
export function normalizeSiteName(raw: string): string {
  return raw
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/\([^)]*\)/g, ' ') // drop "(10 min)" / "(shallow)" qualifiers
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/** Words that indicate the label is not a dive site (village, boat, shop). */
const NAME_BLOCKLIST =
  /\b(dive (center|centre|shop|resort)|divers|beach resort|the village|airport|pier|harbou?r|jetty|town|village)\b/i;

function isPlausibleSiteName(name: string): boolean {
  const n = name.trim();
  if (n.length < 3 || n.length > 60) return false;
  if (NAME_BLOCKLIST.test(n)) return false;
  // Pure numbers or single generic words are noise.
  if (/^\d+$/.test(n)) return false;
  return true;
}

function aggregateVotes(
  extractions: Array<{ extraction: MapExtraction; image: ImageSearchResult }>,
): VotedSite[] {
  const byKey = new Map<string, VotedSite & { spellings: Map<string, number> }>();

  for (const { extraction, image } of extractions) {
    // Dedup names within a single map so one map = max one vote per site.
    const seenInThisMap = new Set<string>();
    for (const site of extraction.sites) {
      if (!isPlausibleSiteName(site.name)) continue;
      const key = normalizeSiteName(site.name);
      if (!key || seenInThisMap.has(key)) continue;
      seenInThisMap.add(key);

      let entry = byKey.get(key);
      if (!entry) {
        entry = {
          name: site.name.trim(),
          key,
          votes: 0,
          travelTimeMinutes: null,
          depthHint: null,
          notableSpecies: [],
          evidenceImages: [],
          sourcePages: [],
          spellings: new Map(),
        };
        byKey.set(key, entry);
      }
      entry.votes += 1;
      entry.spellings.set(site.name.trim(), (entry.spellings.get(site.name.trim()) ?? 0) + 1);
      if (entry.travelTimeMinutes == null && site.travel_time_minutes != null) {
        entry.travelTimeMinutes = site.travel_time_minutes;
      }
      if (entry.depthHint == null && site.depth_hint) entry.depthHint = site.depth_hint;
      for (const sp of site.notable_species ?? []) {
        if (!entry.notableSpecies.includes(sp)) entry.notableSpecies.push(sp);
      }
      if (entry.evidenceImages.length < 3 && !entry.evidenceImages.includes(image.imageUrl)) {
        entry.evidenceImages.push(image.imageUrl);
      }
      if (image.sourceUrl && entry.sourcePages.length < 3 && !entry.sourcePages.includes(image.sourceUrl)) {
        entry.sourcePages.push(image.sourceUrl);
      }
    }
  }

  return [...byKey.values()].map((entry) => {
    // Pick the most frequent raw spelling as the canonical display name.
    let best = entry.name;
    let bestCount = 0;
    for (const [spelling, count] of entry.spellings) {
      if (count > bestCount) {
        best = spelling;
        bestCount = count;
      }
    }
    const { spellings: _spellings, ...rest } = entry;
    return { ...rest, name: titleCase(best) };
  });
}

function titleCase(name: string): string {
  // Maps are often ALL CAPS ("MONAD SHOAL") — normalise for display.
  if (name !== name.toUpperCase()) return name;
  return name
    .toLowerCase()
    .replace(/(^|[\s\-/])([a-z])/g, (_m, sep: string, ch: string) => sep + ch.toUpperCase());
}

// ── Vision extraction ───────────────────────────────────────────────

async function extractSitesFromImage(
  image: ImageSearchResult,
  destination: Destination,
): Promise<MapExtraction | null> {
  const place = destination.country
    ? `${destination.name}, ${destination.country}`
    : destination.name;
  return extractJsonFromImage(MapExtractionSchema, image.imageUrl, {
    system:
      'You read scuba-diving maps. Given an image, decide whether it is a dive-site map ' +
      '(a map, chart or infographic labelling named scuba dive sites) and transcribe EXACTLY ' +
      'the dive-site names printed on it. Do NOT invent names; only transcribe visible text. ' +
      'Exclude labels that are villages, beaches, dive shops, boats or roads. ' +
      'Respond with ONLY minified JSON matching: {"is_dive_map":boolean,' +
      '"location_label":string|null,"sites":[{"name":string,' +
      '"travel_time_minutes":number|null,"depth_hint":string|null,' +
      '"notable_species":string[]|null}]}',
    prompt:
      `This image came from a web search for dive sites at ${place}. ` +
      'If it is a dive map, transcribe every dive-site name on it (with travel time in minutes ' +
      'if printed, e.g. "(45 Min)", any depth text, and notable species drawn/named next to a ' +
      'site, e.g. a thresher shark icon). If it is not a dive map, return {"is_dive_map":false,' +
      '"location_label":null,"sites":[]}.',
    maxTokens: 1500,
  });
}

// ── Validation + enrichment (text LLM) ──────────────────────────────

async function enrichSites(
  destination: Destination,
  sites: VotedSite[],
): Promise<Map<string, EnrichedSite>> {
  const out = new Map<string, EnrichedSite>();
  if (!isLlmConfigured() || sites.length === 0) return out;

  const place = destination.country
    ? `${destination.name}, ${destination.country}`
    : destination.name;
  try {
    const result = await generateJson(EnrichmentSchema, {
      system:
        'You are a scuba-diving domain expert. The user gives you dive-site names transcribed ' +
        'from published dive maps of a destination, so most are real. Mark is_real_dive_site ' +
        'false ONLY for entries that are clearly not dive sites (boats, villages, resorts, ' +
        'generic labels). Never invent numeric data: use null when unsure.',
      prompt:
        `These names were transcribed from dive maps of ${place}: ` +
        `${sites.map((s) => `"${s.name}"`).join(', ')}. ` +
        'For each, return whether it is a real dive site there, plus site_type, difficulty, ' +
        'typical min/max depth in metres, access (shore/boat/liveaboard) and a one-sentence description.',
      temperature: 0.2,
    });
    for (const site of result.sites) {
      out.set(normalizeSiteName(site.name), site);
    }
  } catch (err) {
    logger.warn(
      `Enrichment failed for ${place}: ${err instanceof Error ? err.message : String(err)}`,
    );
  }
  return out;
}

// ── Geocoding with destination-anchored fallback ────────────────────

/** Small deterministic offset (< ~2.5 km) from a name hash, so fallback
 * sites don't all stack on the destination's exact point. */
export function deterministicOffset(name: string): { dlat: number; dlng: number } {
  let hash = 0;
  for (let i = 0; i < name.length; i += 1) {
    hash = (hash * 31 + name.charCodeAt(i)) | 0;
  }
  const a = ((hash & 0xffff) / 0xffff - 0.5) * 0.04; // ±0.02° ≈ ±2.2 km
  const b = (((hash >>> 16) & 0xffff) / 0xffff - 0.5) * 0.04;
  return { dlat: a, dlng: b };
}

// ── Destination resolution with daily rotation ──────────────────────

async function resolveDestinations(errors: string[]): Promise<Destination[]> {
  const explicit = destinationsFromEnv('DIVE_MAP_DESTINATIONS');
  if (explicit) return explicit.slice(0, MAX_DESTINATIONS);

  if (!isLlmConfigured()) {
    logger.warn(
      'No DIVE_MAP_DESTINATIONS and no OPENCODE_ZEN_API_KEY — cannot enumerate destinations.',
    );
    return [];
  }

  const regions = resolveRegions('DIVE_MAP_REGIONS');
  const pool: Destination[] = [];
  for (const region of regions) {
    try {
      pool.push(...(await enumerateDestinations(region, DESTS_PER_REGION)));
    } catch (err) {
      errors.push(
        `enumerateDestinations(${region.name}): ${err instanceof Error ? err.message : String(err)}`,
      );
    }
  }
  if (pool.length <= MAX_DESTINATIONS) return pool;

  // Deterministic daily rotation: successive nightly runs walk the whole
  // pool, so every destination is eventually covered at bounded cost.
  const dayIndex = Math.floor(Date.now() / 86_400_000);
  const start = (dayIndex * MAX_DESTINATIONS) % pool.length;
  const window: Destination[] = [];
  for (let i = 0; i < MAX_DESTINATIONS; i += 1) {
    window.push(pool[(start + i) % pool.length]);
  }
  return window;
}

// ── Main run ────────────────────────────────────────────────────────

export async function runDiveMapVisionEtl(): Promise<void> {
  const startedAt = Date.now();
  logger.info('Starting dive map vision ETL (image search + vision extraction)');

  if (!isVisionConfigured()) {
    logger.warn(
      'Skipping dive-map-vision: GROQ_API_KEY not set. ' +
        'Set it (free at console.groq.com) to enable dive-map reading.',
    );
    logJobSummary('dive-map-vision', { processed: 0, upserted: 0, skipped: 0, errors: [] });
    return;
  }
  logger.info(`Vision: ${visionLabel()}${isLlmConfigured() ? `, enrichment: ${llmLabel()}` : ''}`);

  const errors: string[] = [];
  const destinations = await resolveDestinations(errors);
  if (destinations.length === 0) {
    logJobSummary('dive-map-vision', { processed: 0, upserted: 0, skipped: 0, errors });
    return;
  }
  logger.info(
    `Destinations this run: ${destinations.map((d) => d.name).join(', ')}`,
  );

  const supabase = getSupabase();
  const { data: existingSites } = await supabase.from('dive_sites').select('slug, name');
  const seenSlugs = new Set((existingSites ?? []).map((s) => s.slug as string));
  const seenNames = new Set(
    (existingSites ?? []).map((s) => normalizeSiteName(s.name as string)),
  );
  logger.info(`Existing: ${seenSlugs.size} dive sites already in DB`);

  const siteRows: DiveSiteRow[] = [];
  let candidatesTotal = 0;
  let skippedTotal = 0;

  for (const dest of destinations) {
    const place = dest.country ? `${dest.name}, ${dest.country}` : dest.name;

    // Anchor: geocode the destination itself. Without an anchor we cannot
    // place fallback coordinates, so we skip the destination entirely.
    const anchor = await geocode(place);
    if (!anchor) {
      errors.push(`geocode anchor failed: ${place}`);
      continue;
    }
    const bias = {
      swlat: anchor.lat - 0.5,
      swlng: anchor.lng - 0.5,
      nelat: anchor.lat + 0.5,
      nelng: anchor.lng + 0.5,
    };

    // 1. Image search across query variants, dedup by URL.
    const images: ImageSearchResult[] = [];
    const seenUrls = new Set<string>();
    for (const suffix of SEARCH_QUERIES) {
      const found = await searchImages(`${place} ${suffix}`, IMAGES_PER_DEST);
      for (const img of found) {
        if (seenUrls.has(img.imageUrl)) continue;
        seenUrls.add(img.imageUrl);
        images.push(img);
      }
      if (images.length >= IMAGES_PER_DEST) break;
    }
    if (images.length === 0) {
      logger.warn(`No images found for ${place}`);
      continue;
    }

    // 2. Vision extraction on each candidate image.
    const extractions: Array<{ extraction: MapExtraction; image: ImageSearchResult }> = [];
    for (const image of images.slice(0, IMAGES_PER_DEST)) {
      const extraction = await extractSitesFromImage(image, dest);
      if (extraction?.is_dive_map && extraction.sites.length > 0) {
        extractions.push({ extraction, image });
      }
    }
    logger.info(
      `${place}: ${extractions.length}/${Math.min(images.length, IMAGES_PER_DEST)} images were dive maps`,
    );
    if (extractions.length === 0) continue;

    // 3. Vote across maps, drop names already in the DB.
    const voted = aggregateVotes(extractions)
      .filter((s) => s.votes >= MIN_VOTES)
      .filter((s) => !seenNames.has(s.key));
    candidatesTotal += voted.length;
    if (voted.length === 0) continue;

    // 4. Validate + enrich via text LLM (skips gracefully when unconfigured).
    const enriched = await enrichSites(dest, voted);

    // 5. Geocode each site; fallback anchors near the destination.
    for (const site of voted) {
      const info = enriched.get(site.key);
      if (info && !info.is_real_dive_site) {
        skippedTotal += 1;
        continue;
      }

      let lat: number;
      let lng: number;
      let countryCode = anchor.countryCode;
      let coordsPrecision: 'geocoded' | 'destination_approx';
      const geo = await geocode(`${site.name}, ${place}`, bias);
      if (geo) {
        lat = geo.lat;
        lng = geo.lng;
        countryCode = geo.countryCode ?? countryCode;
        coordsPrecision = 'geocoded';
      } else {
        const off = deterministicOffset(site.key);
        lat = anchor.lat + off.dlat;
        lng = anchor.lng + off.dlng;
        coordsPrecision = 'destination_approx';
      }

      const baseSlug = slugify(`${site.name}-${dest.name}`);
      const slug = uniqueSlug(baseSlug, String(siteRows.length), seenSlugs);
      seenNames.add(site.key);

      const hint = [info?.description, info?.site_type, dest.name].filter(Boolean).join(' ');
      siteRows.push({
        name: site.name,
        slug,
        description: info?.description ?? null,
        location: geographyPoint(lng, lat),
        country_code: normalizeCountryCode(countryCode ?? undefined),
        region: dest.name,
        depth_min: info?.depth_min ?? 0,
        depth_max: info?.depth_max ?? 30,
        difficulty: normalizeDifficulty(info?.difficulty ?? undefined, hint),
        site_type: normalizeSiteType(info?.site_type ?? 'other'),
        access_type: normalizeAccessType(info?.access_type ?? undefined, hint),
        verified: false,
        metadata: {
          source: 'dive_map_vision',
          destination: dest.name,
          destination_country: dest.country || null,
          map_votes: site.votes,
          maps_analyzed: extractions.length,
          coords_precision: coordsPrecision,
          travel_time_minutes: site.travelTimeMinutes,
          depth_hint: site.depthHint,
          notable_species: site.notableSpecies.length > 0 ? site.notableSpecies : null,
          evidence_images: site.evidenceImages,
          source_pages: site.sourcePages,
        },
      });
    }
  }

  logger.info(`Candidates: ${candidatesTotal}, rows to upsert: ${siteRows.length}`);

  if (siteRows.length === 0) {
    logJobSummary('dive-map-vision', {
      processed: candidatesTotal,
      upserted: 0,
      skipped: skippedTotal,
      errors,
    });
    logger.info('No new dive sites extracted from maps');
    return;
  }

  const result = await upsertBatch(
    'dive_sites',
    siteRows as unknown as Record<string, unknown>[],
    'slug',
  );

  logJobSummary('dive-map-vision', {
    processed: candidatesTotal,
    upserted: result.upserted,
    skipped: result.skipped + skippedTotal,
    errors: [...errors, ...result.errors],
  });

  logger.info(`Dive map vision ETL finished in ${Date.now() - startedAt}ms`);
}

if (isMainModule(import.meta.url)) {
  runDiveMapVisionEtl().catch((err) => {
    logger.error('Dive map vision ETL failed', {
      error: err instanceof Error ? err.message : String(err),
    });
    process.exit(1);
  });
}
