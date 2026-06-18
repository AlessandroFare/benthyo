-- Migration 042: fix operator_today_roster().
--
-- Migration 041 referenced users.display_name, which does not exist (the
-- users table has full_name / username, see migration 003). Recreate the
-- RPC using full_name with a username fallback so it applies cleanly and
-- returns a usable guide label.

CREATE OR REPLACE FUNCTION operator_today_roster(
  p_operator_id UUID,
  p_date        DATE DEFAULT current_date
)
RETURNS TABLE (
  trip_id        UUID,
  trip_date      DATE,
  depart_at      TIMESTAMPTZ,
  site_name      TEXT,
  boat_name      TEXT,
  boat_capacity  SMALLINT,
  guide_name     TEXT,
  status         trip_schedule_status,
  booked_count   BIGINT,
  checked_in_count BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    t.id,
    t.trip_date,
    t.depart_at,
    COALESCE(ds.name, t.site_label) AS site_name,
    b.name AS boat_name,
    b.capacity AS boat_capacity,
    COALESCE(g.full_name, g.username) AS guide_name,
    t.status,
    COUNT(r.id) FILTER (WHERE r.status <> 'cancelled') AS booked_count,
    COUNT(r.id) FILTER (WHERE r.status IN ('checked_in','waiver_ok')) AS checked_in_count
  FROM operator_trip_schedule t
  LEFT JOIN dive_sites ds      ON ds.id = t.dive_site_id
  LEFT JOIN operator_boats b   ON b.id = t.boat_id
  LEFT JOIN users g            ON g.id = t.guide_id
  LEFT JOIN trip_roster_entries r ON r.trip_id = t.id
  WHERE t.operator_id = p_operator_id
    AND t.trip_date = p_date
    AND is_operator_member(p_operator_id)
  GROUP BY t.id, ds.name, b.name, b.capacity, g.full_name, g.username
  ORDER BY t.depart_at NULLS LAST, t.created_at;
$$;

GRANT EXECUTE ON FUNCTION operator_today_roster(UUID, DATE) TO authenticated;
