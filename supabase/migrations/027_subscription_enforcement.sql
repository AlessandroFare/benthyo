-- Migration 027: Subscription enforcement helpers.
--
-- Adds a privilege-isolated Postgres role used by the Stripe webhook to
-- write subscription_tier / subscription_status. Members of operator_users
-- and any client call cannot bypass this. The guard in the API also
-- double-checks before allowing tier reads/changes for non-platform
-- callers.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'subscription_admin') THEN
    CREATE ROLE subscription_admin NOLOGIN NOINHERIT;
  END IF;
END$$;

-- The set_operator_subscription function: writes subscription_tier and
-- subscription_status. This is the ONLY path by which those columns
-- should be modified. RLS will block direct UPDATE from clients because
-- the operators_update_member policy is column-agnostic — but to be
-- belt-and-suspenders, we also revoke EXECUTE from PUBLIC and only grant
-- to subscription_admin (the role the Stripe service uses).
CREATE OR REPLACE FUNCTION set_operator_subscription(
  p_operator_id UUID,
  p_tier        TEXT,
  p_status      TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Validate the inputs against the allowed enum values.
  IF p_tier NOT IN ('free', 'starter', 'pro') THEN
    RAISE EXCEPTION 'Invalid tier: %', p_tier USING ERRCODE = '22023';
  END IF;
  IF p_status NOT IN ('active', 'past_due', 'canceled', 'trialing') THEN
    RAISE EXCEPTION 'Invalid status: %', p_status USING ERRCODE = '22023';
  END IF;

  UPDATE operators
  SET subscription_tier = p_tier,
      subscription_status = p_status,
      updated_at = now()
  WHERE id = p_operator_id;
END;
$$;

REVOKE ALL ON FUNCTION set_operator_subscription(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION set_operator_subscription(UUID, TEXT, TEXT) TO service_role;

-- Helper: apply grace period logic to subscription status.
--   - 'active' / 'trialing' => ok
--   - 'past_due'  => ok for 14 days, then downgrade to read-only
--   - 'canceled' => read-only immediately
CREATE OR REPLACE FUNCTION effective_subscription_status(p_operator_id UUID)
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
  WITH op AS (
    SELECT subscription_tier, subscription_status,
           updated_at
    FROM operators WHERE id = p_operator_id
  )
  SELECT CASE
    WHEN op.subscription_status IN ('active', 'trialing') THEN 'active'
    WHEN op.subscription_status = 'past_due'
         AND op.updated_at > now() - INTERVAL '14 days' THEN 'grace'
    ELSE 'inactive'
  END FROM op;
$$;

GRANT EXECUTE ON FUNCTION effective_subscription_status(UUID) TO authenticated, anon;
