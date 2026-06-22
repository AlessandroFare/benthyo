-- Migration 053: Fix species_search_tsv_update_stmt() and
-- species_search_tsv_update_after_stmt() search_path.
-- Bug: both statement-level trigger functions ran `UPDATE species ...`
-- (bare table, no schema prefix, no SET search_path). They were defined as
-- SECURITY INVOKER, so they resolved `species` against the *caller's*
-- search_path.
--   GoTrue deletes auth.users as role supabase_auth_admin, whose
--   search_path is `auth` only (no `public`). During the auth.users DELETE
--   cascade, sightings_cascade -> maintain_sighting_aggregates() does an
--   UPDATE on species_dive_site_stats; that UPDATE is itself a statement on a
--   public table, but the surrounding transaction runs with the caller's
--   search_path. When any code path under the auth-role transaction reached
--   the species statement-level triggers, `UPDATE species` resolved to
--   `auth.species`, which does not exist -> SQLSTATE 42P01 -> the whole
--   auth.users DELETE transaction aborted.
-- Impact: identical to migration 052 — auth.admin.deleteUser (and therefore
--   GDPR Art.17 erasure) failed for every user whose deletion cascaded into
--   the sightings/species aggregate path. Live-verified error:
--   `ERROR: relation "species" does not exist (SQLSTATE 42P01)`
--   raised by `public.species_search_tsv_update_after_stmt() line 6` during
--   `DELETE FROM "users"`.
-- Fix: schema-qualify `public.species` in both bodies AND pin
--   SET search_path = public so the trigger resolves the table regardless of
--   caller role. This mirrors the dive_logs_count_update() fix from 052.

CREATE OR REPLACE FUNCTION public.species_search_tsv_update_stmt()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF pg_trigger_depth() > 1 THEN
    RETURN NULL;
  END IF;
  UPDATE public.species
  SET    search_tsv =
           setweight(to_tsvector('simple', coalesce(public.species.scientific_name, '')), 'A') ||
           setweight(to_tsvector('simple', coalesce(public.species.common_name, '')), 'B') ||
           setweight(to_tsvector('simple', coalesce(public.species.common_name_it, '')), 'B') ||
           setweight(to_tsvector('simple', coalesce(public.species.common_name_es, '')), 'B') ||
           setweight(to_tsvector('simple', coalesce(public.species.family, '')), 'C') ||
           setweight(to_tsvector('simple', coalesce(public.species.description, '')), 'D')
  WHERE  public.species.id IN (SELECT id FROM NEW)
    AND  current_setting('app.bulk_load', true) IS DISTINCT FROM 'on';
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.species_search_tsv_update_after_stmt()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF pg_trigger_depth() > 1 THEN
    RETURN NULL;
  END IF;
  UPDATE public.species AS s
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

COMMENT ON FUNCTION public.species_search_tsv_update_stmt() IS
  'Recomputes species.search_tsv for newly inserted species rows. Schema-qualified + SECURITY DEFINER with search_path=public so the statement trigger resolves public.species even when fired inside the auth role transaction during GoTrue user deletion (migration 053).';
COMMENT ON FUNCTION public.species_search_tsv_update_after_stmt() IS
  'Recomputes species.search_tsv for updated species rows. Schema-qualified + SECURITY DEFINER with search_path=public so the statement trigger resolves public.species even when fired inside the auth role transaction during GoTrue user deletion (migration 053).';
