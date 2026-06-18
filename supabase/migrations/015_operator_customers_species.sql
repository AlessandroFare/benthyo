-- Migration 015: Operator customer directory and species rankings for B2B dashboard.

CREATE OR REPLACE FUNCTION operator_customers(
  p_operator_id UUID,
  p_limit INTEGER DEFAULT 20,
  p_offset INTEGER DEFAULT 0,
  p_search TEXT DEFAULT NULL
)
RETURNS TABLE (
  user_id UUID,
  username TEXT,
  full_name TEXT,
  certification_level cert_level,
  operator_dive_count BIGINT,
  last_dive_at DATE,
  total_count BIGINT
)
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_operator_member(p_operator_id) THEN
    RAISE EXCEPTION 'Not authorized for operator %', p_operator_id;
  END IF;

  RETURN QUERY
  WITH aggregated AS (
    SELECT
      dl.user_id,
      u.username,
      u.full_name,
      u.certification_level,
      COUNT(*)::BIGINT AS operator_dive_count,
      MAX(dl.dive_date) AS last_dive_at
    FROM dive_logs dl
    JOIN operator_dive_sites ods ON ods.dive_site_id = dl.dive_site_id
    JOIN users u ON u.id = dl.user_id
    WHERE ods.operator_id = p_operator_id
      AND (
        p_search IS NULL
        OR p_search = ''
        OR u.username ILIKE '%' || p_search || '%'
        OR u.full_name ILIKE '%' || p_search || '%'
      )
    GROUP BY dl.user_id, u.username, u.full_name, u.certification_level
  ),
  counted AS (
    SELECT COUNT(*)::BIGINT AS cnt FROM aggregated
  )
  SELECT
    a.user_id,
    a.username,
    a.full_name,
    a.certification_level,
    a.operator_dive_count,
    a.last_dive_at,
    c.cnt AS total_count
  FROM aggregated a
  CROSS JOIN counted c
  ORDER BY a.last_dive_at DESC NULLS LAST
  LIMIT p_limit OFFSET p_offset;
END;
$$;

CREATE OR REPLACE FUNCTION operator_species_ranked(
  p_operator_id UUID,
  p_limit INTEGER DEFAULT 20,
  p_offset INTEGER DEFAULT 0,
  p_search TEXT DEFAULT NULL
)
RETURNS TABLE (
  species_id UUID,
  scientific_name TEXT,
  common_name TEXT,
  family TEXT,
  conservation_status conservation_status,
  image_url TEXT,
  sighting_count BIGINT,
  site_count BIGINT,
  last_seen_at TIMESTAMPTZ,
  total_count BIGINT
)
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_operator_member(p_operator_id) THEN
    RAISE EXCEPTION 'Not authorized for operator %', p_operator_id;
  END IF;

  RETURN QUERY
  WITH aggregated AS (
    SELECT
      s.id AS species_id,
      s.scientific_name,
      s.common_name,
      s.family,
      s.conservation_status,
      s.image_url,
      SUM(stats.sighting_count)::BIGINT AS sighting_count,
      COUNT(DISTINCT stats.dive_site_id)::BIGINT AS site_count,
      MAX(stats.last_seen_at) AS last_seen_at
    FROM species_dive_site_stats stats
    JOIN operator_dive_sites ods ON ods.dive_site_id = stats.dive_site_id
    JOIN species s ON s.id = stats.species_id
    WHERE ods.operator_id = p_operator_id
      AND (
        p_search IS NULL
        OR p_search = ''
        OR s.scientific_name ILIKE '%' || p_search || '%'
        OR s.common_name ILIKE '%' || p_search || '%'
        OR s.family ILIKE '%' || p_search || '%'
      )
    GROUP BY
      s.id,
      s.scientific_name,
      s.common_name,
      s.family,
      s.conservation_status,
      s.image_url
  ),
  counted AS (
    SELECT COUNT(*)::BIGINT AS cnt FROM aggregated
  )
  SELECT
    a.species_id,
    a.scientific_name,
    a.common_name,
    a.family,
    a.conservation_status,
    a.image_url,
    a.sighting_count,
    a.site_count,
    a.last_seen_at,
    c.cnt AS total_count
  FROM aggregated a
  CROSS JOIN counted c
  ORDER BY a.sighting_count DESC, a.last_seen_at DESC NULLS LAST
  LIMIT p_limit OFFSET p_offset;
END;
$$;

COMMENT ON FUNCTION operator_customers IS 'Paginated divers with dive logs at operator-linked sites.';
COMMENT ON FUNCTION operator_species_ranked IS 'Paginated species ranked by sightings at operator sites.';
