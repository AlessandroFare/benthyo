-- Migration 010: Badges.
-- Badges are static definitions; user_badges is the per-user join table
-- recording when a user earned a given badge. criteria_json holds the
-- shape of the criteria (e.g. {"count": 10} for species_count badges,
-- {"regions": ["mediterranean"]} for regional badges).

CREATE TABLE badges (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code            TEXT NOT NULL UNIQUE,
  name            TEXT NOT NULL,
  description     TEXT NOT NULL,
  icon_url        TEXT,
  criteria_type   badge_criteria_type NOT NULL,
  criteria_value  JSONB NOT NULL DEFAULT '{}'::jsonb,
  -- Tier: 1 = bronze, 2 = silver, 3 = gold, used to color the badge UI.
  tier            SMALLINT NOT NULL DEFAULT 1 CHECK (tier BETWEEN 1 AND 3),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_badges_criteria_type ON badges (criteria_type);

COMMENT ON TABLE badges IS 'Static badge catalog. Awarded by the on-sighting-created Edge Function.';

CREATE TABLE user_badges (
  user_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  badge_id       UUID NOT NULL REFERENCES badges(id) ON DELETE CASCADE,
  earned_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  context_json   JSONB NOT NULL DEFAULT '{}'::jsonb,

  PRIMARY KEY (user_id, badge_id)
);

CREATE INDEX idx_user_badges_user ON user_badges (user_id, earned_at DESC);
CREATE INDEX idx_user_badges_badge ON user_badges (badge_id);

COMMENT ON TABLE user_badges IS 'Badges a user has earned. Awarded by the on-sighting-created trigger.';
