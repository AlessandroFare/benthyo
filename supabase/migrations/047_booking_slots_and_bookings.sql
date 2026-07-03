-- Migration 047: Booking slots + customer-facing bookings with Stripe.
--
-- Extends the operator scheduling schema (041) with pay-at-booking slots.
--
-- New tables:
--   booking_slots    — operator-published time slots with price & capacity
--   bookings         — diver-initiated bookings with Stripe payment intent
--
-- Flow:
--   1. Operator creates a booking_slot (date, time, site, price, max_capacity)
--   2. Diver browses available slots and creates a booking
--   3. Booking triggers Stripe PaymentIntent creation
--   4. Payment confirmed -> booking.status = 'confirmed', roster entry created
--   5. On booking day -> roster entry checked in by operator

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'booking_status') THEN
    CREATE TYPE booking_status AS ENUM (
      'pending_payment', 'confirmed', 'checked_in', 'cancelled', 'refunded'
    );
  END IF;
END$$;

-- ---------------------------------------------------------------------------
-- booking_slots — operator-published bookable slots
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS booking_slots (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  operator_id    UUID NOT NULL REFERENCES operators(id) ON DELETE CASCADE,
  dive_site_id   UUID REFERENCES dive_sites(id) ON DELETE SET NULL,
  site_label     TEXT,
  trip_date      DATE NOT NULL,
  depart_at      TIMESTAMPTZ,
  boat_id        UUID REFERENCES operator_boats(id) ON DELETE SET NULL,
  guide_id       UUID REFERENCES users(id) ON DELETE SET NULL,
  price_cents    INTEGER NOT NULL CHECK (price_cents >= 0),
  currency       TEXT NOT NULL DEFAULT 'eur',
  max_capacity   SMALLINT NOT NULL DEFAULT 8 CHECK (max_capacity > 0),
  booked_count   SMALLINT NOT NULL DEFAULT 0 CHECK (booked_count <= max_capacity),
  is_active      BOOLEAN NOT NULL DEFAULT true,
  description    TEXT,
  created_by     UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_booking_slots_operator_date
  ON booking_slots(operator_id, trip_date);
CREATE INDEX IF NOT EXISTS idx_booking_slots_active_date
  ON booking_slots(trip_date) WHERE is_active AND booked_count < max_capacity;

-- ---------------------------------------------------------------------------
-- bookings — diver-bought bookings with Stripe payment
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bookings (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slot_id             UUID NOT NULL REFERENCES booking_slots(id) ON DELETE CASCADE,
  user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  operator_id         UUID NOT NULL REFERENCES operators(id) ON DELETE CASCADE,
  status              booking_status NOT NULL DEFAULT 'pending_payment',
  price_cents         INTEGER NOT NULL CHECK (price_cents >= 0),
  currency            TEXT NOT NULL DEFAULT 'eur',
  -- Stripe payment tracking
  stripe_payment_intent_id  TEXT,
  stripe_client_secret      TEXT,
  paid_at             TIMESTAMPTZ,
  -- Diver details at booking time
  diver_name          TEXT,
  diver_email         TEXT,
  diver_phone         TEXT,
  waiver_signed       BOOLEAN NOT NULL DEFAULT false,
  medical_complete    BOOLEAN NOT NULL DEFAULT false,
  notes               TEXT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_bookings_user ON bookings(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bookings_slot ON bookings(slot_id);
CREATE INDEX IF NOT EXISTS idx_bookings_operator ON bookings(operator_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_bookings_stripe_pi ON bookings(stripe_payment_intent_id)
  WHERE stripe_payment_intent_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- RLS: divers read/write own bookings; operator members read their slots
-- ---------------------------------------------------------------------------
ALTER TABLE booking_slots ENABLE ROW LEVEL SECURITY;
ALTER TABLE bookings ENABLE ROW LEVEL SECURITY;

-- booking_slots: anyone authenticated can read active slots; operator admins write
CREATE POLICY booking_slots_select ON booking_slots
  FOR SELECT USING (
    is_operator_member(operator_id)
    OR (is_active AND booked_count < max_capacity)
  );

CREATE POLICY booking_slots_insert ON booking_slots
  FOR INSERT WITH CHECK (is_operator_admin(operator_id));

CREATE POLICY booking_slots_update ON booking_slots
  FOR UPDATE USING (is_operator_admin(operator_id))
  WITH CHECK (is_operator_admin(operator_id));

CREATE POLICY booking_slots_delete ON booking_slots
  FOR DELETE USING (is_operator_admin(operator_id));

-- bookings: diver sees own; operator members see their operator's bookings
CREATE POLICY bookings_select ON bookings
  FOR SELECT USING (user_id = auth.uid() OR is_operator_member(operator_id));

CREATE POLICY bookings_insert ON bookings
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY bookings_update ON bookings
  FOR UPDATE USING (user_id = auth.uid() OR is_operator_admin(operator_id))
  WITH CHECK (user_id = auth.uid() OR is_operator_admin(operator_id));

-- ---------------------------------------------------------------------------
-- Functions
-- ---------------------------------------------------------------------------

-- Book a slot: atomically increment booked_count and create booking
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
  v_slot       booking_slots%ROWTYPE;
  v_booking    bookings;
BEGIN
  -- Lock the slot row to prevent race conditions
  SELECT * INTO v_slot
  FROM booking_slots
  WHERE id = p_slot_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Slot not found');
  END IF;

  IF NOT v_slot.is_active THEN
    RETURN jsonb_build_object('error', 'Slot is not active');
  END IF;

  IF v_slot.booked_count >= v_slot.max_capacity THEN
    RETURN jsonb_build_object('error', 'Slot is fully booked');
  END IF;

  -- Increment booked count
  UPDATE booking_slots
  SET booked_count = booked_count + 1,
      updated_at = now()
  WHERE id = p_slot_id;

  -- Create booking
  INSERT INTO bookings (
    slot_id, user_id, operator_id, status, price_cents, currency,
    diver_name, diver_email, diver_phone
  ) VALUES (
    p_slot_id, p_user_id, p_operator_id, 'pending_payment',
    v_slot.price_cents, v_slot.currency,
    COALESCE(p_diver_name, (SELECT full_name FROM users WHERE id = p_user_id)),
    p_diver_email,
    p_diver_phone
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

GRANT EXECUTE ON FUNCTION book_slot(UUID, UUID, UUID, TEXT, TEXT, TEXT) TO authenticated;

-- Confirm booking after Stripe payment confirmed
CREATE OR REPLACE FUNCTION confirm_booking(
  p_booking_id UUID,
  p_payment_intent_id TEXT,
  p_client_secret TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking bookings%ROWTYPE;
BEGIN
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

  -- Create roster entry for the operator's daily view
  INSERT INTO trip_roster_entries (trip_id, operator_id, customer_id, status)
  VALUES (
    (SELECT id FROM operator_trip_schedule
      WHERE id = (SELECT slot_id FROM bookings WHERE id = p_booking_id)
      LIMIT 1),
    v_booking.operator_id,
    v_booking.user_id,
    'booked'
  )
  ON CONFLICT DO NOTHING;

  RETURN jsonb_build_object(
    'booking_id', v_booking.id,
    'status', v_booking.status,
    'paid_at', v_booking.paid_at
  );
END;
$$;

GRANT EXECUTE ON FUNCTION confirm_booking(UUID, TEXT, TEXT) TO authenticated;

-- Cancel booking (diver or operator admin)
CREATE OR REPLACE FUNCTION cancel_booking(
  p_booking_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking bookings%ROWTYPE;
BEGIN
  UPDATE bookings
  SET status = 'cancelled',
      updated_at = now()
  WHERE id = p_booking_id
    AND status IN ('pending_payment', 'confirmed')
  RETURNING * INTO v_booking;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Booking not found or cannot be cancelled');
  END IF;

  -- Decrement slot count
  UPDATE booking_slots
  SET booked_count = GREATEST(0, booked_count - 1),
      updated_at = now()
  WHERE id = v_booking.slot_id;

  RETURN jsonb_build_object(
    'booking_id', v_booking.id,
    'status', v_booking.status
  );
END;
$$;

GRANT EXECUTE ON FUNCTION cancel_booking(UUID) TO authenticated;
