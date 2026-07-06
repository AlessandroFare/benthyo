-- Migration 063: Set-based batch matching of sightings to nearby dive sites.
--
-- Why this exists
-- ---------------
-- The GBIF / OBIS / iNaturalist occurrence ETLs used to call the
-- `nearby_dive_sites(lat, lng, radius)` RPC once *per occurrence* inside a
-- JavaScript loop. With tens of thousands of occurrences that is tens of
-- thousands of sequential network round-trips to PostgREST, which makes the
-- pipeline extremely slow and, in practice, caps how much data can be
-- ingested in a single run.
--
-- This function replaces that per-row pattern with a single set-based UPDATE:
-- the ETL now inserts every sighting with only its `location` (and a NULL
-- `dive_site_id`), and afterwards calls this function ONCE per source. The
-- nearest dive site within `p_radius_km` is found using the GiST spatial
-- index on `dive_sites.location`, so the whole match runs as one indexed
-- query instead of N REST calls.
--
-- Sightings that still have no site within the radius (pelagic / offshore
-- occurrences) are left with dive_site_id = NULL and are then handled by
-- reconcile_unmatched_occurrences(), which clusters them into "open water"
-- placeholder sites.
--
-- Usage (from run-all-data, after the occurrence import step):
--   SELECT match_sightings_to_nearby_sites('gbif', 20);
--   SELECT match_sightings_to_nearby_sites('obis', 20);
--   SELECT match_sightings_to_nearby_sites('inat', 15);

CREATE OR REPLACE FUNCTION match_sightings_to_nearby_sites(
  p_source     TEXT,
  p_radius_km  DOUBLE PRECISION DEFAULT 20
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_matched INTEGER := 0;
BEGIN
  WITH candidates AS (
    SELECT
      s.id AS sighting_id,
      nn.id AS site_id
    FROM sightings s
    CROSS JOIN LATERAL (
      SELECT ds.id
      FROM dive_sites ds
      WHERE ds.location IS NOT NULL
        AND ST_DWithin(ds.location, s.location, p_radius_km * 1000.0)
      ORDER BY ST_Distance(ds.location, s.location) ASC
      LIMIT 1
    ) nn
    WHERE s.source = p_source
      AND s.dive_site_id IS NULL
      AND s.location IS NOT NULL
  ),
  upd AS (
    UPDATE sightings s
    SET dive_site_id = c.site_id
    FROM candidates c
    WHERE s.id = c.sighting_id
    RETURNING 1
  )
  SELECT count(*) INTO v_matched FROM upd;

  RETURN v_matched;
END;
$$;

GRANT EXECUTE ON FUNCTION match_sightings_to_nearby_sites(TEXT, DOUBLE PRECISION)
  TO service_role;

COMMENT ON FUNCTION match_sightings_to_nearby_sites IS
  'Set-based replacement for per-occurrence nearby_dive_sites RPC calls: links every unmatched sighting of a source to its nearest dive site within p_radius_km using the spatial index. Returns the number of sightings linked.';
