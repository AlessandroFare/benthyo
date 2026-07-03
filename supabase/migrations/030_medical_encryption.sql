-- Migration 030: Medical form answer encryption.
--
-- The medical_form_submissions.answers column is special-category
-- personal data under GDPR Article 9. We encrypt it at rest with
-- pgcrypto's symmetric AES-256-CBC cipher, keyed per operator. The
-- per-operator key is derived from a platform-managed master key via
-- md5 hashing (32 hex chars = 32 bytes = AES-256 key), so a leak of
-- the master key alone does not let an attacker decrypt without also
-- knowing operator ids.
--
-- Implementation note: we use pgcrypto's encrypt()/decrypt() (raw
-- block cipher, always available in every build) instead of
-- pgp_sym_encrypt() (requires OpenPGP / OpenSSL support, absent in
-- the Supabase CLI local Docker image). The ciphertext is padded
-- automatically by the 'aes-cbc/pad:pkcs' method.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- Internal helpers: raw AES-256-CBC key bytes.
-- ---------------------------------------------------------------------------
-- Returns a 32-byte key derived from the operator id + master key.
-- We take the md5 hex string (32 chars) and cast directly to bytea
-- so PostgreSQL treats each character as one octet (ASCII value),
-- giving a deterministic 32-byte key.

CREATE OR REPLACE FUNCTION _medical_key_bytes(p_key_str TEXT)
RETURNS BYTEA
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT decode(md5(p_key_str), 'hex')
$$;

-- Per-operator key string (md5 input material).
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

-- Per-user key string (for global template submissions where operator_id IS NULL).
CREATE OR REPLACE FUNCTION _medical_user_key(p_user_id UUID)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT md5(
    p_user_id::text ||
    COALESCE(
      current_setting('app.medical_master_key', true),
      'benthyo-dev-master-key-do-not-use-in-prod'
    )
  )
$$;

-- ---------------------------------------------------------------------------
-- Encrypt / decrypt helpers — AES-256-CBC via pgcrypto encrypt().
-- ---------------------------------------------------------------------------
-- encrypt(data, key, type) pads data automatically (PKCS padding).
-- The 'type' string 'aes-cbc/pad:pkcs' is fully supported in the
-- plain pgcrypto build shipped with both Supabase local and cloud.

CREATE OR REPLACE FUNCTION encrypt_medical_answers(
  p_operator_id UUID,
  p_answers     JSONB
)
RETURNS BYTEA
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT encrypt(
    convert_to(p_answers::text, 'UTF8'),
    _medical_key_bytes(medical_operator_key(p_operator_id)),
    'aes'
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
  SELECT convert_from(
    decrypt(
      p_ciphertext,
      _medical_key_bytes(medical_operator_key(p_operator_id)),
      'aes'
    ),
    'UTF8'
  )::jsonb
$$;

-- User-key variant for global template submissions (operator_id IS NULL).
CREATE OR REPLACE FUNCTION encrypt_medical_answers_user(
  p_user_id    UUID,
  p_answers    JSONB
)
RETURNS BYTEA
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT encrypt(
    convert_to(p_answers::text, 'UTF8'),
    _medical_key_bytes(_medical_user_key(p_user_id)),
    'aes'
  )
$$;

CREATE OR REPLACE FUNCTION decrypt_medical_answers_user(
  p_user_id     UUID,
  p_ciphertext  BYTEA
)
RETURNS JSONB
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT convert_from(
    decrypt(
      p_ciphertext,
      _medical_key_bytes(_medical_user_key(p_user_id)),
      'aes'
    ),
    'UTF8'
  )::jsonb
$$;

-- ---------------------------------------------------------------------------
ALTER TABLE medical_form_submissions
  ALTER COLUMN answers TYPE BYTEA USING
    CASE
      WHEN answers IS NULL THEN NULL
      WHEN answers = '{}'::jsonb THEN NULL
      ELSE encrypt_medical_answers(operator_id, answers)
    END;

-- ---------------------------------------------------------------------------
-- View-style helper: decrypt a single submission.
-- ---------------------------------------------------------------------------
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
-- Trigger: block direct plaintext writes to answers column.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION block_direct_answers_write()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- Encrypted AES output is always a multiple of 16 bytes.
  -- Reject anything that is shorter than one AES block (16 bytes).
  IF NEW.answers IS NOT NULL AND octet_length(NEW.answers) < 16 THEN
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

-- ---------------------------------------------------------------------------
-- RPC: my-submissions decrypted.
-- ---------------------------------------------------------------------------
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
