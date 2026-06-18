#!/usr/bin/env node
/**
 * Sanitize the local .env file by replacing all known secret values
 * with placeholders. Run this ONCE after cloning the repo:
 *
 *   node scripts/sanitize-env.js
 *
 * The script is idempotent — running it again is a no-op.
 *
 * IMPORTANT: After running this, set the real values for local dev from
 * your password manager. The .env file is gitignored.
 */

const fs = require('fs');
const path = require('path');

const ENV_PATH = path.join(__dirname, '..', '.env');

const SECRET_PATTERNS = [
  { from: /^SUPABASE_SERVICE_ROLE_KEY=.*$/m, to: 'SUPABASE_SERVICE_ROLE_KEY=__set_me__' },
  { from: /^R2_SECRET_ACCESS_KEY=.*$/m, to: 'R2_SECRET_ACCESS_KEY=__set_me__' },
  { from: /^APIFY_TOKEN=.*$/m, to: 'APIFY_TOKEN=__set_me__' },
  { from: /^TAVILY_API_KEY=.*$/m, to: 'TAVILY_API_KEY=__set_me__' },
  { from: /^DIVENUMBER_API_KEY=.*$/m, to: 'DIVENUMBER_API_KEY=__set_me__' },
  { from: /^STRIPE_SECRET_KEY=.*$/m, to: 'STRIPE_SECRET_KEY=__set_me__' },
  { from: /^STRIPE_WEBHOOK_SECRET=.*$/m, to: 'STRIPE_WEBHOOK_SECRET=__set_me__' },
  { from: /^CRON_SHARED_SECRET=.*$/m, to: 'CRON_SHARED_SECRET=__set_me__' },
  { from: /^ADMIN_API_KEY=.*$/m, to: 'ADMIN_API_KEY=__set_me__' },
  { from: /^MEDICAL_ENCRYPTION_MASTER_KEY=.*$/m, to: 'MEDICAL_ENCRYPTION_MASTER_KEY=__set_me__' },
  { from: /^ETL_SYSTEM_USER_ID=.*$/m, to: 'ETL_SYSTEM_USER_ID=__set_me__' },
];

let original;
try {
  original = fs.readFileSync(ENV_PATH, 'utf8');
} catch (err) {
  console.error(`Cannot read ${ENV_PATH}: ${err.message}`);
  process.exit(1);
}

let sanitized = original;
let changed = false;
for (const { from, to } of SECRET_PATTERNS) {
  if (from.test(sanitized)) {
    sanitized = sanitized.replace(from, to);
    changed = true;
  }
}

if (!changed) {
  console.log('.env is already sanitized — nothing to do.');
  process.exit(0);
}

fs.writeFileSync(ENV_PATH, sanitized, 'utf8');
console.log('.env sanitized. Replace the __set_me__ placeholders with your real values for local dev.');
