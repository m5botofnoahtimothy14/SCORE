-- ============================================================
-- Migration 00028: verify existing RLS state.
--
-- The previous migration added broad, permissive policies on top of the
-- production policy set. PostgreSQL combines permissive policies with OR.
-- Keep the existing reviewed policies. Focused new-table policies are added
-- by migrations 00034-00036.
-- ============================================================
DO $$
DECLARE
  v_table text;
  v_required text[] := ARRAY[
    'schools','school_settings','user_profiles','school_memberships',
    'academic_years','subjects','classes','students','teachers',
    'class_enrollments','teaching_assignments','student_activation_credentials',
    'staff_activation_records','rate_limit_events','conversations',
    'conversation_members','messages','attachments','announcements',
    'moderation_events','audit_events','background_jobs',
    'data_retention_policies','mentor_desk_settings','mentor_subject_approvals',
    'mentor_availability','doubt_requests','doubt_status_history',
    'session_bookings','session_no_shows','ratings','mentor_assessments',
    'allowance_transactions','urgent_pass_usage','slt_access_grants'
  ];
BEGIN
  FOREACH v_table IN ARRAY v_required LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_class c
      WHERE c.oid = to_regclass('public.' || v_table)
        AND c.relrowsecurity = true
    ) THEN
      RAISE EXCEPTION 'RLS must be enabled before recovery continues: public.%', v_table;
    END IF;
  END LOOP;
END;
$$;
