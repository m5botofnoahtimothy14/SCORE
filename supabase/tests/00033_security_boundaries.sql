-- Regression checks for migration 00033.
-- Run after applying migrations 00027-00033 in a non-production test project.
DO $$
BEGIN
  IF has_table_privilege('anon', 'public.student_activation_credentials', 'SELECT')
     OR has_table_privilege('authenticated', 'public.student_activation_credentials', 'SELECT')
     OR has_table_privilege('anon', 'public.teacher_activation_credentials', 'SELECT')
     OR has_table_privilege('authenticated', 'public.teacher_activation_credentials', 'SELECT')
     OR has_table_privilege('anon', 'public.staff_activation_records', 'SELECT')
     OR has_table_privilege('authenticated', 'public.staff_activation_records', 'SELECT') THEN
    RAISE EXCEPTION 'Activation credential tables are readable by a client role';
  END IF;

  IF has_function_privilege('anon',
       'public.bootstrap_platform_owner(text,text,text)', 'EXECUTE')
     OR has_function_privilege('authenticated',
       'public.bootstrap_platform_owner(text,text,text)', 'EXECUTE')
     OR has_function_privilege('anon',
       'public.tc_post_edge(text,jsonb)', 'EXECUTE')
     OR has_function_privilege('authenticated',
       'public.tc_post_edge(text,jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION 'A service-only RPC is executable by a client role';
  END IF;

  IF NOT has_function_privilege('authenticated',
       'public.get_google_meet_link(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Authenticated users cannot call the participant-checked Meet RPC';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'session_bookings'
      AND policyname = 'session_bookings_participant_read'
      AND cmd = 'SELECT'
  ) THEN
    RAISE EXCEPTION 'Participant SELECT policy is missing from session_bookings';
  END IF;

  IF has_table_privilege('authenticated', 'public.session_bookings', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.session_bookings', 'DELETE') THEN
    RAISE EXCEPTION 'Clients can mutate session_bookings directly';
  END IF;
END;
$$;
