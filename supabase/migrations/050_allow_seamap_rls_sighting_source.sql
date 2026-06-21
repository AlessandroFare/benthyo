-- Migration 050: allow 'seamap' and 'rls' as sighting sources.
--
-- The seamap and rls ETL sources (migration-era 047/round 2) write
-- sightings.source = 'seamap' / 'rls', but sightings_source_check only
-- permitted ('user','gbif','obis','inaturalist','manual'). Any successful
-- fetch from those sources would have failed the check constraint on insert.
-- This widens the allow-list. Additive; no data rewrite needed.

ALTER TABLE sightings DROP CONSTRAINT IF EXISTS sightings_source_check;
ALTER TABLE sightings ADD CONSTRAINT sightings_source_check
  CHECK (source = ANY (ARRAY[
    'user'::text,
    'gbif'::text,
    'obis'::text,
    'seamap'::text,
    'rls'::text,
    'inaturalist'::text,
    'manual'::text
  ]));
