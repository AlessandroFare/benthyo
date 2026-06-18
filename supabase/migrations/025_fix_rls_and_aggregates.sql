-- Migration 025: Fix RLS cycles, aggregate trigger permissions, and public logbook reads.
--
-- Problems fixed:
-- 1. maintain_sighting_aggregates() runs as the inserting user and hits RLS on
--    species_dive_site_stats / user_life_list (no write policies).
-- 2. trips <-> trip_members policies recurse when listing trips.
-- 3. Public logbook cannot read dive_logs / user_life_list for other users.
-- 4. Trip leaders could not insert trip_members / trip_sites rows.

-- ---------------------------------------------------------------------------
-- 1. SECURITY DEFINER aggregate trigger (bypasses RLS for maintenance writes)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION maintain_sighting_aggregates()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_species_id  UUID;
  v_site_id     UUID;
  v_user_id     UUID;
  v_avg_depth   NUMERIC(5, 1);
  v_count       INTEGER;
  v_last_seen   TIMESTAMPTZ;
  v_best_months INTEGER[];
  v_first_seen  TIMESTAMPTZ;
  v_total       INTEGER;
  v_sites       UUID[];
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_species_id := OLD.species_id;
    v_site_id    := OLD.dive_site_id;
    v_user_id    := OLD.user_id;
  ELSE
    v_species_id := NEW.species_id;
    v_site_id    := NEW.dive_site_id;
    v_user_id    := NEW.user_id;
  END IF;

  SELECT
    count(*),
    avg(depth_m),
    max(observed_at),
    array_agg(DISTINCT extract(month from observed_at)::int)
  INTO v_count, v_avg_depth, v_last_seen, v_best_months
  FROM sightings
  WHERE species_id = v_species_id AND dive_site_id = v_site_id;

  IF v_count = 0 THEN
    DELETE FROM species_dive_site_stats
    WHERE species_id = v_species_id AND dive_site_id = v_site_id;
  ELSE
    INSERT INTO species_dive_site_stats
      (species_id, dive_site_id, sighting_count, last_seen_at, avg_depth_m, best_season)
    VALUES
      (v_species_id, v_site_id, v_count, v_last_seen, v_avg_depth, coalesce(v_best_months, '{}'))
    ON CONFLICT (species_id, dive_site_id) DO UPDATE SET
      sighting_count = EXCLUDED.sighting_count,
      last_seen_at   = EXCLUDED.last_seen_at,
      avg_depth_m    = EXCLUDED.avg_depth_m,
      best_season    = EXCLUDED.best_season;
  END IF;

  IF TG_OP = 'DELETE' THEN
    SELECT count(*) INTO v_total FROM sightings
    WHERE user_id = v_user_id AND species_id = v_species_id;
    IF v_total = 0 THEN
      DELETE FROM user_life_list
      WHERE user_id = v_user_id AND species_id = v_species_id;
    ELSE
      SELECT min(observed_at), array_agg(DISTINCT dive_site_id)
        INTO v_first_seen, v_sites
      FROM sightings
      WHERE user_id = v_user_id AND species_id = v_species_id;
      UPDATE user_life_list SET
        first_seen_at = v_first_seen,
        total_sightings = v_total,
        site_ids = coalesce(v_sites, '{}')
      WHERE user_id = v_user_id AND species_id = v_species_id;
    END IF;
  ELSE
    SELECT min(observed_at), count(*), array_agg(DISTINCT dive_site_id)
      INTO v_first_seen, v_total, v_sites
    FROM sightings
    WHERE user_id = v_user_id AND species_id = v_species_id;
    INSERT INTO user_life_list
      (user_id, species_id, first_seen_at, total_sightings, site_ids)
    VALUES
      (v_user_id, v_species_id, v_first_seen, v_total, coalesce(v_sites, '{}'))
    ON CONFLICT (user_id, species_id) DO UPDATE SET
      first_seen_at = EXCLUDED.first_seen_at,
      total_sightings = EXCLUDED.total_sightings,
      site_ids = EXCLUDED.site_ids;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. Trip access helpers (break trips <-> trip_members RLS recursion)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION is_trip_leader(p_trip_id UUID, p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM trips t
    WHERE t.id = p_trip_id AND t.leader_id = p_user_id
  );
$$;

CREATE OR REPLACE FUNCTION is_trip_member(p_trip_id UUID, p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM trip_members tm
    WHERE tm.trip_id = p_trip_id AND tm.user_id = p_user_id
  );
$$;

GRANT EXECUTE ON FUNCTION is_trip_leader(UUID, UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION is_trip_member(UUID, UUID) TO anon, authenticated;

DROP POLICY IF EXISTS trips_select ON trips;
CREATE POLICY trips_select ON trips
  FOR SELECT USING (
    leader_id = auth.uid()
    OR is_trip_member(id, auth.uid())
  );

DROP POLICY IF EXISTS trip_members_select ON trip_members;
CREATE POLICY trip_members_select ON trip_members
  FOR SELECT USING (
    user_id = auth.uid()
    OR is_trip_leader(trip_id, auth.uid())
  );

DROP POLICY IF EXISTS trip_sites_select ON trip_sites;
CREATE POLICY trip_sites_select ON trip_sites
  FOR SELECT USING (
    is_trip_leader(trip_id, auth.uid())
    OR is_trip_member(trip_id, auth.uid())
  );

DROP POLICY IF EXISTS trip_members_insert ON trip_members;
CREATE POLICY trip_members_insert ON trip_members
  FOR INSERT WITH CHECK (
    is_trip_leader(trip_id, auth.uid())
    OR user_id = auth.uid()
  );

DROP POLICY IF EXISTS trip_sites_insert ON trip_sites;
CREATE POLICY trip_sites_insert ON trip_sites
  FOR INSERT WITH CHECK (is_trip_leader(trip_id, auth.uid()));

-- ---------------------------------------------------------------------------
-- 3. Public logbook reads
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS dive_logs_select_public_logbook ON dive_logs;
CREATE POLICY dive_logs_select_public_logbook ON dive_logs
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM users u
      WHERE u.id = dive_logs.user_id AND u.public_logbook = true
    )
  );

DROP POLICY IF EXISTS user_life_list_select_public_logbook ON user_life_list;
CREATE POLICY user_life_list_select_public_logbook ON user_life_list
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM users u
      WHERE u.id = user_life_list.user_id AND u.public_logbook = true
    )
  );

-- ---------------------------------------------------------------------------
-- 4. operator_users: break self-referential SELECT policy
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION shares_operator_with(
  p_operator_id UUID,
  p_user_id UUID DEFAULT auth.uid()
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM operator_users ou
    WHERE ou.operator_id = p_operator_id AND ou.user_id = p_user_id
  );
$$;

GRANT EXECUTE ON FUNCTION shares_operator_with(UUID, UUID) TO anon, authenticated;

DROP POLICY IF EXISTS operator_users_select_member ON operator_users;
DROP POLICY IF EXISTS operator_users_select_own ON operator_users;
DROP POLICY IF EXISTS operator_users_select_coworkers ON operator_users;

CREATE POLICY operator_users_select_own ON operator_users
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY operator_users_select_coworkers ON operator_users
  FOR SELECT USING (shares_operator_with(operator_id, auth.uid()));
