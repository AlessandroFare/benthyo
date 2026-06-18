-- Migration 006: Operators table.
-- B2B accounts. Each operator has a public profile (for the consumer
-- map) and a private dashboard (for analytics). Operators may be dive
-- centers, liveaboards, or resorts. Public listings include name,
-- slug, location, type, and website; everything else is operator-only.

CREATE TABLE operators (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name                 TEXT NOT NULL,
  slug                 TEXT NOT NULL UNIQUE,
  description          TEXT,
  website              TEXT,
  email                CITEXT,
  phone                TEXT,
  address              TEXT,
  location             GEOGRAPHY(POINT, 4326),
  country_code         CHAR(2),
  operator_type        operator_type NOT NULL,
  padi_store_id        TEXT,
  ssi_center_id        TEXT,
  subscription_tier    subscription_tier NOT NULL DEFAULT 'free',
  subscription_status  subscription_status NOT NULL DEFAULT 'trialing',
  metadata             JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT operators_slug_format CHECK (slug ~ '^[a-z0-9-]+$'),
  CONSTRAINT operators_email_format CHECK (
    email IS NULL OR email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
  )
);

CREATE INDEX idx_operators_slug ON operators (slug);
CREATE INDEX idx_operators_type ON operators (operator_type);
CREATE INDEX idx_operators_country ON operators (country_code);
CREATE INDEX idx_operators_location ON operators USING GIST (location);

CREATE TRIGGER trg_operators_updated_at
  BEFORE UPDATE ON operators
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE operators IS 'Dive centers, liveaboards, and resorts. Public profile + private dashboard.';

-- Operator membership: which users belong to which operators and with what role.
-- Composite primary key prevents duplicate memberships.
CREATE TABLE operator_users (
  operator_id  UUID NOT NULL REFERENCES operators(id) ON DELETE CASCADE,
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role         operator_role NOT NULL DEFAULT 'staff',
  invited_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted_at  TIMESTAMPTZ,

  PRIMARY KEY (operator_id, user_id)
);

CREATE INDEX idx_operator_users_user ON operator_users (user_id);
CREATE INDEX idx_operator_users_role ON operator_users (operator_id, role);

COMMENT ON TABLE operator_users IS 'Multi-tenant B2B membership; a user can belong to multiple operators.';

-- Many-to-many: which dive sites are operated by which operators.
-- is_primary marks the operator's main site at a given location (one per
-- site). Non-primary links mean "we also run trips there."
CREATE TABLE operator_dive_sites (
  operator_id  UUID NOT NULL REFERENCES operators(id) ON DELETE CASCADE,
  dive_site_id UUID NOT NULL REFERENCES dive_sites(id) ON DELETE CASCADE,
  is_primary   BOOLEAN NOT NULL DEFAULT FALSE,
  added_at     TIMESTAMPTZ NOT NULL DEFAULT now(),

  PRIMARY KEY (operator_id, dive_site_id)
);

CREATE INDEX idx_operator_dive_sites_site ON operator_dive_sites (dive_site_id);
CREATE INDEX idx_operator_dive_sites_primary ON operator_dive_sites (operator_id) WHERE is_primary;
