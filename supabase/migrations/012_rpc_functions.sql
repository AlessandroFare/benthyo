-- Migration 012: Public API helper functions.
-- These are RPCs the mobile app and dashboard call via the Supabase
-- REST interface (`supabase.rpc('function_name', { args })`). They
-- bypass RLS for SELECT-only reads by virtue of being SECURITY DEFINER
-- and named with the convention benthyo_public_* so the API surface
-- is obvious.

-- The species seen at a given dive site, with stats.
-- Used by the site-detail screen.
CREATE OR REPLACE FUNCTION species_at_site(p_site_id UUID)
RETURNS TABLE (
  species_id        UUID,
  scientific_name   TEXT,
  common_name       TEXT,
  common_name_it    TEXT,
  common_name_es    TEXT,
  image_url         TEXT,
  conservation_status conservation_status,
  sighting_count    INTEGER,
  last_seen_at      TIMESTAMPTZ,
  avg_depth_m       NUMERIC(5, 1)
)
LANGUAGE sql STABLE AS $$
  SELECT
    s.id,
    s.scientific_name,
    s.common_name,
    s.common_name_it,
    s.common_name_es,
    s.image_url,
    s.conservation_status,
    stats.sighting_count,
    stats.last_seen_at,
    stats.avg_depth_m
  FROM species_dive_site_stats stats
  JOIN species s ON s.id = stats.species_id
  WHERE stats.dive_site_id = p_site_id
  ORDER BY stats.sighting_count DESC, stats.last_seen_at DESC;
$$;

-- The dive sites where a given species has been seen, ordered by count.
-- Used by the species-detail screen ("where to see it").
CREATE OR REPLACE FUNCTION sites_with_species(p_species_id UUID)
RETURNS TABLE (
  dive_site_id      UUID,
  name              TEXT,
  slug              TEXT,
  country_code      CHAR(2),
  region            TEXT,
  sighting_count    INTEGER,
  last_seen_at      TIMESTAMPTZ
)
LANGUAGE sql STABLE AS $$
  SELECT
    ds.id,
    ds.name,
    ds.slug,
    ds.country_code,
    ds.region,
    stats.sighting_count,
    stats.last_seen_at
  FROM species_dive_site_stats stats
  JOIN dive_sites ds ON ds.id = stats.dive_site_id
  WHERE stats.species_id = p_species_id
  ORDER BY stats.sighting_count DESC, stats.last_seen_at DESC;
$$;

-- Aggregate user stats (called from the profile screen).
CREATE OR REPLACE FUNCTION user_dive_stats(p_user_id UUID)
RETURNS JSON LANGUAGE sql STABLE AS $$
  SELECT json_build_object(
    'total_dives', u.total_dives,
    'total_species', (SELECT count(*) FROM user_life_list WHERE user_id = p_user_id),
    'total_sites', (
      SELECT count(DISTINCT dive_site_id) FROM dive_logs
      WHERE user_id = p_user_id AND dive_site_id IS NOT NULL
    ),
    'total_countries', (
      SELECT count(DISTINCT ds.country_code)
      FROM dive_logs dl JOIN dive_sites ds ON ds.id = dl.dive_site_id
      WHERE dl.user_id = p_user_id
    ),
    'deepest_dive_m', (
      SELECT max(max_depth_m) FROM dive_logs WHERE user_id = p_user_id
    ),
    'longest_dive_min', (
      SELECT max(duration_min) FROM dive_logs WHERE user_id = p_user_id
    ),
    'total_bottom_time_min', (
      SELECT coalesce(sum(duration_min), 0) FROM dive_logs WHERE user_id = p_user_id
    )
  )
  FROM users u WHERE u.id = p_user_id;
$$;

-- Operator analytics: top-level KPI card data.
-- Used by the B2B dashboard home page.
CREATE OR REPLACE FUNCTION operator_kpis(p_operator_id UUID, p_window_days INTEGER DEFAULT 30)
RETURNS JSON LANGUAGE sql STABLE AS $$
  WITH window_start AS (
    SELECT (now() - (p_window_days || ' days')::interval) AS ts
  )
  SELECT json_build_object(
    'total_customers', (
      SELECT count(DISTINCT dl.user_id)
      FROM dive_logs dl
      JOIN operator_dive_sites ods ON ods.dive_site_id = dl.dive_site_id
      WHERE ods.operator_id = p_operator_id
    ),
    'dives_in_window', (
      SELECT count(*)
      FROM dive_logs dl
      JOIN operator_dive_sites ods ON ods.dive_site_id = dl.dive_site_id
      WHERE ods.operator_id = p_operator_id
        AND dl.dive_date >= (SELECT ts FROM window_start)
    ),
    'active_sites', (
      SELECT count(*)
      FROM operator_dive_sites
      WHERE operator_id = p_operator_id
    ),
    'top_species', (
      SELECT json_agg(row_to_json(t))
      FROM (
        SELECT s.id AS species_id, s.common_name, s.scientific_name,
               count(*) AS sighting_count
        FROM sightings sg
        JOIN operator_dive_sites ods ON ods.dive_site_id = sg.dive_site_id
        JOIN species s ON s.id = sg.species_id
        WHERE ods.operator_id = p_operator_id
        GROUP BY s.id, s.common_name, s.scientific_name
        ORDER BY sighting_count DESC
        LIMIT 5
      ) t
    )
  );
$$;

-- Monthly dive count for an operator, for the last 12 months.
-- Used by the dashboard line chart.
CREATE OR REPLACE FUNCTION operator_dives_by_month(p_operator_id UUID)
RETURNS TABLE (
  month  DATE,
  count  INTEGER
) LANGUAGE sql STABLE AS $$
  SELECT
    date_trunc('month', dl.dive_date)::date AS month,
    count(*)::int AS count
  FROM dive_logs dl
  JOIN operator_dive_sites ods ON ods.dive_site_id = dl.dive_site_id
  WHERE ods.operator_id = p_operator_id
    AND dl.dive_date >= (now() - interval '12 months')
  GROUP BY date_trunc('month', dl.dive_date)
  ORDER BY month;
$$;
