-- Migration 061: Make sightings.dive_site_id nullable for open-water reconciliation.
--
-- ETL importers (GBIF/OBIS/SEAMAP) previously skipped sightings that
-- had no dive site within their matching radius. This silently dropped
-- pelagic/offshore occurrences. The reconciliation function (migration 029)
-- was designed to cluster and link these orphans, but was blocked because
-- dive_site_id was NOT NULL — unmatched rows could never be inserted.
--
-- This migration:
--   1. Drops NOT NULL + FK on sightings.dive_site_id
--   2. Updates the autofill-location trigger to skip when dive_site_id IS NULL
--   3. Updates the aggregate-maintenance trigger to skip stats for NULL-site sightings
--   4. Drops/recreates the partial index on dive_site_id to allow NULLs

-- ── 1. Relax the FK + NOT NULL ──────────────────────────────────────────────
ALTER TABLE sightings DROP CONSTRAINT IF EXISTS sightings_dive_site_id_fkey;
ALTER TABLE sightings ALTER COLUMN dive_site_id DROP NOT NULL;
ALTER TABLE sightings ADD CONSTRAINT sightings_dive_site_id_fkey
  FOREIGN KEY (dive_site_id) REFERENCES dive_sites(id) ON DELETE SET NULL;

-- ── 2. Update autofill-location trigger ─────────────────────────────────────
-- When dive_site_id is NULL, there's no dive site to copy location from.
CREATE OR REPLACE FUNCTION sightings_autofill_location()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.dive_site_id IS NOT NULL AND NEW.location IS NULL THEN
    SELECT location INTO NEW.location FROM dive_sites WHERE id = NEW.dive_site_id;
  END IF;
  IF NEW.observed_at IS NULL THEN
    NEW.observed_at = now();
  END IF;
  RETURN NEW;
END;
$$;

-- ── 3. Update aggregate trigger to skip NULL-site sightings ─────────────────
-- species_dive_site_stats tracks per-(species, site) pairs; a sighting with
-- no dive_site_id should not create a row there.  user_life_list still
-- counts the sighting (it doesn't filter by site).
CREATE OR REPLACE FUNCTION maintain_sighting_aggregates()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_species_id  UUID;
  v_site_id     UUID;
  v_user_id     UUID;
  v_avg_depth   NUMERIC(5, 1);
  v_count       INTEGER;
  v_last_seen   TIMESTAMPTZ;
  v_best_months INTEGER[];
  v_first_seen  TIMESTAMPTZ;
  v_total       INTEGER;
  v_sites       UUID[];
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_species_id := OLD.species_id;
    v_site_id    := OLD.dive_site_id;
    v_user_id    := OLD.user_id;
  ELSE
    v_species_id := NEW.species_id;
    v_site_id    := NEW.dive_site_id;
    v_user_id    := NEW.user_id;
  END IF;

  -- ── species_dive_site_stats (skip if no site) ────────────────────
  IF v_site_id IS NOT NULL THEN
    SELECT
      count(*), avg(depth_m), max(observed_at),
      array_agg(DISTINCT extract(month from observed_at)::int)
    INTO v_count, v_avg_depth, v_last_seen, v_best_months
    FROM sightings
    WHERE species_id = v_species_id AND dive_site_id = v_site_id;

    IF v_count = 0 THEN
      DELETE FROM species_dive_site_stats
      WHERE species_id = v_species_id AND dive_site_id = v_site_id;
    ELSE
      INSERT INTO species_dive_site_stats
        (species_id, dive_site_id, sighting_count, last_seen_at, avg_depth_m, best_season)
      VALUES
        (v_species_id, v_site_id, v_count, v_last_seen, v_avg_depth, coalesce(v_best_months, '{}'))
      ON CONFLICT (species_id, dive_site_id) DO UPDATE SET
        sighting_count = EXCLUDED.sighting_count,
        last_seen_at   = EXCLUDED.last_seen_at,
        avg_depth_m    = EXCLUDED.avg_depth_m,
        best_season    = EXCLUDED.best_season;
    END IF;
  END IF;

  -- ── user_life_list (always recompute; doesn't depend on site) ────
  IF TG_OP = 'DELETE' THEN
    SELECT count(*) INTO v_total FROM sightings
    WHERE user_id = v_user_id AND species_id = v_species_id;
    IF v_total = 0 THEN
      DELETE FROM user_life_list
      WHERE user_id = v_user_id AND species_id = v_species_id;
    ELSE
      SELECT min(observed_at), array_agg(DISTINCT dive_site_id)
        INTO v_first_seen, v_sites
      FROM sightings
      WHERE user_id = v_user_id AND species_id = v_species_id;
      UPDATE user_life_list SET
        first_seen_at = v_first_seen,
        total_sightings = v_total,
        site_ids = coalesce(v_sites, '{}')
      WHERE user_id = v_user_id AND species_id = v_species_id;
    END IF;
  ELSE
    SELECT min(observed_at), count(*), array_agg(DISTINCT dive_site_id)
      INTO v_first_seen, v_total, v_sites
    FROM sightings
    WHERE user_id = v_user_id AND species_id = v_species_id;
    INSERT INTO user_life_list
      (user_id, species_id, first_seen_at, total_sightings, site_ids)
    VALUES
      (v_user_id, v_species_id, v_first_seen, v_total, coalesce(v_sites, '{}'))
    ON CONFLICT (user_id, species_id) DO UPDATE SET
      first_seen_at = EXCLUDED.first_seen_at,
      total_sightings = EXCLUDED.total_sightings,
      site_ids = EXCLUDED.site_ids;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

-- ── 4. Rebuild dependent index to handle NULLs efficiently ──────────────────
DROP INDEX IF EXISTS idx_sightings_site_time;
CREATE INDEX idx_sightings_site_time ON sightings (dive_site_id, observed_at DESC)
  WHERE dive_site_id IS NOT NULL;

COMMENT ON COLUMN sightings.dive_site_id IS
  'Dive site this sighting belongs to. NULL for open-water/pelagic sightings that are not within range of any known site.';
