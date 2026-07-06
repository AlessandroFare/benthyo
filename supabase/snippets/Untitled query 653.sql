INSERT INTO operator_users (operator_id, user_id, role)
SELECT id, '4834e8cb-8459-4e76-b8eb-52ad091f0a06'::uuid, 'owner'
FROM operators
WHERE slug = 'diving-center-ustica'
LIMIT 1
ON CONFLICT (operator_id, user_id) DO UPDATE SET role = EXCLUDED.role;