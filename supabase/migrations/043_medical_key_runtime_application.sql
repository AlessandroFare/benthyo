-- Migration 043: actually apply the runtime medical master key.
--
-- Problem (CRITICAL, found in the production-readiness pass):
--   The per-operator / per-user medical encryption key is derived from
--   the GUC `app.medical_master_key` (and `app.medical_key_salt`), read
--   inside encrypt_medical_answers* / decrypt_medical_answers* via
--   current_setting('app.medical_master_key', true). When that GUC is
--   unset the helpers fall back to the hardcoded placeholder
--   'oceanlog-dev-master-key-do-not-use-in-prod' (see migrations 038/040).
--
--   The API (apps/api/src/medical/medical.service.ts) reads
--   MEDICAL_ENCRYPTION_MASTER_KEY from the environment but NEVER sets the
--   GUC on the Supabase session. PostgREST runs every `.rpc()` call in its
--   own transaction, so there is no session in which a separately-issued
--   `set_config` would still be live when submit_medical_form runs. Net
--   effect: production GDPR Art. 9 medical data was being encrypted under
--   a publicly-known dev key.
--
-- Fix:
--   Thread the master key + salt THROUGH the RPC call so the key is set
--   and consumed inside the SAME transaction. New SECURITY DEFINER
--   wrappers set the GUCs transaction-locally (is_local = true) and then
--   delegate to the existing submit / decrypt RPCs, whose key-derivation
--   helpers now observe the real key.
--
--   Wrappers are additive: the original RPCs are untouched, so existing
--   callers and the unit-test path (which pass no key and intentionally
--   exercise the dev fallback) keep working.
--
--   The key travels API -> PostgREST over the internal/loopback channel,
--   the same trust boundary the service-role key already crosses. A
--   stronger alternative (ALTER ROLE authenticator SET app.medical_master_key)
--   is documented in docs/runbook.md as the deploy-time hardening; this
--   migration makes correctness not depend on that manual step.

-- ---------------------------------------------------------------------------
-- Helper: set the medical key GUCs for the remainder of the current
-- transaction. No-op for empty inputs so the dev-fallback path is
-- preserved for tests.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION apply_medical_session_keys(
  p_master_key TEXT,
  p_salt       TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_master_key IS NOT NULL AND length(p_master_key) > 0 THEN
    PERFORM set_config('app.medical_master_key', p_master_key, true);
  END IF;
  IF p_salt IS NOT NULL AND length(p_salt) > 0 THEN
    PERFORM set_config('app.medical_key_salt', p_salt, true);
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION apply_medical_session_keys(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION apply_medical_session_keys(TEXT, TEXT)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- submit_medical_form_v2: set the runtime key, then submit. Same
-- transaction, so encrypt_medical_answers* sees the real key.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION submit_medical_form_v2(
  p_user_id        UUID,
  p_operator_id    UUID,
  p_trip_id        UUID,
  p_template_id    UUID,
  p_answers        JSONB,
  p_has_yes_answer BOOLEAN,
  p_signer_name    TEXT,
  p_master_key     TEXT,
  p_salt           TEXT
)
RETURNS medical_form_submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row medical_form_submissions;
BEGIN
  PERFORM apply_medical_session_keys(p_master_key, p_salt);
  v_row := submit_medical_form(
    p_user_id, p_operator_id, p_trip_id, p_template_id,
    p_answers, p_has_yes_answer, p_signer_name
  );
  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION submit_medical_form_v2(
  UUID, UUID, UUID, UUID, JSONB, BOOLEAN, TEXT, TEXT, TEXT
) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- my_medical_submissions_decrypted_v2: set the runtime key, then decrypt.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION my_medical_submissions_decrypted_v2(
  p_user_id    UUID,
  p_master_key TEXT,
  p_salt       TEXT
)
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
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM apply_medical_session_keys(p_master_key, p_salt);
  RETURN QUERY
    SELECT * FROM my_medical_submissions_decrypted(p_user_id);
END;
$$;

GRANT EXECUTE ON FUNCTION my_medical_submissions_decrypted_v2(UUID, TEXT, TEXT)
  TO authenticated, service_role;
