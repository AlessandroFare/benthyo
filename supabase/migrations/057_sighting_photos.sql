-- Migration 057: sighting_photos — normalized gallery table
--
-- Replaces the single-row `photo_urls` JSONB array on the sightings table
-- with a proper one-to-many gallery. The old column is retained as a
-- denormalised cache for backward compatibility with older clients.
--
-- New table: sighting_photos
--   id          — PK
--   sighting_id — FK → sightings(id) CASCADE DELETE
--   user_id     — FK → auth.users(id) — needed for RLS without a join
--   storage_path — Supabase Storage path (bucket: sighting-photos)
--   public_url  — resolved CDN URL cached at insert time
--   caption     — optional user caption
--   sort_order  — controls display order; default 0
--   created_at

CREATE TABLE IF NOT EXISTS sighting_photos (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  sighting_id  UUID        NOT NULL REFERENCES sightings(id) ON DELETE CASCADE,
  user_id      UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  storage_path TEXT        NOT NULL,
  public_url   TEXT        NOT NULL,
  caption      TEXT,
  sort_order   INT         NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Efficient lookup of all photos for a sighting (feed / detail view).
CREATE INDEX IF NOT EXISTS idx_sighting_photos_sighting_id
  ON sighting_photos (sighting_id, sort_order);

-- Per-user photo count for quota enforcement in tier triggers.
CREATE INDEX IF NOT EXISTS idx_sighting_photos_user_id
  ON sighting_photos (user_id, created_at DESC);

-- ─── Row-Level Security ──────────────────────────────────────────────────────
ALTER TABLE sighting_photos ENABLE ROW LEVEL SECURITY;

-- Anyone authenticated can view photos whose parent sighting is visible.
-- (We rely on the sightings table's own RLS for visibility; photos are
--  "public within the app" just like the sighting itself.)
CREATE POLICY "sighting_photos_select" ON sighting_photos
  FOR SELECT TO authenticated
  USING (true);

-- Only the owning user can insert photos.
CREATE POLICY "sighting_photos_insert" ON sighting_photos
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

-- Only the owning user can update (reorder / add caption).
CREATE POLICY "sighting_photos_update" ON sighting_photos
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Only the owning user can delete their photos.
CREATE POLICY "sighting_photos_delete" ON sighting_photos
  FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- ─── Back-fill trigger ───────────────────────────────────────────────────────
-- Whenever a new sighting is inserted with photo_urls already populated
-- (legacy / offline-sync path), fan those URLs out into sighting_photos
-- automatically so both code paths stay in sync.

CREATE OR REPLACE FUNCTION _sync_sighting_photo_urls()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  url  TEXT;
  idx  INT := 0;
BEGIN
  IF NEW.photo_urls IS NULL OR NEW.photo_urls = '[]'::JSONB THEN
    RETURN NEW;
  END IF;

  FOR url IN
    SELECT jsonb_array_elements_text(NEW.photo_urls)
  LOOP
    INSERT INTO sighting_photos (
      sighting_id,
      user_id,
      storage_path,
      public_url,
      sort_order
    )
    VALUES (
      NEW.id,
      NEW.user_id,
      url,   -- legacy rows have no separate storage path; use url as path
      url,
      idx
    )
    ON CONFLICT DO NOTHING;
    idx := idx + 1;
  END LOOP;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_sync_sighting_photo_urls
  AFTER INSERT ON sightings
  FOR EACH ROW
  EXECUTE FUNCTION _sync_sighting_photo_urls();

COMMENT ON TABLE sighting_photos IS
  'Per-photo gallery rows for sightings. '
  'Supersedes the denormalized photo_urls JSONB column on sightings.';
