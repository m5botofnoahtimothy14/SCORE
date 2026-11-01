-- SCORE+ Google Workspace / Google Meet tenant integration.
-- This migration is intentionally additive. It does not alter existing booking quotas,
-- authentication, or school-role functions.

ALTER TABLE public.session_bookings
  ADD COLUMN IF NOT EXISTS google_meet_space_name text,
  ADD COLUMN IF NOT EXISTS google_meet_host_email text,
  ADD COLUMN IF NOT EXISTS google_meet_creation_started_at timestamptz;

CREATE TABLE IF NOT EXISTS public.google_meet_config (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL UNIQUE REFERENCES public.schools(id) ON DELETE CASCADE,
  calendar_id text NOT NULL DEFAULT 'primary',
  time_zone text NOT NULL DEFAULT 'Asia/Kolkata',
  organizer_email text,
  refresh_token_secret_id uuid,
  is_enabled boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.google_meet_config
  ADD COLUMN IF NOT EXISTS organizer_email text,
  ADD COLUMN IF NOT EXISTS refresh_token_secret_id uuid,
  ADD COLUMN IF NOT EXISTS is_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS calendar_id text NOT NULL DEFAULT 'primary',
  ADD COLUMN IF NOT EXISTS time_zone text NOT NULL DEFAULT 'Asia/Kolkata',
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_session_bookings_google_meet_space
  ON public.session_bookings(google_meet_space_name)
  WHERE google_meet_space_name IS NOT NULL;

ALTER TABLE public.google_meet_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS google_meet_config_select ON public.google_meet_config;
DROP POLICY IF EXISTS google_meet_config_admin ON public.google_meet_config;
DROP POLICY IF EXISTS google_meet_config_school_admin ON public.google_meet_config;

CREATE POLICY google_meet_config_school_admin
  ON public.google_meet_config
  FOR ALL
  TO authenticated
  USING (public.tc_is_school_admin(school_id))
  WITH CHECK (public.tc_is_school_admin(school_id));

REVOKE ALL ON public.google_meet_config FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.google_meet_config TO authenticated;
GRANT ALL ON public.google_meet_config TO service_role;

-- The browser/mobile client can read a meeting link only when it is a booked participant.
CREATE OR REPLACE FUNCTION public.get_google_meet_link(p_booking_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_booking public.session_bookings%ROWTYPE;
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO v_booking
  FROM public.session_bookings
  WHERE id = p_booking_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'booking_not_found');
  END IF;

  IF v_uid IS DISTINCT FROM v_booking.student_id
     AND v_uid IS DISTINCT FROM v_booking.mentor_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_a_participant');
  END IF;

  IF v_booking.status::text NOT IN ('confirmed', 'in_progress') THEN
    RETURN jsonb_build_object('success', false, 'error', 'booking_not_confirmed');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'meet_link', v_booking.google_meet_link,
    'calendar_event_id', v_booking.google_calendar_event_id,
    'status', v_booking.status::text
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_google_meet_link(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_google_meet_link(uuid) TO authenticated;

-- Only the server-side Edge Function may read a decrypted Workspace refresh token.
CREATE OR REPLACE FUNCTION public.claim_google_meet_creation(
  p_booking_id uuid,
  p_actor_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault, pg_temp
AS $$
DECLARE
  v_booking public.session_bookings%ROWTYPE;
  v_teacher public.teachers%ROWTYPE;
  v_config public.google_meet_config%ROWTYPE;
  v_refresh_token text;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'service_role_required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_booking
  FROM public.session_bookings
  WHERE id = p_booking_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'booking_not_found');
  END IF;

  IF p_actor_id IS NULL OR
     (p_actor_id IS DISTINCT FROM v_booking.student_id AND
      p_actor_id IS DISTINCT FROM v_booking.mentor_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_a_participant');
  END IF;

  IF v_booking.status::text <> 'confirmed' THEN
    RETURN jsonb_build_object('success', false, 'error', 'booking_not_confirmed');
  END IF;

  IF v_booking.duration_minutes NOT IN (15, 30) OR v_booking.scheduled_at IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_session_schedule');
  END IF;

  SELECT * INTO v_teacher
  FROM public.teachers
  WHERE id = v_booking.mentor_record_id
    AND user_id = v_booking.mentor_id
    AND school_id = v_booking.school_id
    AND is_active = true;

  IF NOT FOUND OR NULLIF(trim(v_teacher.email), '') IS NULL
     OR NULLIF(trim(v_teacher.staff_id_no), '') IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'assigned_teacher_workspace_identity_missing');
  END IF;

  IF v_booking.google_meet_link IS NOT NULL
     AND v_booking.google_meet_space_name IS NOT NULL
     AND v_booking.google_calendar_event_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_created', true,
      'meet_link', v_booking.google_meet_link,
      'space_name', v_booking.google_meet_space_name,
      'calendar_event_id', v_booking.google_calendar_event_id
    );
  END IF;

  IF v_booking.google_meet_creation_started_at IS NOT NULL
     AND v_booking.google_meet_creation_started_at > now() - interval '4 minutes' THEN
    RETURN jsonb_build_object('success', false, 'error', 'creation_in_progress');
  END IF;

  SELECT * INTO v_config
  FROM public.google_meet_config
  WHERE school_id = v_booking.school_id
    AND is_enabled = true;

  IF NOT FOUND OR v_config.refresh_token_secret_id IS NULL
     OR NULLIF(trim(v_config.organizer_email), '') IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'google_workspace_not_connected');
  END IF;

  SELECT decrypted_secret INTO v_refresh_token
  FROM vault.decrypted_secrets
  WHERE id = v_config.refresh_token_secret_id;

  IF NULLIF(v_refresh_token, '') IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'google_workspace_credentials_unavailable');
  END IF;

  UPDATE public.session_bookings
  SET google_meet_creation_started_at = now(),
      updated_at = now()
  WHERE id = p_booking_id;

  RETURN jsonb_build_object(
    'success', true,
    'already_created', false,
    'booking_id', v_booking.id,
    'school_id', v_booking.school_id,
    'student_user_id', v_booking.student_id,
    'mentor_user_id', v_booking.mentor_id,
    'mentor_record_id', v_booking.mentor_record_id,
    'teacher_staff_id_no', v_teacher.staff_id_no,
    'teacher_email', lower(trim(v_teacher.email)),
    'organizer_email', lower(trim(v_config.organizer_email)),
    'calendar_id', v_config.calendar_id,
    'time_zone', v_config.time_zone,
    'refresh_token', v_refresh_token,
    'scheduled_at', v_booking.scheduled_at,
    'duration_minutes', v_booking.duration_minutes,
    'topic', v_booking.topic,
    'subject_id', v_booking.subject_id,
    'space_name', v_booking.google_meet_space_name,
    'meet_link', v_booking.google_meet_link,
    'calendar_event_id', v_booking.google_calendar_event_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.claim_google_meet_creation(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_google_meet_creation(uuid, uuid) TO service_role;

-- Called only by the OAuth callback after it verifies the signed state and Google identity.
-- Refresh tokens are stored in Supabase Vault, never in a public application table.
CREATE OR REPLACE FUNCTION public.store_google_meet_credentials(
  p_school_id uuid,
  p_actor_id uuid,
  p_organizer_email text,
  p_refresh_token text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault, pg_temp
AS $$
DECLARE
  v_secret_id uuid;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'service_role_required' USING ERRCODE = '42501';
  END IF;

  IF p_school_id IS NULL OR p_actor_id IS NULL
     OR NULLIF(trim(p_organizer_email), '') IS NULL
     OR NULLIF(trim(p_refresh_token), '') IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_workspace_credentials');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.school_memberships sm
    WHERE sm.school_id = p_school_id
      AND sm.user_id = p_actor_id
      AND sm.is_active = true
      AND sm.role::text IN ('school_admin', 'principal', 'platform_owner')
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'school_admin_access_required');
  END IF;

  SELECT refresh_token_secret_id INTO v_secret_id
  FROM public.google_meet_config
  WHERE school_id = p_school_id
  FOR UPDATE;

  IF v_secret_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM vault.decrypted_secrets WHERE id = v_secret_id
  ) THEN
    PERFORM vault.update_secret(
      v_secret_id,
      p_refresh_token,
      'scoreplus-google-workspace-' || p_school_id::text,
      'Google Workspace refresh token for SCORE+ school ' || p_school_id::text
    );
  ELSE
    v_secret_id := vault.create_secret(
      p_refresh_token,
      'scoreplus-google-workspace-' || p_school_id::text,
      'Google Workspace refresh token for SCORE+ school ' || p_school_id::text
    );
  END IF;

  INSERT INTO public.google_meet_config (
    school_id, calendar_id, time_zone, organizer_email,
    refresh_token_secret_id, is_enabled, updated_at
  )
  VALUES (
    p_school_id, 'primary', 'Asia/Kolkata', lower(trim(p_organizer_email)),
    v_secret_id, true, now()
  )
  ON CONFLICT (school_id) DO UPDATE
  SET organizer_email = EXCLUDED.organizer_email,
      refresh_token_secret_id = EXCLUDED.refresh_token_secret_id,
      is_enabled = true,
      updated_at = now();

  RETURN jsonb_build_object('success', true, 'organizer_email', lower(trim(p_organizer_email)));
END;
$$;

REVOKE ALL ON FUNCTION public.store_google_meet_credentials(uuid, uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.store_google_meet_credentials(uuid, uuid, text, text) TO service_role;

-- Remove the old placeholder RPC. Meeting creation now runs only in the authenticated Edge Function.
DROP FUNCTION IF EXISTS public.create_google_meet(uuid);
