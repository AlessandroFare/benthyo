-- Migration 007: Dive logs table.
-- One row per logged dive. Optional linkage to an operator means the
-- dive was done through that operator (booking, charter, etc.).
-- tank fields are nullable because free divers and snorkelers log here
-- too and won't have tank data.

CREATE TABLE dive_logs (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  dive_site_id           UUID REFERENCES dive_sites(id) ON DELETE SET NULL,
  operator_id            UUID REFERENCES operators(id) ON DELETE SET NULL,
  dive_date              DATE NOT NULL,
  dive_number            INTEGER,  -- user's own sequential counter, optional
  entry_time             TIMESTAMPTZ,
  exit_time              TIMESTAMPTZ,
  max_depth_m            NUMERIC(5, 1) NOT NULL CHECK (max_depth_m >= 0),
  avg_depth_m            NUMERIC(5, 1) CHECK (avg_depth_m >= 0),
  duration_min           INTEGER NOT NULL CHECK (duration_min > 0),
  water_temp_surface_c   NUMERIC(4, 1),
  water_temp_bottom_c    NUMERIC(4, 1),
  visibility_m           NUMERIC(4, 1),
  current_strength       current_strength,
  tank_start_bar         NUMERIC(5, 1),
  tank_end_bar           NUMERIC(5, 1),
  tank_size_l            NUMERIC(4, 1),
  gas_mix                gas_mix NOT NULL DEFAULT 'air',
  buddy_name             TEXT,
  notes                  TEXT,
  rating                 SMALLINT CHECK (rating BETWEEN 1 AND 5),
  -- sync tracking: when the log was last uploaded from the mobile client.
  -- used to detect stale offline records.
  synced_at              TIMESTAMPTZ,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT dive_logs_max_avg_depth CHECK (avg_depth_m IS NULL OR avg_depth_m <= max_depth_m),
  CONSTRAINT dive_logs_tank_order CHECK (
    tank_start_bar IS NULL OR tank_end_bar IS NULL OR tank_end_bar <= tank_start_bar
  ),
  CONSTRAINT dive_logs_dive_date_not_future CHECK (dive_date <= CURRENT_DATE)
);

CREATE INDEX idx_dive_logs_user_date ON dive_logs (user_id, dive_date DESC);
CREATE INDEX idx_dive_logs_site ON dive_logs (dive_site_id);
CREATE INDEX idx_dive_logs_operator ON dive_logs (operator_id) WHERE operator_id IS NOT NULL;
CREATE INDEX idx_dive_logs_date ON dive_logs (dive_date DESC);

CREATE TRIGGER trg_dive_logs_updated_at
  BEFORE UPDATE ON dive_logs
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE dive_logs IS 'User-recorded dive logs. Offline-first design: client may write many before sync.';

-- Trigger: when a new dive log is inserted, bump the cached
-- total_dives counter on the user profile. Decremented on delete.
CREATE OR REPLACE FUNCTION dive_logs_count_update()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE users SET total_dives = total_dives + 1 WHERE id = NEW.user_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE users SET total_dives = GREATEST(0, total_dives - 1) WHERE id = OLD.user_id;
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_dive_logs_count
  AFTER INSERT OR DELETE ON dive_logs
  FOR EACH ROW EXECUTE FUNCTION dive_logs_count_update();
