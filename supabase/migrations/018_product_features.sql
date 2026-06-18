-- Migration 018: Product features — buddy finder, seasonal forecast, digital waivers.

-- Buddy finder opt-in on public profile.
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS buddy_finder_visible BOOLEAN NOT NULL DEFAULT true;

COMMENT ON COLUMN users.buddy_finder_visible IS
  'When true, user may appear in recent-divers lists at dive sites.';

-- Digital liability waivers for operators (B2B).
CREATE TABLE operator_waivers (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  operator_id  UUID NOT NULL REFERENCES operators(id) ON DELETE CASCADE,
  title        TEXT NOT NULL DEFAULT 'Liability waiver',
  body         TEXT NOT NULL,
  version      INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
  is_active    BOOLEAN NOT NULL DEFAULT true,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_operator_waivers_active
  ON operator_waivers (operator_id)
  WHERE is_active = true;

CREATE TRIGGER trg_operator_waivers_updated_at
  BEFORE UPDATE ON operator_waivers
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE waiver_signatures (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  waiver_id    UUID NOT NULL REFERENCES operator_waivers(id) ON DELETE CASCADE,
  operator_id  UUID NOT NULL REFERENCES operators(id) ON DELETE CASCADE,
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  signer_name  TEXT NOT NULL,
  signed_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (waiver_id, user_id)
);

CREATE INDEX idx_waiver_signatures_operator ON waiver_signatures (operator_id, signed_at DESC);

-- Recent divers at a site (buddy finder).
CREATE OR REPLACE FUNCTION recent_divers_at_site(
  p_site_id UUID,
  p_days INTEGER DEFAULT 90
)
RETURNS TABLE (
  user_id        UUID,
  username       TEXT,
  full_name      TEXT,
  avatar_url     TEXT,
  cert_level     cert_level,
  last_dive_date DATE,
  dive_count     INTEGER
)
LANGUAGE sql STABLE AS $$
  SELECT
    u.id,
    u.username::text,
    u.full_name,
    u.avatar_url,
    u.certification_level,
    max(dl.dive_date) AS last_dive_date,
    count(*)::integer AS dive_count
  FROM dive_logs dl
  JOIN users u ON u.id = dl.user_id
  WHERE dl.dive_site_id = p_site_id
    AND dl.dive_date >= (CURRENT_DATE - p_days)
    AND u.buddy_finder_visible = true
  GROUP BY u.id, u.username, u.full_name, u.avatar_url, u.certification_level
  ORDER BY last_dive_date DESC
  LIMIT 20;
$$;

-- Seasonal species forecast (best months from real sightings).
CREATE OR REPLACE FUNCTION species_seasonal_forecast(
  p_species_id UUID,
  p_site_id UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE sql STABLE AS $$
  WITH monthly AS (
    SELECT
      extract(month FROM s.observed_at)::int AS month,
      count(*)::int AS sightings
    FROM sightings s
    WHERE s.species_id = p_species_id
      AND (p_site_id IS NULL OR s.dive_site_id = p_site_id)
    GROUP BY 1
  ),
  best AS (
    SELECT coalesce(stats.best_season, '{}'::int[]) AS months
    FROM species_dive_site_stats stats
    WHERE stats.species_id = p_species_id
      AND (p_site_id IS NULL OR stats.dive_site_id = p_site_id)
    LIMIT 1
  )
  SELECT json_build_object(
    'species_id', p_species_id,
    'site_id', p_site_id,
    'best_months', coalesce((SELECT months FROM best), '{}'::int[]),
    'monthly_counts', coalesce(
      (SELECT json_object_agg(month::text, sightings) FROM monthly),
      '{}'::json
    ),
    'total_sightings', coalesce((SELECT sum(sightings) FROM monthly), 0)
  );
$$;

GRANT EXECUTE ON FUNCTION recent_divers_at_site(UUID, INTEGER) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION species_seasonal_forecast(UUID, UUID) TO anon, authenticated;

-- RLS for waivers.
ALTER TABLE operator_waivers ENABLE ROW LEVEL SECURITY;
ALTER TABLE waiver_signatures ENABLE ROW LEVEL SECURITY;

CREATE POLICY operator_waivers_public_read ON operator_waivers
  FOR SELECT USING (is_active = true);

CREATE POLICY operator_waivers_staff_write ON operator_waivers
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM operator_users ou
      WHERE ou.operator_id = operator_waivers.operator_id
        AND ou.user_id = auth.uid()
        AND ou.role IN ('owner', 'admin')
    )
  );

CREATE POLICY waiver_signatures_insert_own ON waiver_signatures
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY waiver_signatures_read_own ON waiver_signatures
  FOR SELECT USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM operator_users ou
      WHERE ou.operator_id = waiver_signatures.operator_id
        AND ou.user_id = auth.uid()
    )
  );
