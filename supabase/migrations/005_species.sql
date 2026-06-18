-- Migration 005: Species table.
-- One row per accepted species name. Localized common names allow the
-- mobile UI to display "Cernia bruna" to Italian users without a separate
-- translation pipeline. The iNaturalist taxon id is the source of truth
-- for taxonomy; WoRMS id is the secondary identifier for marine species.

CREATE TABLE species (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  scientific_name    TEXT NOT NULL,
  common_name        TEXT,
  common_name_it     TEXT,
  common_name_es     TEXT,
  family             TEXT,
  genus              TEXT,
  order_name         TEXT,
  class_name         TEXT,
  phylum             TEXT,
  kingdom            TEXT,
  inat_taxon_id      BIGINT,
  worms_id           INTEGER,
  gbif_taxon_key     BIGINT,
  description        TEXT,
  max_depth_m        NUMERIC(5, 1),
  min_depth_m        NUMERIC(5, 1),
  typical_length_cm  NUMERIC(6, 1),
  conservation_status conservation_status,
  image_url          TEXT,
  metadata           JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT species_scientific_name_unique UNIQUE (scientific_name)
);

CREATE INDEX idx_species_scientific_name ON species (scientific_name);
CREATE INDEX idx_species_common_name ON species (common_name);
CREATE INDEX idx_species_inat_taxon_id ON species (inat_taxon_id) WHERE inat_taxon_id IS NOT NULL;
CREATE INDEX idx_species_worms_id ON species (worms_id) WHERE worms_id IS NOT NULL;
CREATE INDEX idx_species_gbif_key ON species (gbif_taxon_key) WHERE gbif_taxon_key IS NOT NULL;
CREATE INDEX idx_species_family ON species (family) WHERE family IS NOT NULL;
CREATE INDEX idx_species_class ON species (class_name) WHERE class_name IS NOT NULL;
CREATE INDEX idx_species_conservation ON species (conservation_status) WHERE conservation_status IS NOT NULL;

-- Full-text search across all name fields.
ALTER TABLE species ADD COLUMN search_tsv tsvector;
CREATE INDEX idx_species_search_tsv ON species USING GIN (search_tsv);

CREATE OR REPLACE FUNCTION species_search_tsv_update()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.search_tsv :=
    setweight(to_tsvector('simple', coalesce(NEW.scientific_name, '')), 'A') ||
    setweight(to_tsvector('simple', coalesce(NEW.common_name, '')), 'B') ||
    setweight(to_tsvector('simple', coalesce(NEW.common_name_it, '')), 'B') ||
    setweight(to_tsvector('simple', coalesce(NEW.common_name_es, '')), 'B') ||
    setweight(to_tsvector('simple', coalesce(NEW.family, '')), 'C') ||
    setweight(to_tsvector('simple', coalesce(NEW.description, '')), 'D');
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_species_search_tsv
  BEFORE INSERT OR UPDATE OF scientific_name, common_name, common_name_it, common_name_es, family, description ON species
  FOR EACH ROW EXECUTE FUNCTION species_search_tsv_update();

CREATE TRIGGER trg_species_updated_at
  BEFORE UPDATE ON species
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE species IS 'Marine species catalog; iNat taxon id is the canonical external link.';
