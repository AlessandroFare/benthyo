/**
 * Dive Site Discovery ETL — v1 (multi-source, zero-budget).
 *
 * Three discovery approaches combined:
 *
 * 1. Wikimedia Commons geosearch: find geotagged underwater photos per region.
 *    Photos often have dive site names in titles/categories/descriptions.
 *
 * 2. DuckDuckGo text search: "dive sites [region]" → extract names from
 *    search snippets using regex patterns.
 *
 * 3. LLM enrichment (optional, off by default): feed candidate names to a
 *    local Ollama model, Groq free tier, or DeepSeek via OpenCode Zen for
 *    structured extraction of location, depth, difficulty, type.
 *
 * All three approaches are zero-cost:
 *  - Wikimedia Commons: free API, no key required
 *  - DuckDuckGo: free HTML search (no API key)
 *  - Ollama: local, free
 *  - Groq: cloud free tier (30 req/min)
 *  - DeepSeek via OpenCode Zen: OpenAI-compatible, free tier available
 *
 * Usage:
 *   DISCOVERY_REGIONS=caribbean,red_sea tsx dive-site-discovery/index.ts
 *   DISCOVERY_REGIONS=all DISCOVERY_USE_LLM=ollama tsx dive-site-discovery/index.ts
 *   DISCOVERY_REGIONS=all DISCOVERY_USE_LLM=deepseek tsx dive-site-discovery/index.ts
 */

import 'dotenv/config';
import { logger, logJobSummary } from '../shared/logger';
import { RateLimiter } from '../shared/rate-limiter';
import { getSupabase, upsertBatch } from '../shared/supabase';
import { isMainModule } from '../shared/cli';
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

const COMMONS_API = process.env.COMMONS_API_URL ?? 'https://commons.wikimedia.org/w/api.php';
const USER_AGENT = process.env.WIKIMEDIA_USER_AGENT ?? 'Benthyo/1.0 (https://benthyo.com; contact@benthyo.com)';
const DDG_SEARCH = process.env.DDG_SEARCH_URL ?? 'https://lite.duckduckgo.com/lite/';
const LLM_MODE = (process.env.DISCOVERY_USE_LLM ?? '').toLowerCase(); // 'ollama' | 'groq' | 'deepseek' | '' (off)
const OLLAMA_URL = process.env.OLLAMA_URL ?? 'http://localhost:11434';
const OLLAMA_MODEL = process.env.OLLAMA_MODEL ?? 'llama3.2:3b';
const GROQ_API_KEY = process.env.GROQ_API_KEY ?? '';
const GROQ_MODEL = process.env.GROQ_MODEL ?? 'llama-3.1-8b-instant';
// DeepSeek via OpenCode Zen (OpenAI-compatible API)
const DEEPSEEK_BASE_URL = process.env.DEEPSEEK_BASE_URL ?? ''; // e.g., https://api.opencodezen.com/v1
const DEEPSEEK_API_KEY = process.env.DEEPSEEK_API_KEY ?? '';
const DEEPSEEK_MODEL = process.env.DEEPSEEK_MODEL ?? 'deepseek-chat';
const MAX_PHOTOS_PER_REGION = Number(process.env.DISCOVERY_PHOTOS_PER_REGION ?? 50);
const MAX_SEARCH_RESULTS = Number(process.env.DISCOVERY_SEARCH_RESULTS ?? 10);
const MIN_PHOTO_RESOLUTION = 800; // skip tiny thumbnails

const limiter = new RateLimiter({ minIntervalMs: 300 });
const ddgLimiter = new RateLimiter({ minIntervalMs: 3000 }); // DuckDuckGo rate-limits aggressively

// ── Wikimedia Commons interfaces ────────────────────────────────────

interface CommonsPage {
  pageid: number;
  title: string;
}

interface CommonsImageInfo {
  url: string;
  descriptionurl: string;
  extmetadata?: Array<{ name: string; value: string }>;
}

interface CommonsSearchResponse {
  query?: {
    geosearch?: CommonsPage[];
    pages?: Record<string, { imageinfo?: CommonsImageInfo[]; categories?: Array<{ title: string }> }>;
  };
}

interface ExtractedCandidate {
  name: string;
  lat: number;
  lng: number;
  source: string; // description, category, title
  rawContext: string;
}

// ── Approach 1: Wikimedia Commons geosearch ─────────────────────────

async function geosearchPhotos(
  region: MarineRegion,
  limit: number,
): Promise<CommonsPage[]> {
  const params = new URLSearchParams({
    action: 'query',
    list: 'geosearch',
    gsbbox: [
      region.bbox.nelat,
      region.bbox.nelng,
      region.bbox.swlat,
      region.bbox.swlng,
    ].join('|'),
    gsnamespace: '6', // File namespace only
    gslimit: String(limit),
    format: 'json',
    origin: '*',
  });
  const url = `${COMMONS_API}?${params}`;
  const data = await limiter.fetchJson<CommonsSearchResponse>(url, {
    headers: { 'User-Agent': USER_AGENT },
  });
  return data.query?.geosearch ?? [];
}

async function fetchImageDetails(pageIds: number[]): Promise<Record<string, CommonsImageInfo>> {
  if (pageIds.length === 0) return {};
  const params = new URLSearchParams({
    action: 'query',
    pageids: pageIds.join('|'),
    prop: 'imageinfo|categories',
    iiprop: 'url|extmetadata',
    iilimit: '1',
    cllimit: '20',
    format: 'json',
    origin: '*',
  });
  const url = `${COMMONS_API}?${params}`;
  const data = await limiter.fetchJson<CommonsSearchResponse>(url, {
    headers: { 'User-Agent': USER_AGENT },
  });
  const result: Record<string, CommonsImageInfo> = {};
  const pages = data.query?.pages ?? {};
  for (const [, page] of Object.entries(pages)) {
    const info = page.imageinfo?.[0];
    if (info) result[String(page.pageid ?? '')] = info;
  }
  return result;
}

const DIVE_SITE_NAME_PATTERNS = [
  // "at [Name]" → extract Name
  /(?:at|a|vicino a|near|off|di)\s+["']?([A-Z][A-Za-z\s'-]{3,40})["']?(?:\s*[,.;!]|\s*$)/g,
  // "[Name] dive site" / "[Name] diving site"
  /([A-Z][A-Za-z\s'-]{3,40})\s+(?:dive\s*site|diving\s*site|scuba\s*site)/gi,
  // "Wreck of [Name]" / "Relitto [Name]"
  /(?:Wreck\s+of|Relitto\s+(?:del|della|di)|Épave\s+(?:du|de))\s+["']?([A-Z][A-Za-z\s'-]{3,40})["']?/gi,
  // "[Name] reef" / "[Name] wall" / "[Name] cave"
  /([A-Z][A-Za-z\s'-]{3,40})\s+(?:reef|wall|pinnacle|wreck|cave|blue\s*hole|drop.off)/gi,
  // Category: "Underwater diving in [Location]"
  /(?:Underwater\s+diving\s+(?:in|at)|Scuba\s+diving\s+(?:in|at)|Diving\s+(?:in|at))\s+([A-Z][A-Za-z\s'-]{3,40})/gi,
];

/** Heuristic: does this look like a real dive site name and not noise? */
function looksLikeDiveSiteName(name: string): boolean {
  const cleaned = name.trim();
  if (cleaned.length < 3 || cleaned.length > 50) return false;
  // Exclude camera model names, EXIF tags, generic words
  const noise = new Set([
    'the', 'and', 'for', 'with', 'from', 'this', 'that', 'canon', 'nikon', 'sony',
    'olympus', 'gopro', 'photo', 'image', 'jpg', 'jpeg', 'png', 'dsc', 'img',
    'underwater', 'scuba', 'diving', 'diver', 'ocean', 'sea', 'water', 'blue',
    'april', 'may', 'june', 'july', 'august', 'september', 'october',
  ]);
  if (noise.has(cleaned.toLowerCase())) return false;
  // Must have at least one capital letter start
  if (!/[A-Z]/.test(cleaned[0])) return false;
  return true;
}

function extractCandidatesFromText(
  text: string,
  lat: number,
  lng: number,
): ExtractedCandidate[] {
  const candidates: ExtractedCandidate[] = [];
  const seen = new Set<string>();

  for (const pattern of DIVE_SITE_NAME_PATTERNS) {
    // Reset regex state
    pattern.lastIndex = 0;
    let match: RegExpExecArray | null;
    while ((match = pattern.exec(text)) !== null) {
      const name = (match[1] ?? match[2] ?? '').trim();
      if (!name || seen.has(name.toLowerCase())) continue;
      if (!looksLikeDiveSiteName(name)) continue;
      seen.add(name.toLowerCase());
      candidates.push({ name, lat, lng, source: 'commons', rawContext: text.slice(Math.max(0, match.index - 50), match.index + match[0].length + 50) });
    }
  }

  return candidates;
}

async function commonsDiscovery(region: MarineRegion): Promise<ExtractedCandidate[]> {
  logger.info(`Commons geosearch: ${region.name}`);
  const photos = await geosearchPhotos(region, MAX_PHOTOS_PER_REGION);
  if (photos.length === 0) {
    logger.info(`Commons: no geotagged photos in ${region.name}`);
    return [];
  }

  const pageIds = photos.map((p) => p.pageid);
  const details = await fetchImageDetails(pageIds);

  const candidates: ExtractedCandidate[] = [];
  let processed = 0;

  for (const photo of photos) {
    const info = details[String(photo.pageid)];
    if (!info?.descriptionurl) continue;

    // The Commons description page URL contains the description text.
    // We fetch it as raw wikitext to extract dive site names.
    const descUrl = info.descriptionurl;
    try {
      const params = new URLSearchParams({
        action: 'raw',
        title: photo.title.replace(/^File:/, ''),
      });
      const rawUrl = `${COMMONS_API}?${params}`;
      const response = await limiter.fetch(rawUrl, {
        headers: { 'User-Agent': USER_AGENT },
      });
      if (!response.ok) continue;
      const wikitext = await response.text();

      // Commons geosearch returns images with coordinates; extract lat/lng
      // from the coordinate templates in the wikitext
      const coordMatch = wikitext.match(/\{\{Location\|(-?[\d.]+)\|(-?[\d.]+)/);
      const lat = coordMatch ? Number(coordMatch[2]) : 0;
      const lng = coordMatch ? Number(coordMatch[1]) : 0;

      if (lat === 0 && lng === 0) continue;

      const extracted = extractCandidatesFromText(wikitext, lat, lng);
      candidates.push(...extracted);
      processed += 1;
    } catch {
      // skip failed fetches
    }

    if (processed >= 20) break; // limit per region to be kind to Commons API
  }

  logger.info(`Commons ${region.name}: ${candidates.length} candidates from ${processed} photos`);
  return candidates;
}

// ── Approach 2: DuckDuckGo text search ──────────────────────────────

interface DdgSearchResult {
  title: string;
  snippet: string;
  url: string;
}

/**
 * DuckDuckGo Lite HTML search (no API key, no JS).
 * Returns up to ~20 text results with title/snippet/url.
 */
async function duckDuckGoSearch(query: string, maxResults: number): Promise<DdgSearchResult[]> {
  const params = new URLSearchParams({ q: query });
  const url = `${DDG_SEARCH}?${params}`;
  const response = await ddgLimiter.fetch(url, {
    headers: {
      'User-Agent': USER_AGENT,
      'Accept': 'text/html',
    },
  });
  if (!response.ok) return [];
  const html = await response.text();

  // Parse DuckDuckGo Lite results (simple HTML structure)
  const results: DdgSearchResult[] = [];
  // Match result rows: <a rel="nofollow" href="URL">Title</a><br>Snippet
  const rowRegex = /<a\s+rel="nofollow"\s+(?:class="result-link"\s+)?href="([^"]+)"[^>]*>([^<]+)<\/a>\s*(?:<br\s*\/?>\s*)?(?:<span[^>]*>)?([^<]*?)(?:<\/span>)?\s*(?:<br|<table|<\/td)/gi;
  let match: RegExpExecArray | null;
  while ((match = rowRegex.exec(html)) !== null) {
    const [, rawUrl, rawTitle, snippet] = match;
    // DuckDuckGo Lite redirects through /l/?uddg=REAL_URL
    const urlMatch = rawUrl.match(/uddg=([^&]+)/);
    const cleanUrl = urlMatch ? decodeURIComponent(urlMatch[1]) : rawUrl;
    results.push({
      title: rawTitle.replace(/<[^>]*>/g, '').trim(),
      snippet: snippet.replace(/<[^>]*>/g, '').trim(),
      url: cleanUrl,
    });
    if (results.length >= maxResults) break;
  }

  return results;
}

async function ddgTextDiscovery(region: MarineRegion): Promise<ExtractedCandidate[]> {
  // Multiple search queries to maximize coverage
  const queries = [
    `dive sites ${region.name.replace(/_/g, ' ')} list`,
    `best scuba diving spots ${region.name.replace(/_/g, ' ')}`,
    `underwater sites ${region.name.replace(/_/g, ' ')} diving`,
  ];

  const candidates: ExtractedCandidate[] = [];
  const seenNames = new Set<string>();

  for (const query of queries) {
    logger.info(`DDG search: "${query}"`);
    const results = await duckDuckGoSearch(query, MAX_SEARCH_RESULTS);

    for (const result of results) {
      const combined = `${result.title} ${result.snippet}`;
      const extracted = extractCandidatesFromText(combined, 0, 0); // no coords yet
      for (const cand of extracted) {
        const key = cand.name.toLowerCase();
        if (seenNames.has(key)) continue;
        seenNames.add(key);
        // Attach the search snippet as context for later enrichment
        cand.rawContext = combined;
        cand.source = 'ddg';
        candidates.push(cand);
      }
    }
  }

  logger.info(`DDG ${region.name}: ${candidates.length} unique candidates`);
  return candidates;
}

// ── Approach 3: LLM enrichment (optional) ──────────────────────────

interface EnrichedSite {
  name: string;
  lat?: number;
  lng?: number;
  depth_min?: number;
  depth_max?: number;
  difficulty?: string;
  site_type?: string;
  description?: string;
  country_code?: string;
}

async function ollamaComplete(prompt: string): Promise<string> {
  const response = await fetch(`${OLLAMA_URL}/api/generate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: OLLAMA_MODEL,
      prompt,
      stream: false,
      options: { temperature: 0.1, num_predict: 500 },
    }),
  });
  if (!response.ok) throw new Error(`Ollama HTTP ${response.status}`);
  const data = (await response.json()) as { response: string };
  return data.response;
}

async function groqComplete(prompt: string): Promise<string> {
  const response = await fetch('https://api.groq.com/openai/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${GROQ_API_KEY}`,
    },
    body: JSON.stringify({
      model: GROQ_MODEL,
      messages: [{ role: 'user', content: prompt }],
      temperature: 0.1,
      max_tokens: 800,
    }),
  });
  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Groq HTTP ${response.status}: ${body.slice(0, 200)}`);
  }
  const data = (await response.json()) as { choices: Array<{ message: { content: string } }> };
  return data.choices[0]?.message?.content ?? '';
}

/**
 * Call DeepSeek via OpenCode Zen (OpenAI-compatible).
 * Same format as callOpenAI in Fluxychat ai-agent.
 */
async function deepseekComplete(prompt: string): Promise<string> {
  const response = await fetch(`${DEEPSEEK_BASE_URL}/chat/completions`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${DEEPSEEK_API_KEY}`,
    },
    body: JSON.stringify({
      model: DEEPSEEK_MODEL,
      messages: [{ role: 'user', content: prompt }],
      temperature: 0.1,
      max_tokens: 800,
    }),
  });
  if (!response.ok) {
    const body = await response.text();
    throw new Error(`DeepSeek HTTP ${response.status}: ${body.slice(0, 200)}`);
  }
  const data = (await response.json()) as { choices: Array<{ message: { content: string } }> };
  return data.choices[0]?.message?.content ?? '';
}

async function enrichWithLLM(candidate: ExtractedCandidate): Promise<EnrichedSite | null> {
  // Try Ollama first (local, zero-cost), fall back to Groq
  const prompt = `Extract structured dive site information from the following context. Return ONLY valid JSON, no explanation.

Context: "${candidate.rawContext || candidate.name}"

{
  "name": "exact dive site name",
  "lat": number or null,
  "lng": number or null,
  "depth_min": number or null,
  "depth_max": number or null,
  "difficulty": "beginner" | "intermediate" | "advanced" | "technical" | null,
  "site_type": "reef" | "wall" | "wreck" | "cave" | "pinnacle" | "muck" | "other" | null,
  "description": "short description or null",
  "country_code": "2-letter ISO code or null"
}`;

  try {
    let raw: string;
    if (LLM_MODE === 'groq' && GROQ_API_KEY) {
      raw = await groqComplete(prompt);
    } else if (LLM_MODE === 'deepseek' && DEEPSEEK_API_KEY) {
      raw = await deepseekComplete(prompt);
    } else {
      raw = await ollamaComplete(prompt);
    }

    // Extract JSON from the response (LLMs often wrap in markdown)
    const jsonMatch = raw.match(/\{[\s\S]*\}/);
    if (!jsonMatch) return null;
    const parsed = JSON.parse(jsonMatch[0]) as EnrichedSite;
    if (!parsed.name) return null;
    return parsed;
  } catch (err) {
    logger.warn(`LLM enrichment failed for "${candidate.name}": ${err instanceof Error ? err.message : String(err)}`);
    return null;
  }
}

// ── Main run ────────────────────────────────────────────────────────

export async function runDiveSiteDiscoveryEtl(): Promise<void> {
  const startedAt = Date.now();
  logger.info('Starting multi-source dive site discovery ETL');
  if (LLM_MODE) {
    const modelLabel = LLM_MODE === 'ollama' ? OLLAMA_MODEL : LLM_MODE === 'groq' ? GROQ_MODEL : DEEPSEEK_MODEL;
    logger.info(`LLM enrichment: ${LLM_MODE} (${modelLabel})`);
  } else {
    logger.info('LLM enrichment: off (set DISCOVERY_USE_LLM=ollama, =groq, or =deepseek to enable)');
  }

  const supabase = getSupabase();
  const regions = resolveRegions('DISCOVERY_REGIONS');
  logger.info(`Discovery regions: ${regions.map((r) => r.name).join(', ')}`);

  // Load existing site slugs for dedup
  const { data: existingSites } = await supabase
    .from('dive_sites')
    .select('slug, name');
  const existingSlugs = new Set((existingSites ?? []).map((s) => s.slug as string));
  const existingNames = new Set(
    (existingSites ?? []).map((s) => (s.name as string).toLowerCase().trim()),
  );
  logger.info(`Existing: ${existingSlugs.size} dive sites already in DB`);

  const allCandidates: ExtractedCandidate[] = [];
  const seenCandidateNames = new Set<string>();

  for (const region of regions) {
    // Phase 1: Commons geosearch
    try {
      const commonsCandidates = await commonsDiscovery(region);
      for (const c of commonsCandidates) {
        const key = c.name.toLowerCase().trim();
        if (seenCandidateNames.has(key) || existingNames.has(key)) continue;
        seenCandidateNames.add(key);
        allCandidates.push(c);
      }
    } catch (err) {
      logger.warn(`Commons discovery failed for ${region.name}: ${err instanceof Error ? err.message : String(err)}`);
    }

    // Phase 2: DuckDuckGo text search
    try {
      const ddgCandidates = await ddgTextDiscovery(region);
      for (const c of ddgCandidates) {
        const key = c.name.toLowerCase().trim();
        if (seenCandidateNames.has(key) || existingNames.has(key)) continue;
        seenCandidateNames.add(key);
        allCandidates.push(c);
      }
    } catch (err) {
      logger.warn(`DDG discovery failed for ${region.name}: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  logger.info(`Total unique new candidates: ${allCandidates.length}`);

  // Phase 3: Enrichment + upsert
  const siteRows: DiveSiteRow[] = [];
  const seenSlugs = new Set(existingSlugs);
  let enriched = 0;
  let skipped = 0;

  for (const candidate of allCandidates) {
    let enrichedData: EnrichedSite | null = null;

    if (LLM_MODE) {
      enrichedData = await enrichWithLLM(candidate);
      if (enrichedData) enriched += 1;
    }

    const baseSlug = slugify(enrichedData?.name ?? candidate.name);
    const slug = uniqueSlug(`disc-${baseSlug}`, String(siteRows.length), seenSlugs);

    const hint = [
      candidate.rawContext,
      enrichedData?.description,
      enrichedData?.site_type,
    ].filter(Boolean).join(' ');

    siteRows.push({
      name: enrichedData?.name ?? candidate.name,
      slug,
      description: enrichedData?.description ?? null,
      location: enrichedData?.lat && enrichedData?.lng
        ? geographyPoint(enrichedData.lng, enrichedData.lat)
        : geographyPoint(candidate.lng || 0, candidate.lat || 0),
      country_code: normalizeCountryCode(enrichedData?.country_code),
      region: null,
      depth_min: enrichedData?.depth_min ?? 0,
      depth_max: enrichedData?.depth_max ?? 30,
      difficulty: normalizeDifficulty(enrichedData?.difficulty, hint),
      site_type: normalizeSiteType(enrichedData?.site_type ?? 'other'),
      access_type: normalizeAccessType(undefined, hint),
      verified: false,
      metadata: {
        source: 'dive_site_discovery',
        discovery_source: candidate.source,
        raw_context: candidate.rawContext?.slice(0, 500),
        llm_enriched: !!enrichedData,
      },
    });
  }

  logger.info(`LLM enriched: ${enriched}/${allCandidates.length} candidates`);

  if (siteRows.length === 0) {
    logger.info('No new dive sites discovered');
    logJobSummary('dive-site-discovery', { processed: allCandidates.length, upserted: 0, skipped: 0, errors: [] });
    return;
  }

  const result = await upsertBatch(
    'dive_sites',
    siteRows as unknown as Record<string, unknown>[],
    'slug',
  );

  logJobSummary('dive-site-discovery', {
    processed: allCandidates.length,
    upserted: result.upserted,
    skipped: result.skipped,
    errors: result.errors,
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
