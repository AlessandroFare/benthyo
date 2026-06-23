-- Migration 040: mark the medical key-derivation and crypto helpers STABLE.
--
-- Migrations 030 and 038 declared these functions IMMUTABLE. That is
-- incorrect: they read session GUCs (app.medical_master_key,
-- app.medical_key_salt) via current_setting(), so their result is NOT a
-- pure function of their arguments. An IMMUTABLE function may be constant-
-- folded / cached by the planner, which could return a stale key if a GUC
-- changes within a session (e.g. during the key-rotation recipe in
-- docs/runbook.md §8.3, which SET LOCALs the old then new secrets in one
-- transaction). STABLE is the correct volatility: the value is fixed
-- within a single statement but may differ across statements.
--
-- Function bodies are unchanged; only the volatility marker is corrected.
-- CREATE OR REPLACE keeps signatures and GRANTs intact.

-- v2 (HMAC-SHA256) derivation, from migration 038.
CREATE OR REPLACE FUNCTION medical_master_key_v2()
RETURNS TEXT LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    current_setting('app.medical_master_key', true),
    'benthyo-dev-master-key-do-not-use-in-prod'
  )
$$;

CREATE OR REPLACE FUNCTION medical_key_salt()
RETURNS TEXT LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    current_setting('app.medical_key_salt', true),
    'benthyo-dev-key-salt-do-not-use-in-prod'
  )
$$;

CREATE OR REPLACE FUNCTION medical_derive_key_v2(p_scope TEXT, p_id UUID)
RETURNS TEXT LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_msg TEXT := p_scope || ':' || p_id::text || ':' || medical_key_salt();
  v_key TEXT := medical_master_key_v2();
  v_has_hmac BOOLEAN;
BEGIN
  SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'hmac') INTO v_has_hmac;
  IF v_has_hmac THEN
    RETURN encode(hmac(v_msg, v_key, 'sha256'), 'hex');
  ELSE
    RETURN encode(digest(v_key || ':' || v_msg, 'sha256'), 'hex');
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION medical_operator_key_v2(p_operator_id UUID)
RETURNS TEXT LANGUAGE sql STABLE AS $$
  SELECT medical_derive_key_v2('op', p_operator_id)
$$;

CREATE OR REPLACE FUNCTION medical_user_key_v2(p_user_id UUID)
RETURNS TEXT LANGUAGE sql STABLE AS $$
  SELECT medical_derive_key_v2('user', p_user_id)
$$;

-- Legacy v1 helpers (retained for rotation), from migration 038.
CREATE OR REPLACE FUNCTION medical_operator_key_v1(p_operator_id UUID)
RETURNS TEXT LANGUAGE sql STABLE AS $$
  SELECT md5(p_operator_id::text || medical_master_key_v2())
$$;

CREATE OR REPLACE FUNCTION medical_user_key_v1(p_user_id UUID)
RETURNS TEXT LANGUAGE sql STABLE AS $$
  SELECT md5(p_user_id::text || medical_master_key_v2())
$$;

-- Encrypt/decrypt helpers, from migrations 030/038. pgp_sym_encrypt itself
-- is volatile (random IV) so encryption was never safely IMMUTABLE; decrypt
-- depends on the GUC-derived key. Both are STABLE.
CREATE OR REPLACE FUNCTION encrypt_medical_answers(p_operator_id UUID, p_answers JSONB)
RETURNS BYTEA LANGUAGE sql STABLE AS $$
  SELECT pgp_sym_encrypt(p_answers::text, medical_operator_key_v2(p_operator_id), 'cipher-algo=aes256')
$$;

CREATE OR REPLACE FUNCTION decrypt_medical_answers(p_operator_id UUID, p_ciphertext BYTEA)
RETURNS JSONB LANGUAGE sql STABLE AS $$
  SELECT pgp_sym_decrypt(p_ciphertext, medical_operator_key_v2(p_operator_id))::jsonb
$$;

CREATE OR REPLACE FUNCTION encrypt_medical_answers_user(p_user_id UUID, p_answers JSONB)
RETURNS BYTEA LANGUAGE sql STABLE AS $$
  SELECT pgp_sym_encrypt(p_answers::text, medical_user_key_v2(p_user_id), 'cipher-algo=aes256')
$$;

CREATE OR REPLACE FUNCTION decrypt_medical_answers_user(p_user_id UUID, p_ciphertext BYTEA)
RETURNS JSONB LANGUAGE sql STABLE AS $$
  SELECT pgp_sym_decrypt(p_ciphertext, medical_user_key_v2(p_user_id))::jsonb
$$;
