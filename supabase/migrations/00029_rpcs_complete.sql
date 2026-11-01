-- ============================================================
-- Migration 00029: preserve the live RPC implementations.
--
-- The previous file replaced secure production RPCs with older versions.
-- In particular, its send_message and activation implementations did not
-- enforce the current security contract. Do not overwrite those functions.
-- Mentor Desk RPCs that are missing from the live project are restored in
-- migration 00035 with explicit auth.uid() checks and scoped permissions.
-- ============================================================
DO $$
BEGIN
  IF to_regprocedure('public.send_message(uuid,uuid,text,text,uuid,uuid)') IS NULL THEN
    RAISE EXCEPTION 'The existing secure send_message RPC is missing';
  END IF;
  IF to_regprocedure('public.tc_is_school_admin(uuid)') IS NULL THEN
    RAISE EXCEPTION 'The existing school-admin security helper is missing';
  END IF;
END;
$$;
