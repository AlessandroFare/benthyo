import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AiVisionConfig } from '../config/ai-vision.config';

/**
 * Structured result of an AI vision identification. All fields are
 * best-effort — the caller reconciles this against iNaturalist and the
 * local catalog before trusting it.
 */
export interface AiVisionResult {
  scientific_name: string | null;
  common_name: string | null;
  common_name_it: string | null;
  common_name_es: string | null;
  family: string | null;
  genus: string | null;
  /** 0..1 self-reported confidence. */
  confidence: number;
  /** Short human-readable justification (shown to the diver). */
  rationale: string | null;
  /** The model's judgement on whether this is a marine organism. */
  is_marine: boolean;
  /** Provider/model label for telemetry + UI ("AI" badge). */
  source: string;
}

/**
 * AiVisionService — "sees" a photo and proposes a species using a free
 * multimodal LLM (Groq Llama 4 Scout) via the OpenAI-compatible Chat
 * Completions API.
 *
 * Uses `fetch` directly (no extra dependency): the API package stays lean
 * and portable, and the same call shape works against any OpenAI-compatible
 * vision endpoint if we ever swap providers.
 */
@Injectable()
export class AiVisionService {
  private readonly logger = new Logger(AiVisionService.name);
  private readonly cfg: AiVisionConfig;

  constructor(configService: ConfigService) {
    this.cfg =
      configService.get<AiVisionConfig>('aiVision') ?? {
        groqApiKey: '',
        groqBaseUrl: 'https://api.groq.com/openai/v1',
        groqModel: 'meta-llama/llama-4-scout-17b-16e-instruct',
      };
  }

  /** True when a Groq key is configured and the AI step can run. */
  isConfigured(): boolean {
    return this.cfg.groqApiKey.trim().length > 0;
  }

  /** Human-readable label for logs and the UI badge. */
  label(): string {
    return `groq (${this.cfg.groqModel})`;
  }

  /**
   * Identify the species in an image. Returns null when the feature is
   * disabled, the model is unsure, or on any error — the caller then
   * falls back to iNaturalist alone.
   */
  async identify(imageUrl: string): Promise<AiVisionResult | null> {
    if (!this.isConfigured()) return null;

    const system =
      'You are a marine biologist specialising in scuba-diving fauna and flora. ' +
      'You identify the single most likely species in an underwater photo. ' +
      'Prefer species commonly seen while scuba diving. If the photo does not ' +
      'clearly show a marine organism, set scientific_name to null. ' +
      'Respond with ONLY a valid minified JSON object, no markdown, matching: ' +
      '{"scientific_name":string|null,"common_name":string|null,' +
      '"common_name_it":string|null,"common_name_es":string|null,' +
      '"family":string|null,"genus":string|null,"confidence":number,' +
      '"rationale":string,"is_marine":boolean}. ' +
      'confidence is 0..1. common_name is English. Use accepted binomial ' +
      'scientific names only.';

    const body = {
      model: this.cfg.groqModel,
      temperature: 0.1,
      max_tokens: 512,
      response_format: { type: 'json_object' as const },
      messages: [
        { role: 'system' as const, content: system },
        {
          role: 'user' as const,
          content: [
            {
              type: 'text' as const,
              text: 'Identify the species in this diving photo. Return the JSON object only.',
            },
            {
              type: 'image_url' as const,
              image_url: { url: imageUrl },
            },
          ],
        },
      ],
    };

    let raw: string;
    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 20_000);
      let response: Response;
      try {
        response = await fetch(`${this.cfg.groqBaseUrl}/chat/completions`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${this.cfg.groqApiKey}`,
          },
          body: JSON.stringify(body),
          signal: controller.signal,
        });
      } finally {
        clearTimeout(timeout);
      }

      if (!response.ok) {
        const detail = await response.text().catch(() => '');
        this.logger.warn(
          `Groq vision returned ${response.status}: ${detail.slice(0, 200)}`,
        );
        return null;
      }

      const json = (await response.json()) as {
        choices?: Array<{ message?: { content?: string } }>;
      };
      raw = json.choices?.[0]?.message?.content ?? '';
    } catch (err) {
      this.logger.warn(
        `Groq vision call failed: ${err instanceof Error ? err.message : String(err)}`,
      );
      return null;
    }

    const parsed = this.parseJson(raw);
    if (!parsed) return null;

    const scientific = this.cleanString(parsed['scientific_name']);
    // A result with no scientific name is useless downstream.
    if (!scientific) return null;

    const confidence = this.clampConfidence(parsed['confidence']);

    return {
      scientific_name: scientific,
      common_name: this.cleanString(parsed['common_name']),
      common_name_it: this.cleanString(parsed['common_name_it']),
      common_name_es: this.cleanString(parsed['common_name_es']),
      family: this.cleanString(parsed['family']),
      genus: this.cleanString(parsed['genus']) ?? scientific.split(' ')[0],
      confidence,
      rationale: this.cleanString(parsed['rationale']),
      is_marine: parsed['is_marine'] !== false,
      source: `groq-${this.cfg.groqModel}`,
    };
  }

  private parseJson(raw: string): Record<string, unknown> | null {
    const trimmed = (raw ?? '').trim();
    if (!trimmed) return null;
    const fenced = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/i);
    const bodyText = fenced ? fenced[1].trim() : trimmed;
    try {
      return JSON.parse(bodyText) as Record<string, unknown>;
    } catch {
      const objMatch = bodyText.match(/\{[\s\S]*\}/);
      if (objMatch) {
        try {
          return JSON.parse(objMatch[0]) as Record<string, unknown>;
        } catch {
          return null;
        }
      }
      return null;
    }
  }

  private cleanString(value: unknown): string | null {
    if (typeof value !== 'string') return null;
    const trimmed = value.trim();
    if (!trimmed) return null;
    const lower = trimmed.toLowerCase();
    if (lower === 'null' || lower === 'unknown' || lower === 'n/a') return null;
    return trimmed;
  }

  private clampConfidence(value: unknown): number {
    const n = typeof value === 'number' ? value : Number(value);
    if (!Number.isFinite(n)) return 0;
    if (n < 0) return 0;
    if (n > 1) return Math.min(n / 100, 1); // tolerate 0..100 scale
    return n;
  }
}
