-- Migration 056: Citizen Science Impact RPC
--
-- Adds a SECURITY DEFINER function `citizen_science_impact(p_user_id UUID)`
-- that returns the number of sightings a user has contributed to each
-- external citizen-science database (iNaturalist, GBIF), plus totals.
--
-- The Flutter app calls this via a single `.rpc('citizen_science_impact')`
-- call and shows an animated impact banner on the profile screen.
--
-- Design notes:
--   - SECURITY DEFINER so the function can read sightings without the
--     caller needing direct table access beyond their own rows.
--   - Returns a single JSONB row so the client can destructure easily.
--   - `databases_count` is the number of distinct platforms that received
--     at least one of this user's sightings — used as the headline figure.

CREATE OR REPLACE FUNCTION citizen_science_impact(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total       INTEGER;
  v_inat        INTEGER;
  v_gbif        INTEGER;
  v_databases   INTEGER := 0;
BEGIN
  -- Verify the caller is requesting their own data (or is service_role).
  IF auth.uid() IS DISTINCT FROM p_user_id
     AND current_setting('role', true) NOT IN ('service_role', 'postgres')
  THEN
    RAISE EXCEPTION 'permission denied' USING ERRCODE = '42501';
  END IF;

  SELECT COUNT(*)
  INTO   v_total
  FROM   sightings
  WHERE  user_id = p_user_id
    AND  source   = 'user';

  -- iNaturalist: rows that have been pushed (non-null pushed_to_inat_at)
  -- OR that exist in the push queue with status = 'sent'.
  SELECT COUNT(DISTINCT s.id)
  INTO   v_inat
  FROM   sightings s
  WHERE  s.user_id = p_user_id
    AND  (
           s.pushed_to_inat_at IS NOT NULL
           OR EXISTS (
             SELECT 1 FROM inaturalist_push_queue q
             WHERE  q.sighting_id = s.id
               AND  q.status      = 'sent'
           )
         );

  -- GBIF: sightings that were included in at least one completed export batch.
  -- We join sightings to gbif_export_batches via exported_at timestamp window
  -- (sightings.gbif_exported_at is the canonical flag).
  SELECT COUNT(*)
  INTO   v_gbif
  FROM   sightings
  WHERE  user_id          = p_user_id
    AND  gbif_exported_at IS NOT NULL;

  IF v_inat > 0 THEN v_databases := v_databases + 1; END IF;
  IF v_gbif > 0 THEN v_databases := v_databases + 1; END IF;

  RETURN jsonb_build_object(
    'total_sightings',  v_total,
    'inat_contributed', v_inat,
    'gbif_contributed', v_gbif,
    'databases_count',  v_databases
  );
END;
$$;

COMMENT ON FUNCTION citizen_science_impact(UUID) IS
  'Returns JSONB with iNaturalist / GBIF contribution counts for a given user. '
  'Caller must match p_user_id unless service_role.';

GRANT EXECUTE ON FUNCTION citizen_science_impact(UUID) TO authenticated, service_role;
