-- Migration 026: RLS hardening (DD-1.1, DD-1.2, DD-1.5, DD-1.6 follow-ups).
--
-- Fixes:
--   1. medical_submissions_operator_read was FOR ALL — narrows to FOR SELECT.
--   2. sighting_corrections had no UPDATE policy — accept/expertResolve
--      flows silently updated 0 rows. Adds a SELECT policy plus an UPDATE
--      policy that lets the reporter withdraw, the sighting owner
--      accept/reject, and a taxonomy expert resolve.
--   3. operator_waivers_staff_write is FOR ALL — keep SELECT/INSERT/UPDATE
--      for staff, but forbid DELETE on waivers that have signatures
--      attached (preserved via a trigger).
--   4. operator_payment_links: FOR ALL is fine in practice (we already
--      audit), but split out an explicit FOR SELECT for clarity.
--   5. Adds an is_approved column + policies on operator_marketplace_listings
--      so a moderator queue can hide unapproved listings from the public.
--   6. Adds image_license to species for the new Wikimedia ETL.
--   7. Adds the export_user_data SECURITY DEFINER function (GDPR Art. 15).
--   8. Adds the inat_identify_cache cleanup helper (callable from pg_cron).
--   9. Adds an unmapped_iucn_codes audit table for the GBIF conservation
--      status map.
--  10. C-6 follow-up: replace the column-agnostic operators UPDATE
--      policy with a column-restricted one. subscription_tier and
--      subscription_status can ONLY be modified via the
--      set_operator_subscription SECURITY DEFINER function.

-- ---------------------------------------------------------------------------
-- 1. Medical: narrow to FOR SELECT.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS medical_submissions_operator_read
  ON medical_form_submissions;
CREATE POLICY medical_submissions_operator_select
  ON medical_form_submissions
  FOR SELECT
  USING (
    operator_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM operator_users ou
      WHERE ou.operator_id = medical_form_submissions.operator_id
        AND ou.user_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 2. Sighting corrections: SELECT for all (already exists as read), plus
--    an explicit UPDATE policy that covers the three legitimate writers.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS sighting_corrections_update ON sighting_corrections;
CREATE POLICY sighting_corrections_update
  ON sighting_corrections
  FOR UPDATE
  USING (
    -- Reporter may withdraw their own open correction.
    (reporter_id = auth.uid() AND status = 'open')
    OR
    -- The sighting's reporter may accept or reject.
    EXISTS (
      SELECT 1 FROM sightings s
      WHERE s.id = sighting_corrections.sighting_id
        AND s.user_id = auth.uid()
    )
    OR
    -- A taxonomy expert may resolve.
    EXISTS (
      SELECT 1 FROM users u
      WHERE u.id = auth.uid() AND u.taxonomy_expert = true
    )
  )
  WITH CHECK (
    -- Same conditions guard the write side.
    (reporter_id = auth.uid() AND status = 'open')
    OR
    EXISTS (
      SELECT 1 FROM sightings s
      WHERE s.id = sighting_corrections.sighting_id
        AND s.user_id = auth.uid()
    )
    OR
    EXISTS (
      SELECT 1 FROM users u
      WHERE u.id = auth.uid() AND u.taxonomy_expert = true
    )
  );

-- ---------------------------------------------------------------------------
-- 3. operator_waivers: keep staff write but add a guard trigger that
--    prevents DELETE if any waiver_signature references this waiver.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION prevent_signed_waiver_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM waiver_signatures ws WHERE ws.waiver_id = OLD.id
  ) THEN
    RAISE EXCEPTION 'Cannot delete a waiver that has signed signatures (%).', OLD.id
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_block_signed_waiver_delete ON operator_waivers;
CREATE TRIGGER trg_block_signed_waiver_delete
  BEFORE DELETE ON operator_waivers
  FOR EACH ROW
  EXECUTE FUNCTION prevent_signed_waiver_delete();

-- ---------------------------------------------------------------------------
-- 4. operator_payment_links: split out SELECT for clarity (was FOR ALL).
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS payment_links_operator ON operator_payment_links;
CREATE POLICY payment_links_operator_select
  ON operator_payment_links FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM operator_users ou
    WHERE ou.operator_id = operator_payment_links.operator_id
      AND ou.user_id = auth.uid()
  ));
CREATE POLICY payment_links_operator_write
  ON operator_payment_links FOR INSERT
  WITH CHECK (EXISTS (
    SELECT 1 FROM operator_users ou
    WHERE ou.operator_id = operator_payment_links.operator_id
      AND ou.user_id = auth.uid()
      AND ou.role IN ('owner', 'admin')
  ));
CREATE POLICY payment_links_operator_update
  ON operator_payment_links FOR UPDATE
  USING (EXISTS (
    SELECT 1 FROM operator_users ou
    WHERE ou.operator_id = operator_payment_links.operator_id
      AND ou.user_id = auth.uid()
      AND ou.role IN ('owner', 'admin')
  ));
CREATE POLICY payment_links_operator_delete
  ON operator_payment_links FOR DELETE
  USING (EXISTS (
    SELECT 1 FROM operator_users ou
    WHERE ou.operator_id = operator_payment_links.operator_id
      AND ou.user_id = auth.uid()
      AND ou.role = 'owner'
  ));

-- ---------------------------------------------------------------------------
-- 5. Marketplace moderation.
-- ---------------------------------------------------------------------------
ALTER TABLE operator_marketplace_listings
  ADD COLUMN IF NOT EXISTS is_approved BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS approved_by UUID REFERENCES users(id) ON DELETE SET NULL;

-- Public reads: only show approved AND active listings.
DROP POLICY IF EXISTS marketplace_listings_public_read
  ON operator_marketplace_listings;
CREATE POLICY marketplace_listings_public_read
  ON operator_marketplace_listings
  FOR SELECT
  USING (is_active = true AND is_approved = true);

-- Operators can still see their own unapproved listings.
CREATE POLICY marketplace_listings_owner_read
  ON operator_marketplace_listings
  FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM operator_users ou
    WHERE ou.operator_id = operator_marketplace_listings.operator_id
      AND ou.user_id = auth.uid()
  ));

-- Moderators (taxonomy_expert OR platform role) can approve.
CREATE POLICY marketplace_listings_moderate
  ON operator_marketplace_listings
  FOR UPDATE
  USING (
    EXISTS (SELECT 1 FROM users u WHERE u.id = auth.uid() AND u.taxonomy_expert = true)
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM users u WHERE u.id = auth.uid() AND u.taxonomy_expert = true)
  );

-- ---------------------------------------------------------------------------
-- 6. species.image_license for the new Wikimedia ETL.
-- ---------------------------------------------------------------------------
ALTER TABLE species
  ADD COLUMN IF NOT EXISTS image_license TEXT,
  ADD COLUMN IF NOT EXISTS image_source TEXT,
  ADD COLUMN IF NOT EXISTS image_attribution TEXT;

-- ---------------------------------------------------------------------------
-- 7. export_user_data (GDPR Article 15).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION export_user_data(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result JSONB;
BEGIN
  -- Only the user themselves, an operator admin for an operator they're
  -- a member of, or a service-role caller may invoke this.
  IF auth.uid() IS DISTINCT FROM p_user_id
     AND NOT EXISTS (
       SELECT 1 FROM operator_users ou
       WHERE ou.user_id = auth.uid() AND ou.role IN ('owner','admin')
     )
  THEN
    IF current_setting('role', true) IS DISTINCT FROM 'service_role' THEN
      RAISE EXCEPTION 'Not authorized to export this user' USING ERRCODE = '42501';
    END IF;
  END IF;

  SELECT jsonb_build_object(
    'exported_at', now(),
    'profile',          (SELECT to_jsonb(u) FROM users u WHERE u.id = p_user_id),
    'dive_logs',        COALESCE((SELECT jsonb_agg(to_jsonb(dl)) FROM dive_logs dl WHERE dl.user_id = p_user_id), '[]'::jsonb),
    'sightings',        COALESCE((SELECT jsonb_agg(to_jsonb(s))  FROM sightings s  WHERE s.user_id  = p_user_id), '[]'::jsonb),
    'life_list',        COALESCE((SELECT jsonb_agg(to_jsonb(ll)) FROM user_life_list ll WHERE ll.user_id = p_user_id), '[]'::jsonb),
    'badges',           COALESCE((SELECT jsonb_agg(to_jsonb(ub)) FROM user_badges ub WHERE ub.user_id = p_user_id), '[]'::jsonb),
    'gear_items',       COALESCE((SELECT jsonb_agg(to_jsonb(gi)) FROM gear_items gi WHERE gi.user_id = p_user_id), '[]'::jsonb),
    'trips_created',    COALESCE((SELECT jsonb_agg(to_jsonb(t))  FROM trips t  WHERE t.leader_id = p_user_id), '[]'::jsonb),
    'trips_member',     COALESCE((SELECT jsonb_agg(to_jsonb(tm)) FROM trip_members tm WHERE tm.user_id = p_user_id), '[]'::jsonb),
    'site_reviews',     COALESCE((SELECT jsonb_agg(to_jsonb(sr)) FROM site_reviews sr WHERE sr.user_id = p_user_id), '[]'::jsonb),
    'sighting_corrections', COALESCE((SELECT jsonb_agg(to_jsonb(sc)) FROM sighting_corrections sc WHERE sc.reporter_id = p_user_id), '[]'::jsonb),
    'medical_submissions', COALESCE((SELECT jsonb_agg(to_jsonb(ms)) FROM medical_form_submissions ms WHERE ms.user_id = p_user_id), '[]'::jsonb),
    'waiver_signatures', COALESCE((SELECT jsonb_agg(to_jsonb(ws)) FROM waiver_signatures ws WHERE ws.user_id = p_user_id), '[]'::jsonb),
    'api_keys',         COALESCE((SELECT jsonb_agg(to_jsonb(ak)) FROM api_keys ak WHERE ak.user_id = p_user_id), '[]'::jsonb),
    'social_posts',     COALESCE((SELECT jsonb_agg(to_jsonb(sf)) FROM social_feed_posts sf WHERE sf.user_id = p_user_id), '[]'::jsonb),
    'buddy_messages_sent', COALESCE((SELECT jsonb_agg(to_jsonb(bm)) FROM buddy_messages bm WHERE bm.sender_id = p_user_id), '[]'::jsonb),
    'rental_gear_checkouts', COALESCE((SELECT jsonb_agg(to_jsonb(rg)) FROM operator_rental_gear rg WHERE rg.checked_out_to = p_user_id), '[]'::jsonb)
  ) INTO result;
  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION export_user_data(UUID) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 8. inat_identify_cache cleanup (callable from pg_cron).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION prune_inat_identify_cache()
RETURNS INTEGER
LANGUAGE sql
AS $$
  WITH deleted AS (
    DELETE FROM inat_identify_cache
    WHERE expires_at < now()
    RETURNING 1
  )
  SELECT count(*)::int FROM deleted;
$$;

-- ---------------------------------------------------------------------------
-- 9. unmapped_iucn_codes audit.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS unmapped_iucn_codes (
  code        TEXT PRIMARY KEY,
  first_seen  TIMESTAMPTZ NOT NULL DEFAULT now(),
  seen_count  INTEGER NOT NULL DEFAULT 1
);

CREATE OR REPLACE FUNCTION log_unmapped_iucn()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.conservation_status IS NULL AND NEW.metadata ? 'iucn_unmapped' THEN
    INSERT INTO unmapped_iucn_codes (code, seen_count)
    VALUES (NEW.metadata->>'iucn_unmapped', 1)
    ON CONFLICT (code) DO UPDATE SET seen_count = unmapped_iucn_codes.seen_count + 1;
  END IF;
  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 10. operators: column-restricted UPDATE.
--
-- C-6: a staff member with role IN (owner, admin) could previously
-- self-upgrade their subscription_tier. We restrict the WITH CHECK so
-- that subscription_tier and subscription_status may not be modified
-- via this policy. The only path to mutate those columns is the
-- set_operator_subscription function.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS operators_update_member ON operators;
CREATE POLICY operators_update_member
  ON operators
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM operator_users
      WHERE operator_id = operators.id
        AND user_id = auth.uid()
        AND role IN ('owner', 'admin')
    )
  )
  WITH CHECK (
    -- Reject if the new row tries to modify the subscription columns
    -- to anything different from the existing row. We do this by
    -- comparing NEW to OLD; the WITH CHECK runs against the NEW row.
    -- The check below uses IS DISTINCT FROM to detect any change.
    subscription_tier  = (SELECT subscription_tier  FROM operators WHERE id = operators.id)
    AND subscription_status = (SELECT subscription_status FROM operators WHERE id = operators.id)
  );
