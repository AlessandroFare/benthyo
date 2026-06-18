-- CI-only Supabase `auth` shim.
--
-- On hosted Supabase the `auth` schema, `auth.users` table and the
-- auth.uid()/auth.role() helpers are provided by GoTrue + the platform.
-- The CI `rls` job runs against a bare postgis/postgis image, which has
-- none of these. Without them migration 003 (REFERENCES auth.users) and
-- migration 041 (auth.uid() in RLS policies) fail with
-- "schema \"auth\" does not exist".
--
-- This file is applied ONLY in CI, before the migrations. It is never part
-- of the migration set and is never run against a real database.

CREATE SCHEMA IF NOT EXISTS auth;

-- Minimal auth.users: only the id is referenced by application FKs.
CREATE TABLE IF NOT EXISTS auth.users (
  id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT
);

-- auth.uid(): the current request's user id. In CI it is driven by a GUC so
-- the RLS suite can impersonate users via `SET LOCAL request.jwt.claim.sub`.
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS UUID
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

-- auth.role(): mirrors the real helper. Defaults to the Postgres role name.
CREATE OR REPLACE FUNCTION auth.role()
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claim.role', true), ''),
    current_user
  )
$$;

-- Supabase PostgREST roles the migrations GRANT to / the suite SETs ROLE to.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN BYPASSRLS;
  END IF;
END$$;

GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;
GRANT anon, authenticated, service_role TO postgres;
