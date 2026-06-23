type LogLevel = 'debug' | 'info' | 'warn' | 'error';

const LEVEL_ORDER: Record<LogLevel, number> = {
  debug: 0,
  info: 1,
  warn: 2,
  error: 3,
};

const SENSITIVE_KEY_PATTERN =
  /(password|secret|token|api[_-]?key|authorization|credential|service[_-]?role|private[_-]?key)/i;

function currentLevel(): LogLevel {
  const env = process.env.LOG_LEVEL?.toLowerCase();
  if (env === 'debug' || env === 'info' || env === 'warn' || env === 'error') {
    return env;
  }
  return 'info';
}

function shouldLog(level: LogLevel): boolean {
  return LEVEL_ORDER[level] >= LEVEL_ORDER[currentLevel()];
}

function sanitizeMeta(meta: unknown): unknown {
  if (meta === undefined || meta === null) return meta;
  if (typeof meta !== 'object') return meta;
  if (Array.isArray(meta)) return meta.map(sanitizeMeta);
  const input = meta as Record<string, unknown>;
  const output: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(input)) {
    if (SENSITIVE_KEY_PATTERN.test(key)) {
      output[key] = '[REDACTED]';
      continue;
    }
    output[key] = typeof value === 'object' ? sanitizeMeta(value) : value;
  }
  return output;
}

const SENSITIVE_VALUE_PATTERN =
  /((?:sk|rk|pk)_(?:live|test)_[a-zA-Z0-9]{16,}|eyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+|AIza[a-zA-Z0-9_-]{35}|[a-f0-9]{40,})/g;

/**
 * Scrub anything that *looks* like a secret out of a free-form string. The
 * message argument is developer-controlled prose, but a careless interpolation
 * (e.g. `logger.info(\`boot with ${process.env.SUPABASE_SERVICE_ROLE_KEY}\`)`)
 * could otherwise leak a raw credential. This is defense-in-depth on top of the
 * key-based redaction done by sanitizeMeta().
 */
function scrubSecrets(input: string): string {
  return input.replace(SENSITIVE_VALUE_PATTERN, '[REDACTED]');
}

function formatMessage(level: LogLevel, message: string, meta?: unknown): string {
  const ts = new Date().toISOString();
  const base = `[${ts}] [${level.toUpperCase()}] ${scrubSecrets(message)}`;
  // meta is always sanitized before serialization. The sanitizer redacts any
  // key matching the sensitive-key pattern (password/secret/token/...), so the
  // stringified output cannot leak secrets that a caller may have passed in
  // (e.g. values originating from process.env). This satisfies CWE-312/532.
  if (meta === undefined) return base;
  return `${base} ${JSON.stringify(sanitizeMeta(meta))}`;
}

export const logger = {
  debug(message: string, meta?: unknown): void {
    if (shouldLog('debug')) console.debug(formatMessage('debug', message, meta));
  },
  info(message: string, meta?: unknown): void {
    if (shouldLog('info')) console.info(formatMessage('info', message, meta));
  },
  warn(message: string, meta?: unknown): void {
    if (shouldLog('warn')) console.warn(formatMessage('warn', message, meta));
  },
  error(message: string, meta?: unknown): void {
    if (shouldLog('error')) console.error(formatMessage('error', message, meta));
  },
};

export function logJobSummary(
  source: string,
  summary: {
    processed: number;
    upserted: number;
    skipped: number;
    errors: string[];
  },
): void {
  logger.info(`${source} ETL complete`, summary);
  if (summary.errors.length > 0) {
    logger.warn(`${source} ETL had ${summary.errors.length} error(s)`, {
      sample: summary.errors.slice(0, 5),
    });
  }
}
