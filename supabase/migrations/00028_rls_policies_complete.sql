-- ============================================================
-- Row Level Security Policies (Complete Redesign)
-- ============================================================

-- ── Schools ──
CREATE POLICY schools_select ON public.schools FOR SELECT
  USING (school_id = ANY(public.tc_user_school_ids()));
CREATE POLICY schools_admin ON public.schools FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ── School Settings ──
CREATE POLICY school_settings_select ON public.school_settings FOR SELECT
  USING (school_id = ANY(public.tc_user_school_ids()));
CREATE POLICY school_settings_admin ON public.school_settings FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ── User Profiles ──
CREATE POLICY user_profiles_select ON public.user_profiles FOR SELECT
  USING (id = auth.uid() OR id = ANY(
    SELECT user_id FROM school_memberships WHERE school_id = ANY(public.tc_user_school_ids()) AND is_active = TRUE
  ));
CREATE POLICY user_profiles_own_update ON public.user_profiles FOR UPDATE
  USING (id = auth.uid());

-- ── School Memberships ──
CREATE POLICY school_memberships_select ON public.school_memberships FOR SELECT
  USING (school_id = ANY(public.tc_user_school_ids()));
CREATE POLICY school_memberships_admin ON public.school_memberships FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ── Academic Years ──
CREATE POLICY academic_years_select ON public.academic_years FOR SELECT
  USING (school_id = ANY(public.tc_user_school_ids()));
CREATE POLICY academic_years_admin ON public.academic_years FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ── Subjects ──
CREATE POLICY subjects_select ON public.subjects FOR SELECT
  USING (school_id = ANY(public.tc_user_school_ids()));
CREATE POLICY subjects_admin ON public.subjects FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ── Classes ──
CREATE POLICY classes_select ON public.classes FOR SELECT
  USING (school_id = ANY(public.tc_user_school_ids()));
CREATE POLICY classes_admin ON public.classes FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ── Students ──
CREATE POLICY students_select ON public.students FOR SELECT
  USING (school_id = ANY(public.tc_user_school_ids()));
CREATE POLICY students_admin ON public.students FOR ALL
  USING (public.tc_is_school_admin(school_id));
-- Students can see their own record
CREATE POLICY students_own ON public.students FOR SELECT
  USING (user_id = auth.uid());

-- ── Teachers ──
CREATE POLICY teachers_select ON public.teachers FOR SELECT
  USING (school_id = ANY(public.tc_user_school_ids()));
CREATE POLICY teachers_admin ON public.teachers FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ── Class Enrollments ──
CREATE POLICY class_enrollments_select ON public.class_enrollments FOR SELECT
  USING (school_id = ANY(public.tc_user_school_ids()));
CREATE POLICY class_enrollments_admin ON public.class_enrollments FOR ALL
  USING (public.tc_is_school_admin(school_id));
-- Students can see their own enrollments
CREATE POLICY class_enrollments_own ON public.class_enrollments FOR SELECT
  USING (student_id IN (
    SELECT id FROM students WHERE user_id = auth.uid()
  ));

-- ── Teaching Assignments ──
CREATE POLICY teaching_assignments_select ON public.teaching_assignments FOR SELECT
  USING (school_id = ANY(public.tc_user_school_ids()));
CREATE POLICY teaching_assignments_admin ON public.teaching_assignments FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ── Activation Credentials ──
CREATE POLICY student_activation_credentials_admin ON public.student_activation_credentials FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ── Staff Activation Records ──
CREATE POLICY staff_activation_records_admin ON public.staff_activation_records FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ── Rate Limit Events ──
CREATE POLICY rate_limit_events_admin ON public.rate_limit_events FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ── Conversations ──
CREATE POLICY conversations_select ON public.conversations FOR SELECT
  USING (school_id = ANY(public.tc_user_school_ids()));
CREATE POLICY conversations_admin ON public.conversations FOR ALL
  USING (public.tc_is_school_admin(school_id));
-- Members can insert into conversations they belong to
CREATE POLICY conversations_insert ON public.conversations FOR INSERT
  WITH CHECK (school_id = ANY(public.tc_user_school_ids()) AND created_by = auth.uid());

-- ── Conversation Members ──
CREATE POLICY conversation_members_select ON public.conversation_members FOR SELECT
  USING (user_id = auth.uid() OR conversation_id IN (
    SELECT conversation_id FROM conversation_members WHERE user_id = auth.uid() AND removed_at IS NULL
  ));
CREATE POLICY conversation_members_admin ON public.conversation_members FOR ALL
  USING (public.tc_is_school_admin(
    SELECT school_id FROM conversations WHERE id = conversation_members.conversation_id
  ));
CREATE POLICY conversation_members_insert ON public.conversation_members FOR INSERT
  WITH CHECK (user_id = auth.uid());

-- ── Messages ──
CREATE POLICY messages_select ON public.messages FOR SELECT
  USING (
    conversation_id IN (
      SELECT conversation_id FROM conversation_members WHERE user_id = auth.uid() AND removed_at IS NULL
    )
  );
CREATE POLICY messages_admin ON public.messages FOR ALL
  USING (public.tc_is_school_admin(school_id));
CREATE POLICY messages_insert ON public.messages FOR INSERT
  WITH CHECK (sender_id = auth.uid());

-- ── Attachments ──
CREATE POLICY attachments_select ON public.attachments FOR SELECT
  USING (uploader_id = auth.uid() OR message_id IN (
    SELECT id FROM messages WHERE conversation_id IN (
      SELECT conversation_id FROM conversation_members WHERE user_id = auth.uid() AND removed_at IS NULL
    )
  ));
CREATE POLICY attachments_admin ON public.attachments FOR ALL
  USING (public.tc_is_school_admin(school_id));
CREATE POLICY attachments_insert ON public.attachments FOR INSERT
  WITH CHECK (uploader_id = auth.uid());

-- ── Announcements ──
CREATE POLICY announcements_select ON public.announcements FOR SELECT
  USING (school_id = ANY(public.tc_user_school_ids()));
CREATE POLICY announcements_admin ON public.announcements FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ── Moderation Events ──
CREATE POLICY moderation_events_select ON public.moderation_events FOR SELECT
  USING (school_id = ANY(public.tc_user_school_ids()));
CREATE POLICY moderation_events_admin ON public.moderation_events FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ── Audit Events ──
CREATE POLICY audit_events_select ON public.audit_events FOR SELECT
  USING (school_id = ANY(public.tc_user_school_ids()));
CREATE POLICY audit_events_admin ON public.audit_events FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ── Background Jobs ──
CREATE POLICY background_jobs_admin ON public.background_jobs FOR ALL
  USING (public.tc_is_school_admin(
    SELECT school_id FROM audit_events WHERE id = background_jobs.payload->>'audit_event_id'
  )) OR public.tc_is_school_admin(
    SELECT school_id FROM doubt_requests WHERE id = background_jobs.payload->>'request_id'
  ) OR public.tc_is_school_admin(
    SELECT school_id FROM session_bookings WHERE id = background_jobs.payload->>'booking_id'
  );

-- ── Data Retention ──
CREATE POLICY data_retention_policies_admin ON public.data_retention_policies FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ── Mentor Desk Settings ──
CREATE POLICY mentor_desk_settings_select ON public.mentor_desk_settings FOR SELECT
  USING (school_id = ANY(public.tc_user_school_ids()));
CREATE POLICY mentor_desk_settings_admin ON public.mentor_desk_settings FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ── Mentor Subject Approvals ──
CREATE POLICY mentor_subject_approvals_select ON public.mentor_subject_approvals FOR SELECT
  USING (school_id = ANY(public.tc_user_school_ids()));
CREATE POLICY mentor_subject_approvals_admin ON public.mentor_subject_approvals FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ── Mentor Availability ──
CREATE POLICY mentor_availability_select ON public.mentor_availability FOR SELECT
  USING (school_id = ANY(public.tc_user_school_ids()));
CREATE POLICY mentor_availability_own_update ON public.mentor_availability FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM teachers t
      WHERE t.id = mentor_availability.teacher_id
        AND t.user_id = auth.uid()
    )
  );
CREATE POLICY mentor_availability_admin ON public.mentor_availability FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ── Doubt Requests ──
CREATE POLICY doubt_requests_student ON public.doubt_requests FOR ALL
  USING (student_id = auth.uid());
CREATE POLICY doubt_requests_mentor ON public.doubt_requests FOR SELECT
  USING (
    school_id = ANY(public.tc_user_school_ids())
    AND (
      assigned_mentor_id = auth.uid()
      OR EXISTS (
        SELECT 1 FROM conversation_members cm
        WHERE cm.conversation_id = doubt_requests.conversation_id
          AND cm.user_id = auth.uid()
          AND cm.removed_at IS NULL
      )
    )
  );
CREATE POLICY doubt_requests_admin ON public.doubt_requests FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM conversations c
      WHERE c.id = doubt_requests.conversation_id
        AND public.tc_is_school_admin(c.school_id)
    )
  );

-- ── Doubt Status History ──
CREATE POLICY doubt_status_history_select ON public.doubt_status_history FOR SELECT
  USING (request_id IN (
    SELECT id FROM doubt_requests WHERE school_id = ANY(public.tc_user_school_ids())
  ));
CREATE POLICY doubt_status_history_admin ON public.doubt_status_history FOR ALL
  USING (public.tc_is_school_admin(
    SELECT school_id FROM doubt_requests WHERE id = doubt_status_history.request_id
  ));

-- ── Session Bookings ──
CREATE POLICY session_bookings_participant ON public.session_bookings FOR ALL
  USING (student_id = auth.uid() OR mentor_id = auth.uid());
CREATE POLICY session_bookings_admin ON public.session_bookings FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ── Session No-Shows ──
CREATE POLICY session_no_shows_reporter ON public.session_no_shows FOR ALL
  USING (reported_by = auth.uid());
CREATE POLICY session_no_shows_admin ON public.session_no_shows FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ── Ratings ──
CREATE POLICY ratings_student ON public.ratings FOR ALL
  USING (student_id = auth.uid());
CREATE POLICY ratings_mentor_read ON public.ratings FOR SELECT
  USING (mentor_id = auth.uid());
CREATE POLICY ratings_admin_read ON public.ratings FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM doubt_requests dr
      WHERE dr.id = ratings.request_id
        AND public.tc_is_school_admin(dr.school_id)
    )
  );

-- ── Mentor Assessments ──
CREATE POLICY mentor_assessments_mentor ON public.mentor_assessments FOR ALL
  USING (mentor_id = auth.uid());
CREATE POLICY mentor_assessments_admin_read ON public.mentor_assessments FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM doubt_requests dr
      WHERE dr.id = mentor_assessments.request_id
        AND public.tc_is_school_admin(dr.school_id)
    )
  );
-- No SELECT policy for students - they can never read assessments

-- ── Allowance Transactions ──
CREATE POLICY allowance_transactions_student ON public.allowance_transactions FOR SELECT
  USING (student_id = auth.uid());
CREATE POLICY allowance_transactions_admin ON public.allowance_transactions FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ── Urgent Pass Usage ──
CREATE POLICY urgent_pass_usage_student ON public.urgent_pass_usage FOR SELECT
  USING (student_id = auth.uid());
CREATE POLICY urgent_pass_usage_admin ON public.urgent_pass_usage FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ── SLT Access Grants ──
CREATE POLICY slt_access_grants_own ON public.slt_access_grants FOR SELECT
  USING (user_id = auth.uid());
CREATE POLICY slt_access_grants_admin ON public.slt_access_grants FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ── Video Rooms ──
CREATE POLICY video_rooms_participant ON public.video_rooms FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM session_bookings b
      WHERE b.id = video_rooms.booking_id
        AND (b.student_id = auth.uid() OR b.mentor_id = auth.uid())
    )
  );
CREATE POLICY video_rooms_admin ON public.video_rooms FOR ALL
  USING (public.tc_is_school_admin(
    SELECT school_id FROM session_bookings WHERE id = video_rooms.booking_id
  ));

-- ── Video Participant Events ──
CREATE POLICY video_events_insert ON public.video_participant_events FOR INSERT
  WITH CHECK (user_id = auth.uid());
CREATE POLICY video_events_select ON public.video_participant_events FOR SELECT
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM session_bookings b
      WHERE b.id = video_participant_events.booking_id
        AND (b.student_id = auth.uid() OR b.mentor_id = auth.uid())
    )
    OR EXISTS (
      SELECT 1 FROM session_bookings b
      WHERE b.id = video_participant_events.booking_id
        AND public.tc_is_school_admin(b.school_id)
    )
  );

-- ── Recording Consents ──
CREATE POLICY recording_consents_own ON public.recording_consents FOR ALL
  USING (user_id = auth.uid());
CREATE POLICY recording_consents_admin ON public.recording_consents FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM session_bookings b
      WHERE b.id = recording_consents.booking_id
        AND public.tc_is_school_admin(b.school_id)
    )
  );

-- ── Session Recordings ──
CREATE POLICY session_recordings_participant ON public.session_recordings FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM session_bookings b
      WHERE b.id = session_recordings.booking_id
        AND (b.student_id = auth.uid() OR b.mentor_id = auth.uid())
    )
  );
CREATE POLICY session_recordings_admin ON public.session_recordings FOR ALL
  USING (public.tc_is_school_admin(
    SELECT school_id FROM session_bookings WHERE id = session_recordings.booking_id
  ));

-- ============================================================
-- REALTIME PUBLICATION
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;
END $$;

DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE messages; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE doubt_requests; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE session_bookings; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE mentor_availability; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE ratings; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE announcements; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE background_jobs; EXCEPTION WHEN duplicate_object THEN NULL; END $$;