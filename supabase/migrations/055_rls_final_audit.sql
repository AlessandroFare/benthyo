-- Migration 055: Final RLS audit pass.
--
-- Supabase flags "rls_disabled_in_public" on the Oceanlog project.
-- After tracing every migration (001–054) the only tables in the public
-- schema without RLS are PostGIS system tables that cannot be altered by
-- application users (spatial_ref_sys, geometry_columns, geography_columns).
-- These are false-positive alerts documented in migration 054; they require
-- superuser ownership to change and are inherently read-only for all
-- non-superuser roles.
--
-- This migration closes two genuine gaps found in the final audit pass:
--
--   Gap 1 — sighting_photo_fingerprints had no DELETE policy, meaning
--     only service_role could delete photo fingerprints. Users should be
--     able to delete their own fingerprints (e.g. when withdrawing a
--     sighting).
--
--   Gap 2 — operator_rental_gear used a FOR ALL policy which permits
--     *any* operator_users member to delete rental gear. Restrict DELETE
--     to owner/admin only to protect the inventory from accidental staff
--     deletions.
--
--   Gap 3 — gbif_export_batches and inaturalist_push_queue used FOR ALL
--     with a USING clause only; the service-role pathway writes these
--     rows and a user should not be able to INSERT directly. Narrow the
--     policies to SELECT + DELETE only for the authenticated user.

-- ---------------------------------------------------------------------------
-- Gap 1: add DELETE policy for sighting_photo_fingerprints.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS photo_fingerprints_delete ON sighting_photo_fingerprints;
CREATE POLICY photo_fingerprints_delete ON sighting_photo_fingerprints
  FOR DELETE USING (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Gap 2: split operator_rental_gear FOR ALL into SELECT/INSERT/UPDATE
--   (any member) and DELETE (admin/owner only).
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS rental_gear_operator ON operator_rental_gear;

CREATE POLICY rental_gear_read ON operator_rental_gear
  FOR SELECT USING (is_operator_member(operator_id));

CREATE POLICY rental_gear_insert ON operator_rental_gear
  FOR INSERT WITH CHECK (is_operator_admin(operator_id));

CREATE POLICY rental_gear_update ON operator_rental_gear
  FOR UPDATE USING (is_operator_member(operator_id))
  WITH CHECK (is_operator_member(operator_id));

CREATE POLICY rental_gear_delete ON operator_rental_gear
  FOR DELETE USING (is_operator_admin(operator_id));

-- ---------------------------------------------------------------------------
-- Gap 3: narrow gbif_export_batches + inaturalist_push_queue so users
--   cannot INSERT directly (service_role writes; user only reads/deletes).
-- ---------------------------------------------------------------------------

-- gbif_export_batches
DROP POLICY IF EXISTS gbif_batches_own ON gbif_export_batches;
CREATE POLICY gbif_batches_select ON gbif_export_batches
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY gbif_batches_delete ON gbif_export_batches
  FOR DELETE USING (auth.uid() = user_id);

-- inaturalist_push_queue
DROP POLICY IF EXISTS inat_queue_own ON inaturalist_push_queue;
CREATE POLICY inat_queue_select ON inaturalist_push_queue
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY inat_queue_delete ON inaturalist_push_queue
  FOR DELETE USING (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- PostGIS false-positive documentation.
--
-- spatial_ref_sys, geometry_columns, geography_columns are owned by
-- the postgres/superuser role and are part of the PostGIS extension.
-- Supabase's rls_disabled_in_public linter flags them because they live
-- in the public schema. This is a known Supabase limitation and cannot be
-- fixed by enabling RLS (ALTER TABLE spatial_ref_sys ENABLE ROW LEVEL
-- SECURITY requires superuser). The correct resolution is to acknowledge
-- the alert in the Supabase dashboard as a false positive.
--
-- Reference: https://github.com/supabase/splinter/issues/XXX
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  RAISE NOTICE
    'Migration 055 complete. spatial_ref_sys RLS alert is a PostGIS '
    'false positive — cannot be fixed at the application level.';
END $$;
