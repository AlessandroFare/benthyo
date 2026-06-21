-- Migration 051: include bookings + cert cards + photo fingerprints in the GDPR export.
--
-- Gap (found in the round-2 production-readiness pass): export_user_data (046)
-- did not include several tables holding the data subject's personal data:
--   - bookings (047): financial + PII (Stripe payment-intent ids, diver_name,
--     diver_email, diver_phone, status). MUST be in an Art. 15 export.
--   - cert_card_records (021): certification card scans / OCR text.
--   - sighting_photo_fingerprints (021): per-photo hashes/metadata tied to the user.
--
-- Redefined (not edited 046 in place) so existing databases pick up the fix on
-- replay. Authorization logic unchanged from 046/037.

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
    'rental_gear_checkouts', COALESCE((SELECT jsonb_agg(to_jsonb(rg)) FROM operator_rental_gear rg WHERE rg.checked_out_to = p_user_id), '[]'::jsonb),
    'bookings',         COALESCE((SELECT jsonb_agg(to_jsonb(bk)) FROM bookings bk WHERE bk.user_id = p_user_id), '[]'::jsonb),
    'cert_card_records', COALESCE((SELECT jsonb_agg(to_jsonb(cc)) FROM cert_card_records cc WHERE cc.user_id = p_user_id), '[]'::jsonb),
    'photo_fingerprints', COALESCE((SELECT jsonb_agg(to_jsonb(pf)) FROM sighting_photo_fingerprints pf WHERE pf.user_id = p_user_id), '[]'::jsonb),
    -- Dive-computer devices the subject paired (device_name + device_uuid are
    -- personal device identifiers; Art. 15 personal data).
    'dive_computer_devices', COALESCE((SELECT jsonb_agg(to_jsonb(dc)) FROM dive_computer_devices dc WHERE dc.user_id = p_user_id), '[]'::jsonb),
    -- Operator memberships + role for the subject (employment/role data).
    'operator_memberships', COALESCE((SELECT jsonb_agg(to_jsonb(ou)) FROM operator_users ou WHERE ou.user_id = p_user_id), '[]'::jsonb),
    -- User-scoped export/push attribution logs.
    'inaturalist_push_queue', COALESCE((SELECT jsonb_agg(to_jsonb(ipq)) FROM inaturalist_push_queue ipq WHERE ipq.user_id = p_user_id), '[]'::jsonb),
    'gbif_export_batches', COALESCE((SELECT jsonb_agg(to_jsonb(gb)) FROM gbif_export_batches gb WHERE gb.user_id = p_user_id), '[]'::jsonb)
  ) INTO result;
  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION export_user_data(UUID) TO authenticated, service_role;
