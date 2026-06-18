-- Migration 009: Aggregates and life-list tables.
-- These tables are denormalized hot-paths updated by triggers so the
-- consumer mobile app can render "species seen at this site" or
-- "my life list" in a single SELECT, not 5 JOINs.

-- Per-(species, dive_site) aggregate stats. One row per pair.
-- Updated by a trigger on sightings INSERT/UPDATE/DELETE.
CREATE TABLE species_dive_site_stats (
  species_id       UUID NOT NULL REFERENCES species(id) ON DELETE CASCADE,
  dive_site_id     UUID NOT NULL REFERENCES dive_sites(id) ON DELETE CASCADE,
  sighting_count   INTEGER NOT NULL DEFAULT 0 CHECK (sighting_count >= 0),
  last_seen_at     TIMESTAMPTZ,
  avg_depth_m      NUMERIC(5, 1),
  -- Months (1-12) when sightings historically peak. Used by the UI to
  -- render "best season to see this species here."
  best_season      INTEGER[] NOT NULL DEFAULT '{}',
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),

  PRIMARY KEY (species_id, dive_site_id)
);

CREATE INDEX idx_species_site_stats_count ON species_dive_site_stats (dive_site_id, sighting_count DESC);
CREATE INDEX idx_species_site_stats_species ON species_dive_site_stats (species_id, sighting_count DESC);

CREATE TRIGGER trg_species_dive_site_stats_updated_at
  BEFORE UPDATE ON species_dive_site_stats
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE species_dive_site_stats IS 'Materialized aggregate. Trigger-maintained from sightings table.';

-- Per-user life list. One row per (user, species) the user has seen.
CREATE TABLE user_life_list (
  user_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  species_id        UUID NOT NULL REFERENCES species(id) ON DELETE CASCADE,
  first_seen_at     TIMESTAMPTZ NOT NULL,
  total_sightings   INTEGER NOT NULL DEFAULT 1 CHECK (total_sightings > 0),
  site_ids          UUID[] NOT NULL DEFAULT '{}',
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

  PRIMARY KEY (user_id, species_id)
);

CREATE INDEX idx_user_life_list_user ON user_life_list (user_id, first_seen_at DESC);

COMMENT ON TABLE user_life_list IS 'Per-user, per-species first-seen + total. Powers the "life list" screen.';

-- Trigger: maintain species_dive_site_stats and user_life_list from sightings.
-- This is a per-statement-after trigger that recomputes the relevant rows
-- after an INSERT/UPDATE/DELETE on sightings. Recomputation is cheap
-- because the rows affected are localized by (species_id, dive_site_id).

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
  -- Determine which (species, site, user) the change applies to.
  -- DELETE has OLD; INSERT has NEW; UPDATE has both.
  IF TG_OP = 'DELETE' THEN
    v_species_id := OLD.species_id;
    v_site_id    := OLD.dive_site_id;
    v_user_id    := OLD.user_id;
  ELSE
    v_species_id := NEW.species_id;
    v_site_id    := NEW.dive_site_id;
    v_user_id    := NEW.user_id;
  END IF;

  -- Recompute species_dive_site_stats for this (species, site) pair.
  SELECT
    count(*),
    avg(depth_m),
    max(observed_at),
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

  -- Recompute user_life_list for this (user, species) pair.
  IF TG_OP = 'DELETE' THEN
    -- After a delete, check if any sightings remain for this pair.
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

CREATE TRIGGER trg_sightings_aggregates
  AFTER INSERT OR UPDATE OR DELETE ON sightings
  FOR EACH ROW EXECUTE FUNCTION maintain_sighting_aggregates();
