-- Migration 039: Close remaining audit gaps.
--
-- Gap 1 (036): the prevent_subscription_self_upgrade trigger granted a
-- bypass to any caller whose JWT carried role = 'subscription_admin'.
-- That claim can originate from a client token (e.g. Supabase app_metadata
-- surfaced into request.jwt.claims), so an operator could potentially mint
-- it and self-upgrade. There is NO legitimate caller that sets this claim:
-- migration 027 defines subscription_admin as a NOLOGIN NOINHERIT Postgres
-- role and grants set_operator_subscription() to service_role only. So the
-- only legitimate bypass is the actual service_role. We remove the
-- JWT-claim escape hatch entirely.
--
-- Gap 2 (030): block_direct_answers_write only rejected answers shorter
-- than 64 bytes, so a >=64-byte plaintext blob slipped through. We instead
-- assert the payload begins with an OpenPGP packet tag (high bit set on the
-- first octet), which a raw JSON/text plaintext never does, in addition to
-- the length floor.

-- ---------------------------------------------------------------------------
-- Gap 1: remove the subscription_admin JWT bypass.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION prevent_subscription_self_upgrade()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only the actual service_role (used by the Stripe webhook via
  -- set_operator_subscription) may change the subscription columns.
  -- The previous JWT-claim ('subscription_admin') bypass is removed
  -- because that claim could be client-controlled.
  IF current_setting('role', true) = 'service_role' THEN
    RETURN NEW;
  END IF;

  IF NEW.subscription_tier IS DISTINCT FROM OLD.subscription_tier THEN
    RAISE EXCEPTION 'Cannot modify subscription_tier directly. Use set_operator_subscription().'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.subscription_status IS DISTINCT FROM OLD.subscription_status THEN
    RAISE EXCEPTION 'Cannot modify subscription_status directly. Use set_operator_subscription().'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

-- Trigger from 036 already points at this function; recreating the
-- function above is sufficient. Re-assert the trigger for idempotency.
DROP TRIGGER IF EXISTS trg_prevent_subscription_self_upgrade ON operators;
CREATE TRIGGER trg_prevent_subscription_self_upgrade
  BEFORE UPDATE ON operators
  FOR EACH ROW
  EXECUTE FUNCTION prevent_subscription_self_upgrade();

-- ---------------------------------------------------------------------------
-- Gap 2: harden block_direct_answers_write against >=64-byte plaintext.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION block_direct_answers_write()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_first_byte INTEGER;
BEGIN
  IF NEW.answers IS NULL THEN
    RETURN NEW;
  END IF;

  -- A pgp_sym_encrypt() output is a well-formed OpenPGP message whose
  -- first octet is a packet tag with the high bit set. A raw JSON / text
  -- plaintext blob starts with '{' (0x7B), '[' (0x5B) or whitespace --
  -- none of which have the high bit set. We reject anything implausibly
  -- short AND anything whose first byte is not an OpenPGP packet tag.
  IF octet_length(NEW.answers) < 64 THEN
    RAISE EXCEPTION
      'medical_form_submissions.answers must be encrypted with encrypt_medical_answers() (too short)'
      USING ERRCODE = '22023';
  END IF;

  v_first_byte := get_byte(NEW.answers, 0);
  IF (v_first_byte & 128) = 0 THEN
    RAISE EXCEPTION
      'medical_form_submissions.answers must be encrypted with encrypt_medical_answers() (not an OpenPGP message)'
      USING ERRCODE = '22023';
  END IF;

  RETURN NEW;
END;
$$;

-- Trigger from 030 already references this function; reassert for safety.
DROP TRIGGER IF EXISTS trg_block_plaintext_answers ON medical_form_submissions;
CREATE TRIGGER trg_block_plaintext_answers
  BEFORE INSERT OR UPDATE ON medical_form_submissions
  FOR EACH ROW
  EXECUTE FUNCTION block_direct_answers_write();
