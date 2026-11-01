-- Schema reconciliation regression checks.
-- Run after migration 00034 in a disposable Supabase project.
DO $$
DECLARE
  v_column text;
  v_required text[] := ARRAY[
    'conversation_id','student_id','student_record_id','class_id',
    'subject_id','question','urgent','urgent_reason','urgent_pass_used',
    'status','assigned_mentor_id','assigned_teacher_id','idempotency_key',
    'created_at','updated_at'
  ];
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum e
    JOIN pg_type t ON t.oid=e.enumtypid
    WHERE t.typname='conversation_type' AND e.enumlabel='mentor_desk'
  ) THEN
    RAISE EXCEPTION 'mentor_desk conversation type is missing';
  END IF;

  FOREACH v_column IN ARRAY v_required LOOP
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema='public' AND table_name='doubt_requests'
        AND column_name=v_column
    ) THEN
      RAISE EXCEPTION 'Missing public.doubt_requests column: %', v_column;
    END IF;
  END LOOP;

  IF to_regclass('public.student_subject_enrollments') IS NULL THEN
    RAISE EXCEPTION 'Student subject enrolment table is missing';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.student_subject_enrollments'::regclass) THEN
    RAISE EXCEPTION 'RLS is disabled on student_subject_enrollments';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='urgent_pass_usage'
      AND column_name='request_id'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='urgent_pass_usage'
      AND column_name='consumed_at'
  ) THEN
    RAISE EXCEPTION 'Urgent-pass request linkage is incomplete';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='session_no_shows'
      AND column_name='reported_by'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='session_no_shows'
      AND column_name='review_status'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='session_no_shows'
      AND column_name='reviewed_by'
  ) THEN
    RAISE EXCEPTION 'No-show review columns are incomplete';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='doubt_requests'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='session_bookings'
  ) THEN
    RAISE EXCEPTION 'Mentor Desk realtime publication membership is missing';
  END IF;
END;
$$;
