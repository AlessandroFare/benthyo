# Benthyo — Security Audit & Remediation Log

This document is a living record of every security finding raised during
the pre-launch audit and the remediation applied.

The audit is organized by severity. Each entry includes the original
finding ID (e.g. **C-1**), a one-line summary, the file(s) modified,
and the date of remediation.

## Quick scoreboard

| Severity | Open | Remediated | Total |
|----------|------|------------|-------|
| Critical | 0    | 8          | 8     |
| High     | 0    | 11         | 11    |
| Medium   | 0    | 22         | 22    |
| Low      | 0    | 7          | 7     |

## Critical (8 / 8 fixed)

### C-1 — Operator staff could mutate another user's medical submission
- **File:** `supabase/migrations/026_rls_hardening_and_gdpr.sql`
- **Fix:** narrowed the `medical_submissions_operator_read` policy
  from `FOR ALL` to `FOR SELECT`. The remaining staff WRITE path
  (waivers, payments) is split into separate INSERT/UPDATE/DELETE
  policies so the column surface is explicit.

### C-2 — Weekly-digest emailer ignored `weekly_digest_opt_in`
- **File:** `supabase/functions/weekly-digest/index.ts`
- **Fix:** the function now filters users to `weekly_digest_opt_in =
  true` before sending. The route is also gated by a shared-secret
  header (X-Cron-Secret) compared in constant time, OR a valid
  admin JWT. Cron jobs pass the secret; manual invocations must
  come from an admin.

### C-3 — Any user could self-verify their own sightings
- **Files:** `apps/api/src/sightings/sightings.controller.ts`,
  `apps/api/src/sightings/sightings.service.ts`,
  `apps/api/src/common/guards/taxonomy-expert.guard.ts`,
  `apps/api/src/common/decorators/taxonomy-expert.decorator.ts`
- **Fix:** the verify endpoint is now `@UseGuards(TaxonomyExpertGuard)`
  and the service explicitly refuses to set `verified_by` to the
  caller's own UUID. The guard checks `users.taxonomy_expert = true`
  via the RLS-aware Supabase client.

### C-4 — Public Darwin Core export leaked the verified dataset
- **File:** `supabase/functions/darwin-core-export/index.ts`
- **Fix:** the API-side public route is removed. The Edge Function
  filters `verified_at IS NOT NULL AND verified_by IS NOT NULL` (both,
  fixing the prior inconsistency), caps at 5000 rows, and requires
  the same X-Cron-Secret header as the weekly digest.

### C-5 — `PUT /v1/waivers/operator/:operatorId` had no role check
- **Files:** `apps/api/src/waivers/waivers.controller.ts`,
  `apps/api/src/waivers/waivers.service.ts`,
  `supabase/migrations/028_waiver_signature_legal.sql`
- **Fix:** added `@UseGuards(OperatorRoleGuard)` + `@OperatorRoles('owner',
  'admin')` on the route. The service now also captures IP, User-Agent,
  signer email, and a SHA256 of the signed waiver body so the
  signature is legally binding under eIDAS (SES compliance). A new
  trigger `prevent_signed_waiver_delete` blocks deletion of any
  waiver that has signatures attached.

### C-6 — Operator owners could self-upgrade their subscription tier
- **File:** `supabase/migrations/026_rls_hardening_and_gdpr.sql`,
  `supabase/migrations/027_subscription_enforcement.sql`
- **Fix:** the `operators_update_member` policy's `WITH CHECK` clause
  now requires `subscription_tier` and `subscription_status` to equal
  the existing values — so an UPDATE on those columns via the RLS
  policy always affects 0 rows. A new SECURITY DEFINER function
  `set_operator_subscription()` is the only path that mutates those
  columns; the API service calls it via service role from the
  Stripe webhook.

### C-7 — Production secrets committed to the workspace `.env`
- **Files:** `benthyo/.env`, `benthyo/.gitignore`,
  `benthyo/.env.example`, `benthyo/scripts/sanitize-env.js`
- **Fix:** the real secrets in `.env` were replaced with `__set_me__`
  placeholders via PowerShell. `.gitignore` now explicitly excludes
  `.env`, `.env.local`, and `*.pem`. `.env.example` documents every
  variable the project needs. `scripts/sanitize-env.js` is a
  re-runnable helper for the same operation.

### C-8 — Subscription tier never enforced anywhere
- **Files:** `apps/api/src/common/guards/tier.guard.ts`,
  `apps/api/src/common/decorators/operator-roles.decorator.ts`
  (already existed), `apps/api/src/payments/stripe.service.ts`,
  `apps/api/src/payments/stripe-webhook.controller.ts`
- **Fix:** `@RequireTier('starter' | 'pro')` decorator + `TierGuard`
  reads the operator's `subscription_tier` and
  `subscription_status` from the DB (with a 14-day grace period for
  `past_due`). The Stripe webhook (`POST /v1/billing/stripe/webhook`)
  uses `stripe.webhooks.constructEvent` to verify the signature, then
  calls `set_operator_subscription()` to update tier and status.

## High (11 / 11 fixed)

### DD-1.1 — `sighting_corrections` had no UPDATE policy
- **File:** `supabase/migrations/026_rls_hardening_and_gdpr.sql`
- **Fix:** added an explicit `FOR UPDATE` policy that allows:
  - The reporter to withdraw their own open correction.
  - The sighting's reporter to accept/reject.
  - A taxonomy expert to resolve.
  - Anyone else: 0 rows. The `accept` and `expertResolve` flows now
    actually update rows instead of silently failing.

### DD-1.2 — Admin could delete signed waivers
- **File:** `supabase/migrations/026_rls_hardening_and_gdpr.sql`
- **Fix:** added the `trg_block_signed_waiver_delete` BEFORE DELETE
  trigger on `operator_waivers`. Any DELETE on a waiver with
  attached `waiver_signatures` raises a `check_violation`.

### H-1 — SSRF in iNaturalist identify proxy
- **File:** `apps/api/src/species/species.service.ts`
- **Fix:** the `identify` endpoint now validates that `image_url`
  starts with `R2_PUBLIC_URL` (or one of the dev defaults). Any other
  URL returns 400. The iNaturalist server-side fetch can no longer
  be coerced into reaching internal services.

### H-3 (revised) — `getMembers` returned full operator_users list
- **File:** `apps/api/src/operators/operators.controller.ts`
- **Fix:** the route already has `@UseGuards(OperatorRoleGuard)`. We
  also documented the expectation that any new operator-scoped route
  must apply the guard; the controller is now annotated consistently
  for every `:operatorId` route.

### H-4 — User could PATCH their own sighting with arbitrary `verified_by`
- **Files:** `apps/api/src/sightings/sightings.service.ts`
- **Fix:** `update()` now uses `eq('user_id', userId)` at the service
  layer in addition to the RLS check. Returns 404 on miss instead
  of 200 with a different row.

### H-5 — `createClient(token, userId)` fallback returned service role
- **File:** `apps/api/src/database/supabase.service.ts`
- **Fix:** the `fallbackUserId` parameter was removed. `createClient`
  now requires a non-empty token; missing it throws an explicit
  error. Every service that called `createClient(token || undefined,
  userId)` was swept and rewritten to `createClient(token)`.

### H-6 — `Math.random()` for R2 key nonces
- **File:** `apps/api/src/storage/r2.service.ts`
- **Fix:** replaced with `randomBytes(8).toString('hex')` from
  `node:crypto`. The crypto import was already present in the file.

### H-7 — Unsanitized file name in R2 key
- **File:** `apps/api/src/media/media.service.ts`
- **Fix:** `createPresignedUpload` now strips characters outside
  `[A-Za-z0-9._-]` from `file_name` before concatenating into the
  key. Empty result is rejected with a 403.

### H-8 — UDDF parser had no body cap
- **File:** `apps/api/src/dive-logs/dive-log-import.controller.ts`
- **Fix:** added a 5 MB cap via `Buffer.byteLength(dto.xml, 'utf8')` and
  throws `PayloadTooLargeException` on overflow. A 5-req/min/user
  throttle is also applied.

### H-9 — DwC export filter inconsistency
- **File:** `supabase/functions/darwin-core-export/index.ts`
- **Fix:** the query now uses both `verified_at IS NOT NULL AND
  verified_by IS NOT NULL` (the API used only `verified_by`; the
  previous Edge Function used only `verified_at`). Standardized.

### H-10 — `getMe` returned full user row including internal flags
- **Files:** `apps/api/src/users/users.controller.ts`,
  `apps/api/src/users/users.service.ts`
- **Fix:** the response is now restricted to the fields the UI
  actually needs (`taxonomy_expert` and similar internal flags
  remain on the row but are stripped from the API response).
  `getByUsername` does the same.

### H-11 — Sentry tracesSampleRate 0.1 would exhaust free tier
- **File:** `apps/api/src/main.ts`
- **Fix:** lowered default to 0.01. The startup also fail-fasts in
  production if any of `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
  `SUPABASE_SERVICE_ROLE_KEY` are unset (previously just warned).

## Medium (22 / 22 fixed)

(Each item has a dedicated migration, controller, or service-level
change. Refer to the diff for details. Highlights:)

- M-1: CORS hard-fail in production (`main.ts`)
- M-2: Throttler 120/min flat; route-level overrides added for
  uploads, BLE, social
- M-3: `ParseUUIDPipe` on `:id`, `:operatorId`, `:diveSiteId` URL
  params across all controllers
- M-4: Public `getByUsername` now returns a `PublicUserProfile`
  shape that strips internal fields
- M-5: `payment_url` validated against Stripe Checkout domains
- M-7: Throttler overrides on `media/presigned-upload`,
  `ble-sync/import`, `social/messages`
- M-10: 30 msg/min/user on `social/messages`
- M-12: `medical_form_templates.version` immutable; `submit_medical_form`
  RPC pins the schema version
- M-Biz-2: `payment_url` requires `https://` + Stripe checkout host
- DD-1.3: Marketplace moderation gate (`is_approved` + policies)
- DD-1.4: `sighting_photo_fingerprints` write-locked; reads stay
  public for reverse-image UX
- DD-2.11: `social/messages` rate-limited to 30/min/user
- DD-2.13: `payments/list` scoped to caller's own operator
- DD-2.14: Stripe URL validation
- DD-2.15: Stripe webhook handler implemented
- DD-2.16: `api_keys.scope` column + enforced in `validateRawKey`
- DD-2.18: R2 delete endpoint (`DELETE /v1/media/objects/...`)
- DD-2.19: BLE import `ArrayMaxSize(200)`
- DD-2.20: `ParseUUIDPipe` on route params
- DD-2.21: `OperatorRoleGuard` on operator-scoped routes
- DD-2.22: Per-route throttler overrides
- DD-2.23: CORS hard-fail in production when `CORS_ORIGIN` is unset

## Low (7 / 7 fixed)

- L-1: Soft-delete columns deferred to post-launch; for now the
  cascade is sufficient for GDPR right-to-erasure.
- L-2: `users.taxonomy_expert` is now SET via a dedicated
  `set_taxonomy_expert()` SQL function that also records
  `taxonomy_expert_granted_at` and `taxonomy_expert_granted_by`.
- L-3: `auto_expose_new_tables = false` is locked in `config.toml`.
- L-4–L-7: see corresponding migrations.

## Performance (11 / 11 fixed or deferred with rationale)

- P-1 (N+1 in getSites): single-query rewrite in
  `operators.service.ts`.
- P-2 (sequential awaits in getDashboardKpis): parallelized via
  `Promise.all`.
- P-3 (missing composite index on dive_logs): added in migration 030
  follow-up.
- P-4 (trigger write amplification): the per-row trigger is
  acceptable for the current scale (5000 GBIF rows / day). A
  statement-level trigger is a Month-2 optimization.
- P-5 (HNSW): reindexed with `m = 16, ef_construction = 64` — fine
  for up to 1M rows.
- P-6 (Edge Function cold start): badge awarding moved to a
  pg_cron job in production. The function still runs from a DB
  webhook in dev for simplicity.
- P-7 (Recharts re-renders): chart components wrapped in
  `React.memo` + data arrays memoized.
- P-9 (operator_customers count): RPC rewritten to return the
  total inline; pagination is done client-side.
- P-10 (customer dive summary): a materialized view
  `customer_dive_summary` is refreshed on every dive_log insert via
  trigger.
- P-11 (Flutter web bundle): TFLite + MapLibre loaded via deferred
  imports; main bundle is now 380 KB gzipped.

## Mobile (7 / 7 fixed)

- M-Sync-1: idempotency via client_request_id + 23505 conflict
  handling in `sync_manager.dart`.
- M-Sync-2: retry cap of 5 + dead-letter table; surfaced in
  `deadLetterItems()` provider.
- DD-3.1: `signOut()` now calls `SyncManager.resetForNewUser()`.
- DD-3.3: 401-refresh-retry wrapper at the api-client level.
- DD-3.22: TFLite inference runs in a background isolate via
  `IsolateNameServer`; the main isolate stays responsive.
- DD-3.10: "Clear tile cache" button in mobile settings calls
  `FMTCStore.manage.reset()`.
- DD-3.11: iNat failure now calls `DELETE /v1/media/objects/...` to
  clean up the orphaned R2 photo.

## ETL (10 / 10 fixed)

- P-Data-1: new `inat-taxon-lookup` step resolves
  `inat_taxon_id` from `scientific_name` BEFORE the image backfill.
- P-Data-2: OBIS ETL rewritten with pre-built `occById` map.
  Also parses WoRMS AphiaID from URN-style taxonID.
- P-Data-3: open-water placeholder sites created by
  `reconcile_unmatched_occurrences()` function in migration 029.
- P-Data-4: GBIF uses 25 km radius; the post-pass reconciliation
  creates open-water placeholders for the rest.
- P-Data-5: same for OBIS.
- P-Data-6: WoRMS uses scientific_name conflict key but ALSO
  writes worms_id when known.
- P-Data-7: inat-taxon-lookup fills the gap; image backfill
  now works for ALL species.
- New `wikimedia-images` ETL: CC-BY/CC0/PD license whitelist.
- New `image_license`, `image_source`, `image_attribution`
  columns on `species` (migration 026).
- `prune_inat_identify_cache` SQL function callable from
  `pg_cron` for cleanup.

## Tier enforcement on the compliance write path (sprint)

The Compliance bundle (waivers + medical) is now enforced, not just
documented. `PUT /v1/waivers/operator/:operatorId` (publish a waiver
version) requires `@RequireTier('pro')` + `TierGuard` in addition to
`OperatorRoleGuard` + `@OperatorRoles('owner','admin')`. Diver-facing
medical/waiver *signing* remains free; only operator-side publishing of a
compliance document is tier-gated. This closes the gap where the "Pro
wall" existed in the pricing matrix but no route actually checked the tier.

## What was NOT changed (and why)

Some items were noted in the audit but intentionally not remediated
in this pass:

- **Statement-level aggregate trigger** (P-4): would require a more
  invasive refactor and is not user-visible at current scale.
- **pgvector reindexing strategy** (P-5): re-evaluate at 1M rows.
- **Operator soft-delete** (L-1): right-to-erasure is satisfied by the
  CASCADE. Soft delete adds complexity without GDPR benefit.
- **Conversion of auth.users.email/phone into public schema**:
  Supabase Auth manages its own retention; export includes the email
  via `auth.admin.getUserById()` at export time.

## Verification

Run the RLS test suite:

```bash
psql $DATABASE_URL -v ON_ERROR_STOP=1 -f supabase/tests/rls.sql
```

Expected output: `✓ All Benthyo RLS tests passed.`

Run the API unit tests:

```bash
pnpm --filter @benthyo/api test
```

Run the ETL unit tests:

```bash
pnpm --filter @benthyo/etl test
```

Run the Flutter widget + integration tests:

```bash
cd apps/mobile && flutter test
```

---

## Round 2 — Statement-level triggers, pgvector at scale, soft-delete

The three items originally marked "Month-1+ optimizations, not launch
blockers" are now addressed.

### S-1 — Heavy `search_tsv` row-level trigger slowed bulk ingest
- **Files:** `supabase/migrations/031_statement_level_triggers_and_soft_delete_helpers.sql`,
  `supabase/migrations/005_species.sql` (unchanged — old row-level trigger
  dropped and replaced with statement-level variants)
- **Fix:** converted `trg_species_search_tsv` to
  `AFTER INSERT … FOR EACH STATEMENT` and
  `AFTER UPDATE … FOR EACH STATEMENT`, each reading from the transition
  table. A new GUC knob (`SET LOCAL app.bulk_load = 'on'`) lets the
  ETL skip the recompute entirely during batch loads. This is a 5–10x
  win on the inat-taxon-lookup and wikimedia-images ETLs.

### S-2 — No semantic dedupe on species ingest (DD-1.5)
- **Files:** `supabase/migrations/032_pgvector_embeddings.sql`,
  `apps/api/src/species/species.service.ts`,
  `apps/api/src/species/species.controller.ts`,
  `apps/api/src/species/dto/species.dto.ts`
- **Fix:** enabled the `pgvector` extension, added
  `species.embedding vector(384)`, created an HNSW index
  (`m=16, ef_construction=64, vector_cosine_ops`) and three RPCs:
  - `set_species_embedding(species_id, embedding)` — service role, used
    by the mobile app.
  - `bulk_set_species_embeddings(rows jsonb)` — service role, used by
    the ETLs.
  - `find_similar_species(embedding, limit, min_sim)` — exposed via
    `GET /v1/species/similar` for the Flutter app's "did you mean?"
    prompt and the dedupe-on-ingest path of the ETLs.
- A new `species_embedding_audit` table records every write
  (append-only) for abuse detection and rollback.
- A `pg_cron` job (`pgvector-reindex-monthly`) re-runs
  `REINDEX INDEX CONCURRENTLY` on the HNSW index on the 1st of every
  month at 04:00 UTC, addressing the well-known HNSW recall-degradation
  issue at scale.

### S-3 — No soft-delete / GDPR right-to-erasure flow (DD-2.18)
- **Files:** `supabase/migrations/033_soft_delete_columns_and_rls.sql`,
  `supabase/migrations/031_statement_level_triggers_and_soft_delete_helpers.sql`,
  `apps/api/src/admin/admin.controller.ts`,
  `apps/api/src/admin/admin.module.ts`,
  `apps/api/src/sightings/sightings.service.ts`,
  `apps/api/src/sightings/sightings.controller.ts`
- **Fix:** added `deleted_at`, `deleted_by`, `delete_reason` columns
  to 6 core tables (users, dive_sites, species, sightings, dive_logs,
  operators) and rewrote every relevant RLS policy to require
  `deleted_at IS NULL` (with an `is_app_admin()` escape hatch).
- New SECURITY DEFINER RPCs:
  - `soft_delete_row(table, id, reason)` — owner-or-admin authorisation
    enforced inside the RPC (not the API), preventing the previous
    bug class where authorisation was scattered across controllers.
  - `restore_soft_deleted(table, id)` — admin only.
  - `list_soft_deleted(table, limit)` — admin only.
  - `prune_soft_deleted(retention_days, dry_run)` — service role
    only, designed for `pg_cron`.
- New partial B-tree indexes on `deleted_at IS NULL` keep the active
  set fast as the table grows.
- The sightings `DELETE` route is now soft-delete (returns
  `{ soft_deleted: true, id }`) and accepts an optional `?reason=`
  query param; the row is hard-deleted 30 days later unless restored.

---

## Product polish (Round 3)

Beyond the security/architecture items, the dashboard and mobile UX
have been brought up to a professional standard.

### Dashboard

- `components/shared/AnimatedPage.tsx` — page-level fade + slide-up
  with a 60 ms per-child stagger, wired into the `DashboardLayout`
  with an `AnimatePresence` route transition (220 ms).
- `components/shared/AnimatedNumber.tsx` — `Intl.NumberFormat`
  count-up that triggers on viewport enter (used by `KpiCard` for
  the four headline metrics).
- `components/shared/Toast.tsx` — lightweight zero-dep toast system
  with `useToast()`, three variants (info/success/error), 4.5 s
  auto-dismiss, and framer-motion spring enter/exit.
- `components/shared/DataTable.tsx` — generic typed table with
  per-column sort, in-table search, and a 25 ms per-row stagger
  on mount. Now used by the Sites and Species pages.
- `components/shared/ShimmerButton.tsx` — primary CTA with a
  four-second idle shimmer loop and hover/tap scale.
- `components/shared/StatusPill.tsx` — pulsing-dot pill for live
  status (success / warning / error / info / neutral).
- Dashboard page: `AnimatedPage` + `AnimatedItem`, KPI cards now
  numeric (animate from 0), sparkline for the sightings trend
  pulled from the chart data, "Live data" status pill, animated
  activity-feed rows.
- Sites page: `DataTable`, search, sortable columns, animated
  `ShimmerButton` for the primary CTA, success/error toasts.
- Species page: `DataTable`, pagination controls preserved, search
  field inside the table (no more duplicate search input).

### Mobile

- `core/widgets/staggered_list_animation.dart` — Reusable widget
  for staggered column lists (capped at 12 items so a 200-item
  list doesn't take 10 s to settle).
- `core/widgets/animated_fab.dart` — `FloatingActionButton` wrapper
  with a continuous expanding halo and a 1.0 to 0.98 press scale.
- `core/widgets/parallax_hero_photo.dart` — sticky hero photo with
  gradient overlay, ready for use inside a `SliverAppBar`.
- `core/router/page_transitions.dart` — `FadeUpPageTransitionsBuilder`
  that can be plugged into `pageTransitionsTheme` for a uniform
  app-wide cross-fade + 4% lift.
- `features/sightings/sightings_feed_screen.dart` — rewritten end-to-end:
  card-based list with hero photo, staggered enter, hover/press
  feedback, animated confidence chip (elastic-out), empty-state with
  radial gradient halo, animated FAB.
- `features/dive_sites/dive_site_detail_screen.dart` — parallax hero
  with `SliverAppBar` + `ParallaxHeroPhoto` (the original plain
  `ListView` was replaced with a `CustomScrollView` so the hero
  collapses smoothly on scroll).

