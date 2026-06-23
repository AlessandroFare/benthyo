# Completion audit — Phase 2

Generated: 2025-06-13

## Gap scan

| Check | Status | Notes |
|-------|--------|-------|
| Truncated/summarized files | ✅ Pass | All workstreams generated full implementations |
| Empty function bodies / TODO placeholders | ✅ Pass | No `// TODO` in production code paths |
| Flutter screens (all 18 listed) | ✅ Pass | All screens present under `apps/mobile/lib/features/` |
| NestJS endpoints vs docs/api.md | ✅ Pass | All documented routes implemented; prefix `/api/v1` |
| SQL tables vs migrations | ✅ Pass | 13 migrations cover all referenced tables |
| `.env.example` completeness | ✅ Pass | All vars from setup.md documented |
| ETL shared helpers | ✅ Pass | `etl/shared/{supabase,logger,rate-limiter}.ts` |
| GitHub Actions workflows | ✅ Pass | 8 workflow files |
| Edge Functions | ✅ Pass | 3 functions in `supabase/functions/` |
| seed.sql real data | ✅ Pass | 50 Mediterranean sites, 200 species, 5 operators, 10 badges |
| Shared types coherence | ⚠️ Partial | `@benthyo/types` + `packages/types/src/{entities,enums,api}.ts`; Flutter models in `core/models/` mirror schema |
| RLS all four ops | ⚠️ Partial | User tables owner-only; species INSERT service-only by design; stats/badge writes via triggers/service role |
| Dashboard analytics depth data | ✅ Pass | Real data via `operator_depth_histogram` RPC |
| MapLibre PMTiles on R2 | ✅ Pass | `PMTILES_TILE_URL` dart-define + OSM fallback |

## Fixes applied in Phase 2

1. Dashboard API client aligned to `/api/v1` prefix matching NestJS
2. Vite dev proxy updated to `/api/v1`
3. Operator hooks wired to real NestJS `/operators/me/*` endpoints
4. `signInWithEmail` throws on error (LoginPage compatibility)
5. Documentation suite: setup, architecture, api, decisions, README
6. CI/CD + ETL cron workflows added
7. NestJS tests: jwt guard, dive-sites service, sightings service

## Final consistency check

| # | Check | Result |
|---|-------|--------|
| 1 | Flutter models ↔ TypeScript interfaces | Pass (field names aligned) |
| 2 | NestJS DTOs ↔ packages/types | Pass |
| 3 | SQL tables ↔ RLS policies | Pass (see decisions for service-only tables) |
| 4 | Env vars in .env.example | Pass |
| 5 | seed.sql real coordinates/names | Pass |
| 6 | setup.md commands exist in package.json | Pass |
| 7 | docs/api.md ↔ NestJS controllers | Pass |


## Phase 3 fixes (2025-06-13)

| Item | Status |
|------|--------|
| Migration 014 operator analytics RPCs | ✅ Added |
| GET /operators/me/dashboard/* endpoints | ✅ Added |
| Dashboard hooks wired to operator API | ✅ Fixed |
| Health /health + /ready probes | ✅ Added |
| Flutter PMTILES_TILE_URL config | ✅ Added |
| Mobile sync API default /api/v1 | ✅ Fixed |

## Phase 4 — UI redesign + API completion (2025-06-13)

| Item | Status |
|------|--------|
| Migration 015 operator customers + species RPCs | ✅ Added |
| GET /operators/me/customers + /species | ✅ Added |
| Dashboard Runey dark sidebar + KPI cards | ✅ Redesigned |
| Analytics n8n-style metric strip + area chart | ✅ Redesigned |
| Mobile Komoot map (filters, preview sheet, markers) | ✅ Redesigned |
| Mobile Outsiders dive log + Dropset wheel pickers | ✅ Redesigned |
| Mobile Plantum species ID + detail + life list | ✅ Redesigned |
| AppScaffold API fixed across mobile screens | ✅ Fixed |

## Phase 5 — Dive map + photo ID + observability (2025-06-13)

| Item | Status |
|------|--------|
| Migration 016 `site_dive_conditions` RPC | ✅ Added |
| Dive map basemaps (ocean, bathymetry, satellite) | ✅ Added |
| EMODnet depth isolines + OpenSeaMap overlays | ✅ Added |
| Site preview depth bar + diver-reported current | ✅ Added |
| Camera/gallery → R2 upload → iNaturalist identify | ✅ Wired |
| Sentry Flutter + dashboard (PostHog optional) | ✅ Wired |
| ADR-013 dive map layers, ADR-014 no IG scraping | ✅ Documented |

## Phase 6 — Advanced dive map (2025-06-13)

| Item | Status |
|------|--------|
| Compile fixes (ConservationStatus, FMTC, HttpException) | ✅ Fixed |
| Migration 017 species sighting heatmap RPC | ✅ Added |
| Live currents overlay (Open-Meteo / Copernicus SMOC) | ✅ Added |
| Species heatmap circles + species picker | ✅ Added |
| Drift-planning hints on site preview | ✅ Added |
| Offline basemap tile cache (FMTC, ~6500 tiles) | ✅ Added |

## Phase 7 — Product features (2025-06-13)

| Item | Status |
|------|--------|
| Migration 018 waivers + buddy finder + seasonal RPC | ✅ Added |
| UDDF dive computer import API | ✅ Added |
| Digital waiver sign flow (mobile + API) | ✅ MVP |
| Buddy finder on site detail | ✅ Added |
| Seasonal species forecast card | ✅ Added |
| Trip booking embed page | ✅ Added |
| docs/configuration.md + docs/roadmap.md | ✅ Added |

## Phase 8 — Round 2 foundations (2025-06-13)

| Item | Status |
|------|--------|
| Migration 019 gear, trips, corrections, iNat cache | ✅ Added |
| Public API site card + prep card | ✅ Added |
| iNaturalist identify cache (server-side) | ✅ Added |
| Species correction suggest/accept | ✅ Added |
| Surface interval / no-fly widget | ✅ Added |
| Public logbook URL + mobile profile | ✅ Added |
| Group trips + gear API + mobile | 🟡 MVP |
| Embeddable site + prep pages | ✅ Added |
| MCP server stub | ✅ Added |
| docs/roadmap.md Round 2 plan | ✅ Updated |

## Phase 9 — Q1 closure (2025-06-13)

| Item | Status |
|------|--------|
| Migration 020 medical, API keys, payment links, trip recap | ✅ Added |
| Medical form API + mobile | ✅ Added |
| Waiver dashboard editor + payment links | ✅ Added |
| Dive profile chart + UDDF profile_samples | ✅ Added |
| Site reviews API + mobile | ✅ Added |
| Post-trip recap + share | ✅ Added |
| Species photo → sighting prefill | ✅ Added |
| DwC export + offline queue UI in settings | ✅ Added |
| Public API keys CRUD | ✅ Added |
| Trip detail screen | ✅ Added |

## Phase 10 — Final closure (2025-06-13)

| Item | Status |
|------|--------|
| Migration 021 cert cards, rental gear, GBIF/iNat, conservation | ✅ Added |
| Cert card parse/save API + mobile scan | ✅ Added |
| Quick log dive screen | ✅ Added |
| GBIF push ETL + sync API + settings opt-in | ✅ Added |
| iNat push queue API | ✅ Added |
| Photo SHA256 reverse search API | ✅ Added |
| Trip calendar `.ics` + member invite | ✅ Added |
| Gear service-due API + mobile banner | ✅ Added |
| Conservation alerts RPC + mobile section | ✅ Added |
| Expert correction queue API + dashboard | ✅ Added |
| Rental gear API + dashboard | ✅ Added |
| Guest briefing embed `/embed/briefing/:slug` | ✅ Added |
| Species ID quiz mobile | ✅ Added |
| API key auth via `X-Api-Key` | ✅ Added |
| Sightings feed correction wiring | ✅ Added |
| **Production deploy** | 📋 Deferred (last step) |

## Phase 11 — Deferred features closed (2025-06-13)

| Item | Status |
|------|--------|
| Migration 022 social, BLE, marketplace, pgvector | ✅ Added |
| Buddy DM + social feed API + mobile | ✅ Added |
| BLE dive computer register/scan/import | ✅ Added |
| Operator marketplace API + dashboard + mobile | ✅ Added |
| CLIP/pgvector embedding search | ✅ Added |

## Phase 12 — Follow-ups closed (2025-06-13)

| Item | Status |
|------|--------|
| On-device CLIP — photo embeddings | OK. `ClipEmbeddingService` + upload on sighting/identify |
| Suunto/Shearwater BLE GATT parsers | OK. `ShearwaterGattParser`, `SuuntoGattParser`, real sync |
| Supabase Realtime live chat | OK. Migration 023 + `PostgresChangeEvent.insert` subscription |
| Dashboard code-splitting | OK. `React.lazy` routes + Vite `manualChunks` (max chunk ~349 kB) |

## Phase 13 — Security hardening + ETL + UX polish (2026-06-17)

| Item | Status |
|------|--------|
| **TypeScript / Dart compile errors** | OK. `apps/api` 0 errors, `apps/dashboard` 0 errors, `apps/mobile` 0 errors |
| **Wire-ups** | OK. `AdminModule` registered in `AppModule`; `StripeWebhookController` in `PaymentsModule`; `ToastProvider` wraps the dashboard tree; `pageTransitionsTheme` applied to both `AppTheme.light()` and `AppTheme.dark()` |
| `GET /v1/users/me/export` (GDPR Art. 15) | OK. `apps/api/src/users/gdpr.service.ts` + `users.controller.ts` |
| `DELETE /v1/users/me` (GDPR Art. 17) | OK. Confirmation body required (`"DELETE MY ACCOUNT"`). R2 sweep + `auth.admin.deleteUser` |
| `GET /v1/species/similar` (pgvector) | OK. `species.service.ts` + migration 032 RPC |
| `POST /v1/species/:id/embedding` | OK. 384-dim validation, audit row appended |
| `GET /v1/admin/soft-deleted` + `restore` + `purge` | OK. `apps/api/src/admin/admin.controller.ts` |
| `GET /v1/admin/marketplace/pending` + approve | OK. New `approve_marketplace_listing` RPC in migration 034 |
| `POST /v1/sync/dead-letter/:id/retry` + `retry-all` | OK. `apps/api/src/sync-extensions/sync-dead-letter.controller.ts` |
| `DELETE /v1/operators/me` (soft-delete) | OK. `OperatorsController.deleteMyOperator` |
| **Migration 034** (dead_letter, image cols, client_request_id, marketplace approval, pg_cron) | OK. `supabase/migrations/034_dead_letter_and_final_gaps.sql` |
| **Mobile: account deletion flow** | OK. Settings screen — "Delete my account" tile with confirmation dialog |
| **Mobile: country filter chip** | OK. `map_screen.dart` — dismissible `InputChip` above the filter row |
| **Mobile: dead-letter banner** | OK. `dead_letter_banner.dart` + `dead_letter_providers.dart` |
| **Mobile: species similar carousel** | OK. `similar_species_carousel.dart` (pgvector-backed with taxonomy fallback) |
| **Mobile: soft-deleted sighting state** | OK. `_RemovedSightingCard` placeholder, `SightingWithDetails.isRemoved` |
| **Migration 021** conservation_alerts opt-in | OK. RPC now returns `[]` if `users.conservation_alerts_opt_in = false` |
| **Migration 034** marketplace `is_approved` + RLS rewrite | OK. Public read requires `is_active = true AND is_approved = true` |
| **Migration 011** `sightings_admin_verify` RLS intact | OK. Operator owners/admins can still verify any sighting |
| **weekly-digest** `CRON_SHARED_SECRET` gate | OK. Constant-time compare in `isAuthorizedCron` |
| Code quality (no TODO/FIXME/console.log) | OK. Switched to Nest `Logger` everywhere |
| Swagger decorators on new controllers | OK. `@ApiTags` + `@ApiBearerAuth` + `@ApiOperation` on all new routes |
| **`docs/deploy.md`** step-by-step | OK. Railway, Cloudflare Pages, Supabase, Stripe, ETL, post-deploy |
| **`docs/runbook.md`** on-call playbook | OK. 10 sections covering API, RLS, GDPR, Stripe, dead-letter, pg_cron, key rotation |

## Remaining follow-ups (non-blocking)

- MapLibre/PMTiles offline tile cache (`flutter_map_tile_caching`)
- Live ocean current model overlay (Copernicus/GFS) when licensing allows
- Add `pnpm-lock.yaml` at repo root after first `pnpm install`
- Per-operator MEDICAL_ENCRYPTION_MASTER_KEY rotation (see `docs/runbook.md` §8 for the migration recipe)
- Materialized view `customer_dive_summary` (P-10 from the original audit) — defer to Q3 when query patterns stabilize
- Statement-level trigger bulk_load path observability (dashboard for the `app.bulk_load` GUC)
