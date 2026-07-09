/**
 * Shared vision helper for the ETL pipeline — zero-budget multimodal with
 * a provider fallback chain (previously Groq-only with NO fallback).
 *
 * Chain (all free tiers):
 *   1. groq     llama-4-scout      30 RPM / 1,000 RPD / 500K TPD
 *   2. google   gemini-2.5-flash-lite  30 RPM / 1,500 RPD — strong OCR
 *   3. mistral  mistral-small-latest   ~1 RPS / 1B tokens-month — vision-capable
 *
 * Callers pass their own prompt and Zod schema and get structured JSON
 * extracted FROM an image. Used by dive-map-vision to read dive-site names
 * off dive maps found online.
 *
 * Robustness notes:
 *   - Many image hosts block hotlinking / non-browser user agents, so we
 *     download the image ourselves (browser-ish UA) and pass base64.
 *   - A provider that errors or rate-limits goes on cooldown and the next
 *     one in the chain is tried; every hard failure degrades to `null` so
 *     a single bad image never kills a run.
 *
 * Env:
 *   GROQ_API_KEY          console.groq.com
 *   GROQ_BASE_URL         default https://api.groq.com/openai/v1
 *   GROQ_VISION_MODEL     default meta-llama/llama-4-scout-17b-16e-instruct
 *   GOOGLE_AI_API_KEY     aistudio.google.com
 *   GOOGLE_VISION_MODEL   default gemini-2.5-flash-lite
 *   MISTRAL_API_KEY       console.mistral.ai
 *   MISTRAL_VISION_MODEL  default mistral-small-latest
 *   MISTRAL_BASE_URL      default https://api.mistral.ai/v1
 */

import type { z } from 'zod';
import { logger } from './logger';
import { extractJson } from './llm';
import { RateLimiter } from './rate-limiter';

const GROQ_API_KEY = process.env.GROQ_API_KEY ?? '';
const GROQ_BASE_URL = process.env.GROQ_BASE_URL ?? 'https://api.groq.com/openai/v1';
const GROQ_VISION_MODEL =
  process.env.GROQ_VISION_MODEL ?? 'meta-llama/llama-4-scout-17b-16e-instruct';

const GOOGLE_API_KEY = process.env.GOOGLE_AI_API_KEY ?? '';
const GOOGLE_VISION_MODEL = process.env.GOOGLE_VISION_MODEL ?? 'gemini-2.5-flash-lite';

const MISTRAL_API_KEY = process.env.MISTRAL_API_KEY ?? '';
const MISTRAL_BASE_URL = process.env.MISTRAL_BASE_URL ?? 'https://api.mistral.ai/v1';
const MISTRAL_VISION_MODEL = process.env.MISTRAL_VISION_MODEL ?? 'mistral-small-latest';

interface VisionProvider {
  id: 'groq' | 'google' | 'mistral';
  modelId: string;
  apiKey: string;
  limiter: RateLimiter;
  cooldownUntil: number;
}

const VISION_PROVIDERS: VisionProvider[] = [
  {
    id: 'groq',
    modelId: GROQ_VISION_MODEL,
    apiKey: GROQ_API_KEY,
    limiter: new RateLimiter({ minIntervalMs: 2500, maxRetries: 2 }),
    cooldownUntil: 0,
  },
  {
    id: 'google',
    modelId: GOOGLE_VISION_MODEL,
    apiKey: GOOGLE_API_KEY,
    limiter: new RateLimiter({ minIntervalMs: 2500, maxRetries: 2 }),
    cooldownUntil: 0,
  },
  {
    id: 'mistral',
    modelId: MISTRAL_VISION_MODEL,
    apiKey: MISTRAL_API_KEY,
    limiter: new RateLimiter({ minIntervalMs: 1500, maxRetries: 2 }),
    cooldownUntil: 0,
  },
];

const VISION_COOLDOWN_MS = 120_000;

/** Separate limiter for downloading candidate images (be a polite crawler). */
const downloadLimiter = new RateLimiter({ minIntervalMs: 500, maxRetries: 1 });

const BROWSER_UA =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';

/** Max image size accepted as a base64 data URL (Groq limit 4 MB), minus margin. */
const MAX_IMAGE_BYTES = 3_800_000;

/** True when at least one vision-capable key is configured. */
export function isVisionConfigured(): boolean {
  return VISION_PROVIDERS.some((p) => p.apiKey.trim().length > 0);
}

/** Human-readable label for logs. */
export function visionLabel(): string {
  const active = VISION_PROVIDERS.find((p) => p.apiKey.trim().length > 0);
  return active ? `${active.id} (${active.modelId})` : 'unconfigured';
}

/**
 * Download an image and return it as a base64 data URL, or null when the
 * host refuses, the payload is not an image, or it exceeds the size limit.
 */
export async function fetchImageAsDataUrl(url: string): Promise<string | null> {
  try {
    const res = await downloadLimiter.fetch(url, {
      headers: { 'User-Agent': BROWSER_UA, Accept: 'image/*,*/*;q=0.8' },
    });
    if (!res.ok) return null;

    const contentType = res.headers.get('content-type') ?? '';
    if (!contentType.startsWith('image/')) return null;
    // Vision models support jpeg/png/gif/webp; skip svg and anything exotic.
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

/** Call an OpenAI-compatible vision endpoint (Groq, Mistral). Returns raw text or null. */
async function callOpenAiCompatVision(
  p: VisionProvider,
  baseUrl: string,
  dataUrl: string,
  opts: { system: string; prompt: string; temperature?: number; maxTokens?: number },
): Promise<string | null> {
  const body = {
    model: p.modelId,
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

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 45_000);
  try {
    const response = await p.limiter.fetch(`${baseUrl}/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${p.apiKey}`,
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    if (!response.ok) {
      const detail = await response.text().catch(() => '');
      logger.warn(`${p.id} vision returned ${response.status}: ${detail.slice(0, 200)}`);
      return null;
    }
    const json = (await response.json()) as {
      choices?: Array<{ message?: { content?: string } }>;
    };
    return json.choices?.[0]?.message?.content ?? null;
  } finally {
    clearTimeout(timeout);
  }
}

/** Call the Google Generative Language REST API with an inline image. */
async function callGoogleVision(
  p: VisionProvider,
  dataUrl: string,
  opts: { system: string; prompt: string; temperature?: number; maxTokens?: number },
): Promise<string | null> {
  const match = dataUrl.match(/^data:([^;]+);base64,(.+)$/s);
  if (!match) return null;
  const [, mimeType, base64Data] = match;

  const body = {
    system_instruction: { parts: [{ text: opts.system }] },
    contents: [
      {
        parts: [
          { text: opts.prompt },
          { inline_data: { mime_type: mimeType, data: base64Data } },
        ],
      },
    ],
    generationConfig: {
      temperature: opts.temperature ?? 0.1,
      maxOutputTokens: opts.maxTokens ?? 1024,
      responseMimeType: 'application/json',
    },
  };

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 45_000);
  try {
    const response = await p.limiter.fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${p.modelId}:generateContent`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': p.apiKey,
        },
        body: JSON.stringify(body),
        signal: controller.signal,
      },
    );
    if (!response.ok) {
      const detail = await response.text().catch(() => '');
      logger.warn(`google vision returned ${response.status}: ${detail.slice(0, 200)}`);
      return null;
    }
    const json = (await response.json()) as {
      candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
    };
    return json.candidates?.[0]?.content?.parts?.[0]?.text ?? null;
  } finally {
    clearTimeout(timeout);
  }
}

/**
 * Ask the vision chain to extract structured JSON from an image.
 *
 * `imageUrl` may be an http(s) URL (we download + inline it as base64) or an
 * existing data: URL. Tries each configured provider in order; a provider
 * that fails goes on a short cooldown. Returns the parsed object validated
 * against `schema`, or null when every provider fails.
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

  const now = Date.now();
  const candidates = VISION_PROVIDERS.filter(
    (p) => p.apiKey.trim().length > 0 && p.cooldownUntil <= now,
  );
  // When everything is cooling down, still try the full configured chain once.
  const chain = candidates.length > 0
    ? candidates
    : VISION_PROVIDERS.filter((p) => p.apiKey.trim().length > 0);

  for (const p of chain) {
    let raw: string | null = null;
    try {
      if (p.id === 'google') {
        raw = await callGoogleVision(p, dataUrl, opts);
      } else {
        const baseUrl = p.id === 'groq' ? GROQ_BASE_URL : MISTRAL_BASE_URL;
        raw = await callOpenAiCompatVision(p, baseUrl, dataUrl, opts);
      }
    } catch (err) {
      logger.warn(
        `${p.id} vision call failed: ${err instanceof Error ? err.message : String(err)}`,
      );
    }

    if (!raw) {
      p.cooldownUntil = Date.now() + VISION_COOLDOWN_MS;
      continue;
    }

    try {
      return schema.parse(extractJson(raw));
    } catch (err) {
      logger.warn(
        `${p.id} vision JSON did not match schema: ${err instanceof Error ? err.message : String(err)}`,
      );
      // Schema mismatch is usually image-specific, not provider-specific —
      // don't cool the provider down, but do try the next one for this image.
      continue;
    }
  }

  return null;
}
