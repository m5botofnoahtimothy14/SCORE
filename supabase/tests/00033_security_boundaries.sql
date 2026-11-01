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
       'public.activate_student(uuid,text,text,uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated',
       'public.activate_student(uuid,text,text,uuid)', 'EXECUTE')
     OR has_function_privilege('anon',
       'public.activate_teacher(uuid,text,uuid,text)', 'EXECUTE')
     OR has_function_privilege('authenticated',
       'public.activate_teacher(uuid,text,uuid,text)', 'EXECUTE')
     OR has_function_privilege('anon',
       'public.tc_post_edge(text,jsonb)', 'EXECUTE')
     OR has_function_privilege('authenticated',
       'public.tc_post_edge(text,jsonb)', 'EXECUTE')
     OR has_function_privilege('anon',
       'public.publish_due_announcements()', 'EXECUTE')
     OR has_function_privilege('authenticated',
       'public.publish_due_announcements()', 'EXECUTE') THEN
    RAISE EXCEPTION 'A service-only RPC is executable by a client role';
  END IF;

  IF has_function_privilege('anon',
       'public.create_student_support_conversation(uuid,uuid,uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated',
       'public.create_student_support_conversation(uuid,uuid,uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('anon',
       'public.rls_auto_enable()', 'EXECUTE')
     OR has_function_privilege('authenticated',
       'public.rls_auto_enable()', 'EXECUTE') THEN
    RAISE EXCEPTION 'An internal helper is executable by a client role';
  END IF;

  IF has_function_privilege('anon',
       'public.register_notification_device(uuid,text,text,text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated',
       'public.register_notification_device(uuid,text,text,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Notification registration is not restricted to authenticated users';
  END IF;

  IF has_function_privilege('anon',
       'public.send_message(uuid,uuid,text,text,uuid,uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated',
       'public.send_message(uuid,uuid,text,text,uuid,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Message RPC permissions are incorrect';
  END IF;

  IF has_function_privilege('anon',
       'public.issue_student_code(uuid,text,integer)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated',
       'public.issue_student_code(uuid,text,integer)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Student activation-code issuance is not authenticated/admin-only';
  END IF;

  IF has_table_privilege('anon', 'public.session_bookings', 'SELECT')
     OR has_table_privilege('anon', 'public.session_google_meet_links', 'SELECT')
     OR has_table_privilege('anon', 'public.google_meet_config', 'SELECT') THEN
    RAISE EXCEPTION 'Anonymous users can read booking or Google Meet records';
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
