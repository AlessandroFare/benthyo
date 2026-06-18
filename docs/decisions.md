# Architecture Decision Records

## ADR-001: Supabase Postgres as primary database

**Status:** Accepted

**Context:** OceanLog needs geospatial queries (PostGIS), row-level security, real-time subscriptions, and managed auth.

**Decision:** Use Supabase-hosted Postgres with PostGIS extension. Migrations live in `supabase/migrations/`.

**Consequences:** Tight coupling to Supabase auth and RLS. Spatial queries are efficient via GIST indexes. Edge Functions deploy alongside the database.

---

## ADR-002: Shared types package

**Status:** Accepted

**Context:** The API, dashboard, ETL scripts, and Edge Functions all need consistent entity shapes and API DTOs.

**Decision:** Publish `@oceanlog/types` as a workspace package with enums, entities, pagination helpers, and Darwin Core types.

**Consequences:** Single source of truth for TypeScript types. Requires build step before dependent packages compile.

---

## ADR-003: Trigger-maintained aggregates

**Status:** Accepted

**Context:** Mobile app needs "species at site" and "my life list" in single-query reads without expensive JOINs.

**Decision:** Maintain `species_dive_site_stats` and `user_life_list` via an AFTER trigger on `sightings`.

**Consequences:** Write amplification on sighting inserts/updates/deletes. Reads are O(1) per user or site.

---

## ADR-004: Idempotent ETL with provenance

**Status:** Accepted

**Context:** GBIF, OBIS, and WoRMS pipelines run on schedules and must not create duplicate records.

**Decision:** Sightings use `(source, external_id)` unique constraint. Species upsert on `scientific_name`. Dive sites upsert on `slug`.

**Consequences:** User-submitted sightings have `source='user'` and NULL `external_id`, so the constraint does not apply to them.

---

## ADR-005: Cloudflare R2 for photo storage

**Status:** Accepted

**Context:** Sighting photos can be large and numerous. Supabase Storage has egress costs at scale.

**Decision:** Store photos in Cloudflare R2 with presigned upload URLs from the NestJS API.

**Consequences:** Additional service to configure. Zero egress fees within Cloudflare network.

---

## ADR-006: Darwin Core export via Edge Function

**Status:** Accepted

**Context:** Research partners need standards-compliant biodiversity data export (GBIF, OBIS compatible).

**Decision:** Implement `darwin-core-export` Edge Function mapping verified sightings to DwC Occurrence records with CC-BY 4.0 license.

**Consequences:** Export quality depends on expert verification workflow. Only `user` and `manual` source sightings are exported.

---

## ADR-007: Badge awarding on sighting insert

**Status:** Accepted

**Context:** Gamification badges should be awarded automatically when users hit milestones.

**Decision:** Database webhook on `sightings` INSERT triggers `on-sighting-created` Edge Function, which evaluates badge criteria and upserts `user_badges`.

**Consequences:** Badge checks run asynchronously. Criteria types: dive_count, species_count, site_count, region, manual.

---

## ADR-008: pnpm workspace + Melos

**Status:** Accepted

**Context:** Monorepo contains TypeScript (API, dashboard, packages, ETL) and Flutter (mobile).

**Decision:** pnpm workspaces for Node packages; Melos for Flutter multi-package management.

**Consequences:** Two package managers in one repo. CI runs both `pnpm` and `melos` jobs.

---

## ADR-009: Mediterranean-first seed data

**Status:** Accepted

**Context:** Launch market is Mediterranean dive tourism (Italy, Malta, Croatia, Greece, Spain, France).

**Decision:** Seed 50 real Mediterranean dive sites with GPS coordinates, 200 marine species with EN/IT/ES names, and 5 Italian dive center operators.

**Consequences:** Non-Mediterranean expansion requires additional seed/ETL coverage.

---

## ADR-010: Scheduled ETL via GitHub Actions

**Status:** Accepted

**Context:** External APIs (GBIF, OBIS, WoRMS, Overpass) should be polled on a schedule without dedicated infrastructure.

**Decision:** One workflow per ETL source with cron schedules and `workflow_dispatch` for manual runs.

**Consequences:** GitHub Actions minutes consumption. Secrets must be configured per repository.

---

## ADR-011: Operator dashboard routes under `/operators/me/*`

**Status:** Accepted

**Context:** The B2B dashboard must resolve the active operator from the JWT without storing operator IDs in local storage.

**Decision:** Expose dashboard KPIs, charts, activity, and analytics bundles at `/operators/me/*`, resolving membership server-side.

**Consequences:** Route ordering in NestJS must declare `me/*` paths before `:slug` and `:operatorId` param routes.

---

## ADR-012: Health probes outside API prefix

**Status:** Accepted

**Context:** Railway and container orchestrators expect lightweight liveness/readiness endpoints.

**Decision:** Register `/health` and `/ready` on the NestJS root (outside `/api/v1`).

**Consequences:** Load balancers can probe health without auth; readiness checks Supabase connectivity.

---

## ADR-013: Dive exploration map layers

**Status:** Accepted

**Context:** A generic OpenStreetMap view is insufficient for dive site exploration. Divers need depth context (isolines), nautical marks, and aggregated current reports from logs.

**Decision:** Use flutter_map with selectable basemaps (Ocean, EMODnet bathymetry, satellite, standard PMTiles/OSM) and togglable overlays (EMODnet depth isolines, OpenSeaMap seamarks). Show typical current strength on markers and in the site preview sheet via a `site_dive_conditions` RPC aggregating dive logs.

**Consequences:** Third-party tile attribution is required. Live oceanographic current models are out of scope for Phase 1; diver-reported conditions are the source of truth until Copernicus/GFS integration is justified.

---

## ADR-014: Species photo ID via iNaturalist, not social scraping

**Status:** Accepted

**Context:** Feedback suggested scraping Instagram for marine life recognition. That raises ToS, copyright, and privacy issues and produces unreliable taxonomy.

**Decision:** Identify species from user photos through the existing NestJS → iNaturalist proxy (`POST /species/identify`). Enrich the catalog via GBIF, OBIS, WoRMS ETL and user sightings—not unauthorized social media scraping.

**Consequences:** Photo ID requires auth and a public image URL (R2 presign upload). Species not yet in the catalog show iNaturalist matches with a manual sighting fallback.
