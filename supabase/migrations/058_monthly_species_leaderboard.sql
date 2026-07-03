-- Migration 058: Monthly species leaderboard RPC
--
-- Exposes `monthly_species_leaderboard()` — a zero-infra social challenge
-- built entirely on the existing `sightings` and `user_life_list` tables.
--
-- Leaderboard ranking:
--   1. Total distinct species observed this calendar month (main score).
--   2. New-to-life-list species this month (tiebreaker / secondary badge).
--
-- The function is SECURITY DEFINER so it can read the `users` public
-- profile columns (username, avatar_url) without the caller needing
-- direct SELECT on the users table.

CREATE OR REPLACE FUNCTION monthly_species_leaderboard(
  p_limit INT DEFAULT 50
)
RETURNS TABLE(
  rank            INT,
  user_id         UUID,
  username        TEXT,
  avatar_url      TEXT,
  species_count   INT,
  new_to_lifelist INT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  WITH month_sightings AS (
    -- All user sightings in the current calendar month.
    SELECT
      s.user_id,
      s.species_id
    FROM sightings s
    WHERE s.observed_at >= date_trunc('month', now())
      AND s.source = 'user'
  ),
  agg AS (
    SELECT
      ms.user_id,
      COUNT(DISTINCT ms.species_id)::INT                          AS species_count,
      -- A species is "new to life list" when the user's life-list entry for
      -- it was created this month (i.e. first ever sighting was this month).
      COUNT(DISTINCT ms.species_id) FILTER (
        WHERE EXISTS (
          SELECT 1 FROM user_life_list ll
          WHERE ll.user_id     = ms.user_id
            AND ll.species_id  = ms.species_id
            AND ll.first_seen_at >= date_trunc('month', now())
        )
      )::INT AS new_to_lifelist
    FROM month_sightings ms
    GROUP BY ms.user_id
  )
  SELECT
    ROW_NUMBER() OVER (ORDER BY agg.species_count DESC, agg.new_to_lifelist DESC)::INT AS rank,
    agg.user_id,
    u.username,
    u.avatar_url,
    agg.species_count,
    agg.new_to_lifelist
  FROM agg
  JOIN users u ON u.id = agg.user_id
  ORDER BY agg.species_count DESC, agg.new_to_lifelist DESC
  LIMIT p_limit
$$;

COMMENT ON FUNCTION monthly_species_leaderboard(INT) IS
  'Returns the top divers ranked by distinct species observed in the current '
  'calendar month. SECURITY DEFINER — safe to call from authenticated role.';

GRANT EXECUTE ON FUNCTION monthly_species_leaderboard(INT) TO authenticated, service_role;
