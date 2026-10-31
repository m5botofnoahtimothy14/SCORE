-- ============================================================
-- Migration 00025 — Google Meet calendar-based session scheduling
-- ============================================================
-- Replaces self-hosted LiveKit video with Google Meet calendar events.
-- Every confirmed session gets a Google Calendar event with a Meet link.
-- ============================================================

-- ── Google Meet columns on session_bookings ──
ALTER TABLE public.session_bookings
  ADD COLUMN IF NOT EXISTS google_meet_link TEXT,
  ADD COLUMN IF NOT EXISTS google_calendar_event_id TEXT,
  ADD COLUMN IF NOT EXISTS google_meet_created_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_session_bookings_google_event
  ON public.session_bookings(google_calendar_event_id)
  WHERE google_calendar_event_id IS NOT NULL;

-- ── Per-school Google Calendar integration config ──
CREATE TABLE IF NOT EXISTS public.google_meet_config (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id             UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
  calendar_id           TEXT NOT NULL DEFAULT 'primary',
  time_zone             TEXT NOT NULL DEFAULT 'Asia/Kolkata',
  meet_link_column_note TEXT DEFAULT 'Auto-created Meet link stored in session_bookings.google_meet_link',
  is_enabled            BOOLEAN NOT NULL DEFAULT TRUE,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (school_id)
);

ALTER TABLE public.google_meet_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY google_meet_config_select ON public.google_meet_config FOR SELECT
  USING (school_id = ANY(public.tc_user_school_ids()));

CREATE POLICY google_meet_config_admin ON public.google_meet_config FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ── Realtime publication ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;
END $$;

ALTER PUBLICATION supabase_realtime ADD TABLE IF EXISTS google_meet_config;

-- ── RPC: create_google_meet — creates a Calendar event + Meet link for a booking ──
CREATE OR REPLACE FUNCTION public.create_google_meet(p_booking_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid        UUID := auth.uid();
  v_booking    session_bookings%ROWTYPE;
  v_settings   google_meet_config%ROWTYPE;
  v_meet_link  TEXT;
  v_event_id   TEXT;
  v_calendar   TEXT;
  v_tz         TEXT;
  v_start      TIMESTAMPTZ;
  v_end        TIMESTAMPTZ;
  v_summary    TEXT;
  v_description TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO v_booking FROM public.session_bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'booking_not_found');
  END IF;

  -- Only participants may request the Meet link
  IF v_uid IS DISTINCT FROM v_booking.student_id
     AND v_uid IS DISTINCT FROM v_booking.mentor_id
     AND NOT public.tc_is_school_admin(v_booking.school_id) THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_a_participant');
  END IF;

  IF v_booking.status <> 'confirmed' THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'booking_not_confirmed');
  END IF;

  -- Return existing Meet link if already created (idempotent)
  IF v_booking.google_calendar_event_id IS NOT NULL AND v_booking.google_meet_link IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', TRUE,
      'meet_link', v_booking.google_meet_link,
      'calendar_event_id', v_booking.google_calendar_event_id,
      'created', FALSE
    );
  END IF;

  -- Load Google Meet config for the school
  SELECT * INTO v_settings FROM public.google_meet_config WHERE school_id = v_booking.school_id;
  IF NOT FOUND OR NOT v_settings.is_enabled THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'google_meet_not_configured');
  END IF;

  v_calendar := v_settings.calendar_id;
  v_tz := v_settings.time_zone;
  v_start := COALESCE(v_booking.scheduled_at, v_booking.created_at);
  v_end := v_start + (v_booking.duration_minutes || ' minutes')::INTERVAL;
  v_summary := 'Mentor Desk Session — ' || COALESCE(v_booking.topic, 'Session');
  v_description := 'School: ' || v_booking.school_id::TEXT ||
                   '\nSubject: ' || v_booking.subject_id::TEXT ||
                   '\nDuration: ' || v_booking.duration_minutes || ' minutes' ||
                   '\nBooking ID: ' || p_booking_id::TEXT;

  -- NOTE: The actual Google Calendar API call happens in the edge function
  -- `create_google_meet` (Supabase Edge Function) which this RPC delegates to
  -- via HTTP. Here we persist the placeholder and signal the client to call
  -- the edge function. The edge function writes back meet_link/event_id.
  UPDATE public.session_bookings
  SET google_meet_created_at = NOW(), updated_at = NOW()
  WHERE id = p_booking_id;

  INSERT INTO public.audit_events(school_id, actor_id, action, target_type, target_id, outcome, metadata)
  VALUES (v_booking.school_id, v_uid, 'session.google_meet.requested', 'session_booking',
          p_booking_id::TEXT, 'success', jsonb_build_object('calendar_id', v_calendar));

  RETURN jsonb_build_object(
    'success', TRUE,
    'booking_id', p_booking_id,
    'meet_link', v_booking.google_meet_link,
    'calendar_event_id', v_booking.google_calendar_event_id,
    'created', FALSE,
    'requires_edge_call', TRUE
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_google_meet(UUID) TO authenticated;

-- ── RPC: get_google_meet_link — read-only access to the Meet link for a booking ──
CREATE OR REPLACE FUNCTION public.get_google_meet_link(p_booking_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid   UUID := auth.uid();
  v_booking session_bookings%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO v_booking FROM public.session_bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'booking_not_found');
  END IF;

  IF v_uid IS DISTINCT FROM v_booking.student_id
     AND v_uid IS DISTINCT FROM v_booking.mentor_id
     AND NOT public.tc_is_school_admin(v_booking.school_id) THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_a_participant');
  END IF;

  RETURN jsonb_build_object(
    'success', TRUE,
    'meet_link', v_booking.google_meet_link,
    'calendar_event_id', v_booking.google_calendar_event_id,
    'status', v_booking.status
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_google_meet_link(UUID) TO authenticated;
