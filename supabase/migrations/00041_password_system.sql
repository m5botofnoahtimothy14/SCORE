-- Migration 00041 — Add app password support for students and teachers
-- Allows students/teachers to create a password after first activation.
-- Admin can view and reset passwords from the DMS website.

-- ── 1. Add app_password column to students ──
ALTER TABLE public.students
  ADD COLUMN IF NOT EXISTS app_password TEXT,
  ADD COLUMN IF NOT EXISTS password_set_at TIMESTAMPTZ;

-- ── 2. Add app_password column to teachers ──
ALTER TABLE public.teachers
  ADD COLUMN IF NOT EXISTS app_password TEXT,
  ADD COLUMN IF NOT EXISTS password_set_at TIMESTAMPTZ;

-- ── 3. RPC: set_student_password ──
CREATE OR REPLACE FUNCTION public.set_student_password(
  p_student_id UUID,
  p_password TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_student students%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO v_student FROM students WHERE id = p_student_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'student_not_found');
  END IF;

  IF v_student.user_id IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authorized');
  END IF;

  IF p_password IS NULL OR length(p_password) < 4 THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'password_too_short');
  END IF;

  UPDATE students
  SET app_password = p_password,
      password_set_at = NOW(),
      updated_at = NOW()
  WHERE id = p_student_id;

  -- Also update Supabase auth password
  -- (done client-side via supabase.auth.updateUser)

  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome)
  VALUES (v_student.school_id, auth.uid(), 'student.password_set', 'student', p_student_id::TEXT, 'success');

  RETURN jsonb_build_object('success', TRUE, 'student_id', p_student_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_student_password(UUID, TEXT) TO authenticated;

-- ── 4. RPC: set_teacher_password ──
CREATE OR REPLACE FUNCTION public.set_teacher_password(
  p_teacher_id UUID,
  p_password TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_teacher teachers%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO v_teacher FROM teachers WHERE id = p_teacher_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'teacher_not_found');
  END IF;

  IF v_teacher.user_id IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authorized');
  END IF;

  IF p_password IS NULL OR length(p_password) < 4 THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'password_too_short');
  END IF;

  UPDATE teachers
  SET app_password = p_password,
      password_set_at = NOW(),
      updated_at = NOW()
  WHERE id = p_teacher_id;

  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome)
  VALUES (v_teacher.school_id, auth.uid(), 'teacher.password_set', 'teacher', p_teacher_id::TEXT, 'success');

  RETURN jsonb_build_object('success', TRUE, 'teacher_id', p_teacher_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_teacher_password(UUID, TEXT) TO authenticated;

-- ── 5. RPC: admin_reset_password ──
CREATE OR REPLACE FUNCTION public.admin_reset_password(
  p_user_type TEXT,  -- 'student' or 'teacher'
  p_user_id UUID,
  p_new_password TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_school_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authenticated');
  END IF;

  IF p_user_type = 'student' THEN
    SELECT school_id INTO v_school_id FROM students WHERE id = p_user_id;
    IF v_school_id IS NULL THEN
      RETURN jsonb_build_object('success', FALSE, 'error', 'student_not_found');
    END IF;
    IF NOT public.tc_is_school_admin(v_school_id) THEN
      RETURN jsonb_build_object('success', FALSE, 'error', 'forbidden');
    END IF;
    UPDATE students
    SET app_password = p_new_password,
        password_set_at = NOW(),
        updated_at = NOW()
    WHERE id = p_user_id;
  ELSIF p_user_type = 'teacher' THEN
    SELECT school_id INTO v_school_id FROM teachers WHERE id = p_user_id;
    IF v_school_id IS NULL THEN
      RETURN jsonb_build_object('success', FALSE, 'error', 'teacher_not_found');
    END IF;
    IF NOT public.tc_is_school_admin(v_school_id) THEN
      RETURN jsonb_build_object('success', FALSE, 'error', 'forbidden');
    END IF;
    UPDATE teachers
    SET app_password = p_new_password,
        password_set_at = NOW(),
        updated_at = NOW()
    WHERE id = p_user_id;
  ELSE
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_user_type');
  END IF;

  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome, metadata)
  VALUES (v_school_id, auth.uid(), 'password.reset', p_user_type, p_user_id::TEXT, 'success',
    jsonb_build_object('reset_by', auth.uid()));

  RETURN jsonb_build_object('success', TRUE);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_reset_password(TEXT, UUID, TEXT) TO authenticated;

-- ── 6. RPC: get_student_password (admin only) ──
CREATE OR REPLACE FUNCTION public.get_student_password(p_student_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_school_id UUID;
  v_password TEXT;
BEGIN
  SELECT school_id, app_password INTO v_school_id, v_password
  FROM students WHERE id = p_student_id;
  IF v_school_id IS NULL THEN
    RETURN NULL;
  END IF;
  IF NOT public.tc_is_school_admin(v_school_id) THEN
    RETURN NULL;
  END IF;
  RETURN v_password;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_student_password(UUID) TO authenticated;

-- ── 7. RPC: get_teacher_password (admin only) ──
CREATE OR REPLACE FUNCTION public.get_teacher_password(p_teacher_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_school_id UUID;
  v_password TEXT;
BEGIN
  SELECT school_id, app_password INTO v_school_id, v_password
  FROM teachers WHERE id = p_teacher_id;
  IF v_school_id IS NULL THEN
    RETURN NULL;
  END IF;
  IF NOT public.tc_is_school_admin(v_school_id) THEN
    RETURN NULL;
  END IF;
  RETURN v_password;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_teacher_password(UUID) TO authenticated;