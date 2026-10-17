-- ============================================================
-- 00017 — Security, RLS and workflow fixes
-- Consolidates findings from the full-stack audit (web + mobile + backend).
-- ============================================================

-- ------------------------------------------------------------
-- 1. activate_student() referenced school_memberships.updated_at,
--    which did not exist. The CREATE FUNCTION succeeded but the
--    returning-student revoke branch raised at runtime.
-- ------------------------------------------------------------
ALTER TABLE school_memberships
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- ------------------------------------------------------------
-- 2. rate_limit_events had RLS DISABLED (phone numbers in `key`
--    were world-readable and the limiter was bypassable).
--    Only edge functions (service_role) touch this table.
--    Enabling RLS with no policies = deny anon/authenticated.
-- ------------------------------------------------------------
ALTER TABLE rate_limit_events ENABLE ROW LEVEL SECURITY;

-- ------------------------------------------------------------
-- 3. Read receipts. conversation_members had no safe UPDATE path
--    and message_receipts had RLS enabled with ZERO policies, so
--    markRead() silently failed and unread counts grew forever.
--    Use a column-safe SECURITY DEFINER RPC instead of a broad
--    UPDATE policy (which would let users self-escalate can_send).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.mark_conversation_read(p_conversation_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  IF NOT public.tc_is_conversation_member(p_conversation_id) THEN
    RAISE EXCEPTION 'not_a_member';
  END IF;

  UPDATE conversation_members
  SET last_read_at = NOW()
  WHERE conversation_id = p_conversation_id
    AND user_id = v_uid;

  INSERT INTO message_receipts (message_id, user_id, delivered_at, read_at)
  SELECT m.id, v_uid, NOW(), NOW()
  FROM messages m
  WHERE m.conversation_id = p_conversation_id
    AND m.status = 'approved'
    AND m.is_deleted = FALSE
    AND m.sender_id <> v_uid
  ON CONFLICT (message_id, user_id)
  DO UPDATE SET
    read_at = NOW(),
    delivered_at = COALESCE(message_receipts.delivered_at, NOW());
END;
$$;

GRANT EXECUTE ON FUNCTION public.mark_conversation_read(uuid) TO authenticated;

-- message_receipts: owner may read their own receipts; school admins manage all.
CREATE POLICY receipts_own_read ON message_receipts FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY receipts_admin ON message_receipts FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM messages m
      WHERE m.id = message_receipts.message_id
        AND public.tc_is_school_admin(m.school_id)
    )
  );

-- ------------------------------------------------------------
-- 4. attachments INSERT was `WITH CHECK (uploader_id = auth.uid())`
--    — a client could insert an already-approved, unmoderated row.
--    Only allow the pending upload states, scoped to the user's school.
-- ------------------------------------------------------------
DROP POLICY IF EXISTS attachments_insert ON attachments;

CREATE POLICY attachments_insert ON attachments FOR INSERT
  WITH CHECK (
    uploader_id = auth.uid()
    AND status IN ('uploading', 'pending_scan')
    AND school_id = ANY(public.tc_user_school_ids())
  );

-- Owner may still update their own (not-yet-approved) attachment row.
CREATE POLICY attachments_owner_update ON attachments FOR UPDATE
  USING (uploader_id = auth.uid() AND status IN ('uploading', 'pending_scan'))
  WITH CHECK (uploader_id = auth.uid() AND status IN ('uploading', 'pending_scan'));

-- ------------------------------------------------------------
-- 5. schools UPDATE was platform-owner only, so a school admin
--    could never edit their own school profile from the DMS.
-- ------------------------------------------------------------
CREATE POLICY schools_admin_update ON schools FOR UPDATE
  USING (public.tc_is_school_admin(id))
  WITH CHECK (public.tc_is_school_admin(id));

-- ------------------------------------------------------------
-- 6. data_retention_policies had RLS enabled with no read policy,
--    so the Settings page could never load retention config.
-- ------------------------------------------------------------
CREATE POLICY retention_admin_read ON data_retention_policies FOR SELECT
  USING (public.tc_is_school_admin(school_id));

CREATE POLICY retention_admin_write ON data_retention_policies FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ------------------------------------------------------------
-- 7. support_questions: teachers (conversation members) could read
--    but never update status; support_question_history had no INSERT.
-- ------------------------------------------------------------
CREATE POLICY support_questions_teacher_update ON support_questions FOR UPDATE
  USING (public.tc_is_conversation_member(conversation_id));

CREATE POLICY support_q_history_insert ON support_question_history FOR INSERT
  WITH CHECK (
    changed_by = auth.uid()
    AND EXISTS (
      SELECT 1 FROM support_questions sq
      WHERE sq.id = support_question_history.question_id
        AND public.tc_is_conversation_member(sq.conversation_id)
    )
  );

-- ------------------------------------------------------------
-- 8. Teacher directory visibility. Head teachers/leaders in a school
--    should see all teachers; students should be able to see school
--    leadership so they can start a conversation with them.
-- ------------------------------------------------------------
CREATE POLICY teachers_leadership ON teachers FOR SELECT
  USING (
    school_id = ANY(public.tc_user_school_ids())
    AND EXISTS (
      SELECT 1 FROM school_memberships sm
      WHERE sm.user_id = auth.uid()
        AND sm.school_id = teachers.school_id
        AND sm.is_active = TRUE
        AND sm.role IN ('head_teacher', 'principal', 'school_admin', 'platform_owner')
    )
  );

CREATE POLICY teachers_student_leadership ON teachers FOR SELECT
  USING (
    is_leadership = TRUE
    AND EXISTS (
      SELECT 1 FROM students s
      WHERE s.user_id = auth.uid()
        AND s.school_id = teachers.school_id
    )
  );

-- ------------------------------------------------------------
-- 9. OTP provider default/data hygiene. The send-otp edge function
--    always uses TextBee; the stale 'twilio' default was misleading.
-- ------------------------------------------------------------
ALTER TABLE school_settings ALTER COLUMN otp_provider SET DEFAULT 'textbee';
UPDATE school_settings SET otp_provider = 'textbee'
  WHERE otp_provider IS NULL OR otp_provider = 'twilio';
