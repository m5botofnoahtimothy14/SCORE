-- ============================================================
-- Migration 00031 — activation credential security hardening
-- All credential verification and account linking run atomically
-- through service-role-only RPCs. Client roles cannot bypass codes.
-- ============================================================

-- Track failed attempts and temporary locks for both activation flows.
ALTER TABLE public.student_activation_credentials
  ADD COLUMN IF NOT EXISTS failed_attempts INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS locked_until TIMESTAMPTZ;

ALTER TABLE public.teacher_activation_credentials
  ADD COLUMN IF NOT EXISTS code_salt TEXT,
  ADD COLUMN IF NOT EXISTS failed_attempts INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS locked_until TIMESTAMPTZ;

-- Invalidate any legacy teacher codes that do not have the new salted format.
UPDATE public.teacher_activation_credentials
SET used_at = COALESCE(used_at, NOW())
WHERE code_salt IS NULL;

COMMENT ON COLUMN public.teacher_activation_credentials.code IS
  'SHA-256 hash of the one-time code plus code_salt. Never store a plaintext code.';

-- Activation hashes are never readable through the client API.
DROP POLICY IF EXISTS student_activation_credentials_admin
  ON public.student_activation_credentials;
DROP POLICY IF EXISTS teacher_activation_credentials_admin
  ON public.teacher_activation_credentials;
REVOKE ALL ON TABLE public.student_activation_credentials FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.teacher_activation_credentials FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.student_activation_credentials TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.teacher_activation_credentials TO service_role;

-- The old student RPC trusted any authenticated caller and did not verify the code.
REVOKE ALL ON FUNCTION public.activate_student(TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.activate_teacher(TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;

-- Atomically verify, consume and activate a student credential.
CREATE OR REPLACE FUNCTION public.activate_student_verified(
  p_student_id_no TEXT,
  p_activation_code TEXT,
  p_user_id UUID
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_student students%ROWTYPE;
  v_credential student_activation_credentials%ROWTYPE;
  v_class_id UUID;
  v_conversation_id UUID;
  v_submitted_hash TEXT;
BEGIN
  IF auth.role() <> 'service_role' OR p_user_id IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'forbidden');
  END IF;

  IF p_student_id_no IS NULL OR length(trim(p_student_id_no)) = 0
     OR p_activation_code IS NULL OR length(trim(p_activation_code)) = 0 THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_credentials');
  END IF;

  SELECT * INTO v_student
  FROM students
  WHERE student_id_no = trim(p_student_id_no) AND is_active = TRUE
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'student_not_found');
  END IF;

  IF v_student.user_id IS NOT NULL THEN
    IF v_student.user_id = p_user_id THEN
      SELECT ce.class_id INTO v_class_id
      FROM class_enrollments ce
      WHERE ce.student_id = v_student.id AND ce.unenrolled_at IS NULL
      ORDER BY ce.enrolled_at DESC
      LIMIT 1;
      RETURN jsonb_build_object(
        'success', TRUE, 'student_id', v_student.id,
        'class_id', v_class_id, 'school_id', v_student.school_id,
        'idempotent', TRUE
      );
    END IF;
    RETURN jsonb_build_object('success', FALSE, 'error', 'student_already_linked');
  END IF;

  SELECT * INTO v_credential
  FROM student_activation_credentials
  WHERE student_id = v_student.id AND used_at IS NULL
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND OR v_credential.expires_at <= NOW() THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_credentials');
  END IF;

  IF v_credential.locked_until IS NOT NULL AND v_credential.locked_until > NOW() THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'rate_limited');
  END IF;

  IF v_credential.code_hash IS NULL OR v_credential.code_salt IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_credentials');
  END IF;

  v_submitted_hash := encode(
    digest(trim(p_activation_code) || ':' || v_credential.code_salt, 'sha256'),
    'hex'
  );

  IF v_submitted_hash <> v_credential.code_hash THEN
    UPDATE student_activation_credentials
    SET failed_attempts = failed_attempts + 1,
        locked_until = CASE
          WHEN failed_attempts + 1 >= 5 THEN NOW() + INTERVAL '15 minutes'
          ELSE locked_until
        END
    WHERE id = v_credential.id;

    RETURN jsonb_build_object(
      'success', FALSE,
      'error', CASE WHEN v_credential.failed_attempts + 1 >= 5
        THEN 'rate_limited' ELSE 'invalid_credentials' END
    );
  END IF;

  UPDATE student_activation_credentials
  SET used_at = NOW(), failed_attempts = 0, locked_until = NULL
  WHERE id = v_credential.id AND used_at IS NULL;

  UPDATE students
  SET user_id = p_user_id, updated_at = NOW()
  WHERE id = v_student.id AND user_id IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'student_already_linked');
  END IF;

  INSERT INTO user_profiles(id, display_name, is_active, created_at, updated_at)
  VALUES (
    p_user_id,
    trim(COALESCE(v_student.first_name, '') || ' ' || COALESCE(v_student.last_name, '')),
    TRUE, NOW(), NOW()
  )
  ON CONFLICT (id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    is_active = TRUE,
    updated_at = NOW();

  INSERT INTO school_memberships(user_id, school_id, role, is_active, joined_at)
  VALUES (p_user_id, v_student.school_id, 'student', TRUE, NOW())
  ON CONFLICT (user_id, school_id, role) DO UPDATE SET
    is_active = TRUE, joined_at = NOW();

  INSERT INTO conversations(school_id, type, title, created_by, is_active, created_at, updated_at)
  VALUES (
    v_student.school_id, 'student_support',
    'Support: ' || COALESCE(v_student.first_name, 'Student'),
    p_user_id, TRUE, NOW(), NOW()
  )
  RETURNING id INTO v_conversation_id;

  INSERT INTO conversation_members(conversation_id, user_id, role, can_send)
  VALUES (v_conversation_id, p_user_id, 'student', TRUE);

  SELECT ce.class_id INTO v_class_id
  FROM class_enrollments ce
  WHERE ce.student_id = v_student.id AND ce.unenrolled_at IS NULL
  ORDER BY ce.enrolled_at DESC
  LIMIT 1;

  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome, metadata)
  VALUES (
    v_student.school_id, p_user_id, 'student.activate', 'student',
    v_student.id::TEXT, 'success',
    jsonb_build_object('student_id_no', p_student_id_no)
  );

  RETURN jsonb_build_object(
    'success', TRUE, 'student_id', v_student.id,
    'class_id', v_class_id, 'school_id', v_student.school_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.activate_student_verified(TEXT, TEXT, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.activate_student_verified(TEXT, TEXT, UUID) TO service_role;

-- Atomically verify, consume and activate a teacher credential.
CREATE OR REPLACE FUNCTION public.activate_teacher_verified(
  p_staff_id_no TEXT,
  p_activation_code TEXT,
  p_user_id UUID
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_teacher teachers%ROWTYPE;
  v_credential teacher_activation_credentials%ROWTYPE;
  v_submitted_hash TEXT;
BEGIN
  IF auth.role() <> 'service_role' OR p_user_id IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'forbidden');
  END IF;

  IF p_staff_id_no IS NULL OR length(trim(p_staff_id_no)) = 0
     OR p_activation_code IS NULL OR length(trim(p_activation_code)) = 0 THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_credentials');
  END IF;

  SELECT * INTO v_teacher
  FROM teachers
  WHERE staff_id_no = trim(p_staff_id_no) AND is_active = TRUE
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'teacher_not_found');
  END IF;

  IF v_teacher.user_id IS NOT NULL THEN
    IF v_teacher.user_id = p_user_id THEN
      RETURN jsonb_build_object(
        'success', TRUE, 'teacher_id', v_teacher.id,
        'school_id', v_teacher.school_id, 'idempotent', TRUE
      );
    END IF;
    RETURN jsonb_build_object('success', FALSE, 'error', 'teacher_already_linked');
  END IF;

  SELECT * INTO v_credential
  FROM teacher_activation_credentials
  WHERE teacher_id = v_teacher.id AND school_id = v_teacher.school_id
    AND used_at IS NULL
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND OR v_credential.expires_at <= NOW() THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'no_activation_code');
  END IF;

  IF v_credential.locked_until IS NOT NULL AND v_credential.locked_until > NOW() THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'rate_limited');
  END IF;

  IF v_credential.code_salt IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'no_activation_code');
  END IF;

  v_submitted_hash := encode(
    digest(trim(p_activation_code) || ':' || v_credential.code_salt, 'sha256'),
    'hex'
  );

  IF v_submitted_hash <> v_credential.code THEN
    UPDATE teacher_activation_credentials
    SET failed_attempts = failed_attempts + 1,
        locked_until = CASE
          WHEN failed_attempts + 1 >= 5 THEN NOW() + INTERVAL '15 minutes'
          ELSE locked_until
        END
    WHERE id = v_credential.id;

    RETURN jsonb_build_object(
      'success', FALSE,
      'error', CASE WHEN v_credential.failed_attempts + 1 >= 5
        THEN 'rate_limited' ELSE 'invalid_code' END
    );
  END IF;

  UPDATE teacher_activation_credentials
  SET used_at = NOW(), failed_attempts = 0, locked_until = NULL
  WHERE id = v_credential.id AND used_at IS NULL;

  UPDATE teachers
  SET user_id = p_user_id, updated_at = NOW()
  WHERE id = v_teacher.id AND user_id IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'teacher_already_linked');
  END IF;

  INSERT INTO user_profiles(id, display_name, is_active, created_at, updated_at)
  VALUES (
    p_user_id,
    trim(COALESCE(v_teacher.first_name, '') || ' ' || COALESCE(v_teacher.last_name, '')),
    TRUE, NOW(), NOW()
  )
  ON CONFLICT (id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    is_active = TRUE,
    updated_at = NOW();

  INSERT INTO school_memberships(user_id, school_id, role, is_active, joined_at)
  VALUES (p_user_id, v_teacher.school_id, 'teacher', TRUE, NOW())
  ON CONFLICT (user_id, school_id, role) DO UPDATE SET
    is_active = TRUE, joined_at = NOW();

  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome)
  VALUES (
    v_teacher.school_id, p_user_id, 'teacher.activate', 'teacher',
    v_teacher.id::TEXT, 'success'
  );

  RETURN jsonb_build_object(
    'success', TRUE, 'teacher_id', v_teacher.id,
    'school_id', v_teacher.school_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.activate_teacher_verified(TEXT, TEXT, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.activate_teacher_verified(TEXT, TEXT, UUID) TO service_role;

-- School admins can issue/reissue a teacher code. Only a salted hash is stored.
CREATE OR REPLACE FUNCTION public.issue_teacher_activation_code(
  p_teacher_id UUID,
  p_plain_code TEXT,
  p_days_valid INTEGER DEFAULT 7
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_teacher teachers%ROWTYPE;
  v_salt TEXT;
  v_expires_at TIMESTAMPTZ;
BEGIN
  SELECT * INTO v_teacher FROM teachers
  WHERE id = p_teacher_id AND is_active = TRUE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'teacher_not_found');
  END IF;

  IF NOT public.tc_is_school_admin(v_teacher.school_id) THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'forbidden');
  END IF;

  IF p_plain_code IS NULL OR length(trim(p_plain_code)) < 8
     OR length(trim(p_plain_code)) > 128
     OR p_days_valid IS NULL OR p_days_valid < 1 OR p_days_valid > 30 THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_code');
  END IF;

  v_salt := encode(gen_random_bytes(16), 'hex');
  v_expires_at := NOW() + make_interval(days => p_days_valid);

  INSERT INTO teacher_activation_credentials(
    school_id, teacher_id, code, code_salt, expires_at,
    used_at, failed_attempts, locked_until, created_by, created_at
  )
  VALUES (
    v_teacher.school_id, v_teacher.id,
    encode(digest(trim(p_plain_code) || ':' || v_salt, 'sha256'), 'hex'),
    v_salt, v_expires_at, NULL, 0, NULL, auth.uid(), NOW()
  )
  ON CONFLICT (teacher_id) DO UPDATE SET
    school_id = EXCLUDED.school_id,
    code = EXCLUDED.code,
    code_salt = EXCLUDED.code_salt,
    expires_at = EXCLUDED.expires_at,
    used_at = NULL,
    failed_attempts = 0,
    locked_until = NULL,
    created_by = auth.uid(),
    created_at = NOW();

  RETURN jsonb_build_object(
    'success', TRUE, 'teacher_id', v_teacher.id,
    'expires_at', v_expires_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.issue_teacher_activation_code(UUID, TEXT, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.issue_teacher_activation_code(UUID, TEXT, INTEGER) TO authenticated;


-- Keep student code issuance aligned with the same salted hash format.
CREATE OR REPLACE FUNCTION public.issue_student_code(
  p_student_id UUID,
  p_plain_code TEXT,
  p_days_valid INTEGER DEFAULT 7
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_student students%ROWTYPE;
  v_code_hash TEXT;
  v_code_salt TEXT;
  v_expires_at TIMESTAMPTZ;
BEGIN
  SELECT * INTO v_student
  FROM students
  WHERE id = p_student_id AND is_active = TRUE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'student_not_found');
  END IF;

  IF NOT public.tc_is_school_admin(v_student.school_id) THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'forbidden');
  END IF;

  IF p_plain_code IS NULL OR length(trim(p_plain_code)) < 8
     OR length(trim(p_plain_code)) > 128
     OR p_days_valid IS NULL OR p_days_valid < 1 OR p_days_valid > 30 THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_code');
  END IF;

  v_code_salt := encode(gen_random_bytes(16), 'hex');
  v_code_hash := encode(digest(trim(p_plain_code) || ':' || v_code_salt, 'sha256'), 'hex');
  v_expires_at := NOW() + make_interval(days => p_days_valid);

  INSERT INTO student_activation_credentials(
    school_id, student_id, code_hash, code_salt, expires_at,
    created_by, created_at, failed_attempts, locked_until
  ) VALUES (
    v_student.school_id, p_student_id, v_code_hash, v_code_salt,
    v_expires_at, auth.uid(), NOW(), 0, NULL
  )
  ON CONFLICT (student_id) DO UPDATE SET
    school_id = EXCLUDED.school_id,
    code_hash = EXCLUDED.code_hash,
    code_salt = EXCLUDED.code_salt,
    expires_at = EXCLUDED.expires_at,
    used_at = NULL,
    created_by = EXCLUDED.created_by,
    created_at = NOW(),
    failed_attempts = 0,
    locked_until = NULL;

  RETURN jsonb_build_object(
    'success', TRUE, 'student_id', p_student_id,
    'expires_at', v_expires_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.issue_student_code(UUID, TEXT, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.issue_student_code(UUID, TEXT, INTEGER) TO authenticated;
