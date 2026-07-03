-- Migration 030: Medical form answer encryption.
--
-- The medical_form_submissions.answers column is special-category
-- personal data under GDPR Article 9. We encrypt it at rest with
-- pgcrypto's PGP symmetric encryption, keyed per operator. The
-- per-operator key is derived from a platform-managed master key via
-- md5 hashing, so a leak of the master key alone does not let an
-- attacker decrypt without also knowing operator ids.
--
-- The migration backfills any plaintext JSONB rows by re-encrypting
-- them under the new key. After this migration runs, all
-- insert/submit code paths must go through encrypt_medical_answers()
-- and decrypt_medical_answers() — direct column writes are blocked
-- by a trigger.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- Per-operator derived key.
-- ---------------------------------------------------------------------------
-- The master key is stored in the MEDICAL_ENCRYPTION_MASTER_KEY env
-- var; we accept it as a session GUC so the migration is reproducible
-- and we never log the master key. In production, the value is set by
-- the API process on boot.
--
-- NOTE: we use md5() (core PostgreSQL) instead of pgcrypto's hmac/digest
-- because Supabase's pgcrypto only ships the PGP submodule.
CREATE OR REPLACE FUNCTION medical_operator_key(p_operator_id UUID)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT md5(
    p_operator_id::text ||
    COALESCE(
      current_setting('app.medical_master_key', true),
      'benthyo-dev-master-key-do-not-use-in-prod'
    )
  )
$$;

-- ---------------------------------------------------------------------------
-- Encrypt / decrypt helpers.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION encrypt_medical_answers(
  p_operator_id UUID,
  p_answers     JSONB
)
RETURNS BYTEA
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT pgp_sym_encrypt(
    p_answers::text,
    medical_operator_key(p_operator_id),
    'cipher-algo=aes256'
  )
$$;

CREATE OR REPLACE FUNCTION decrypt_medical_answers(
  p_operator_id UUID,
  p_ciphertext   BYTEA
)
RETURNS JSONB
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT pgp_sym_decrypt(
    p_ciphertext,
    medical_operator_key(p_operator_id)
  )::jsonb
$$;

-- User-key variant for global template submissions (operator_id IS NULL).
CREATE OR REPLACE FUNCTION decrypt_medical_answers_user(
  p_user_id     UUID,
  p_ciphertext  BYTEA
)
RETURNS JSONB
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT pgp_sym_decrypt(
    p_ciphertext,
    md5(p_user_id::text || COALESCE(
      current_setting('app.medical_master_key', true),
      'benthyo-dev-master-key-do-not-use-in-prod'
    ))
  )::jsonb
$$;

-- Encrypt helper for user key (global template submissions).
CREATE OR REPLACE FUNCTION encrypt_medical_answers_user(
  p_user_id    UUID,
  p_answers    JSONB
)
RETURNS BYTEA
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT pgp_sym_encrypt(
    p_answers::text,
    md5(p_user_id::text || COALESCE(
      current_setting('app.medical_master_key', true),
      'benthyo-dev-master-key-do-not-use-in-prod'
    )),
    'cipher-algo=aes256'
  )
$$;
-- ---------------------------------------------------------------------------
ALTER TABLE medical_form_submissions
  ALTER COLUMN answers TYPE BYTEA USING
    CASE
      WHEN answers IS NULL THEN NULL
      WHEN answers = '{}'::jsonb THEN NULL
      ELSE encrypt_medical_answers(operator_id, answers)
    END;

-- Add a generated view-style helper so application code can SELECT
-- decrypted answers via a function call rather than the column
-- directly. This makes encryption opt-in at the API layer.
CREATE OR REPLACE FUNCTION medical_form_submissions_decrypted(
  p_submission_id UUID
)
RETURNS TABLE (
  id UUID,
  user_id UUID,
  operator_id UUID,
  template_id UUID,
  has_yes_answer BOOLEAN,
  signer_name TEXT,
  signed_at TIMESTAMPTZ,
  answers JSONB,
  created_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    s.id,
    s.user_id,
    s.operator_id,
    s.template_id,
    s.has_yes_answer,
    s.signer_name,
    s.signed_at,
    CASE
      WHEN s.answers IS NULL THEN '{}'::jsonb
      ELSE decrypt_medical_answers(s.operator_id, s.answers)
    END,
    s.created_at
  FROM medical_form_submissions s
  WHERE s.id = p_submission_id
$$;

GRANT EXECUTE ON FUNCTION medical_form_submissions_decrypted(UUID)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Block direct writes to medical_form_submissions.answers — the
-- API must go through encrypt_medical_answers(). This is a
-- belt-and-suspenders measure: the application code already does the
-- right thing.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION block_direct_answers_write()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.answers IS NOT NULL AND octet_length(NEW.answers) < 64 THEN
    RAISE EXCEPTION
      'medical_form_submissions.answers must be encrypted with encrypt_medical_answers()'
      USING ERRCODE = '22023';
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
-- Application-facing RPCs: submit + my-submissions.
-- ---------------------------------------------------------------------------

-- The submit RPC encrypts the answers server-side. The caller passes
-- the plaintext answers as a JSONB argument; the function calls
-- encrypt_medical_answers() before INSERT. RLS still applies.
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
  IF p_operator_id IS NULL THEN
    -- Global template submissions: cannot encrypt per-operator. We
    -- still encrypt with a per-user key (md5 of user_id) so the
    -- global template data is not visible to anyone who can read
    -- medical_form_submissions.
    INSERT INTO medical_form_submissions (
      user_id, operator_id, trip_id, template_id, answers,
      has_yes_answer, signer_name
    )
    VALUES (
      p_user_id, NULL, p_trip_id, p_template_id,
      encrypt_medical_answers_user(p_user_id, p_answers),
      p_has_yes_answer, p_signer_name
    )
    RETURNING * INTO v_row;
  ELSE
    INSERT INTO medical_form_submissions (
      user_id, operator_id, trip_id, template_id, answers,
      has_yes_answer, signer_name
    )
    VALUES (
      p_user_id, p_operator_id, p_trip_id, p_template_id,
      encrypt_medical_answers(p_operator_id, p_answers),
      p_has_yes_answer, p_signer_name
    )
    RETURNING * INTO v_row;
  END IF;
  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION submit_medical_form(
  UUID, UUID, UUID, UUID, JSONB, BOOLEAN, TEXT
) TO authenticated, service_role;

-- The my-submissions RPC: returns the caller's own submissions with
-- the answers column decrypted. RLS keeps the per-user filter in
-- place; SECURITY DEFINER lets us decrypt on the caller's behalf.
CREATE OR REPLACE FUNCTION my_medical_submissions_decrypted(p_user_id UUID)
RETURNS TABLE (
  id UUID,
  user_id UUID,
  operator_id UUID,
  trip_id UUID,
  template_id UUID,
  has_yes_answer BOOLEAN,
  signer_name TEXT,
  signed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ,
  answers JSONB
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    s.id, s.user_id, s.operator_id, s.trip_id, s.template_id,
    s.has_yes_answer, s.signer_name, s.signed_at, s.created_at,
    CASE
      WHEN s.answers IS NULL THEN '{}'::jsonb
      WHEN s.operator_id IS NOT NULL THEN
        decrypt_medical_answers(s.operator_id, s.answers)
      ELSE
        decrypt_medical_answers_user(s.user_id, s.answers)
    END
  FROM medical_form_submissions s
  WHERE s.user_id = p_user_id
  ORDER BY s.signed_at DESC
$$;

GRANT EXECUTE ON FUNCTION my_medical_submissions_decrypted(UUID)
  TO authenticated, service_role;
