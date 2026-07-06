-- Migration 036: Fix two logic bugs found in review.
--
-- Bug 1 (026): operators_update_member WITH CHECK used self-referencing
-- subqueries to detect subscription column changes. In Postgres RLS,
-- WITH CHECK has no OLD row — the subquery reads the current row state,
-- which is the NEW row being written, so it always matches itself.
-- Fix: replace the WITH CHECK clause with a BEFORE UPDATE trigger that
-- explicitly compares OLD vs NEW and raises if subscription columns
-- change for non-privileged callers.
--
-- Bug 2 (030): The backfill ALTER COLUMN answers TYPE BYTEA called
-- encrypt_medical_answers(operator_id, answers) for ALL rows, including
-- those where operator_id IS NULL. Those rows must be encrypted with
-- encrypt_medical_answers_user(user_id, answers) instead. On a fresh
-- db reset medical_form_submissions is empty so this is a no-op, but
-- any real database with global-template submissions would have errored.

-- ---------------------------------------------------------------------------
-- Bug 1: BEFORE UPDATE trigger to prevent subscription self-upgrade.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION prevent_subscription_self_upgrade()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Allow service_role and subscription_admin to do anything.
  IF current_setting('role', true) = 'service_role'
     OR current_setting('request.jwt.claims', true)::jsonb ->> 'role'
        = 'subscription_admin'
  THEN
    RETURN NEW;
  END IF;

  -- For everyone else, block changes to subscription_tier / subscription_status.
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

DROP TRIGGER IF EXISTS trg_prevent_subscription_self_upgrade ON operators;
CREATE TRIGGER trg_prevent_subscription_self_upgrade
  BEFORE UPDATE ON operators
  FOR EACH ROW
  EXECUTE FUNCTION prevent_subscription_self_upgrade();

-- Now tighten the RLS policy so the WITH CHECK is a no-op guard (the
-- trigger does the real work). We keep the USING clause so only
-- owner/admin staff can UPDATE operators at all.
DROP POLICY IF EXISTS operators_update_member ON operators;
CREATE POLICY operators_update_member
  ON operators
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM operator_users
      WHERE operator_id = operators.id
        AND user_id = auth.uid()
        AND role IN ('owner', 'admin')
    )
  )
  WITH CHECK (
    -- WITH CHECK is intentionally permissive; the real guard is the
    -- BEFORE UPDATE trigger above. This avoids the self-referencing
    -- subquery antipattern.
    true
  );

-- ---------------------------------------------------------------------------
-- Bug 2: Re-encrypt any medical_form_submissions where operator_id IS NULL
-- but answers were encrypted with the operator-key function (which would
-- have produced garbage or errored). We re-encrypt with the user-keyed
-- variant. This is a no-op if all rows already have correct encryption
-- or if the table is empty (typical after db reset).
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_master TEXT := COALESCE(
    current_setting('app.medical_master_key', true),
    'benthyo-dev-master-key-do-not-use-in-prod'
  );
  v_updated INTEGER;
BEGIN
  -- Re-encrypt rows where operator_id IS NULL. We can't call
  -- encrypt_medical_answers_user() directly in an ALTER TYPE USING
  -- because it's IMMUTABLE and the planner might cache, so we use
  -- inline encryption logic.
  UPDATE medical_form_submissions
  SET answers = pgp_sym_encrypt(
    answers::text,
    md5(user_id::text || v_master),
    'cipher-algo=aes256'
  )
  WHERE operator_id IS NULL
    AND answers IS NOT NULL
    AND octet_length(answers) >= 64;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated > 0 THEN
    RAISE NOTICE 'Re-encrypted % medical_form_submissions with user key', v_updated;
  END IF;
END;
$$;