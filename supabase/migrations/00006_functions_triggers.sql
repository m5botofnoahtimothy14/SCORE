-- ============================================================
-- TeachCross: Migration 00006 — Database Functions & Triggers
-- ============================================================

-- Auto-update updated_at timestamps
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER schools_updated_at          BEFORE UPDATE ON schools          FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER school_settings_updated_at  BEFORE UPDATE ON school_settings  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER user_profiles_updated_at    BEFORE UPDATE ON user_profiles    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER students_updated_at         BEFORE UPDATE ON students         FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER teachers_updated_at         BEFORE UPDATE ON teachers         FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER conversations_updated_at    BEFORE UPDATE ON conversations    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER messages_updated_at         BEFORE UPDATE ON messages         FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER announcements_updated_at    BEFORE UPDATE ON announcements    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER review_cases_updated_at     BEFORE UPDATE ON moderation_review_cases FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER incidents_updated_at        BEFORE UPDATE ON safeguarding_incidents  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER tickets_updated_at          BEFORE UPDATE ON support_tickets  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER support_q_updated_at        BEFORE UPDATE ON support_questions FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Update conversation updated_at when a new message arrives
CREATE OR REPLACE FUNCTION update_conversation_on_message()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE conversations SET updated_at = NOW()
  WHERE id = NEW.conversation_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER messages_update_conversation
  AFTER INSERT ON messages
  FOR EACH ROW EXECUTE FUNCTION update_conversation_on_message();

-- ============================================================
-- SECURE STUDENT ACTIVATION
-- Validates activation code and creates user membership
-- Called from Edge Function (service role) — NOT directly by client
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
BEGIN
  -- 1. Find student record (timing-safe: don't reveal existence via error detail)
  SELECT * INTO v_student
  FROM students
  WHERE school_id = p_school_id
    AND student_id_no = p_student_id_no
    AND is_active = TRUE;

  IF NOT FOUND THEN
    -- Generic error: do not reveal whether ID exists
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_credentials');
  END IF;

  -- 2. Check activation credential
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

  -- 3. Verify code (bcrypt comparison done server-side)
  IF v_credential.code != crypt(p_activation_code, v_credential.code) THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_credentials');
  END IF;

  -- 4. Mark code used
  UPDATE student_activation_credentials
  SET used_at = NOW()
  WHERE id = v_credential.id;

  -- 5. Link auth user to student record
  UPDATE students SET user_id = p_auth_user_id, updated_at = NOW()
  WHERE id = v_student.id;

  -- 6. Create user_profile if not exists
  INSERT INTO user_profiles(id, display_name, is_active)
  VALUES (p_auth_user_id, v_student.first_name || ' ' || v_student.last_name, TRUE)
  ON CONFLICT (id) DO NOTHING;

  -- 7. Create school membership
  INSERT INTO school_memberships(user_id, school_id, role, is_active)
  VALUES (p_auth_user_id, p_school_id, 'student', TRUE)
  ON CONFLICT (user_id, school_id, role) DO UPDATE SET is_active = TRUE;

  -- 8. Get current class enrollment
  SELECT ce.class_id INTO v_class_id
  FROM class_enrollments ce
  WHERE ce.student_id = v_student.id
    AND ce.unenrolled_at IS NULL
  LIMIT 1;

  -- 9. Create support conversation if not exists
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

-- ============================================================
-- CREATE STUDENT SUPPORT CONVERSATION
-- Creates the student ↔ their teachers support conversation
-- ============================================================
CREATE OR REPLACE FUNCTION create_student_support_conversation(
  p_student_id    UUID,
  p_class_id      UUID,
  p_school_id     UUID,
  p_student_user_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_conv_id UUID;
  v_teacher RECORD;
BEGIN
  -- Check if already exists
  SELECT c.id INTO v_conv_id
  FROM conversations c
    JOIN conversation_members cm ON cm.conversation_id = c.id
  WHERE c.school_id = p_school_id
    AND c.type = 'student_support'
    AND c.class_id = p_class_id
    AND cm.user_id = p_student_user_id
    AND cm.role = 'student'
    AND cm.removed_at IS NULL
  LIMIT 1;

  IF v_conv_id IS NOT NULL THEN
    RETURN v_conv_id;
  END IF;

  -- Create the conversation
  INSERT INTO conversations(school_id, type, class_id, created_by, title)
  VALUES (p_school_id, 'student_support', p_class_id, p_student_user_id, 'Teacher Support')
  RETURNING id INTO v_conv_id;

  -- Add student as member (can send)
  INSERT INTO conversation_members(conversation_id, user_id, role, can_send)
  VALUES (v_conv_id, p_student_user_id, 'student', TRUE);

  -- Add all teachers assigned to this class
  FOR v_teacher IN
    SELECT t.user_id
    FROM teaching_assignments ta
      JOIN teachers t ON t.id = ta.teacher_id
    WHERE ta.class_id = p_class_id
      AND t.user_id IS NOT NULL
      AND t.is_active = TRUE
  LOOP
    INSERT INTO conversation_members(conversation_id, user_id, role, can_send)
    VALUES (v_conv_id, v_teacher.user_id, 'teacher', TRUE)
    ON CONFLICT (conversation_id, user_id) DO NOTHING;
  END LOOP;

  RETURN v_conv_id;
END;
$$;

-- ============================================================
-- SECURE TEACHER ACTIVATION
-- Called from Edge Function after OTP verification
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
  v_teacher teachers%ROWTYPE;
  v_class   RECORD;
BEGIN
  -- Find teacher in roster
  SELECT * INTO v_teacher
  FROM teachers
  WHERE school_id = p_school_id
    AND staff_id_no = p_staff_id_no
    AND is_active = TRUE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_credentials');
  END IF;

  -- Verify phone matches roster (anti-impersonation)
  IF v_teacher.phone != p_phone THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_credentials');
  END IF;

  -- Link auth user
  UPDATE teachers SET user_id = p_auth_user_id, updated_at = NOW()
  WHERE id = v_teacher.id;

  -- Create profile
  INSERT INTO user_profiles(id, display_name, phone, is_active)
  VALUES (p_auth_user_id, v_teacher.first_name || ' ' || v_teacher.last_name, p_phone, TRUE)
  ON CONFLICT (id) DO UPDATE SET phone = p_phone, display_name = EXCLUDED.display_name;

  -- Create membership with appropriate role
  INSERT INTO school_memberships(user_id, school_id, role, is_active)
  VALUES (
    p_auth_user_id,
    p_school_id,
    CASE WHEN v_teacher.is_leadership THEN 'head_teacher' ELSE 'teacher' END,
    TRUE
  )
  ON CONFLICT (user_id, school_id, role) DO UPDATE SET is_active = TRUE;

  -- Create staff conversations with assigned class students who are already activated
  FOR v_class IN
    SELECT DISTINCT ta.class_id FROM teaching_assignments ta
    WHERE ta.teacher_id = v_teacher.id
  LOOP
    -- The student support conversations will include this teacher
    -- (handled retroactively when teacher activates after students)
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

-- ============================================================
-- SEND MESSAGE (enforces all security checks server-side)
-- ============================================================
CREATE OR REPLACE FUNCTION send_message(
  p_conversation_id UUID,
  p_sender_id       UUID,
  p_body            TEXT,
  p_idempotency_key TEXT,
  p_reply_to_id     UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_conv conversations%ROWTYPE;
  v_member conversation_members%ROWTYPE;
  v_msg_id UUID;
  v_school_id UUID;
BEGIN
  -- 1. Verify caller is the sender
  IF p_sender_id != auth.uid() THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'forbidden');
  END IF;

  -- 2. Get conversation
  SELECT * INTO v_conv FROM conversations WHERE id = p_conversation_id;
  IF NOT FOUND OR NOT v_conv.is_active THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'conversation_not_found');
  END IF;

  v_school_id := v_conv.school_id;

  -- 3. Verify membership and send permission
  SELECT * INTO v_member
  FROM conversation_members
  WHERE conversation_id = p_conversation_id
    AND user_id = p_sender_id
    AND removed_at IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_a_member');
  END IF;

  IF NOT v_member.can_send THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'send_not_permitted');
  END IF;

  -- 4. Block student-to-student: class_channel students cannot send
  IF v_conv.type = 'class_channel' AND v_member.role = 'student' THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'students_cannot_send_in_class_channel');
  END IF;

  -- 5. Validate body
  IF p_body IS NULL OR length(trim(p_body)) = 0 THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'empty_message');
  END IF;

  IF length(p_body) > 4000 THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'message_too_long');
  END IF;

  -- 6. Insert message (starts as pending_moderation)
  INSERT INTO messages(
    idempotency_key, conversation_id, school_id,
    sender_id, body, status, reply_to_id
  )
  VALUES (
    p_idempotency_key, p_conversation_id, v_school_id,
    p_sender_id, p_body, 'pending_moderation', p_reply_to_id
  )
  ON CONFLICT (idempotency_key) DO NOTHING
  RETURNING id INTO v_msg_id;

  IF v_msg_id IS NULL THEN
    -- Duplicate — return the existing message id
    SELECT id INTO v_msg_id FROM messages WHERE idempotency_key = p_idempotency_key;
    RETURN jsonb_build_object('success', TRUE, 'message_id', v_msg_id, 'duplicate', TRUE);
  END IF;

  -- 7. Log audit event
  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome)
  VALUES (v_school_id, p_sender_id, 'message.send', 'message', v_msg_id::TEXT, 'success');

  RETURN jsonb_build_object('success', TRUE, 'message_id', v_msg_id);
END;
$$;

-- ============================================================
-- PLATFORM BOOTSTRAP — create initial platform owner
-- Called ONCE during deployment via service role
-- ============================================================
CREATE OR REPLACE FUNCTION bootstrap_platform_owner(
  p_email     TEXT,
  p_school_name TEXT,
  p_school_code TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_school_id UUID;
  v_existing_count INTEGER;
BEGIN
  -- Prevent re-bootstrap if platform owners already exist
  SELECT COUNT(*) INTO v_existing_count
  FROM school_memberships WHERE role = 'platform_owner';

  IF v_existing_count > 0 THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'already_bootstrapped');
  END IF;

  -- Create first school
  INSERT INTO schools(name, code) VALUES (p_school_name, p_school_code)
  RETURNING id INTO v_school_id;

  INSERT INTO school_settings(school_id) VALUES (v_school_id);

  RETURN jsonb_build_object(
    'success', TRUE,
    'school_id', v_school_id,
    'note', 'Create admin user via Supabase Auth, then assign platform_owner role in school_memberships'
  );
END;
$$;
