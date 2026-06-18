-- Migration 020: Close remaining Q1/Q2 MVP gaps — medical forms, API keys, payment links.

-- ---------------------------------------------------------------------------
-- RSTC-style medical questionnaire
-- ---------------------------------------------------------------------------
CREATE TABLE medical_form_templates (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  operator_id  UUID REFERENCES operators(id) ON DELETE CASCADE,
  title        TEXT NOT NULL DEFAULT 'Medical statement',
  schema       JSONB NOT NULL,
  version      INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
  is_active    BOOLEAN NOT NULL DEFAULT true,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_medical_templates_operator
  ON medical_form_templates (operator_id)
  WHERE is_active = true;

CREATE TABLE medical_form_submissions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  operator_id     UUID REFERENCES operators(id) ON DELETE SET NULL,
  trip_id         UUID REFERENCES trips(id) ON DELETE SET NULL,
  template_id     UUID NOT NULL REFERENCES medical_form_templates(id) ON DELETE RESTRICT,
  answers         JSONB NOT NULL,
  has_yes_answer  BOOLEAN NOT NULL DEFAULT false,
  signer_name     TEXT NOT NULL,
  signed_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_medical_submissions_user ON medical_form_submissions (user_id, signed_at DESC);
CREATE INDEX idx_medical_submissions_trip ON medical_form_submissions (trip_id) WHERE trip_id IS NOT NULL;

CREATE TRIGGER trg_medical_templates_updated_at
  BEFORE UPDATE ON medical_form_templates
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Default global RSTC-style template (operator_id NULL = platform default).
INSERT INTO medical_form_templates (operator_id, title, schema, is_active)
VALUES (
  NULL,
  'RSTC medical statement',
  '[
    {"id":"heart","text":"Heart or blood pressure problems?","type":"yes_no"},
    {"id":"lung","text":"Asthma, wheezing, or lung disease?","type":"yes_no"},
    {"id":"diabetes","text":"Diabetes?","type":"yes_no"},
    {"id":"seizure","text":"Seizures or blackouts?","type":"yes_no"},
    {"id":"surgery","text":"Surgery in the last 12 months?","type":"yes_no"},
    {"id":"pregnancy","text":"Currently pregnant?","type":"yes_no"}
  ]'::jsonb,
  true
);

-- ---------------------------------------------------------------------------
-- Public read API keys (data moat)
-- ---------------------------------------------------------------------------
CREATE TABLE api_keys (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  key_prefix   TEXT NOT NULL,
  key_hash     TEXT NOT NULL UNIQUE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_used_at TIMESTAMPTZ,
  revoked_at   TIMESTAMPTZ
);

CREATE INDEX idx_api_keys_user ON api_keys (user_id) WHERE revoked_at IS NULL;

-- ---------------------------------------------------------------------------
-- Operator payment links (Stripe URL or manual deposit link)
-- ---------------------------------------------------------------------------
CREATE TABLE operator_payment_links (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  operator_id           UUID NOT NULL REFERENCES operators(id) ON DELETE CASCADE,
  created_by            UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  amount_cents          INTEGER NOT NULL CHECK (amount_cents > 0),
  currency              TEXT NOT NULL DEFAULT 'eur',
  description           TEXT NOT NULL,
  payment_url           TEXT NOT NULL,
  customer_email        TEXT,
  paid_at               TIMESTAMPTZ,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_payment_links_operator ON operator_payment_links (operator_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- RPC: trip recap stats
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trip_recap(p_trip_id UUID)
RETURNS JSONB
LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'trip_id', t.id,
    'name', t.name,
    'start_date', t.start_date,
    'end_date', t.end_date,
    'region', t.region,
    'dive_count', (
      SELECT count(*)::integer
      FROM dive_logs dl
      JOIN trip_members tm ON tm.user_id = dl.user_id AND tm.trip_id = t.id
      WHERE dl.dive_date BETWEEN t.start_date AND t.end_date
    ),
    'species_count', (
      SELECT count(DISTINCT s.species_id)::integer
      FROM sightings s
      JOIN trip_members tm ON tm.user_id = s.user_id AND tm.trip_id = t.id
      WHERE s.observed_at::date BETWEEN t.start_date AND t.end_date
    ),
    'new_life_list', (
      SELECT count(*)::integer
      FROM user_life_list ull
      JOIN trip_members tm ON tm.user_id = ull.user_id AND tm.trip_id = t.id
      WHERE ull.first_seen_at::date BETWEEN t.start_date AND t.end_date
    ),
    'max_depth_m', (
      SELECT max(dl.max_depth_m)
      FROM dive_logs dl
      JOIN trip_members tm ON tm.user_id = dl.user_id AND tm.trip_id = t.id
      WHERE dl.dive_date BETWEEN t.start_date AND t.end_date
    )
  )
  FROM trips t
  WHERE t.id = p_trip_id;
$$;

GRANT EXECUTE ON FUNCTION trip_recap(UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
ALTER TABLE medical_form_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE medical_form_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE api_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE operator_payment_links ENABLE ROW LEVEL SECURITY;

CREATE POLICY medical_templates_read ON medical_form_templates
  FOR SELECT USING (is_active = true);

CREATE POLICY medical_submissions_own ON medical_form_submissions
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE POLICY medical_submissions_operator_read ON medical_form_submissions
  FOR SELECT USING (
    operator_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM operator_users ou
      WHERE ou.operator_id = medical_form_submissions.operator_id
        AND ou.user_id = auth.uid()
    )
  );

CREATE POLICY api_keys_own ON api_keys
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE POLICY payment_links_operator ON operator_payment_links
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM operator_users ou
      WHERE ou.operator_id = operator_payment_links.operator_id
        AND ou.user_id = auth.uid()
    )
  );

-- Enum extension: must commit before 021 uses the new value.
ALTER TYPE badge_criteria_type ADD VALUE IF NOT EXISTS 'max_depth';