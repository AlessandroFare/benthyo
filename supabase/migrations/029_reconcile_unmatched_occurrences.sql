-- Migration 029: GBIF/OBIS open-water placeholder sites.
--
-- When the GBIF/OBIS pipelines cannot link a sighting to a known dive
-- site within their radius, the previous behaviour was to skip the
-- sighting entirely. That is a real data loss: ~20% of marine
-- occurrences are pelagic / offshore and don't have a coastal dive
-- site within 30 km.
--
-- This migration adds a function that runs as a post-import
-- reconciliation step. It clusters unmatched sightings into 10-km
-- buckets, creates a "Open water (N occurrences)" dive_site per
-- bucket, and back-fills the dive_site_id on the sightings.
--
-- Usage (run from the GBIF/OBIS ETL after the main import):
--   SELECT * from reconcile_unmatched_occurrences('gbif', 30);
--   SELECT * from reconcile_unmatched_occurrences('obis', 30);

CREATE OR REPLACE FUNCTION reconcile_unmatched_occurrences(
  p_source           TEXT,
  p_radius_meters    INTEGER DEFAULT 30000
)
RETURNS TABLE (created_sites INTEGER, linked_sightings INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_created INTEGER := 0;
  v_linked  INTEGER := 0;
  v_orphan   RECORD;
  v_new_id   UUID;
  v_centroid GEOGRAPHY(POINT, 4326);
  v_existing UUID;
  v_metadata JSONB;
BEGIN
  -- Iterate over distinct (round-to-0.1°) coordinate clusters of
  -- unmatched sightings. This is O(N) on the distinct count, not the
  -- raw sighting count.
  FOR v_orphan IN
    WITH unmatched AS (
      SELECT
        s.id AS sighting_id,
        s.location,
        s.observed_at,
        s.notes,
        ds.country_code,
        round(ST_Y(s.location::geometry)::numeric, 1) AS lat_bucket,
        round(ST_X(s.location::geometry)::numeric, 1) AS lng_bucket
      FROM sightings s
      LEFT JOIN dive_sites ds ON ds.id = s.dive_site_id
      WHERE s.source = p_source
        AND s.dive_site_id IS NULL
        AND s.location IS NOT NULL
    ),
    buckets AS (
      SELECT
        lat_bucket,
        lng_bucket,
        count(*) AS sighting_count,
        avg(ST_Y(location::geometry)) AS avg_lat,
        avg(ST_X(location::geometry)) AS avg_lng,
        min(country_code) AS country_code
      FROM unmatched
      GROUP BY lat_bucket, lng_bucket
      HAVING count(*) >= 3  -- only create placeholders for 3+ orphans
    )
    SELECT * FROM buckets
  LOOP
    -- Try to find a known dive_site within p_radius_meters of the
    -- bucket centroid. If found, use it instead of creating a new
    -- placeholder.
    v_centroid := ST_MakePoint(v_orphan.avg_lng, v_orphan.avg_lat)::geography;
    SELECT id INTO v_existing
    FROM dive_sites
    WHERE ST_DWithin(location, v_centroid, p_radius_meters)
    ORDER BY ST_Distance(location, v_centroid) ASC
    LIMIT 1;

    IF v_existing IS NOT NULL THEN
      -- Link all sightings in this bucket to the existing site.
      WITH linked AS (
        UPDATE sightings
        SET dive_site_id = v_existing
        WHERE source = p_source
          AND dive_site_id IS NULL
          AND ST_DWithin(
            location,
            v_centroid,
            p_radius_meters
          )
        RETURNING 1
      )
      SELECT count(*) INTO v_linked FROM linked;
      CONTINUE;
    END IF;

    v_metadata := jsonb_build_object(
      'source', 'open_water_reconciliation',
      'sighting_count', v_orphan.sighting_count,
      'created_from_etl_source', p_source
    );

    INSERT INTO dive_sites (
      name, slug, location, country_code, region,
      depth_min, depth_max, difficulty, site_type, access_type,
      verified, metadata
    )
    VALUES (
      'Open water (' || v_orphan.sighting_count || ' occurrences)',
      'ow-' || extract(epoch from now())::bigint || '-' || v_orphan.lat_bucket::text || '-' || v_orphan.lng_bucket::text,
      v_centroid,
      COALESCE(v_orphan.country_code, 'XX'),
      'Open water',
      0, 0, 'advanced', 'other', 'boat',
      false,
      v_metadata
    )
    RETURNING id INTO v_new_id;

    v_created := v_created + 1;

    -- Link all sightings in this bucket to the new site.
    WITH linked AS (
      UPDATE sightings
      SET dive_site_id = v_new_id
      WHERE source = p_source
        AND dive_site_id IS NULL
        AND ST_DWithin(
          location,
          v_centroid,
          p_radius_meters
        )
      RETURNING 1
    )
    SELECT count(*) INTO v_linked FROM linked;
  END LOOP;

  RETURN QUERY SELECT v_created, v_linked;
END;
$$;

GRANT EXECUTE ON FUNCTION reconcile_unmatched_occurrences(TEXT, INTEGER)
  TO service_role;

COMMENT ON FUNCTION reconcile_unmatched_occurrences IS
  'Post-import reconciliation: link unmatched GBIF/OBIS sightings to existing dive sites within radius, or create "open water" placeholder sites for the rest. Returns (created_sites, linked_sightings).';
