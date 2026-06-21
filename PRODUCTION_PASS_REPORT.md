# OceanLog — Production-Readiness Pass Report

**Branch:** `production-pass` (one logical change per commit)
**Date:** 2026-06-20/21
**Scope:** 14-phase audit/fix/research/polish pass per the production-pass brief.

---

## 0. Honesty preface — what this environment could and could not do

This pass ran on a Windows dev box **without** `psql`, a running Supabase
stack, a browser/Lighthouse runner, or mobile devices/emulators. Therefore:

- **Verified by execution here:** TypeScript typecheck (all workspaces),
  API Jest suite (24 tests), ETL Vitest suite (4 tests), `flutter test`
  (12 tests). Every code fix below was typechecked and, where a unit path
  exists, unit-tested.
- **Written but executed only in CI / not here:** all SQL migrations and the
  RLS test suite. CI's `rls` job (`.github/workflows/ci.yml`) applies every
  migration + seed against a real `postgis/postgis:16` and runs
  `supabase/tests/rls.sql`. The new migrations (043–046) and RLS test blocks
  are written to run there; they were **not** executed in this session.
- **Not done (require a live stack/devices/browser):** live API latency
  numbers, Lighthouse/Core-Web-Vitals, mobile cold-start/frame profiling, and
  a click-by-click app walkthrough. These are reported as **deferred** with
  the reason, not faked. No before/after performance numbers are invented.

Every "fixed/added" claim below points to a commit, a passing test, or a
diff. Where something is analysis or a recommendation rather than shipped
code, it says so.

---

## 1. Inventory

Monorepo (`pnpm` + `melos`), 7 workspaces:

| Area | Stack | Entry |
|------|-------|-------|
| `apps/api` | NestJS 10, Supabase JS, Pino, Sentry | `src/main.ts` (135 TS files) |
| `apps/dashboard` | React + Vite + Tailwind + shadcn + Framer Motion | `src/main.tsx` (64 files) |
| `apps/mobile` | Flutter, Riverpod, GoRouter, flutter_map, sqflite | `lib/main.dart` (113 Dart files) |
| `apps/mcp-server` | MCP integration | — |
| `packages/types`, `packages/ui` | shared DTOs + UI | — |
| `etl` | tsx + Vitest, 11 sources | `run-all-data.ts` |
| `supabase` | 46 migrations (001–046), Edge Functions, RLS suite | — |

README's "migrations 000..030" line is stale doc only — the tree has 001–046
and the roster RPC (041/042) and pgvector/soft-delete (032/033) all exist.
Baseline before changes: typecheck green, 15 API tests, 4 ETL tests, 12
Flutter tests — all passing.

---

## 2–4. Security / GDPR / ETL — found and fixed

Each invariant was re-verified against current code. **8 of 9 README security
invariants held**; the drift found and fixed:

### CRITICAL — Medical encryption used a public dev key at runtime
**Commit `6ed2002`.** `MedicalService` read `MEDICAL_ENCRYPTION_MASTER_KEY`
from env but never set the `app.medical_master_key` GUC on the Supabase
session, and PostgREST runs each `.rpc()` in its own transaction, so the
key-derivation helpers (`038`/`040`) silently fell back to
`'oceanlog-dev-master-key-do-not-use-in-prod'`. Production GDPR Art. 9
medical answers were effectively encrypted under a publicly-known key.
**Fix:** migration `043` adds `submit_medical_form_v2` /
`my_medical_submissions_decrypted_v2` SECURITY DEFINER wrappers that
`set_config(..., is_local => true)` the key+salt in the same transaction as
encrypt/decrypt; `MedicalService` threads the env key/salt through them and
**fail-fasts at boot in production** if the master key is unset.
Tests: `medical.service.spec.ts` (3) assert the threading + fail-fast.

### HIGH — Pro features were not tier-gated
**Commit `648ac65`.** Only waiver-publish carried `@RequireTier('pro')`.
Marketplace create/update, all rental-gear routes, and API-key creation were
usable on Free/Starter. Added `@RequireTier('pro')` + `TierGuard` to each.
Also removed an unsafe `params.id` fallback in `TierGuard` operator
resolution (on `/operators/me/marketplace/:id` that `:id` is the *listing*
id, which would mis-resolve the tier lookup).

### HIGH — Tier resource limits were not enforced
**Commit `0a4ec0a`.** `linkSite`/`inviteMember` inserted with no count check;
operators could exceed the README caps (sites 3/10/100, team 1/5/20). Added
server-side `assertUnderTierLimit` + migration `045` BEFORE INSERT triggers
as a DB-level second line for direct PostgREST writes (`service_role`
bypasses). Tests: `operators.tier-limit.spec.ts` (4).

### HIGH — Sightings verification RLS bypassed the expert/self-verify rules
**Commit `06a630e`.** `sightings_admin_verify` (011) let any operator
owner/admin set `verified_by` via a direct PostgREST call with no
`taxonomy_expert` check and no self-verify guard — defeating the
"defense-in-depth at the RLS layer" claim for the data-moat. Migration `044`
replaces it with `sightings_expert_verify` (requires `taxonomy_expert`,
`verified_by IS NULL`, `user_id <> auth.uid()`, WITH CHECK pinning
`verified_by`) and adds a `prevent_self_verify_columns` trigger so the
reporter's own UPDATE policy can't set verification columns either. RLS test
block added.

### HIGH — GDPR erasure reported success on failure; iNat step absent
**Commits `63ca0de`, `16e24ba`.** `eraseUser` returned `{ ok: true,
auth_deleted: false }` when `auth.admin.deleteUser` failed — caller believed
the account was erased. Now **throws 500** on that failure (account stays
soft-deleted/recoverable). The README-documented iNaturalist deletion was
entirely missing; the platform can't delete user-owned iNat observations
without the user's OAuth token, so erasure now **enumerates and returns the
residual observation ids** + logs them (honest accounting) rather than
pretending. R2 partial failure is surfaced too. Export (migration `046`) now
includes `buddy_messages_received` + `buddy_conversations` (Art. 15 covers
received messages, not only sent). Tests: `gdpr.service.spec.ts` (2).

### MEDIUM — Three tables shipped without RLS
**Commit `06a630e` / migration `044`.** `species_embedding_audit`,
`pgvector_reindex_log`, `unmapped_iucn_codes` had no RLS; the first also
granted `SELECT` to every authenticated user (full audit-log read). Enabled
RLS on all three; revoked the broad grant (audit reads are now
service-role-only).

### Invariants confirmed intact (no change needed)
No `fallbackUserId`/service-role fallback on user paths (`supabase.service.ts`
throws on empty token); operator role checks at controller **and** RLS;
`subscription_tier` mutable only via `set_operator_subscription()` — note the
`026` `WITH CHECK` self-reference was a no-op but the `036` BEFORE UPDATE
trigger holds the line (RLS test added to prove it); waiver eIDAS capture
(IP/UA/email/SHA256) intact; CORS hard-fails in prod; no secrets in client
bundles (grep of dashboard/mobile clean — only anon/publishable keys).

### ETL correctness
Order in `run-all-data.ts` matches the README/ADR-015 exactly
(worms → sites∥ → apify → gbif∥obis → reconcile → inat-taxon-lookup →
images). Each top-level step is try/caught and the run exits non-zero if any
failed. **Found weakness:** the two parallel batches used `Promise.all`, so
one source throwing aborted its siblings and discarded their work — contrary
to the stated per-source isolation. **Commit `518b4da`** adds
`parallelSources()` (`Promise.allSettled` + per-source recording).
Idempotency: each source upserts on its documented `onConflict` key (spot-
checked gbif/worms) — unchanged.

---

## 5. New data sources — evaluation

Researched authoritative marine/dive sources beyond the current set
(GBIF, OBIS, WoRMS, iNaturalist, OpenDiveMap, Overpass, Apify Google Maps).
Evaluation for licensing / quality / coverage gain:

| Source | License | Adds | Verdict |
|--------|---------|------|---------|
| **OBIS-SEAMAP** (Duke) | CC-BY | Marine mega-fauna (turtles, mammals, birds) tracks | **Worth adding** — complements GBIF/OBIS for charismatic species divers actually log; same occurrence shape, slots beside obis. |
| **Reef Life Survey (RLS)** | CC-BY 4.0 | Standardised reef fish/invert transects, Indo-Pacific + Med | **Worth adding** — high-quality, dive-relevant; per-site abundance. Needs a small column map (RLS codes → WoRMS). |
| **NOAA CRCP / NCEI** | Public domain (US gov) | Coral reef monitoring, US/Caribbean/Pacific | Worth adding for US coverage; large, needs throttling. |
| **Copernicus Marine (CMEMS)** | Free, attribution + account | SST, chlorophyll, currents (environmental, not occurrences) | **Defer** — enriches dive-condition layer, not species; raster/NetCDF, bigger build. |
| **Protected Planet (WDPA)** | Custom non-commercial terms | Marine-park boundaries | **Skip** — license not clean for a commercial B2B product; legal risk outweighs gain. |
| National dive-site DBs (UK BSAC, AU, etc.) | Mixed/unclear | Regional sites | **Skip for now** — fragmented licensing, low marginal coverage over OpenDiveMap+Overpass. |

**Implemented this pass:** none shipped as runnable ETL — each worth-adding
source needs a real upstream key/endpoint and a mocked-fixture Vitest test to
match the existing source pattern, a bounded but real build per source. They
are scoped as the top of the data-roadmap rather than half-built. The new
`parallelSources()` helper and the documented slot order make adding
OBIS-SEAMAP / RLS a localized change (new `etl/<source>/` + one line in
`run-all-data.ts` near step 4, idempotent upsert on
`occurrence_id`/`scientific_name`).

---

## 6. Multi-tenant / billing

Covered in §2–4: every Pro route now `@RequireTier('pro')`; limits enforced
in service + DB trigger; Stripe webhook remains the only writer of
subscription state (`stripe.service.ts` → `set_operator_subscription()`),
verified by `constructEvent` signature check, and the `036` trigger blocks
any other path. No change needed to the webhook itself.

---

## 7. Code quality & correctness

- **N+1 fixed** (`77dedd4`): `OperatorsService.getSites` issued one
  `species_dive_site_stats` query per linked site (the SECURITY_AUDIT P-1
  "single-query rewrite" had regressed to a loop). Now 2 queries total via
  `IN()` + in-memory sum.
- Typecheck clean across all workspaces; API `tsc --noEmit` clean.
- No swallowed-error regressions introduced; GDPR R2/iNat failures are now
  surfaced rather than silently zeroed.

Not exhaustively swept: a full dead-code/lint pass across 135 API + 64
dashboard + 113 Dart files was not run to completion here (ESLint/knip need a
clean install + time budget); flagged as a follow-up, not claimed done.

---

## 8. Performance audit

**Static wins shipped:** the getSites N+1 (§7) — an operator with N sites
drops from N+1 to 2 queries. **Live numbers (API latency, slow-query plans,
Lighthouse, mobile frame/cold-start) were NOT measured** — no running stack
or device in this environment. SECURITY_AUDIT documents prior perf work
(memoized Recharts, deferred Flutter imports, 380 KB gzipped main bundle,
HNSW params); those were not re-measured. **Deferred with reason**, no
fabricated before/after.

---

## 9. UI/UX audit & polish

SECURITY_AUDIT "Round 3" documents an existing animation/polish layer
(AnimatedPage, AnimatedNumber, Toast, DataTable, ShimmerButton, mobile
staggered lists, parallax hero, page transitions). **Without a browser/device
I could not visually audit screens or produce screenshots**, so no UI changes
were made this pass — making cosmetic edits I can't see would risk the
performance budget and can't be grounded. **Deferred**; recommend running the
`browser-qa` / Lighthouse pass against a deployed preview as the next step.

---

## 10. Market research — findings

Segments OceanLog spans: **(a) dive-logging consumer apps**, **(b)
citizen-science marine platforms**, **(c) dive-operator management software**.

**Competitive landscape (analysis from domain knowledge, not a live web
scrape this session):**
- Consumer logging: Subsurface (free, desktop-strong, open data), Diviac,
  PADI Adventures/ScubaEarth, MacDive, deepblu. Bar: fast dive entry,
  dive-computer import (UDDF/Bluetooth), buddy/social, offline.
- Citizen science: iNaturalist, Reef Life Survey, eOceans, REEF.org surveys.
  Bar: verifiable, expert-reviewed records that flow to GBIF/OBIS.
- Operator management: DiveShop360, DIVES, centre-management suites. Bar:
  bookings/roster, customer CRM, **digital waivers + medical** (the legal hook),
  rental/asset tracking, payments.

**OceanLog vs that bar — gaps ranked by value:**

1. **Dive-computer import breadth** (consumer table-stakes). UDDF import
   exists (`dive-log-import`), but Bluetooth/native-computer ingestion is the
   real adoption driver. *Roadmap — large (per-vendor protocols).*
2. **Bookings/scheduling depth for operators.** Roster (Today) exists, but
   online booking + capacity + pay-at-booking is what operator suites sell.
   *Roadmap — large.*
3. **Offline-first reliability on mobile** is necessary, not differentiating;
   confirm sqflite sync robustness (SECURITY_AUDIT M-Sync items suggest it's
   handled). *Verify, not build.*
4. **Data-moat exports** (GBIF/Darwin Core) — already a differentiator vs
   pure logging apps; keep investing (see §5). *Buildable incrementally.*
5. **Pricing alignment:** the Compliance bundle (waivers+medical) correctly
   anchors Pro — a legal need, highest willingness-to-pay. €29 Starter
   (analytics+CRM+roster) is reasonable; the risk is Free (3 sites) being too
   generous for tiny centres to ever upgrade. *Pricing experiment, not code.*

**Implemented this pass:** none of the gaps are small enough to build+test
responsibly inside this pass without a live stack; building one half-way would
violate the brief's "don't start and abandon." They are documented as a
prioritized roadmap above. The **billing-correctness work (§2,§6) directly
protects the pricing model** this analysis calls OceanLog's strongest asset —
the highest-leverage market-aligned change available here.

---

## 11. Tests

| Suite | Before | After |
|-------|--------|-------|
| API Jest | 15 pass | **24 pass** (added medical, tier-limit, gdpr specs) |
| ETL Vitest | 4 pass | 4 pass (isolation change is structural) |
| Flutter | 12 pass | 12 pass |
| Workspace typecheck | green | green |
| RLS SQL suite | (CI only) | +2 blocks (self-upgrade, expert-verify) — runs in CI, not here |

New regression tests cover every phase-2–6 fix that has a unit path. RLS
blocks cover the migration-044/036 invariants.

---

## 12. Full app walkthrough

**Deferred — could not be executed.** No running API/dashboard/mobile in this
environment (no DB, no browser, no device). The brief's walkthrough (diver
signup→log→sighting→life list→badges→site page; operator
signup→roster→customer→compliance→upgrade→marketplace) requires the live
stack. Recommend running it against a Supabase preview + `flutter run` before
launch. The code paths touched this pass (medical submit, tier-gated Pro
routes, erasure, getSites) are covered by unit tests instead.

---

## 13. Dependency & CI hygiene

`pnpm audit`: **25 advisories (7 high, 16 moderate, 2 low)**, all transitive.
Highest-value remediations (not auto-applied — they need dependency bumps I
can't validate without running the apps; **documented, not silently
changed**):

- **multer DoS (high, several)** via `@nestjs/platform-express@10.4.22`.
  Bump to NestJS 10's patched multer or move to NestJS 11.
- **lodash `_.template` code injection (high)** — find the pulling dep
  (`pnpm why lodash`) and bump/override to a patched ≥4.17.21 line.
- **dompurify (moderate)** via `posthog-js@1.386.6` → bump posthog-js.
- **qs / js-yaml / file-type / OpenTelemetry (moderate)** — patch bumps.

CI (`ci.yml`) gates PRs correctly: API build+test, dashboard typecheck+build,
ETL test, and a real-Postgres `rls` job that applies all migrations+seed and
runs the RLS suite. CodeQL workflow present. Deploy/ETL-cron workflows match
the README. CI sets the medical GUC session-wide via `PGOPTIONS`, so
migrations 043–046 are compatible there.

---

## 14. Summary

| Phase | Status |
|-------|--------|
| 2 Security invariants | **9 issues fixed** (1 CRITICAL, 4 HIGH, incl. RLS) |
| 3 GDPR | erasure throw-on-fail, iNat residuals, received-msg export |
| 4 ETL | order verified; per-source isolation fixed |
| 5 New data sources | evaluated 6; 3 worth adding, scoped as roadmap |
| 6 Billing | Pro routes gated; limits enforced (service+DB) |
| 7 Code quality | N+1 fixed; typecheck clean |
| 8 Performance | static N+1 win; live metrics deferred (no stack) |
| 9 UI/UX | deferred (no browser/device); existing polish noted |
| 10 Market research | analysed; gaps → roadmap; billing protected |
| 11 Tests | 15→24 API; RLS blocks added; all green here |
| 12 Walkthrough | deferred (no live stack) |
| 13 Deps/CI | 25 advisories documented; CI gating verified |

**Net:** 9 commits on `production-pass`, every code change typechecked and
unit-tested green. The highest-risk real defect — medical data encrypted
under a public key — is fixed. Billing/tenant correctness, the RLS data-moat,
and GDPR erasure are now sound. The deferred phases are deferred because the
environment lacked a DB/browser/devices, not because they were skipped — each
has a concrete next step above and nothing was faked.

---

## Round 2 (2026-06-21)

### Correction to Round 1 inventory claim — migration 041

**Round 1 stated "46 migrations (001–046), baseline all green." This was
typecheck-true but not apply-true.** Migration `041_operator_roster_scheduling.sql`
referenced `users.display_name`, which does not exist in the schema — the
column is `full_name`. A fresh `supabase db reset` or CI's migration loop
aborted at 041, meaning **only 36/46 migrations were ever applied from a
clean database**. Fixed in round 2 to `COALESCE(full_name, username)` (which
migration 042 already assumed). After the fix, `supabase db reset` applied
all 001–046 clean and the full RLS suite now passes sections 1–5 against
real Postgres 17. This is the most important single finding to surface
honestly: round 1's database verification was incomplete.

### Round 2 phases — built and verified

| Phase | Status | Note |
|-------|--------|------|
| 3 Performance | **Measured** | REST latency (8–28ms avg hot endpoints), EXPLAIN ANALYZE on slow RPCs (20–27ms at dev scale), bundle audit (550 KB gzipped — vendor-charts 436 KB, Recharts is the largest single chunk) |
| 4 UI/UX | **Audited (code-level)** | Dashboard: 16 pages, missing i18n, 2 pages with no error state, a11y gaps, no mobile sidebar toggle. Mobile: 36 screens, no Semantics, silent `[]` error returns, no shimmer, no onboarding. All documented with file:line references. |
| 5 Onboarding | **Built and committed** | Mobile swipeable 4-card intro (Explore→Log→Sightings→Journey), PageView + dot indicators, SharedPreferences persistence, re-triggerable from Settings. 12 Flutter tests pass. |
| 8 Deps | **Bumped and verified** | multer ^2.2.0, lodash ^4.18.1, qs ^6.15.2, dompurify ^3.4.11. API 24/24, ETL 4/4, Flutter 12/12 all green. js-yaml/file-type deliberately held at current major (breaking-change risk > advisory severity). |
| 11 Report | This section | — |

### Phase 3 — Performance detail

**Stack**: All 46 migrations applied to `supabase_db_oceanlog` (Postgres 17),
Supabase REST/Auth/Storage/Studio health green throughout. Dev data only
(~200 species, 50 dive sites, 7 operators, 4 users) — no production-scale
wall-clock numbers.

**REST API latency (PostgREST at 127.0.0.1:54321, warm, 10 calls each):**

| Endpoint | Avg | Notes |
|---|---|---|
| `/species?limit=20` | 10.3 ms | Cold start ~122 ms (schema cache) |
| `/dive_sites?limit=20` | 28.1 ms | Geometry column cost |
| `/sightings?limit=20` | 7.9 ms | Simple filtered list |
| `/rpc/operator_kpis` | 9.1 ms | 4-subquery JSON aggregate |
| `/rpc/site_public_card` | 27.1 ms | 6 subqueries + nested |

Max spike ~118 ms (likely GC/pool refresh on PostgREST). All within
acceptable range at dev scale.

**SQL EXPLAIN ANALYZE (key RPCs):**
- `operator_kpis()`: 20 ms, 964 buffers — most expensive found
- `operator_today_roster()`: 27 ms, 1906 buffers — 4 LEFT JOINs + FILTER aggregates
- `operator_customer_retention()`: <1 ms, 9 buffers — well-indexed
- `operator_species_ranked()` / `operator_customers()`: auth-gated, not directly
  measurable from psql

**Index coverage**: 59 indexes across key tables. No obvious gaps. Low
hit rates on species (10%), users (10–17%), user_life_list (20%) are
artifacts of tiny dev data — at production scale these indexes will be used.

**Dashboard bundle**: Vite build 19 s. Total JS ~1.7 MB raw / ~550 KB gzipped.
Largest chunks: vendor-charts 436 KB (117 KB gzip — Recharts), vendor-react
318 KB, vendor-supabase 212 KB. Round 1's SECURITY_AUDIT claimed 380 KB
gzipped — current ~550 KB suggests bundle growth from posthog, additional
chart dependencies, or code-splitting regression. **Recommendation**: if
bundle size becomes a launch blocker, eval replacing Recharts with a
lightweight alternative (uPlot ~50 KB, billboard.js ~100 KB).

### Phase 4 — UI/UX audit summary

**Dashboard (React + Tailwind + Framer Motion):**
- 16 pages, consistent layout via DashboardLayout + Sidebar + TopBar
- AnimatedPage (staggered children) used by 3/11 main pages; AnimatePresence
  on all route transitions; AnimatedNumber in KPI cards; Toast spring animation
- **Key findings**: No i18n framework; Marketplace.tsx and RentalGear.tsx
  have no `isError` state (silent failures); icon-only buttons lack aria-labels
  (Species View, Customers View, Back links); DataTable sortable headers
  have no `aria-sort`; tables lack `overflow-x-auto` on mobile; embed pages
  use fixed pixel widths; Today.tsx default export is inconsistent; AnimatedPage
  adoption is spotty; all formatting defaults to `en-US`.

**Mobile (Flutter + Riverpod + go_router):**
- 36 screen files, strong theme (M3, light/dark/sunlight), FadeUp page
  transitions, StaggeredListAnimation reusable widget (underused)
- **Key findings**: Zero Semantics widgets; 6+ FutureProviders silently
  return `[]` on HTTP errors (user sees "empty" not "error"); no shimmer
  loading states; no retry on detail-screen errors; no pull-to-refresh on
  6 lists; MainNavigationBar rendered per-screen (no ShellRoute); ChatScreen
  uses raw `_loading` instead of `AsyncValue`; WaiverSignScreen reads API_URL
  from env directly.

### Phase 5 — Onboarding flow

Implemented as a Flutter feature following the codebase's existing patterns
(Riverpod + go_router + SharedPreferences). 4 swipeable cards in a PageView:
Explore Dive Sites → Log Your Dives → Record Sightings → Track Your Journey.
Each card has a colored background, large icon, title, and descriptive text.
Dot indicator at bottom, Skip button top-right, Next/Get Started button.

**Persistence**: SharedPreferences key `onboarding_completed`. Router redirect
checks the flag before the splash screen resolves — first launch redirects to
`/onboarding`, subsequent launches go to splash → login/map as normal.
Re-triggerable from Settings > Tools > "Show onboarding intro".

### Deferred to future rounds

- **Phase 9 (Walkthrough)**: requires running API + browser + mobile
- **Phase 10 (Lint sweep)**: ESLint/knip across 135 + 64 + 113 files;
  ~1 day of tooling time, low risk to block
- **Phase 6 (New ETL sources)**: OBIS-SEAMAP + Reef Life Survey are
  chartered, each needs ~1–2 days of implementation following existing
  source pattern (`etl/<source>/` + one line in `run-all-data.ts`)
- **Phase 7 (Large features)**: Bluetooth dive-computer import and
  booking/scheduling are multiple-session builds, scoped as the next
  major round
- **Phase 4 fixes**: i18n, a11y, error-handling — documented with
  file:line, ready for targeted fix passes

### Commits (Round 2, production-pass, 4 ahead of origin)

```
73eb1d6 feat(mobile): swipeable onboarding intro for first-launch
512e326 docs: round 2 progress log
29ecccf fix(deps): bump overrides to patched floors (multer, lodash, qs, dompurify)
c0e85c6 fix(db): make migration chain apply cleanly + RLS suite green on real PG
```
