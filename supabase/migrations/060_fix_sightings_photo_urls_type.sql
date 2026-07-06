-- Migration 060: fix photo_urls type TEXT[] → JSONB
--
-- The trigger _sync_sighting_photo_urls() (migration 057) treats
-- photo_urls as JSONB, but the column was created as TEXT[] in migration 008.
-- This mismatch causes ETL upserts to fail with
-- "operator does not exist: text[] = jsonb" because the Supabase JS client
-- sends photo_urls as a JSON array (jsonb) but the column expects text[].

ALTER TABLE sightings
  ALTER COLUMN photo_urls DROP DEFAULT,
  ALTER COLUMN photo_urls SET DATA TYPE JSONB USING to_jsonb(photo_urls),
  ALTER COLUMN photo_urls SET DEFAULT '[]'::JSONB;
