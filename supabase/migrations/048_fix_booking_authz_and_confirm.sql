-- Migration 048: fix authorization + correctness bugs in the booking RPCs
-- introduced by migration 047.
--
-- Bugs found in the Round-2 verification pass:
--
--  1. CRITICAL (payment bypass): confirm_booking() is SECURITY DEFINER and
--     was GRANTed to `authenticated` with NO caller check. Any diver could
--     call confirm_booking(their_booking_id, 'fake_pi', 'fake_secret')
--     directly via PostgREST and mark a PAID booking confirmed/paid without
--     ever paying. confirm_booking must be callable ONLY by the Stripe
--     webhook (service_role).
--
--  2. CRITICAL (broken confirm): confirm_booking inserted a
--     trip_roster_entries row with trip_id taken from
--     operator_trip_schedule WHERE id = booking_slots.slot_id — two
--     unrelated tables, so the subquery is always NULL. trip_id is NOT
--     NULL, so the INSERT raised and rolled back EVERY paid confirmation.
--     booking_slots are not trip_schedule rows; drop the bogus roster
--     insert (roster integration is a separate, future concern).
--
--  3. HIGH (cancel any booking): cancel_booking() is SECURITY DEFINER,
--     GRANTed to `authenticated`, with no ownership check — any user could
--     cancel ANY booking by id. Enforce caller = booking owner OR operator
--     admin inside the function.
--
--  4. MEDIUM (book as another user): book_slot() is SECURITY DEFINER and
--     RLS-exempt, and trusted its p_user_id argument, so a direct call
--     could create a booking for an arbitrary user_id. Pin to auth.uid()
--     for non-service callers, and confirm free (price 0) slots inline so
--     the API no longer needs to call confirm_booking for them.
--
-- All changes are CREATE OR REPLACE + REVOKE/GRANT — additive, no drops of
-- data or columns.

-- ---------------------------------------------------------------------------
-- 4. book_slot: pin user to the caller (unless service_role); auto-confirm
--    free slots.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION book_slot(
  p_slot_id         UUID,
  p_user_id         UUID,
  p_operator_id     UUID,
  p_diver_name      TEXT DEFAULT NULL,
  p_diver_email     TEXT DEFAULT NULL,
  p_diver_phone     TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_slot    booking_slots%ROWTYPE;
  v_booking bookings;
  v_uid     UUID := auth.uid();
  v_status  TEXT;
BEGIN
  -- Non-service callers may only book for themselves.
  IF current_setting('role', true) <> 'service_role'
     AND v_uid IS NOT NULL
     AND p_user_id <> v_uid THEN
    RETURN jsonb_build_object('error', 'Cannot book on behalf of another user');
  END IF;

  SELECT * INTO v_slot FROM booking_slots WHERE id = p_slot_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Slot not found');
  END IF;
  IF NOT v_slot.is_active THEN
    RETURN jsonb_build_object('error', 'Slot is not active');
  END IF;
  IF v_slot.booked_count >= v_slot.max_capacity THEN
    RETURN jsonb_build_object('error', 'Slot is fully booked');
  END IF;

  UPDATE booking_slots
  SET booked_count = booked_count + 1, updated_at = now()
  WHERE id = p_slot_id;

  -- Free slots are confirmed immediately; paid slots await Stripe.
  v_status := CASE WHEN COALESCE(v_slot.price_cents, 0) = 0
                   THEN 'confirmed' ELSE 'pending_payment' END;

  INSERT INTO bookings (
    slot_id, user_id, operator_id, status, price_cents, currency,
    diver_name, diver_email, diver_phone, paid_at
  ) VALUES (
    p_slot_id, p_user_id, v_slot.operator_id, v_status::booking_status,
    v_slot.price_cents, v_slot.currency,
    COALESCE(p_diver_name, (SELECT full_name FROM users WHERE id = p_user_id)),
    p_diver_email, p_diver_phone,
    CASE WHEN v_status = 'confirmed' THEN now() ELSE NULL END
  )
  RETURNING * INTO v_booking;

  RETURN jsonb_build_object(
    'booking_id', v_booking.id,
    'price_cents', v_booking.price_cents,
    'currency', v_booking.currency,
    'status', v_booking.status
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 1 + 2. confirm_booking: service_role only; drop the broken roster insert.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION confirm_booking(
  p_booking_id        UUID,
  p_payment_intent_id TEXT,
  p_client_secret     TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking bookings%ROWTYPE;
BEGIN
  -- Only the Stripe webhook (service_role) may confirm payment.
  IF current_setting('role', true) <> 'service_role' THEN
    RAISE EXCEPTION 'confirm_booking may only be called by the payment webhook'
      USING ERRCODE = '42501';
  END IF;

  UPDATE bookings
  SET status = 'confirmed',
      stripe_payment_intent_id = p_payment_intent_id,
      stripe_client_secret = p_client_secret,
      paid_at = now(),
      updated_at = now()
  WHERE id = p_booking_id AND status = 'pending_payment'
  RETURNING * INTO v_booking;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Booking not found or already confirmed');
  END IF;

  RETURN jsonb_build_object(
    'booking_id', v_booking.id,
    'status', v_booking.status,
    'paid_at', v_booking.paid_at
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION confirm_booking(UUID, TEXT, TEXT) FROM authenticated, PUBLIC;
GRANT EXECUTE ON FUNCTION confirm_booking(UUID, TEXT, TEXT) TO service_role;

-- book_slot stays accessible to authenticated (API calls it on behalf of
-- the logged-in diver) but the function body now enforces auth.uid() match.
-- cancel_booking stays accessible to authenticated (diver or operator admin)
-- and the function body enforces ownership or operator admin role.
GRANT EXECUTE ON FUNCTION book_slot(UUID, UUID, UUID, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION cancel_booking(UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. cancel_booking: enforce owner-or-operator-admin.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION cancel_booking(p_booking_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking bookings%ROWTYPE;
BEGIN
  SELECT * INTO v_booking FROM bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Booking not found');
  END IF;

  IF current_setting('role', true) <> 'service_role'
     AND v_booking.user_id <> auth.uid()
     AND NOT is_operator_admin(v_booking.operator_id) THEN
    RAISE EXCEPTION 'Not authorized to cancel this booking'
      USING ERRCODE = '42501';
  END IF;

  UPDATE bookings
  SET status = 'cancelled', updated_at = now()
  WHERE id = p_booking_id
    AND status IN ('pending_payment', 'confirmed')
  RETURNING * INTO v_booking;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Booking cannot be cancelled');
  END IF;

  UPDATE booking_slots
  SET booked_count = GREATEST(0, booked_count - 1), updated_at = now()
  WHERE id = v_booking.slot_id;

  RETURN jsonb_build_object('booking_id', v_booking.id, 'status', v_booking.status);
END;
$$;
