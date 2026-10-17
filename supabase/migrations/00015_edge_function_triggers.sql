-- ============================================================
-- TeachCross: Migration 00015 — Edge Function Triggers (pg_net)
-- ============================================================
-- Wires real database events to the server-side Edge Functions that were
-- previously expected to run via dashboard "Database Webhooks" but were
-- never actually configured. Without these, messages stayed in
-- `pending_moderation` forever (invisible to recipients) and attachments
-- were never scanned.
--
-- The shared secret is read from Supabase Vault (secret name:
-- `internal_webhook_secret`) so no secret is committed to the repo. Set it
-- once with:
--   select vault.create_secret('<random>', 'internal_webhook_secret',
--     'Shared secret for internal edge-function calls');
-- and mirror the same value into the Edge Function env as
-- INTERNAL_WEBHOOK_SECRET.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ------------------------------------------------------------
-- Helper: POST a JSON payload to an internal Edge Function, authenticated
-- with the Vault-stored shared secret. SECURITY DEFINER so trigger callers
-- don't need direct Vault/pg_net privileges.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.tc_post_edge(p_fn TEXT, p_payload JSONB)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_secret TEXT;
  v_url    TEXT := 'https://pdnrloftybrhuwefmrhp.supabase.co/functions/v1/' || p_fn;
BEGIN
  SELECT decrypted_secret INTO v_secret
  FROM vault.decrypted_secrets
  WHERE name = 'internal_webhook_secret'
  LIMIT 1;

  IF v_secret IS NULL THEN
    RAISE WARNING 'tc_post_edge: internal_webhook_secret missing in Vault — skipping %', p_fn;
    RETURN NULL;
  END IF;

  RETURN net.http_post(
    url := v_url,
    body := p_payload,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', v_secret
    ),
    timeout_milliseconds := 5000
  );
END;
$$;

-- ------------------------------------------------------------
-- Messages: moderate on insert (only while pending)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.tc_trigger_moderate_message()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  PERFORM public.tc_post_edge('moderate-message', jsonb_build_object(
    'message_id', NEW.id,
    'school_id', NEW.school_id
  ));
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS messages_moderate_insert ON public.messages;
CREATE TRIGGER messages_moderate_insert
  AFTER INSERT ON public.messages
  FOR EACH ROW
  WHEN (NEW.status = 'pending_moderation')
  EXECUTE FUNCTION public.tc_trigger_moderate_message();

-- ------------------------------------------------------------
-- Attachments: scan on insert (only while pending)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.tc_trigger_moderate_attachment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  PERFORM public.tc_post_edge('moderate-image', jsonb_build_object(
    'attachment_id', NEW.id,
    'school_id', NEW.school_id
  ));
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS attachments_scan_insert ON public.attachments;
CREATE TRIGGER attachments_scan_insert
  AFTER INSERT ON public.attachments
  FOR EACH ROW
  WHEN (NEW.status = 'pending_scan')
  EXECUTE FUNCTION public.tc_trigger_moderate_attachment();
