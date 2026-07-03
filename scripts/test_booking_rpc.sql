-- Pre-clean + setup (needs to handle auth trigger, so do this idempotently)
INSERT INTO auth.users (id, email, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000001', 'test@test.com',
  jsonb_build_object('sub', '00000000-0000-0000-0000-000000000001', 'username', 'testuser', 'full_name', 'Test Diver'))
ON CONFLICT (id) DO NOTHING;

-- The auth trigger should have created public.users; if not, insert directly
INSERT INTO public.users (id, username, full_name)
VALUES ('00000000-0000-0000-0000-000000000001', 'testuser', 'Test Diver')
ON CONFLICT (id) DO NOTHING;

DELETE FROM bookings;
DELETE FROM booking_slots;
DELETE FROM operators WHERE slug = 'test-op';

INSERT INTO operators (id, slug, name, operator_type, subscription_tier)
VALUES ('00000000-0000-0000-0000-000000000001', 'test-op', 'Test Operator', 'dive_center', 'free');

INSERT INTO booking_slots (id, operator_id, trip_date, price_cents, max_capacity)
VALUES
  ('00000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000001', CURRENT_DATE + 7, 500, 5),
  ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001', CURRENT_DATE + 7, 0, 5);

-- TEST 1: Free slot -> auto-confirmed with paid_at set
BEGIN;
SELECT 'TEST 1: Free slot' AS test;
SELECT book_slot('00000000-0000-0000-0000-000000000011'::uuid, '00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000001'::uuid);
SELECT 'Result:' AS info, status, price_cents, paid_at IS NOT NULL AS paid FROM bookings WHERE slot_id = '00000000-0000-0000-0000-000000000011'::uuid;
DELETE FROM bookings;
UPDATE booking_slots SET booked_count = 0;
COMMIT;

-- TEST 2: Paid slot -> stays pending_payment
BEGIN;
SELECT 'TEST 2: Paid slot' AS test;
SELECT book_slot('00000000-0000-0000-0000-000000000010'::uuid, '00000000-0000-0000-0000-000000000001'::uuid, '00000000-0000-0000-0000-000000000001'::uuid);
SELECT 'Result:' AS info, status, price_cents, paid_at IS NOT NULL AS paid FROM bookings WHERE slot_id = '00000000-0000-0000-0000-000000000010'::uuid;
COMMIT;

-- TEST 3: confirm_booking as authenticated -> must be DENIED
BEGIN;
SELECT 'TEST 3: confirm_booking as authenticated' AS test;
SET LOCAL ROLE authenticated;
SELECT confirm_booking((SELECT id FROM bookings WHERE slot_id = '00000000-0000-0000-0000-000000000010'::uuid LIMIT 1), 'pi_test', 'secret');
COMMIT;
