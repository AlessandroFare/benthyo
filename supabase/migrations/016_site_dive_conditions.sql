-- Migration 016: Aggregated dive conditions per site (current, visibility).
-- Powers the dive exploration map preview and site detail cards.

CREATE OR REPLACE FUNCTION site_dive_conditions(p_site_id UUID)
RETURNS JSON
LANGUAGE sql
STABLE
AS $$
  WITH logs AS (
    SELECT visibility_m, current_strength
    FROM dive_logs
    WHERE dive_site_id = p_site_id
  ),
  current_mode AS (
    SELECT current_strength
    FROM logs
    WHERE current_strength IS NOT NULL
    GROUP BY current_strength
    ORDER BY count(*) DESC
    LIMIT 1
  )
  SELECT json_build_object(
    'log_count', (SELECT count(*) FROM logs),
    'avg_visibility_m', (
      SELECT round(avg(visibility_m)::numeric, 1)
      FROM logs
      WHERE visibility_m IS NOT NULL
    ),
    'typical_current', (SELECT current_strength::text FROM current_mode),
    'current_counts', COALESCE(
      (
        SELECT json_object_agg(current_strength::text, cnt)
        FROM (
          SELECT current_strength, count(*) AS cnt
          FROM logs
          WHERE current_strength IS NOT NULL
          GROUP BY current_strength
        ) grouped
      ),
      '{}'::json
    )
  );
$$;

GRANT EXECUTE ON FUNCTION site_dive_conditions(UUID) TO anon, authenticated;
