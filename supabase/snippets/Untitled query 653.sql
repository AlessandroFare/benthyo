INSERT INTO operator_users (operator_id, user_id, role)
SELECT id, '4dfdac53-55e5-4eae-8789-6361de5cabc5'::uuid, 'owner'
FROM operators WHERE slug = 'diving-center-ustica' LIMIT 1
ON CONFLICT (operator_id, user_id) DO UPDATE SET role = EXCLUDED.role;