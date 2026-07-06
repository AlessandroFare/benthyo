/**
 * Zero-budget web image search for the ETL pipeline.
 *
 * Replicates what a human does: type "<place> dive sites map" into an image
 * search engine and look at the results. There is no free official Google
 * Images API, so we use:
 *
 *   1. DuckDuckGo Images (primary) — free, no API key. Uses the same
 *      two-step flow as the DDG web UI: fetch the search page to obtain a
 *      `vqd` request token, then call the `i.js` JSON endpoint. Unofficial
 *      but stable for years; failures degrade gracefully.
 *   2. Tavily (fallback) — `include_images: true` on the search endpoint.
 *      Only used when TAVILY_API_KEY is set and DDG returned nothing
 *      (Tavily's free tier is 1000 credits/month, so we spend it sparingly).
 *
 * All failures return [] — image search is an enrichment source, never a
 * pipeline-fatal dependency.
 */

import { logger } from './logger';
import { RateLimiter } from './rate-limiter';

const DDG_HTML_URL = 'https://duckduckgo.com/';
const DDG_IMAGES_URL = 'https://duckduckgo.com/i.js';
const TAVILY_API = process.env.TAVILY_API_URL ?? 'https://api.tavily.com/search';
const TAVILY_API_KEY = process.env.TAVILY_API_KEY ?? '';

const BROWSER_UA =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';

// Be a polite scraper: ~1 request / 1.5s to DDG.
const ddgLimiter = new RateLimiter({ minIntervalMs: 1500, maxRetries: 2 });
const tavilyLimiter = new RateLimiter({ minIntervalMs: 1000, maxRetries: 2 });

export interface ImageSearchResult {
  /** Direct URL of the full-size image. */
  imageUrl: string;
  /** Page the image was found on (provenance / evidence). */
  sourceUrl: string | null;
  /** Result title (often contains the place / dive shop name). */
  title: string | null;
  width: number | null;
  height: number | null;
  provider: 'duckduckgo' | 'tavily';
}

/** Fetch the DDG search page and extract the vqd token required by i.js. */
async function fetchDdgVqd(query: string): Promise<string | null> {
  const params = new URLSearchParams({ q: query, iax: 'images', ia: 'images' });
  try {
    const res = await ddgLimiter.fetch(`${DDG_HTML_URL}?${params}`, {
      headers: { 'User-Agent': BROWSER_UA, Accept: 'text/html' },
    });
    if (!res.ok) return null;
    const html = await res.text();
    // The token appears as vqd="4-..." or vqd=4-...& depending on build.
    const match = html.match(/vqd=['"]?([\d-]+)/);
    return match?.[1] ?? null;
  } catch (err) {
    logger.warn(
      `DDG vqd fetch failed for "${query}": ${err instanceof Error ? err.message : String(err)}`,
    );
    return null;
  }
}

interface DdgImageRow {
  image?: string;
  url?: string;
  title?: string;
  width?: number;
  height?: number;
}

/** DuckDuckGo image search (no key). Returns [] on any failure. */
export async function searchImagesDdg(
  query: string,
  maxResults: number,
): Promise<ImageSearchResult[]> {
  const vqd = await fetchDdgVqd(query);
  if (!vqd) {
    logger.warn(`DDG image search: no vqd token for "${query}"`);
    return [];
  }

  const params = new URLSearchParams({
    l: 'us-en',
    o: 'json',
    q: query,
    vqd,
    f: ',,,',
    p: '1',
  });

  try {
    const res = await ddgLimiter.fetch(`${DDG_IMAGES_URL}?${params}`, {
      headers: {
        'User-Agent': BROWSER_UA,
        Accept: 'application/json',
        Referer: 'https://duckduckgo.com/',
      },
    });
    if (!res.ok) return [];
    const data = (await res.json()) as { results?: DdgImageRow[] };
    return (data.results ?? [])
      .filter((r): r is DdgImageRow & { image: string } => typeof r.image === 'string')
      .slice(0, maxResults)
      .map((r) => ({
        imageUrl: r.image,
        sourceUrl: r.url ?? null,
        title: r.title ?? null,
        width: r.width ?? null,
        height: r.height ?? null,
        provider: 'duckduckgo' as const,
      }));
  } catch (err) {
    logger.warn(
      `DDG image search failed for "${query}": ${err instanceof Error ? err.message : String(err)}`,
    );
    return [];
  }
}

/** Tavily image search fallback. Returns [] when no key or on failure. */
export async function searchImagesTavily(
  query: string,
  maxResults: number,
): Promise<ImageSearchResult[]> {
  if (!TAVILY_API_KEY) return [];
  try {
    const res = await tavilyLimiter.fetch(TAVILY_API, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        api_key: TAVILY_API_KEY,
        query,
        search_depth: 'basic',
        include_images: true,
        max_results: 5,
      }),
    });
    if (!res.ok) return [];
    const data = (await res.json()) as { images?: string[] };
    return (data.images ?? []).slice(0, maxResults).map((url) => ({
      imageUrl: url,
      sourceUrl: null,
      title: null,
      width: null,
      height: null,
      provider: 'tavily' as const,
    }));
  } catch (err) {
    logger.warn(
      `Tavily image search failed for "${query}": ${err instanceof Error ? err.message : String(err)}`,
    );
    return [];
  }
}

/**
 * Search the web for images matching `query`.
 * DuckDuckGo first (free, unlimited-ish), Tavily as fallback when DDG
 * yields nothing. Results are deduped by image URL.
 */
export async function searchImages(
  query: string,
  maxResults = 8,
): Promise<ImageSearchResult[]> {
  let results = await searchImagesDdg(query, maxResults);
  if (results.length === 0) {
    results = await searchImagesTavily(query, maxResults);
  }
  const seen = new Set<string>();
  return results.filter((r) => {
    if (seen.has(r.imageUrl)) return false;
    seen.add(r.imageUrl);
    return true;
  });
}
