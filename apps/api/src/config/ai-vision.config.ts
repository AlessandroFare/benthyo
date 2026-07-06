import { registerAs } from '@nestjs/config';

/**
 * Configuration for AI-powered photo species identification.
 *
 * We use Groq's OpenAI-compatible endpoint with a free multimodal model
 * (Llama 4 Scout) to "look at" the uploaded photo and propose a species.
 * Groq's free developer tier requires no credit card, keeping the whole
 * feature zero-budget — consistent with the ETL pipeline (OpenCode Zen).
 *
 * The feature degrades gracefully: when `GROQ_API_KEY` is absent the AI
 * step is skipped and identification falls back to iNaturalist's vision
 * API alone (the previous behaviour).
 *
 * Env:
 *   GROQ_API_KEY        required to enable the AI vision step
 *   GROQ_BASE_URL       default https://api.groq.com/openai/v1
 *   GROQ_VISION_MODEL   default meta-llama/llama-4-scout-17b-16e-instruct
 */
export interface AiVisionConfig {
  groqApiKey: string;
  groqBaseUrl: string;
  groqModel: string;
}

export default registerAs(
  'aiVision',
  (): AiVisionConfig => ({
    groqApiKey: process.env['GROQ_API_KEY'] ?? '',
    groqBaseUrl:
      process.env['GROQ_BASE_URL'] ?? 'https://api.groq.com/openai/v1',
    groqModel:
      process.env['GROQ_VISION_MODEL'] ??
      'meta-llama/llama-4-scout-17b-16e-instruct',
  }),
);
