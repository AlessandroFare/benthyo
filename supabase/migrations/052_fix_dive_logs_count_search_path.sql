-- Migration 052: Fix dive_logs_count_update() search_path.
-- Bug: function body referenced unqualified `users`, relying on the caller's
-- search_path. GoTrue deletes auth.users as role supabase_auth_admin, whose
-- search_path resolves `users` to `auth.users` — which has no total_dives
-- column — so the AFTER DELETE trigger raised "column total_dives does not
-- exist" and aborted the whole auth.users DELETE transaction.
-- Impact: any user with >=1 dive_log could not be deleted via
-- auth.admin.deleteUser / GoTrue admin API. GDPR Art.17 erasure was therefore
-- broken for every active diver.
-- Fix: schema-qualify public.users and pin the function's search_path to
-- public so the trigger resolves the profile table regardless of caller role.

CREATE OR REPLACE FUNCTION public.dive_logs_count_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.users SET total_dives = total_dives + 1 WHERE id = NEW.user_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.users SET total_dives = GREATEST(0, total_dives - 1) WHERE id = OLD.user_id;
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

-- Trigger stays the same; function OID is replaced in place.
COMMENT ON FUNCTION public.dive_logs_count_update() IS
  'Keeps users.total_dives in sync with dive_logs row count. Schema-qualified + SECURITY DEFINER with search_path=public so it resolves public.users even when fired by the auth role during GoTrue user deletion (migration 052).';
