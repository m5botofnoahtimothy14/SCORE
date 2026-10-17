-- ============================================================
-- Migration 00010 — Fix activation profile ordering
-- students.user_id and teachers.user_id reference user_profiles(id),
-- but both activation RPCs performed the UPDATE before inserting the
-- profile row, so every activation failed with FK 23503
-- (user_profiles key not present). Create the profile first.
-- ============================================================

CREATE OR REPLACE FUNCTION activate_student(
  p_school_id       UUID,
  p_student_id_no   TEXT,
  p_activation_code TEXT,
  p_auth_user_id    UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_student         students%ROWTYPE;
  v_credential      student_activation_credentials%ROWTYPE;
  v_class_id        UUID;
  v_match           BOOLEAN := FALSE;
BEGIN
  SELECT * INTO v_student
  FROM students
  WHERE school_id = p_school_id
    AND student_id_no = p_student_id_no
    AND is_active = TRUE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_credentials');
  END IF;

  SELECT * INTO v_credential
  FROM student_activation_credentials
  WHERE student_id = v_student.id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'no_activation_code');
  END IF;

  IF v_credential.used_at IS NOT NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'code_already_used');
  END IF;

  IF v_credential.expires_at < NOW() THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'code_expired');
  END IF;

  IF left(v_credential.code, 3) = '$2a' OR left(v_credential.code, 3) = '$2b' THEN
    v_match := (v_credential.code = crypt(p_activation_code, v_credential.code));
  ELSE
    v_match := (v_credential.code = encode(digest(p_activation_code, 'sha256'), 'hex'));
  END IF;

  IF NOT v_match THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_credentials');
  END IF;

  -- 1. Create the profile FIRST (students.user_id FK -> user_profiles.id).
  INSERT INTO user_profiles(id, display_name, is_active)
  VALUES (p_auth_user_id, v_student.first_name || ' ' || v_student.last_name, TRUE)
  ON CONFLICT (id) DO NOTHING;

  UPDATE student_activation_credentials
  SET used_at = NOW()
  WHERE id = v_credential.id;

  -- 2. Now safe to link the auth user to the student.
  UPDATE students SET user_id = p_auth_user_id, updated_at = NOW()
  WHERE id = v_student.id;

  INSERT INTO school_memberships(user_id, school_id, role, is_active)
  VALUES (p_auth_user_id, p_school_id, 'student', TRUE)
  ON CONFLICT (user_id, school_id, role) DO UPDATE SET is_active = TRUE;

  SELECT ce.class_id INTO v_class_id
  FROM class_enrollments ce
  WHERE ce.student_id = v_student.id
    AND ce.unenrolled_at IS NULL
  LIMIT 1;

  IF v_class_id IS NOT NULL THEN
    PERFORM create_student_support_conversation(v_student.id, v_class_id, p_school_id, p_auth_user_id);
  END IF;

  RETURN jsonb_build_object(
    'success', TRUE,
    'student_id', v_student.id,
    'class_id', v_class_id
  );
END;
$$;

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

  -- 1. Create the profile FIRST (teachers.user_id FK -> user_profiles.id).
  INSERT INTO user_profiles(id, display_name, phone, is_active)
  VALUES (p_auth_user_id, v_teacher.first_name || ' ' || v_teacher.last_name, p_phone, TRUE)
  ON CONFLICT (id) DO UPDATE SET phone = p_phone, display_name = EXCLUDED.display_name;

  -- 2. Now safe to link the auth user to the teacher.
  UPDATE teachers SET user_id = p_auth_user_id, updated_at = NOW()
  WHERE id = v_teacher.id;

  INSERT INTO school_memberships(user_id, school_id, role, is_active)
  VALUES (
    p_auth_user_id,
    p_school_id,
    CASE WHEN v_teacher.is_leadership THEN 'head_teacher' ELSE 'teacher' END,
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
