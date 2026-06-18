-- Migration 003: Users table.
-- Extends Supabase's built-in auth.users with application-specific profile data.
-- The id is the same UUID as auth.users.id (foreign key with cascade delete
-- so removing an auth account removes the public profile).

CREATE TABLE users (
  id                   UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username             CITEXT NOT NULL UNIQUE,
  full_name            TEXT,
  avatar_url           TEXT,
  bio                  TEXT,
  certification_level  cert_level DEFAULT 'OW' NOT NULL,
  certification_agency cert_agency DEFAULT 'PADI' NOT NULL,
  total_dives          INTEGER NOT NULL DEFAULT 0 CHECK (total_dives >= 0),
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Username constraints: 3-30 chars, alphanum + underscore + dot + hyphen.
  CONSTRAINT users_username_length CHECK (char_length(username) BETWEEN 3 AND 30),
  CONSTRAINT users_username_format CHECK (username ~ '^[a-zA-Z0-9_.-]+$')
);

CREATE INDEX idx_users_username ON users (username);
CREATE INDEX idx_users_agency_level ON users (certification_agency, certification_level);

COMMENT ON TABLE users IS 'Application-level user profile, 1:1 with auth.users.';
COMMENT ON COLUMN users.username IS 'Unique handle, case-insensitive (CITEXT).';
COMMENT ON COLUMN users.total_dives IS 'Cached count, updated when dive_logs are inserted.';

-- Trigger: keep updated_at fresh on every UPDATE.
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Trigger: when a new auth.users row is created, automatically
-- create a public.users row with a default username.
CREATE OR REPLACE FUNCTION handle_new_auth_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.users (id, username, full_name, avatar_url)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'username', 'user_' || substring(NEW.id::text, 1, 8)),
    NEW.raw_user_meta_data->>'full_name',
    NEW.raw_user_meta_data->>'avatar_url'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_auth_user();
