-- ============================================================
-- TeachCross: Migration 00016 — Notification dispatch cron
-- ============================================================
-- `notification_jobs` rows only get sent when something calls the
-- `dispatch-notifications` Edge Function. Jobs inserted without an inline
-- invoke (e.g. by other services) would linger forever. This schedules a
-- periodic sweep via pg_cron that reuses the Vault-authenticated helper.
--
-- Requires the extension to be enabled by the platform (Supabase supports
-- pg_cron out of the box). If enabling fails, the migration is a no-op and
-- the function must be dispatched manually / by callers.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_cron;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'pg_cron unavailable (%); skipping notification sweep schedule', SQLERRM;
END $$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    -- Idempotent: scheduling the same job name replaces its definition.
    PERFORM cron.schedule(
      'dispatch-notifications-sweep',
      '*/5 * * * *',
      $cron$ SELECT public.tc_post_edge('dispatch-notifications', '{}'::jsonb); $cron$
    );
  END IF;
END $$;
