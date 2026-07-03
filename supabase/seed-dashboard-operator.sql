-- Link a Supabase Auth user to a demo operator for the B2B dashboard.
-- Run AFTER creating a user in Supabase Auth (email/password signup or Studio).
--
-- 1. Get your Auth user UUID (replace the email):
--    SELECT id FROM auth.users WHERE email = 'asgana8@gmail.com';
-- 2. Replace the UUID below if it does not match your login
-- 3. psql "postgresql://postgres:postgres@127.0.0.1:54322/benthyo" -f supabase/seed-dashboard-operator.sql

INSERT INTO operator_users (operator_id, user_id, role)
SELECT id, '2ed73b83-abf0-4e4a-b30a-54680869f4a3'::uuid, 'owner'
FROM operators
WHERE slug = 'diving-center-ustica'
LIMIT 1
ON CONFLICT (operator_id, user_id) DO UPDATE SET role = EXCLUDED.role;
