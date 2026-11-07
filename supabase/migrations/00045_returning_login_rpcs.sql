-- Migration 00044 — Returning user login RPCs
-- Handles sign-in with ID + password for returning students/teachers.
-- Creates anonymous session link, updates roster, profile, and membership.

-- ── 1. Returning student login ──
CREATE OR REPLACE FUNCTION public.returning_student_login(
  p_student_id_no TEXT,
  p_password TEXT,
  p_auth_user_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_student students%ROWTYPE;
  v_school_id UUID;
BEGIN
  IF p_auth_user_id IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO v_student FROM students
  WHERE student_id_no = p_student_id_no AND is_active = TRUE
  LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'student_not_found');
  END IF;

  -- Verify password
  IF v_student.app_password IS NULL OR v_student.app_password != p_password THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_password');
  END IF;

  v_school_id := v_student.school_id;

  -- Link auth user to student record
  UPDATE students
  SET user_id = p_auth_user_id, updated_at = NOW()
  WHERE id = v_student.id;

  -- Create/update user profile
  INSERT INTO user_profiles(id, display_name, is_active)
  VALUES (p_auth_user_id, v_student.first_name || ' ' || v_student.last_name, TRUE)
  ON CONFLICT (id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    is_active = TRUE,
    updated_at = NOW();

  -- Create/update school membership
  INSERT INTO school_memberships(user_id, school_id, role, is_active, joined_at)
  VALUES (p_auth_user_id, v_school_id, 'student', TRUE, NOW())
  ON CONFLICT (user_id, school_id, role) DO UPDATE SET
    is_active = TRUE,
    joined_at = NOW();

  RETURN jsonb_build_object(
    'success', TRUE,
    'student_id', v_student.id,
    'school_id', v_school_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.returning_student_login(TEXT, TEXT, UUID) TO authenticated;

-- ── 2. Returning teacher login ──
CREATE OR REPLACE FUNCTION public.returning_teacher_login(
  p_staff_id_no TEXT,
  p_password TEXT,
  p_auth_user_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_teacher teachers%ROWTYPE;
  v_school_id UUID;
BEGIN
  IF p_auth_user_id IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO v_teacher FROM teachers
  WHERE staff_id_no = p_staff_id_no AND is_active = TRUE
  LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'teacher_not_found');
  END IF;

  -- Verify password
  IF v_teacher.app_password IS NULL OR v_teacher.app_password != p_password THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_password');
  END IF;

  v_school_id := v_teacher.school_id;

  -- Link auth user to teacher record
  UPDATE teachers
  SET user_id = p_auth_user_id, updated_at = NOW()
  WHERE id = v_teacher.id;

  -- Create/update user profile
  INSERT INTO user_profiles(id, display_name, phone, is_active)
  VALUES (p_auth_user_id, v_teacher.first_name || ' ' || v_teacher.last_name, v_teacher.phone, TRUE)
  ON CONFLICT (id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    phone = EXCLUDED.phone,
    is_active = TRUE,
    updated_at = NOW();

  -- Create/update school membership
  INSERT INTO school_memberships(user_id, school_id, role, is_active, joined_at)
  VALUES (
    p_auth_user_id,
    v_school_id,
    (CASE WHEN v_teacher.is_leadership THEN 'head_teacher' ELSE 'teacher' END)::school_role,
    TRUE,
    NOW()
  )
  ON CONFLICT (user_id, school_id, role) DO UPDATE SET
    is_active = TRUE,
    joined_at = NOW();

  RETURN jsonb_build_object(
    'success', TRUE,
    'teacher_id', v_teacher.id,
    'school_id', v_school_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.returning_teacher_login(TEXT, TEXT, UUID) TO authenticated;