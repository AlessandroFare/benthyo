-- Migration 044: close two RLS gaps found in the production-readiness pass.
--
-- Gap 1 (HIGH) — sightings verification at the RLS layer ignored the
--   taxonomy-expert requirement and allowed self-verification.
--   The original policy `sightings_admin_verify` (011_rls.sql) let ANY
--   operator owner/admin set verified_by directly via their RLS-aware
--   client, with no `users.taxonomy_expert` check and no self-verify
--   guard. The API service + TaxonomyExpertGuard enforce both, but the
--   mobile app talks to PostgREST directly, so the RLS layer must also
--   enforce them ("defense in depth" per the README security model).
--
-- Gap 2 (MEDIUM) — three tables shipped without RLS; one
--   (species_embedding_audit) additionally granted SELECT to every
--   authenticated user, exposing the full embedding-write audit log.
--
-- All changes are additive (policy + ALTER ENABLE RLS + REVOKE); no data
-- is dropped or rewritten.

-- ---------------------------------------------------------------------------
-- Gap 1: replace the sightings verification UPDATE policy.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS sightings_admin_verify ON sightings;

-- Verification requires the caller to be a taxonomy expert, the sighting
-- to be currently unverified, and the caller to NOT be the reporter
-- (no self-verify). WITH CHECK pins the new verified_by to the caller so
-- a verifier cannot attribute the verification to someone else.
CREATE POLICY sightings_expert_verify ON sightings
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM users u
      WHERE u.id = auth.uid() AND u.taxonomy_expert = true
    )
    AND verified_by IS NULL          -- no re-verification
    AND user_id <> auth.uid()        -- no self-verify
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM users u
      WHERE u.id = auth.uid() AND u.taxonomy_expert = true
    )
    AND user_id <> auth.uid()
    AND (verified_by IS NULL OR verified_by = auth.uid())
  );

-- The reporter's own UPDATE policy (sightings_update_own, 011_rls.sql)
-- only constrained user_id in its WITH CHECK, so a reporter could set
-- verified_by on their own row via a direct PostgREST call — the same
-- self-verify hole, through a different policy. Re-create it to forbid
-- the reporter from touching the verification columns; verification must
-- go through sightings_expert_verify (a different, non-reporter caller).
-- A BEFORE UPDATE trigger enforces "verification columns unchanged for
-- the reporter path" reliably (RLS WITH CHECK has no OLD row).
CREATE OR REPLACE FUNCTION prevent_self_verify_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- service_role bypasses RLS entirely and never fires under a user JWT,
  -- but guard explicitly so cron/admin writes are unaffected.
  IF current_setting('role', true) = 'service_role' THEN
    RETURN NEW;
  END IF;
  -- If the caller is the reporter, they may not change verification state.
  IF auth.uid() = OLD.user_id THEN
    IF NEW.verified_by IS DISTINCT FROM OLD.verified_by
       OR NEW.verified_at IS DISTINCT FROM OLD.verified_at THEN
      RAISE EXCEPTION 'Reporters cannot verify their own sightings'
        USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_self_verify_columns ON sightings;
CREATE TRIGGER trg_prevent_self_verify_columns
  BEFORE UPDATE ON sightings
  FOR EACH ROW
  EXECUTE FUNCTION prevent_self_verify_columns();

-- ---------------------------------------------------------------------------
-- Gap 2: enable RLS on the three tables that lacked it.
-- ---------------------------------------------------------------------------

-- species_embedding_audit: append-only audit log. No authenticated user
-- should read it. Revoke the over-broad SELECT grant and lock reads to
-- service_role only (admins use the service-role client for audits).
ALTER TABLE public.species_embedding_audit ENABLE ROW LEVEL SECURITY;
REVOKE SELECT ON public.species_embedding_audit FROM authenticated;
-- No policy granting SELECT to authenticated/anon => default deny for them.
-- service_role bypasses RLS, so audit reads still work via the admin client.

-- pgvector_reindex_log: operational log written by a SECURITY DEFINER
-- pg_cron function. Not user data; default-deny under RLS is correct.
ALTER TABLE public.pgvector_reindex_log ENABLE ROW LEVEL SECURITY;

-- unmapped_iucn_codes: ETL audit counter. Default-deny under RLS.
ALTER TABLE public.unmapped_iucn_codes ENABLE ROW LEVEL SECURITY;
