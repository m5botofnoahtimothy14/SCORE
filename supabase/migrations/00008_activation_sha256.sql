-- ============================================================
-- Migration 00008 — SHA-256 activation codes (server-issued)
-- Allows the DMS API to issue codes without pgcrypto round-trips.
-- activate_student() now accepts BOTH legacy crypt hashes ($2…)
-- and SHA-256 hex (64 lowercase hex chars), compared server-side.
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

  -- Accept crypt hashes (legacy, issued via issue_student_code) or
  -- SHA-256 hex (issued via DMS API). Comparison stays server-side.
  IF left(v_credential.code, 3) = '$2a' OR left(v_credential.code, 3) = '$2b' THEN
    v_match := (v_credential.code = crypt(p_activation_code, v_credential.code));
  ELSE
    v_match := (v_credential.code = encode(digest(p_activation_code, 'sha256'), 'hex'));
  END IF;

  IF NOT v_match THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_credentials');
  END IF;

  UPDATE student_activation_credentials
  SET used_at = NOW()
  WHERE id = v_credential.id;

  UPDATE students SET user_id = p_auth_user_id, updated_at = NOW()
  WHERE id = v_student.id;

  INSERT INTO user_profiles(id, display_name, is_active)
  VALUES (p_auth_user_id, v_student.first_name || ' ' || v_student.last_name, TRUE)
  ON CONFLICT (id) DO NOTHING;

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
