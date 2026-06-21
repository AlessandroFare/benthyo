-- Migration 049: Fix operator_customers() return-type mismatch.
--
-- users.username is CITEXT (003_users.sql) but operator_customers() declares
-- its RETURNS TABLE column as `username TEXT`. Postgres treats citext and text
-- as distinct types for composite/record structure checks, so every call that
-- returned at least one row failed at runtime with:
--   "structure of query does not match function result type"
-- (the function only "worked" before because the dev DB had no dive logs at
-- operator-linked sites, so RETURN QUERY produced zero rows).
--
-- Fix: cast username to text in the projection. Additive (CREATE OR REPLACE),
-- signature unchanged.

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
      u.username::TEXT AS username,
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

COMMENT ON FUNCTION operator_customers IS 'Paginated divers with dive logs at operator-linked sites (username cast to text; see migration 049).';
