-- Migration 004: Dive sites table.
-- Contains a PostGIS GEOGRAPHY(POINT, 4326) column for spatial queries
-- (find sites within X km of a coordinate, etc.). The SRID 4326 is
-- WGS 84, the GPS standard.

CREATE TABLE dive_sites (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name         TEXT NOT NULL,
  slug         TEXT NOT NULL UNIQUE,
  description  TEXT,
  location     GEOGRAPHY(POINT, 4326) NOT NULL,
  country_code CHAR(2) NOT NULL,  -- ISO 3166-1 alpha-2
  region       TEXT,
  depth_min    NUMERIC(5, 1) NOT NULL CHECK (depth_min >= 0),
  depth_max    NUMERIC(5, 1) NOT NULL CHECK (depth_max >= 0),
  difficulty   site_difficulty NOT NULL,
  site_type    site_type NOT NULL,
  access_type  access_type NOT NULL,
  created_by   UUID REFERENCES users(id) ON DELETE SET NULL,
  verified     BOOLEAN NOT NULL DEFAULT FALSE,
  -- Free-form metadata: OSM node id, source attribution, etc.
  metadata     JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT dive_sites_depth_order CHECK (depth_min <= depth_max),
  CONSTRAINT dive_sites_slug_format CHECK (slug ~ '^[a-z0-9-]+$')
);

-- B-tree indexes for lookups by slug and country.
CREATE INDEX idx_dive_sites_slug ON dive_sites (slug);
CREATE INDEX idx_dive_sites_country ON dive_sites (country_code);
CREATE INDEX idx_dive_sites_difficulty ON dive_sites (difficulty);
CREATE INDEX idx_dive_sites_site_type ON dive_sites (site_type);

-- GIST index is the only way to query GEOGRAPHY efficiently.
-- Without it, "find sites near (lat, lng)" would be a full table scan.
CREATE INDEX idx_dive_sites_location ON dive_sites USING GIST (location);
-- Partial GIST index: rows with a known country_code (covers the common
-- "find sites near coord within a specific country" query pattern).
CREATE INDEX idx_dive_sites_country_location ON dive_sites USING GIST (location)
  WHERE country_code IS NOT NULL;

-- B-tree on metadata fields for common filters.
CREATE INDEX idx_dive_sites_metadata ON dive_sites USING GIN (metadata);

-- GIN index for full-text search (added after tsvector column).
ALTER TABLE dive_sites ADD COLUMN search_tsv tsvector;
CREATE INDEX idx_dive_sites_search_tsv ON dive_sites USING GIN (search_tsv);

-- Trigger: keep search_tsv up to date.
CREATE OR REPLACE FUNCTION dive_sites_search_tsv_update()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.search_tsv :=
    setweight(to_tsvector('simple', coalesce(NEW.name, '')), 'A') ||
    setweight(to_tsvector('simple', coalesce(NEW.region, '')), 'B') ||
    setweight(to_tsvector('simple', coalesce(NEW.description, '')), 'C');
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_dive_sites_search_tsv
  BEFORE INSERT OR UPDATE OF name, region, description ON dive_sites
  FOR EACH ROW EXECUTE FUNCTION dive_sites_search_tsv_update();

CREATE TRIGGER trg_dive_sites_updated_at
  BEFORE UPDATE ON dive_sites
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE dive_sites IS 'Georeferenced scuba dive sites with depth, difficulty, and type metadata.';
COMMENT ON COLUMN dive_sites.location IS 'PostGIS GEOGRAPHY POINT in WGS 84; use ST_DWithin for radius queries.';
COMMENT ON COLUMN dive_sites.metadata IS 'Source attribution, OSM id, photo URL set, etc.';

-- Spatial helper: sites within a radius (km) of a coordinate.
-- Returns id, name, slug, country_code, and distance in meters.
CREATE OR REPLACE FUNCTION nearby_dive_sites(
  p_lat      DOUBLE PRECISION,
  p_lng      DOUBLE PRECISION,
  p_radius_km DOUBLE PRECISION DEFAULT 50
)
RETURNS TABLE (
  id           UUID,
  name         TEXT,
  slug         TEXT,
  country_code CHAR(2),
  region       TEXT,
  distance_m   DOUBLE PRECISION
)
LANGUAGE sql STABLE AS $$
  SELECT
    s.id,
    s.name,
    s.slug,
    s.country_code,
    s.region,
    ST_Distance(s.location, ST_MakePoint(p_lng, p_lat)::geography) AS distance_m
  FROM dive_sites s
  WHERE ST_DWithin(
    s.location,
    ST_MakePoint(p_lng, p_lat)::geography,
    p_radius_km * 1000.0
  )
  ORDER BY distance_m ASC;
$$;