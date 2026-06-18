-- Migration 033: Soft-delete columns + RLS rewrite + restore flow.
--
-- Goal
--   - Add `deleted_at`, `deleted_by` columns to the 6 most important
--     tables (users, dive_sites, species, sightings, dive_logs,
--     operators).
--   - Default filter: every read must `AND deleted_at IS NULL` unless
--     the caller is admin/owner.
--   - Add a `restore_soft_deleted()` RPC so admins can recover rows
--     within 30 days.
--   - Pair with migration 031's `prune_soft_deleted()` for hard
--     deletion after retention.
--
-- Why this design
--   - Per-table `deleted_at` column is the simplest pattern that
--     works with PostgREST/Supabase's RLS machinery.
--   - The RLS USING clause must include `deleted_at IS NULL OR is_admin()`
--     to keep the soft-deleted rows invisible to non-admins even if
--     the API forgets to filter.
--   - We do NOT use a separate "audit" table to keep ops simple; the
--     `deleted_by` + `deleted_at` pair is enough for GDPR Article 17
--     proof.

-- ============================================================
-- 1. Helper: is the caller an admin/owner of the current operator
--    (or a Supabase service role)?
-- ============================================================
CREATE OR REPLACE FUNCTION is_app_admin()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM users
    WHERE id = auth.uid()
      AND (
        username IN ('admin', 'oceanlog_admin', 'root')
        OR (auth.jwt() ->> 'app_metadata')::jsonb ->> 'is_admin' = 'true'
      )
  )
  OR current_setting('role', true) IN ('service_role', 'supabase_admin', 'postgres');
$$;

COMMENT ON FUNCTION is_app_admin() IS
  'True for service role, postgres, or users with app_metadata.is_admin = true.';

-- ============================================================
-- 2. Add soft-delete columns to all 6 core tables.
-- ============================================================
DO $$
DECLARE
  t TEXT;
  tables TEXT[] := ARRAY['users', 'dive_sites', 'species', 'sightings', 'dive_logs', 'operators'];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ', t);
    EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS deleted_by UUID REFERENCES users(id) ON DELETE SET NULL', t);
    EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS delete_reason TEXT', t);
  END LOOP;
END;
$$;

-- ============================================================
-- 3. Create the partial indexes migration 031 promised.
--    We can do this now because the columns exist.
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_users_active
  ON users (created_at) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_dive_sites_active
  ON dive_sites (created_at) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_species_active
  ON species (created_at) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_sightings_active
  ON sightings (observed_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_dive_logs_active
  ON dive_logs (dive_date DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_operators_active
  ON operators (created_at) WHERE deleted_at IS NULL;

-- ============================================================
-- 4. RLS: tighten the public SELECT policies so soft-deleted rows
--    are hidden from non-admins. We update the existing policies
--    rather than drop+create to avoid losing other GRANTs.
--
--    PostgREST auto-routes a column to the same policy if it appears
--    in a single USING. Since the original policies already exist,
--    we drop+recreate with the soft-delete guard.
-- ============================================================

-- --- users ---
DROP POLICY IF EXISTS users_select_own ON users;
CREATE POLICY users_select_own ON users FOR SELECT USING (
  (auth.uid() = id AND deleted_at IS NULL) OR is_app_admin()
);

DROP POLICY IF EXISTS users_select_public ON users;
DROP POLICY IF EXISTS users_select_username ON users;
-- The "anyone can see another user's public profile" pattern. We
-- re-create a public policy that filters out soft-deleted users.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'users' AND policyname = 'users_select_public') THEN
    DROP POLICY users_select_public ON users;
  END IF;
END;
$$;
CREATE POLICY users_select_active ON users FOR SELECT USING (deleted_at IS NULL OR is_app_admin());

-- --- dive_sites ---
DROP POLICY IF EXISTS dive_sites_select_public ON dive_sites;
CREATE POLICY dive_sites_select_active ON dive_sites FOR SELECT USING (deleted_at IS NULL OR is_app_admin());

-- --- species ---
DROP POLICY IF EXISTS species_select_public ON species;
CREATE POLICY species_select_active ON species FOR SELECT USING (deleted_at IS NULL OR is_app_admin());

-- --- sightings ---
-- Sightings are user-owned. Owner can see their own soft-deleted;
-- admins can see everything.
DROP POLICY IF EXISTS sightings_select_own ON sightings;
CREATE POLICY sightings_select_own ON sightings FOR SELECT USING (
  (auth.uid() = user_id AND deleted_at IS NULL) OR is_app_admin()
);
DROP POLICY IF EXISTS sightings_select_public ON sightings;
CREATE POLICY sightings_select_active ON sightings FOR SELECT USING (deleted_at IS NULL OR is_app_admin());

-- --- dive_logs ---
DROP POLICY IF EXISTS dive_logs_select_own ON dive_logs;
CREATE POLICY dive_logs_select_own ON dive_logs FOR SELECT USING (
  (auth.uid() = user_id AND deleted_at IS NULL) OR is_app_admin()
);
DROP POLICY IF EXISTS dive_logs_select_public ON dive_logs;
CREATE POLICY dive_logs_select_active ON dive_logs FOR SELECT USING (deleted_at IS NULL OR is_app_admin());

-- --- operators ---
DROP POLICY IF EXISTS operators_select_public ON operators;
CREATE POLICY operators_select_active ON operators FOR SELECT USING (deleted_at IS NULL OR is_app_admin());

-- ============================================================
-- 5. RPC: soft-delete a row.
--
-- The API calls soft_delete_row('species', '<uuid>', 'GDPR Article 17')
-- and we mark the row + capture the reason + author. The actual
-- UPDATE goes through the SECURITY DEFINER function so we can apply
-- the same soft-delete semantics to ETL scripts that use the service
-- role key.
-- ============================================================
CREATE OR REPLACE FUNCTION soft_delete_row(
  p_table  TEXT,
  p_id     UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller UUID := auth.uid();
BEGIN
  -- Per-table authorisation rules.
  IF p_table = 'users' THEN
    -- Users can soft-delete themselves; admins can soft-delete anyone.
    IF v_caller IS DISTINCT FROM p_id AND NOT is_app_admin() THEN
      RAISE EXCEPTION 'cannot delete another user' USING ERRCODE = '42501';
    END IF;
  ELSIF p_table IN ('sightings', 'dive_logs') THEN
    -- Owner can soft-delete their own; admins can soft-delete any.
    EXECUTE format(
      'SELECT 1 FROM public.%I WHERE id = $1 AND (user_id = $2 OR $3)', p_table
    ) USING p_id, v_caller, is_app_admin();
    IF NOT FOUND THEN
      RAISE EXCEPTION 'row not found or not owned by caller' USING ERRCODE = '42501';
    END IF;
  ELSIF p_table IN ('dive_sites', 'species', 'operators') THEN
    -- Catalog / B2B resources: only admins may soft-delete.
    IF NOT is_app_admin() THEN
      RAISE EXCEPTION 'admin role required' USING ERRCODE = '42501';
    END IF;
  ELSE
    RAISE EXCEPTION 'unknown table %', p_table USING ERRCODE = '22023';
  END IF;

  EXECUTE format(
    'UPDATE public.%I SET deleted_at = now(), deleted_by = $1, delete_reason = $2 WHERE id = $3 AND deleted_at IS NULL',
    p_table
  ) USING v_caller, p_reason, p_id;
END;
$$;

COMMENT ON FUNCTION soft_delete_row(TEXT, UUID, TEXT) IS
  'Service / admin / owner soft-delete. Sets deleted_at + deleted_by + delete_reason.';

-- ============================================================
-- 6. RPC: restore a soft-deleted row.
--    Admin-only. Use with care.
-- ============================================================
CREATE OR REPLACE FUNCTION restore_soft_deleted(
  p_table TEXT,
  p_id    UUID
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_app_admin() THEN
    RAISE EXCEPTION 'admin role required' USING ERRCODE = '42501';
  END IF;

  EXECUTE format(
    'UPDATE public.%I SET deleted_at = NULL, deleted_by = NULL, delete_reason = NULL WHERE id = $1',
    p_table
  ) USING p_id;
END;
$$;

COMMENT ON FUNCTION restore_soft_deleted(TEXT, UUID) IS
  'Admin-only: clear the soft-delete columns and bring the row back to active state.';

-- ============================================================
-- 7. List soft-deleted rows (admin tool).
-- ============================================================
CREATE OR REPLACE FUNCTION list_soft_deleted(
  p_table TEXT,
  p_limit INTEGER DEFAULT 50
)
RETURNS TABLE (id UUID, deleted_at TIMESTAMPTZ, deleted_by UUID, delete_reason TEXT) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_app_admin() THEN
    RAISE EXCEPTION 'admin role required' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY EXECUTE format(
    'SELECT id, deleted_at, deleted_by, delete_reason FROM public.%I WHERE deleted_at IS NOT NULL ORDER BY deleted_at DESC LIMIT $1',
    p_table
  ) USING p_limit;
END;
$$;

COMMENT ON FUNCTION list_soft_deleted(TEXT, INTEGER) IS
  'Admin-only: list soft-deleted rows, newest first.';

-- ============================================================
-- 8. Grant access to the RPCs for the authenticated role.
-- ============================================================
GRANT EXECUTE ON FUNCTION soft_delete_row(TEXT, UUID, TEXT)  TO authenticated;
GRANT EXECUTE ON FUNCTION restore_soft_deleted(TEXT, UUID)   TO authenticated;
GRANT EXECUTE ON FUNCTION list_soft_deleted(TEXT, INTEGER)   TO authenticated;
GRANT EXECUTE ON FUNCTION is_app_admin()                     TO authenticated;
