/**
 * Shared Groq vision helper for the ETL pipeline — zero-budget multimodal.
 *
 * Mirrors the API's AiVisionService (apps/api/src/species/ai-vision.service.ts)
 * but generalised: instead of "identify a species", callers pass their own
 * prompt and Zod schema and get structured JSON extracted FROM an image.
 * Used by dive-map-vision to read dive-site names off dive maps found online.
 *
 * Robustness notes:
 *   - Many image hosts block hotlinking / non-browser user agents, and Groq
 *     fetching a URL server-side can fail silently. We therefore download the
 *     image ourselves (with a browser-ish UA) and pass it as a base64 data
 *     URL, which Groq accepts up to 4 MB.
 *   - Every failure degrades to `null` so a single bad image never kills a run.
 *
 * Env (same keys as the API):
 *   GROQ_API_KEY        required to enable vision steps
 *   GROQ_BASE_URL       default https://api.groq.com/openai/v1
 *   GROQ_VISION_MODEL   default meta-llama/llama-4-scout-17b-16e-instruct
 */

import type { z } from 'zod';
import { logger } from './logger';
import { extractJson } from './llm';
import { RateLimiter } from './rate-limiter';

const GROQ_API_KEY = process.env.GROQ_API_KEY ?? '';
const GROQ_BASE_URL = process.env.GROQ_BASE_URL ?? 'https://api.groq.com/openai/v1';
const GROQ_VISION_MODEL =
  process.env.GROQ_VISION_MODEL ?? 'meta-llama/llama-4-scout-17b-16e-instruct';

/** Groq free tier is ~30 req/min for vision models; stay well under it. */
const groqLimiter = new RateLimiter({ minIntervalMs: 2500, maxRetries: 3 });

/** Separate limiter for downloading candidate images (be a polite crawler). */
const downloadLimiter = new RateLimiter({ minIntervalMs: 500, maxRetries: 1 });

const BROWSER_UA =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';

/** Max image size Groq accepts as a base64 data URL (4 MB), minus margin. */
const MAX_IMAGE_BYTES = 3_800_000;

/** True when a Groq key is configured and vision steps can run. */
export function isVisionConfigured(): boolean {
  return GROQ_API_KEY.trim().length > 0;
}

/** Human-readable label for logs. */
export function visionLabel(): string {
  return `groq (${GROQ_VISION_MODEL})`;
}

/**
 * Download an image and return it as a base64 data URL, or null when the
 * host refuses, the payload is not an image, or it exceeds Groq's limit.
 */
export async function fetchImageAsDataUrl(url: string): Promise<string | null> {
  try {
    const res = await downloadLimiter.fetch(url, {
      headers: { 'User-Agent': BROWSER_UA, Accept: 'image/*,*/*;q=0.8' },
    });
    if (!res.ok) return null;

    const contentType = res.headers.get('content-type') ?? '';
    if (!contentType.startsWith('image/')) return null;
    // Groq vision supports jpeg/png/gif/webp; skip svg and anything exotic.
    if (/svg/i.test(contentType)) return null;

    const buf = Buffer.from(await res.arrayBuffer());
    if (buf.byteLength === 0 || buf.byteLength > MAX_IMAGE_BYTES) return null;

    const mime = contentType.split(';')[0].trim();
    return `data:${mime};base64,${buf.toString('base64')}`;
  } catch (err) {
    logger.warn(
      `Image download failed for ${url}: ${err instanceof Error ? err.message : String(err)}`,
    );
    return null;
  }
}

/**
 * Ask the vision model to extract structured JSON from an image.
 *
 * `imageUrl` may be an http(s) URL (we download + inline it as base64) or an
 * existing data: URL. Returns the parsed object validated against `schema`,
 * or null on any failure (download, HTTP, parse, or schema mismatch).
 */
export async function extractJsonFromImage<T>(
  schema: z.ZodType<T, z.ZodTypeDef, unknown>,
  imageUrl: string,
  opts: { system: string; prompt: string; temperature?: number; maxTokens?: number },
): Promise<T | null> {
  if (!isVisionConfigured()) return null;

  const dataUrl = imageUrl.startsWith('data:')
    ? imageUrl
    : await fetchImageAsDataUrl(imageUrl);
  if (!dataUrl) return null;

  const body = {
    model: GROQ_VISION_MODEL,
    temperature: opts.temperature ?? 0.1,
    max_tokens: opts.maxTokens ?? 1024,
    response_format: { type: 'json_object' as const },
    messages: [
      { role: 'system' as const, content: opts.system },
      {
        role: 'user' as const,
        content: [
          { type: 'text' as const, text: opts.prompt },
          { type: 'image_url' as const, image_url: { url: dataUrl } },
        ],
      },
    ],
  };

  let raw = '';
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 45_000);
    let response: Response;
    try {
      response = await groqLimiter.fetch(`${GROQ_BASE_URL}/chat/completions`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${GROQ_API_KEY}`,
        },
        body: JSON.stringify(body),
        signal: controller.signal,
      });
    } finally {
      clearTimeout(timeout);
    }

    if (!response.ok) {
      const detail = await response.text().catch(() => '');
      logger.warn(`Groq vision returned ${response.status}: ${detail.slice(0, 200)}`);
      return null;
    }

    const json = (await response.json()) as {
      choices?: Array<{ message?: { content?: string } }>;
    };
    raw = json.choices?.[0]?.message?.content ?? '';
  } catch (err) {
    logger.warn(
      `Groq vision call failed: ${err instanceof Error ? err.message : String(err)}`,
    );
    return null;
  }

  try {
    return schema.parse(extractJson(raw));
  } catch (err) {
    logger.warn(
      `Vision JSON did not match schema: ${err instanceof Error ? err.message : String(err)}`,
    );
    return null;
  }
}
