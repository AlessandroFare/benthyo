GRANT USAGE ON SCHEMA public TO anon, authenticated;

GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;

-- Per le sequenze (se ci sono)
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;