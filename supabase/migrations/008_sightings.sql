-- Migration 008: Sightings table.
-- A user-reported observation of a species at a dive site (and optionally
-- within a specific dive log). Photos are stored in R2 and referenced
-- by URL. Confidence levels let the UI distinguish "I think it was X"
-- from "I'm certain." The verified_by column is set by an admin or
-- expert when the sighting is confirmed for export to GBIF.

CREATE TABLE sightings (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  dive_site_id      UUID NOT NULL REFERENCES dive_sites(id) ON DELETE CASCADE,
  species_id        UUID NOT NULL REFERENCES species(id) ON DELETE RESTRICT,
  dive_log_id       UUID REFERENCES dive_logs(id) ON DELETE SET NULL,
  observed_at       TIMESTAMPTZ NOT NULL,
  depth_m           NUMERIC(5, 1) CHECK (depth_m IS NULL OR depth_m >= 0),
  water_temp_c      NUMERIC(4, 1),
  visibility_m      NUMERIC(4, 1),
  count             INTEGER NOT NULL DEFAULT 1 CHECK (count > 0),
  behavior_tags     TEXT[] NOT NULL DEFAULT '{}',
  photo_urls        TEXT[] NOT NULL DEFAULT '{}',
  confidence_level  confidence_level NOT NULL DEFAULT 'likely',
  verified_by       UUID REFERENCES users(id) ON DELETE SET NULL,
  verified_at       TIMESTAMPTZ,
  notes             TEXT,
  location          GEOGRAPHY(POINT, 4326),
  -- Provenance: was this from a user contribution, an ETL import (gbif/obis),
  -- or an iNaturalist observation? Critical for GBIF export filtering.
  source            TEXT NOT NULL DEFAULT 'user'
                    CHECK (source IN ('user', 'gbif', 'obis', 'inaturalist', 'manual')),
  external_id       TEXT,  -- e.g., GBIF occurrence key
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- For idempotent ETL upserts: same (source, external_id) can only
  -- appear once. User-submitted sightings have source='user' and a
  -- NULL external_id, so the constraint only applies to ETL imports.
  CONSTRAINT sightings_source_external_unique UNIQUE (source, external_id)
);

CREATE INDEX idx_sightings_user ON sightings (user_id, observed_at DESC);
CREATE INDEX idx_sightings_site_time ON sightings (dive_site_id, observed_at DESC);
CREATE INDEX idx_sightings_species ON sightings (species_id, observed_at DESC);
CREATE INDEX idx_sightings_dive_log ON sightings (dive_log_id) WHERE dive_log_id IS NOT NULL;
CREATE INDEX idx_sightings_verified ON sightings (verified_by, verified_at) WHERE verified_by IS NOT NULL;
CREATE INDEX idx_sightings_confidence ON sightings (confidence_level);
CREATE INDEX idx_sightings_observed_at ON sightings (observed_at DESC);
CREATE INDEX idx_sightings_location ON sightings USING GIST (location);
CREATE INDEX idx_sightings_behavior ON sightings USING GIN (behavior_tags);

CREATE TRIGGER trg_sightings_updated_at
  BEFORE UPDATE ON sightings
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE sightings IS 'A single observation of a species at a place and time. The data moat.';
COMMENT ON COLUMN sightings.verified_by IS 'Expert who confirmed this record for GBIF export.';
COMMENT ON COLUMN sightings.source IS 'Provenance; only user- and expert-sourced rows become GBIF candidates.';

-- Auto-fill location from dive site if not provided.
CREATE OR REPLACE FUNCTION sightings_autofill_location()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.location IS NULL THEN
    SELECT location INTO NEW.location FROM dive_sites WHERE id = NEW.dive_site_id;
  END IF;
  IF NEW.observed_at IS NULL THEN
    NEW.observed_at = now();
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_sightings_autofill
  BEFORE INSERT ON sightings
  FOR EACH ROW EXECUTE FUNCTION sightings_autofill_location();
