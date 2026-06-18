-- Migration 013: Storage bucket for photos.
-- We declare the bucket and its RLS policies in a migration so that
-- `supabase db reset` produces a fully-configured environment.
-- The actual photo objects are uploaded to Cloudflare R2 (see
-- apps/api/src/modules/media); the bucket here exists for
-- consistency in case we ever fall back to Supabase Storage.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'sighting-photos',
  'sighting-photos',
  true,
  10485760,  -- 10 MB per file
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/heic']
)
ON CONFLICT (id) DO NOTHING;

-- Policy: anyone can read public photos.
CREATE POLICY "sighting_photos_public_read" ON storage.objects
  FOR SELECT USING (bucket_id = 'sighting-photos');

-- Policy: authenticated users can upload to their own folder.
-- Folder convention: sightings/{user_id}/{filename}
CREATE POLICY "sighting_photos_user_upload" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'sighting-photos'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[1] = 'sightings'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );

-- Policy: users can delete their own photos.
CREATE POLICY "sighting_photos_user_delete" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'sighting-photos'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );
