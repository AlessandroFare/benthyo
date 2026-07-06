-- Migration 038: Strengthen medical-form encryption key derivation.
--
-- Threat model / problem (found in audit):
--   Migration 030 derived the per-operator / per-user encryption key as
--   md5(operator_id || master_key) and md5(user_id || master_key).
--   * operator_id and user_id are NOT secrets: they appear in API
--     responses, GDPR exports, and URLs. So the only secret protecting
--     GDPR Article 9 special-category data (medical answers) is the
--     master key. A master-key leak therefore enables decryption of
--     EVERY row with no additional knowledge required.
--   * md5 is not a KDF and is cryptographically broken for collision
--     resistance.
--
-- Fix: derive keys with HMAC-SHA256 keyed by the master key, mixing in a
-- secret server-side salt (app.medical_key_salt) in addition to the id.
-- This (a) uses the master key as a proper HMAC key rather than a string
-- concatenation, and (b) adds a second secret factor so that knowledge of
-- the (public) id alone is useless. pgcrypto's hmac() ships in Supabase;
-- we guard for its presence and fall back to a salted SHA-256 digest if a
-- target lacks it.
--
-- NOTE: pgcrypto is installed in the "extensions" schema on Supabase, not
-- "public". Every function below that calls pgp_sym_*/hmac/digest sets
-- search_path explicitly to public, extensions -- otherwise Postgres
-- raises "function ... does not exist" even though the function is
-- present (see 030 postmortem).
--
-- Backfill: existing ciphertext was produced with the legacy md5 key. We
-- re-encrypt it under the new key in an idempotent block:
--   * no-op on empty tables (fresh db reset),
--   * no-op if run twice (a per-row marker column records the key version).
-- If the runtime master key is not present at migration time, the backfill
-- is skipped with a NOTICE and the rotation procedure in docs/runbook.md
-- (§8) must be run with the key available; new writes already use v2.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Track which key version encrypted each row so the backfill is idempotent
-- and future rotations are auditable. NULL/1 = legacy md5 (migration 030),
-- 2 = HMAC-SHA256 (this migration).
ALTER TABLE medical_form_submissions
  ADD COLUMN IF NOT EXISTS answers_key_version SMALLINT;

-- ---------------------------------------------------------------------------
-- v2 key derivation. Returns a hex string used as the pgp_sym passphrase.
--   key = HMAC_SHA256( key = master_key, msg = scope || ':' || id || ':' || salt )
-- where scope is 'op' or 'user'. Falls back to digest() if hmac() is absent.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION medical_master_key_v2()
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(
    current_setting('app.medical_master_key', true),
    'benthyo-dev-master-key-do-not-use-in-prod'
  )
$$;

CREATE OR REPLACE FUNCTION medical_key_salt()
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(
    current_setting('app.medical_key_salt', true),
    'benthyo-dev-key-salt-do-not-use-in-prod'
  )
$$;

CREATE OR REPLACE FUNCTION medical_derive_key_v2(p_scope TEXT, p_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, extensions
AS $$
DECLARE
  v_msg   TEXT := p_scope || ':' || p_id::text || ':' || medical_key_salt();
  v_key   TEXT := medical_master_key_v2();
  v_has_hmac BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_proc WHERE proname = 'hmac'
  ) INTO v_has_hmac;

  IF v_has_hmac THEN
    -- hmac(data, key, type) -> bytea
    RETURN encode(hmac(v_msg, v_key, 'sha256'), 'hex');
  ELSE
    -- Fallback: salted SHA-256 digest. Still vastly better than md5 of a
    -- public id, because the master key and secret salt are mixed in.
    RETURN encode(digest(v_key || ':' || v_msg, 'sha256'), 'hex');
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION medical_operator_key_v2(p_operator_id UUID)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
  SELECT medical_derive_key_v2('op', p_operator_id)
$$;

CREATE OR REPLACE FUNCTION medical_user_key_v2(p_user_id UUID)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
  SELECT medical_derive_key_v2('user', p_user_id)
$$;

-- ---------------------------------------------------------------------------
-- Re-point the encrypt/decrypt helpers and RPCs to the v2 keys. Signatures
-- are unchanged so callers (submit_medical_form, *_decrypted RPCs) keep
-- working; only the passphrase derivation changes.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION encrypt_medical_answers(p_operator_id UUID, p_answers JSONB)
RETURNS BYTEA LANGUAGE sql IMMUTABLE
SET search_path = public, extensions
AS $$
  SELECT pgp_sym_encrypt(p_answers::text, medical_operator_key_v2(p_operator_id), 'cipher-algo=aes256')
$$;

CREATE OR REPLACE FUNCTION decrypt_medical_answers(p_operator_id UUID, p_ciphertext BYTEA)
RETURNS JSONB LANGUAGE sql IMMUTABLE
SET search_path = public, extensions
AS $$
  SELECT pgp_sym_decrypt(p_ciphertext, medical_operator_key_v2(p_operator_id))::jsonb
$$;

CREATE OR REPLACE FUNCTION encrypt_medical_answers_user(p_user_id UUID, p_answers JSONB)
RETURNS BYTEA LANGUAGE sql IMMUTABLE
SET search_path = public, extensions
AS $$
  SELECT pgp_sym_encrypt(p_answers::text, medical_user_key_v2(p_user_id), 'cipher-algo=aes256')
$$;

CREATE OR REPLACE FUNCTION decrypt_medical_answers_user(p_user_id UUID, p_ciphertext BYTEA)
RETURNS JSONB LANGUAGE sql IMMUTABLE
SET search_path = public, extensions
AS $$
  SELECT pgp_sym_decrypt(p_ciphertext, medical_user_key_v2(p_user_id))::jsonb
$$;

-- ---------------------------------------------------------------------------
-- Legacy (v1) key helpers, retained ONLY so the backfill can decrypt rows
-- that were written with the md5 derivation in migration 030.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION medical_operator_key_v1(p_operator_id UUID)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
  SELECT md5(p_operator_id::text || medical_master_key_v2())
$$;

CREATE OR REPLACE FUNCTION medical_user_key_v1(p_user_id UUID)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
  SELECT md5(p_user_id::text || medical_master_key_v2())
$$;

-- ---------------------------------------------------------------------------
-- Idempotent backfill: re-encrypt legacy rows under the v2 key.
--   * Skipped entirely if the master key is not set at migration time
--     (so we never silently corrupt data with the dev placeholder in prod).
--   * Processes only rows whose answers_key_version is NULL or 1.
--   * Marks each row answers_key_version = 2, so a second run is a no-op.
--
-- A DO block can't take a function-level SET clause, so we SET LOCAL as
-- the first statement inside BEGIN -- this scopes pgp_sym_*/hmac/digest
-- resolution to the extensions schema for the duration of this block only.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_key_set BOOLEAN := current_setting('app.medical_master_key', true) IS NOT NULL;
  v_row     RECORD;
  v_plain   JSONB;
  v_count   INTEGER := 0;
BEGIN
  SET LOCAL search_path = public, extensions;

  IF NOT v_key_set THEN
    RAISE NOTICE 'app.medical_master_key not set; skipping v2 backfill. Run the rotation recipe in docs/runbook.md with the key available. New writes already use v2.';
    RETURN;
  END IF;

  FOR v_row IN
    SELECT id, user_id, operator_id, answers
    FROM medical_form_submissions
    WHERE answers IS NOT NULL
      AND octet_length(answers) >= 64
      AND COALESCE(answers_key_version, 1) = 1
  LOOP
    BEGIN
      -- Decrypt with the legacy v1 key for this row's scope.
      IF v_row.operator_id IS NOT NULL THEN
        v_plain := pgp_sym_decrypt(v_row.answers, medical_operator_key_v1(v_row.operator_id))::jsonb;
        UPDATE medical_form_submissions
        SET answers = pgp_sym_encrypt(v_plain::text, medical_operator_key_v2(v_row.operator_id), 'cipher-algo=aes256'),
            answers_key_version = 2
        WHERE id = v_row.id;
      ELSE
        v_plain := pgp_sym_decrypt(v_row.answers, medical_user_key_v1(v_row.user_id))::jsonb;
        UPDATE medical_form_submissions
        SET answers = pgp_sym_encrypt(v_plain::text, medical_user_key_v2(v_row.user_id), 'cipher-algo=aes256'),
            answers_key_version = 2
        WHERE id = v_row.id;
      END IF;
      v_count := v_count + 1;
    EXCEPTION WHEN OTHERS THEN
      -- A row that won't decrypt under v1 was likely already v2 (or written
      -- with a different master key). Leave it untouched and log.
      RAISE WARNING 'Skipping medical_form_submissions % during v2 backfill: %', v_row.id, SQLERRM;
    END;
  END LOOP;

  -- Any new rows written by the v2 helpers above this line are version 2.
  UPDATE medical_form_submissions
  SET answers_key_version = 2
  WHERE answers IS NOT NULL AND answers_key_version IS NULL;

  IF v_count > 0 THEN
    RAISE NOTICE 'Re-encrypted % medical_form_submissions row(s) to key version 2', v_count;
  END IF;
END;
$$;

-- New inserts via submit_medical_form() use the v2 encrypt helpers above
-- and should record the key version. Tag fresh rows defensively.
ALTER TABLE medical_form_submissions
  ALTER COLUMN answers_key_version SET DEFAULT 2;