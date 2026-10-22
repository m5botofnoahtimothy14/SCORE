-- ============================================================
-- TeachCross: Migration 00021 — SCORE Mentor Desk
--
-- Adds the Mentor Desk system on top of the existing platform:
-- doubt requests, session bookings, verification codes, ratings,
-- private mentor assessments, weekly allowances, urgent passes,
-- mentor availability, and the SLT oversight scope.
--
-- All mutations go through SECURITY DEFINER RPCs so authorization
-- is enforced server-side. Reads are protected by RLS.
-- ============================================================

-- ── Add a conversation type for Mentor Desk threads ──
ALTER TYPE public.conversation_type ADD VALUE 'mentor_desk';

-- ── Mentor Desk settings (per school, admin-configurable) ──
CREATE TABLE public.mentor_desk_settings (
  id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id                   UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
  open_doubt_limit            INTEGER NOT NULL DEFAULT 3,
  session_allowance_minutes   INTEGER NOT NULL DEFAULT 120,
  urgent_passes_per_week      INTEGER NOT NULL DEFAULT 1,
  escalation_threshold_minutes INTEGER NOT NULL DEFAULT 30,
  week_start_day              INTEGER NOT NULL DEFAULT 1,
  session_lengths             INTEGER[] NOT NULL DEFAULT '{15,30,45}',
  verification_code_digits    INTEGER NOT NULL DEFAULT 6,
  code_visible_minutes_before INTEGER NOT NULL DEFAULT 10,
  max_verification_attempts   INTEGER NOT NULL DEFAULT 5,
  created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (school_id)
);

-- ── Mentor subject approvals (teacher -> subject) ──
CREATE TYPE public.mentor_approval_status AS ENUM ('pending', 'approved', 'rejected');

CREATE TABLE public.mentor_subject_approvals (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id      UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
  teacher_id     UUID NOT NULL REFERENCES public.teachers(id) ON DELETE CASCADE,
  subject_id     UUID NOT NULL REFERENCES public.subjects(id) ON DELETE CASCADE,
  status         mentor_approval_status NOT NULL DEFAULT 'pending',
  approved_by    UUID REFERENCES public.user_profiles(id),
  approved_at    TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (teacher_id, subject_id)
);

-- ── Mentor availability / presence ──
CREATE TYPE public.availability_status AS ENUM ('available', 'away');

CREATE TABLE public.mentor_availability (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id   UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
  teacher_id  UUID NOT NULL REFERENCES public.teachers(id) ON DELETE CASCADE,
  status      availability_status NOT NULL DEFAULT 'away',
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (teacher_id)
);

-- ── Doubt requests ──
CREATE TYPE public.doubt_status AS ENUM ('waiting', 'assigned', 'resolved', 'closed');

CREATE TABLE public.doubt_requests (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id         UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
  conversation_id   UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  student_id        UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  student_record_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  subject_id        UUID NOT NULL REFERENCES public.subjects(id) ON DELETE CASCADE,
  question          TEXT NOT NULL,
  chapter           TEXT,
  question_number   TEXT,
  explanation       TEXT,
  previous_attempts TEXT,
  urgent            BOOLEAN NOT NULL DEFAULT FALSE,
  urgent_reason     TEXT,
  urgent_pass_used  BOOLEAN NOT NULL DEFAULT FALSE,
  status            doubt_status NOT NULL DEFAULT 'waiting',
  assigned_mentor_id UUID REFERENCES public.user_profiles(id),
  assigned_teacher_id UUID REFERENCES public.teachers(id),
  named_mentor      BOOLEAN NOT NULL DEFAULT FALSE,
  first_reply_at    TIMESTAMPTZ,
  resolved_at       TIMESTAMPTZ,
  closed_at         TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_doubt_requests_student ON public.doubt_requests(student_id, status);
CREATE INDEX idx_doubt_requests_subject ON public.doubt_requests(subject_id, status);
CREATE INDEX idx_doubt_requests_status  ON public.doubt_requests(status) WHERE status IN ('waiting', 'assigned');
CREATE INDEX idx_doubt_requests_mentor  ON public.doubt_requests(assigned_mentor_id) WHERE assigned_mentor_id IS NOT NULL;
CREATE INDEX idx_doubt_requests_created ON public.doubt_requests(created_at DESC);

-- ── Session bookings ──
CREATE TYPE public.booking_status AS ENUM (
  'requested',
  'confirmed',
  'cancelled_by_student',
  'cancelled_by_mentor',
  'completed',
  'no_show_student',
  'no_show_mentor',
  'unverified_closed'
);

CREATE TABLE public.session_bookings (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id          UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
  student_id         UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  student_record_id  UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  mentor_id          UUID NOT NULL REFERENCES public.user_profiles(id),
  mentor_record_id   UUID NOT NULL REFERENCES public.teachers(id),
  subject_id         UUID NOT NULL REFERENCES public.subjects(id) ON DELETE CASCADE,
  duration_minutes   INTEGER NOT NULL,
  topic              TEXT NOT NULL,
  preparation        TEXT,
  requested_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  scheduled_at       TIMESTAMPTZ,
  confirmed_at       TIMESTAMPTZ,
  meeting_link       TEXT,
  meeting_room       TEXT,
  status             booking_status NOT NULL DEFAULT 'requested',
  allowance_minutes_used INTEGER NOT NULL DEFAULT 0,
  cancelled_at       TIMESTAMPTZ,
  cancelled_by       UUID REFERENCES public.user_profiles(id),
  refunded           BOOLEAN NOT NULL DEFAULT FALSE,
  verification_code  TEXT,
  code_expires_at    TIMESTAMPTZ,
  code_attempts      INTEGER NOT NULL DEFAULT 0,
  code_locked_at     TIMESTAMPTZ,
  code_visible_at    TIMESTAMPTZ,
  verified_at        TIMESTAMPTZ,
  closed_without_code BOOLEAN NOT NULL DEFAULT FALSE,
  close_reason       TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_session_bookings_student ON public.session_bookings(student_id, status);
CREATE INDEX idx_session_bookings_mentor  ON public.session_bookings(mentor_id, status);
CREATE INDEX idx_session_bookings_scheduled ON public.session_bookings(scheduled_at) WHERE status = 'confirmed';
CREATE INDEX idx_session_bookings_subject ON public.session_bookings(subject_id, status);

-- ── Session no-shows / administrative review records ──
CREATE TYPE public.no_show_type AS ENUM ('student_no_show', 'mentor_no_show');

CREATE TABLE public.session_no_shows (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id      UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
  booking_id     UUID NOT NULL REFERENCES public.session_bookings(id) ON DELETE CASCADE,
  reported_by    UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  reported_by_role TEXT NOT NULL,
  no_show_type   no_show_type NOT NULL,
  refund_minutes INTEGER NOT NULL DEFAULT 0,
  refunded       BOOLEAN NOT NULL DEFAULT FALSE,
  review_status  TEXT NOT NULL DEFAULT 'pending',
  reviewed_by    UUID REFERENCES public.user_profiles(id),
  reviewed_at    TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_session_no_shows_booking ON public.session_no_shows(booking_id);
CREATE INDEX idx_session_no_shows_review  ON public.session_no_shows(review_status) WHERE review_status = 'pending';

-- ── Ratings (student -> mentor; visible to mentor + admins) ──
CREATE TABLE public.ratings (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id   UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
  request_id  UUID NOT NULL REFERENCES public.doubt_requests(id) ON DELETE CASCADE,
  student_id  UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  mentor_id   UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  rating      INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment     TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (request_id, student_id)
);

CREATE INDEX idx_ratings_request ON public.ratings(request_id);
CREATE INDEX idx_ratings_mentor  ON public.ratings(mentor_id);

-- ── Mentor assessments (mentor -> student; PRIVATE, never shown to student) ──
CREATE TYPE public.engagement_scale AS ENUM (
  'unprepared',
  'needs_improvement',
  'satisfactory',
  'good',
  'outstanding'
);

CREATE TABLE public.mentor_assessments (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id     UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
  request_id    UUID NOT NULL REFERENCES public.doubt_requests(id) ON DELETE CASCADE,
  mentor_id     UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  student_id    UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  preparation   engagement_scale NOT NULL,
  engagement    engagement_scale NOT NULL,
  private_note  TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (request_id, mentor_id)
);

CREATE INDEX idx_mentor_assessments_request ON public.mentor_assessments(request_id);
CREATE INDEX idx_mentor_assessments_mentor  ON public.mentor_assessments(mentor_id);

-- ── Allowance transactions (session minutes used / refunded) ──
CREATE TYPE public.allowance_action AS ENUM ('deduct', 'refund');

CREATE TABLE public.allowance_transactions (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id          UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
  student_id         UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  subject_id         UUID NOT NULL REFERENCES public.subjects(id) ON DELETE CASCADE,
  booking_id         UUID REFERENCES public.session_bookings(id) ON DELETE SET NULL,
  week_start         DATE NOT NULL,
  action             allowance_action NOT NULL,
  minutes            INTEGER NOT NULL,
  reason             TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_allowance_student_week ON public.allowance_transactions(student_id, subject_id, week_start);
CREATE INDEX idx_allowance_booking      ON public.allowance_transactions(booking_id);

-- ── Urgent pass consumption (1 per subject per week) ──
CREATE TABLE public.urgent_pass_usage (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id    UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
  student_id   UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  subject_id   UUID NOT NULL REFERENCES public.subjects(id) ON DELETE CASCADE,
  request_id   UUID NOT NULL REFERENCES public.doubt_requests(id) ON DELETE CASCADE,
  week_start   DATE NOT NULL,
  consumed_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (student_id, subject_id, week_start)
);

CREATE INDEX idx_urgent_pass_student_week ON public.urgent_pass_usage(student_id, subject_id, week_start);

-- ── SLT access grants (administrator assigns scope) ──
CREATE TYPE public.slt_scope_type AS ENUM ('program', 'batch', 'campus', 'organisation');

CREATE TABLE public.slt_access_grants (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id     UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
  user_id       UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  granted_by    UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  scope_type    slt_scope_type NOT NULL,
  scope_value   TEXT NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  revoked_at    TIMESTAMPTZ,
  UNIQUE (user_id, scope_type, scope_value)
);

CREATE INDEX idx_slt_access_user ON public.slt_access_grants(user_id) WHERE revoked_at IS NULL;

-- ── Enable RLS on all new tables ──
ALTER TABLE public.mentor_desk_settings           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mentor_subject_approvals       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mentor_availability            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.doubt_requests                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.session_bookings               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.session_no_shows               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ratings                        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mentor_assessments             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.allowance_transactions         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.urgent_pass_usage              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.slt_access_grants              ENABLE ROW LEVEL SECURITY;

-- ── Realtime publication for new tables ──
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;
END $$;

ALTER PUBLICATION supabase_realtime ADD TABLE IF EXISTS doubt_requests;
ALTER PUBLICATION supabase_realtime ADD TABLE IF EXISTS session_bookings;
ALTER PUBLICATION supabase_realtime ADD TABLE IF EXISTS mentor_availability;
ALTER PUBLICATION supabase_realtime ADD TABLE IF EXISTS ratings;
ALTER PUBLICATION supabase_realtime ADD TABLE IF EXISTS notification_jobs;

-- ============================================================
-- RLS POLICIES
-- ============================================================

-- mentor_desk_settings: members read, admins write
CREATE POLICY mentor_desk_settings_select ON public.mentor_desk_settings FOR SELECT
  USING (school_id = ANY(public.tc_user_school_ids()));
CREATE POLICY mentor_desk_settings_admin ON public.mentor_desk_settings FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- mentor_subject_approvals: members read, admins write
CREATE POLICY mentor_approvals_select ON public.mentor_subject_approvals FOR SELECT
  USING (school_id = ANY(public.tc_user_school_ids()));
CREATE POLICY mentor_approvals_admin ON public.mentor_subject_approvals FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- mentor_availability: members read; teacher updates own
CREATE POLICY mentor_availability_select ON public.mentor_availability FOR SELECT
  USING (school_id = ANY(public.tc_user_school_ids()));
CREATE POLICY mentor_availability_own_update ON public.mentor_availability FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.teachers t
      WHERE t.id = mentor_availability.teacher_id
        AND t.user_id = auth.uid()
    )
  );
CREATE POLICY mentor_availability_admin ON public.mentor_availability FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- doubt_requests: student owns; assigned mentor + school admin read
CREATE POLICY doubt_requests_student ON public.doubt_requests FOR ALL
  USING (student_id = auth.uid());
CREATE POLICY doubt_requests_mentor ON public.doubt_requests FOR SELECT
  USING (
    school_id = ANY(public.tc_user_school_ids())
    AND (
      assigned_mentor_id = auth.uid()
      OR EXISTS (
        SELECT 1 FROM public.conversation_members cm
        WHERE cm.conversation_id = doubt_requests.conversation_id
          AND cm.user_id = auth.uid()
          AND cm.removed_at IS NULL
      )
    )
  );
CREATE POLICY doubt_requests_admin ON public.doubt_requests FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.conversations c
      WHERE c.id = doubt_requests.conversation_id
        AND public.tc_is_school_admin(c.school_id)
    )
  );

-- session_bookings: student + mentor + admin
CREATE POLICY session_bookings_participant ON public.session_bookings FOR ALL
  USING (student_id = auth.uid() OR mentor_id = auth.uid());
CREATE POLICY session_bookings_admin ON public.session_bookings FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.session_bookings b
      WHERE b.id = session_bookings.id
        AND public.tc_is_school_admin(b.school_id)
    )
  );

-- session_no_shows: reporter + admin
CREATE POLICY session_no_shows_reporter ON public.session_no_shows FOR ALL
  USING (reported_by = auth.uid());
CREATE POLICY session_no_shows_admin ON public.session_no_shows FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ratings: student creates/owns; mentor + admin read own
CREATE POLICY ratings_student ON public.ratings FOR ALL
  USING (student_id = auth.uid());
CREATE POLICY ratings_mentor_read ON public.ratings FOR SELECT
  USING (mentor_id = auth.uid());
CREATE POLICY ratings_admin_read ON public.ratings FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.doubt_requests dr
      WHERE dr.id = ratings.request_id
        AND public.tc_is_school_admin(dr.school_id)
    )
  );

-- mentor_assessments: mentor creates/owns; admin read; NEVER student
CREATE POLICY mentor_assessments_mentor ON public.mentor_assessments FOR ALL
  USING (mentor_id = auth.uid());
CREATE POLICY mentor_assessments_admin_read ON public.mentor_assessments FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.doubt_requests dr
      WHERE dr.id = mentor_assessments.request_id
        AND public.tc_is_school_admin(dr.school_id)
    )
  );
-- No SELECT policy for students -> they can never read assessments.

-- allowance_transactions: student own + admin
CREATE POLICY allowance_transactions_student ON public.allowance_transactions FOR SELECT
  USING (student_id = auth.uid());
CREATE POLICY allowance_transactions_admin ON public.allowance_transactions FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- urgent_pass_usage: student own + admin
CREATE POLICY urgent_pass_usage_student ON public.urgent_pass_usage FOR SELECT
  USING (student_id = auth.uid());
CREATE POLICY urgent_pass_usage_admin ON public.urgent_pass_usage FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- slt_access_grants: own + admin
CREATE POLICY slt_access_grants_own ON public.slt_access_grants FOR SELECT
  USING (user_id = auth.uid());
CREATE POLICY slt_access_grants_admin ON public.slt_access_grants FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ============================================================
-- HELPER: week start date (Monday boundary) in school timezone ──
-- ============================================================
CREATE OR REPLACE FUNCTION public.tc_week_start(p_ts TIMESTAMPTZ, p_tz TEXT)
RETURNS DATE
LANGUAGE sql STABLE
AS $$
  SELECT (p_ts AT TIME ZONE p_tz)::DATE
         - EXTRACT(ISODOW FROM (p_ts AT TIME ZONE p_tz))::INTEGER + 1;
$$;

-- ============================================================
-- RPC: submit_doubt — creates conversation, request, first message
-- ============================================================
CREATE OR REPLACE FUNCTION public.submit_doubt(
  p_subject_id         UUID,
  p_question           TEXT,
  p_chapter            TEXT DEFAULT NULL,
  p_question_number    TEXT DEFAULT NULL,
  p_explanation        TEXT DEFAULT NULL,
  p_previous_attempts  TEXT DEFAULT NULL,
  p_urgent             BOOLEAN DEFAULT FALSE,
  p_urgent_reason      TEXT DEFAULT NULL,
  p_attachment_ids     UUID[] DEFAULT '{}'::UUID[]
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid          UUID := auth.uid();
  v_student      students%ROWTYPE;
  v_settings     mentor_desk_settings%ROWTYPE;
  v_school_id    UUID;
  v_conv_id      UUID;
  v_req_id       UUID;
  v_open_count   INTEGER;
  v_urgent_used  BOOLEAN := FALSE;
  v_week_start   DATE;
  v_mentor       UUID;
  v_teacher_id   UUID;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authenticated');
  END IF;

  -- Resolve the student record for this user
  SELECT * INTO v_student
  FROM students
  WHERE user_id = v_uid AND is_active = TRUE
  LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'student_not_found');
  END IF;
  v_school_id := v_student.school_id;

  -- Settings
  SELECT * INTO v_settings
  FROM mentor_desk_settings
  WHERE school_id = v_school_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'settings_not_configured');
  END IF;

  -- Subject must belong to the school
  IF NOT EXISTS (
    SELECT 1 FROM subjects WHERE id = p_subject_id AND school_id = v_school_id
  ) THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_subject');
  END IF;

  -- Open-doubt limit per subject
  SELECT COUNT(*) INTO v_open_count
  FROM doubt_requests
  WHERE student_id = v_uid
    AND subject_id = p_subject_id
    AND status IN ('waiting', 'assigned');
  IF v_open_count >= v_settings.open_doubt_limit THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'doubt_limit_reached');
  END IF;

  -- Urgent pass validation
  IF p_urgent THEN
    IF p_urgent_reason IS NULL OR trim(p_urgent_reason) = '' THEN
      RETURN jsonb_build_object('success', FALSE, 'error', 'urgent_reason_required');
    END IF;
    v_week_start := tc_week_start(NOW(), (SELECT timezone FROM school_settings WHERE school_id = v_school_id));
    IF EXISTS (
      SELECT 1 FROM urgent_pass_usage
      WHERE student_id = v_uid AND subject_id = p_subject_id AND week_start = v_week_start
    ) THEN
      RETURN jsonb_build_object('success', FALSE, 'error', 'urgent_pass_used');
    END IF;
  END IF;

  -- Create the conversation (mentor_desk type)
  INSERT INTO conversations(school_id, type, title, created_by, is_active)
  VALUES (v_school_id, 'mentor_desk', 'Doubt: ' || left(p_question, 60), v_uid, TRUE)
  RETURNING id INTO v_conv_id;

  INSERT INTO conversation_members(conversation_id, user_id, role, can_send)
  VALUES (v_conv_id, v_uid, 'student', TRUE);

  -- Create the doubt request
  INSERT INTO doubt_requests(
    school_id, conversation_id, student_id, student_record_id,
    subject_id, question, chapter, question_number, explanation,
    previous_attempts, urgent, urgent_reason, status, created_at, updated_at
  )
  VALUES (
    v_school_id, v_conv_id, v_uid, v_student.id,
    p_subject_id, p_question, p_chapter, p_question_number, p_explanation,
    p_previous_attempts, p_urgent, p_urgent_reason,
    CASE WHEN p_urgent THEN 'waiting' ELSE 'waiting' END,
    NOW(), NOW()
  )
  RETURNING id INTO v_req_id;

  -- Consume urgent pass atomically
  IF p_urgent THEN
    INSERT INTO urgent_pass_usage(school_id, student_id, subject_id, request_id, week_start)
    VALUES (v_school_id, v_uid, p_subject_id, v_req_id, v_week_start)
    ON CONFLICT (student_id, subject_id, week_start) DO NOTHING;
    IF FOUND THEN
      v_urgent_used := TRUE;
      UPDATE doubt_requests SET urgent_pass_used = TRUE WHERE id = v_req_id;
    END IF;
  END IF;

  -- Create the first message (the doubt itself) via send_message for moderation
  IF p_question IS NOT NULL AND length(trim(p_question)) > 0 THEN
    PERFORM public.send_message(
      v_conv_id, v_uid, p_question,
      gen_random_uuid()::TEXT, NULL, NULL
    );
  END IF;

  -- Link attachments (owned by the student, in this school)
  IF array_length(p_attachment_ids, 1) IS NOT NULL THEN
    UPDATE attachments
    SET message_id = (
      SELECT id FROM messages
      WHERE conversation_id = v_conv_id AND sender_id = v_uid
      ORDER BY created_at DESC LIMIT 1
    )
    WHERE id = ANY(p_attachment_ids)
      AND uploader_id = v_uid
      AND school_id = v_school_id
      AND message_id IS NULL;
  END IF;

  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome, metadata)
  VALUES (v_school_id, v_uid, 'doubt.submit', 'doubt_request', v_req_id::TEXT, 'success',
          jsonb_build_object('urgent', p_urgent, 'subject_id', p_subject_id));

  RETURN jsonb_build_object(
    'success', TRUE,
    'request_id', v_req_id,
    'conversation_id', v_conv_id,
    'status', 'waiting',
    'urgent_pass_used', v_urgent_used
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_doubt(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN, TEXT, UUID[]) TO authenticated;

-- ============================================================
-- RPC: claim_doubt — mentor claims a waiting request (atomic)
-- ============================================================
CREATE OR REPLACE FUNCTION public.claim_doubt(
  p_request_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid       UUID := auth.uid();
  v_req       doubt_requests%ROWTYPE;
  v_teacher   teachers%ROWTYPE;
  v_approval  mentor_subject_approvals%ROWTYPE;
  v_conflict  BOOLEAN := FALSE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO v_req FROM doubt_requests WHERE id = p_request_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'request_not_found');
  END IF;

  -- Caller must be a teacher in the same school
  SELECT * INTO v_teacher
  FROM teachers
  WHERE user_id = v_uid AND school_id = v_req.school_id AND is_active = TRUE
  LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_a_teacher');
  END IF;

  -- Must be approved for the subject
  SELECT * INTO v_approval
  FROM mentor_subject_approvals
  WHERE teacher_id = v_teacher.id AND subject_id = v_req.subject_id
    AND status = 'approved';
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_approved_for_subject');
  END IF;

  -- Only waiting requests can be claimed
  IF v_req.status <> 'waiting' THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'request_not_waiting');
  END IF;

  -- Named-mentor restriction: only the named mentor can claim initially
  IF v_req.named_mentor AND v_req.assigned_mentor_id IS DISTINCT FROM v_uid THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'named_mentor_only');
  END IF;

  -- Atomic claim: only one mentor can transition waiting -> assigned
  UPDATE doubt_requests
  SET status = 'assigned',
      assigned_mentor_id = v_uid,
      assigned_teacher_id = v_teacher.id,
      updated_at = NOW()
  WHERE id = p_request_id
    AND status = 'waiting'
    AND (NOT named_mentor OR assigned_mentor_id = v_uid);

  IF NOT FOUND THEN
    -- Another mentor claimed it first, or named-mentor mismatch
    RETURN jsonb_build_object('success', FALSE, 'error', 'already_claimed');
  END IF;

  -- Add mentor to the conversation
  INSERT INTO conversation_members(conversation_id, user_id, role, can_send)
  VALUES (v_req.conversation_id, v_uid, 'teacher', TRUE)
  ON CONFLICT (conversation_id, user_id) DO NOTHING;

  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome)
  VALUES (v_req.school_id, v_uid, 'doubt.claim', 'doubt_request', p_request_id::TEXT, 'success');

  RETURN jsonb_build_object(
    'success', TRUE,
    'request_id', p_request_id,
    'conversation_id', v_req.conversation_id,
    'status', 'assigned'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_doubt(UUID) TO authenticated;

-- ============================================================
-- RPC: reply_doubt — post a reply; auto-assigns if waiting
-- ============================================================
CREATE OR REPLACE FUNCTION public.reply_doubt(
  p_request_id UUID,
  p_body       TEXT,
  p_attachment_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid    UUID := auth.uid();
  v_req    doubt_requests%ROWTYPE;
  v_member conversation_members%ROWTYPE;
  v_msg_id UUID;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO v_req FROM doubt_requests WHERE id = p_request_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'request_not_found');
  END IF;

  -- Must be a member of the conversation
  SELECT * INTO v_member
  FROM conversation_members
  WHERE conversation_id = v_req.conversation_id
    AND user_id = v_uid AND removed_at IS NULL;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_a_member');
  END IF;

  -- Auto-assign on first mentor reply when still waiting
  IF v_req.status = 'waiting' AND v_member.role = 'teacher' THEN
    UPDATE doubt_requests
    SET status = 'assigned',
        assigned_mentor_id = v_uid,
        assigned_teacher_id = (SELECT id FROM teachers WHERE user_id = v_uid LIMIT 1),
        first_reply_at = NOW(),
        updated_at = NOW()
    WHERE id = p_request_id AND status = 'waiting';
  END IF;

  -- Send the message via the existing send_message RPC (moderation, idempotency)
  PERFORM public.send_message(
    v_req.conversation_id, v_uid, p_body,
    gen_random_uuid()::TEXT, NULL, p_attachment_id
  );

  UPDATE doubt_requests SET updated_at = NOW() WHERE id = p_request_id;

  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome)
  VALUES (v_req.school_id, v_uid, 'doubt.reply', 'doubt_request', p_request_id::TEXT, 'success');

  RETURN jsonb_build_object('success', TRUE, 'request_id', p_request_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.reply_doubt(UUID, TEXT, UUID) TO authenticated;

-- ============================================================
-- RPC: resolve_doubt — mentor marks a request resolved
-- ============================================================
CREATE OR REPLACE FUNCTION public.resolve_doubt(
  p_request_id UUID
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

  IF v_req.assigned_mentor_id IS DISTINCT FROM v_uid THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_assigned_mentor');
  END IF;

  IF v_req.status = 'closed' THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'already_closed');
  END IF;

  UPDATE doubt_requests
  SET status = 'resolved', resolved_at = NOW(), updated_at = NOW()
  WHERE id = p_request_id
    AND status IN ('waiting', 'assigned', 'resolved');

  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome)
  VALUES (v_req.school_id, v_uid, 'doubt.resolve', 'doubt_request', p_request_id::TEXT, 'success');

  RETURN jsonb_build_object('success', TRUE, 'request_id', p_request_id, 'status', 'resolved');
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_doubt(UUID) TO authenticated;

-- ============================================================
-- RPC: reopen_doubt — student reopens a closed/resolved doubt
-- ============================================================
CREATE OR REPLACE FUNCTION public.reopen_doubt(
  p_request_id UUID
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

  IF v_req.student_id IS DISTINCT FROM v_uid THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_the_student');
  END IF;

  IF v_req.status = 'waiting' OR v_req.status = 'assigned' THEN
    RETURN jsonb_build_object('success', TRUE, 'request_id', p_request_id, 'status', v_req.status);
  END IF;

  UPDATE doubt_requests
  SET status = 'waiting',
      assigned_mentor_id = NULL,
      assigned_teacher_id = NULL,
      resolved_at = NULL,
      closed_at = NULL,
      updated_at = NOW()
  WHERE id = p_request_id AND status IN ('resolved', 'closed');

  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome)
  VALUES (v_req.school_id, v_uid, 'doubt.reopen', 'doubt_request', p_request_id::TEXT, 'success');

  RETURN jsonb_build_object('success', TRUE, 'request_id', p_request_id, 'status', 'waiting');
END;
$$;

GRANT EXECUTE ON FUNCTION public.reopen_doubt(UUID) TO authenticated;

-- ============================================================
-- RPC: book_session — student books a session (allowance enforced)
-- ============================================================
CREATE OR REPLACE FUNCTION public.book_session(
  p_subject_id        UUID,
  p_mentor_id         UUID,           -- user_profiles id of the mentor (or null for any)
  p_duration_minutes  INTEGER,
  p_scheduled_at      TIMESTAMPTZ,    -- preferred time (mentor confirms final)
  p_topic             TEXT,
  p_preparation       TEXT DEFAULT NULL,
  p_attachment_ids    UUID[] DEFAULT '{}'::UUID[]
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid          UUID := auth.uid();
  v_student      students%ROWTYPE;
  v_settings     mentor_desk_settings%ROWTYPE;
  v_school_id    UUID;
  v_teacher      teachers%ROWTYPE;
  v_approval     mentor_subject_approvals%ROWTYPE;
  v_week_start   DATE;
  v_used         INTEGER := 0;
  v_allowance    INTEGER;
  v_booking_id   UUID;
  v_is_named     BOOLEAN := (p_mentor_id IS NOT NULL);
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO v_student
  FROM students
  WHERE user_id = v_uid AND is_active = TRUE
  LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'student_not_found');
  END IF;
  v_school_id := v_student.school_id;

  SELECT * INTO v_settings
  FROM mentor_desk_settings WHERE school_id = v_school_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'settings_not_configured');
  END IF;

  -- Subject belongs to school
  IF NOT EXISTS (
    SELECT 1 FROM subjects WHERE id = p_subject_id AND school_id = v_school_id
  ) THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_subject');
  END IF;

  -- Duration must be an allowed length
  IF NOT (p_duration_minutes = ANY(v_settings.session_lengths)) THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_duration');
  END IF;

  -- Mentor must be approved for the subject (when named)
  IF v_is_named THEN
    SELECT t.* INTO v_teacher
    FROM teachers t
    JOIN user_profiles up ON up.id = p_mentor_id
    WHERE t.user_id = p_mentor_id AND t.school_id = v_school_id AND t.is_active = TRUE
    LIMIT 1;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', FALSE, 'error', 'mentor_not_found');
    END IF;

    SELECT * INTO v_approval
    FROM mentor_subject_approvals
    WHERE teacher_id = v_teacher.id AND subject_id = p_subject_id
      AND status = 'approved';
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', FALSE, 'error', 'mentor_not_approved');
    END IF;
  END IF;

  -- Weekly allowance check (server-side)
  v_week_start := tc_week_start(NOW(), (SELECT timezone FROM school_settings WHERE school_id = v_school_id));
  v_allowance := v_settings.session_allowance_minutes;

  SELECT COALESCE(SUM(allowance_minutes_used), 0) INTO v_used
  FROM session_bookings
  WHERE student_id = v_uid
    AND subject_id = p_subject_id
    AND status IN ('confirmed', 'completed')
    AND date_trunc('week', requested_at)::DATE >= v_week_start;

  IF v_used + p_duration_minutes > v_allowance THEN
    RETURN jsonb_build_object(
      'success', FALSE, 'error', 'allowance_exceeded',
      'remaining', v_allowance - v_used
    );
  END IF;

  INSERT INTO session_bookings(
    school_id, student_id, student_record_id, mentor_id, mentor_record_id,
    subject_id, duration_minutes, topic, preparation,
    scheduled_at, status, allowance_minutes_used, created_at, updated_at
  )
  VALUES (
    v_school_id, v_uid, v_student.id,
    CASE WHEN v_is_named THEN p_mentor_id ELSE NULL END,
    CASE WHEN v_is_named THEN (SELECT id FROM teachers WHERE user_id = p_mentor_id LIMIT 1) ELSE NULL END,
    p_subject_id, p_duration_minutes, p_topic, p_preparation,
    p_scheduled_at, 'requested', p_duration_minutes,
    NOW(), NOW()
  )
  RETURNING id INTO v_booking_id;

  -- Deduct allowance tentatively (refunded if not confirmed / cancelled)
  INSERT INTO allowance_transactions(
    school_id, student_id, subject_id, booking_id, week_start,
    action, minutes, reason, created_at
  )
  VALUES (v_school_id, v_uid, p_subject_id, v_booking_id, v_week_start,
          'deduct', p_duration_minutes, 'session_booked', NOW());

  -- Link attachments
  IF array_length(p_attachment_ids, 1) IS NOT NULL THEN
    UPDATE attachments
    SET message_id = NULL, -- bookings carry attachments on the request row; keep unattached until confirmed
        school_id = v_school_id
    WHERE id = ANY(p_attachment_ids)
      AND uploader_id = v_uid
      AND school_id = v_school_id;
  END IF;

  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome)
  VALUES (v_school_id, v_uid, 'session.book', 'session_booking', v_booking_id::TEXT, 'success');

  RETURN jsonb_build_object(
    'success', TRUE,
    'booking_id', v_booking_id,
    'status', 'requested',
    'allowance_remaining', v_allowance - v_used - p_duration_minutes
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.book_session(UUID, UUID, INTEGER, TIMESTAMPTZ, TEXT, TEXT, UUID[]) TO authenticated;

-- ============================================================
-- RPC: confirm_session — mentor confirms schedule (final allowance basis)
-- ============================================================
CREATE OR REPLACE FUNCTION public.confirm_session(
  p_booking_id     UUID,
  p_scheduled_at   TIMESTAMPTZ,
  p_duration_minutes INTEGER,
  p_meeting_link   TEXT DEFAULT NULL,
  p_meeting_room   TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid   UUID := auth.uid();
  v_booking session_bookings%ROWTYPE;
  v_teacher teachers%ROWTYPE;
  v_adjust  INTEGER;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO v_booking FROM session_bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'booking_not_found');
  END IF;

  -- Only the assigned mentor can confirm
  SELECT * INTO v_teacher
  FROM teachers
  WHERE user_id = v_uid AND school_id = v_booking.school_id AND is_active = TRUE
  LIMIT 1;
  IF NOT FOUND OR v_teacher.id IS DISTINCT FROM v_booking.mentor_record_id THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_the_mentor');
  END IF;

  IF v_booking.status <> 'requested' THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'booking_not_requested');
  END IF;

  -- Adjust allowance: confirmed length is the basis; refund difference if shorter
  v_adjust := p_duration_minutes - v_booking.allowance_minutes_used;

  UPDATE session_bookings
  SET mentor_id = v_uid,
      mentor_record_id = v_teacher.id,
      scheduled_at = p_scheduled_at,
      duration_minutes = p_duration_minutes,
      meeting_link = p_meeting_link,
      meeting_room = p_meeting_room,
      status = 'confirmed',
      confirmed_at = NOW(),
      allowance_minutes_used = p_duration_minutes,
      updated_at = NOW()
  WHERE id = p_booking_id AND status = 'requested';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'booking_not_requested');
  END IF;

  -- Top-up or refund the allowance difference
  IF v_adjust <> 0 THEN
    INSERT INTO allowance_transactions(
      school_id, student_id, subject_id, booking_id,
      date_trunc('week', v_booking.requested_at)::DATE,
      action, minutes, reason, created_at
    )
    VALUES (
      v_booking.school_id, v_booking.student_id, v_booking.subject_id,
      p_booking_id, date_trunc('week', v_booking.requested_at)::DATE,
      CASE WHEN v_adjust > 0 THEN 'deduct' ELSE 'refund' END,
      ABS(v_adjust),
      'session_confirmed_length_adjust', NOW()
    );
  END IF;

  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome)
  VALUES (v_booking.school_id, v_uid, 'session.confirm', 'session_booking', p_booking_id::TEXT, 'success');

  RETURN jsonb_build_object(
    'success', TRUE, 'booking_id', p_booking_id, 'status', 'confirmed'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.confirm_session(UUID, TIMESTAMPTZ, INTEGER, TEXT, TEXT) TO authenticated;

-- ============================================================
-- RPC: cancel_session — cancel before scheduling (refund allowance)
-- ============================================================
CREATE OR REPLACE FUNCTION public.cancel_session(
  p_booking_id UUID,
  p_cancelled_by UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid    UUID := COALESCE(p_cancelled_by, auth.uid());
  v_booking session_bookings%ROWTYPE;
  v_week_start DATE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO v_booking FROM session_bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'booking_not_found');
  END IF;

  -- Only student or the assigned mentor may cancel a requested booking
  IF v_uid IS DISTINCT FROM v_booking.student_id
     AND v_uid IS DISTINCT FROM v_booking.mentor_id THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_a_participant');
  END IF;

  IF v_booking.status <> 'requested' THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'booking_not_requested');
  END IF;

  IF v_booking.refunded THEN
    RETURN jsonb_build_object('success', TRUE, 'booking_id', p_booking_id, 'status', v_booking.status);
  END IF;

  UPDATE session_bookings
  SET status = CASE WHEN v_uid = v_booking.student_id THEN 'cancelled_by_student'
                    ELSE 'cancelled_by_mentor' END,
      cancelled_at = NOW(), cancelled_by = v_uid,
      refunded = TRUE, updated_at = NOW()
  WHERE id = p_booking_id AND status = 'requested';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'booking_not_requested');
  END IF;

  -- Refund the full allowance (no double refund)
  INSERT INTO allowance_transactions(
    school_id, student_id, subject_id, booking_id,
    date_trunc('week', v_booking.requested_at)::DATE,
    action, minutes, reason, created_at
  )
  VALUES (
    v_booking.school_id, v_booking.student_id, v_booking.subject_id,
    p_booking_id, date_trunc('week', v_booking.requested_at)::DATE,
    'refund', v_booking.allowance_minutes_used, 'session_cancelled', NOW()
  );

  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome)
  VALUES (v_booking.school_id, v_uid, 'session.cancel', 'session_booking', p_booking_id::TEXT, 'success');

  RETURN jsonb_build_object('success', TRUE, 'booking_id', p_booking_id, 'refunded', TRUE);
END;
$$;

GRANT EXECUTE ON Function public.cancel_session(UUID, UUID) TO authenticated;

-- ============================================================
-- RPC: generate_verification_code — 6-digit code, visible 10 min before
-- ============================================================
CREATE OR REPLACE FUNCTION public.generate_verification_code(
  p_booking_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid     UUID := auth.uid();
  v_booking session_bookings%ROWTYPE;
  v_settings mentor_desk_settings%ROWTYPE;
  v_code    TEXT;
  v_expires TIMESTAMPTZ;
  v_visible TIMESTAMPTZ;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO v_booking FROM session_bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'booking_not_found');
  END IF;

  -- Only the student may request the code (mentor sees it only at verification time)
  IF v_uid IS DISTINCT FROM v_booking.student_id THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_the_student');
  END IF;

  IF v_booking.status <> 'confirmed' THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'booking_not_confirmed');
  END IF;

  SELECT * INTO v_settings FROM mentor_desk_settings WHERE school_id = v_booking.school_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'settings_not_configured');
  END IF;

  -- Code is only available starting 10 minutes before the session
  v_visible := v_booking.scheduled_at - (v_settings.code_visible_minutes_before || ' minutes')::INTERVAL;
  IF NOW() < v_visible THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'code_not_yet_visible',
                              'visible_at', v_visible);
  END IF;

  -- Generate a secure 6-digit code
  v_code := lpad((floor(random() * 1000000))::INTEGER::TEXT, 6, '0');
  v_expires := v_booking.scheduled_at + INTERVAL '30 minutes';

  UPDATE session_bookings
  SET verification_code = v_code,
      code_expires_at = v_expires,
      code_attempts = 0,
      code_locked_at = NULL,
      code_visible_at = NOW(),
      updated_at = NOW()
  WHERE id = p_booking_id;

  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome)
  VALUES (v_booking.school_id, v_uid, 'session.code.generated', 'session_booking', p_booking_id::TEXT, 'success');

  -- Return the code to the student (mentor does NOT get it via this RPC)
  RETURN jsonb_build_object(
    'success', TRUE,
    'verification_code', v_code,
    'expires_at', v_expires,
    'visible_at', v_visible
  );
END;
$$;

GRANT EXECUTE ON Function public.generate_verification_code(UUID) TO authenticated;

-- ============================================================
-- RPC: verify_session_code — mentor enters code (5 attempts lock)
-- ============================================================
CREATE OR REPLACE FUNCTION public.verify_session_code(
  p_booking_id UUID,
  p_code       TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid     UUID := auth.uid();
  v_booking session_bookings%ROWTYPE;
  v_settings mentor_desk_settings%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO v_booking FROM session_bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'booking_not_found');
  END IF;

  -- Only the assigned mentor may verify
  IF v_uid IS DISTINCT FROM v_booking.mentor_id THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_the_mentor');
  END IF;

  IF v_booking.status <> 'confirmed' THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'booking_not_confirmed');
  END IF;

  -- Code must exist and be visible (10 min before start)
  IF v_booking.verification_code IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'no_code');
  END IF;

  -- Locked?
  IF v_booking.code_locked_at IS NOT NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'code_locked');
  END IF;

  -- Expired?
  IF v_booking.code_expires_at IS NOT NULL AND NOW() > v_booking.code_expires_at THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'code_expired');
  END IF;

  SELECT * INTO v_settings FROM mentor_desk_settings WHERE school_id = v_booking.school_id;

  -- Increment attempts
  UPDATE session_bookings
  SET code_attempts = code_attempts + 1, updated_at = NOW()
  WHERE id = p_booking_id;

  IF v_booking.code_attempts + 1 >= v_settings.max_verification_attempts THEN
    -- 5th incorrect (or this attempt reaches limit) -> lock
    -- Only lock if the code is wrong
    IF v_booking.verification_code <> p_code THEN
      UPDATE session_bookings
      SET code_locked_at = NOW(), updated_at = NOW()
      WHERE id = p_booking_id;
      RETURN jsonb_build_object('success', FALSE, 'error', 'code_locked',
                                'reason', 'max_attempts_reached');
    END IF
  END IF;

  -- Check code match
  IF v_booking.verification_code <> p_code THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'incorrect_code',
                              'attempts_remaining', v_settings.max_verification_attempts - (v_booking.code_attempts + 1));
  END IF;

  -- Success: mark verified + completed
  UPDATE session_bookings
  SET verified_at = NOW(),
      status = 'completed',
      updated_at = NOW()
  WHERE id = p_booking_id;

  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome)
  VALUES (v_booking.school_id, v_uid, 'session.verify', 'session_booking', p_booking_id::TEXT, 'success');

  RETURN jsonb_build_object('success', TRUE, 'booking_id', p_booking_id, 'status', 'completed');
END;
$$;

GRANT EXECUTE ON Function public.verify_session_code(UUID, TEXT) TO authenticated;

-- ============================================================
-- RPC: close_session_without_code — mentor exception workflow
-- ============================================================
CREATE OR REPLACE FUNCTION public.close_session_without_code(
  p_booking_id UUID,
  p_reason     TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid     UUID := auth.uid();
  v_booking session_bookings%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO v_booking FROM session_bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'booking_not_found');
  END IF;

  IF v_uid IS DISTINCT FROM v_booking.mentor_id THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_the_mentor');
  END IF;

  IF v_booking.status <> 'confirmed' THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'booking_not_confirmed');
  END IF;

  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'reason_required');
  END IF;

  UPDATE session_bookings
  SET status = 'unverified_closed',
      closed_without_code = TRUE,
      close_reason = p_reason,
      updated_at = NOW()
  WHERE id = p_booking_id AND status = 'confirmed';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'booking_not_confirmed');
  END IF;

  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome, metadata)
  VALUES (v_booking.school_id, v_uid, 'session.close_without_code', 'session_booking',
          p_booking_id::TEXT, 'success', jsonb_build_object('reason', p_reason));

  RETURN jsonb_build_object('success', TRUE, 'booking_id', p_booking_id, 'status', 'unverified_closed');
END;
$$;

GRANT EXECUTE ON Function public.close_session_without_code(UUID, TEXT) TO authenticated;

-- ============================================================
-- RPC: record_no_show — no-show (refund + admin review)
-- ============================================================
CREATE OR REPLACE FUNCTION public.record_no_show(
  p_booking_id   UUID,
  p_reported_by_role TEXT,
  p_reason       TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid     UUID := auth.uid();
  v_booking session_bookings%ROWTYPE;
  v_ns_type no_show_type;
  v_refund  INTEGER;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO v_booking FROM session_bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'booking_not_found');
  END IF;

  -- Participant reports the other party
  IF v_uid = v_booking.student_id THEN
    v_ns_type := 'mentor_no_show';
    v_refund := v_booking.allowance_minutes_used;
  ELSIF v_uid = v_booking.mentor_id THEN
    v_ns_type := 'student_no_show';
    v_refund := 0; -- student no-show: no refund to student
  ELSE
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_a_participant');
  END IF;

  IF v_booking.status IN ('no_show_student', 'no_show_mentor', 'completed') THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'already_resolved');
  END IF;

  INSERT INTO session_no_shows(
    school_id, booking_id, reported_by, reported_by_role,
    no_show_type, refund_minutes, review_status, created_at
  )
  VALUES (
    v_booking.school_id, p_booking_id, v_uid, p_reported_by_role,
    v_ns_type, v_refund, 'pending', NOW()
  );

  IF v_ns_type = 'mentor_no_show' THEN
    -- Refund the student's allowance
    UPDATE session_bookings
    SET status = 'no_show_mentor', refunded = TRUE, updated_at = NOW()
    WHERE id = p_booking_id AND status = 'confirmed';

    INSERT INTO allowance_transactions(
      school_id, student_id, subject_id, booking_id,
      date_trunc('week', v_booking.requested_at)::DATE,
      action, minutes, reason, created_at
    )
    VALUES (
      v_booking.school_id, v_booking.student_id, v_booking.subject_id,
      p_booking_id, date_trunc('week', v_booking.requested_at)::DATE,
      'refund', v_refund, 'mentor_no_show', NOW()
    );
  ELSE
    UPDATE session_bookings
    SET status = 'no_show_student', updated_at = NOW()
    WHERE id = p_booking_id AND status = 'confirmed';
  END IF;

  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome)
  VALUES (v_booking.school_id, v_uid, 'session.no_show', 'session_booking', p_booking_id::TEXT, 'success');

  RETURN jsonb_build_object(
    'success', TRUE,
    'booking_id', p_booking_id,
    'no_show_type', v_ns_type,
    'refund_minutes', v_refund
  );
END;
$$;

GRANT EXECUTE ON Function public.record_no_show(UUID, TEXT, TEXT) TO authenticated;

-- ============================================================
-- RPC: submit_rating — student rates a closed request (once)
-- ============================================================
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

  IF v_req.status <> 'resolved' AND v_req.status <> 'closed' THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'request_not_closed');
  END IF;

  -- One rating per request (UNIQUE constraint enforces; catch conflict)
  INSERT INTO ratings(school_id, request_id, student_id, mentor_id, rating, comment)
  VALUES (v_req.school_id, p_request_id, v_uid, v_req.assigned_mentor_id, p_rating, p_comment);

  UPDATE doubt_requests SET status = 'closed', closed_at = NOW(), updated_at = NOW()
  WHERE id = p_request_id AND status = 'resolved';

  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome)
  VALUES (v_req.school_id, v_uid, 'rating.submit', 'rating', p_request_id::TEXT, 'success');

  RETURN jsonb_build_object('success', TRUE, 'request_id', p_request_id, 'rating', p_rating);
END;
$$;

GRANT EXECUTE ON Function public.submit_rating(UUID, INTEGER, TEXT) TO authenticated;

-- ============================================================
-- RPC: submit_mentor_assessment — mentor's private assessment of student
-- ============================================================
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

  IF v_req.status <> 'resolved' AND v_req.status <> 'closed' THEN
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

GRANT EXECUTE ON Function public.submit_mentor_assessment(UUID, engagement_scale, engagement_scale, TEXT) TO authenticated;

-- ============================================================
-- RPC: set_mentor_availability — Available / Away
-- ============================================================
CREATE OR REPLACE FUNCTION public.set_mentor_availability(p_status availability_status)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_teacher teachers%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT * INTO v_teacher
  FROM teachers
  WHERE user_id = auth.uid() AND is_active = TRUE
  LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_a_teacher';
  END IF;

  INSERT INTO mentor_availability(school_id, teacher_id, status, updated_at)
  VALUES (v_teacher.school_id, v_teacher.id, p_status, NOW())
  ON CONFLICT (teacher_id) DO UPDATE
    SET status = EXCLUDED.status, updated_at = NOW();

  PERFORM public.touch_my_presence();
END;
$$;

GRANT EXECUTE ON Function public.set_mentor_availability(availability_status) TO authenticated;

-- ============================================================
-- RPC: approve_mentor_subject — admin approves/rejects a mentor for a subject
-- ============================================================
CREATE OR REPLACE FUNCTION public.approve_mentor_subject(
  p_teacher_id UUID,
  p_subject_id UUID,
  p_approved   BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_school UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authenticated');
  END IF;

  SELECT t.school_id INTO v_school FROM teachers WHERE id = p_teacher_id;
  IF v_school IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'teacher_not_found');
  END IF;

  IF NOT public.tc_is_school_admin(v_school) THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'forbidden');
  END IF;

  INSERT INTO mentor_subject_approvals(
    school_id, teacher_id, subject_id,
    status, approved_by, approved_at, created_at
  )
  VALUES (
    v_school, p_teacher_id, p_subject_id,
    CASE WHEN p_approved THEN 'approved' ELSE 'rejected' END,
    auth.uid(), NOW(), NOW()
  )
  ON CONFLICT (teacher_id, subject_id) DO UPDATE
    SET status = CASE WHEN p_approved THEN 'approved' ELSE 'rejected' END,
        approved_by = auth.uid(),
        approved_at = NOW(),
        updated_at = NOW();

  RETURN jsonb_build_object('success', TRUE);
END;
$$;

GRANT EXECUTE ON Function public.approve_mentor_subject(UUID, UUID, BOOLEAN) TO authenticated;

-- ============================================================
-- RPC: reset_weekly_allowances — cron: reset weekly counters
-- ============================================================
-- Weekly "counters" are derived from allowance_transactions by week_start,
-- so there is no mutable counter to reset. This RPC is a no-op placeholder
-- kept for the operations runbook and to mark the reset ran.
CREATE OR REPLACE FUNCTION public.reset_weekly_allowances()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER := 0;
BEGIN
  -- Nothing mutable to reset: usage is computed from transactions grouped by week_start.
  -- Log the run for audit.
  INSERT INTO background_jobs(type, status, payload, attempts, max_attempts, completed_at, created_at)
  VALUES ('weekly_allowance_reset', 'completed', '{}'::jsonb, 0, 1, NOW(), NOW());
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN jsonb_build_object('success', TRUE, 'note', 'allowance is week-derived; no mutable reset needed');
END;
$$;

GRANT EXECUTE ON Function public.reset_weekly_allowances() TO authenticated;

-- Schedule the weekly allowance reset (Monday 00:00 school timezone) if pg_cron available
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule(
      'weekly_allowance_reset',
      '0 0 * * 1',
      $cron$ SELECT public.reset_weekly_allowances(); $cron$
    );
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'weekly_allowance_reset cron not scheduled: %', SQLERRM;
END $$;
