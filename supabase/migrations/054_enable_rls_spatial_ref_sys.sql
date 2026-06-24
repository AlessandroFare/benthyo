-- Enable Row-Level Security on the public.spatial_ref_sys table.
-- This table is created by the PostGIS extension and contains public
-- EPSG coordinate-reference metadata; only SELECT access is needed.
-- Supabase flags rls_disabled_in_public as a high-severity alert.

ALTER TABLE public.spatial_ref_sys ENABLE ROW LEVEL SECURITY;

-- Allow all roles (anon + authenticated) to read spatial reference data.
CREATE POLICY "spatial_ref_sys public read"
  ON public.spatial_ref_sys
  FOR SELECT
  USING (true);
