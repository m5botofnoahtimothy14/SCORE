-- Migration 00036 — Leadership/SLT read access fixes
-- Ensures SLT (head_teacher, principal, school_admin) can read all
-- doubt_requests, session_bookings, and mentor_availability for their school.

-- ── SLT read access to doubt_requests ──
DO $$ BEGIN
  DROP POLICY IF EXISTS doubt_requests_slt_read ON public.doubt_requests;
  CREATE POLICY doubt_requests_slt_read ON public.doubt_requests FOR SELECT
    USING (
      public.tc_has_school_role(school_id, 'head_teacher')
      OR public.tc_is_school_admin(school_id)
    );
END $$;

-- ── SLT read access to session_bookings ──
DO $$ BEGIN
  DROP POLICY IF EXISTS session_bookings_slt_read ON public.session_bookings;
  CREATE POLICY session_bookings_slt_read ON public.session_bookings FOR SELECT
    USING (
      public.tc_has_school_role(school_id, 'head_teacher')
      OR public.tc_is_school_admin(school_id)
    );
END $$;

-- ── SLT read access to mentor_availability ──
DO $$ BEGIN
  DROP POLICY IF EXISTS mentor_availability_slt_read ON public.mentor_availability;
  CREATE POLICY mentor_availability_slt_read ON public.mentor_availability FOR SELECT
    USING (
      public.tc_has_school_role(school_id, 'head_teacher')
      OR public.tc_is_school_admin(school_id)
    );
END $$;

-- ── SLT read access to session_no_shows ──
DO $$ BEGIN
  DROP POLICY IF EXISTS session_no_shows_slt_read ON public.session_no_shows;
  CREATE POLICY session_no_shows_slt_read ON public.session_no_shows FOR SELECT
    USING (
      public.tc_has_school_role(
        (SELECT school_id FROM public.session_bookings WHERE id = session_no_shows.booking_id),
        'head_teacher'
      )
      OR public.tc_is_school_admin(
        (SELECT school_id FROM public.session_bookings WHERE id = session_no_shows.booking_id)
      )
    );
END $$;