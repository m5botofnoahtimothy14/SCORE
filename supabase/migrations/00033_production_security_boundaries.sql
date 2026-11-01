-- ============================================================
-- 00033: production security boundary repair
--
-- This migration closes client access to activation secrets and
-- service-only RPCs. It also restores participant-only read access
-- to Mentor Desk bookings. It does not delete application records.
-- Apply only after migrations 00027-00032 have been reviewed/applied.
-- ============================================================

-- 1. Remove every client policy and table grant from activation material.
-- OTP hashes and activation hashes must only be read by trusted Edge Functions.
DO $$
DECLARE
  v_table text;
  v_policy record;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'student_activation_credentials',
    'teacher_activation_credentials',
    'staff_activation_records'
  ] LOOP
    FOR v_policy IN
      SELECT policyname
      FROM pg_policies
      WHERE schemaname = 'public' AND tablename = v_table
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', v_policy.policyname, v_table);
    END LOOP;
    EXECUTE format(
      'REVOKE ALL ON TABLE public.%I FROM PUBLIC, anon, authenticated',
      v_table
    );
    EXECUTE format('GRANT ALL ON TABLE public.%I TO service_role', v_table);
  END LOOP;
END;
$$;

-- 2. SECURITY DEFINER is not a reason to expose a function to every API role.
-- Default: revoke all client execution and retain service-role execution.
DO $$
DECLARE
  v_function record;
BEGIN
  FOR v_function IN
    SELECT p.oid
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef = true
      AND p.prokind = 'f'
  LOOP
    EXECUTE format(
      'REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated',
      v_function.oid::regprocedure
    );
    EXECUTE format(
      'GRANT EXECUTE ON FUNCTION %s TO service_role',
      v_function.oid::regprocedure
    );
  END LOOP;
END;
$$;

-- 3. Explicit allowlist for RPCs that are designed for authenticated clients.
-- Every entry is schema-qualified and resolved safely. Missing optional
-- functions are skipped so this migration remains compatible with minor
-- migration-history differences.
DO $$
DECLARE
  v_signature text;
  v_function regprocedure;
BEGIN
  FOREACH v_signature IN ARRAY ARRAY[
    'public.deactivate_notification_device(text)',
    'public.issue_student_code(uuid,text,integer)',
    'public.mark_conversation_read(uuid)',
    'public.reassign_student_class(uuid,uuid,text)',
    'public.send_message(uuid,uuid,text,text,uuid,uuid)',
    'public.set_staff_active(uuid,boolean)',
    'public.set_student_active(uuid,boolean)',
    'public.start_teacher_conversation(uuid)',
    'public.touch_my_presence()',

    -- SECURITY DEFINER helpers used by authenticated RLS policies.
    'public.tc_can_read_attachment(uuid,uuid)',
    'public.tc_has_school_role(uuid,public.school_role)',
    'public.tc_is_announcement_recipient(uuid)',
    'public.tc_is_booking_participant(uuid)',
    'public.tc_is_conversation_member(uuid)',
    'public.tc_is_platform_owner()',
    'public.tc_is_school_admin(uuid)',
    'public.tc_is_student_in_my_class(uuid)',
    'public.tc_my_student_id(uuid)',
    'public.tc_my_student_ids()',
    'public.tc_my_taught_class_ids()',
    'public.tc_my_teacher_id(uuid)',
    'public.tc_school_id_of_announcement(uuid)',
    'public.tc_taught_student_ids()',
    'public.tc_user_school_ids()',

    -- Participant-only Meet link retrieval.
    'public.get_google_meet_link(uuid)'
  ] LOOP
    v_function := to_regprocedure(v_signature);
    IF v_function IS NOT NULL THEN
      EXECUTE format(
        'GRANT EXECUTE ON FUNCTION %s TO authenticated',
        v_function
      );
    END IF;
  END LOOP;
END;
$$;

-- 4. Explicitly document sensitive RPCs as service-role-only.
-- The broad revocation above already enforces this. These statements make
-- the critical boundary obvious during future reviews.
DO $$
DECLARE
  v_signature text;
  v_function regprocedure;
BEGIN
  FOREACH v_signature IN ARRAY ARRAY[
    'public.activate_student(uuid,text,text,uuid)',
    'public.activate_teacher(uuid,text,uuid,text)',
    'public.bootstrap_platform_owner(text,text,text)',
    'public.tc_post_edge(text,jsonb)',
    'public.publish_due_announcements()',
    'public.activate_student_verified(text,text,uuid)',
    'public.activate_teacher_verified(text,text,uuid)',
    'public.claim_google_meet_creation(uuid,uuid)',
    'public.store_google_meet_credentials(uuid,uuid,text,text)'
  ] LOOP
    v_function := to_regprocedure(v_signature);
    IF v_function IS NOT NULL THEN
      EXECUTE format(
        'REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated',
        v_function
      );
      EXECUTE format(
        'GRANT EXECUTE ON FUNCTION %s TO service_role',
        v_function
      );
    END IF;
  END LOOP;
END;
$$;

-- 5. Meeting booking records are visible to the booked student, assigned
-- teacher, or a school administrator. Clients cannot write booking rows
-- directly; state changes must use the guarded RPCs.
ALTER TABLE public.session_bookings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS session_bookings_participant ON public.session_bookings;
DROP POLICY IF EXISTS session_bookings_admin ON public.session_bookings;
DROP POLICY IF EXISTS session_bookings_participant_read ON public.session_bookings;

CREATE POLICY session_bookings_participant_read
  ON public.session_bookings
  FOR SELECT
  TO authenticated
  USING (
    student_id = auth.uid()
    OR mentor_id = auth.uid()
    OR public.tc_is_school_admin(school_id)
  );

REVOKE INSERT, UPDATE, DELETE ON public.session_bookings FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.session_bookings TO authenticated;
GRANT ALL ON public.session_bookings TO service_role;

-- 6. The Meet link table is also participant-only. The helper checks the
-- booking is confirmed/in progress and the caller is one of its participants.
ALTER TABLE public.session_google_meet_links ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS session_google_meet_links_participants
  ON public.session_google_meet_links;
CREATE POLICY session_google_meet_links_participants
  ON public.session_google_meet_links
  FOR SELECT
  TO authenticated
  USING (public.tc_is_booking_participant(booking_id));

REVOKE ALL ON public.session_google_meet_links FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.session_google_meet_links TO authenticated;
GRANT ALL ON public.session_google_meet_links TO service_role;

-- 7. Google Workspace configuration contains no token value. Only school
-- administrators can manage the config row; the refresh token stays in Vault.
ALTER TABLE public.google_meet_config ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS google_meet_config_school_admin
  ON public.google_meet_config;
CREATE POLICY google_meet_config_school_admin
  ON public.google_meet_config
  FOR ALL
  TO authenticated
  USING (public.tc_is_school_admin(school_id))
  WITH CHECK (public.tc_is_school_admin(school_id));

REVOKE ALL ON public.google_meet_config FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.google_meet_config TO authenticated;
GRANT ALL ON public.google_meet_config TO service_role;
