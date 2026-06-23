import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { logJobSummary, logger } from './logger';

describe('logger secret redaction', () => {
  let consoleInfoSpy: ReturnType<typeof vi.spyOn>;
  let consoleErrorSpy: ReturnType<typeof vi.spyOn>;
  let consoleWarnSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    process.env.LOG_LEVEL = 'debug';
    consoleInfoSpy = vi.spyOn(console, 'info').mockImplementation(() => undefined);
    consoleErrorSpy = vi.spyOn(console, 'error').mockImplementation(() => undefined);
    consoleWarnSpy = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
  });

  afterEach(() => {
    delete process.env.LOG_LEVEL;
    vi.restoreAllMocks();
  });

  it('redacts object keys that look like secrets (CWE-312/532)', () => {
    logger.info('boot', {
      url: 'https://example.com',
      api_key: 'ol_secretvalue',
      SUPABASE_SERVICE_ROLE_KEY: 'eyJfake.jwt.token',
      password: 'hunter2',
    });

    const output = consoleInfoSpy.mock.calls[0]?.[0] as string;
    expect(output).toContain('[REDACTED]');
    expect(output).not.toContain('ol_secretvalue');
    expect(output).not.toContain('hunter2');
    expect(output).toContain('https://example.com');
  });

  it('scrubs JWT-shaped secrets interpolated into the message', () => {
    const fakeJwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ4In0.signaturepart';
    logger.info(`connected with token ${fakeJwt}`);

    const output = consoleInfoSpy.mock.calls[0]?.[0] as string;
    expect(output).not.toContain(fakeJwt);
    expect(output).toContain('[REDACTED]');
  });

  it('scrubs Stripe-shaped (sk_...) secrets from the message', () => {
    logger.info(`stripe key sk_live_0123456789abcdefgh loaded`);

    const output = consoleInfoSpy.mock.calls[0]?.[0] as string;
    expect(output).not.toContain('sk_live_0123456789abcdefgh');
    expect(output).toContain('[REDACTED]');
  });

  it('does not mutate benign numeric summaries', () => {
    logJobSummary('gbif', {
      processed: 10,
      upserted: 8,
      skipped: 2,
      errors: [],
    });

    const output = consoleInfoSpy.mock.calls[0]?.[0] as string;
    expect(output).toContain('"processed":10');
    expect(output).toContain('"upserted":8');
  });

  it('never logs the raw value of a process.env secret passed as meta', () => {
    process.env.FAKE_SECRET = 'supersecret-value-123';
    logger.info('step done', { FAKE_SECRET: process.env.FAKE_SECRET });

    const output = consoleInfoSpy.mock.calls[0]?.[0] as string;
    expect(output).not.toContain('supersecret-value-123');
    delete process.env.FAKE_SECRET;
  });
});
