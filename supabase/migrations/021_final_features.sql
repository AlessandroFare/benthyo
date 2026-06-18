-- Migration 021: Final product features — cert OCR, GBIF/iNat sync, conservation, rental gear, photo search.

-- User preferences & expert role
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS gbif_export_opt_in BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS weekly_digest_opt_in BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS conservation_alerts_opt_in BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS taxonomy_expert BOOLEAN NOT NULL DEFAULT false;

-- Certification card records (OCR-assisted)
CREATE TABLE cert_card_records (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  operator_id         UUID REFERENCES operators(id) ON DELETE SET NULL,
  photo_url           TEXT,
  agency              cert_agency,
  cert_number         TEXT,
  cert_level          cert_level,
  instructor_name     TEXT,
  expiry_date         DATE,
  raw_ocr_text        TEXT,
  verified_at         TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_cert_card_records_user ON cert_card_records (user_id, created_at DESC);

-- Operator rental gear inventory
CREATE TABLE operator_rental_gear (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  operator_id           UUID NOT NULL REFERENCES operators(id) ON DELETE CASCADE,
  gear_type             gear_type NOT NULL DEFAULT 'other',
  label                 TEXT NOT NULL,
  serial_number         TEXT,
  qr_code               TEXT NOT NULL UNIQUE,
  last_service_date     DATE,
  service_interval_months INTEGER,
  dives_since_service   INTEGER NOT NULL DEFAULT 0,
  checked_out_to        UUID REFERENCES users(id) ON DELETE SET NULL,
  checked_out_at        TIMESTAMPTZ,
  is_active             BOOLEAN NOT NULL DEFAULT true,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_operator_rental_gear_operator ON operator_rental_gear (operator_id);

CREATE TRIGGER trg_operator_rental_gear_updated_at
  BEFORE UPDATE ON operator_rental_gear
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Photo fingerprint index (reverse image / duplicate detection)
CREATE TABLE sighting_photo_fingerprints (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sighting_id  UUID NOT NULL REFERENCES sightings(id) ON DELETE CASCADE,
  photo_url    TEXT NOT NULL,
  sha256       TEXT NOT NULL,
  species_id   UUID REFERENCES species(id) ON DELETE SET NULL,
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_photo_fingerprints_sha ON sighting_photo_fingerprints (sha256);
CREATE INDEX idx_photo_fingerprints_user ON sighting_photo_fingerprints (user_id);

-- iNaturalist push queue
CREATE TABLE inaturalist_push_queue (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sighting_id  UUID NOT NULL REFERENCES sightings(id) ON DELETE CASCADE,
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status       TEXT NOT NULL DEFAULT 'pending'
               CHECK (status IN ('pending', 'sent', 'failed')),
  inat_observation_id BIGINT,
  error_message TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  processed_at TIMESTAMPTZ,
  UNIQUE (sighting_id)
);

-- GBIF export batch log
CREATE TABLE gbif_export_batches (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  sighting_count INTEGER NOT NULL DEFAULT 0,
  status       TEXT NOT NULL DEFAULT 'completed',
  exported_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE sightings
  ADD COLUMN IF NOT EXISTS pushed_to_inat_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS gbif_exported_at TIMESTAMPTZ;

-- Depth milestone badges
INSERT INTO badges (code, name, description, criteria_type, criteria_value, tier)
VALUES
  ('depth-30', '30 Meter Club', 'Log a dive to 30m or deeper', 'max_depth', '{"depth_m":30}'::jsonb, 2),
  ('depth-40', '40 Meter Explorer', 'Log a dive to 40m or deeper', 'max_depth', '{"depth_m":40}'::jsonb, 3)
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  criteria_type = EXCLUDED.criteria_type,
  criteria_value = EXCLUDED.criteria_value,
  tier = EXCLUDED.tier;

-- Award max_depth badges after dive insert
CREATE OR REPLACE FUNCTION award_depth_badges()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  badge_row RECORD;
BEGIN
  FOR badge_row IN
    SELECT id, criteria_value FROM badges WHERE criteria_type = 'max_depth'
  LOOP
    IF NEW.max_depth_m >= (badge_row.criteria_value->>'depth_m')::numeric THEN
      INSERT INTO user_badges (user_id, badge_id, context_json)
      VALUES (NEW.user_id, badge_row.id, jsonb_build_object('dive_log_id', NEW.id, 'max_depth_m', NEW.max_depth_m))
      ON CONFLICT (user_id, badge_id) DO NOTHING;
    END IF;
  END LOOP;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_dive_logs_depth_badges
  AFTER INSERT ON dive_logs
  FOR EACH ROW EXECUTE FUNCTION award_depth_badges();

-- Conservation alerts: CR/EN species near user's recent dive regions.
-- Returns an empty array immediately if the user has not opted in
-- (users.conservation_alerts_opt_in = false). The opt-in is the
-- authoritative GDPR + deliverability check; we do not fall back to
-- "send anyway" anywhere.
CREATE OR REPLACE FUNCTION conservation_alerts_for_user(p_user_id UUID)
RETURNS JSONB
LANGUAGE sql STABLE AS $$
  WITH prefs AS (
    SELECT COALESCE(u.conservation_alerts_opt_in, true) AS opt_in
    FROM users u
    WHERE u.id = p_user_id
  ),
  user_regions AS (
    SELECT DISTINCT ds.country_code, ds.region
    FROM dive_logs dl
    JOIN dive_sites ds ON ds.id = dl.dive_site_id
    WHERE dl.user_id = p_user_id
      AND dl.dive_date >= (CURRENT_DATE - INTERVAL '365 days')
  ),
  alerts AS (
    SELECT sp.id, sp.scientific_name, sp.common_name,
           sp.conservation_status, ds.name AS site_name, ds.slug AS site_slug,
           s.observed_at
    FROM sightings s
    JOIN species sp ON sp.id = s.species_id
    JOIN dive_sites ds ON ds.id = s.dive_site_id
    CROSS JOIN prefs
    WHERE prefs.opt_in = true
      AND sp.conservation_status IN ('CR', 'EN')
      AND s.observed_at >= (now() - INTERVAL '90 days')
      AND EXISTS (
        SELECT 1 FROM user_regions ur
        WHERE ur.country_code = ds.country_code
           OR (ur.region IS NOT NULL AND ur.region = ds.region)
      )
    ORDER BY s.observed_at DESC
    LIMIT 20
  )
  SELECT COALESCE(jsonb_agg(to_jsonb(alerts)), '[]'::jsonb) FROM alerts;
$$;

GRANT EXECUTE ON FUNCTION conservation_alerts_for_user(UUID) TO authenticated;

-- RLS
ALTER TABLE cert_card_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE operator_rental_gear ENABLE ROW LEVEL SECURITY;
ALTER TABLE sighting_photo_fingerprints ENABLE ROW LEVEL SECURITY;
ALTER TABLE inaturalist_push_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE gbif_export_batches ENABLE ROW LEVEL SECURITY;

CREATE POLICY cert_cards_own ON cert_card_records
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE POLICY cert_cards_operator_read ON cert_card_records
  FOR SELECT USING (
    operator_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM operator_users ou
      WHERE ou.operator_id = cert_card_records.operator_id AND ou.user_id = auth.uid()
    )
  );

CREATE POLICY rental_gear_operator ON operator_rental_gear
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM operator_users ou
      WHERE ou.operator_id = operator_rental_gear.operator_id AND ou.user_id = auth.uid()
    )
  );

CREATE POLICY photo_fingerprints_read ON sighting_photo_fingerprints
  FOR SELECT USING (true);

CREATE POLICY photo_fingerprints_insert ON sighting_photo_fingerprints
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY inat_queue_own ON inaturalist_push_queue
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY gbif_batches_own ON gbif_export_batches
  FOR ALL USING (auth.uid() = user_id);