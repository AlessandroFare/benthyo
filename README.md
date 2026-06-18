# OceanLog

> B2B-anchored citizen-science platform for scuba diving.

Divers use the mobile app to log dives, discover sites, and record
marine species sightings. Dive centers and liveaboards use the web
dashboard to manage customers, sites, and analytics. Verified
sightings feed a GBIF-exportable data moat with contributor
attribution.

**Stack:** Flutter (mobile) · NestJS (API) · Supabase (PostgreSQL +
PostGIS + RLS + Edge Functions) · Cloudflare R2 (media) · GitHub
Actions (ETL cron) · Stripe (billing) · Resend (transactional email).

**$0/month launch target** on free tiers; production-grade path
documented in [`docs/configuration.md`](docs/configuration.md).

---

## Table of contents

- [Quick start](#quick-start)
- [Architecture](#architecture)
- [Repository layout](#repository-layout)
- [Local development](#local-development)
- [ETL pipeline](#etl-pipeline)
- [Security model](#security-model)
- [Subscriptions & billing](#subscriptions--billing)
- [GDPR compliance](#gdpr-compliance)
- [Testing](#testing)
- [Deployment](#deployment)
- [Contributing](#contributing)

---

## Quick start

```bash
git clone <repo-url> && cd oceanlog
pnpm install
node scripts/sanitize-env.js        # replace real secrets with placeholders
cp .env.example .env                # fill in real values for local dev
docker compose up -d                # Postgres + PostGIS on 54322, Redis on 6379
supabase start                       # local Supabase stack on 54321
psql "$DATABASE_URL" -f supabase/migrations/000_extensions.sql
for f in supabase/migrations/0*.sql; do
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$f"
done
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/seed.sql
pnpm --filter @oceanlog/types build
pnpm dev:api                         # http://localhost:3000
pnpm dev:dashboard                   # http://localhost:5173
cd apps/mobile && flutter run -d chrome \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=$SUPABASE_ANON_KEY \
  --dart-define=API_URL=http://localhost:3000/api/v1
```

See [`docs/setup.md`](docs/setup.md) for full setup details and
[`docs/configuration.md`](docs/configuration.md) for production env
vars.

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────────┐
│ Flutter App │────▶│  NestJS API  │────▶│ Supabase (PG)   │
│  (mobile)   │     │  + R2 media  │     │ PostGIS + RLS   │
└─────────────┘     └──────────────┘     └────────┬────────┘
       │                    ▲                     │
       │ offline sqflite    │                     ▼
       └────────────────────┘            ┌─────────────────┐
┌─────────────┐                          │ Edge Functions  │
│  Dashboard  │─────────────────────────▶│ badges, digest  │
│   (React)   │                          └─────────────────┘
└─────────────┘
       ▲
       │ GitHub Actions cron
┌──────┴──────┐
│ ETL: GBIF   │
│ OBIS WoRMS  │
│ + more     │
└─────────────┘
```

| Layer        | Tech                                                                                  |
|--------------|---------------------------------------------------------------------------------------|
| Mobile       | Flutter, Riverpod, GoRouter, flutter_map, sqflite                                     |
| Backend      | NestJS, Supabase JS, Sentry, Pino                                                     |
| Database     | Supabase PostgreSQL + PostGIS + RLS                                                  |
| Media        | Cloudflare R2 (presigned uploads; no server-side streaming)                          |
| Dashboard    | React, Vite, Tailwind, shadcn/ui, Recharts, Framer Motion                             |
| ETL          | TypeScript, tsx, Vitest, GitHub Actions                                               |
| Billing      | Stripe (subscriptions + webhooks)                                                      |
| Auth         | Supabase Auth (JWT)                                                                  |
| Email        | Resend (transactional)                                                                |
| Errors       | Sentry (mobile + API + dashboard)                                                     |
| Analytics    | PostHog (opt-in)                                                                     |

## Repository layout

```
oceanlog/
├── apps/
│   ├── api/            # NestJS backend
│   ├── dashboard/      # React B2B dashboard
│   ├── mcp-server/     # MCP integration (Claude / Cursor)
│   └── mobile/         # Flutter consumer app
├── packages/
│   └── types/          # @oceanlog/types — shared DTOs
├── supabase/
│   ├── migrations/     # 000..030 in order
│   ├── functions/      # Edge Functions (Deno)
│   ├── seed.sql        # 50 Mediterranean sites, 200 species, 5 operators
│   └── config.toml     # Supabase local stack config
├── etl/                # GBIF, OBIS, WoRMS, OpenDiveMap, Overpass, etc.
├── docs/                # Architecture, API, decisions, configuration
├── scripts/             # Sanitization, dev tooling
└── .github/workflows/   # CI + deploy + ETL cron
```

## Local development

```bash
# Run all services in dev mode
pnpm dev:api          # NestJS on :3000 with hot reload
pnpm dev:dashboard    # Vite on :5173
flutter run -d chrome # mobile (after cd apps/mobile)

# Type-check everything
pnpm -r typecheck

# Run all unit tests
pnpm -r test

# Run the ETL dry-run for a single source
pnpm --filter @oceanlog/etl gbif

# Run the full data pipeline
pnpm --filter @oceanlog/etl all-data
```

The Supabase local stack (`supabase start`) is required for `pnpm dev:api`.
Docker Compose also runs a Postgres+PostGIS image for direct DB work.

## ETL pipeline

The ETL pipeline runs in dependency order. The executed order lives in
[`etl/run-all-data.ts`](etl/run-all-data.ts), which is the single source
of truth; see [`docs/decisions.md`](docs/decisions.md) (ADR-015) for the
rationale.

```
1. worms                              ─ canonical taxonomy (EN/IT/ES vernaculars); first so occurrences can link by scientific name
2. dive sites (parallel):             ─ opendivemap & overpass & divenumber
3. apify:google-maps                  ─ Google Maps (slowest; runs last in the site batch)
4. occurrences (parallel): gbif & obis ─ independent sources; run concurrently
5. reconcile_unmatched_occurrences    ─ open-water placeholder sites (gbif then obis)
6. inat:taxon-lookup                  ─ resolve inat_taxon_id; MUST precede the image backfills
7. images (sequential):               ─ wikimedia:images → inaturalist:images → tavily:species
```

The `all-data` script runs the chain in this order. Each step is
idempotent on its `onConflict` key, so re-runs are safe. Each top-level
step is failure-isolated: a single failing source is logged and the
pipeline continues, exiting non-zero at the end if any step failed.

## Security model

OceanLog is multi-tenant and security-sensitive. The full audit and
remediation are documented in
[`SECURITY_AUDIT.md`](SECURITY_AUDIT.md). The core invariants:

- **Every table has RLS enabled.** Default deny. Service role bypasses
  for cron jobs only.
- **API requests always go through a per-request RLS-aware Supabase
  client.** No `fallbackUserId` path. The previous "fall back to
  service role if the token is empty" was a privilege escalation bug
  and is now removed.
- **Operator role checks are explicit at the controller layer** AND
  enforced at the RLS layer. Defense in depth.
- **Subscription tier is column-restricted** — only the
  `set_operator_subscription()` SECURITY DEFINER function can change
  `subscription_tier` / `subscription_status`. Operators cannot
  self-upgrade.
- **Sightings verification requires `taxonomy_expert = true`.**
  Self-verify is rejected at the service layer.
- **Medical form answers are encrypted at rest** with a per-operator
  key derived from a platform-managed master key (pgcrypto).
- **Waiver signatures are legally binding under eIDAS** (SES
  compliance): we capture IP, User-Agent, signer email, and a SHA256
  of the signed waiver body.
- **CORS hard-fails in production** if the origin list is unset. No
  `origin: true` reflection.
- **No secrets in client bundles.** The publishable key is meant to be
  public; service role keys never leave the server.

## Subscriptions & billing

Three tiers, configured in the `operators` table. The **Compliance bundle**
(digital waivers + medical questionnaires) is the headline paid hook: it is
a legal/liability need rather than a nice-to-have, so it anchors the Pro
tier and is the primary upgrade driver for dive centers.

| Tier    | Price (target) | Sites | Team | What you get                                                                 |
|---------|----------------|-------|------|------------------------------------------------------------------------------|
| Free    | €0            | 3     | 1    | Dive logs, sightings, life list, public site/species pages                   |
| Starter | €29/mo        | 10    | 5    | + Analytics, customer CRM, daily roster                                      |
| Pro     | €79/mo        | 100   | 20   | + **Compliance bundle (waivers + medical)**, marketplace, rental gear, API keys |

> **Compliance bundle** = digitally signed, eIDAS-binding waivers
> (IP + UA + SHA256 capture) and encrypted medical questionnaires
> (GDPR Art. 9, HMAC-SHA256-derived per-tenant keys). Publishing a waiver
> version is gated by `@RequireTier('pro')` + `TierGuard`; medical signing
> by divers stays free.

The `RequireTier()` decorator on a route enforces the minimum tier.
Subscription state is mutated only by the Stripe webhook
(`/v1/billing/stripe/webhook`) → `set_operator_subscription()`
SQL function. Operators cannot self-upgrade; Stripe is the source of
truth.

Test the webhook locally:

```bash
stripe listen --forward-to localhost:3000/api/v1/billing/stripe/webhook \
  --print-secret
# use the whsec_… value as STRIPE_WEBHOOK_SECRET in your .env
```

## GDPR compliance

- **Right to access:** `GET /v1/users/me/export` returns a JSON dump
  of every table row tied to the caller (profile, dive logs, sightings,
  life list, badges, gear, trips, site reviews, medical submissions,
  waiver signatures, API keys, social posts, buddy messages). Auth
  required.
- **Right to erasure:** `DELETE /v1/users/me` initiates the cascade
  (R2 photo cleanup → iNat observation deletion → `auth.admin.deleteUser`
  which triggers the DB cascade). The Stripe data processor agreement
  is in the project wiki.
- **Medical form encryption:** see the security model above.
- **Waiver signatures:** IP, User-Agent, signer email, and a SHA256 of
  the signed waiver body are captured. The DB trigger
  `prevent_signed_waiver_delete` blocks deletion of any waiver that
  has signatures attached.
- **Default cookie consent:** the only cookie set by OceanLog is the
  Supabase auth token, which is treated as strictly necessary. No
  consent banner is required for that. PostHog is opt-in.

## Testing

- **API unit tests** (`apps/api/src/**/*.spec.ts`): mock the Supabase
  client, exercise the service layer. Run with `pnpm --filter @oceanlog/api test`.
- **RLS test suite** (`supabase/tests/rls.sql`): bootstrap test rows
  under `anon`, `authenticated`, and `service_role` contexts and
  assert visibility + write permissions for every table. Run with
  `psql $DATABASE_URL -v ON_ERROR_STOP=1 -f supabase/tests/rls.sql`.
- **ETL tests** (`etl/*/*.test.ts`): mock the upstream API responses,
  verify the upsert payloads. Run with `pnpm --filter @oceanlog/etl test`.
- **Flutter widget + integration tests** (`apps/mobile/test/`):
  exercise the auth state machine, the sync queue idempotency, and
  the bottom sheets. Run with `flutter test` from `apps/mobile`.

CI runs the API + ETL tests on every PR; the Flutter tests run on
push to `main`.

## Deployment

Three targets:

| Target  | URL                                          | Deploy  |
|---------|----------------------------------------------|---------|
| API     | https://api.oceanlog.app                    | Railway |
| Dashboard | https://app.oceanlog.app                  | Cloudflare Pages |
| Mobile  | (Play Store / App Store)                    | Fastlane |

Deploys are triggered by the GitHub Actions workflows in
`.github/workflows/`:

- `ci.yml` — lint + typecheck + tests on PR
- `deploy-api.yml` — Railway deploy on push to `main` (apps/api/** paths)
- `deploy-dashboard.yml` — Cloudflare Pages deploy on push to `main`
- `etl-gbif.yml` / `etl-obis.yml` — daily cron
- `etl-all-data.yml` — weekly full refresh
- `flutter-build.yml` — mobile builds on tag

Required GitHub Actions secrets: `SUPABASE_URL`,
`SUPABASE_SERVICE_ROLE_KEY`, `RAILWAY_TOKEN`, `CLOUDFLARE_API_TOKEN`,
`CLOUDFLARE_ACCOUNT_ID`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`,
`RESEND_API_KEY`, `SENTRY_DSN`, `APIFY_TOKEN`, `TAVILY_API_KEY`,
`DIVENUMBER_API_KEY`, `CRON_SHARED_SECRET`, `MEDICAL_ENCRYPTION_MASTER_KEY`.

## Contributing

1. Branch from `main`. Open a PR.
2. CI must pass: typecheck, tests, RLS suite, build.
3. New tables need an RLS test in `supabase/tests/rls.sql`.
4. New API routes need a unit test in the relevant `*.spec.ts`.
5. New Edge Functions need a shared-secret gate if they touch user
   data.

## License

MIT — see [LICENSE](LICENSE).
