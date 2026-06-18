-- Migration 034: Dead letter queue, image columns, idempotency columns,
-- marketplace approval, pg_cron jobs.
--
-- This migration closes the remaining audit / launch gaps:
--   1. dead_letter table for the Flutter offline sync queue.
--   2. species.image_license / image_source / image_attribution columns.
--   3. dive_logs.client_request_id, sightings.client_request_id with
--      a unique partial index so the sync manager can retry without
--      creating duplicates.
--   4. operator_marketplace_listings.is_approved + updated RLS.
--   5. pg_cron jobs for the maintenance routines.

-- ============================================================
-- 1. dead_letter
-- ============================================================
CREATE TABLE IF NOT EXISTS public.dead_letter (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- Endpoint path (e.g. '/sightings', '/dive-logs') the client tried
  -- to POST/PATCH.
  endpoint      TEXT NOT NULL,
  -- Original payload that failed.
  payload       JSONB NOT NULL,
  -- HTTP status / network error string from the last attempt.
  error         TEXT NOT NULL,
  -- Number of times we've retried this row.
  attempts      INTEGER NOT NULL DEFAULT 0,
  -- The client_request_id from the original request — used to dedupe
  -- retries.
  client_request_id UUID,
  -- First and last attempt timestamps.
  first_failed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_failed_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  retried_at      TIMESTAMPTZ,
  -- When the user dismisses the item without retrying.
  dismissed_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dead_letter_user_open
  ON dead_letter (user_id, last_failed_at DESC)
  WHERE dismissed_at IS NULL AND retried_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_dead_letter_request_id
  ON dead_letter (user_id, client_request_id)
  WHERE client_request_id IS NOT NULL;

COMMENT ON TABLE dead_letter IS
  'Failed sync writes from the Flutter app. Owner-only RLS; dismissable / retryable.';
COMMENT ON COLUMN dead_letter.client_request_id IS
  'Mirrors the column on dive_logs / sightings so the sync manager can resume without double-inserting.';

ALTER TABLE dead_letter ENABLE ROW LEVEL SECURITY;

-- Owner can see / modify only their own dead-letter rows. Inserts are
-- performed by the service role via the API (the Flutter app calls
-- /v1/sync/dead-letter to fetch and retry, never to insert).
DROP POLICY IF EXISTS dead_letter_select_own ON dead_letter;
CREATE POLICY dead_letter_select_own ON dead_letter FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS dead_letter_delete_own ON dead_letter;
CREATE POLICY dead_letter_delete_own ON dead_letter FOR DELETE USING (auth.uid() = user_id);

-- ============================================================
-- 2. species image attribution columns
-- ============================================================
ALTER TABLE species
  ADD COLUMN IF NOT EXISTS image_license      TEXT,
  ADD COLUMN IF NOT EXISTS image_source       TEXT,
  ADD COLUMN IF NOT EXISTS image_attribution  TEXT;

COMMENT ON COLUMN species.image_license     IS 'SPDX identifier (CC-BY-4.0, CC0-1.0, etc.). NULL = unverified.';
COMMENT ON COLUMN species.image_source      IS 'wikimedia | inaturalist | gbif | obis | manual | other.';
COMMENT ON COLUMN species.image_attribution IS 'Photographer / author credit, required for CC-BY.';

-- ============================================================
-- 3. client_request_id columns + unique partial indexes
-- ============================================================
ALTER TABLE dive_logs
  ADD COLUMN IF NOT EXISTS client_request_id UUID;

ALTER TABLE sightings
  ADD COLUMN IF NOT EXISTS client_request_id UUID;

-- Unique partial indexes per (user_id, client_request_id). Multiple
-- NULL client_request_ids per user are allowed (legacy rows).
CREATE UNIQUE INDEX IF NOT EXISTS idx_dive_logs_client_req
  ON dive_logs (user_id, client_request_id)
  WHERE client_request_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_sightings_client_req
  ON sightings (user_id, client_request_id)
  WHERE client_request_id IS NOT NULL;

-- ============================================================
-- 4. operator_marketplace_listings: is_approved + RLS update
-- ============================================================
ALTER TABLE operator_marketplace_listings
  ADD COLUMN IF NOT EXISTS is_approved BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE operator_marketplace_listings
  ADD COLUMN IF NOT EXISTS approved_by UUID REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE operator_marketplace_listings
  ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ;

-- Replace the public-read policy to require is_approved = true.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'operator_marketplace_listings'
      AND policyname = 'marketplace_listings_public_read'
  ) THEN
    DROP POLICY marketplace_listings_public_read ON operator_marketplace_listings;
  END IF;
END;
$$;

CREATE POLICY marketplace_listings_public_read ON operator_marketplace_listings
  FOR SELECT USING (is_active = true AND is_approved = true);

-- Operator owners can still see their own unapproved listings.
CREATE POLICY marketplace_listings_owner_select ON operator_marketplace_listings
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM operator_users
      WHERE operator_id = operator_marketplace_listings.operator_id
        AND user_id = auth.uid()
        AND role IN ('owner', 'admin')
    )
  );

-- Admin: an admin can flip is_approved via the SECURITY DEFINER
-- approve_marketplace_listing() RPC below.
CREATE OR REPLACE FUNCTION approve_marketplace_listing(p_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller UUID := auth.uid();
BEGIN
  -- Only platform admins (app_metadata.is_admin = true) can approve.
  IF NOT EXISTS (
    SELECT 1 FROM users
    WHERE id = v_caller
      AND (auth.jwt() ->> 'app_metadata')::jsonb ->> 'is_admin' = 'true'
  ) AND current_setting('role', true) NOT IN ('service_role', 'postgres') THEN
    RAISE EXCEPTION 'admin role required' USING ERRCODE = '42501';
  END IF;

  UPDATE operator_marketplace_listings
  SET    is_approved = true,
         approved_by = v_caller,
         approved_at = now()
  WHERE  id = p_id;
END;
$$;

GRANT EXECUTE ON FUNCTION approve_marketplace_listing(UUID) TO authenticated, service_role;

-- ============================================================
-- 5. pg_cron jobs
-- ============================================================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    -- 5a. prune_inat_identify_cache — weekly, Sunday 03:00 UTC.
    IF NOT EXISTS (
      SELECT 1 FROM cron.job WHERE jobname = 'prune-inat-identify-cache-weekly'
    ) THEN
      PERFORM cron.schedule(
        'prune-inat-identify-cache-weekly',
        '0 3 * * 0',
        $cron$ DELETE FROM public.inat_identify_cache WHERE expires_at < now(); $cron$
      );
    END IF;

    -- 5b. reconcile_unmatched_occurrences — nightly, 02:00 UTC.
    IF NOT EXISTS (
      SELECT 1 FROM cron.job WHERE jobname = 'reconcile-unmatched-nightly'
    ) THEN
      PERFORM cron.schedule(
        'reconcile-unmatched-nightly',
        '0 2 * * *',
        $cron$ SELECT public.reconcile_unmatched_occurrences('gbif', 30); $cron$
      );
    END IF;

    -- 5c. pgvector monthly reindex — already scheduled in migration
    -- 032; nothing to do here.
  END IF;
END;
$$;