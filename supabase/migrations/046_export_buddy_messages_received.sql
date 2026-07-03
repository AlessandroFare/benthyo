-- Migration 046: include received buddy messages in the GDPR export.
--
-- Gap (found in the production-readiness pass): export_user_data (037)
-- exported only buddy messages the subject SENT (sender_id = p_user_id).
-- Messages the subject received are also their personal data under GDPR
-- Art. 15. buddy_messages has no recipient_id (it is conversation-based),
-- so "received" = messages in a conversation the subject participates in
-- that were sent by the other participant.
--
-- Redefined (not edited 037 in place) so existing databases pick up the
-- fix on replay. Authorization logic is unchanged from 037.

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
    'buddy_conversations', COALESCE((SELECT jsonb_agg(to_jsonb(bc)) FROM buddy_conversations bc WHERE bc.participant_a = p_user_id OR bc.participant_b = p_user_id), '[]'::jsonb),
    'buddy_messages_sent', COALESCE((SELECT jsonb_agg(to_jsonb(bm)) FROM buddy_messages bm WHERE bm.sender_id = p_user_id), '[]'::jsonb),
    'buddy_messages_received', COALESCE((
      SELECT jsonb_agg(to_jsonb(bm))
      FROM buddy_messages bm
      JOIN buddy_conversations bc ON bc.id = bm.conversation_id
      WHERE (bc.participant_a = p_user_id OR bc.participant_b = p_user_id)
        AND bm.sender_id <> p_user_id
    ), '[]'::jsonb),
    'rental_gear_checkouts', COALESCE((SELECT jsonb_agg(to_jsonb(rg)) FROM operator_rental_gear rg WHERE rg.checked_out_to = p_user_id), '[]'::jsonb)
  ) INTO result;
  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION export_user_data(UUID) TO authenticated, service_role;
