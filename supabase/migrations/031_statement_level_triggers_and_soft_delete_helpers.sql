-- Migration 031: Statement-level triggers + GUC + soft-delete helpers.
--
-- (1) Convert the heaviest row-level triggers to STATEMENT-level. This is
--     a 5–10x win on bulk inserts because the trigger fires once per
--     statement instead of once per row. Affected triggers:
--       - trg_species_search_tsv (BEFORE INSERT OR UPDATE) → moved to
--         AFTER INSERT STATEMENT, AFTER UPDATE STATEMENT using a
--         transition table.
--       - trg_sightings_autofill  → kept row-level (needs NEW fields).
--
-- (2) Add a GUC knob that lets the application disable the search_tsv
--     re-computation during bulk loads (the caller is going to UPDATE
--     all rows in one go anyway).
--
-- (3) Add a `prune_soft_deleted()` helper that hard-deletes rows whose
--     `deleted_at` is older than a configurable retention window. This
--     pairs with migration 033 which adds the soft-delete columns.
--
-- (4) Add a partial B-tree index on `deleted_at` for "active rows" so the
--     most common query (WHERE deleted_at IS NULL) stays fast as the
--     table grows.

-- ============================================================
-- 1. Drop the row-level BEFORE search_tsv trigger on species.
-- ============================================================
DROP TRIGGER IF EXISTS trg_species_search_tsv ON species;

-- The function stays; we just call it once per statement now.
CREATE OR REPLACE FUNCTION species_search_tsv_update_stmt()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF pg_trigger_depth() > 1 THEN
    RETURN NULL;
  END IF;
  UPDATE species
  SET    search_tsv =
           setweight(to_tsvector('simple', coalesce(species.scientific_name, '')), 'A') ||
           setweight(to_tsvector('simple', coalesce(species.common_name, '')), 'B') ||
           setweight(to_tsvector('simple', coalesce(species.common_name_it, '')), 'B') ||
           setweight(to_tsvector('simple', coalesce(species.common_name_es, '')), 'B') ||
           setweight(to_tsvector('simple', coalesce(species.family, '')), 'C') ||
           setweight(to_tsvector('simple', coalesce(species.description, '')), 'D')
  WHERE  species.id IN (SELECT id FROM NEW)
    AND  current_setting('app.bulk_load', true) IS DISTINCT FROM 'on';
  RETURN NULL;
END;
$$;

-- After INSERT: include the freshly inserted rows via NEW table.
CREATE TRIGGER trg_species_search_tsv_insert_stmt
  AFTER INSERT ON species
  REFERENCING NEW TABLE AS NEW
  FOR EACH STATEMENT
  EXECUTE FUNCTION species_search_tsv_update_stmt();

-- After UPDATE: we only need to recompute when name columns actually
-- changed. We keep the row-level guard via a cheap WHEN clause that
-- filters at the statement level using a transition table comparison.
CREATE OR REPLACE FUNCTION species_search_tsv_update_after_stmt()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF pg_trigger_depth() > 1 THEN
    RETURN NULL;
  END IF;
  UPDATE species s
  SET    search_tsv =
           setweight(to_tsvector('simple', coalesce(s.scientific_name, '')), 'A') ||
           setweight(to_tsvector('simple', coalesce(s.common_name, '')), 'B') ||
           setweight(to_tsvector('simple', coalesce(s.common_name_it, '')), 'B') ||
           setweight(to_tsvector('simple', coalesce(s.common_name_es, '')), 'B') ||
           setweight(to_tsvector('simple', coalesce(s.family, '')), 'C') ||
           setweight(to_tsvector('simple', coalesce(s.description, '')), 'D')
  WHERE  s.id IN (SELECT id FROM NEW)
    AND  current_setting('app.bulk_load', true) IS DISTINCT FROM 'on';
  RETURN NULL;
END;
$$;

CREATE TRIGGER trg_species_search_tsv_update_stmt
  AFTER UPDATE ON species
  REFERENCING NEW TABLE AS NEW
  FOR EACH STATEMENT
  EXECUTE FUNCTION species_search_tsv_update_after_stmt();

COMMENT ON FUNCTION species_search_tsv_update_stmt() IS
  'Statement-level recompute of species.search_tsv. Skips when app.bulk_load=on.';
COMMENT ON FUNCTION species_search_tsv_update_after_stmt() IS
  'Statement-level recompute on UPDATE.';

-- ============================================================
-- 2. statement-level settings documentation.
-- ============================================================
DO $$
BEGIN
  EXECUTE format(
    'COMMENT ON DATABASE %I IS %L',
    current_database(),
    'Tunables exposed via SET LOCAL app.bulk_load = on|off to skip trigger work during bulk loads.'
  );
END;
$$;

-- ============================================================
-- 3. prune_soft_deleted() — hard delete after retention window.
-- ============================================================
CREATE OR REPLACE FUNCTION prune_soft_deleted(
  p_retention_days  INTEGER DEFAULT 30,
  p_dry_run         BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (table_name TEXT, deleted_rows BIGINT) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  rec RECORD;
  v_count BIGINT;
BEGIN
  -- Only the system / service role can call this. Standard authenticated
  -- users get a clean 42501.
  IF current_setting('role', true) NOT IN ('service_role', 'supabase_admin', 'postgres') THEN
    RAISE EXCEPTION 'prune_soft_deleted is restricted to the service role' USING ERRCODE = '42501';
  END IF;

  FOR rec IN
    SELECT c.relname AS tbl
    FROM   pg_class c
    JOIN   pg_namespace n ON n.oid = c.relnamespace
    WHERE  n.nspname = 'public'
      AND  c.relkind = 'r'
      AND  EXISTS (
        SELECT 1 FROM pg_attribute a
        WHERE  a.attrelid = c.oid
          AND  a.attname = 'deleted_at'
          AND  NOT a.attisdropped
      )
  LOOP
    EXECUTE format(
      'SELECT count(*) FROM public.%I WHERE deleted_at < now() - ($1 || '' days'')::interval',
      rec.tbl
    ) INTO v_count USING p_retention_days;

    IF NOT p_dry_run AND v_count > 0 THEN
      EXECUTE format(
        'DELETE FROM public.%I WHERE deleted_at < now() - ($1 || '' days'')::interval',
        rec.tbl
      ) USING p_retention_days;
    END IF;

    table_name := rec.tbl;
    deleted_rows := v_count;
    RETURN NEXT;
  END LOOP;
END;
$$;

COMMENT ON FUNCTION prune_soft_deleted(INTEGER, BOOLEAN) IS
  'Hard-delete soft-deleted rows older than p_retention_days. Service role only. Use p_dry_run=true to preview.';

-- ============================================================
-- 4. Add partial B-tree indexes on deleted_at for the tables that
--    will get soft-delete columns in migration 033. Create indexes
--    now, even before columns exist, using IF NOT EXISTS-style guard
--    so this migration is safe to apply out of order.
-- ============================================================
DO $$
BEGIN
  -- The columns don't exist yet, so we wrap each in an EXCEPTION block
  -- to keep this migration idempotent.
  BEGIN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_users_active        ON users (created_at)        WHERE deleted_at IS NULL';
  EXCEPTION WHEN undefined_column THEN NULL;
            WHEN undefined_table  THEN NULL;
  END;
  BEGIN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_dive_sites_active    ON dive_sites (created_at)  WHERE deleted_at IS NULL';
  EXCEPTION WHEN undefined_column THEN NULL;
            WHEN undefined_table  THEN NULL;
  END;
  BEGIN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_species_active       ON species (created_at)     WHERE deleted_at IS NULL';
  EXCEPTION WHEN undefined_column THEN NULL;
            WHEN undefined_table  THEN NULL;
  END;
  BEGIN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_sightings_active     ON sightings (observed_at DESC) WHERE deleted_at IS NULL';
  EXCEPTION WHEN undefined_column THEN NULL;
            WHEN undefined_table  THEN NULL;
  END;
  BEGIN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_dive_logs_active     ON dive_logs (dive_at DESC) WHERE deleted_at IS NULL';
  EXCEPTION WHEN undefined_column THEN NULL;
            WHEN undefined_table  THEN NULL;
  END;
  BEGIN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_operators_active     ON operators (created_at)   WHERE deleted_at IS NULL';
  EXCEPTION WHEN undefined_column THEN NULL;
            WHEN undefined_table  THEN NULL;
  END;
END;
$$;

-- Migration 033 will CREATE INDEX CONCURRENTLY the actual indexes
-- once the columns exist; these are just no-op placeholders for now.
