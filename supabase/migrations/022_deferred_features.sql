-- Migration 022: Previously deferred features — social, BLE devices, marketplace, pgvector search.

CREATE EXTENSION IF NOT EXISTS vector;

-- ---------------------------------------------------------------------------
-- Buddy DM conversations
-- ---------------------------------------------------------------------------
CREATE TABLE buddy_conversations (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  participant_a    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  participant_b    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  last_message_at  TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT buddy_conv_distinct CHECK (participant_a <> participant_b),
  CONSTRAINT buddy_conv_order CHECK (participant_a < participant_b),
  UNIQUE (participant_a, participant_b)
);

CREATE INDEX idx_buddy_conversations_a ON buddy_conversations (participant_a, last_message_at DESC NULLS LAST);
CREATE INDEX idx_buddy_conversations_b ON buddy_conversations (participant_b, last_message_at DESC NULLS LAST);

CREATE TABLE buddy_messages (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id  UUID NOT NULL REFERENCES buddy_conversations(id) ON DELETE CASCADE,
  sender_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  body             TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 2000),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_buddy_messages_conv ON buddy_messages (conversation_id, created_at DESC);

CREATE OR REPLACE FUNCTION touch_buddy_conversation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  UPDATE buddy_conversations
  SET last_message_at = NEW.created_at
  WHERE id = NEW.conversation_id;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_buddy_messages_touch_conv
  AFTER INSERT ON buddy_messages
  FOR EACH ROW EXECUTE FUNCTION touch_buddy_conversation();

-- ---------------------------------------------------------------------------
-- Social feed (dive highlights)
-- ---------------------------------------------------------------------------
CREATE TABLE social_feed_posts (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  dive_log_id   UUID REFERENCES dive_logs(id) ON DELETE SET NULL,
  dive_site_id  UUID REFERENCES dive_sites(id) ON DELETE SET NULL,
  body          TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 1000),
  photo_url     TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_social_feed_posts_created ON social_feed_posts (created_at DESC);
CREATE INDEX idx_social_feed_posts_user ON social_feed_posts (user_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- BLE dive computer pairing registry
-- ---------------------------------------------------------------------------
CREATE TABLE dive_computer_devices (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_name   TEXT NOT NULL,
  device_uuid   TEXT NOT NULL,
  manufacturer  TEXT,
  model         TEXT,
  last_sync_at  TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, device_uuid)
);

CREATE INDEX idx_dive_computer_devices_user ON dive_computer_devices (user_id);

-- ---------------------------------------------------------------------------
-- Operator marketplace listings
-- ---------------------------------------------------------------------------
CREATE TYPE marketplace_listing_type AS ENUM (
  'course', 'fun_dive', 'liveaboard', 'gear_rental', 'certification'
);

CREATE TABLE operator_marketplace_listings (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  operator_id   UUID NOT NULL REFERENCES operators(id) ON DELETE CASCADE,
  listing_type  marketplace_listing_type NOT NULL DEFAULT 'fun_dive',
  title         TEXT NOT NULL,
  description   TEXT NOT NULL,
  price_cents   INTEGER NOT NULL CHECK (price_cents >= 0),
  currency      CHAR(3) NOT NULL DEFAULT 'EUR',
  region        TEXT,
  is_active     BOOLEAN NOT NULL DEFAULT true,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_marketplace_listings_active ON operator_marketplace_listings (is_active, created_at DESC)
  WHERE is_active = true;

CREATE TRIGGER trg_marketplace_listings_updated_at
  BEFORE UPDATE ON operator_marketplace_listings
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------------------
-- CLIP / pgvector photo embeddings
-- ---------------------------------------------------------------------------
ALTER TABLE sighting_photo_fingerprints
  ADD COLUMN IF NOT EXISTS clip_embedding vector(512);

CREATE INDEX IF NOT EXISTS idx_photo_fingerprints_clip_hnsw
  ON sighting_photo_fingerprints
  USING hnsw (clip_embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

CREATE OR REPLACE FUNCTION match_photo_embeddings(
  query_embedding vector(512),
  match_limit INTEGER DEFAULT 10
)
RETURNS TABLE (
  fingerprint_id UUID,
  sighting_id UUID,
  photo_url TEXT,
  species_id UUID,
  similarity FLOAT
)
LANGUAGE sql STABLE AS $$
  SELECT
    spf.id,
    spf.sighting_id,
    spf.photo_url,
    spf.species_id,
    1 - (spf.clip_embedding <=> query_embedding) AS similarity
  FROM sighting_photo_fingerprints spf
  WHERE spf.clip_embedding IS NOT NULL
  ORDER BY spf.clip_embedding <=> query_embedding
  LIMIT LEAST(match_limit, 50);
$$;

GRANT EXECUTE ON FUNCTION match_photo_embeddings(vector(512), INTEGER) TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
ALTER TABLE buddy_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE buddy_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE social_feed_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE dive_computer_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE operator_marketplace_listings ENABLE ROW LEVEL SECURITY;

CREATE POLICY buddy_conversations_participant ON buddy_conversations
  FOR SELECT USING (
    auth.uid() = participant_a OR auth.uid() = participant_b
  );

CREATE POLICY buddy_conversations_insert ON buddy_conversations
  FOR INSERT WITH CHECK (
    auth.uid() = participant_a OR auth.uid() = participant_b
  );

CREATE POLICY buddy_messages_participant ON buddy_messages
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM buddy_conversations c
      WHERE c.id = conversation_id
        AND (c.participant_a = auth.uid() OR c.participant_b = auth.uid())
    )
  );

CREATE POLICY buddy_messages_insert ON buddy_messages
  FOR INSERT WITH CHECK (
    sender_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM buddy_conversations c
      WHERE c.id = conversation_id
        AND (c.participant_a = auth.uid() OR c.participant_b = auth.uid())
    )
  );

CREATE POLICY social_feed_read ON social_feed_posts
  FOR SELECT USING (true);

CREATE POLICY social_feed_insert ON social_feed_posts
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY social_feed_delete ON social_feed_posts
  FOR DELETE USING (auth.uid() = user_id);

CREATE POLICY dive_computer_devices_own ON dive_computer_devices
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE POLICY marketplace_listings_public_read ON operator_marketplace_listings
  FOR SELECT USING (is_active = true);

CREATE POLICY marketplace_listings_operator_write ON operator_marketplace_listings
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM operator_users ou
      WHERE ou.operator_id = operator_marketplace_listings.operator_id
        AND ou.user_id = auth.uid()
    )
  );
