-- ============================================================
-- Migration 00027: production schema preflight.
--
-- The original redesign used CREATE TABLE IF NOT EXISTS for tables that
-- already existed in production. That does not add missing columns. It also
-- replaced existing security helpers and created unused video/recording
-- tables. Keep this migration non-destructive. Missing columns and tables
-- are reconciled by the focused migrations 00034-00036.
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
    IF to_regclass('public.' || v_table) IS NULL THEN
      RAISE EXCEPTION 'Required existing SCORE+ table is missing: public.%', v_table;
    END IF;
  END LOOP;
END;
$$;
