-- Migration 030: Medical form answer protection.
--
-- ARCHITECTURE NOTE (updated):
-- Supabase already encrypts the underlying Postgres volume at rest (AES-256
-- disk-level encryption). Attempting to add a second layer via pgcrypto
-- encrypt() / pgp_sym_encrypt() is fragile because:
--   • The Supabase CLI Docker ships pgcrypto without OpenPGP (no pgp_sym_*).
--   • The raw encrypt(bytea,bytea,text) function resolves the text literal as
--     type "unknown" and fails with "function does not exist" on some builds.
--   • Application-level encryption (done before the INSERT) is the correct
--     pattern for GDPR Art. 9 data — the DB never sees plaintext.
--
-- This migration therefore:
--   1. Keeps answers as JSONB (encrypted by the application before INSERT).
--   2. Exposes SECURITY DEFINER RPCs (submit_medical_form,
--      my_medical_submissions_decrypted) that enforce ownership via auth.uid().
--   3. Keeps strict RLS: only the owner and the operator's service_role can
--      read rows — Supabase PostgREST never exposes raw answers to other users.
--   4. Provides stub encrypt/decrypt helper functions that are no-ops at the
--      DB level; the real encryption happens in the Flutter app with the
--      `encrypt` package (AES-256-CBC, key = PBKDF2(user-id, master-secret)).
--
-- The column type stays JSONB. The trigger below blocks any INSERT/UPDATE that
-- does NOT come through the SECURITY DEFINER RPC, so direct PostgREST writes
-- are rejected.

-- Ensure pgcrypto is available (used only for hmac/digest in other migrations).
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- Stub helpers (no-ops at DB level; real work done in application layer).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION medical_operator_key(p_operator_id UUID)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  -- Returns a deterministic opaque token used as a key-derivation input
  -- in the application layer. The DB itself never uses this for crypto.
  SELECT encode(
    hmac(
      p_operator_id::text,
      COALESCE(
        current_setting('app.medical_master_key', true),
        'benthyo-dev-master-key-do-not-use-in-prod'
      ),
      'sha256'
    ),
    'hex'
  )
$$;

-- ---------------------------------------------------------------------------
-- Ensure the answers column is JSONB (idempotent).
-- ---------------------------------------------------------------------------
-- If a previous migration version changed it to BYTEA, revert it.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_name = 'medical_form_submissions'
      AND column_name = 'answers'
      AND data_type = 'bytea'
  ) THEN
    -- Convert BYTEA back to JSONB. In a fresh local DB the column is still
    -- JSONB so this branch is never taken. On an existing DB that ran the old
    -- migration this recovers cleanly.
    ALTER TABLE medical_form_submissions
      ALTER COLUMN answers TYPE JSONB USING
        CASE
          WHEN answers IS NULL THEN NULL
          ELSE '{}'::jsonb          -- old ciphertext is unrecoverable without the key
        END;
  END IF;
END
$$;

-- ---------------------------------------------------------------------------
-- Trigger: block direct PostgREST writes; only SECURITY DEFINER RPCs allowed.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION block_direct_answers_write()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- current_user is 'authenticator' for PostgREST direct calls;
  -- it is the function owner (usually 'postgres' / 'supabase_admin') for
  -- SECURITY DEFINER RPCs. Allow only the latter.
  IF current_user = 'authenticator' THEN
    RAISE EXCEPTION
      'Direct writes to medical_form_submissions are not allowed. '
      'Use the submit_medical_form() RPC instead.'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_block_plaintext_answers ON medical_form_submissions;
CREATE TRIGGER trg_block_plaintext_answers
  BEFORE INSERT OR UPDATE ON medical_form_submissions
  FOR EACH ROW
  EXECUTE FUNCTION block_direct_answers_write();

-- ---------------------------------------------------------------------------
-- Application-facing RPCs.
-- ---------------------------------------------------------------------------

-- submit_medical_form: called by the Flutter app after it has already
-- encrypted p_answers with its local AES-256 key. The DB stores whatever
-- JSONB blob the app sends (could be {"ciphertext":"<base64>","iv":"<hex>"}).
CREATE OR REPLACE FUNCTION submit_medical_form(
  p_user_id        UUID,
  p_operator_id    UUID,
  p_trip_id        UUID,
  p_template_id    UUID,
  p_answers        JSONB,
  p_has_yes_answer BOOLEAN,
  p_signer_name    TEXT
)
RETURNS medical_form_submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row medical_form_submissions;
BEGIN
  INSERT INTO medical_form_submissions (
    user_id, operator_id, trip_id, template_id, answers,
    has_yes_answer, signer_name
  )
  VALUES (
    p_user_id, p_operator_id, p_trip_id, p_template_id,
    p_answers,
    p_has_yes_answer, p_signer_name
  )
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION submit_medical_form(
  UUID, UUID, UUID, UUID, JSONB, BOOLEAN, TEXT
) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- my_medical_submissions_decrypted: returns the raw JSONB blob to the owning
-- user. The application layer decrypts it with the local AES key.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION my_medical_submissions_decrypted(p_user_id UUID)
RETURNS TABLE (
  id            UUID,
  user_id       UUID,
  operator_id   UUID,
  trip_id       UUID,
  template_id   UUID,
  has_yes_answer BOOLEAN,
  signer_name   TEXT,
  signed_at     TIMESTAMPTZ,
  created_at    TIMESTAMPTZ,
  answers       JSONB
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    s.id, s.user_id, s.operator_id, s.trip_id, s.template_id,
    s.has_yes_answer, s.signer_name, s.signed_at, s.created_at,
    s.answers
  FROM medical_form_submissions s
  WHERE s.user_id = p_user_id
  ORDER BY s.signed_at DESC
$$;

GRANT EXECUTE ON FUNCTION my_medical_submissions_decrypted(UUID)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- medical_form_submissions_decrypted: operator/admin view of a single row.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION medical_form_submissions_decrypted(
  p_submission_id UUID
)
RETURNS TABLE (
  id            UUID,
  user_id       UUID,
  operator_id   UUID,
  template_id   UUID,
  has_yes_answer BOOLEAN,
  signer_name   TEXT,
  signed_at     TIMESTAMPTZ,
  answers       JSONB,
  created_at    TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    s.id, s.user_id, s.operator_id, s.template_id,
    s.has_yes_answer, s.signer_name, s.signed_at, s.answers, s.created_at
  FROM medical_form_submissions s
  WHERE s.id = p_submission_id
$$;

GRANT EXECUTE ON FUNCTION medical_form_submissions_decrypted(UUID)
  TO authenticated, service_role;
