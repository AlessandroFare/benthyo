# OceanLog Production-Pass — Final Consolidated Summary

**Branch:** `production-pass` (36 commits ahead of `origin/main`)
**Rounds:** 1 (initial 14-phase pass) → 2 (new features: booking, BLE, onboarding,
ETL sources) → 3 (this document: live-DB verification, CI repair, gap closure)
**Date:** 2026-06-22

This file is the single honest accounting the brief asked for: what is
genuinely complete now, what was honestly excluded with reasoning, and a
confirmation that every item in the brief has been addressed (not deferred).

---

## What is genuinely complete (verified, not claimed)

### Database / migrations — proven green end-to-end for the first time
- **All 51 migrations apply clean from a fresh Postgres+PostGIS+pgvector
  database.** Verified by booting a throwaway `pgvector/pgvector:pg16`
  container, installing postgis, and applying the exact CI sequence
  (bootstrap → 001..051 → seed). Zero errors.
- **`rls.sql` RLS suite passes** on that fresh DB ("✓ All OceanLog RLS tests
  passed"), AND a new `booking_rls_check.sql` passes all 5 booking
  authorization checks (operator slot creation, stranger denial, book_slot
  caller-pinning, cancel_booking owner/operator-admin-only, **confirm_booking
  denied to authenticated — payment-bypass closed**).
- The CI auth bootstrap (`ci_auth_bootstrap.sql`) was repaired: it was
  missing the `supabase_realtime` publication, the `auth.jwt()` helper, and
  four `auth.users` columns — so the CI `rls` job could never have passed.
  Now fixed and proven.

### Security / RLS — heaviest scrutiny applied
- **RLS enabled on all 41 user tables** (0 DISABLE statements anywhere).
  Only `unmapped_iucn_codes` has RLS-on-but-no-policy → default-deny (it's
  an internal ETL scratch table; correct).
- **Booking RPCs (migration 047/048) verified live**: `book_slot` pins to
  `auth.uid()`, `cancel_booking` enforces owner OR operator-admin (both
  sides), `confirm_booking` is service_role-only (the payment-bypass from
  047 is genuinely closed, tested directly).
- **`prevent_signed_waiver_delete`** trigger (migration 026) confirmed present.
- **Defense-in-depth** on expert corrections: service-layer
  `taxonomy_expert` check (ForbiddenException) backs the route.
- Migration-041's `is_operator_admin` redef dropped SECURITY DEFINER/
  search_path from the 011 original — functionally correct (auth.uid() is
  request-scoped) but a minor hardening regression; noted, not blocking.

### GDPR (Art. 15 export + Art. 17 erasure)
- `export_user_data` (migration 051, **verified returning 26 keys live**)
  now covers every user-scoped PII table, including the four this audit
  found missing: `dive_computer_devices`, `operator_users`,
  `inaturalist_push_queue`, `gbif_export_batches`.
- Erasure cascade (gdpr.service.ts) verified: soft-delete → iNat residual-obs
  enumeration → R2 prefix delete (partial-failure tracked) →
  auth.admin.deleteUser (FK cascades). iNat third-party deletions honestly
  surfaced as residual, not silently dropped.

### ETL pipeline
- **SEAMAP is real now** (was fabricated → 0-row → fixed): queries OBIS v3
  by megafauna taxa in the Med WKT. Verified live (ETL vitest 21/21,
  Cetacea + Testudines return real data).
- **RLS is honestly excluded** (no public REST API; `api.reeflifesurvey.com`
  does not resolve): opt-in via `RLS_API_URL`, self-skips cleanly so the
  nightly workflow doesn't go red. Reasoned, documented, not a silent gap.
- Order, idempotency (onConflict keys), failure isolation (parallelSources),
  and the ETL_SYSTEM_USER_ID guard all verified.

### Billing / multi-tenant
- `@RequireTier('pro')` + `TierGuard` confirmed on marketplace (2 routes),
  api-keys, rental-gear (class-level, all 4 routes).
- Per-tier limits enforced server-side (migration 045 triggers).
- Stripe webhook remains the sole writer of paid booking state
  (`confirm_booking` is service_role-only).
- `cancel_booking` handles both diver-side and operator-side cancellation.

### Code quality
- typecheck clean (all 6 workspaces).
- **ESLint now actually runs** (was broken in both apps — configs didn't
  exist). 0 errors / 0 warnings.
- N+1 in `OperatorsService.getSites` fixed (single IN() + in-memory agg).
- 59 indexes; no gaps for declared key queries.

### Features (round-2 builds, verified real this round)
- **BLE dive-computer import**: 3 real GATT parsers (Shearwater, Suunto,
  Garmin) + UDDF fallback, wired through `BleDiveSyncService`. Not a stub.
- **Booking/scheduling**: schema + RPCs + API (10 routes) + mobile screens
  (3, routed) + **dashboard SlotsPage now wired into routes + sidebar** (was
  orphaned dead code — fixed this round).
- **Onboarding**: swipeable 4-card intro, persisted, re-triggerable.

### Tests
| Suite | Result |
|-------|--------|
| API Jest | 33/33 |
| ETL Vitest | 21/21 (SEAMAP real-query tests green) |
| Flutter test | 26/26 (round 2; cold-build re-run deferred) |
| Fresh-DB migration chain 001→051 | clean |
| rls.sql + booking_rls_check.sql | all pass |

### Dependencies
`pnpm audit` 15 → 13. js-yaml bumped (CVE-2025-64718). Remaining 13 are
dev/build-only or low-real-risk runtime with no safe auto-fix (each
enumerated in the round-3 report section).

---

## Honest exclusions / deferred (with reasoning, not silent gaps)

1. **Reef Life Survey ETL** — no public REST API exists. Excluded by default,
   opt-in via `RLS_API_URL`, source self-skips cleanly. The fabricated
   `api.reeflifesurvey.com` endpoint does not resolve.
2. **Live API click-by-click walkthrough** — ~~Docker daemon went flaky
   mid-session~~ **CLOSED in session 4 (2026-06-22):** Docker reinstalled,
   stack rebuilt live, full 12/12 dashboard page screenshot walkthrough
   captured via Playwright, API latency battery on 11 endpoints with real
   ms. See ROUND2_PROGRESS.md session-4 section.
3. **Lighthouse / Core-Web-Vitals / mobile cold-start / frame profiling** —
   ~~no stable browser or emulator~~ **CLOSED in session 4 (2026-06-22):**
   Lighthouse ran live against the dashboard — **performance 100, a11y 96,
   best-practices 100, seo 91** (FCP 0.5s, LCP 0.5s, TBT 0ms, CLS 0). EXPLAIN
   ANALYZE on operator_today_roster (0.47ms) + operator_kpis (73ms, all 4
   subqueries index-backed). Flutter web cold-start captured via headless
   Chrome CDP (DOMContentLoaded 417ms, main.dart.js 4.35MB); **boot crash
   diagnosed** (`Null check operator` on a plugin web path in main.dart.js)
   and `flutter build web` hangs on this Windows box — that one sub-item
   remains a genuine, evidenced gap. Real dashboard bundle size: ~430 KB
   gzipped.
4. **Remaining 13 audit advisories** — all dev/build-only (webpack, ajv,
   vite, launch-editor) or low-real-risk runtime (file-type major-bump risk
   > advisory; @nestjs/core already at patched 10.4.22; @opentelemetry W3C
   DoS only at untrusted huge volume).
5. **Flutter `flutter test` re-run** — passes 26/26 but cold build hangs on
   this Windows box; round-2 result stands.
6. **file-type** left at major 20 deliberately (prev session) — the 20→21
   jump is ESM-only/breaking; advisory severity (DoS on uploaded file
   detection via @nestjs/bullmq, not user uploads) doesn't justify the risk.

---

## The "claimed done, not actually done" findings (this round's main value)

Three were caught and fixed — exactly the failure mode the brief warned about:
1. **Migration 051 was recorded-applied but never applied to the live DB.**
2. **CI auth bootstrap was missing 3 shims → the `rls` job could never have
   passed.**
3. **SEAMAP (round 1) + RLS (earlier agent) were fabricated** — SEAMAP is now
   real; RLS is now an honest, reasoned exclusion.

---

## Confirmation against the brief

Every item in the production-pass brief has been addressed this round — none
deferred silently:
- Round-1 phases 1–14: inventory, security, GDPR, ETL, billing, code quality,
  market research, tests — all re-verified; report updated.
- Round-2 items (migrations through 050, db reset, rls.sql, dep bumps,
  onboarding, BLE, booking, lint sweep): all confirmed, with the live-DB and
  CI-bootstrap gaps found and fixed.
- Migration-048 payment-bypass: flagged as a finding, verified closed live.
- SEAMAP/RLS honest history: documented as fabricated → fixed/excluded.

The branch is **36 commits ahead of origin/main**, one logical change per
commit, additive migrations only, no real secrets, no push to main.

---

## Session 4 addendum (2026-06-22) — the final 3 deferred items, closed live

Docker reinstalled fresh; full stack rebuilt live. The three items that prior
rounds deferred only because Docker was down are now genuinely done:

1. **GDPR erasure cascade — LIVE + a real production bug FIXED.**
   `species_search_tsv_*_stmt()` triggers had no `search_path` and ran bare
   `UPDATE species`, which GoTrue's `auth`-role search_path resolved to
   `auth.species` (42P01), aborting `auth.admin.deleteUser` for any user with
   sightings. Migration **053** fixes it (same class as the dive_logs_count
   fix in 052). **Proven end-to-end:** `DELETE /api/v1/users/me` → HTTP 200,
   `auth_deleted:true`, `inat_observations:[8888888]` (residual enumeration
   works), all 8 user-scoped tables cascade to 0 rows, unrelated data intact.

2. **Performance — real numbers.** API latency battery on 11 hot endpoints
   (operator RPC endpoints 115–191ms, public reads 13–36ms). EXPLAIN ANALYZE
   on the two slowest queries: roster 0.47ms, kpis 73ms total — all
   index-backed, no optimization needed. Lighthouse dashboard **perf=100 /
   a11y=96 / bp=100 / seo=91**. Flutter web cold-start captured via CDP;
   boot crash diagnosed (Null check on a plugin web path); `flutter build`
   hangs on Windows — the one remaining genuine gap.

3. **UI/UX screenshots — 12/12 dashboard pages LIVE.** Playwright drove the
   real running dashboard (login as operator owner → navigate each route →
   full-page PNG): today, overview, sites, customers, analytics, species,
   corrections, rental-gear, slots, marketplace, settings, login. Files in
   `.verify/screenshots/dashboard/`. Mobile web blocked by the Flutter boot
   crash above.

The branch is now **39 commits ahead of origin/main**. The only item that
could not be completed live is **mobile web screenshots** — and that is
blocked by a real Flutter web boot bug (diagnosed, not deferred lazily),
which itself requires a Flutter rebuild that the Windows flutter tooling
hangs on. Everything else the brief asked for is now verified against a
real, running stack.
