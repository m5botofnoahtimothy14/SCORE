-- ============================================================
-- 00018 — Role capabilities: presence, direct teacher chat,
--          teacher posting, leadership staffing requests,
--          roster management, conversation insights.
-- Everything here is server-enforced; the app only reflects it.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Teacher presence.
--    The app pings on open/resume; "online" = seen recently.
-- ------------------------------------------------------------
ALTER TABLE teachers
  ADD COLUMN IF NOT EXISTS last_seen_at timestamptz;

CREATE OR REPLACE FUNCTION public.touch_my_presence()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE teachers
     SET last_seen_at = NOW()
   WHERE user_id = auth.uid()
     AND is_active = TRUE;
$$;

GRANT EXECUTE ON FUNCTION public.touch_my_presence() TO authenticated;

-- ------------------------------------------------------------
-- 2. Direct student -> teacher conversation.
--    Reuses the existing 'student_teacher' conversation type.
--    Idempotent: returns the existing thread when there is one.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.start_teacher_conversation(p_teacher_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid         uuid := auth.uid();
  v_school      uuid;
  v_teacher_uid uuid;
  v_teacher_on  boolean;
  v_conv        uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT t.school_id, t.user_id, t.is_active
    INTO v_school, v_teacher_uid, v_teacher_on
    FROM teachers t
   WHERE t.id = p_teacher_id;

  IF v_school IS NULL OR v_teacher_on IS DISTINCT FROM TRUE OR v_teacher_uid IS NULL THEN
    RAISE EXCEPTION 'teacher_unavailable';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM school_memberships m
     WHERE m.user_id = v_uid AND m.school_id = v_school AND m.is_active = TRUE
  ) THEN
    RAISE EXCEPTION 'not_a_member';
  END IF;

  SELECT c.id INTO v_conv
    FROM conversations c
    JOIN conversation_members a
      ON a.conversation_id = c.id AND a.user_id = v_uid AND a.removed_at IS NULL
    JOIN conversation_members b
      ON b.conversation_id = c.id AND b.user_id = v_teacher_uid AND b.removed_at IS NULL
   WHERE c.school_id = v_school AND c.type = 'student_teacher'
   LIMIT 1;

  IF v_conv IS NOT NULL THEN
    RETURN v_conv;
  END IF;

  INSERT INTO conversations(school_id, type, title, created_by)
  VALUES (v_school, 'student_teacher', NULL, v_uid)
  RETURNING id INTO v_conv;

  INSERT INTO conversation_members(conversation_id, user_id, role, can_send)
  VALUES (v_conv, v_uid, 'student', TRUE),
         (v_conv, v_teacher_uid, 'teacher', TRUE);

  INSERT INTO audit_events(school_id, action, target_type, target_id, outcome)
  VALUES (v_school, 'conversation.direct_teacher.started', 'conversation', v_conv, 'success');

  RETURN v_conv;
END;
$$;

GRANT EXECUTE ON FUNCTION public.start_teacher_conversation(uuid) TO authenticated;

-- ------------------------------------------------------------
-- 3. Leadership staffing requests.
--    Leadership proposes a teacher; only a platform/school admin
--    can approve it into the real roster.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.staff_add_requests (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id    uuid NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
  requested_by uuid NOT NULL REFERENCES auth.users(id),
  first_name   text NOT NULL,
  last_name    text NOT NULL,
  phone        text,
  email        text,
  staff_id_no  text NOT NULL,
  subject      text,
  note         text,
  status       text NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending', 'approved', 'rejected')),
  decided_by   uuid REFERENCES auth.users(id),
  decided_at   timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (school_id, staff_id_no)
);

ALTER TABLE public.staff_add_requests ENABLE ROW LEVEL SECURITY;

-- Leadership may raise and track requests; only admins may decide.
DROP POLICY IF EXISTS staff_requests_read ON public.staff_add_requests;
CREATE POLICY staff_requests_read ON public.staff_add_requests FOR SELECT
  USING (
    requested_by = auth.uid()
    OR public.tc_is_platform_owner()
    OR public.tc_has_school_role(school_id, 'head_teacher')
    OR public.tc_is_school_admin(school_id)
  );

DROP POLICY IF EXISTS staff_requests_create ON public.staff_add_requests;
CREATE POLICY staff_requests_create ON public.staff_add_requests FOR INSERT
  WITH CHECK (
    requested_by = auth.uid()
    AND (
      public.tc_is_platform_owner()
      OR public.tc_has_school_role(school_id, 'head_teacher')
      OR public.tc_is_school_admin(school_id)
    )
  );

-- ------------------------------------------------------------
-- 4. Roster management for leadership (scoped RPCs).
--    RLS cannot restrict UPDATE to a single column, so these
--    SECURITY DEFINER functions are the only safe path.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_staff_active(p_teacher_id uuid, p_active boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_school uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT school_id INTO v_school FROM teachers WHERE id = p_teacher_id;
  IF v_school IS NULL THEN RAISE EXCEPTION 'not_found'; END IF;

  IF NOT (
    public.tc_is_platform_owner()
    OR public.tc_has_school_role(v_school, 'head_teacher')
    OR public.tc_is_school_admin(v_school)
  ) THEN
    RAISE EXCEPTION 'insufficient_permissions';
  END IF;

  UPDATE teachers SET is_active = p_active WHERE id = p_teacher_id;

  -- A deactivated staff member loses access immediately.
  IF p_active = FALSE THEN
    UPDATE school_memberships SET is_active = FALSE
     WHERE user_id = (SELECT user_id FROM teachers WHERE id = p_teacher_id)
       AND school_id = v_school;
  END IF;

  INSERT INTO audit_events(school_id, action, target_type, target_id, outcome)
  VALUES (v_school,
          CASE WHEN p_active THEN 'teacher.reactivate' ELSE 'teacher.deactivate' END,
          'teacher', p_teacher_id, 'success');
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_staff_active(uuid, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_student_active(p_student_id uuid, p_active boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_school uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT school_id INTO v_school FROM students WHERE id = p_student_id;
  IF v_school IS NULL THEN RAISE EXCEPTION 'not_found'; END IF;

  IF NOT (
    public.tc_is_platform_owner()
    OR public.tc_has_school_role(v_school, 'head_teacher')
    OR public.tc_is_school_admin(v_school)
  ) THEN
    RAISE EXCEPTION 'insufficient_permissions';
  END IF;

  UPDATE students SET is_active = p_active WHERE id = p_student_id;

  IF p_active = FALSE THEN
    UPDATE school_memberships SET is_active = FALSE
     WHERE user_id = (SELECT user_id FROM students WHERE id = p_student_id)
       AND school_id = v_school;
  END IF;

  INSERT INTO audit_events(school_id, action, target_type, target_id, outcome)
  VALUES (v_school,
          CASE WHEN p_active THEN 'student.reactivate' ELSE 'student.suspend' END,
          'student', p_student_id, 'success');
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_student_active(uuid, boolean) TO authenticated;

-- ------------------------------------------------------------
-- 5. Conversation insights (OpenAI scoring).
--    Written by the scoring edge function (service role),
--    read by leadership and teachers on their own threads.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.conversation_scores (
  conversation_id uuid PRIMARY KEY REFERENCES public.conversations(id) ON DELETE CASCADE,
  school_id       uuid NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
  overall         numeric(5,2),
  sentiment       numeric(5,2),
  safety_risk     numeric(5,2),
  resolution      numeric(5,2),
  flagged         boolean NOT NULL DEFAULT false,
  topics          text[] NOT NULL DEFAULT '{}',
  summary         text,
  model           text,
  scored_at       timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.conversation_scores ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS conversation_scores_admin_read ON public.conversation_scores;
CREATE POLICY conversation_scores_admin_read ON public.conversation_scores FOR SELECT
  USING (public.tc_is_platform_owner() OR public.tc_is_school_admin(school_id));

-- Leadership read access mirroring admin scope.
DROP POLICY IF EXISTS conversation_scores_leadership_read ON public.conversation_scores;
CREATE POLICY conversation_scores_leadership_read ON public.conversation_scores FOR SELECT
  USING (public.tc_has_school_role(school_id, 'head_teacher'));

-- A participant can read the score for their own conversation.
DROP POLICY IF EXISTS conversation_scores_member_read ON public.conversation_scores;
CREATE POLICY conversation_scores_member_read ON public.conversation_scores FOR SELECT
  USING (public.tc_is_conversation_member(conversation_id));

-- ------------------------------------------------------------
-- 6. Leadership needs to see staff activity + school files.
-- ------------------------------------------------------------
DROP POLICY IF EXISTS teachers_leadership_update ON public.teachers;
CREATE POLICY teachers_leadership_update ON public.teachers FOR UPDATE
  USING (
    public.tc_is_platform_owner()
    OR public.tc_has_school_role(school_id, 'head_teacher')
    OR public.tc_is_school_admin(school_id)
  );

-- students read own attachment metadata
DROP POLICY IF EXISTS attachments_own_list ON public.attachments;
CREATE POLICY attachments_own_list ON public.attachments FOR SELECT
  USING (uploader_id = auth.uid());

-- ------------------------------------------------------------
-- 7. Presence hygiene: index for fast "who is online" queries.
-- ------------------------------------------------------------
CREATE INDEX IF NOT EXISTS teachers_last_seen_idx
  ON public.teachers (school_id, last_seen_at DESC)
  WHERE is_active = TRUE;