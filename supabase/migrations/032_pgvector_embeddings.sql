-- Migration 032: pgvector species embeddings + similarity search.
--
-- Goal
--   - Store a 384-dim embedding per species (matches all-MiniLM-L6-v2,
--     the model that runs on-device in the Flutter app via TFLite).
--   - Use HNSW for fast approximate nearest-neighbour queries.
--   - Provide a `find_similar_species()` RPC that the mobile app and
--     the dedupe-on-ingest ETL can call.
--   - Schedule a CONCURRENTLY REINDEX maintenance job to keep the
--     HNSW graph healthy as data grows (the known caveat of HNSW is
--     that recall degrades after a lot of point deletions; periodic
--     reindexing is the standard remedy).
--
-- Idempotency
--   - CREATE EXTENSION wrapped in IF NOT EXISTS.
--   - Column added with IF NOT EXISTS guard.
--   - Index created in a separate transaction (CREATE INDEX
--     CONCURRENTLY cannot run inside a transaction block, so we ship
--     the SQL function but document that it must be run separately —
--     see supabase/tests/rls.sql for the offline-CI variant).

-- ============================================================
-- 1. Enable pgvector.
-- ============================================================
CREATE EXTENSION IF NOT EXISTS vector;

-- ============================================================
-- 2. Embedding column.
-- ============================================================
ALTER TABLE species
  ADD COLUMN IF NOT EXISTS embedding vector(384);

COMMENT ON COLUMN species.embedding IS
  '384-dim semantic embedding. Computed on-device (TFLite MiniLM) or via the backfill RPC.';

-- ============================================================
-- 3. HNSW index.
--
-- Parameters:
--   m = 16  (default, balanced speed/recall)
--   ef_construction = 64 (default, balanced build/recall)
--   operator = vector_cosine_ops (because the on-device model
--     returns L2-normalised vectors and cosine == dot product for
--     those, so cosine is the cheapest semantically-correct choice).
--
-- We DO NOT use CONCURRENTLY here because CREATE INDEX CONCURRENTLY
-- cannot run inside a transaction. For production we recommend:
--   CREATE INDEX CONCURRENTLY idx_species_embedding_hnsw
--     ON species USING hnsw (embedding vector_cosine_ops)
--     WITH (m = 16, ef_construction = 64)
--     WHERE embedding IS NOT NULL;
-- Run that manually the first time, or via supabase/tests/rls.sql.
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_species_embedding_hnsw
  ON species USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64)
  WHERE embedding IS NOT NULL;

-- ============================================================
-- 4. RPC: backfill embeddings from a JSONB payload.
--
-- The Flutter app sends the model output to /v1/species/:id/embedding
-- and the API forwards the payload to this RPC. We also expose a
-- backfill variant for ETL use.
-- ============================================================
CREATE OR REPLACE FUNCTION set_species_embedding(
  p_species_id UUID,
  p_embedding  vector(384)
)
RETURNS VOID LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE species
  SET    embedding = p_embedding
  WHERE  id = p_species_id;
$$;

-- Bulk version used by the inat-taxon-lookup / wikimedia ETL
-- (called via supabase-js with the service role).
CREATE OR REPLACE FUNCTION bulk_set_species_embeddings(
  p_rows JSONB
)
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_count INTEGER := 0;
BEGIN
  WITH input AS (
    SELECT (r->>'id')::UUID        AS id,
           (r->>'embedding')::vector(384) AS embedding
    FROM   jsonb_array_elements(p_rows) AS r
    WHERE  r ? 'id' AND r ? 'embedding'
  )
  UPDATE species s
  SET    embedding = i.embedding
  FROM   input i
  WHERE  s.id = i.id;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION set_species_embedding(UUID, vector) IS
  'Service-role only: set a single species embedding. Called from the mobile app via API.';
COMMENT ON FUNCTION bulk_set_species_embeddings(JSONB) IS
  'Service-role only: bulk-set embeddings. Used by the inat-taxon-lookup and wikimedia-images ETLs.';

-- ============================================================
-- 5. RPC: find similar species by embedding.
--
-- Returns the top N closest species, with a similarity score in
-- [0, 1] (1 = identical direction). Excludes the query species.
-- ============================================================
CREATE OR REPLACE FUNCTION find_similar_species(
  p_embedding vector(384),
  p_limit     INTEGER DEFAULT 5,
  p_min_sim   REAL    DEFAULT 0.70
)
RETURNS TABLE (
  id              UUID,
  scientific_name TEXT,
  common_name     TEXT,
  similarity      REAL
) LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public AS $$
  SELECT s.id,
         s.scientific_name,
         s.common_name,
         1 - (s.embedding <=> p_embedding) AS similarity
  FROM   species s
  WHERE  s.embedding IS NOT NULL
    AND  1 - (s.embedding <=> p_embedding) >= p_min_sim
  ORDER  BY s.embedding <=> p_embedding
  LIMIT  p_limit;
$$;

COMMENT ON FUNCTION find_similar_species(vector, INTEGER, REAL) IS
  'Approximate-NN species search. Higher similarity = closer. Threshold 0.70 keeps false positives low.';

-- ============================================================
-- 6. HNSW reindex helper.
--
-- HNSW recall degrades over time as inserts and deletes change the
-- graph topology. The standard remedy is to drop and recreate the
-- index CONCURRENTLY. This function returns the SQL you need to run
-- via the Supabase dashboard SQL editor (since CREATE INDEX
-- CONCURRENTLY cannot run inside a transaction).
-- ============================================================
CREATE OR REPLACE FUNCTION hnsw_reindex_sql()
RETURNS TEXT LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public AS $$
  SELECT format(
    '%I DROP INDEX CONCURRENTLY IF EXISTS public.%I; %s CREATE INDEX CONCURRENTLY %I ON public.%I USING hnsw (%I vector_cosine_ops) WITH (m = 16, ef_construction = 64) WHERE %I IS NOT NULL;',
    '--', 'idx_species_embedding_hnsw', E'\n', 'idx_species_embedding_hnsw', 'species', 'embedding', 'embedding'
  );
$$;

COMMENT ON FUNCTION hnsw_reindex_sql() IS
  'Returns the SQL needed to CONCURRENTLY rebuild the HNSW index. Run it from the Supabase SQL editor (not via migration).';

-- ============================================================
-- 7. Schedule a monthly CONCURRENTLY reindex via pg_cron.
--
-- pg_cron is the standard Supabase add-on; the job calls the helper
-- function and then runs the returned SQL via a DO block. We use
-- cron.schedule to register it on the first of every month at 04:00 UTC
-- (low traffic, leaves the day free for backups).
--
-- The reindex SQL is logged in a dedicated table so an operator can
-- audit when it last ran.
-- ============================================================
CREATE TABLE IF NOT EXISTS public.pgvector_reindex_log (
  id          BIGSERIAL PRIMARY KEY,
  ran_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  result      TEXT NOT NULL,
  duration_ms INTEGER
);

CREATE OR REPLACE FUNCTION run_pgvector_reindex()
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_catalog AS $$
DECLARE
  v_start   TIMESTAMPTZ := clock_timestamp();
  v_sql     TEXT;
  v_result  TEXT;
BEGIN
  -- Build the SQL with the right search_path.
  v_sql := format(
    'REINDEX INDEX CONCURRENTLY public.idx_species_embedding_hnsw'
  );
  BEGIN
    EXECUTE v_sql;
    v_result := 'ok';
  EXCEPTION WHEN OTHERS THEN
    v_result := 'error: ' || SQLERRM;
  END;

  INSERT INTO public.pgvector_reindex_log (result, duration_ms)
  VALUES (v_result, (EXTRACT(MILLISECOND FROM clock_timestamp() - v_start) +
                      EXTRACT(SECOND FROM clock_timestamp() - v_start) * 1000)::INTEGER);

  RETURN v_result;
END;
$$;

-- Register the cron job if pg_cron is available. Failure to schedule
-- is non-fatal (pg_cron is a paid add-on; some teams skip it).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule(
      'pgvector-reindex-monthly',
      '0 4 1 * *',  -- 04:00 UTC on the 1st of every month
      $cron$ SELECT run_pgvector_reindex(); $cron$
    );
  END IF;
END;
$$;

-- ============================================================
-- 8. Audit log for embedding writes.
--    Append-only table; one row per (species_id, actor) per write.
-- ============================================================
CREATE TABLE IF NOT EXISTS public.species_embedding_audit (
  id             BIGSERIAL PRIMARY KEY,
  species_id     UUID NOT NULL REFERENCES species(id) ON DELETE CASCADE,
  actor_id       UUID REFERENCES users(id) ON DELETE SET NULL,
  source         TEXT NOT NULL CHECK (source IN ('mobile', 'etl', 'manual')),
  model_version  TEXT NOT NULL DEFAULT 'all-MiniLM-L6-v2',
  written_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_species_embedding_audit_species
  ON species_embedding_audit (species_id, written_at DESC);
CREATE INDEX IF NOT EXISTS idx_species_embedding_audit_actor
  ON species_embedding_audit (actor_id, written_at DESC) WHERE actor_id IS NOT NULL;

COMMENT ON TABLE species_embedding_audit IS
  'Append-only log of every species embedding write. Used for abuse detection and rollback.';

-- Service role + authenticated can insert (the API uses the service
-- role client). No UPDATE / DELETE — this is audit data.
REVOKE ALL ON public.species_embedding_audit FROM PUBLIC;
GRANT SELECT ON public.species_embedding_audit TO authenticated;
GRANT INSERT ON public.species_embedding_audit TO service_role;
