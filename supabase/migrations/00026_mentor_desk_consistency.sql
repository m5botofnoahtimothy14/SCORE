-- ============================================================
-- Migration 00026 — Mentor Desk consistency fixes + production hardening
-- ============================================================
-- Fix status transitions broken by migration 00024 (resolve -> 'answered'
-- but submit_rating/submit_mentor_assessment only accepted 'resolved'/'closed').
-- Add Google Meet config defaults for demo schools.
-- ============================================================

-- ── Fix submit_rating to accept 'answered' (resolve now sets 'answered') ──
CREATE OR REPLACE FUNCTION public.submit_rating(
  p_request_id UUID,
  p_rating     INTEGER,
  p_comment    TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid  UUID := auth.uid();
  v_req  doubt_requests%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authenticated');
  END IF;

  IF p_rating < 1 OR p_rating > 5 THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_rating');
  END IF;

  SELECT * INTO v_req FROM doubt_requests WHERE id = p_request_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'request_not_found');
  END IF;

  IF v_req.student_id IS DISTINCT FROM v_uid THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_the_student');
  END IF;

  -- Accept answered/resolved/reopened-closed states
  IF v_req.status <> 'answered' AND v_req.status <> 'resolved' AND v_req.status <> 'closed' THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'request_not_closed');
  END IF;

  INSERT INTO ratings(school_id, request_id, student_id, mentor_id, rating, comment)
  VALUES (v_req.school_id, p_request_id, v_uid, v_req.assigned_mentor_id, p_rating, p_comment)
  ON CONFLICT (request_id, student_id) DO UPDATE
    SET rating = EXCLUDED.rating,
        comment = EXCLUDED.comment,
        created_at = NOW();

  UPDATE doubt_requests
  SET status = 'closed', closed_at = NOW(), updated_at = NOW()
  WHERE id = p_request_id AND status IN ('answered', 'resolved');

  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome)
  VALUES (v_req.school_id, v_uid, 'rating.submit', 'rating', p_request_id::TEXT, 'success');

  RETURN jsonb_build_object('success', TRUE, 'request_id', p_request_id, 'rating', p_rating);
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_rating(UUID, INTEGER, TEXT) TO authenticated;

-- ── Fix submit_mentor_assessment to accept 'answered' ──
CREATE OR REPLACE FUNCTION public.submit_mentor_assessment(
  p_request_id   UUID,
  p_preparation  engagement_scale,
  p_engagement   engagement_scale,
  p_private_note TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid  UUID := auth.uid();
  v_req  doubt_requests%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO v_req FROM doubt_requests WHERE id = p_request_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'request_not_found');
  END IF;

  IF v_uid IS DISTINCT FROM v_req.assigned_mentor_id THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_assigned_mentor');
  END IF;

  IF v_req.status <> 'answered' AND v_req.status <> 'resolved' AND v_req.status <> 'closed' THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'request_not_closed');
  END IF;

  INSERT INTO mentor_assessments(
    school_id, request_id, mentor_id, student_id,
    preparation, engagement, private_note, created_at, updated_at
  )
  VALUES (v_req.school_id, p_request_id, v_uid, v_req.student_id,
          p_preparation, p_engagement, p_private_note, NOW(), NOW())
  ON CONFLICT (request_id, mentor_id) DO UPDATE
    SET preparation = EXCLUDED.preparation,
        engagement = EXCLUDED.engagement,
        private_note = EXCLUDED.private_note,
        updated_at = NOW();

  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome)
  VALUES (v_req.school_id, v_uid, 'mentor.assessment', 'mentor_assessment', p_request_id::TEXT, 'success');

  RETURN jsonb_build_object('success', TRUE, 'request_id', p_request_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_mentor_assessment(UUID, engagement_scale, engagement_scale, TEXT) TO authenticated;

-- ── Ensure Google Meet config exists for schools with mentor_desk_settings ──
INSERT INTO public.google_meet_config(school_id, calendar_id, time_zone, is_enabled)
SELECT mds.school_id, 'primary', COALESCE(ss.timezone, 'Asia/Kolkata'), TRUE
FROM public.mentor_desk_settings mds
LEFT JOIN public.school_settings ss ON ss.school_id = mds.school_id
ON CONFLICT (school_id) DO NOTHING;

-- ── Indexes for query performance ──
CREATE INDEX IF NOT EXISTS idx_doubt_requests_status_assigned
  ON public.doubt_requests(assigned_mentor_id, status) WHERE assigned_mentor_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_session_bookings_google_meet
  ON public.session_bookings(google_calendar_event_id) WHERE google_calendar_event_id IS NOT NULL;
