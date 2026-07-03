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
-- raw_user_meta_data / instance_id / aud / role are included because:
--   - migration 003's handle_new_auth_user trigger reads NEW.raw_user_meta_data
--   - the RLS suite (supabase/tests/rls.sql) inserts auth.users rows with
--     id, instance_id, aud, role, email, raw_user_meta_data (matching the
--     real Supabase auth.users shape).
CREATE TABLE IF NOT EXISTS auth.users (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  instance_id        UUID,
  aud                TEXT,
  role               TEXT,
  email              TEXT,
  raw_user_meta_data JSONB NOT NULL DEFAULT '{}'::jsonb
);

-- auth.uid(): the current request's user id. Matches the real Supabase
-- helper, which extracts `sub` from the `request.jwt.claims` JSON GUC. The
-- RLS suite impersonates users via
--   SET LOCAL request.jwt.claims = '{"sub":"..."}';
-- A `request.jwt.claim.sub` scalar GUC is also honoured as a fallback.
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS UUID
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub',
    NULLIF(current_setting('request.jwt.claim.sub', true), '')
  )::uuid
$$;

-- auth.role(): mirrors the real helper. Reads role from the claims JSON,
-- then a scalar GUC, then falls back to the Postgres role name.
CREATE OR REPLACE FUNCTION auth.role()
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    NULLIF(current_setting('request.jwt.claim.role', true), ''),
    current_user
  )
$$;

-- auth.jwt(): mirrors the real Supabase helper. Returns the current request's
-- JWT claims as JSONB. Migrations 033/034 read app_metadata from it
-- (e.g. is_admin). The RLS suite sets request.jwt.claims; return '{}' when
-- unset so the function is safe to call outside a request context.
CREATE OR REPLACE FUNCTION auth.jwt()
RETURNS JSONB
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb,
    '{}'::jsonb
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

-- ---------------------------------------------------------------------------
-- Minimal Supabase `storage` shim (migration 013 inserts into storage.buckets).
-- ---------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS storage;

CREATE TABLE IF NOT EXISTS storage.buckets (
  id                   TEXT PRIMARY KEY,
  name                 TEXT NOT NULL,
  owner                UUID,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  public               BOOLEAN NOT NULL DEFAULT false,
  avif_autodetection   BOOLEAN NOT NULL DEFAULT false,
  file_size_limit      BIGINT,
  allowed_mime_types   TEXT[]
);

CREATE TABLE IF NOT EXISTS storage.objects (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bucket_id          TEXT REFERENCES storage.buckets(id),
  name               TEXT,
  owner              UUID,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_accessed_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  metadata           JSONB,
  path_tokens        TEXT[],
  version            TEXT,
  user_metadata      JSONB
);

CREATE OR REPLACE FUNCTION storage.foldername(name TEXT)
RETURNS TEXT[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT string_to_array(name, '/');
$$;

ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

GRANT USAGE ON SCHEMA storage TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA storage TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Minimal Supabase Realtime publication shim. Hosted Supabase pre-creates the
-- `supabase_realtime` publication; the bare postgis CI image does not, so
-- migration 023 (`ALTER PUBLICATION supabase_realtime ADD TABLE buddy_messages`)
-- fails without this. FOR ALL TABLES mirrors the hosted default and is
-- harmless because the CI suite never asserts on replication.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    -- Empty publication (NOT FOR ALL TABLES): hosted Supabase creates it
    -- empty so migrations can ALTER PUBLICATION ... ADD TABLE. A FOR ALL
    -- TABLES publication rejects ADD TABLE, which would break migration 023.
    CREATE PUBLICATION supabase_realtime;
  END IF;
END$$;
