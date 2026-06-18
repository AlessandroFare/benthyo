# OceanLog — configuration checklist

Use this checklist to get **mobile (Flutter)**, **web dashboard**, and **API** fully operational locally or on Supabase cloud.

## 1. Infrastructure

| Step | Command / action |
|------|------------------|
| Copy env | `cp .env.example .env` |
| Start Docker | `docker compose up -d` (Postgres `54322`, Redis `6379`) |
| Apply migrations | Run all `supabase/migrations/*.sql` through `020` + `supabase/seed.sql` |
| Build packages | `pnpm --filter @oceanlog/types build` |

## 2. Supabase (local or cloud)

### Local (`supabase start`)
- `SUPABASE_URL=http://127.0.0.1:54321`
- Keys from `supabase status`

### Cloud (your project)
1. **Database → Migrations**: push `016`–`020`.
2. **Authentication → URL configuration**:
   - **Site URL**: Flutter web origin (e.g. `http://localhost:54321` or the port Edge shows).
   - **Redirect URLs**: `http://localhost:**`, dashboard `http://localhost:5173/**`.
3. **Authentication → Providers**: Email + optional Google OAuth.
4. **Storage**: bucket `sighting-photos` (from migration 013).

## 3. NestJS API (`:3000`)

| Variable | Required for |
|----------|----------------|
| `DATABASE_URL` | Health ready probe |
| `SUPABASE_URL` + `SUPABASE_ANON_KEY` | JWT validation |
| `SUPABASE_SERVICE_ROLE_KEY` | ETL only |
| `R2_*` + `R2_PUBLIC_URL` | Photo upload + species ID |
| `RESEND_API_KEY` | Operator digest emails |
| `SENTRY_DSN` | Error tracking (optional) |
| `API_CORS_ORIGIN` | Dashboard + Flutter web (`http://localhost:5173,http://localhost:7357`) |

```bash
pnpm --filter @oceanlog/api start:dev
```

Verify: `http://localhost:3000/health` and `http://localhost:3000/api/v1/species`.

## 4. Dashboard (web, `:5173`)

Create `apps/dashboard/.env.local`:

```env
VITE_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-key
VITE_API_URL=http://localhost:3000/api/v1
VITE_SENTRY_DSN=
VITE_POSTHOG_KEY=
```

```bash
pnpm --filter @oceanlog/dashboard dev
```

**Embed booking widget:**  
`http://localhost:5173/embed/{operator-slug}/book`

**Embed site data card:**  
`http://localhost:5173/embed/site/{site-slug}`

**Pre-dive prep card (shareable):**  
`http://localhost:5173/embed/site/{site-slug}/prep`

**MCP server (Claude / Cursor):**
```bash
cd apps/mcp-server && pnpm install
OCEANLOG_API_URL=http://localhost:3000/api/v1 pnpm start
```

## 5. Flutter mobile + web

### Dependencies
```bash
cd apps/mobile
flutter pub get
```

### Run on Edge (web)
```powershell
flutter run -d edge `
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=your-publishable-key `
  --dart-define=API_URL=http://localhost:3000/api/v1
```

### Run on Android emulator
Use `API_URL=http://10.0.2.2:3000/api/v1` (host machine from emulator).

### Optional dart-defines
| Flag | Purpose |
|------|---------|
| `SENTRY_DSN` | Crash reporting |
| `PMTILES_TILE_URL` | Custom map tiles on R2 |

### Features that need extra config
| Feature | What you need |
|---------|----------------|
| **Photo species ID** | Signed-in user + R2 presign (`R2_*` in API `.env`) |
| **Dive computer import** | API running + `POST /dive-logs/import/uddf` |
| **Pre-dive prep card** | API running; share from site detail |
| **Public logbook** | `/u/{username}` in app; API `/users/{username}/logbook` |
| **Group trips / gear** | Migration `019` + API running |
| **Live map currents** | Internet (Open-Meteo, no key) |
| **Offline map cache** | Mobile/desktop only (not Edge/web) |

### Create an operator waiver (SQL example)
```sql
INSERT INTO operator_waivers (operator_id, title, body, is_active)
SELECT id,
  'Liability waiver',
  'I understand scuba diving involves risks…',
  true
FROM operators WHERE slug = 'your-operator-slug' LIMIT 1;
```

Guest flow: sign in on mobile → open `/waiver/your-operator-slug`.

## 6. Operator B2B dashboard login

1. Create user in Supabase Auth (same as mobile signup, or via Studio).
2. Link to operator:
   ```bash
   # Edit supabase/seed-dashboard-operator.sql with your auth user UUID, then:
   psql "$DATABASE_URL" -f supabase/seed-dashboard-operator.sql
   ```
3. Login at dashboard → KPIs at `/operators/me/*` routes.

## 7. ETL (optional, scheduled data)

Set in `.env`:
- `ETL_SYSTEM_USER_ID` — UUID of system user
- `SUPABASE_SERVICE_ROLE_KEY`

Dive sites: `opendivemap`, `overpass`, `divenumber`, `apify:google-maps`, or `all-data`.  
Species images: `inaturalist:images`, `tavily:species`.

```bash
pnpm --filter @oceanlog/etl all-data
pnpm --filter @oceanlog/etl gbif
```

## 8. Production checklist

- [ ] Supabase cloud migrations 001–020 applied
- [ ] R2 bucket + public URL for photos
- [ ] API deployed (Railway/Fly) with `SENTRY_DSN`
- [ ] Dashboard on Vercel/Cloudflare with `VITE_*` vars
- [ ] Flutter web build with production `SUPABASE_URL` + `API_URL`
- [ ] Supabase redirect URLs include production domains
- [ ] Resend domain verified for digest emails
- [ ] PostHog/Sentry keys (optional)

## Quick smoke test

1. Register → confirm email → login (mobile web).
2. Map → layers → isolines + live currents.
3. Species → camera identify (needs R2).
4. Dive logs → import UDDF file.
5. Dive site detail → buddy finder list.
6. Species detail → seasonal forecast chart.
7. Dashboard login → analytics KPIs.
8. `/embed/{slug}/book` loads operator card.
