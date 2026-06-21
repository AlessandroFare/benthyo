-- RLS test suite for OceanLog.
--
-- This is a comprehensive RLS correctness test. Run with:
--   psql $DATABASE_URL -v ON_ERROR_STOP=1 -f supabase/tests/rls.sql
--
-- The test bootstraps fixtures under the calling user (typically
-- the migration owner / service role) and then verifies visibility
-- under `anon` and `authenticated` roles via SET LOCAL ROLE.
--
-- The tests cover the tables with the highest blast radius: the
-- multi-tenant tables (operators, operator_users, operator_payment_links)
-- and the privacy-sensitive tables (sightings, medical_form_submissions,
-- waiver_signatures, sighting_corrections).

BEGIN;

-- Test fixtures (only created if absent).
--
-- The user bootstrap must work in BOTH environments:
--   * CI: the `auth` schema is a bare shim (auth.users has only id+email,
--     no handle_new_auth_user trigger), so we insert public.users directly.
--   * Local / real Supabase: auth.users is the full GoTrue table and a
--     handle_new_auth_user trigger auto-creates public.users from
--     raw_user_meta_data. Inserting four ids that share the same first 8
--     chars makes the trigger's default username ('user_'||left(id,8))
--     collide, so we must supply a distinct `username` in the metadata.
-- We branch on whether auth.users has a raw_user_meta_data column.
DO $$
DECLARE has_meta BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'auth' AND table_name = 'users'
      AND column_name = 'raw_user_meta_data'
  ) INTO has_meta;

  IF has_meta THEN
    -- Real Supabase: seed auth.users with username metadata; the trigger
    -- populates public.users with the distinct usernames.
    INSERT INTO auth.users (id, instance_id, aud, role, email, raw_user_meta_data) VALUES
      ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','alice@test.local','{"username":"alice"}'),
      ('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','bob@test.local','{"username":"bob"}'),
      ('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','carol@test.local','{"username":"carol"}'),
      ('00000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','expert@test.local','{"username":"expert"}')
    ON CONFLICT (id) DO NOTHING;
  ELSE
    -- CI shim: minimal auth.users + direct public.users.
    INSERT INTO auth.users (id, email) VALUES
      ('00000000-0000-0000-0000-000000000001','alice@test.local'),
      ('00000000-0000-0000-0000-000000000002','bob@test.local'),
      ('00000000-0000-0000-0000-000000000003','carol@test.local'),
      ('00000000-0000-0000-0000-000000000004','expert@test.local')
    ON CONFLICT (id) DO NOTHING;
    INSERT INTO users (id, username) VALUES
      ('00000000-0000-0000-0000-000000000001', 'alice'),
      ('00000000-0000-0000-0000-000000000002', 'bob'),
      ('00000000-0000-0000-0000-000000000003', 'carol'),
      ('00000000-0000-0000-0000-000000000004', 'expert')
    ON CONFLICT (id) DO NOTHING;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM operators WHERE id = '00000000-0000-0000-0000-000000000010') THEN
    -- subscription_tier='starter' so the multi-member / multi-site fixtures
    -- below fit under the tier caps enforced by migration 045's triggers
    -- (free caps team at 1; the suite seeds 2 members in OpA). Setting tier
    -- at INSERT time is fine — the 036 self-upgrade guard is BEFORE UPDATE.
    INSERT INTO operators (id, name, slug, operator_type, subscription_tier) VALUES
      ('00000000-0000-0000-0000-000000000010', 'OpA', 'opa', 'dive_center', 'starter'),
      ('00000000-0000-0000-0000-000000000011', 'OpB', 'opb', 'dive_center', 'starter');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM operator_users WHERE operator_id = '00000000-0000-0000-0000-000000000010') THEN
    INSERT INTO operator_users (operator_id, user_id, role) VALUES
      ('00000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000001', 'owner'),
      ('00000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000002', 'staff'),
      ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000003', 'owner');
  END IF;
  UPDATE users SET taxonomy_expert = true WHERE id = '00000000-0000-0000-0000-000000000004';

  -- Reference-data fixtures (species). species RLS restricts INSERT to
  -- service_role, so create the test species here in the bootstrap block,
  -- which runs as the migration owner (RLS-exempt), not under SET ROLE.
  INSERT INTO species (id, scientific_name)
  VALUES ('00000000-0000-0000-0000-000000000030', 'Test species')
  ON CONFLICT DO NOTHING;
END$$;

-- ─── 1. operator_users self-referential RLS (no recursion after 025) ────
DO $$
DECLARE
  v_count INTEGER;
BEGIN
  SET LOCAL ROLE authenticated;
  SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';
  SELECT count(*) INTO v_count
    FROM operator_users
    WHERE operator_id = '00000000-0000-0000-0000-000000000010';
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'alice (OpA owner) should see 2 members in OpA, got %', v_count;
  END IF;
  -- Cross-tenant: alice should see 0 OpB members.
  SELECT count(*) INTO v_count
    FROM operator_users
    WHERE operator_id = '00000000-0000-0000-0000-000000000011';
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'alice should not see OpB members, got %', v_count;
  END IF;
  RESET ROLE;
END$$;

-- ─── 2. medical_form_submissions: operator cannot UPDATE another
--       operator's submission (DD-1.5 / C-1) ───────────────────────────
DO $$
DECLARE
  v_template_id UUID;
  v_count       INTEGER;
BEGIN
  SET LOCAL ROLE authenticated;
  -- Use a regular user (alice) to write a submission; then escalate
  -- to bob who is staff of OpA but the submission is for OpB; the
  -- UPDATE should affect 0 rows.
  SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000003","role":"authenticated"}';
  SELECT id INTO v_template_id FROM medical_form_templates
    WHERE operator_id IS NULL AND is_active = true LIMIT 1;
  -- answers is BYTEA since migration 030; encrypt the plaintext with the
  -- per-operator key (dev fallback in tests) instead of casting jsonb in.
  INSERT INTO medical_form_submissions (
    user_id, operator_id, template_id, answers, signer_name
  )
  VALUES (
    '00000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000011',
    v_template_id,
    encrypt_medical_answers('00000000-0000-0000-0000-000000000011', '{"heart": false}'::jsonb),
    'Carol'
  );

  -- Switch to alice who is NOT a member of OpB. The mutation
  -- should NOT succeed.
  SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';
  UPDATE medical_form_submissions
    SET signer_name = 'Alice was here'
    WHERE operator_id = '00000000-0000-0000-0000-000000000011';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'alice (non-member of OpB) was able to UPDATE % rows in OpB medical submissions', v_count;
  END IF;
  RESET ROLE;
  -- Clean up: the migration 030 changed answers to BYTEA. If
  -- applied, we use the placeholder value. Either way, the test
  -- above is the source of truth.
  DELETE FROM medical_form_submissions
    WHERE operator_id = '00000000-0000-0000-0000-000000000011';
END$$;

-- ─── 3. sighting_corrections: only the reporter / sighting owner /
--       expert can UPDATE (DD-1.1) ────────────────────────────────────
DO $$
DECLARE
  v_dummy_site   UUID;
  v_alice_sighting UUID;
  v_correction_id UUID;
  v_count INTEGER;
BEGIN
  SET LOCAL ROLE authenticated;
  -- Act as alice from the start: the dive_sites INSERT policy checks
  -- auth.uid(), so the JWT claim must be set BEFORE the insert (previously
  -- it was set only after, leaving auth.uid() NULL → RLS denial).
  SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';
  -- Create a dive site for alice
  INSERT INTO dive_sites (id, name, slug, location, country_code, depth_min,
                          depth_max, difficulty, site_type, access_type, created_by)
  VALUES (
    '00000000-0000-0000-0000-000000000020', 'SiteA', 'site-a',
    ST_MakePoint(10, 45)::geography, 'IT', 0, 30, 'beginner', 'reef', 'shore',
    '00000000-0000-0000-0000-000000000001'
  )
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_dummy_site;
  v_dummy_site := '00000000-0000-0000-0000-000000000020';
  -- (Test species pre-created in the bootstrap block; species INSERT is
  -- service_role-only so it cannot be created here under authenticated.)

  -- Alice's sighting.
  SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';
  INSERT INTO sightings (id, user_id, dive_site_id, species_id, observed_at,
                        count, source)
  VALUES (
    '00000000-0000-0000-0000-000000000040',
    '00000000-0000-0000-0000-000000000001',
    v_dummy_site,
    '00000000-0000-0000-0000-000000000030',
    now(),
    1,
    'user'
  )
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_alice_sighting;
  v_alice_sighting := '00000000-0000-0000-0000-000000000040';

  -- Bob (not the owner, not an expert) suggests a correction.
  SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}';
  INSERT INTO sighting_corrections (
    sighting_id, reporter_id, proposed_species_id, reason
  )
  VALUES (
    v_alice_sighting,
    '00000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000030',
    'Wrong species'
  )
  RETURNING id INTO v_correction_id;

  -- Random user Carol (not reporter, not owner, not expert) tries to
  -- accept the correction. Should affect 0 rows.
  SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000003","role":"authenticated"}';
  UPDATE sighting_corrections
    SET status = 'accepted', resolver_id = '00000000-0000-0000-0000-000000000003'
    WHERE id = v_correction_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'carol (random user) was able to UPDATE correction %', v_correction_id;
  END IF;

  -- Alice (the sighting owner) accepts the correction. Should succeed.
  SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';
  UPDATE sighting_corrections
    SET status = 'accepted', resolver_id = '00000000-0000-0000-0000-000000000001'
    WHERE id = v_correction_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'alice (sighting owner) could not accept her own correction';
  END IF;
  RESET ROLE;

  -- Cleanup.
  DELETE FROM sighting_corrections WHERE id = v_correction_id;
  DELETE FROM sightings WHERE id = v_alice_sighting;
  DELETE FROM dive_sites WHERE id = v_dummy_site;
  DELETE FROM species WHERE id = '00000000-0000-0000-0000-000000000030';
END$$;

-- ─── 4. sightings: self-verify is blocked at the RLS layer (C-3 / 044) ──
-- Migration 044 added the prevent_self_verify_columns trigger so the RLS
-- layer ALSO forbids a reporter from setting verified_by/verified_at on
-- their own sighting (previously this was only enforced in the API). This
-- test asserts the reporter self-verify now raises.
DO $$
DECLARE
  v_sighting_id UUID := '00000000-0000-0000-0000-000000000041';
BEGIN
  -- Reference data created as the migration owner (RLS-exempt): dive site
  -- for the FK + a test species (species INSERT is service_role-only).
  INSERT INTO dive_sites (id, name, slug, location, country_code, depth_min,
                          depth_max, difficulty, site_type, access_type, created_by)
  VALUES (
    '00000000-0000-0000-0000-000000000021', 'SiteB', 'site-b',
    ST_MakePoint(11, 46)::geography, 'IT', 0, 30, 'beginner', 'reef', 'shore',
    '00000000-0000-0000-0000-000000000001'
  )
  ON CONFLICT DO NOTHING;
  INSERT INTO species (id, scientific_name)
  VALUES ('00000000-0000-0000-0000-000000000031', 'Test species 2')
  ON CONFLICT DO NOTHING;

  SET LOCAL ROLE authenticated;
  SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';
  INSERT INTO sightings (id, user_id, dive_site_id, species_id, observed_at,
                        count, source)
  VALUES (
    v_sighting_id,
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000021',
    '00000000-0000-0000-0000-000000000031',
    now(),
    1,
    'user'
  )
  ON CONFLICT DO NOTHING;

  -- Alice (reporter, not a taxonomy expert) tries to self-verify. The
  -- prevent_self_verify_columns trigger (migration 044) must reject it.
  BEGIN
    UPDATE sightings
      SET verified_by = '00000000-0000-0000-0000-000000000001',
          verified_at = now(),
          confidence_level = 'certain'
      WHERE id = v_sighting_id;
    RAISE EXCEPTION 'reporter self-verify was NOT blocked at the RLS layer';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;  -- Expected.
  END;
  RESET ROLE;

  -- A non-verification update by the reporter still works (confidence only).
  SET LOCAL ROLE authenticated;
  SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';
  UPDATE sightings SET confidence_level = 'certain' WHERE id = v_sighting_id;
  RESET ROLE;

  DELETE FROM sightings WHERE id = v_sighting_id;
  DELETE FROM dive_sites WHERE id = '00000000-0000-0000-0000-000000000021';
  DELETE FROM species WHERE id = '00000000-0000-0000-0000-000000000031';
END$$;

-- ─── 5. operators: subscription_tier is column-restricted (C-6) ───
-- An operator owner CANNOT change their own subscription_tier. Only
-- the set_operator_subscription SECURITY DEFINER function can.
DO $$
BEGIN
  SET LOCAL ROLE authenticated;
  SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';
  -- Migration 036 replaced the no-op WITH CHECK self-reference with a
  -- BEFORE UPDATE trigger that RAISES, so a direct self-upgrade now errors
  -- (rather than silently affecting 0 rows).
  BEGIN
    UPDATE operators
      SET subscription_tier = 'pro'
      WHERE id = '00000000-0000-0000-0000-000000000010';
    RAISE EXCEPTION 'operator owner was able to self-upgrade subscription_tier';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;  -- Expected: prevent_subscription_self_upgrade raises 42501.
  END;
  RESET ROLE;
END$$;

-- ─── 5b. export_user_data: an operator admin can only export a user who
--        shares one of the caller's operators (migration 037) ──────────
DO $$
DECLARE
  v_ok BOOLEAN;
BEGIN
  SET LOCAL ROLE authenticated;

  -- carol is owner of OpB and shares NO operator with alice (OpA only).
  -- carol attempting to export alice must be rejected.
  SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000003","role":"authenticated"}';
  BEGIN
    PERFORM export_user_data('00000000-0000-0000-0000-000000000001');
    RAISE EXCEPTION 'carol (no shared operator) was able to export alice''s data';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL; -- expected (ERRCODE 42501)
  END;

  -- alice is owner of OpA and bob is staff of OpA: they share an operator,
  -- so alice exporting bob must succeed.
  SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';
  SELECT (export_user_data('00000000-0000-0000-0000-000000000002') ? 'profile')
    INTO v_ok;
  IF NOT v_ok THEN
    RAISE EXCEPTION 'alice (shares OpA with bob) could not export bob''s data';
  END IF;

  -- Self-export always works.
  SELECT (export_user_data('00000000-0000-0000-0000-000000000001') ? 'profile')
    INTO v_ok;
  IF NOT v_ok THEN
    RAISE EXCEPTION 'alice could not export her own data';
  END IF;

  RESET ROLE;
END$$;

-- ─── 6. operator_waivers: signed waivers cannot be deleted (DD-1.2) ───
DO $$
DECLARE
  v_waiver_id  UUID;
  v_dummy_site UUID;
BEGIN
  INSERT INTO dive_sites (id, name, slug, location, country_code, depth_min,
                          depth_max, difficulty, site_type, access_type, created_by)
  VALUES (
    '00000000-0000-0000-0000-000000000022', 'SiteC', 'site-c',
    ST_MakePoint(12, 47)::geography, 'IT', 0, 30, 'beginner', 'reef', 'shore',
    '00000000-0000-0000-0000-000000000001'
  )
  ON CONFLICT DO NOTHING;
  v_dummy_site := '00000000-0000-0000-0000-000000000022';

  INSERT INTO operator_waivers (id, operator_id, title, body, version,
                                 is_active)
  VALUES (
    '00000000-0000-0000-0000-000000000050',
    '00000000-0000-0000-0000-000000000010',
    'Test',
    'Test body content here for legal coverage',
    1, true
  )
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_waiver_id;
  v_waiver_id := '00000000-0000-0000-0000-000000000050';

  -- Add a signature to the waiver.
  INSERT INTO waiver_signatures (waiver_id, operator_id, user_id, signer_name,
                                ip_address, user_agent, signed_waiver_text_hash,
                                signed_waiver_version)
  VALUES (v_waiver_id, '00000000-0000-0000-0000-000000000010',
          '00000000-0000-0000-0000-000000000001', 'Alice',
          '127.0.0.1'::inet, 'jest', 'abc123', 1);

  -- Attempt to delete the waiver. The trigger should block it.
  SET LOCAL ROLE authenticated;
  SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';
  BEGIN
    DELETE FROM operator_waivers WHERE id = v_waiver_id;
    RAISE EXCEPTION 'DELETE of signed waiver was NOT blocked';
  EXCEPTION WHEN check_violation THEN
    -- Expected.
    NULL;
  END;
  RESET ROLE;
  DELETE FROM waiver_signatures WHERE waiver_id = v_waiver_id;
  DELETE FROM operator_waivers WHERE id = v_waiver_id;
  DELETE FROM dive_sites WHERE id = v_dummy_site;
END$$;

-- ─── 7. operators: subscription tier cannot be self-upgraded (C-6 / 036) ───
DO $$
BEGIN
  SET LOCAL ROLE authenticated;
  SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';
  BEGIN
    UPDATE operators SET subscription_tier = 'pro'
    WHERE id = '00000000-0000-0000-0000-000000000010';
    RAISE EXCEPTION 'subscription_tier self-upgrade was NOT blocked';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;  -- Expected: prevent_subscription_self_upgrade raises 42501.
  END;
  RESET ROLE;
END$$;

-- ─── 8. sightings: reporter cannot self-verify; non-expert cannot verify ───
DO $$
DECLARE
  v_site UUID := '00000000-0000-0000-0000-000000000023';
  v_sp   UUID;
  v_sig  UUID := '00000000-0000-0000-0000-000000000060';
BEGIN
  INSERT INTO dive_sites (id, name, slug, location, country_code, depth_min,
                          depth_max, difficulty, site_type, access_type, created_by)
  VALUES (v_site, 'SiteV', 'site-v', ST_MakePoint(13, 46)::geography, 'IT',
          0, 30, 'beginner', 'reef', 'shore',
          '00000000-0000-0000-0000-000000000001')
  ON CONFLICT DO NOTHING;

  SELECT id INTO v_sp FROM species LIMIT 1;
  IF v_sp IS NULL THEN
    INSERT INTO species (id, scientific_name)
    VALUES ('00000000-0000-0000-0000-000000000070', 'Testus marinus')
    ON CONFLICT DO NOTHING;
    v_sp := '00000000-0000-0000-0000-000000000070';
  END IF;

  -- Alice reports a sighting.
  INSERT INTO sightings (id, user_id, dive_site_id, species_id, observed_at, source)
  VALUES (v_sig, '00000000-0000-0000-0000-000000000001', v_site, v_sp,
          now(), 'user')
  ON CONFLICT DO NOTHING;

  -- Alice (the reporter, not an expert) tries to verify her own sighting.
  SET LOCAL ROLE authenticated;
  SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';
  BEGIN
    UPDATE sightings
    SET verified_by = '00000000-0000-0000-0000-000000000001', verified_at = now()
    WHERE id = v_sig;
    RAISE EXCEPTION 'reporter self-verify was NOT blocked';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;  -- Expected: prevent_self_verify_columns raises 42501.
  END;
  RESET ROLE;

  -- The expert (taxonomy_expert = true, different user) CAN verify it.
  SET LOCAL ROLE authenticated;
  SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000004","role":"authenticated"}';
  UPDATE sightings
  SET verified_by = '00000000-0000-0000-0000-000000000004', verified_at = now()
  WHERE id = v_sig;
  IF NOT EXISTS (
    SELECT 1 FROM sightings WHERE id = v_sig AND verified_by IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'expert verification did not take effect';
  END IF;
  RESET ROLE;

  DELETE FROM sightings WHERE id = v_sig;
  DELETE FROM dive_sites WHERE id = v_site;
END$$;

COMMIT;

\echo '✓ All OceanLog RLS tests passed.'
