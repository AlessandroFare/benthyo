/**
 * Shared LLM client for the ETL pipeline — OpenCode Zen (OpenAI-compatible).
 *
 * Uses the free `deepseek-v4-flash-free` model served by OpenCode Zen through
 * the AI SDK's `@ai-sdk/openai-compatible` provider. This keeps the whole
 * pipeline zero-budget while giving us a capable model for:
 *   - dive-site-discovery: enumerating real dive destinations & sites per region
 *   - species-seed / enrichment: normalising names, disambiguating taxa
 *   - photo species identification (vision) via the API
 *
 * Config (all optional except the API key):
 *   OPENCODE_ZEN_API_KEY   required — your OpenCode Zen key
 *   OPENCODE_ZEN_BASE_URL  default https://opencode.ai/zen/v1
 *   OPENCODE_ZEN_MODEL     default deepseek-v4-flash-free
 *
 * The helper degrades gracefully: `isLlmConfigured()` lets callers skip LLM
 * work entirely when no key is present, so the pipeline never hard-fails just
 * because the key is missing.
 */

import { createOpenAICompatible } from '@ai-sdk/openai-compatible';
import { generateObject, generateText, type LanguageModel } from 'ai';
import type { z } from 'zod';
import { logger } from './logger';

const BASE_URL = process.env.OPENCODE_ZEN_BASE_URL ?? 'https://opencode.ai/zen/v1';
const API_KEY = process.env.OPENCODE_ZEN_API_KEY ?? '';
const MODEL_ID = process.env.OPENCODE_ZEN_MODEL ?? 'deepseek-v4-flash-free';

/** True when an OpenCode Zen key is configured. */
export function isLlmConfigured(): boolean {
  return API_KEY.trim().length > 0;
}

/** Human-readable label for logs. */
export function llmLabel(): string {
  return `opencode-zen (${MODEL_ID})`;
}

let cachedModel: LanguageModel | null = null;

/** Lazily build (and cache) the OpenCode Zen chat model. */
export function getZenModel(): LanguageModel {
  if (!isLlmConfigured()) {
    throw new Error(
      'OPENCODE_ZEN_API_KEY is not set — set it to enable LLM-backed ETL steps',
    );
  }
  if (!cachedModel) {
    const provider = createOpenAICompatible({
      name: 'opencode-zen',
      baseURL: BASE_URL,
      apiKey: API_KEY,
    });
    cachedModel = provider.chatModel(MODEL_ID);
  }
  return cachedModel;
}

/**
 * Generate a structured object validated against a Zod schema.
 *
 * Primary path: AI SDK `generateObject` (JSON mode). Free/OpenAI-compatible
 * endpoints occasionally reject `response_format: json_schema`, so on failure
 * we fall back to a plain `generateText` call that asks for raw JSON and parse
 * it ourselves against the same schema. This makes the step resilient across
 * providers without changing call sites.
 */
export async function generateJson<T>(
  schema: z.ZodType<T>,
  opts: { system?: string; prompt: string; temperature?: number; maxOutputTokens?: number },
): Promise<T> {
  const model = getZenModel();
  const temperature = opts.temperature ?? 0.2;

  try {
    const { object } = await generateObject({
      model,
      schema,
      system: opts.system,
      prompt: opts.prompt,
      temperature,
    });
    return object as T;
  } catch (err) {
    logger.warn(
      `generateObject failed, falling back to text+parse: ${
        err instanceof Error ? err.message : String(err)
      }`,
    );
  }

  const { text } = await generateText({
    model,
    system:
      (opts.system ? `${opts.system}\n\n` : '') +
      'Respond with ONLY valid minified JSON. No markdown, no code fences, no prose.',
    prompt: opts.prompt,
    temperature,
  });

  const json = extractJson(text);
  return schema.parse(json);
}

/** Best-effort extraction of a JSON value from an LLM text response. */
export function extractJson(raw: string): unknown {
  const trimmed = raw.trim();
  // Strip ```json ... ``` fences if present.
  const fenced = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/i);
  const body = fenced ? fenced[1].trim() : trimmed;
  try {
    return JSON.parse(body);
  } catch {
    // Fall back to the first {...} or [...] block.
    const objMatch = body.match(/[[{][\s\S]*[\]}]/);
    if (objMatch) return JSON.parse(objMatch[0]);
    throw new Error(`Could not extract JSON from LLM response: ${raw.slice(0, 200)}`);
  }
}

/** Raw text completion (used for vision / free-form prompts). */
export async function generatePlainText(opts: {
  system?: string;
  prompt: string;
  temperature?: number;
}): Promise<string> {
  const model = getZenModel();
  const { text } = await generateText({
    model,
    system: opts.system,
    prompt: opts.prompt,
    temperature: opts.temperature ?? 0.2,
  });
  return text;
}
