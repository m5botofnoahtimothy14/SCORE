-- ============================================================
-- Migration 00022: Self-hosted video + recording consent + hardening
-- ============================================================

-- Video room linked to a booking (internal, non-sensitive room name)
CREATE TABLE IF NOT EXISTS public.video_rooms (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id     UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
  booking_id    UUID NOT NULL REFERENCES public.session_bookings(id) ON DELETE CASCADE,
  room_name     TEXT NOT NULL UNIQUE,
  provider      TEXT NOT NULL DEFAULT 'self_hosted_livekit',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (booking_id)
);

ALTER TABLE public.session_bookings
  ADD COLUMN IF NOT EXISTS video_room_name TEXT,
  ADD COLUMN IF NOT EXISTS recording_status TEXT NOT NULL DEFAULT 'disabled';

-- Participant connection events (attendance evidence, separate from verification)
CREATE TABLE IF NOT EXISTS public.video_participant_events (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id     UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
  booking_id    UUID NOT NULL REFERENCES public.session_bookings(id) ON DELETE CASCADE,
  user_id       UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  role          TEXT NOT NULL,
  event_type    TEXT NOT NULL CHECK (event_type IN ('join','leave','reconnect','disconnect')),
  connected_at  TIMESTAMPTZ,
  disconnected_at TIMESTAMPTZ,
  duration_seconds INTEGER,
  metadata      JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_video_events_booking ON public.video_participant_events(booking_id, created_at);

-- Recording consent decisions (one per required participant per booking)
CREATE TABLE IF NOT EXISTS public.recording_consents (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id     UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
  booking_id    UUID NOT NULL REFERENCES public.session_bookings(id) ON DELETE CASCADE,
  user_id       UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  role          TEXT NOT NULL,
  consented     BOOLEAN NOT NULL,
  guardian_consent BOOLEAN NOT NULL DEFAULT FALSE,
  decided_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (booking_id, user_id)
);

-- Recording metadata (private storage; no public URLs)
CREATE TABLE IF NOT EXISTS public.session_recordings (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id     UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
  booking_id    UUID NOT NULL REFERENCES public.session_bookings(id) ON DELETE CASCADE,
  storage_path  TEXT NOT NULL,
  status        TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','recording','completed','failed','deleted')),
  started_at    TIMESTAMPTZ,
  ended_at      TIMESTAMPTZ,
  duration_seconds INTEGER,
  size_bytes    BIGINT,
  expires_at    TIMESTAMPTZ,
  deleted_at    TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_session_recordings_booking ON public.session_recordings(booking_id);

-- RLS
ALTER TABLE public.video_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.video_participant_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recording_consents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.session_recordings ENABLE ROW LEVEL SECURITY;

-- video_rooms: participants + admin
CREATE POLICY video_rooms_participant ON public.video_rooms FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.session_bookings b
      WHERE b.id = video_rooms.booking_id
        AND (b.student_id = auth.uid() OR b.mentor_id = auth.uid())
    )
  );
CREATE POLICY video_rooms_admin ON public.video_rooms FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.session_bookings b
      WHERE b.id = video_rooms.booking_id
        AND public.tc_is_school_admin(b.school_id)
    )
  );

-- video_participant_events: participants insert own; participants/admin read
CREATE POLICY video_events_insert ON public.video_participant_events FOR INSERT
  WITH CHECK (user_id = auth.uid());
CREATE POLICY video_events_select ON public.video_participant_events FOR SELECT
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.session_bookings b
      WHERE b.id = video_participant_events.booking_id
        AND (b.student_id = auth.uid() OR b.mentor_id = auth.uid())
    )
    OR EXISTS (
      SELECT 1 FROM public.session_bookings b
      WHERE b.id = video_participant_events.booking_id
        AND public.tc_is_school_admin(b.school_id)
    )
  );

-- recording_consents: participants manage own; admin read
CREATE POLICY recording_consents_own ON public.recording_consents FOR ALL
  USING (user_id = auth.uid());
CREATE POLICY recording_consents_admin ON public.recording_consents FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.session_bookings b
      WHERE b.id = recording_consents.booking_id
        AND public.tc_is_school_admin(b.school_id)
    )
  );

-- session_recordings: participants read metadata; admin manage
CREATE POLICY session_recordings_participant ON public.session_recordings FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.session_bookings b
      WHERE b.id = session_recordings.booking_id
        AND (b.student_id = auth.uid() OR b.mentor_id = auth.uid())
    )
  );
CREATE POLICY session_recordings_admin ON public.session_recordings FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.session_bookings b
      WHERE b.id = session_recordings.booking_id
        AND public.tc_is_school_admin(b.school_id)
    )
  );

-- RPC: provision a video room for a confirmed booking (idempotent)
CREATE OR REPLACE FUNCTION public.provision_video_room(p_booking_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_booking session_bookings%ROWTYPE;
  v_room TEXT;
  v_existing TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO v_booking FROM session_bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'booking_not_found');
  END IF;

  -- Only participants may provision
  IF v_uid IS DISTINCT FROM v_booking.student_id
     AND v_uid IS DISTINCT FROM v_booking.mentor_id THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_a_participant');
  END IF;

  IF v_booking.status NOT IN ('confirmed','completed') THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'booking_not_confirmed');
  END IF;

  SELECT room_name INTO v_existing FROM video_rooms WHERE booking_id = p_booking_id;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('success', TRUE, 'room_name', v_existing, 'created', FALSE);
  END IF;

  -- Internal, non-sensitive room name derived from booking id
  v_room := 'md-' || replace(p_booking_id::TEXT, '-', '');

  INSERT INTO video_rooms(school_id, booking_id, room_name)
  VALUES (v_booking.school_id, p_booking_id, v_room)
  ON CONFLICT (booking_id) DO NOTHING;

  SELECT room_name INTO v_existing FROM video_rooms WHERE booking_id = p_booking_id;

  UPDATE session_bookings SET video_room_name = v_existing, updated_at = NOW()
  WHERE id = p_booking_id;

  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome)
  VALUES (v_booking.school_id, v_uid, 'video.room_provision', 'session_booking', p_booking_id::TEXT, 'success');

  RETURN jsonb_build_object('success', TRUE, 'room_name', v_existing, 'created', TRUE);
END;
$$;

GRANT EXECUTE ON FUNCTION public.provision_video_room(UUID) TO authenticated;

-- RPC: record a video participant event
CREATE OR REPLACE FUNCTION public.record_video_event(
  p_booking_id UUID,
  p_event_type TEXT,
  p_duration_seconds INTEGER DEFAULT NULL,
  p_metadata JSONB DEFAULT '{}'::JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_booking session_bookings%ROWTYPE;
  v_role TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO v_booking FROM session_bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'booking_not_found');
  END IF;

  IF v_uid = v_booking.student_id THEN v_role := 'student';
  ELSIF v_uid = v_booking.mentor_id THEN v_role := 'mentor';
  ELSE
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_a_participant');
  END IF;

  INSERT INTO video_participant_events(
    school_id, booking_id, user_id, role, event_type, duration_seconds, metadata
  )
  VALUES (
    v_booking.school_id, p_booking_id, v_uid, v_role, p_event_type, p_duration_seconds, p_metadata
  );

  RETURN jsonb_build_object('success', TRUE);
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_video_event(UUID, TEXT, INTEGER, JSONB) TO authenticated;

-- RPC: record consent decision
CREATE OR REPLACE FUNCTION public.record_recording_consent(
  p_booking_id UUID,
  p_consented BOOLEAN,
  p_guardian_consent BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_booking session_bookings%ROWTYPE;
  v_role TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO v_booking FROM session_bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'booking_not_found');
  END IF;

  IF v_uid = v_booking.student_id THEN v_role := 'student';
  ELSIF v_uid = v_booking.mentor_id THEN v_role := 'mentor';
  ELSE
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_a_participant');
  END IF;

  INSERT INTO recording_consents(school_id, booking_id, user_id, role, consented, guardian_consent)
  VALUES (v_booking.school_id, p_booking_id, v_uid, v_role, p_consented, p_guardian_consent)
  ON CONFLICT (booking_id, user_id) DO UPDATE
  SET consented = EXCLUDED.consented,
      guardian_consent = EXCLUDED.guardian_consent,
      decided_at = NOW();

  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome, metadata)
  VALUES (v_booking.school_id, v_uid, 'video.consent', 'session_booking', p_booking_id::TEXT, 'success',
          jsonb_build_object('consented', p_consented));

  RETURN jsonb_build_object('success', TRUE, 'consented', p_consented);
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_recording_consent(UUID, BOOLEAN, BOOLEAN) TO authenticated;
