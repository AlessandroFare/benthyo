/**
 * Nominatim (OpenStreetMap) geocoder — free, zero-budget.
 *
 * Used by dive-site-discovery to resolve coordinates for LLM-enumerated dive
 * sites. Nominatim's usage policy requires:
 *   - a descriptive User-Agent / contact
 *   - at most 1 request per second
 *   - result caching (we cache per-process to avoid duplicate lookups)
 *
 * Set NOMINATIM_URL to point at a self-hosted instance if you need higher
 * throughput; the default is the public endpoint.
 */

import { RateLimiter } from './rate-limiter';
import { logger } from './logger';

const NOMINATIM_URL = process.env.NOMINATIM_URL ?? 'https://nominatim.openstreetmap.org/search';
const USER_AGENT =
  process.env.NOMINATIM_USER_AGENT ??
  'Benthyo/1.0 (https://benthyo.com; contact@benthyo.com)';

// 1 request / 1.1s to stay within the public usage policy.
const limiter = new RateLimiter({ minIntervalMs: 1100, maxRetries: 3 });

const cache = new Map<string, GeocodeResult | null>();

export interface GeocodeResult {
  lat: number;
  lng: number;
  displayName: string;
  countryCode: string | null;
  importance: number;
}

interface NominatimRow {
  lat: string;
  lon: string;
  display_name: string;
  importance?: number;
  address?: { country_code?: string };
}

/**
 * Geocode a free-text place query. Returns the best match, or null when
 * nothing plausible is found. Results are cached per-process.
 *
 * `viewbox` (optional) biases results to a region's bounding box so that,
 * e.g., "Blue Hole" resolves inside the Red Sea rather than in Belize.
 */
export async function geocode(
  query: string,
  viewbox?: { swlat: number; swlng: number; nelat: number; nelng: number },
): Promise<GeocodeResult | null> {
  const key = `${query}|${viewbox ? `${viewbox.swlat},${viewbox.swlng},${viewbox.nelat},${viewbox.nelng}` : ''}`;
  if (cache.has(key)) return cache.get(key) ?? null;

  const params = new URLSearchParams({
    q: query,
    format: 'jsonv2',
    limit: '1',
    addressdetails: '1',
  });
  if (viewbox) {
    // Nominatim viewbox order: left(lng),top(lat),right(lng),bottom(lat)
    params.set('viewbox', `${viewbox.swlng},${viewbox.nelat},${viewbox.nelng},${viewbox.swlat}`);
    params.set('bounded', '1');
  }

  const url = `${NOMINATIM_URL}?${params}`;
  try {
    const rows = await limiter.fetchJson<NominatimRow[]>(url, {
      headers: { 'User-Agent': USER_AGENT, Accept: 'application/json' },
    });
    const row = rows[0];
    if (!row) {
      cache.set(key, null);
      return null;
    }
    const result: GeocodeResult = {
      lat: Number(row.lat),
      lng: Number(row.lon),
      displayName: row.display_name,
      countryCode: row.address?.country_code?.toUpperCase() ?? null,
      importance: row.importance ?? 0,
    };
    if (!Number.isFinite(result.lat) || !Number.isFinite(result.lng)) {
      cache.set(key, null);
      return null;
    }
    cache.set(key, result);
    return result;
  } catch (err) {
    logger.warn(
      `Nominatim geocode failed for "${query}": ${err instanceof Error ? err.message : String(err)}`,
    );
    cache.set(key, null);
    return null;
  }
}
