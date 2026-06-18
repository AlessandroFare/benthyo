-- Migration 041: Daily roster / trip scheduling for dive centers.
--
-- The #1 daily B2B job is "who is diving today, on which boat, with which
-- guide." This adds the minimal schema to power a dashboard "Today" view:
--   * operator_boats         — the center's vessels/groups
--   * operator_trip_schedule — a scheduled trip (date, time, site, boat, guide)
--   * trip_roster_entries    — customers assigned to a scheduled trip
-- Plus an operator_today_roster() RPC for the landing page.
--
-- All tables are RLS-protected: operator members read; owner/admin write.

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'trip_schedule_status') THEN
    CREATE TYPE trip_schedule_status AS ENUM ('planned', 'confirmed', 'departed', 'completed', 'cancelled');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'roster_entry_status') THEN
    CREATE TYPE roster_entry_status AS ENUM ('booked', 'checked_in', 'waiver_ok', 'no_show', 'cancelled');
  END IF;
END$$;

-- ---------------------------------------------------------------------------
-- operator_boats
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS operator_boats (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  operator_id UUID NOT NULL REFERENCES operators(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  capacity    SMALLINT NOT NULL DEFAULT 12 CHECK (capacity > 0),
  is_active   BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_operator_boats_operator ON operator_boats(operator_id);

-- ---------------------------------------------------------------------------
-- operator_trip_schedule
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS operator_trip_schedule (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  operator_id   UUID NOT NULL REFERENCES operators(id) ON DELETE CASCADE,
  trip_date     DATE NOT NULL,
  depart_at     TIMESTAMPTZ,
  dive_site_id  UUID REFERENCES dive_sites(id) ON DELETE SET NULL,
  site_label    TEXT,                       -- free text when no catalog site
  boat_id       UUID REFERENCES operator_boats(id) ON DELETE SET NULL,
  guide_id      UUID REFERENCES users(id) ON DELETE SET NULL,
  status        trip_schedule_status NOT NULL DEFAULT 'planned',
  notes         TEXT,
  created_by    UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_trip_schedule_operator_date
  ON operator_trip_schedule(operator_id, trip_date);

-- ---------------------------------------------------------------------------
-- trip_roster_entries
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS trip_roster_entries (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id     UUID NOT NULL REFERENCES operator_trip_schedule(id) ON DELETE CASCADE,
  operator_id UUID NOT NULL REFERENCES operators(id) ON DELETE CASCADE,
  -- A roster entry is either a known platform user (customer) or a walk-in
  -- captured by name only.
  customer_id UUID REFERENCES users(id) ON DELETE SET NULL,
  guest_name  TEXT,
  status      roster_entry_status NOT NULL DEFAULT 'booked',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (customer_id IS NOT NULL OR guest_name IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS idx_roster_entries_trip ON trip_roster_entries(trip_id);

-- ---------------------------------------------------------------------------
-- RLS: operator members read; owner/admin write.
-- ---------------------------------------------------------------------------
ALTER TABLE operator_boats          ENABLE ROW LEVEL SECURITY;
ALTER TABLE operator_trip_schedule  ENABLE ROW LEVEL SECURITY;
ALTER TABLE trip_roster_entries     ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION is_operator_member(p_operator_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM operator_users ou
    WHERE ou.operator_id = p_operator_id AND ou.user_id = auth.uid()
  )
$$;

CREATE OR REPLACE FUNCTION is_operator_admin(p_operator_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM operator_users ou
    WHERE ou.operator_id = p_operator_id AND ou.user_id = auth.uid()
      AND ou.role IN ('owner', 'admin')
  )
$$;

-- boats
CREATE POLICY operator_boats_read ON operator_boats
  FOR SELECT USING (is_operator_member(operator_id));
CREATE POLICY operator_boats_write ON operator_boats
  FOR ALL USING (is_operator_admin(operator_id))
  WITH CHECK (is_operator_admin(operator_id));

-- schedule
CREATE POLICY trip_schedule_read ON operator_trip_schedule
  FOR SELECT USING (is_operator_member(operator_id));
CREATE POLICY trip_schedule_write ON operator_trip_schedule
  FOR ALL USING (is_operator_admin(operator_id))
  WITH CHECK (is_operator_admin(operator_id));

-- roster
CREATE POLICY roster_entries_read ON trip_roster_entries
  FOR SELECT USING (is_operator_member(operator_id));
CREATE POLICY roster_entries_write ON trip_roster_entries
  FOR ALL USING (is_operator_admin(operator_id))
  WITH CHECK (is_operator_admin(operator_id));

-- ---------------------------------------------------------------------------
-- operator_today_roster(): today's trips for the caller's operator with
-- boat, guide, site, and counts. Used by the dashboard "Today" landing page.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION operator_today_roster(
  p_operator_id UUID,
  p_date        DATE DEFAULT current_date
)
RETURNS TABLE (
  trip_id        UUID,
  trip_date      DATE,
  depart_at      TIMESTAMPTZ,
  site_name      TEXT,
  boat_name      TEXT,
  boat_capacity  SMALLINT,
  guide_name     TEXT,
  status         trip_schedule_status,
  booked_count   BIGINT,
  checked_in_count BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    t.id,
    t.trip_date,
    t.depart_at,
    COALESCE(ds.name, t.site_label) AS site_name,
    b.name AS boat_name,
    b.capacity AS boat_capacity,
    g.display_name AS guide_name,
    t.status,
    COUNT(r.id) FILTER (WHERE r.status <> 'cancelled') AS booked_count,
    COUNT(r.id) FILTER (WHERE r.status IN ('checked_in','waiver_ok')) AS checked_in_count
  FROM operator_trip_schedule t
  LEFT JOIN dive_sites ds      ON ds.id = t.dive_site_id
  LEFT JOIN operator_boats b   ON b.id = t.boat_id
  LEFT JOIN users g            ON g.id = t.guide_id
  LEFT JOIN trip_roster_entries r ON r.trip_id = t.id
  WHERE t.operator_id = p_operator_id
    AND t.trip_date = p_date
    AND is_operator_member(p_operator_id)  -- authz inside the definer fn
  GROUP BY t.id, ds.name, b.name, b.capacity, g.display_name
  ORDER BY t.depart_at NULLS LAST, t.created_at;
$$;

GRANT EXECUTE ON FUNCTION operator_today_roster(UUID, DATE) TO authenticated;
