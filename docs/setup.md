# Setup Guide

## Prerequisites

- Node.js 20+
- pnpm 9+
- Docker Desktop (for local Postgres/Redis)
- Supabase CLI (optional, for Edge Functions)
- Flutter 3.x + Melos (for mobile development)

## 1. Clone and install

```bash
git clone https://github.com/benthyo/benthyo.git
cd benthyo
pnpm install
```

## 2. Environment variables

```bash
cp .env.example .env
```

Required for local development:

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | Postgres connection string |
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_ANON_KEY` | Public anon key |
| `SUPABASE_SERVICE_ROLE_KEY` | Service role (ETL + Edge Functions only) |
| `REDIS_URL` | Redis for BullMQ |
| `ETL_SYSTEM_USER_ID` | UUID of system user for ETL sighting imports |

## 3. Start infrastructure

```bash
docker compose up -d
```

This starts:

- PostGIS Postgres on port `54322`
- Redis on port `6379`
- Mailpit (email testing) on port `8025`

## 4. Database setup

Apply migrations in order:

```bash
export DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:54322/benthyo

for f in supabase/migrations/*.sql; do
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$f"
done

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/seed.sql
```

Seed data includes 50 Mediterranean dive sites, 200 marine species, 5 Italian dive centers, and 10 badges.

## 5. Build shared packages

```bash
pnpm --filter @benthyo/types build
pnpm --filter @benthyo/ui build
```

## 6. Run services

**API (NestJS):**

```bash
pnpm --filter @benthyo/api start:dev
```

**Dashboard (Vite):**

```bash
pnpm --filter @benthyo/dashboard dev
```

Dashboard runs at `http://localhost:5173`, API at `http://localhost:3000`.

## 7. Supabase Edge Functions (optional)

```bash
supabase functions serve --env-file .env
supabase functions deploy on-sighting-created
supabase functions deploy darwin-core-export
supabase functions deploy weekly-digest
```

Configure a database webhook on `sightings` INSERT to call `on-sighting-created`.

## 8. ETL pipelines

Set in `.env`:
- `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` (required for all ETL)
- `ETL_SYSTEM_USER_ID` — UUID of system user (GBIF/OBIS sightings)

### Dive sites (global coverage)

| Command | Source | Auth |
|---------|--------|------|
| `pnpm --filter @benthyo/etl opendivemap` | [OpenDiveMap](https://opendivemap.com/docs/api) GeoJSON API (~3k+ sites) | None |
| `pnpm --filter @benthyo/etl overpass` | OpenStreetMap (9 regions incl. Nordic) | None |
| `pnpm --filter @benthyo/etl divenumber` | [Dive Number](https://divenumber.com/free_dive_site_map) embed API (region-scoped) | `DIVENUMBER_API_KEY` |
| `pnpm --filter @benthyo/etl apify:google-maps` | Google Maps via [Apify](https://apify.com) | `APIFY_TOKEN` |
| `pnpm --filter @benthyo/etl all-data` | Runs all of the above + species images | Mixed |

```bash
pnpm --filter @benthyo/etl opendivemap
pnpm --filter @benthyo/etl overpass
pnpm --filter @benthyo/etl all-data
```

Norway / Nordic sites: run Overpass (`OVERPASS_REGIONS=nordic`) or Apify with `APIFY_GOOGLE_SEARCHES=scuba diving sites Norway`.

### Species

| Command | Purpose |
|---------|---------|
| `pnpm --filter @benthyo/etl gbif` | Mediterranean occurrence imports |
| `pnpm --filter @benthyo/etl obis` | OBIS marine occurrences |
| `pnpm --filter @benthyo/etl worms` | WoRMS taxonomy |
| `pnpm --filter @benthyo/etl inaturalist:images` | Backfill `image_url` from `inat_taxon_id` |
| `pnpm --filter @benthyo/etl tavily:species` | Image search fallback via [Tavily](https://www.tavily.com) |

### Dashboard operator (local)

After creating a Supabase Auth user:

```bash
psql "$DATABASE_URL" -f supabase/seed-dashboard-operator.sql
```

Replace `PASTE-AUTH-USER-UUID` in that file with your user's UUID, then log in at `http://localhost:5173`.

See [configuration.md](./configuration.md) for the full mobile + web + production checklist.

See [roadmap.md](./roadmap.md) for product feature priorities.

## 9. Flutter mobile (optional)

```bash
dart pub global activate melos
melos bootstrap
cd apps/mobile && flutter run
```

### Supabase cloud auth (mobile + dashboard)

When using a hosted Supabase project (not local `supabase start`):

1. **Apply migrations** to your cloud project (`supabase db push` or run SQL from `supabase/migrations/`).
2. In Supabase → **Authentication → URL configuration**:
   - **Site URL**: your app origin (e.g. `http://localhost:5173` for dashboard, or the Flutter web URL shown in the terminal when you `flutter run -d edge`).
   - **Redirect URLs**: add the same origins plus wildcards if needed, e.g. `http://localhost:**` for local Flutter web.
3. **Confirm email** is enabled by default — users must click the link in the signup email before password login works.
4. Enable **Google** (or other providers) under Authentication → Providers, then add the OAuth client ID/secret from Google Cloud Console.
5. Run Flutter with your project keys:

```bash
cd apps/mobile
flutter run -d edge \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

Legacy name `SUPABASE_ANON_KEY` also works. Use the **publishable** key from Supabase → Project Settings → API (not the service role secret).

After email confirmation, sign in with the **same password** used at registration. If login fails, use **Resend confirmation email** on the sign-in screen.

## Troubleshooting

- **PostGIS errors**: ensure the `postgis/postgis` Docker image is used, not plain Postgres.
- **ETL auth errors**: verify `SUPABASE_SERVICE_ROLE_KEY` and `ETL_SYSTEM_USER_ID` are set.
- **Overpass timeouts**: the Overpass API can be slow; retry or reduce the bounding box.
