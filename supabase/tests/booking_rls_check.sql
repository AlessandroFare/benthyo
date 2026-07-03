-- Booking RLS + RPC authorization live check (run against a migrated DB).
-- Complements rls.sql which has no booking section. Verifies:
--   1. operator admin can create a slot on their own operator (RLS)
--   2. stranger cannot create a slot on another operator (RLS)
--   3. book_slot pins caller to auth.uid() (cannot book as another user)
--   4. cancel_booking: owner OR operator-admin only; stranger denied
--   5. confirm_booking: service_role ONLY (diver denied) [payment-bypass closed]

-- Seed test users as the superuser (postgres) inside a DO block (RLS-exempt).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = '00000000-0000-0000-0000-000000000099') THEN
    INSERT INTO auth.users (id, instance_id, aud, role, email, raw_user_meta_data)
    VALUES ('00000000-0000-0000-0000-000000000099','00000000-0000-0000-0000-000000000000','authenticated','authenticated','dave@test.local','{"username":"dave"}');
  END IF;
  INSERT INTO public.users (id, username) VALUES ('00000000-0000-0000-0000-000000000099','dave') ON CONFLICT (id) DO NOTHING;

  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = '00000000-0000-0000-0000-000000000098') THEN
    INSERT INTO auth.users (id, instance_id, aud, role, email, raw_user_meta_data)
    VALUES ('00000000-0000-0000-0000-000000000098','00000000-0000-0000-0000-000000000000','authenticated','authenticated','erin@test.local','{"username":"erin"}');
  END IF;
  INSERT INTO public.users (id, username) VALUES ('00000000-0000-0000-0000-000000000098','erin') ON CONFLICT (id) DO NOTHING;
END$$;

-- ─── 1. operator admin (alice owns op-a) can create a slot ───────────────
DO $$
DECLARE v_opa UUID; v_site UUID; v_slot UUID;
BEGIN
  v_opa := '00000000-0000-0000-0000-000000000010';
  SELECT id INTO v_site FROM dive_sites LIMIT 1;
  SET LOCAL ROLE authenticated;
  SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';
  INSERT INTO booking_slots (operator_id, dive_site_id, trip_date, price_cents, currency, max_capacity, is_active, created_by)
  VALUES (v_opa, v_site, CURRENT_DATE + INTERVAL '7 days', 2500, 'eur', 4, true, '00000000-0000-0000-0000-000000000001')
  RETURNING id INTO v_slot;
  RAISE NOTICE 'OK: operator admin created slot %', v_slot;
END$$;

-- ─── 2. stranger (erin) cannot create a slot on op-a ─────────────────────
DO $$
DECLARE v_opa UUID; v_site UUID;
BEGIN
  v_opa := '00000000-0000-0000-0000-000000000010';
  SELECT id INTO v_site FROM dive_sites LIMIT 1;
  SET LOCAL ROLE authenticated;
  SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000098","role":"authenticated"}';
  BEGIN
    INSERT INTO booking_slots (operator_id, dive_site_id, trip_date, price_cents, currency, max_capacity, is_active, created_by)
    VALUES (v_opa, v_site, CURRENT_DATE + INTERVAL '8 days', 2500, 'eur', 4, true, '00000000-0000-0000-0000-000000000098');
    RAISE EXCEPTION 'TEST FAIL: stranger erin was able to INSERT a slot on op-a';
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN
    RAISE NOTICE 'OK: stranger erin cannot create a slot for op-a';
  END;
END$$;

-- ─── 3. book_slot pins caller to auth.uid() ──────────────────────────────
-- dave books the slot as himself (allowed), then tries to book AS erin (denied).
DO $$
DECLARE v_opa UUID; v_slot UUID; v_dave_book JSONB;
BEGIN
  v_opa := '00000000-0000-0000-0000-000000000010';
  SELECT id INTO v_slot FROM booking_slots WHERE operator_id = v_opa ORDER BY created_at DESC LIMIT 1;
  SET LOCAL ROLE authenticated;
  SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000099","role":"authenticated"}';
  -- dave books as himself: allowed
  SELECT book_slot(p_slot_id := v_slot, p_user_id := '00000000-0000-0000-0000-000000000099', p_operator_id := v_opa) INTO v_dave_book;
  RAISE NOTICE 'OK: dave booked as himself: %', v_dave_book;
  -- dave tries to book AS erin: book_slot returns a JSON error (does not RAISE)
  SELECT book_slot(p_slot_id := v_slot, p_user_id := '00000000-0000-0000-0000-000000000098', p_operator_id := v_opa) INTO v_dave_book;
  IF (v_dave_book->>'error') = 'Cannot book on behalf of another user' THEN
    RAISE NOTICE 'OK: book_slot rejects booking as another user';
  ELSE
    RAISE EXCEPTION 'TEST FAIL: dave booked as erin, result=%', v_dave_book;
  END IF;
END$$;

-- ─── 4. cancel_booking: stranger cannot cancel dave's booking ────────────
DO $$
DECLARE v_booking UUID;
BEGIN
  SELECT id INTO v_booking FROM bookings WHERE user_id = '00000000-0000-0000-0000-000000000099' LIMIT 1;
  SET LOCAL ROLE authenticated;
  SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000098","role":"authenticated"}';
  BEGIN
    PERFORM cancel_booking(p_booking_id := v_booking);
    RAISE EXCEPTION 'TEST FAIL: erin was able to cancel dave''s booking';
  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM LIKE '%Not authorized%' THEN
        RAISE NOTICE 'OK: stranger cannot cancel others booking';
      ELSE
        RAISE EXCEPTION 'Unexpected: %', SQLERRM;
      END IF;
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'OK: stranger cannot cancel others booking (insufficient_privilege)';
  END;
END$$;

-- ─── 5. confirm_booking as a diver (authenticated) must be DENIED ────────
DO $$
DECLARE v_booking UUID;
BEGIN
  SELECT id INTO v_booking FROM bookings WHERE user_id = '00000000-0000-0000-0000-000000000099' LIMIT 1;
  SET LOCAL ROLE authenticated;
  SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000099","role":"authenticated"}';
  BEGIN
    PERFORM confirm_booking(p_booking_id := v_booking, p_payment_intent_id := 'pi_fake', p_client_secret := 'cs_fake');
    RAISE EXCEPTION 'TEST FAIL: dave (authenticated) was able to confirm_booking (payment bypass!)';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: confirm_booking denied to authenticated (payment-bypass closed)';
  END;
END$$;

\echo '✓ All booking RLS/RPC checks passed.'
