-- Migration 037: Fix authorization scoping in export_user_data (GDPR Art. 15).
--
-- Bug (found in audit): the version defined in migration 026 authorized
-- the call if the caller was an owner/admin of ANY operator, without
-- checking that the *target* user (p_user_id) is a member of an operator
-- the caller administers. This let any operator admin export an arbitrary
-- user's full profile, medical submissions, and buddy messages.
--
-- Fix: an operator owner/admin may export a user ONLY when that user is a
-- member (via operator_users) of an operator the caller owns or admins.
-- The self-export path (auth.uid() = p_user_id) and the service_role path
-- are unchanged. We do not edit 026 in place so existing databases pick
-- up the fix on replay.

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
  -- Authorization:
  --   1. The user themselves, OR
  --   2. An operator owner/admin, but ONLY for a user who shares one of
  --      the caller's operators, OR
  --   3. A service-role caller.
  IF auth.uid() IS DISTINCT FROM p_user_id
     AND NOT EXISTS (
       SELECT 1
       FROM operator_users caller
       JOIN operator_users target
         ON target.operator_id = caller.operator_id
       WHERE caller.user_id = auth.uid()
         AND caller.role IN ('owner', 'admin')
         AND target.user_id = p_user_id
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
