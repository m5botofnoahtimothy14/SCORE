-- ============================================================
-- TeachCross: Migration 00005 — Row-Level Security Policies
-- ============================================================
-- This is the security layer. All policies enforce multi-tenant
-- isolation and role-based access. Never trust client-supplied IDs.
-- ============================================================

-- Helper function: get authenticated user's school memberships
CREATE OR REPLACE FUNCTION public.tc_user_school_ids()
RETURNS UUID[] AS $$
  SELECT ARRAY(
    SELECT school_id FROM school_memberships
    WHERE user_id = auth.uid() AND is_active = TRUE
  )
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Helper: check if user has a role in a school
CREATE OR REPLACE FUNCTION public.tc_has_school_role(p_school_id UUID, p_role school_role)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM school_memberships
    WHERE user_id = auth.uid()
      AND school_id = p_school_id
      AND role = p_role
      AND is_active = TRUE
  )
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Helper: check if user is admin or above in a school
CREATE OR REPLACE FUNCTION public.tc_is_school_admin(p_school_id UUID)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM school_memberships
    WHERE user_id = auth.uid()
      AND school_id = p_school_id
      AND role IN ('platform_owner', 'school_admin', 'principal')
      AND is_active = TRUE
  )
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Helper: check if user is platform owner
CREATE OR REPLACE FUNCTION public.tc_is_platform_owner()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM school_memberships
    WHERE user_id = auth.uid()
      AND role = 'platform_owner'
      AND is_active = TRUE
  )
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Helper: check conversation membership (active)
CREATE OR REPLACE FUNCTION public.tc_is_conversation_member(p_conversation_id UUID)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM conversation_members
    WHERE conversation_id = p_conversation_id
      AND user_id = auth.uid()
      AND removed_at IS NULL
  )
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Helper: get user's teacher record ID for a school
CREATE OR REPLACE FUNCTION public.tc_my_teacher_id(p_school_id UUID)
RETURNS UUID AS $$
  SELECT id FROM teachers
  WHERE user_id = auth.uid() AND school_id = p_school_id
  LIMIT 1
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Helper: get user's student record ID for a school
CREATE OR REPLACE FUNCTION public.tc_my_student_id(p_school_id UUID)
RETURNS UUID AS $$
  SELECT id FROM students
  WHERE user_id = auth.uid() AND school_id = p_school_id
  LIMIT 1
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- ============================================================
-- ENABLE RLS ON ALL TABLES
-- ============================================================
ALTER TABLE schools                       ENABLE ROW LEVEL SECURITY;
ALTER TABLE school_settings               ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_profiles                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE school_memberships            ENABLE ROW LEVEL SECURITY;
ALTER TABLE academic_years                ENABLE ROW LEVEL SECURITY;
ALTER TABLE subjects                      ENABLE ROW LEVEL SECURITY;
ALTER TABLE classes                       ENABLE ROW LEVEL SECURITY;
ALTER TABLE students                      ENABLE ROW LEVEL SECURITY;
ALTER TABLE teachers                      ENABLE ROW LEVEL SECURITY;
ALTER TABLE class_enrollments             ENABLE ROW LEVEL SECURITY;
ALTER TABLE teaching_assignments          ENABLE ROW LEVEL SECURITY;
ALTER TABLE student_activation_credentials ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_activation_records      ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversation_members          ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages                      ENABLE ROW LEVEL SECURITY;
ALTER TABLE message_receipts              ENABLE ROW LEVEL SECURITY;
ALTER TABLE attachments                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE announcements                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE announcement_recipients       ENABLE ROW LEVEL SECURITY;
ALTER TABLE announcement_receipts         ENABLE ROW LEVEL SECURITY;
ALTER TABLE moderation_results            ENABLE ROW LEVEL SECURITY;
ALTER TABLE moderation_review_cases       ENABLE ROW LEVEL SECURITY;
ALTER TABLE safeguarding_incidents        ENABLE ROW LEVEL SECURITY;
ALTER TABLE message_reports               ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_events                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE investigation_requests        ENABLE ROW LEVEL SECURITY;
ALTER TABLE investigation_approvals       ENABLE ROW LEVEL SECURITY;
ALTER TABLE investigation_access_events   ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_devices          ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_jobs             ENABLE ROW LEVEL SECURITY;
ALTER TABLE support_tickets               ENABLE ROW LEVEL SECURITY;
ALTER TABLE data_retention_policies       ENABLE ROW LEVEL SECURITY;
ALTER TABLE background_jobs               ENABLE ROW LEVEL SECURITY;
ALTER TABLE support_questions             ENABLE ROW LEVEL SECURITY;
ALTER TABLE support_question_history      ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- SCHOOLS — read for members, write for admins
-- ============================================================
CREATE POLICY schools_select ON schools FOR SELECT
  USING (id = ANY(public.tc_user_school_ids()));

CREATE POLICY schools_admin_all ON schools FOR ALL
  USING (public.tc_is_platform_owner());

-- ============================================================
-- SCHOOL_SETTINGS — read for admins of that school
-- ============================================================
CREATE POLICY school_settings_select ON school_settings FOR SELECT
  USING (public.tc_is_school_admin(school_id));

CREATE POLICY school_settings_update ON school_settings FOR UPDATE
  USING (public.tc_is_school_admin(school_id));

-- ============================================================
-- USER_PROFILES — users can see their own profile;
-- school members can see other members of shared schools
-- ============================================================
CREATE POLICY user_profiles_own ON user_profiles FOR ALL
  USING (id = auth.uid());

CREATE POLICY user_profiles_school_member ON user_profiles FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM school_memberships sm
      WHERE sm.user_id = user_profiles.id
        AND sm.school_id = ANY(public.tc_user_school_ids())
        AND sm.is_active = TRUE
    )
  );

-- ============================================================
-- SCHOOL_MEMBERSHIPS
-- ============================================================
CREATE POLICY memberships_own ON school_memberships FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY memberships_admin_school ON school_memberships FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ============================================================
-- ACADEMIC_YEARS, SUBJECTS, CLASSES — school members read
-- ============================================================
CREATE POLICY academic_years_select ON academic_years FOR SELECT
  USING (school_id = ANY(public.tc_user_school_ids()));

CREATE POLICY academic_years_admin ON academic_years FOR ALL
  USING (public.tc_is_school_admin(school_id));

CREATE POLICY subjects_select ON subjects FOR SELECT
  USING (school_id = ANY(public.tc_user_school_ids()));

CREATE POLICY subjects_admin ON subjects FOR ALL
  USING (public.tc_is_school_admin(school_id));

CREATE POLICY classes_select ON classes FOR SELECT
  USING (school_id = ANY(public.tc_user_school_ids()));

CREATE POLICY classes_admin ON classes FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ============================================================
-- STUDENTS — admins see all; teachers see their class students;
-- students see only themselves
-- ============================================================
CREATE POLICY students_admin ON students FOR ALL
  USING (public.tc_is_school_admin(school_id));

CREATE POLICY students_own ON students FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY students_teacher_view ON students FOR SELECT
  USING (
    school_id = ANY(public.tc_user_school_ids())
    AND EXISTS (
      SELECT 1 FROM teaching_assignments ta
        JOIN class_enrollments ce ON ce.class_id = ta.class_id
        JOIN teachers t ON t.id = ta.teacher_id
      WHERE t.user_id = auth.uid()
        AND ce.student_id = students.id
        AND ce.unenrolled_at IS NULL
    )
  );

-- ============================================================
-- TEACHERS — admins see all; teachers see colleagues in same school;
-- students see only their assigned teachers
-- ============================================================
CREATE POLICY teachers_admin ON teachers FOR ALL
  USING (public.tc_is_school_admin(school_id));

CREATE POLICY teachers_own ON teachers FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY teachers_colleague ON teachers FOR SELECT
  USING (
    school_id = ANY(public.tc_user_school_ids())
    AND public.tc_has_school_role(school_id, 'teacher')
  );

CREATE POLICY teachers_student_view ON teachers FOR SELECT
  USING (
    school_id = ANY(public.tc_user_school_ids())
    AND public.tc_has_school_role(school_id, 'student')
    AND EXISTS (
      SELECT 1 FROM teaching_assignments ta
        JOIN class_enrollments ce ON ce.class_id = ta.class_id
        JOIN students s ON s.id = ce.student_id
      WHERE ta.teacher_id = teachers.id
        AND s.user_id = auth.uid()
        AND ce.unenrolled_at IS NULL
    )
  );

-- ============================================================
-- CLASS_ENROLLMENTS & TEACHING_ASSIGNMENTS — admins full access
-- ============================================================
CREATE POLICY class_enrollments_admin ON class_enrollments FOR ALL
  USING (public.tc_is_school_admin(school_id));

CREATE POLICY class_enrollments_teacher ON class_enrollments FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM teaching_assignments ta
        JOIN teachers t ON t.id = ta.teacher_id
      WHERE ta.class_id = class_enrollments.class_id
        AND t.user_id = auth.uid()
    )
  );

CREATE POLICY class_enrollments_student ON class_enrollments FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM students s
      WHERE s.id = class_enrollments.student_id
        AND s.user_id = auth.uid()
    )
  );

CREATE POLICY teaching_assignments_admin ON teaching_assignments FOR ALL
  USING (public.tc_is_school_admin(school_id));

CREATE POLICY teaching_assignments_read ON teaching_assignments FOR SELECT
  USING (school_id = ANY(public.tc_user_school_ids()));

-- ============================================================
-- ACTIVATION CREDENTIALS — admin only (no student self-read!)
-- ============================================================
CREATE POLICY student_credentials_admin ON student_activation_credentials FOR ALL
  USING (public.tc_is_school_admin(school_id));

CREATE POLICY staff_activation_own ON staff_activation_records FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM teachers t
      WHERE t.id = staff_activation_records.teacher_id
        AND t.user_id = auth.uid()
    )
  );

CREATE POLICY staff_activation_admin ON staff_activation_records FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ============================================================
-- CONVERSATIONS — only members can see their conversations
-- ============================================================
CREATE POLICY conversations_member ON conversations FOR SELECT
  USING (public.tc_is_conversation_member(id));

CREATE POLICY conversations_admin ON conversations FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ============================================================
-- CONVERSATION_MEMBERS — only see members of your own conversations
-- ============================================================
CREATE POLICY conv_members_read ON conversation_members FOR SELECT
  USING (
    public.tc_is_conversation_member(conversation_id)
    OR user_id = auth.uid()
  );

CREATE POLICY conv_members_admin ON conversation_members FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM conversations c
      WHERE c.id = conversation_members.conversation_id
        AND public.tc_is_school_admin(c.school_id)
    )
  );

-- ============================================================
-- MESSAGES — CRITICAL: only approved messages visible to members
-- Students can only see approved messages in their own conversations
-- ============================================================
CREATE POLICY messages_member_read ON messages FOR SELECT
  USING (
    public.tc_is_conversation_member(conversation_id)
    AND (
      status = 'approved'
      OR sender_id = auth.uid()         -- can see own pending messages
    )
    AND is_deleted = FALSE
  );

CREATE POLICY messages_insert ON messages FOR INSERT
  WITH CHECK (
    sender_id = auth.uid()              -- must be the actual sender
    AND public.tc_is_conversation_member(conversation_id)
    AND EXISTS (
      SELECT 1 FROM conversation_members cm
      WHERE cm.conversation_id = messages.conversation_id
        AND cm.user_id = auth.uid()
        AND cm.can_send = TRUE
        AND cm.removed_at IS NULL
    )
  );

CREATE POLICY messages_admin_read ON messages FOR SELECT
  USING (public.tc_is_school_admin(school_id));

CREATE POLICY messages_admin_update ON messages FOR UPDATE
  USING (public.tc_is_school_admin(school_id));

-- ============================================================
-- ATTACHMENTS — only approved, conversation members can access
-- ============================================================
CREATE POLICY attachments_member_read ON attachments FOR SELECT
  USING (
    uploader_id = auth.uid()
    OR (
      status = 'approved'
      AND EXISTS (
        SELECT 1 FROM messages m
        WHERE m.id = attachments.message_id
          AND public.tc_is_conversation_member(m.conversation_id)
      )
    )
  );

CREATE POLICY attachments_insert ON attachments FOR INSERT
  WITH CHECK (uploader_id = auth.uid());

CREATE POLICY attachments_admin ON attachments FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ============================================================
-- ANNOUNCEMENTS — published announcements visible to recipients
-- ============================================================
CREATE POLICY announcements_recipient ON announcements FOR SELECT
  USING (
    is_published = TRUE
    AND EXISTS (
      SELECT 1 FROM announcement_recipients ar
      WHERE ar.announcement_id = announcements.id
        AND ar.user_id = auth.uid()
    )
  );

CREATE POLICY announcements_admin ON announcements FOR ALL
  USING (public.tc_is_school_admin(school_id));

CREATE POLICY announcements_teacher_insert ON announcements FOR INSERT
  WITH CHECK (
    author_id = auth.uid()
    AND public.tc_has_school_role(school_id, 'teacher')
    AND audience_type NOT IN ('school_wide')   -- teachers can't broadcast school-wide
  );

-- ============================================================
-- ANNOUNCEMENT_RECIPIENTS & RECEIPTS
-- ============================================================
CREATE POLICY ann_recipients_own ON announcement_recipients FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY ann_recipients_admin ON announcement_recipients FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM announcements a
      WHERE a.id = announcement_recipients.announcement_id
        AND public.tc_is_school_admin(a.school_id)
    )
  );

CREATE POLICY ann_receipts_own ON announcement_receipts FOR ALL
  USING (user_id = auth.uid());

CREATE POLICY ann_receipts_admin ON announcement_receipts FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM announcements a
      WHERE a.id = announcement_receipts.announcement_id
        AND public.tc_is_school_admin(a.school_id)
    )
  );

-- ============================================================
-- MODERATION — admin only
-- ============================================================
CREATE POLICY moderation_results_admin ON moderation_results FOR ALL
  USING (public.tc_is_school_admin(school_id));

CREATE POLICY review_cases_admin ON moderation_review_cases FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ============================================================
-- SAFEGUARDING — admin + assigned reviewer only
-- ============================================================
CREATE POLICY incidents_admin ON safeguarding_incidents FOR ALL
  USING (public.tc_is_school_admin(school_id));

CREATE POLICY incidents_assigned ON safeguarding_incidents FOR SELECT
  USING (assigned_to = auth.uid());

-- ============================================================
-- MESSAGE REPORTS — reporters can see their own; admins see all
-- ============================================================
CREATE POLICY reports_own ON message_reports FOR ALL
  USING (reporter_id = auth.uid());

CREATE POLICY reports_admin ON message_reports FOR SELECT
  USING (public.tc_is_school_admin(school_id));

-- ============================================================
-- AUDIT EVENTS — READ ONLY for admins; NO UPDATE/DELETE
-- ============================================================
CREATE POLICY audit_admin_read ON audit_events FOR SELECT
  USING (
    (school_id IS NULL AND public.tc_is_platform_owner())
    OR public.tc_is_school_admin(school_id)
  );

-- Intentionally NO UPDATE or DELETE policy — audit records are immutable
-- Even admins cannot modify audit history via RLS

-- ============================================================
-- INVESTIGATION REQUESTS — platform owner + school admin
-- ============================================================
CREATE POLICY investigation_admin ON investigation_requests FOR ALL
  USING (public.tc_is_school_admin(school_id) OR public.tc_is_platform_owner());

CREATE POLICY investigation_requested_by ON investigation_requests FOR SELECT
  USING (requested_by = auth.uid());

CREATE POLICY inv_approvals_admin ON investigation_approvals FOR ALL
  USING (public.tc_is_platform_owner());

CREATE POLICY inv_access_events_admin ON investigation_access_events FOR ALL
  USING (public.tc_is_platform_owner());

-- ============================================================
-- NOTIFICATION DEVICES — own only; admins can see for their school
-- ============================================================
CREATE POLICY notif_devices_own ON notification_devices FOR ALL
  USING (user_id = auth.uid());

CREATE POLICY notif_devices_admin ON notification_devices FOR SELECT
  USING (public.tc_is_school_admin(school_id));

-- ============================================================
-- NOTIFICATION JOBS — user sees own; admins see school
-- ============================================================
CREATE POLICY notif_jobs_own ON notification_jobs FOR SELECT
  USING (recipient_id = auth.uid());

CREATE POLICY notif_jobs_admin ON notification_jobs FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ============================================================
-- SUPPORT TICKETS — own; admin sees all for school
-- ============================================================
CREATE POLICY tickets_own ON support_tickets FOR ALL
  USING (submitted_by = auth.uid());

CREATE POLICY tickets_admin ON support_tickets FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ============================================================
-- BACKGROUND JOBS — platform admin only
-- ============================================================
CREATE POLICY background_jobs_platform ON background_jobs FOR ALL
  USING (public.tc_is_platform_owner());

-- ============================================================
-- SUPPORT QUESTIONS
-- ============================================================
CREATE POLICY support_questions_student ON support_questions FOR ALL
  USING (student_id = auth.uid());

CREATE POLICY support_questions_teacher ON support_questions FOR SELECT
  USING (public.tc_is_conversation_member(conversation_id));

CREATE POLICY support_questions_admin ON support_questions FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM conversations c
      WHERE c.id = support_questions.conversation_id
        AND public.tc_is_school_admin(c.school_id)
    )
  );

CREATE POLICY support_q_history_read ON support_question_history FOR SELECT
  USING (changed_by = auth.uid() OR
    EXISTS (
      SELECT 1 FROM support_questions sq
        JOIN conversations c ON c.id = sq.conversation_id
      WHERE sq.id = support_question_history.question_id
        AND (public.tc_is_school_admin(c.school_id)
             OR public.tc_is_conversation_member(sq.conversation_id))
    )
  );
