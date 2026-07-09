import { logger } from './logger';

export interface RateLimiterOptions {
  /** Minimum milliseconds between consecutive requests. */
  minIntervalMs?: number;
  /** Maximum retry attempts on HTTP 429 / 503. */
  maxRetries?: number;
  /** Base backoff in ms for exponential retry. */
  baseBackoffMs?: number;
  /** HTTP request timeout in ms (AbortSignal). Default no timeout. */
  timeoutMs?: number;
}

export class RateLimiter {
  private lastRequestAt = 0;
  private readonly minIntervalMs: number;
  private readonly maxRetries: number;
  private readonly baseBackoffMs: number;
  private readonly timeoutMs: number;

  constructor(options: RateLimiterOptions = {}) {
    this.minIntervalMs = options.minIntervalMs ?? 200;
    this.maxRetries = options.maxRetries ?? 5;
    this.baseBackoffMs = options.baseBackoffMs ?? 500;
    this.timeoutMs = options.timeoutMs ?? 0;
  }

  private async waitForSlot(): Promise<void> {
    const elapsed = Date.now() - this.lastRequestAt;
    const waitMs = this.minIntervalMs - elapsed;
    if (waitMs > 0) {
      await sleep(waitMs);
    }
    this.lastRequestAt = Date.now();
  }

  async fetch(url: string, init?: RequestInit): Promise<Response> {
    let attempt = 0;

    while (true) {
      await this.waitForSlot();

      try {
        const signal = this.timeoutMs > 0
          ? AbortSignal.timeout(this.timeoutMs)
          : undefined;
        const response = await fetch(url, { ...init, signal });

        if (response.status === 429 || response.status === 503) {
          if (attempt >= this.maxRetries) {
            throw new Error(`Rate limited after ${this.maxRetries} retries: ${url}`);
          }
          const retryAfter = parseRetryAfter(response.headers.get('retry-after'));
          const backoff = retryAfter ?? this.baseBackoffMs * 2 ** attempt;
          logger.warn(`HTTP ${response.status}, backing off ${backoff}ms`, { url, attempt });
          await sleep(backoff);
          attempt += 1;
          continue;
        }

        return response;
      } catch (err) {
        if (attempt >= this.maxRetries) throw err;
        const backoff = this.baseBackoffMs * 2 ** attempt;
        logger.warn(`Fetch failed, retrying in ${backoff}ms`, {
          url,
          attempt,
          error: err instanceof Error ? err.message : String(err),
        });
        await sleep(backoff);
        attempt += 1;
      }
    }
  }

  async fetchJson<T>(url: string, init?: RequestInit): Promise<T> {
    const response = await this.fetch(url, init);
    if (!response.ok) {
      const body = await response.text().catch(() => '');
      throw new Error(`HTTP ${response.status} for ${url}: ${body.slice(0, 200)}`);
    }
    return (await response.json()) as T;
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function parseRetryAfter(header: string | null): number | null {
  if (!header) return null;
  const seconds = Number(header);
  if (!Number.isNaN(seconds)) return seconds * 1000;
  const date = Date.parse(header);
  if (!Number.isNaN(date)) return Math.max(0, date - Date.now());
  return null;
}

/** Paginate an offset/limit API until a page returns fewer rows than limit. */
export async function paginate<T>(
  fetchPage: (offset: number, limit: number) => Promise<T[]>,
  limit = 300,
  maxPages = 1000,
): Promise<T[]> {
  const all: T[] = [];
  let offset = 0;

  for (let page = 0; page < maxPages; page += 1) {
    const rows = await fetchPage(offset, limit);
    all.push(...rows);
    if (rows.length < limit) break;
    offset += limit;
  }

  return all;
}
