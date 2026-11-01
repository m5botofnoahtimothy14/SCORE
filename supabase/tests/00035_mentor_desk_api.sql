-- Mentor Desk API regression checks.
-- Run after migrations 00034 and 00035 in a non-production project.
DO $$
DECLARE
  v_signature text;
  v_function regprocedure;
  v_table text;
BEGIN
  FOREACH v_signature IN ARRAY ARRAY[
    'public.submit_doubt(uuid,text,text,text,text,text,boolean,text,uuid[],uuid)',
    'public.claim_doubt(uuid)',
    'public.reply_doubt(uuid,text,uuid)',
    'public.resolve_doubt(uuid)',
    'public.close_doubt(uuid,text)',
    'public.reopen_doubt(uuid)',
    'public.book_session(uuid,uuid,integer,timestamp with time zone,text,text,uuid[])',
    'public.confirm_session(uuid,timestamp with time zone,integer,text,text)',
    'public.cancel_session(uuid,uuid)',
    'public.start_teacher_session(uuid)',
    'public.generate_verification_code(uuid)',
    'public.verify_session_code(uuid,text)',
    'public.close_session_without_code(uuid,text)',
    'public.record_no_show(uuid,text,text)',
    'public.set_mentor_availability(public.availability_status)',
    'public.approve_mentor_subject(uuid,uuid,boolean)',
    'public.submit_rating(uuid,integer,text)',
    'public.submit_mentor_assessment(uuid,public.engagement_scale,public.engagement_scale,text)',
    'public.get_student_learning_allowances()',
    'public.student_learning_context()'
  ] LOOP
    v_function := to_regprocedure(v_signature);
    IF v_function IS NULL THEN
      RAISE EXCEPTION 'Missing Mentor Desk RPC: %', v_signature;
    END IF;
    IF NOT has_function_privilege('authenticated', v_function, 'EXECUTE') THEN
      RAISE EXCEPTION 'Authenticated role cannot execute Mentor Desk RPC: %', v_signature;
    END IF;
    IF has_function_privilege('anon', v_function, 'EXECUTE') THEN
      RAISE EXCEPTION 'Anonymous role can execute Mentor Desk RPC: %', v_signature;
    END IF;
  END LOOP;

  FOREACH v_table IN ARRAY ARRAY[
    'doubt_requests',
    'doubt_status_history',
    'ratings',
    'mentor_assessments',
    'mentor_availability',
    'mentor_subject_approvals',
    'allowance_transactions',
    'urgent_pass_usage',
    'session_no_shows',
    'mentor_desk_settings',
    'session_bookings'
  ] LOOP
    IF NOT (
      SELECT c.relrowsecurity
      FROM pg_class c
      WHERE c.oid = ('public.' || v_table)::regclass
    ) THEN
      RAISE EXCEPTION 'RLS is disabled for public.%', v_table;
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_policies p
      WHERE p.schemaname = 'public' AND p.tablename = v_table
    ) THEN
      RAISE EXCEPTION 'No RLS policy exists for public.%', v_table;
    END IF;
  END LOOP;

  IF has_table_privilege('authenticated', 'public.session_bookings', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.session_bookings', 'DELETE') THEN
    RAISE EXCEPTION 'Authenticated clients can mutate session_bookings directly';
  END IF;

  IF to_regclass('public.student_subject_enrollments') IS NULL THEN
    RAISE EXCEPTION 'Student subject enrolment compatibility view is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='session_bookings' AND column_name='otp_hash'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='session_bookings' AND column_name='otp_hash_expires_at'
  ) THEN
    RAISE EXCEPTION 'Session OTP hash storage columns are missing';
  END IF;
END;
$$;
