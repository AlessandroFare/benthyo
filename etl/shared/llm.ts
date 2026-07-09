/**
 * Shared LLM client for the ETL pipeline — multi-provider with auto-failover.
 *
 * Primary: Groq (fast, free tier 30 req/min, 100K TPD on llama-3.3-70b)
 * Fallback: OpenCode Zen (slower, no documented daily limit)
 *
 * When Groq hits its daily token limit (TPD), the client automatically
 * switches to OpenCode Zen for the rest of the process lifetime. This
 * lets the pipeline complete even on heavy days where Groq's 100K TPD
 * is exhausted after 2-3 regions.
 *
 * Config:
 *   ETL_LLM_PROVIDER          'groq' | 'opencode-zen' (default: auto)
 *   GROQ_API_KEY              Groq API key (free at console.groq.com)
 *   GROQ_LLM_MODEL            default llama-3.3-70b-versatile
 *   GROQ_BASE_URL             default https://api.groq.com/openai/v1
 *   OPENCODE_ZEN_API_KEY      OpenCode Zen key
 *   OPENCODE_ZEN_BASE_URL     default https://opencode.ai/zen/v1
 *   OPENCODE_ZEN_MODEL        default deepseek-v4-flash-free
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

// ── Provider config ─────────────────────────────────────────────────

const GOOGLE_API_KEY = process.env.GOOGLE_AI_API_KEY ?? '';
const GOOGLE_LLM_MODEL = process.env.GOOGLE_LLM_MODEL ?? 'gemini-2.5-flash';

const GROQ_API_KEY = process.env.GROQ_API_KEY ?? '';
const GROQ_BASE_URL = process.env.GROQ_BASE_URL ?? 'https://api.groq.com/openai/v1';
const GROQ_LLM_MODEL = process.env.GROQ_LLM_MODEL ?? 'llama-3.3-70b-versatile';

const ZEN_API_KEY = process.env.OPENCODE_ZEN_API_KEY ?? '';
const ZEN_BASE_URL = process.env.OPENCODE_ZEN_BASE_URL ?? 'https://opencode.ai/zen/v1';
const ZEN_MODEL_ID = process.env.OPENCODE_ZEN_MODEL ?? 'deepseek-v4-flash-free';

type Provider = 'google' | 'groq' | 'opencode-zen';

/** Active provider — can change at runtime. */
let activeProvider: Provider;

function resolveInitialProvider(): Provider {
  const explicit = (process.env.ETL_LLM_PROVIDER ?? '').toLowerCase();
  if (explicit === 'google' && GOOGLE_API_KEY) return 'google';
  if (explicit === 'groq' && GROQ_API_KEY) return 'groq';
  if (explicit === 'opencode-zen' && ZEN_API_KEY) return 'opencode-zen';
  if (GOOGLE_API_KEY) return 'google';
  if (GROQ_API_KEY) return 'groq';
  if (ZEN_API_KEY) return 'opencode-zen';
  return 'google';
}

activeProvider = resolveInitialProvider();

/** True when any LLM key is configured. */
export function isLlmConfigured(): boolean {
  return GOOGLE_API_KEY.trim().length > 0 || GROQ_API_KEY.trim().length > 0 || ZEN_API_KEY.trim().length > 0;
}

/** Human-readable label for logs. */
export function llmLabel(): string {
  if (activeProvider === 'google') return `google (${GOOGLE_LLM_MODEL})`;
  if (activeProvider === 'groq') return `groq (${GROQ_LLM_MODEL})`;
  return `opencode-zen (${ZEN_MODEL_ID})`;
}

let googleModel: LanguageModel | null = null;
let groqModel: LanguageModel | null = null;
let zenModel: LanguageModel | null = null;
  // Try generateObject on all providers; disable per-provider on first failure.
  let generateObjectSupported = true;

function getGoogleModel(): LanguageModel {
  if (!googleModel) {
    const provider = createGoogleGenerativeAI({
      apiKey: GOOGLE_API_KEY,
    });
    googleModel = provider.chat(GOOGLE_LLM_MODEL) as unknown as LanguageModel;
  }
  return googleModel;
}

function getGroqModel(): LanguageModel {
  if (!groqModel) {
    const provider = createOpenAICompatible({
      name: 'groq',
      baseURL: GROQ_BASE_URL,
      apiKey: GROQ_API_KEY,
    });
    groqModel = provider.chatModel(GROQ_LLM_MODEL);
  }
  return groqModel;
}

function getZenModelInternal(): LanguageModel {
  if (!zenModel) {
    const provider = createOpenAICompatible({
      name: 'opencode-zen',
      baseURL: ZEN_BASE_URL,
      apiKey: ZEN_API_KEY,
    });
    zenModel = provider.chatModel(ZEN_MODEL_ID);
  }
  return zenModel;
}

/** Get the model for the currently active provider. */
export function getLlmModel(): LanguageModel {
  if (!isLlmConfigured()) {
    throw new Error(
      'No LLM API key is set — set GOOGLE_AI_API_KEY, GROQ_API_KEY, or OPENCODE_ZEN_API_KEY',
    );
  }
  if (activeProvider === 'google') {
    if (!GOOGLE_API_KEY) throw new Error('GOOGLE_AI_API_KEY not set');
    return getGoogleModel();
  }
  if (activeProvider === 'groq') {
    if (!GROQ_API_KEY) throw new Error('GROQ_API_KEY not set');
    return getGroqModel();
  }
  if (!ZEN_API_KEY) throw new Error('OPENCODE_ZEN_API_KEY not set');
  return getZenModelInternal();
}

/** Backward compat alias. */
export const getZenModel = getLlmModel;

// ── Rate limiting ───────────────────────────────────────────────────

const TEXT_INTERVAL_MS = 4000; // Google free: 20 req/min → 4s = 15/min (safe buffer for retries)
let lastTextCallAt = 0;

async function textRateLimit(): Promise<void> {
  const elapsed = Date.now() - lastTextCallAt;
  const wait = TEXT_INTERVAL_MS - elapsed;
  if (wait > 0) await sleep(wait);
  lastTextCallAt = Date.now();
}

// ── Failover detection ──────────────────────────────────────────────

/** True when an error message indicates a per-minute quota/rate limit (recoverable after wait). */
function isMinuteRateLimit(err: unknown): boolean {
  const msg = err instanceof Error ? err.message : String(err);
  return /rate limit/i.test(msg) || /quota exceeded/i.test(msg) || /current quota/i.test(msg);
}

/** Extract retry-after seconds from a Google "Please retry in Xs" message. */
function parseRetrySeconds(err: unknown): number {
  const msg = err instanceof Error ? err.message : String(err);
  const m = msg.match(/retry in ([\d.]+)s/i);
  return m ? Math.ceil(Number(m[1])) + 2 : 15;
}

/** True when an error message indicates a daily limit (unrecoverable, must failover). */
function isDailyLimit(err: unknown): boolean {
  const msg = err instanceof Error ? err.message : String(err);
  return (
    /TPD|TPM/i.test(msg) ||
    /tokens per day/i.test(msg) ||
    /daily limit/i.test(msg) ||
    /daily.*request.*quota/i.test(msg) ||
    /dailyLimitExceeded/i.test(msg)
  );
}

const PROVIDER_CHAIN: Provider[] = ['google', 'groq', 'opencode-zen'];

/** Try the next provider in the chain. Returns true when a fallback is available. */
function failoverToNextProvider(): boolean {
  const idx = PROVIDER_CHAIN.indexOf(activeProvider);
  for (let i = idx + 1; i < PROVIDER_CHAIN.length; i++) {
    const next = PROVIDER_CHAIN[i];
    if (next === 'groq' && GROQ_API_KEY) {
      activeProvider = 'groq';
      generateObjectSupported = true;
      logger.warn(`Failing over to groq (${GROQ_LLM_MODEL})`);
      return true;
    }
    if (next === 'opencode-zen' && ZEN_API_KEY) {
      activeProvider = 'opencode-zen';
      generateObjectSupported = true;
      logger.warn(`Failing over to OpenCode Zen (${ZEN_MODEL_ID})`);
      return true;
    }
  }
  return false;
}

// ── Truncated JSON repair ───────────────────────────────────────────

/** Attempt to repair a truncated JSON string by adding missing closing brackets. */
function repairJson(text: string): string | null {
  const start = text.search(/[[{]/);
  if (start === -1) return null;
  let json = text.slice(start);
  const quoteStack: number[] = [];
  let escaped = false;
  for (let i = 0; i < json.length; i++) {
    const ch = json[i];
    if (escaped) { escaped = false; continue; }
    if (ch === '\\') { escaped = true; continue; }
    if (ch === '"') {
      if (quoteStack.length > 0 && quoteStack[quoteStack.length - 1] === i - 1) {
        // empty string — leave
      }
      quoteStack.push(i);
      continue;
    }
  }
  // If inside a string (odd number of quotes), close it
  if (quoteStack.length % 2 !== 0) {
    json += '"';
  }
  // Count structural brackets
  let opens = 0;
  let closes = 0;
  let inStr = false;
  let esc = false;
  for (const ch of json) {
    if (esc) { esc = false; continue; }
    if (ch === '\\') { esc = true; continue; }
    if (ch === '"') { inStr = !inStr; continue; }
    if (inStr) continue;
    if (ch === '{' || ch === '[') opens++;
    if (ch === '}' || ch === ']') closes++;
  }
  const diff = opens - closes;
  if (diff > 0) {
    json += ']}'[json.startsWith('[') ? 0 : 1].repeat(diff);
  }
  try { JSON.parse(json); return json; } catch { return null; }
}

// ── generateJson ────────────────────────────────────────────────────

export async function generateJson<T>(
  schema: z.ZodType<T>,
  opts: { system?: string; prompt: string; temperature?: number; maxOutputTokens?: number },
): Promise<T> {
  const temperature = opts.temperature ?? 0.2;
  const maxOutputTokens = opts.maxOutputTokens ?? 8192;

  // Try generateObject first (once)
  if (generateObjectSupported) {
    try {
      await textRateLimit();
      const systemWithJson = opts.system
        ? `${opts.system} (in JSON format)`
        : 'Respond in JSON format.';
      const { object } = await generateObject({
        model: getLlmModel(),
        schema,
        system: systemWithJson,
        prompt: opts.prompt,
        temperature,
        maxOutputTokens,
      });
      return object as T;
    } catch (err) {
      generateObjectSupported = false;
      if (isDailyLimit(err) && failoverToNextProvider()) {
        return generateJson(schema, opts);
      }
      // generateObject rate limit → wait once then fall through to generateText
      if (isMinuteRateLimit(err)) {
        const waitSec = parseRetrySeconds(err);
        logger.warn(`Rate limit hit, waiting ${waitSec}s…`);
        await sleep(waitSec * 1000);
        // fall through to generateText
      } else {
        logger.warn(
          `generateObject failed: ${err instanceof Error ? err.message : String(err)}`,
        );
      }
    }
  }

  const example = schemaToExample(schema);
  let consecutiveRateLimits = 0;

  // Fallback: generateText + manual JSON parse
  // Max 6 attempts — rate limit retries wait Google's suggested time so each
  // retry gives the rolling window time to clear.
  const MAX_FALLBACK_ATTEMPTS = 6;
  for (let attempt = 0; attempt < MAX_FALLBACK_ATTEMPTS; attempt++) {
    await textRateLimit();
    try {
      const { text } = await generateText({
        model: getLlmModel(),
        system:
          (opts.system ? `${opts.system}\n\n` : '') +
          'Respond with ONLY valid minified JSON. No markdown, no code fences, no prose.\n' +
          'Return ONLY the JSON object matching this structure:\n' +
          example,
        prompt: opts.prompt + '\n\nReturn the result as JSON.',
        temperature,
        maxOutputTokens,
      });

      // Reset rate limit counter on success
      consecutiveRateLimits = 0;

      let json: unknown;
      try {
        json = extractJson(text);
      } catch (extractErr) {
        if (attempt === 0) {
          logger.warn(
            `JSON extraction failed (${extractErr instanceof Error ? extractErr.message : String(extractErr)}). Retrying with reduced scope…`,
          );
          const reducedPrompt = opts.prompt.replace(/up to \d+/gi, 'up to 15') +
            '\n\nKeep the JSON concise. Return at most 15 items. Return the result as JSON.';
          try {
            const { text: retryText } = await generateText({
              model: getLlmModel(),
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
          } catch (reExtractErr) {
            throw reExtractErr;
          }
        } else {
          throw extractErr;
        }
      }

      try {
        return schema.parse(json);
      } catch (parseErr) {
        // Try lenient parse first
        const lenient = lenientParse(schema, json);
        if (lenient !== undefined) return lenient;
        // Try repaired JSON
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
      if (isDailyLimit(err) && failoverToNextProvider()) {
        consecutiveRateLimits = 0;
        continue;
      }
      if (isMinuteRateLimit(err)) {
        consecutiveRateLimits++;
        // After 2 consecutive per-minute rate limits → treat as daily and failover
        if (consecutiveRateLimits >= 2 && failoverToNextProvider()) {
          logger.warn(`2 consecutive rate limits — failing over to next provider`);
          continue;
        }
        const waitSec = Math.max(parseRetrySeconds(err), 10);
        logger.warn(`Rate limit (${attempt + 1}/${MAX_FALLBACK_ATTEMPTS}), waiting ${waitSec}s…`);
        await sleep(waitSec * 1000);
        continue;
      }
      // Any persistent failure → try next provider in chain
      if (failoverToNextProvider()) {
        consecutiveRateLimits = 0;
        continue;
      }
      throw err;
    }
  }

  // Last resort: try the next provider regardless of error type
  if (failoverToNextProvider()) {
    return generateJson(schema, opts);
  }
  throw new Error(`generateJson failed after ${MAX_FALLBACK_ATTEMPTS} retries and provider fallbacks`);
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
    if (objMatch) return JSON.parse(objMatch[0]);
    throw new Error(`Could not extract JSON from LLM response: ${raw.slice(0, 200)}`);
  }
}

// ── generatePlainText ───────────────────────────────────────────────

export async function generatePlainText(opts: {
  system?: string;
  prompt: string;
  temperature?: number;
}): Promise<string> {
  await textRateLimit();
  try {
    const { text } = await generateText({
      model: getLlmModel(),
      system: opts.system,
      prompt: opts.prompt,
      temperature: opts.temperature ?? 0.2,
    });
    return text;
  } catch (err) {
    if (failoverToNextProvider()) {
      await textRateLimit();
      const { text } = await generateText({
        model: getLlmModel(),
        system: opts.system,
        prompt: opts.prompt,
        temperature: opts.temperature ?? 0.2,
      });
      return text;
    }
    throw err;
  }
}
