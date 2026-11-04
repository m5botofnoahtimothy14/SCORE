
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
  USING (public.tc_is_school_admin((
    SELECT school_id FROM doubt_requests WHERE id = doubt_status_history.request_id
  )));

-- ── Session Bookings ──
CREATE POLICY session_bookings_participant ON public.session_bookings FOR ALL
  USING (student_id = auth.uid() OR mentor_id = auth.uid());
CREATE POLICY session_bookings_admin ON public.session_bookings FOR ALL
  USING (public.tc_is_school_admin(school_id));

-- ── Session No-Shows ──
CREATE POLICY session_no_shows_reporter ON public.session_no_shows FOR ALL
  USING (recorded_by = auth.uid());
CREATE POLICY session_no_shows_admin ON public.session_no_shows FOR ALL
  USING (public.tc_is_school_admin((
    SELECT school_id FROM session_bookings WHERE id = session_no_shows.booking_id
  )));

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

