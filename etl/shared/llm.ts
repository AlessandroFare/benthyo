/**
 * Shared LLM client for the ETL pipeline — multi-provider chain with
 * per-provider rate limiting, cooldowns, and automatic recovery.
 *
 * Provider chain (all free tiers, best RPD/quality first):
 *   1. google    gemini-2.5-flash-lite   30 RPM / 1,500 RPD — native structured output
 *   2. mistral   mistral-small-latest    ~1 RPS / 1B tokens-month — native JSON mode
 *   3. cerebras  llama-3.3-70b           30 RPM / 14,400 RPD / 1M tokens-day
 *   4. groq      llama-3.1-8b-instant    30 RPM / 14,400 RPD / 500K TPD
 *   5. opencode-zen  deepseek-v4-flash-free  last resort (flaky JSON)
 *
 * Unlike the previous one-way failover, every provider has an independent
 * cooldown: a per-minute rate limit puts it on a short cooldown, a daily
 * limit on a long one. Each request picks the FIRST provider in the chain
 * whose cooldown has expired, so the pipeline automatically returns to the
 * primary once its window clears instead of staying on a fallback forever.
 *
 * The `generateObject` capability flag is also tracked PER PROVIDER: an
 * OpenAI-compatible provider that rejects structured output no longer
 * disables it for providers that support it natively.
 *
 * Config (all optional — chain skips providers without a key):
 *   ETL_LLM_PROVIDER          force one provider ('google' | 'mistral' | 'cerebras' | 'groq' | 'opencode-zen')
 *   GOOGLE_AI_API_KEY         aistudio.google.com — free
 *   GOOGLE_LLM_MODEL          default gemini-2.5-flash-lite
 *   MISTRAL_API_KEY           console.mistral.ai — free tier
 *   MISTRAL_LLM_MODEL         default mistral-small-latest
 *   MISTRAL_BASE_URL          default https://api.mistral.ai/v1
 *   CEREBRAS_API_KEY          cloud.cerebras.ai — free tier
 *   CEREBRAS_LLM_MODEL        default llama-3.3-70b
 *   CEREBRAS_BASE_URL         default https://api.cerebras.ai/v1
 *   GROQ_API_KEY              console.groq.com — free tier
 *   GROQ_LLM_MODEL            default llama-3.1-8b-instant
 *   GROQ_BASE_URL             default https://api.groq.com/openai/v1
 *   OPENCODE_ZEN_API_KEY      opencode.ai
 *   OPENCODE_ZEN_MODEL        default deepseek-v4-flash-free
 *   OPENCODE_ZEN_BASE_URL     default https://opencode.ai/zen/v1
 */

import { createOpenAICompatible } from '@ai-sdk/openai-compatible';
import { createGoogleGenerativeAI } from '@ai-sdk/google';
import { generateObject, generateText, type LanguageModel } from 'ai';
import { z } from 'zod';
import type { ZodTypeAny } from 'zod';
import { logger } from './logger';

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ── Provider registry ───────────────────────────────────────────────

type ProviderId = 'google' | 'mistral' | 'cerebras' | 'groq' | 'opencode-zen';

interface ProviderState {
  id: ProviderId;
  apiKey: string;
  modelId: string;
  baseURL: string | null; // null → native Google SDK
  /** Minimum ms between calls to this provider. */
  minIntervalMs: number;
  /** Timestamp of the last call to this provider. */
  lastCallAt: number;
  /** Whether generateObject (structured output) still works on this provider. */
  generateObjectSupported: boolean;
  /** Provider is unavailable until this timestamp (rate/daily limits). */
  cooldownUntil: number;
  /** Consecutive per-minute rate limits (reset on success). */
  consecutiveRateLimits: number;
  /** Lazily-created AI SDK model instance. */
  instance: LanguageModel | null;
}

function makeProvider(
  id: ProviderId,
  apiKey: string,
  modelId: string,
  baseURL: string | null,
  minIntervalMs: number,
): ProviderState {
  return {
    id,
    apiKey,
    modelId,
    baseURL,
    minIntervalMs,
    lastCallAt: 0,
    generateObjectSupported: true,
    cooldownUntil: 0,
    consecutiveRateLimits: 0,
    instance: null,
  };
}

/** Ordered best-first. Providers without a key are skipped at selection time. */
const PROVIDERS: ProviderState[] = [
  makeProvider(
    'google',
    process.env.GOOGLE_AI_API_KEY ?? '',
    process.env.GOOGLE_LLM_MODEL ?? 'gemini-2.5-flash-lite',
    null,
    2500, // 30 RPM free → 24/min with buffer
  ),
  makeProvider(
    'mistral',
    process.env.MISTRAL_API_KEY ?? '',
    process.env.MISTRAL_LLM_MODEL ?? 'mistral-small-latest',
    process.env.MISTRAL_BASE_URL ?? 'https://api.mistral.ai/v1',
    1500, // free tier ~1 req/s
  ),
  makeProvider(
    'cerebras',
    process.env.CEREBRAS_API_KEY ?? '',
    process.env.CEREBRAS_LLM_MODEL ?? 'llama-3.3-70b',
    process.env.CEREBRAS_BASE_URL ?? 'https://api.cerebras.ai/v1',
    2500, // 30 RPM free
  ),
  makeProvider(
    'groq',
    process.env.GROQ_API_KEY ?? '',
    process.env.GROQ_LLM_MODEL ?? 'llama-3.1-8b-instant',
    process.env.GROQ_BASE_URL ?? 'https://api.groq.com/openai/v1',
    2500, // 30 RPM free
  ),
  makeProvider(
    'opencode-zen',
    process.env.OPENCODE_ZEN_API_KEY ?? '',
    process.env.OPENCODE_ZEN_MODEL ?? 'deepseek-v4-flash-free',
    process.env.OPENCODE_ZEN_BASE_URL ?? 'https://opencode.ai/zen/v1',
    3000,
  ),
];

/** Cooldown applied when a provider hits a per-minute rate limit twice in a row. */
const SHORT_COOLDOWN_MS = 90_000;
/** Cooldown applied when a provider hits a daily/TPD limit. */
const DAILY_COOLDOWN_MS = 6 * 60 * 60 * 1000;

const FORCED_PROVIDER = (process.env.ETL_LLM_PROVIDER ?? '').toLowerCase() as
  | ProviderId
  | '';

function configuredProviders(): ProviderState[] {
  const withKeys = PROVIDERS.filter((p) => p.apiKey.trim().length > 0);
  if (FORCED_PROVIDER) {
    const forced = withKeys.filter((p) => p.id === FORCED_PROVIDER);
    if (forced.length > 0) return forced;
  }
  return withKeys;
}

/** True when at least one LLM key is configured. */
export function isLlmConfigured(): boolean {
  return configuredProviders().length > 0;
}

/**
 * Pick the best available provider: first in the chain whose cooldown has
 * expired. When ALL are cooling down, wait for the soonest one.
 */
async function pickProvider(): Promise<ProviderState> {
  const candidates = configuredProviders();
  if (candidates.length === 0) {
    throw new Error(
      'No LLM API key is set — set GOOGLE_AI_API_KEY, MISTRAL_API_KEY, CEREBRAS_API_KEY, GROQ_API_KEY, or OPENCODE_ZEN_API_KEY',
    );
  }
  const now = Date.now();
  const ready = candidates.find((p) => p.cooldownUntil <= now);
  if (ready) return ready;

  // Everyone is cooling down — wait for the soonest.
  const soonest = candidates.reduce((a, b) =>
    a.cooldownUntil <= b.cooldownUntil ? a : b,
  );
  const waitMs = Math.max(soonest.cooldownUntil - now, 1000);
  logger.warn(
    `All LLM providers cooling down — waiting ${Math.ceil(waitMs / 1000)}s for ${soonest.id}`,
  );
  await sleep(waitMs);
  soonest.cooldownUntil = 0;
  return soonest;
}

function getModelFor(p: ProviderState): LanguageModel {
  if (!p.instance) {
    if (p.baseURL === null) {
      const provider = createGoogleGenerativeAI({ apiKey: p.apiKey });
      p.instance = provider.chat(p.modelId) as unknown as LanguageModel;
    } else {
      const provider = createOpenAICompatible({
        name: p.id,
        baseURL: p.baseURL,
        apiKey: p.apiKey,
      });
      p.instance = provider.chatModel(p.modelId);
    }
  }
  return p.instance;
}

/** Per-provider rate limit gate. */
async function rateLimit(p: ProviderState): Promise<void> {
  const elapsed = Date.now() - p.lastCallAt;
  const wait = p.minIntervalMs - elapsed;
  if (wait > 0) await sleep(wait);
  p.lastCallAt = Date.now();
}

/** Human-readable label for logs (best currently-available provider). */
export function llmLabel(): string {
  const candidates = configuredProviders();
  if (candidates.length === 0) return 'unconfigured';
  const now = Date.now();
  const active = candidates.find((p) => p.cooldownUntil <= now) ?? candidates[0];
  return `${active.id} (${active.modelId})`;
}

/** Get the model for the best currently-available provider (sync, no wait). */
export function getLlmModel(): LanguageModel {
  const candidates = configuredProviders();
  if (candidates.length === 0) {
    throw new Error('No LLM API key is set');
  }
  const now = Date.now();
  const active = candidates.find((p) => p.cooldownUntil <= now) ?? candidates[0];
  return getModelFor(active);
}

/** Backward compat alias. */
export const getZenModel = getLlmModel;

// ── Error classification ────────────────────────────────────────────

/** True when an error message indicates a per-minute quota/rate limit (recoverable after wait). */
function isMinuteRateLimit(err: unknown): boolean {
  const msg = err instanceof Error ? err.message : String(err);
  return /rate limit/i.test(msg) || /quota exceeded/i.test(msg) || /current quota/i.test(msg) || /429/.test(msg);
}

/** Extract retry-after seconds from a "Please retry in Xs" message. */
function parseRetrySeconds(err: unknown): number {
  const msg = err instanceof Error ? err.message : String(err);
  const m = msg.match(/retry in ([\d.]+)s/i);
  return m ? Math.ceil(Number(m[1])) + 2 : 15;
}

/** True when an error message indicates a daily limit (put provider on long cooldown). */
function isDailyLimit(err: unknown): boolean {
  const msg = err instanceof Error ? err.message : String(err);
  return (
    /TPD/i.test(msg) ||
    /tokens per day/i.test(msg) ||
    /daily limit/i.test(msg) ||
    /daily.*request.*quota/i.test(msg) ||
    /dailyLimitExceeded/i.test(msg) ||
    /PerDay/i.test(msg)
  );
}

/**
 * Record a failure against a provider and apply the right cooldown.
 * Returns true when the caller should retry (on another provider or after wait).
 */
function recordFailure(p: ProviderState, err: unknown): void {
  if (isDailyLimit(err)) {
    p.cooldownUntil = Date.now() + DAILY_COOLDOWN_MS;
    p.consecutiveRateLimits = 0;
    logger.warn(`${p.id} hit a daily limit — cooling down for 6h`);
    return;
  }
  if (isMinuteRateLimit(err)) {
    p.consecutiveRateLimits++;
    if (p.consecutiveRateLimits >= 2) {
      p.cooldownUntil = Date.now() + SHORT_COOLDOWN_MS;
      p.consecutiveRateLimits = 0;
      logger.warn(`${p.id} rate-limited twice — cooling down for 90s`);
    } else {
      const waitSec = parseRetrySeconds(err);
      p.cooldownUntil = Date.now() + waitSec * 1000;
      logger.warn(`${p.id} rate-limited — cooling down for ${waitSec}s`);
    }
    return;
  }
  // Generic failure — brief cooldown so we rotate to the next provider.
  p.cooldownUntil = Date.now() + 30_000;
  logger.warn(
    `${p.id} failed (${err instanceof Error ? err.message.slice(0, 160) : String(err).slice(0, 160)}) — cooling down for 30s`,
  );
}

// ── Truncated JSON repair ───────────────────────────────────────────

/** Attempt to repair a truncated JSON string by adding missing closing brackets. */
function repairJson(text: string): string | null {
  const start = text.search(/[[{]/);
  if (start === -1) return null;
  let json = text.slice(start);
  // If inside a string (odd number of unescaped quotes), close it
  let quotes = 0;
  let escaped = false;
  for (const ch of json) {
    if (escaped) { escaped = false; continue; }
    if (ch === '\\') { escaped = true; continue; }
    if (ch === '"') quotes++;
  }
  if (quotes % 2 !== 0) json += '"';
  // Count structural brackets
  const stack: string[] = [];
  let inStr = false;
  let esc = false;
  for (const ch of json) {
    if (esc) { esc = false; continue; }
    if (ch === '\\') { esc = true; continue; }
    if (ch === '"') { inStr = !inStr; continue; }
    if (inStr) continue;
    if (ch === '{') stack.push('}');
    if (ch === '[') stack.push(']');
    if (ch === '}' || ch === ']') stack.pop();
  }
  while (stack.length > 0) json += stack.pop();
  try { JSON.parse(json); return json; } catch { return null; }
}

// ── generateJson ────────────────────────────────────────────────────

const MAX_ATTEMPTS = 8;

export async function generateJson<T>(
  schema: z.ZodType<T>,
  opts: { system?: string; prompt: string; temperature?: number; maxOutputTokens?: number },
): Promise<T> {
  const temperature = opts.temperature ?? 0.2;
  const maxOutputTokens = opts.maxOutputTokens ?? 8192;
  const example = schemaToExample(schema);

  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    const provider = await pickProvider();
    await rateLimit(provider);

    // Path A: structured output when the provider still supports it.
    if (provider.generateObjectSupported) {
      try {
        const systemWithJson = opts.system
          ? `${opts.system} (in JSON format)`
          : 'Respond in JSON format.';
        const { object } = await generateObject({
          model: getModelFor(provider),
          schema,
          system: systemWithJson,
          prompt: opts.prompt,
          temperature,
          maxOutputTokens,
        });
        provider.consecutiveRateLimits = 0;
        return object as T;
      } catch (err) {
        if (isMinuteRateLimit(err) || isDailyLimit(err)) {
          recordFailure(provider, err);
          continue; // pick again (same provider after wait, or next in chain)
        }
        // Schema/format failure → disable structured output for THIS provider only.
        provider.generateObjectSupported = false;
        logger.warn(
          `generateObject unsupported on ${provider.id}, falling back to text+parse: ${
            err instanceof Error ? err.message.slice(0, 160) : String(err)
          }`,
        );
        // fall through to Path B on the same provider without re-picking
        await rateLimit(provider);
      }
    }

    // Path B: generateText + manual JSON extraction.
    try {
      const { text } = await generateText({
        model: getModelFor(provider),
        system:
          (opts.system ? `${opts.system}\n\n` : '') +
          'Respond with ONLY valid minified JSON. No markdown, no code fences, no prose.\n' +
          'Return ONLY the JSON object matching this structure:\n' +
          example,
        prompt: opts.prompt + '\n\nReturn the result as JSON.',
        temperature,
        maxOutputTokens,
      });
      provider.consecutiveRateLimits = 0;

      let json: unknown;
      try {
        json = extractJson(text);
      } catch {
        // One in-place retry with reduced scope (long lists often truncate).
        logger.warn(`JSON extraction failed on ${provider.id}. Retrying with reduced scope…`);
        await rateLimit(provider);
        const reducedPrompt =
          opts.prompt.replace(/up to \d+/gi, 'up to 15') +
          '\n\nKeep the JSON concise. Return at most 15 items. Return the result as JSON.';
        const { text: retryText } = await generateText({
          model: getModelFor(provider),
          system:
            (opts.system ? `${opts.system}\n\n` : '') +
            'Respond with ONLY valid minified JSON. No markdown, no code fences.\n' +
            'Return ONLY the JSON object matching this structure:\n' +
            example,
          prompt: reducedPrompt,
          temperature,
          maxOutputTokens,
        });
        json = extractJson(retryText);
      }

      try {
        return schema.parse(json);
      } catch (parseErr) {
        const lenient = lenientParse(schema, json);
        if (lenient !== undefined) return lenient;
        const repaired = repairJson(JSON.stringify(json));
        if (repaired) {
          try {
            return schema.parse(JSON.parse(repaired));
          } catch { /* fall through */ }
        }
        logger.warn(`Strict parse failed and lenient recovery had no effect: ${parseErr}`);
        throw parseErr;
      }
    } catch (err) {
      recordFailure(provider, err);
      continue;
    }
  }

  throw new Error(`generateJson failed after ${MAX_ATTEMPTS} attempts across the provider chain`);
}

// ── Lenient parse (drop invalid array elements) ─────────────────────

function lenientParse<T>(schema: z.ZodType<T>, json: unknown): T | undefined {
  if (!(json instanceof Object) || Array.isArray(json)) return undefined;
  const jsonObj = json as Record<string, unknown>;
  if (!(schema instanceof z.ZodObject)) return undefined;
  const shape = (schema as z.ZodTypeAny)._def.shape();
  const result: Record<string, unknown> = {};

  for (const [key, fieldSchema] of Object.entries(shape)) {
    if (!(key in jsonObj)) continue;
    if (fieldSchema instanceof z.ZodArray && Array.isArray(jsonObj[key])) {
      const elementSchema = (fieldSchema as z.ZodTypeAny)._def.type;
      const validElements: unknown[] = [];
      for (const element of jsonObj[key] as unknown[]) {
        const parsed = (elementSchema as z.ZodTypeAny).safeParse(element);
        if (parsed.success) {
          validElements.push(parsed.data);
        }
      }
      result[key] = validElements;
    } else {
      result[key] = jsonObj[key];
    }
  }

  if (Object.keys(result).length === 0) return undefined;

  try {
    return schema.parse(result);
  } catch {
    return undefined;
  }
}

// ── Schema → example string ─────────────────────────────────────────

function schemaToExample(schema: z.ZodType<unknown>, indent = ''): string {
  const def = (schema as ZodTypeAny)._def;
  if (schema instanceof z.ZodObject) {
    const shape = def.shape();
    const fields = Object.entries(shape).map(([key, val]) => {
      const inner = schemaToExample(val as z.ZodType<unknown>, `${indent}  `);
      return `${indent}  "${key}": ${inner}`;
    });
    return `{\n${fields.join(',\n')}\n${indent}}`;
  }
  if (schema instanceof z.ZodArray) {
    return `[${schemaToExample(schema.element, indent)}]`;
  }
  if (schema instanceof z.ZodString) {
    const desc = def.description;
    return desc ? `"${desc}"` : '"..."';
  }
  if (schema instanceof z.ZodNumber) {
    return '0';
  }
  if (schema instanceof z.ZodBoolean) {
    return 'true';
  }
  if (schema instanceof z.ZodEnum) {
    return `"${def.values.join('" | "')}"`;
  }
  if (schema instanceof z.ZodNullable) {
    return `${schemaToExample(schema.unwrap(), indent)} | null`;
  }
  if (schema instanceof z.ZodOptional) {
    return `${schemaToExample(schema.unwrap(), indent)} (optional)`;
  }
  if (schema instanceof z.ZodDefault) {
    return `${schemaToExample(schema.removeDefault(), indent)} (default: ${JSON.stringify(def.defaultValue())})`;
  }
  return '"..."';
}

// ── JSON extraction ─────────────────────────────────────────────────

export function extractJson(raw: string): unknown {
  const trimmed = raw.trim();
  const fenced = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/i);
  const body = fenced ? fenced[1].trim() : trimmed;
  try {
    return JSON.parse(body);
  } catch {
    const objMatch = body.match(/[[{][\s\S]*[\]}]/);
    if (objMatch) {
      try {
        return JSON.parse(objMatch[0]);
      } catch {
        const repaired = repairJson(objMatch[0]);
        if (repaired) return JSON.parse(repaired);
      }
    }
    throw new Error(`Could not extract JSON from LLM response: ${raw.slice(0, 200)}`);
  }
}

// ── generatePlainText ───────────────────────────────────────────────

export async function generatePlainText(opts: {
  system?: string;
  prompt: string;
  temperature?: number;
}): Promise<string> {
  for (let attempt = 0; attempt < 4; attempt++) {
    const provider = await pickProvider();
    await rateLimit(provider);
    try {
      const { text } = await generateText({
        model: getModelFor(provider),
        system: opts.system,
        prompt: opts.prompt,
        temperature: opts.temperature ?? 0.2,
      });
      provider.consecutiveRateLimits = 0;
      return text;
    } catch (err) {
      recordFailure(provider, err);
    }
  }
  throw new Error('generatePlainText failed after 4 attempts across the provider chain');
}
