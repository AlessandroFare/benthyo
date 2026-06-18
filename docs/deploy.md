# OceanLog — Deploy Guide

This is the step-by-step recipe for shipping a new release of OceanLog
to production. Read the runbook too — this guide assumes you have
already rotated the secrets listed in `docs/runbook.md`.

## 0. Pre-flight

- [ ] `git status` is clean on `main`.
- [ ] All migrations are committed under `supabase/migrations/`.
- [ ] All ETL scripts have been unit-tested locally with `pnpm --filter @oceanlog/etl test`.
- [ ] API `pnpm --filter @oceanlog/api test` is green.
- [ ] Flutter `flutter test` is green.
- [ ] Dashboard `pnpm --filter @oceanlog/dashboard build` is green.

## 1. Supabase (database + edge functions)

```bash
# 1.1 Link the project (once per machine)
supabase link --project-ref <project-ref>

# 1.2 Push the migrations. ALWAYS check the diff first.
supabase db diff --schema public
# If the diff matches your new migration files, push:
supabase db push --include-all

# 1.3 Apply the pg_cron jobs from migration 034 if pg_cron is enabled.
#    Inside the Supabase SQL editor:
#      SELECT * FROM cron.job;
#    You should see entries: prune-inat-identify-cache-weekly,
#    reconcile-unmatched-nightly, pgvector-reindex-monthly.
#    If pg_cron is not enabled, enable it from the Supabase dashboard
#    and re-run the migration block from 034_dead_letter_and_final_gaps.sql.

# 1.4 Deploy the Edge Functions
supabase functions deploy darwin-core-export
supabase functions deploy weekly-digest
supabase functions deploy on-sighting-created

# 1.5 Set the function secrets (CRON_SHARED_SECRET is the most
#    important; keep it in sync with the API's env).
supabase secrets set CRON_SHARED_SECRET=$(openssl rand -hex 32)
```

## 2. Railway (NestJS API)

```bash
# 2.1 Set the env vars (the full list lives in apps/api/.env.example).
#    Required:
#      NODE_ENV=production
#      PORT=3000
#      SUPABASE_URL
#      SUPABASE_ANON_KEY
#      SUPABASE_SERVICE_ROLE_KEY
#      R2_ACCOUNT_ID
#      R2_ACCESS_KEY_ID
#      R2_SECRET_ACCESS_KEY
#      R2_BUCKET_NAME
#      R2_PUBLIC_URL
#      RESEND_API_KEY
#      STRIPE_SECRET_KEY
#      STRIPE_WEBHOOK_SECRET
#      CRON_SHARED_SECRET (same as Supabase)
#      ADMIN_API_KEY (rotate per release)
#      SENTRY_DSN
#      MEDICAL_ENCRYPTION_MASTER_KEY (rotation documented in runbook.md)

# 2.2 Deploy. The Railway project is wired to the GitHub repo; pushing
#    to main triggers a build + deploy automatically. For a manual
#    push, use the Railway CLI:
railway up

# 2.3 Tail the logs for the first 10 minutes:
railway logs --follow
```

## 3. Cloudflare Pages (Dashboard)

```bash
# 3.1 The dashboard is a Vite SPA. Build it from the dashboard folder.
pnpm --filter @oceanlog/dashboard build
#    The output goes to apps/dashboard/dist/.

# 3.2 Cloudflare Pages is wired to the GitHub repo; a push to main
#    triggers a build via the wrangler.toml at the dashboard root.
#    For a manual deploy:
pnpm --filter @oceanlog/dashboard exec wrangler pages deploy dist --project-name=oceanlog-dashboard

# 3.3 Set the dashboard env vars in the Cloudflare Pages dashboard:
#      VITE_API_URL=https://api.oceanlog.app/api/v1
#      VITE_SUPABASE_URL
#      VITE_SUPABASE_ANON_KEY
#      VITE_SENTRY_DSN
#      VITE_POSTHOG_KEY
#      VITE_MAP_TILES_TOKEN
#      VITE_STRIPE_PUBLISHABLE_KEY
```

## 4. Flutter (iOS, Android, Web)

```bash
# 4.1 Build the Android App Bundle (Play Store)
cd apps/mobile
flutter build appbundle --release \
  --dart-define=API_URL=https://api.oceanlog.app/api/v1 \
  --dart-define=SUPABASE_URL=$SUPABASE_URL \
  --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY

# 4.2 Build the iOS archive (App Store)
flutter build ipa --release \
  --dart-define=API_URL=https://api.oceanlog.app/api/v1

# 4.3 Build the Web release (Cloudflare Pages)
flutter build web --release \
  --dart-define=API_URL=https://api.oceanlog.app/api/v1
#    Output: apps/mobile/build/web/

# 4.4 Tag the release in git.
git tag -a v1.x.y -m "Release v1.x.y"
git push origin v1.x.y
```

## 5. Stripe webhook

```bash
# 5.1 In the Stripe dashboard, point the webhook to:
#      https://api.oceanlog.app/api/v1/billing/stripe/webhook

# 5.2 Subscribe to the events:
#      invoice.paid
#      customer.subscription.created
#      customer.subscription.updated
#      customer.subscription.deleted

# 5.3 Test locally before you push:
stripe listen --forward-to localhost:3000/api/v1/billing/stripe/webhook
#    Stripe prints a `whsec_...` secret — set STRIPE_WEBHOOK_SECRET to it
#    in your local .env.
```

## 6. ETL first-run

The first time the ETL runs against a fresh database, the order matters:

```bash
# 6.1 Taxonomy
pnpm --filter @oceanlog/etl worms          # ~3 min
pnpm --filter @oceanlog/etl inat:taxon-lookup   # ~5 min (fills inat_taxon_id)

# 6.2 Dive sites (3 sources in parallel via the run-all-data script)
pnpm --filter @oceanlog/etl all-data       # ~30 min on first run

# 6.3 Image backfill (heavy)
pnpm --filter @oceanlog/etl wikimedia:images    # ~1 hour
pnpm --filter @oceanlog/etl inaturalist:images  # ~30 min
pnpm --filter @oceanlog/etl tavily:species       # ~10 min
```

The github workflow at `.github/workflows/etl-all-data.yml` runs
`all-data` weekly. For a one-off run, the script is idempotent — it
upserts on `(source, external_id)` for occurrences and on
`scientific_name` for species.

## 7. Post-deploy verification

```bash
# 7.1 Health probes (should return 200)
curl https://api.oceanlog.app/health/live
curl https://api.oceanlog.app/health/ready

# 7.2 RLS test suite
psql $DATABASE_URL -v ON_ERROR_STOP=1 -f supabase/tests/rls.sql

# 7.3 Dashboard smoke
#    - Open the dashboard.
#    - Log in as the seed operator.
#    - Verify the KPI cards animate, the sightings chart renders, the
#      sites table sorts.

# 7.4 Mobile smoke
#    - Open the app on a real device.
#    - Verify the map loads, the sightings feed renders, the settings
#      banner shows the dead-letter count (should be 0 on a fresh
#      install).
#    - Trigger an account deletion from Settings and confirm the
#      auth.users row is gone.
```
