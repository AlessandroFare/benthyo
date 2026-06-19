# Testing Guide

End-to-end checklist for validating OceanLog locally before production deploy.

## 1. Prerequisites

```powershell
cd C:\Users\alefare\scuba\oceanlog
docker compose up -d
supabase start          # or apply migrations manually (see setup.md)
pnpm install
```

Copy `.env.example` → `.env` and fill at minimum:

| Variable | Used by |
|----------|---------|
| `DATABASE_URL` | migrations, RLS suite |
| `SUPABASE_URL` / keys | API, ETL, mobile |
| `ETL_SYSTEM_USER_ID` | GBIF/OBIS imports |
| `API_URL` (mobile dart-define) | trips, gear, reviews |

Link dashboard operator (once per auth user):

```sql
SELECT id, email FROM auth.users WHERE email = 'your@email.com';
-- Update UUID in supabase/seed-dashboard-operator.sql, then:
psql "$DATABASE_URL" -f supabase/seed-dashboard-operator.sql
```

## 2. Automated checks (run before every push)

```powershell
# RLS correctness (same as CI)
psql "$env:DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/ci_auth_bootstrap.sql
Get-ChildItem supabase/migrations/0*.sql | ForEach-Object {
  psql "$env:DATABASE_URL" -v ON_ERROR_STOP=1 -f $_.FullName
}
psql "$env:DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/seed.sql
psql "$env:DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/rls.sql

# API unit tests
pnpm --filter @oceanlog/api test

# Dashboard typecheck + build
pnpm --filter @oceanlog/dashboard typecheck
pnpm --filter @oceanlog/dashboard build

# ETL unit tests
pnpm --filter @oceanlog/etl test
```

Expected RLS output: `All OceanLog RLS tests passed.`

## 3. Start services

Terminal 1 — API:

```powershell
pnpm --filter @oceanlog/api start:dev
```

Terminal 2 — Dashboard:

```powershell
pnpm --filter @oceanlog/dashboard dev
```

Terminal 3 — Mobile (web):

```powershell
cd apps/mobile
flutter run -d edge --dart-define-from-file=dart_defines.local.json
```

Terminal 4 (optional) — Edge Functions:

```powershell
supabase functions serve --env-file .env
```

## 4. Manual smoke test matrix

| Area | Steps | Pass criteria |
|------|-------|---------------|
| Auth | Register → profile setup | Lands on map |
| Dive log | Quick log + full create | Row in `dive_logs` |
| Sighting | Report sighting at a site | No RLS error; stats row updated |
| Trips / Gear | Open list screens | No "Failed to load" |
| Logbook | Profile → public logbook | 200, not 500 |
| Species quiz | Settings → quiz | Loads (not UUID error) |
| BLE sync | Settings → BLE | Screen opens |
| Social feed | Post highlight | Snackbar + item in feed |
| Reviews | Site detail → review | Success or clear API error |
| Dashboard Today | Login as operator | Roster / today data |
| Dashboard KPIs | `/overview` | Charts load (needs operator seed) |
| Marketplace | Publish listing | Error shown if not linked |

## 5. ETL pipelines

**Order matters.** `run-all-data.ts` is the single source of truth:

1. `worms` (taxonomy)
2. `opendivemap` + `overpass` + `divenumber` **in parallel**
3. `apify:google-maps`
4. `gbif` + `obis` **in parallel**
5. SQL reconcile (open-water sites)
6. `inat:taxon-lookup`
7. `wikimedia:images` → `inaturalist:images` → `tavily:species`

### Run everything (recommended first time)

```powershell
pnpm --filter @oceanlog/etl all-data
```

Individual commands (when debugging one source):

```powershell
pnpm --filter @oceanlog/etl opendivemap    # ~3k sites, no key
pnpm --filter @oceanlog/etl overpass      # OSM regions
pnpm --filter @oceanlog/etl worms
pnpm --filter @oceanlog/etl gbif          # needs ETL_SYSTEM_USER_ID
pnpm --filter @oceanlog/etl obis
pnpm --filter @oceanlog/etl inaturalist:images
pnpm --filter @oceanlog/etl wikimedia:images
```

Optional (API keys in `.env`):

```powershell
pnpm --filter @oceanlog/etl divenumber
pnpm --filter @oceanlog/etl apify:google-maps
pnpm --filter @oceanlog/etl tavily:species
```

### Parallel tips

- **Safe to run in parallel:** `gbif` + `obis`; `opendivemap` + `overpass` + `divenumber`
- **Do not parallelize:** image backfills (wikimedia → inat → tavily) — they share species rows
- **Always run `worms` before** occurrence imports

Verify counts:

```sql
SELECT count(*) FROM dive_sites;
SELECT count(*) FROM species;
SELECT count(*) FROM sightings;
SELECT source, count(*) FROM dive_sites GROUP BY source ORDER BY 2 DESC;
```

## 6. Data quality expectations

ETL names are not 100% curated:

- **OpenDiveMap** — shop/center names mixed with site names
- **Overpass/OSM** — community tags, inconsistent naming
- **Apify Google Maps** — business listings

Filter map by `verified = true` (seed sites) or dedupe by lat/lng in future work.

## 7. Production deploy (when ready)

GitHub Actions deploy jobs **skip automatically** when secrets are missing:

| Secret | Workflow |
|--------|----------|
| `RAILWAY_TOKEN` | deploy-api |
| `CLOUDFLARE_API_TOKEN` + `CLOUDFLARE_ACCOUNT_ID` | deploy-dashboard |
| `SUPABASE_*` | ETL workflows |

Until those are set, CI still runs lint/test/RLS on every push.

## 8. Troubleshooting

| Symptom | Fix |
|---------|-----|
| Dashboard KPIs empty | Re-run `seed-dashboard-operator.sql` with your auth UUID |
| RLS 42501 on sighting | Ensure migration 025+ applied |
| API CORS from Flutter web | Set `CORS_ORIGIN` or `API_CORS_ORIGIN` in API `.env` |
| Darwin export in app | Server-side cron only — see `darwin-core-export` Edge Function |
| Deploy API failed | Expected without `RAILWAY_TOKEN` |

See also: [setup.md](./setup.md), [runbook.md](./runbook.md).
