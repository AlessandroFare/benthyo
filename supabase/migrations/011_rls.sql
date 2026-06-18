-- Migration 011: Row-Level Security policies.
-- RLS is enforced by Postgres before any SELECT/INSERT/UPDATE/DELETE
-- returns rows. The application connects with the anon JWT, and policies
-- authorize rows based on auth.uid() and the user's role in
-- operator_users.
--
-- Service-role key bypasses RLS by design; it is only used server-side
-- in NestJS and Edge Functions for trusted operations (cron jobs,
-- email triggers, etc.).

-- Enable RLS on every table.
ALTER TABLE users                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE dive_sites              ENABLE ROW LEVEL SECURITY;
ALTER TABLE species                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE dive_logs               ENABLE ROW LEVEL SECURITY;
ALTER TABLE sightings               ENABLE ROW LEVEL SECURITY;
ALTER TABLE operators               ENABLE ROW LEVEL SECURITY;
ALTER TABLE operator_users          ENABLE ROW LEVEL SECURITY;
ALTER TABLE operator_dive_sites     ENABLE ROW LEVEL SECURITY;
ALTER TABLE species_dive_site_stats  ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_life_list           ENABLE ROW LEVEL SECURITY;
ALTER TABLE badges                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_badges             ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- users: own profile is read+write; others are read-only.
-- ============================================================
CREATE POLICY users_select_public ON users
  FOR SELECT USING (true);

CREATE POLICY users_update_own ON users
  FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

CREATE POLICY users_insert_self ON users
  FOR INSERT WITH CHECK (auth.uid() = id);

-- ============================================================
-- dive_sites: public read; authenticated user can create;
-- only admins or original creator can update.
-- ============================================================
CREATE POLICY dive_sites_select_public ON dive_sites
  FOR SELECT USING (true);

CREATE POLICY dive_sites_insert_auth ON dive_sites
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY dive_sites_update_creator ON dive_sites
  FOR UPDATE USING (created_by = auth.uid()) WITH CHECK (created_by = auth.uid());

CREATE POLICY dive_sites_delete_creator ON dive_sites
  FOR DELETE USING (created_by = auth.uid());

-- ============================================================
-- species: public read; only service role can insert/update
-- (species come from the WoRMS ETL, not from end users).
-- ============================================================
CREATE POLICY species_select_public ON species
  FOR SELECT USING (true);

-- ============================================================
-- dive_logs: only the owner can read+write+delete.
-- ============================================================
CREATE POLICY dive_logs_select_own ON dive_logs
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY dive_logs_insert_own ON dive_logs
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY dive_logs_update_own ON dive_logs
  FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE POLICY dive_logs_delete_own ON dive_logs
  FOR DELETE USING (auth.uid() = user_id);

-- ============================================================
-- sightings: public read (anyone can see the species-sightings feed);
-- only owner can write+delete. Admins can verify.
-- ============================================================
CREATE POLICY sightings_select_public ON sightings
  FOR SELECT USING (true);

CREATE POLICY sightings_insert_own ON sightings
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY sightings_update_own ON sightings
  FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE POLICY sightings_delete_own ON sightings
  FOR DELETE USING (auth.uid() = user_id);

-- Verification is a write that flips verified_by/verified_at; the
-- owner can do this on their own row, admins can do it on any.
-- We define an "is admin" helper below.
CREATE POLICY sightings_admin_verify ON sightings
  FOR UPDATE USING (
    EXISTS (SELECT 1 FROM operator_users
            WHERE user_id = auth.uid() AND role IN ('owner', 'admin'))
    AND verified_by IS NULL  -- don't allow re-verification
  );

-- ============================================================
-- operators: public read of basic profile; full read for members.
-- ============================================================
CREATE POLICY operators_select_public ON operators
  FOR SELECT USING (true);

-- Members can update operator profile (owner/admin only).
CREATE POLICY operators_update_member ON operators
  FOR UPDATE USING (
    EXISTS (SELECT 1 FROM operator_users
            WHERE operator_id = operators.id
              AND user_id = auth.uid()
              AND role IN ('owner', 'admin'))
  );

-- Anyone authenticated can register a new operator (becomes owner).
CREATE POLICY operators_insert_auth ON operators
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

-- Only owners can delete.
CREATE POLICY operators_delete_owner ON operators
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM operator_users
            WHERE operator_id = operators.id
              AND user_id = auth.uid()
              AND role = 'owner')
  );

-- ============================================================
-- operator_users: members can see other members; owners can manage.
-- ============================================================
CREATE POLICY operator_users_select_member ON operator_users
  FOR SELECT USING (
    user_id = auth.uid()
    OR EXISTS (SELECT 1 FROM operator_users ou
                WHERE ou.operator_id = operator_users.operator_id
                  AND ou.user_id = auth.uid())
  );

CREATE POLICY operator_users_insert_owner ON operator_users
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM operator_users
            WHERE operator_id = operator_users.operator_id
              AND user_id = auth.uid()
              AND role = 'owner')
  );

CREATE POLICY operator_users_delete_owner ON operator_users
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM operator_users
            WHERE operator_id = operator_users.operator_id
              AND user_id = auth.uid()
              AND role = 'owner')
  );

-- ============================================================
-- operator_dive_sites: members of the operator can manage; public read.
-- ============================================================
CREATE POLICY operator_dive_sites_select_public ON operator_dive_sites
  FOR SELECT USING (true);

CREATE POLICY operator_dive_sites_insert_member ON operator_dive_sites
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM operator_users
            WHERE operator_id = operator_dive_sites.operator_id
              AND user_id = auth.uid())
  );

CREATE POLICY operator_dive_sites_delete_member ON operator_dive_sites
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM operator_users
            WHERE operator_id = operator_dive_sites.operator_id
              AND user_id = auth.uid())
  );

-- ============================================================
-- species_dive_site_stats: public read; system write only.
-- No policy for INSERT/UPDATE/DELETE means service role only.
-- ============================================================
CREATE POLICY species_dive_site_stats_select_public ON species_dive_site_stats
  FOR SELECT USING (true);

-- ============================================================
-- user_life_list: owner read; service role write.
-- ============================================================
CREATE POLICY user_life_list_select_own ON user_life_list
  FOR SELECT USING (auth.uid() = user_id);

-- ============================================================
-- badges: public read; service role write.
-- ============================================================
CREATE POLICY badges_select_public ON badges
  FOR SELECT USING (true);

-- ============================================================
-- user_badges: owner read; service role write.
-- ============================================================
CREATE POLICY user_badges_select_own ON user_badges
  FOR SELECT USING (auth.uid() = user_id);

-- ============================================================
-- Helper functions used by RLS policies.
-- ============================================================

-- True if the current user is an admin/owner of the given operator.
CREATE OR REPLACE FUNCTION is_operator_admin(p_operator_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM operator_users
    WHERE operator_id = p_operator_id
      AND user_id = auth.uid()
      AND role IN ('owner', 'admin')
  );
$$;

-- True if the current user is any member of the given operator.
CREATE OR REPLACE FUNCTION is_operator_member(p_operator_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM operator_users
    WHERE operator_id = p_operator_id
      AND user_id = auth.uid()
  );
$$;
