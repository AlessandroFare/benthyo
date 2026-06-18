-- Migration 028: Waiver signature legal-binding fields.
--
-- DD-5.7: eIDAS SES compliance. We capture IP, User-Agent, signer email,
-- a SHA256 of the waiver body at the time of signing, and the version
-- number. Any subsequent change to the waiver body is detectable.

ALTER TABLE waiver_signatures
  ADD COLUMN IF NOT EXISTS signer_email TEXT,
  ADD COLUMN IF NOT EXISTS ip_address INET,
  ADD COLUMN IF NOT EXISTS user_agent TEXT,
  ADD COLUMN IF NOT EXISTS signed_waiver_text_hash TEXT,
  ADD COLUMN IF NOT EXISTS signed_waiver_version INTEGER;

-- Backfill ip_address 'unknown' for any pre-existing rows so NOT NULL
-- constraints can be applied later without breaking the migration.
UPDATE waiver_signatures
  SET ip_address = COALESCE(ip_address, '0.0.0.0'::inet),
      user_agent = COALESCE(user_agent, 'legacy'),
      signed_waiver_text_hash = COALESCE(signed_waiver_text_hash, 'legacy'),
      signed_waiver_version = COALESCE(signed_waiver_version, 1);

ALTER TABLE waiver_signatures
  ALTER COLUMN ip_address SET NOT NULL,
  ALTER COLUMN user_agent SET NOT NULL,
  ALTER COLUMN signed_waiver_text_hash SET NOT NULL,
  ALTER COLUMN signed_waiver_version SET NOT NULL;

-- Add a unique-constraint to allow ON CONFLICT (waiver_id, user_id)
-- in the API upsert.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'waiver_signatures_waiver_user_unique'
  ) THEN
    ALTER TABLE waiver_signatures
      ADD CONSTRAINT waiver_signatures_waiver_user_unique UNIQUE (waiver_id, user_id);
  END IF;
END$$;
