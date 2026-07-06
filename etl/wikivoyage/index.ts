/**
 * Wikivoyage Dive Guides ETL — free, high-quality, coordinate-accurate.
 *
 * English Wikivoyage hosts an entire scuba travel guide corpus: "Diving in
 * South Africa", "Diving the Cape Peninsula and False Bay" (with one subpage
 * PER DIVE SITE, each carrying exact coordinates, depth and conditions),
 * "Diving in Bali", "Diving in Fiji", etc. All CC BY-SA, all served by the
 * free MediaWiki API. Unlike LLM enumeration or map OCR, the coordinates
 * here are human-curated — this is the most *correct* zero-budget source we
 * have, so its sites are stored with metadata.coords_precision='geocoded'.
 *
 * Pipeline:
 *   1. SEARCH — MediaWiki fulltext search for mainspace pages whose title
 *      contains "Diving" (paginated; bounded by WIKIVOYAGE_MAX_PAGES).
 *   2. PARSE — fetch each page's wikitext and deterministically extract
 *      {{see|...}} / {{do|...}} / {{listing|...}} / {{marker|...}} templates
 *      that carry name + lat + long. No LLM involved — pure parsing.
 *   3. FILTER — drop dive shops / resorts / non-site listings by keyword.
 *   4. NORMALISE — depth parsed from the listing text when present
 *      ("Depth: 24 m", "max depth 30m"); country via coarse-grid Nominatim
 *      reverse geocoding (cached, ~0.5° grid, so a whole guide usually
 *      costs 1-2 reverse lookups).
 *
 * Sites are stored unverified (verified=false, metadata.source='wikivoyage')
 * with the source page title + URL kept for attribution (CC BY-SA).
 *
 * Usage:
 *   pnpm wikivoyage
 *   WIKIVOYAGE_MAX_PAGES=100 pnpm wikivoyage
 */

import 'dotenv/config';
import { logger, logJobSummary } from '../shared/logger';
import { RateLimiter } from '../shared/rate-limiter';
import { getSupabase, upsertBatch } from '../shared/supabase';
import { isMainModule } from '../shared/cli';
import {
  geographyPoint,
  inferDifficultyFromText,
  normalizeAccessType,
  normalizeCountryCode,
  normalizeSiteType,
  slugify,
  uniqueSlug,
  type DiveSiteRow,
} from '../shared/dive-site-utils';

// ── Config ──────────────────────────────────────────────────────────

const WIKIVOYAGE_API = process.env.WIKIVOYAGE_API_URL ?? 'https://en.wikivoyage.org/w/api.php';
const MAX_PAGES = Number(process.env.WIKIVOYAGE_MAX_PAGES ?? 60);
const USER_AGENT =
  process.env.WIKIMEDIA_USER_AGENT ?? 'Benthyo/1.0 (https://benthyo.com; contact@benthyo.com)';

const wikiLimiter = new RateLimiter({ minIntervalMs: 500, maxRetries: 3 });
const nominatimLimiter = new RateLimiter({ minIntervalMs: 1100, maxRetries: 3 });

// ── MediaWiki API ───────────────────────────────────────────────────

interface SearchHit {
  title: string;
  pageid: number;
}

async function searchDivingPages(): Promise<SearchHit[]> {
  const hits: SearchHit[] = [];
  let offset = 0;
  while (hits.length < MAX_PAGES) {
    const params = new URLSearchParams({
      action: 'query',
      list: 'search',
      srsearch: 'intitle:Diving',
      srnamespace: '0',
      srlimit: '50',
      sroffset: String(offset),
      format: 'json',
      origin: '*',
    });
    const data = await wikiLimiter.fetchJson<{
      query?: { search?: SearchHit[] };
      continue?: { sroffset?: number };
    }>(`${WIKIVOYAGE_API}?${params}`, { headers: { 'User-Agent': USER_AGENT } });

    const page = data.query?.search ?? [];
    hits.push(...page);
    const next = data.continue?.sroffset;
    if (!next || page.length === 0) break;
    offset = next;
  }
  return hits.slice(0, MAX_PAGES);
}

async function fetchWikitext(pageid: number): Promise<string | null> {
  const params = new URLSearchParams({
    action: 'parse',
    pageid: String(pageid),
    prop: 'wikitext',
    format: 'json',
    origin: '*',
  });
  try {
    const data = await wikiLimiter.fetchJson<{
      parse?: { wikitext?: { '*': string } };
    }>(`${WIKIVOYAGE_API}?${params}`, { headers: { 'User-Agent': USER_AGENT } });
    return data.parse?.wikitext?.['*'] ?? null;
  } catch (err) {
    logger.warn(
      `Wikitext fetch failed for pageid=${pageid}: ${err instanceof Error ? err.message : String(err)}`,
    );
    return null;
  }
}

// ── Wikitext listing parsing (deterministic, no LLM) ────────────────

export interface WikiListing {
  name: string;
  lat: number;
  lng: number;
  content: string;
  templateType: string;
}

/**
 * Extract {{see|...}} / {{do|...}} / {{listing|...}} / {{marker|...}}
 * templates that carry name + lat + long from raw wikitext. Handles one
 * level of nested templates inside field values (e.g. {{convert|30|m}}).
 */
export function parseListings(wikitext: string): WikiListing[] {
  const listings: WikiListing[] = [];
  const templateRe = /\{\{(see|do|listing|marker|vcard)\s*\|((?:[^{}]|\{\{[^{}]*\}\})*)\}\}/gi;

  let match: RegExpExecArray | null;
  while ((match = templateRe.exec(wikitext)) !== null) {
    const type = match[1].toLowerCase();
    const body = match[2];

    // Split fields on top-level pipes (ignore pipes inside nested {{...}}).
    const fields: Record<string, string> = {};
    let depth = 0;
    let current = '';
    const parts: string[] = [];
    for (const ch of body) {
      if (ch === '{') depth += 1;
      else if (ch === '}') depth -= 1;
      if (ch === '|' && depth === 0) {
        parts.push(current);
        current = '';
      } else {
        current += ch;
      }
    }
    parts.push(current);

    for (const part of parts) {
      const eq = part.indexOf('=');
      if (eq === -1) continue;
      const key = part.slice(0, eq).trim().toLowerCase();
      const value = part.slice(eq + 1).trim();
      if (key) fields[key] = value;
    }

    const name = stripWikiMarkup(fields['name'] ?? '');
    const lat = Number(fields['lat']);
    const lng = Number(fields['long'] ?? fields['lng'] ?? fields['lon']);
    if (!name || !Number.isFinite(lat) || !Number.isFinite(lng)) continue;
    if (lat === 0 && lng === 0) continue;

    listings.push({
      name,
      lat,
      lng,
      content: stripWikiMarkup(
        [fields['alt'], fields['content'], fields['description']].filter(Boolean).join('. '),
      ),
      templateType: type,
    });
  }
  return listings;
}

/** Strip common wiki markup from a field value. */
export function stripWikiMarkup(value: string): string {
  return value
    .replace(/\[\[(?:[^\]|]*\|)?([^\]]*)\]\]/g, '$1') // [[link|text]] → text
    .replace(/\{\{[^{}]*\}\}/g, ' ')                   // drop nested templates
    .replace(/'{2,}/g, '')                             // bold/italic quotes
    .replace(/<[^>]+>/g, ' ')                          // html tags
    .replace(/\s+/g, ' ')
    .trim();
}

/** Listings that are clearly not dive sites (shops, schools, resorts). */
const NON_SITE_RE =
  /\b(dive (shop|center|centre|school|resort|club|operator)|divers den|scuba (school|shop)|hotel|restaurant|hostel|airline|airport|museum(?! ship)|aquarium)\b/i;

/** Parse a depth range in metres out of free text, e.g. "Depth: 12 to 30 m". */
export function parseDepth(text: string): { min: number | null; max: number | null } {
  const range = text.match(/depth[^.\d]{0,20}(\d{1,3})\s*(?:m|metres|meters)?\s*(?:to|-|–)\s*(\d{1,3})\s*(?:m|metres|meters)\b/i);
  if (range) return { min: Number(range[1]), max: Number(range[2]) };
  const single = text.match(/(?:max(?:imum)? )?depth[^.\d]{0,20}(\d{1,3})\s*(?:m|metres|meters)\b/i);
  if (single) return { min: null, max: Number(single[1]) };
  return { min: null, max: null };
}

// ── Coarse-grid reverse geocoding for country codes ─────────────────

const countryCache = new Map<string, string | null>();

async function reverseCountry(lat: number, lng: number): Promise<string | null> {
  const key = `${Math.round(lat * 2) / 2},${Math.round(lng * 2) / 2}`;
  if (countryCache.has(key)) return countryCache.get(key) ?? null;
  const params = new URLSearchParams({
    lat: String(lat),
    lon: String(lng),
    format: 'jsonv2',
    zoom: '3',
  });
  try {
    const data = await nominatimLimiter.fetchJson<{ address?: { country_code?: string } }>(
      `https://nominatim.openstreetmap.org/reverse?${params}`,
      { headers: { 'User-Agent': USER_AGENT, Accept: 'application/json' } },
    );
    const code = data.address?.country_code?.toUpperCase() ?? null;
    countryCache.set(key, code);
    return code;
  } catch {
    countryCache.set(key, null);
    return null;
  }
}

// ── Main run ────────────────────────────────────────────────────────

export async function runWikivoyageEtl(): Promise<void> {
  const startedAt = Date.now();
  logger.info('Starting Wikivoyage dive guides ETL');

  const supabase = getSupabase();
  const { data: existingSites } = await supabase.from('dive_sites').select('slug, name');
  const seenSlugs = new Set((existingSites ?? []).map((s) => s.slug as string));
  const seenNames = new Set(
    (existingSites ?? []).map((s) => (s.name as string).toLowerCase().trim()),
  );

  const errors: string[] = [];
  let pages: SearchHit[] = [];
  try {
    pages = await searchDivingPages();
  } catch (err) {
    throw new Error(
      `Wikivoyage search failed: ${err instanceof Error ? err.message : String(err)}`,
    );
  }
  logger.info(`Found ${pages.length} Wikivoyage diving pages`);

  const siteRows: DiveSiteRow[] = [];
  let listingsTotal = 0;
  let skipped = 0;

  for (const page of pages) {
    const wikitext = await fetchWikitext(page.pageid);
    if (!wikitext) continue;

    const listings = parseListings(wikitext);
    listingsTotal += listings.length;

    // Region label: "Diving the Cape Peninsula and False Bay/Ark Rock" →
    // "Cape Peninsula and False Bay"; "Diving in Bali" → "Bali".
    const region = page.title
      .split('/')[0]
      .replace(/^diving (in|the|at|around)?\s*/i, '')
      .trim();

    for (const listing of listings) {
      if (NON_SITE_RE.test(listing.name) || NON_SITE_RE.test(listing.content)) {
        skipped += 1;
        continue;
      }
      const nameKey = listing.name.toLowerCase().trim();
      if (seenNames.has(nameKey)) {
        skipped += 1;
        continue;
      }
      seenNames.add(nameKey);

      const depth = parseDepth(listing.content);
      const countryCode = await reverseCountry(listing.lat, listing.lng);
      const hint = `${listing.content} ${page.title}`;
      const baseSlug = slugify(`${listing.name}-${region}`);
      const slug = uniqueSlug(baseSlug, String(siteRows.length), seenSlugs);

      siteRows.push({
        name: listing.name,
        slug,
        description: listing.content || null,
        location: geographyPoint(listing.lng, listing.lat),
        country_code: normalizeCountryCode(countryCode ?? undefined),
        region,
        depth_min: depth.min ?? 0,
        depth_max: depth.max ?? 30,
        difficulty: inferDifficultyFromText(hint),
        site_type: normalizeSiteType(hint),
        access_type: normalizeAccessType(undefined, hint),
        verified: false,
        metadata: {
          source: 'wikivoyage',
          page_title: page.title,
          page_url: `https://en.wikivoyage.org/wiki/${encodeURIComponent(page.title.replace(/ /g, '_'))}`,
          license: 'CC BY-SA 4.0',
          template_type: listing.templateType,
          coords_precision: 'geocoded',
        },
      });
    }
  }

  logger.info(`Parsed ${listingsTotal} listings → ${siteRows.length} new dive sites`);

  if (siteRows.length === 0) {
    logJobSummary('wikivoyage', { processed: listingsTotal, upserted: 0, skipped, errors });
    return;
  }

  const result = await upsertBatch(
    'dive_sites',
    siteRows as unknown as Record<string, unknown>[],
    'slug',
  );

  logJobSummary('wikivoyage', {
    processed: listingsTotal,
    upserted: result.upserted,
    skipped: skipped + result.skipped,
    errors: [...errors, ...result.errors],
  });

  logger.info(`Wikivoyage ETL finished in ${Date.now() - startedAt}ms`);
}

if (isMainModule(import.meta.url)) {
  runWikivoyageEtl().catch((err) => {
    logger.error('Wikivoyage ETL failed', {
      error: err instanceof Error ? err.message : String(err),
    });
    process.exit(1);
  });
}
