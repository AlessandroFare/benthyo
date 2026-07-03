-- Migration 045: DB-level enforcement of per-tier resource caps.
--
-- The API enforces these in OperatorsService.assertUnderTierLimit, but
-- the mobile app and any API-key client can INSERT into operator_users /
-- operator_dive_sites directly through PostgREST, bypassing the service.
-- These BEFORE INSERT triggers make the caps a database invariant.
--
-- Caps (README "Subscriptions & billing"):
--   sites: free 3 / starter 10 / pro 100
--   team:  free 1 / starter 5  / pro 20
--
-- Additive: triggers + functions only. service_role (cron/admin/seed)
-- bypasses the cap so platform operations are unaffected.

CREATE OR REPLACE FUNCTION enforce_operator_site_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tier  TEXT;
  v_count INTEGER;
  v_cap   INTEGER;
BEGIN
  IF current_setting('role', true) = 'service_role' THEN
    RETURN NEW;
  END IF;

  SELECT subscription_tier INTO v_tier FROM operators WHERE id = NEW.operator_id;
  v_cap := CASE COALESCE(v_tier, 'free')
             WHEN 'pro' THEN 100
             WHEN 'starter' THEN 10
             ELSE 3
           END;

  SELECT count(*) INTO v_count
  FROM operator_dive_sites WHERE operator_id = NEW.operator_id;

  IF v_count >= v_cap THEN
    RAISE EXCEPTION 'Dive site limit reached for the % tier (%).', COALESCE(v_tier, 'free'), v_cap
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_operator_site_limit ON operator_dive_sites;
CREATE TRIGGER trg_enforce_operator_site_limit
  BEFORE INSERT ON operator_dive_sites
  FOR EACH ROW
  EXECUTE FUNCTION enforce_operator_site_limit();

CREATE OR REPLACE FUNCTION enforce_operator_team_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tier  TEXT;
  v_count INTEGER;
  v_cap   INTEGER;
BEGIN
  IF current_setting('role', true) = 'service_role' THEN
    RETURN NEW;
  END IF;

  SELECT subscription_tier INTO v_tier FROM operators WHERE id = NEW.operator_id;
  v_cap := CASE COALESCE(v_tier, 'free')
             WHEN 'pro' THEN 20
             WHEN 'starter' THEN 5
             ELSE 1
           END;

  SELECT count(*) INTO v_count
  FROM operator_users WHERE operator_id = NEW.operator_id;

  IF v_count >= v_cap THEN
    RAISE EXCEPTION 'Team member limit reached for the % tier (%).', COALESCE(v_tier, 'free'), v_cap
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_operator_team_limit ON operator_users;
CREATE TRIGGER trg_enforce_operator_team_limit
  BEFORE INSERT ON operator_users
  FOR EACH ROW
  EXECUTE FUNCTION enforce_operator_team_limit();
