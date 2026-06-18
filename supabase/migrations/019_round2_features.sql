-- Migration 019: Round 2 product features — data moat, retention, B2B CRM foundation.

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
CREATE TYPE gear_type AS ENUM (
  'bcd', 'regulator', 'wetsuit', 'computer', 'fins', 'mask', 'tank', 'other'
);

CREATE TYPE correction_status AS ENUM (
  'open', 'accepted', 'contested', 'rejected'
);

CREATE TYPE trip_member_role AS ENUM ('leader', 'member', 'guest');

-- ---------------------------------------------------------------------------
-- Dive log profile samples (UDDF depth/time series)
-- ---------------------------------------------------------------------------
ALTER TABLE dive_logs
  ADD COLUMN IF NOT EXISTS profile_samples JSONB;

COMMENT ON COLUMN dive_logs.profile_samples IS
  'Optional depth/time samples from dive computer import [{t_sec, depth_m}]';

-- ---------------------------------------------------------------------------
-- Gear inventory (diver-side maintenance tracking)
-- ---------------------------------------------------------------------------
CREATE TABLE gear_items (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                 UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  gear_type               gear_type NOT NULL DEFAULT 'other',
  name                    TEXT NOT NULL,
  brand                   TEXT,
  serial_number           TEXT,
  purchase_date           DATE,
  last_service_date       DATE,
  service_interval_months INTEGER CHECK (service_interval_months IS NULL OR service_interval_months > 0),
  dives_since_service     INTEGER NOT NULL DEFAULT 0 CHECK (dives_since_service >= 0),
  notes                   TEXT,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_gear_items_user ON gear_items (user_id);

CREATE TRIGGER trg_gear_items_updated_at
  BEFORE UPDATE ON gear_items
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------------------
-- Group trips (B2B coordination)
-- ---------------------------------------------------------------------------
CREATE TABLE trips (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  leader_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  operator_id UUID REFERENCES operators(id) ON DELETE SET NULL,
  name        TEXT NOT NULL,
  start_date  DATE NOT NULL,
  end_date    DATE NOT NULL,
  region      TEXT,
  notes       TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT trips_date_order CHECK (end_date >= start_date)
);

CREATE TABLE trip_members (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id    UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role       trip_member_role NOT NULL DEFAULT 'member',
  waiver_signed BOOLEAN NOT NULL DEFAULT false,
  medical_complete BOOLEAN NOT NULL DEFAULT false,
  joined_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (trip_id, user_id)
);

CREATE TABLE trip_sites (
  trip_id      UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  dive_site_id UUID NOT NULL REFERENCES dive_sites(id) ON DELETE CASCADE,
  sort_order   INTEGER NOT NULL DEFAULT 0,
  planned_date DATE,
  PRIMARY KEY (trip_id, dive_site_id)
);

CREATE INDEX idx_trips_leader ON trips (leader_id, start_date DESC);
CREATE INDEX idx_trip_members_user ON trip_members (user_id);

CREATE TRIGGER trg_trips_updated_at
  BEFORE UPDATE ON trips
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------------------
-- Site reviews (pre-dive prep card data)
-- ---------------------------------------------------------------------------
CREATE TABLE site_reviews (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  dive_site_id UUID NOT NULL REFERENCES dive_sites(id) ON DELETE CASCADE,
  dive_log_id  UUID REFERENCES dive_logs(id) ON DELETE SET NULL,
  rating       SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  visibility_m NUMERIC(4, 1),
  current_note TEXT,
  body         TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, dive_site_id, dive_log_id)
);

CREATE INDEX idx_site_reviews_site ON site_reviews (dive_site_id, created_at DESC);

CREATE TRIGGER trg_site_reviews_updated_at
  BEFORE UPDATE ON site_reviews
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------------------
-- Species sighting corrections (data quality loop)
-- ---------------------------------------------------------------------------
CREATE TABLE sighting_corrections (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sighting_id        UUID NOT NULL REFERENCES sightings(id) ON DELETE CASCADE,
  reporter_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  proposed_species_id UUID NOT NULL REFERENCES species(id) ON DELETE RESTRICT,
  reason             TEXT NOT NULL,
  status             correction_status NOT NULL DEFAULT 'open',
  resolver_id        UUID REFERENCES users(id) ON DELETE SET NULL,
  resolved_at        TIMESTAMPTZ,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_sighting_corrections_sighting ON sighting_corrections (sighting_id, created_at DESC);
CREATE INDEX idx_sighting_corrections_open ON sighting_corrections (status) WHERE status = 'open';

CREATE TRIGGER trg_sighting_corrections_updated_at
  BEFORE UPDATE ON sighting_corrections
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Public correction log on sightings
ALTER TABLE sightings
  ADD COLUMN IF NOT EXISTS correction_log JSONB NOT NULL DEFAULT '[]';

COMMENT ON COLUMN sightings.correction_log IS
  'Append-only audit: [{from_species_id, to_species_id, by, at, reason}]';

-- ---------------------------------------------------------------------------
-- iNaturalist identify cache (rate-limit protection)
-- ---------------------------------------------------------------------------
CREATE TABLE inat_identify_cache (
  image_hash   TEXT PRIMARY KEY,
  image_url    TEXT NOT NULL,
  results      JSONB NOT NULL,
  model_version TEXT NOT NULL DEFAULT 'inat-v1',
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at   TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '30 days')
);

CREATE INDEX idx_inat_cache_expires ON inat_identify_cache (expires_at);

-- ---------------------------------------------------------------------------
-- Public profile / logbook visibility
-- ---------------------------------------------------------------------------
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS public_logbook BOOLEAN NOT NULL DEFAULT true;

COMMENT ON COLUMN users.public_logbook IS
  'When true, public logbook URL shows dive count and recent dives.';

-- ---------------------------------------------------------------------------
-- RPC: site public data card (embed widget)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION site_public_card(p_site_id UUID)
RETURNS JSONB
LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'site_id', ds.id,
    'name', ds.name,
    'slug', ds.slug,
    'region', ds.region,
    'country_code', ds.country_code,
    'depth_max', ds.depth_max,
    'difficulty', ds.difficulty,
    'total_dives', (
      SELECT count(*)::integer FROM dive_logs dl WHERE dl.dive_site_id = ds.id
    ),
    'total_species', (
      SELECT count(DISTINCT s.species_id)::integer
      FROM sightings s WHERE s.dive_site_id = ds.id
    ),
    'verified_sightings', (
      SELECT count(*)::integer FROM sightings s
      WHERE s.dive_site_id = ds.id AND s.verified_by IS NOT NULL
    ),
    'last_dive_at', (
      SELECT max(dl.dive_date) FROM dive_logs dl WHERE dl.dive_site_id = ds.id
    ),
    'avg_depth_m', (
      SELECT round(avg(dl.max_depth_m)::numeric, 1)
      FROM dive_logs dl WHERE dl.dive_site_id = ds.id
    ),
    'avg_visibility_m', (
      SELECT round(avg(sr.visibility_m)::numeric, 1)
      FROM site_reviews sr WHERE sr.dive_site_id = ds.id AND sr.visibility_m IS NOT NULL
    )
  )
  FROM dive_sites ds
  WHERE ds.id = p_site_id;
$$;

-- ---------------------------------------------------------------------------
-- RPC: pre-dive prep card payload
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION site_prep_card(p_site_id UUID)
RETURNS JSONB
LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'site', site_public_card(p_site_id),
    'recent_reviews', COALESCE((
      SELECT jsonb_agg(row_to_json(r) ORDER BY r.created_at DESC)
      FROM (
        SELECT sr.rating, sr.visibility_m, sr.current_note, sr.body, sr.created_at,
               u.username, u.full_name
        FROM site_reviews sr
        JOIN users u ON u.id = sr.user_id
        WHERE sr.dive_site_id = p_site_id
        ORDER BY sr.created_at DESC
        LIMIT 5
      ) r
    ), '[]'::jsonb),
    'recent_species', COALESCE((
      SELECT jsonb_agg(row_to_json(sp) ORDER BY sp.observed_at DESC)
      FROM (
        SELECT sp2.common_name, sp2.scientific_name, s.observed_at
        FROM sightings s
        JOIN species sp2 ON sp2.id = s.species_id
        WHERE s.dive_site_id = p_site_id
        ORDER BY s.observed_at DESC
        LIMIT 8
      ) sp
    ), '[]'::jsonb),
    'conditions', site_dive_conditions(p_site_id)
  );
$$;

-- ---------------------------------------------------------------------------
-- RPC: diver verification level (data quality signal)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION diver_verification_level(p_user_id UUID)
RETURNS JSONB
LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'level', CASE
      WHEN u.total_dives >= 200
        AND NOT EXISTS (
          SELECT 1 FROM sighting_corrections sc
          JOIN sightings s ON s.id = sc.sighting_id
          WHERE s.user_id = p_user_id
            AND sc.status = 'accepted'
            AND sc.created_at > now() - INTERVAL '12 months'
        )
      THEN 3
      WHEN u.total_dives >= 50 THEN 2
      ELSE 1
    END,
    'total_dives', u.total_dives,
    'verified_sightings', (
      SELECT count(*)::integer FROM sightings s
      WHERE s.user_id = p_user_id AND s.verified_by IS NOT NULL
    ),
    'accepted_corrections_12m', (
      SELECT count(*)::integer FROM sighting_corrections sc
      JOIN sightings s ON s.id = sc.sighting_id
      WHERE s.user_id = p_user_id
        AND sc.status = 'accepted'
        AND sc.created_at > now() - INTERVAL '12 months'
    )
  )
  FROM users u
  WHERE u.id = p_user_id;
$$;

GRANT EXECUTE ON FUNCTION site_public_card(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION site_prep_card(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION diver_verification_level(UUID) TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
ALTER TABLE gear_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE trips ENABLE ROW LEVEL SECURITY;
ALTER TABLE trip_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE trip_sites ENABLE ROW LEVEL SECURITY;
ALTER TABLE site_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE sighting_corrections ENABLE ROW LEVEL SECURITY;
ALTER TABLE inat_identify_cache ENABLE ROW LEVEL SECURITY;

CREATE POLICY gear_items_own ON gear_items
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE POLICY trips_select ON trips
  FOR SELECT USING (
    leader_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM trip_members tm
      WHERE tm.trip_id = trips.id AND tm.user_id = auth.uid()
    )
  );

CREATE POLICY trips_insert ON trips
  FOR INSERT WITH CHECK (leader_id = auth.uid());

CREATE POLICY trips_update ON trips
  FOR UPDATE USING (leader_id = auth.uid());

CREATE POLICY trip_members_select ON trip_members
  FOR SELECT USING (
    user_id = auth.uid()
    OR EXISTS (SELECT 1 FROM trips t WHERE t.id = trip_id AND t.leader_id = auth.uid())
  );

CREATE POLICY trip_sites_select ON trip_sites
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM trips t
      WHERE t.id = trip_sites.trip_id
        AND (t.leader_id = auth.uid() OR EXISTS (
          SELECT 1 FROM trip_members tm
          WHERE tm.trip_id = t.id AND tm.user_id = auth.uid()
        ))
    )
  );

CREATE POLICY site_reviews_public_read ON site_reviews
  FOR SELECT USING (true);

CREATE POLICY site_reviews_insert ON site_reviews
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY site_reviews_update_own ON site_reviews
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY sighting_corrections_read ON sighting_corrections
  FOR SELECT USING (true);

CREATE POLICY sighting_corrections_insert ON sighting_corrections
  FOR INSERT WITH CHECK (auth.uid() = reporter_id);

-- Service role manages iNat cache; no client access
CREATE POLICY inat_cache_deny ON inat_identify_cache
  FOR ALL USING (false);
