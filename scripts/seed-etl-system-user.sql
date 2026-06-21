-- Seed a dedicated system user for ETL occurrence imports.
--
-- Occurrence-based ETL sources (obis, seamap, rls, gbif) write
-- sightings.user_id = ETL_SYSTEM_USER_ID. public.users.id is a FK to
-- auth.users(id), so the system user must exist in BOTH tables. Run this once
-- against the target database, then set ETL_SYSTEM_USER_ID to the printed id.
--
--   docker exec -i supabase_db_oceanlog psql -U postgres -d postgres \
--     < scripts/seed-etl-system-user.sql
--
-- Idempotent: safe to re-run.

DO $$
DECLARE
  v_id UUID := '00000000-0000-0000-0000-0000000e7100';  -- stable "etl" id
BEGIN
  INSERT INTO auth.users (id, instance_id, aud, role, email, created_at, updated_at)
  VALUES (
    v_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'etl-system@oceanlog.internal',
    now(),
    now()
  )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.users (id, username, full_name)
  VALUES (v_id, 'etl_system', 'OceanLog Data Import')
  ON CONFLICT (id) DO NOTHING;

  RAISE NOTICE 'ETL system user id: %', v_id;
END $$;
