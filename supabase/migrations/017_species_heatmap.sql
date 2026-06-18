-- Migration 017: Species sighting density for map heatmap overlay.

CREATE OR REPLACE FUNCTION species_sighting_heatmap(p_species_id UUID)
RETURNS TABLE (
  dive_site_id   UUID,
  name           TEXT,
  lat            DOUBLE PRECISION,
  lng            DOUBLE PRECISION,
  sighting_count INTEGER
)
LANGUAGE sql STABLE AS $$
  SELECT
    ds.id,
    ds.name,
    ST_Y(ds.location::geometry) AS lat,
    ST_X(ds.location::geometry) AS lng,
    stats.sighting_count
  FROM species_dive_site_stats stats
  JOIN dive_sites ds ON ds.id = stats.dive_site_id
  WHERE stats.species_id = p_species_id
    AND stats.sighting_count > 0
  ORDER BY stats.sighting_count DESC;
$$;

GRANT EXECUTE ON FUNCTION species_sighting_heatmap(UUID) TO anon, authenticated;

COMMENT ON FUNCTION species_sighting_heatmap IS
  'Per-site sighting counts for a species — powers the map heatmap overlay.';
