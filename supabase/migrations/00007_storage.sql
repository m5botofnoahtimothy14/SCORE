-- ============================================================
-- TeachCross: Migration 00007 — Storage, helpers, realtime
-- ============================================================

-- ── Private storage buckets (never public) ─────────────────
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  ('attachments', 'attachments', FALSE, 15728640, ARRAY[
    'image/jpeg','image/png','image/webp','image/gif',
    'audio/mpeg','audio/mp4','audio/ogg','audio/wav','audio/webm',
    'application/pdf'
  ]),
  ('avatars', 'avatars', FALSE, 2097152, ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT (id) DO NOTHING;

-- Storage access: only authenticated conversation members may read an
-- attachment object; path convention: <school_id>/<conversation_id>/<file>.
-- Owner (uploader path prefix is the school id, not user id) — so enforce
-- via DB membership checks in a helper function.
CREATE OR REPLACE FUNCTION public.tc_can_read_attachment(p_school_id UUID, p_conversation_id UUID)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM conversation_members cm
    JOIN conversations c ON c.id = cm.conversation_id
    WHERE cm.conversation_id = p_conversation_id
      AND cm.user_id = auth.uid()
      AND cm.removed_at IS NULL
      AND c.school_id = p_school_id
  ) OR public.tc_is_school_admin(p_school_id);
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Attachments bucket policies (objects carry school/conv ids in first segments)
CREATE POLICY attachments_read ON storage.objects FOR SELECT
  USING (
    bucket_id = 'attachments'
    AND public.tc_can_read_attachment(
      (string_to_array(name, '/'))[1]::UUID,
      (string_to_array(name, '/'))[2]::UUID
    )
  );

CREATE POLICY attachments_upload ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'attachments'
    AND auth.uid() IS NOT NULL
  );

CREATE POLICY attachments_delete_admin ON storage.objects FOR DELETE
  USING (
    bucket_id = 'attachments'
    AND public.tc_is_school_admin((string_to_array(name, '/'))[1]::UUID)
  );

CREATE POLICY avatars_own ON storage.objects FOR ALL
  USING (bucket_id = 'avatars' AND auth.uid()::TEXT = (storage.foldername(name))[1])
  WITH CHECK (bucket_id = 'avatars' AND auth.uid()::TEXT = (storage.foldername(name))[1]);

-- ── Issue / rotate a student activation code (admin-only) ──
-- Stores a pgcrypto-hashed code compatible with activate_student().
CREATE OR REPLACE FUNCTION issue_student_code(
  p_student_id UUID,
  p_plain_code TEXT,
  p_days_valid INTEGER DEFAULT 7
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_student students%ROWTYPE;
BEGIN
  SELECT * INTO v_student FROM students WHERE id = p_student_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'student_not_found');
  END IF;

  IF NOT (public.tc_is_school_admin(v_student.school_id) OR public.tc_is_platform_owner()) THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'forbidden');
  END IF;

  IF p_plain_code IS NULL OR length(p_plain_code) < 6 OR length(p_plain_code) > 32 THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'weak_code');
  END IF;

  INSERT INTO student_activation_credentials(school_id, student_id, code, expires_at, used_at, created_by)
  VALUES (
    v_student.school_id, v_student.id,
    crypt(p_plain_code, gen_salt('bf', 10)),
    NOW() + (COALESCE(p_days_valid, 7) || ' days')::INTERVAL,
    NULL, auth.uid()
  )
  ON CONFLICT (student_id) DO UPDATE SET
    code = EXCLUDED.code,
    expires_at = EXCLUDED.expires_at,
    used_at = NULL,
    created_by = EXCLUDED.created_by,
    created_at = NOW();

  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome)
  VALUES (v_student.school_id, auth.uid(), 'enrollment.code.issued', 'student', p_student_id::TEXT, 'success');

  RETURN jsonb_build_object('success', TRUE, 'expires_in_days', COALESCE(p_days_valid, 7));
END;
$$;

-- ── Reassign a student to another class (admin-only, audited) ──
CREATE OR REPLACE FUNCTION reassign_student_class(
  p_student_id UUID,
  p_new_class_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_student students%ROWTYPE;
  v_class classes%ROWTYPE;
BEGIN
  SELECT * INTO v_student FROM students WHERE id = p_student_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', FALSE, 'error', 'student_not_found'); END IF;
  SELECT * INTO v_class FROM classes WHERE id = p_new_class_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', FALSE, 'error', 'class_not_found'); END IF;
  IF v_student.school_id != v_class.school_id THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'cross_school');
  END IF;
  IF NOT (public.tc_is_school_admin(v_student.school_id) OR public.tc_is_platform_owner()) THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'forbidden');
  END IF;

  UPDATE class_enrollments SET unenrolled_at = NOW()
  WHERE student_id = p_student_id AND unenrolled_at IS NULL;

  INSERT INTO class_enrollments(school_id, class_id, student_id)
  VALUES (v_student.school_id, p_new_class_id, p_student_id);

  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome, reason)
  VALUES (v_student.school_id, auth.uid(), 'class.reassign', 'student', p_student_id::TEXT, 'success', p_reason);

  RETURN jsonb_build_object('success', TRUE, 'class_id', p_new_class_id);
END;
$$;

-- ── Publish due scheduled announcements (called by pg_cron / edge cron) ──
CREATE OR REPLACE FUNCTION publish_due_announcements()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_count INTEGER := 0;
BEGIN
  UPDATE announcements
  SET is_published = TRUE, published_at = NOW(), updated_at = NOW()
  WHERE is_published = FALSE
    AND scheduled_for IS NOT NULL
    AND scheduled_for <= NOW();
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN jsonb_build_object('success', TRUE, 'published', v_count);
END;
$$;

-- ── Realtime publication for authorized live updates ────────
-- (RLS still enforced on realtime subscriptions.)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;
END $$;

ALTER PUBLICATION supabase_realtime ADD TABLE messages;
ALTER PUBLICATION supabase_realtime ADD TABLE conversations;
ALTER PUBLICATION supabase_realtime ADD TABLE conversation_members;
ALTER PUBLICATION supabase_realtime ADD TABLE announcements;
ALTER PUBLICATION supabase_realtime ADD TABLE announcement_recipients;
ALTER PUBLICATION supabase_realtime ADD TABLE announcement_receipts;
ALTER PUBLICATION supabase_realtime ADD TABLE attachments;
ALTER PUBLICATION supabase_realtime ADD TABLE support_questions;
ALTER PUBLICATION supabase_realtime ADD TABLE notification_jobs;
