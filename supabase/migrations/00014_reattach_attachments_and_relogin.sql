-- ============================================================
-- Migration 00014 — Attachment linking + returning-student re-login
--
-- 1. send_message() accepts an optional attachment id so an image/audio/
--    document upload can be linked to the message that carries it. The
--    attachment row is created first (status = pending_scan) and is only
--    linked here, inside the SECURITY DEFINER function, because there is
--    no client UPDATE policy on attachments.
--    Body may be empty when an attachment is supplied (image-only messages).
--
-- 2. activate_student() supports returning students. A student who already
--    activated once can sign in again from a new device/session: the code
--    still has to match, but used_at/expiry no longer block a re-login for
--    the same student. Prior conversation memberships are handed over to the
--    new auth user so message history is preserved, and the previous session's
--    access in this school is revoked.
-- ============================================================

-- ── 1. send_message with optional attachment ───────────────
-- Adding a parameter creates an overload; drop the previous 5-arg version
-- so callers (PostgREST) resolve to a single function.
DROP FUNCTION IF EXISTS send_message(UUID, UUID, TEXT, TEXT, UUID);

CREATE OR REPLACE FUNCTION send_message(
  p_conversation_id UUID,
  p_sender_id       UUID,
  p_body            TEXT,
  p_idempotency_key TEXT,
  p_reply_to_id     UUID DEFAULT NULL,
  p_attachment_id   UUID DEFAULT NULL
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

  -- 5. Validate body (an attachment alone is allowed)
  IF p_attachment_id IS NULL AND (p_body IS NULL OR length(trim(p_body)) = 0) THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'empty_message');
  END IF;

  IF p_body IS NOT NULL AND length(p_body) > 4000 THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'message_too_long');
  END IF;

  -- 6. If an attachment is supplied, it must belong to the sender in this school
  IF p_attachment_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM attachments
      WHERE id = p_attachment_id
        AND uploader_id = p_sender_id
        AND school_id = v_school_id
    ) THEN
      RETURN jsonb_build_object('success', FALSE, 'error', 'attachment_not_found');
    END IF;
  END IF;

  -- 7. Insert message (starts as pending_moderation)
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
    -- Link the attachment to the existing (duplicate) message too.
    IF p_attachment_id IS NOT NULL THEN
      UPDATE attachments SET message_id = v_msg_id
      WHERE id = p_attachment_id AND uploader_id = p_sender_id AND message_id IS NULL;
    END IF;
    RETURN jsonb_build_object('success', TRUE, 'message_id', v_msg_id, 'duplicate', TRUE);
  END IF;

  -- 8. Link the attachment to the new message
  IF p_attachment_id IS NOT NULL THEN
    UPDATE attachments
    SET message_id = v_msg_id
    WHERE id = p_attachment_id
      AND uploader_id = p_sender_id
      AND message_id IS NULL;
  END IF;

  -- 9. Log audit event
  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome)
  VALUES (v_school_id, p_sender_id, 'message.send', 'message', v_msg_id::TEXT, 'success');

  RETURN jsonb_build_object('success', TRUE, 'message_id', v_msg_id);
END;
$$;

-- ── 2. activate_student with returning-student re-login ────
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
  v_returning       BOOLEAN := FALSE;
  v_prev_user       UUID;
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

  -- Verify the code (bcrypt or sha256)
  IF left(v_credential.code, 3) = '$2a' OR left(v_credential.code, 3) = '$2b' THEN
    v_match := (v_credential.code = crypt(p_activation_code, v_credential.code));
  ELSE
    v_match := (v_credential.code = encode(digest(p_activation_code, 'sha256'), 'hex'));
  END IF;

  IF NOT v_match THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_credentials');
  END IF;

  -- A credential that has been used before marks a returning student. For a
  -- first activation the code must still be within its validity window; for a
  -- returning student the code is their lasting credential (rotation happens
  -- via issue_student_code, which clears used_at and resets expiry).
  v_returning := v_credential.used_at IS NOT NULL;

  IF NOT v_returning AND v_credential.expires_at < NOW() THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'code_expired');
  END IF;

  -- 1. Create/refresh the profile FIRST (students.user_id FK -> user_profiles.id).
  INSERT INTO user_profiles(id, display_name, is_active)
  VALUES (p_auth_user_id, v_student.first_name || ' ' || v_student.last_name, TRUE)
  ON CONFLICT (id) DO UPDATE SET
    display_name = v_student.first_name || ' ' || v_student.last_name,
    is_active = TRUE;

  -- 2. First activation consumes the code.
  IF NOT v_returning THEN
    UPDATE student_activation_credentials
    SET used_at = NOW()
    WHERE id = v_credential.id;
  END IF;

  v_prev_user := v_student.user_id;

  -- 3. Returning on a different session: hand over conversation memberships so
  --    history follows the student, then revoke the previous session's access.
  IF v_returning AND v_prev_user IS NOT NULL AND v_prev_user <> p_auth_user_id THEN
    UPDATE conversation_members cm
    SET user_id = p_auth_user_id
    WHERE cm.user_id = v_prev_user
      AND cm.conversation_id IN (SELECT id FROM conversations WHERE school_id = p_school_id)
      AND NOT EXISTS (
        SELECT 1 FROM conversation_members cm2
        WHERE cm2.conversation_id = cm.conversation_id
          AND cm2.user_id = p_auth_user_id
      );

    UPDATE conversation_members
    SET removed_at = NOW()
    WHERE user_id = v_prev_user
      AND removed_at IS NULL
      AND conversation_id IN (SELECT id FROM conversations WHERE school_id = p_school_id);

    UPDATE school_memberships
    SET is_active = FALSE, updated_at = NOW()
    WHERE user_id = v_prev_user
      AND school_id = p_school_id
      AND user_id <> p_auth_user_id;
  END IF;

  -- 4. Link the auth user to the student.
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
    'class_id', v_class_id,
    'returning', v_returning
  );
END;
$$;
