-- ============================================================
-- Migration 00011 — Cast teacher membership role to school_role
-- school_memberships.role is the enum school_role; a CASE expression
-- produces text, which Postgres will not implicitly cast to an enum
-- (error 42804). Cast explicitly.
-- ============================================================

CREATE OR REPLACE FUNCTION activate_teacher(
  p_school_id       UUID,
  p_staff_id_no     TEXT,
  p_auth_user_id    UUID,
  p_phone           TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_teacher RECORD;
  v_class   RECORD;
BEGIN
  SELECT * INTO v_teacher
  FROM teachers
  WHERE school_id = p_school_id
    AND staff_id_no = p_staff_id_no
    AND is_active = TRUE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_credentials');
  END IF;

  IF v_teacher.phone IS DISTINCT FROM p_phone THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_credentials');
  END IF;

  INSERT INTO user_profiles(id, display_name, phone, is_active)
  VALUES (p_auth_user_id, v_teacher.first_name || ' ' || v_teacher.last_name, p_phone, TRUE)
  ON CONFLICT (id) DO UPDATE SET phone = p_phone, display_name = EXCLUDED.display_name;

  UPDATE teachers SET user_id = p_auth_user_id, updated_at = NOW()
  WHERE id = v_teacher.id;

  INSERT INTO school_memberships(user_id, school_id, role, is_active)
  VALUES (
    p_auth_user_id,
    p_school_id,
    (CASE WHEN v_teacher.is_leadership THEN 'head_teacher' ELSE 'teacher' END)::school_role,
    TRUE
  )
  ON CONFLICT (user_id, school_id, role) DO UPDATE SET is_active = TRUE;

  FOR v_class IN
    SELECT DISTINCT ta.class_id FROM teaching_assignments ta
    WHERE ta.teacher_id = v_teacher.id
  LOOP
    INSERT INTO conversation_members(conversation_id, user_id, role, can_send)
    SELECT c.id, p_auth_user_id, 'teacher', TRUE
    FROM conversations c
      JOIN conversation_members cm ON cm.conversation_id = c.id AND cm.role = 'student'
      JOIN students s ON s.user_id = cm.user_id
      JOIN class_enrollments ce ON ce.student_id = s.id AND ce.class_id = v_class.class_id AND ce.unenrolled_at IS NULL
    WHERE c.school_id = p_school_id
      AND c.type = 'student_support'
      AND c.class_id = v_class.class_id
    ON CONFLICT (conversation_id, user_id) DO NOTHING;
  END LOOP;

  RETURN jsonb_build_object('success', TRUE, 'teacher_id', v_teacher.id);
END;
$$;
