-- ============================================================
-- 00020 — Device registration RPCs
--
-- The mobile app registers its FCM token from the client. When the token
-- is already on file it belongs to the PREVIOUS account on that handset
-- (a re-enrolment, a factory reset, a handed-down phone), so the upsert
-- turns into an UPDATE of somebody else's row — which row-level security
-- rightly refuses.
--
-- These SECURITY DEFINER functions own the write instead: the server
-- decides that the caller is taking over the device, and the row is
-- re-pointed at the signed-in user. The client can only ever register a
-- device for itself (auth.uid()), never for anybody else.
-- ============================================================

-- Registers (or takes over) this device's push token.
CREATE OR REPLACE FUNCTION public.register_notification_device(
  p_school_id      UUID,
  p_fcm_token      TEXT,
  p_platform       TEXT DEFAULT 'android',
  p_app_version    TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF p_fcm_token IS NULL OR length(p_fcm_token) < 8 THEN
    RAISE EXCEPTION 'invalid_token';
  END IF;

  INSERT INTO notification_devices (
    user_id, school_id, fcm_token, platform, app_version, is_active, last_seen_at
  )
  VALUES (
    auth.uid(), p_school_id, p_fcm_token, COALESCE(p_platform, 'android'),
    p_app_version, TRUE, NOW()
  )
  ON CONFLICT (fcm_token) DO UPDATE
    SET user_id      = EXCLUDED.user_id,
        school_id    = EXCLUDED.school_id,
        platform     = EXCLUDED.platform,
        app_version  = EXCLUDED.app_version,
        is_active    = TRUE,
        last_seen_at = NOW()
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.register_notification_device(UUID, TEXT, TEXT, TEXT)
  TO authenticated;

-- Retires this device's push token on sign-out. Only the row that belongs
-- to the caller is touched.
CREATE OR REPLACE FUNCTION public.deactivate_notification_device(p_fcm_token TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  UPDATE notification_devices
  SET is_active = FALSE
  WHERE fcm_token = p_fcm_token
    AND user_id = auth.uid();

  RETURN FOUND;
END;
$$;

GRANT EXECUTE ON FUNCTION public.deactivate_notification_device(TEXT)
  TO authenticated;
