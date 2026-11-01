-- ============================================================
-- 00034: reconcile Mentor Desk tables created before schema redesign.
--
-- Earlier CREATE TABLE IF NOT EXISTS migrations did not add columns
-- to pre-existing partial tables. Live audit found doubt_requests
-- contained only id/school_id and doubt_status_history used legacy
-- column names. Both tables currently contain zero rows. This migration
-- is additive and retains all legacy columns.
-- ============================================================

-- Mentor Desk threads use a dedicated conversation type.
ALTER TYPE public.conversation_type ADD VALUE IF NOT EXISTS 'mentor_desk';

-- Extend legacy enums to the state model used by the current app.
ALTER TYPE public.booking_status ADD VALUE IF NOT EXISTS 'cancelled_by_student';
ALTER TYPE public.booking_status ADD VALUE IF NOT EXISTS 'cancelled_by_mentor';
ALTER TYPE public.booking_status ADD VALUE IF NOT EXISTS 'no_show_student';
ALTER TYPE public.booking_status ADD VALUE IF NOT EXISTS 'no_show_mentor';
ALTER TYPE public.booking_status ADD VALUE IF NOT EXISTS 'unverified_closed';

-- Current policy functions use weekly_doubt_allowance. Keep the newer
-- open_doubt_limit column intact; both remain available during transition.
ALTER TABLE public.mentor_desk_settings
  ADD COLUMN IF NOT EXISTS weekly_doubt_allowance integer NOT NULL DEFAULT 3;

-- Rebuild the incomplete doubt request row shape. The live table was empty
-- when audited, so required fields can be added without fabricating records.
ALTER TABLE public.doubt_requests
  ADD COLUMN IF NOT EXISTS conversation_id uuid REFERENCES public.conversations(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS student_id uuid REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS student_record_id uuid REFERENCES public.students(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS class_id uuid REFERENCES public.classes(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS subject_id uuid REFERENCES public.subjects(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS question text,
  ADD COLUMN IF NOT EXISTS chapter text,
  ADD COLUMN IF NOT EXISTS question_number text,
  ADD COLUMN IF NOT EXISTS explanation text,
  ADD COLUMN IF NOT EXISTS previous_attempts text,
  ADD COLUMN IF NOT EXISTS urgent boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS urgent_reason text,
  ADD COLUMN IF NOT EXISTS urgent_pass_used boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'waiting',
  ADD COLUMN IF NOT EXISTS assigned_mentor_id uuid REFERENCES public.user_profiles(id),
  ADD COLUMN IF NOT EXISTS assigned_teacher_id uuid REFERENCES public.teachers(id),
  ADD COLUMN IF NOT EXISTS named_mentor boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS first_reply_at timestamptz,
  ADD COLUMN IF NOT EXISTS resolved_at timestamptz,
  ADD COLUMN IF NOT EXISTS closed_at timestamptz,
  ADD COLUMN IF NOT EXISTS idempotency_key uuid,
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- Keep the status contract as TEXT. The earlier learning migration used TEXT,
-- while the older schema also contains an unused doubt_status enum.
ALTER TABLE public.doubt_requests
  ALTER COLUMN status DROP DEFAULT,
  ALTER COLUMN status TYPE text USING status::text;
UPDATE public.doubt_requests
SET status = CASE status
  WHEN 'waiting' THEN 'pending_assignment'
  WHEN 'resolved' THEN 'answered'
  ELSE status
END;
ALTER TABLE public.doubt_requests
  ALTER COLUMN status SET DEFAULT 'pending_assignment',
  ALTER COLUMN status SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.doubt_requests'::regclass
      AND conname = 'doubt_requests_status_recovery_check'
  ) THEN
    ALTER TABLE public.doubt_requests
      ADD CONSTRAINT doubt_requests_status_recovery_check
      CHECK (status IN ('submitted','pending_assignment','assigned','in_progress','answered','closed','reopened'));
  END IF;
END;
$$;

-- Do not permit a partially populated doubt request to enter the new API.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.doubt_requests
    WHERE conversation_id IS NULL OR student_id IS NULL
       OR student_record_id IS NULL OR subject_id IS NULL
       OR question IS NULL OR length(trim(question)) = 0
  ) THEN
    RAISE EXCEPTION 'doubt_requests contains legacy rows that need an explicit backfill';
  END IF;
END;
$$;

ALTER TABLE public.doubt_requests
  ALTER COLUMN conversation_id SET NOT NULL,
  ALTER COLUMN student_id SET NOT NULL,
  ALTER COLUMN student_record_id SET NOT NULL,
  ALTER COLUMN subject_id SET NOT NULL,
  ALTER COLUMN question SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_doubt_requests_student_status
  ON public.doubt_requests(student_id, status);
CREATE INDEX IF NOT EXISTS idx_doubt_requests_subject_status
  ON public.doubt_requests(subject_id, status);
CREATE INDEX IF NOT EXISTS idx_doubt_requests_assigned_mentor
  ON public.doubt_requests(assigned_mentor_id)
  WHERE assigned_mentor_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_doubt_requests_idempotency
  ON public.doubt_requests(student_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

-- Preserve legacy history columns while adding the names used by the current
-- RPC contract. Existing rows are mapped where possible.
ALTER TABLE public.doubt_status_history
  ADD COLUMN IF NOT EXISTS actor_id uuid REFERENCES public.user_profiles(id),
  ADD COLUMN IF NOT EXISTS from_status text,
  ADD COLUMN IF NOT EXISTS to_status text,
  ADD COLUMN IF NOT EXISTS reason text,
  ADD COLUMN IF NOT EXISTS created_at timestamptz;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='doubt_status_history' AND column_name='changed_by') THEN
    EXECUTE 'UPDATE public.doubt_status_history SET actor_id = COALESCE(actor_id, changed_by)'
    ;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='doubt_status_history' AND column_name='old_status') THEN
    EXECUTE 'UPDATE public.doubt_status_history SET from_status = COALESCE(from_status, old_status::text)'
    ;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='doubt_status_history' AND column_name='new_status') THEN
    EXECUTE 'UPDATE public.doubt_status_history SET to_status = COALESCE(to_status, new_status::text)'
    ;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='doubt_status_history' AND column_name='changed_at') THEN
    EXECUTE 'UPDATE public.doubt_status_history SET created_at = COALESCE(created_at, changed_at, now())'
    ;
  ELSE
    UPDATE public.doubt_status_history SET created_at = COALESCE(created_at, now());
  END IF;
END;
$$;

ALTER TABLE public.doubt_status_history
  ALTER COLUMN created_at SET DEFAULT now(),
  ALTER COLUMN created_at SET NOT NULL;
CREATE INDEX IF NOT EXISTS idx_doubt_status_history_request_created
  ON public.doubt_status_history(request_id, created_at DESC);

-- Explicit subject enrolment. The live database did not contain this table,
-- while migration 00023 defines it. Recreate the intended table shape and seed
-- only subjects assigned to each student's active class.
CREATE TABLE IF NOT EXISTS public.student_subject_enrollments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  class_id uuid NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  subject_id uuid NOT NULL REFERENCES public.subjects(id) ON DELETE CASCADE,
  assigned_by uuid REFERENCES public.user_profiles(id),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(student_id, subject_id)
);

CREATE INDEX IF NOT EXISTS student_subject_enrollment_lookup
  ON public.student_subject_enrollments(student_id, active, subject_id);

INSERT INTO public.student_subject_enrollments(
  school_id, student_id, class_id, subject_id, active
)
SELECT DISTINCT ce.school_id, ce.student_id, ce.class_id, ta.subject_id, true
FROM public.class_enrollments ce
JOIN public.classes c ON c.id = ce.class_id AND c.is_active = true
JOIN public.teaching_assignments ta
  ON ta.class_id = ce.class_id
 AND ta.school_id = ce.school_id
WHERE ce.unenrolled_at IS NULL
  AND ta.subject_id IS NOT NULL
ON CONFLICT (student_id, subject_id) DO NOTHING;

DO $$
DECLARE
  v_policy record;
BEGIN
  FOR v_policy IN
    SELECT policyname FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'student_subject_enrollments'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.student_subject_enrollments', v_policy.policyname);
  END LOOP;
END;
$$;

ALTER TABLE public.student_subject_enrollments ENABLE ROW LEVEL SECURITY;

CREATE POLICY student_subject_enrollment_read
  ON public.student_subject_enrollments FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.students s
      WHERE s.id = student_id AND s.user_id = auth.uid()
    )
    OR public.tc_is_school_admin(school_id)
    OR EXISTS (
      SELECT 1 FROM public.teachers t
      JOIN public.teaching_assignments ta ON ta.teacher_id = t.id
      WHERE t.user_id = auth.uid()
        AND t.is_active
        AND ta.class_id = student_subject_enrollments.class_id
        AND ta.subject_id = student_subject_enrollments.subject_id
    )
  );

CREATE POLICY student_subject_enrollment_admin
  ON public.student_subject_enrollments FOR ALL TO authenticated
  USING (public.tc_is_school_admin(school_id))
  WITH CHECK (public.tc_is_school_admin(school_id));

GRANT SELECT, INSERT, UPDATE, DELETE
  ON public.student_subject_enrollments TO authenticated;

-- Extend the no-show table while retaining any older recorded_by/recorded_at fields.
ALTER TABLE public.session_no_shows
  ADD COLUMN IF NOT EXISTS school_id uuid REFERENCES public.schools(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS reported_by uuid REFERENCES public.user_profiles(id),
  ADD COLUMN IF NOT EXISTS reported_by_role text,
  ADD COLUMN IF NOT EXISTS refund_minutes integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS review_status text NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS reason text,
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='session_no_shows' AND column_name='recorded_by')
     AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='session_no_shows' AND column_name='recorded_at') THEN
    EXECUTE $sql$
      UPDATE public.session_no_shows ns
      SET school_id = COALESCE(ns.school_id, sb.school_id),
          reported_by = COALESCE(ns.reported_by, ns.recorded_by),
          reported_by_role = COALESCE(ns.reported_by_role,
            CASE WHEN ns.recorded_by = sb.student_id THEN 'student'
                 WHEN ns.recorded_by = sb.mentor_id THEN 'mentor' ELSE NULL END),
          created_at = COALESCE(ns.created_at, ns.recorded_at, now())
      FROM public.session_bookings sb
      WHERE sb.id = ns.booking_id
    $sql$;
  END IF;
END;
$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.session_no_shows
    WHERE school_id IS NULL OR reported_by IS NULL OR reported_by_role IS NULL
  ) THEN
    RAISE EXCEPTION 'session_no_shows contains legacy rows without complete reporter context';
  END IF;
END;
$$;
ALTER TABLE public.session_no_shows
  ALTER COLUMN school_id SET NOT NULL,
  ALTER COLUMN reported_by SET NOT NULL,
  ALTER COLUMN reported_by_role SET NOT NULL;

ALTER TABLE public.mentor_subject_approvals
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();
-- The urgent-pass ledger is one row per student/subject/week. Add the
-- request link and a canonical consumption timestamp while retaining used_at.
ALTER TABLE public.urgent_pass_usage
  ADD COLUMN IF NOT EXISTS request_id uuid REFERENCES public.doubt_requests(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS consumed_at timestamptz;

UPDATE public.urgent_pass_usage
SET consumed_at = COALESCE(consumed_at, used_at, now())
WHERE consumed_at IS NULL;

ALTER TABLE public.urgent_pass_usage
  ALTER COLUMN consumed_at SET DEFAULT now(),
  ALTER COLUMN consumed_at SET NOT NULL;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.urgent_pass_usage WHERE request_id IS NULL) THEN
    RAISE EXCEPTION 'urgent_pass_usage contains legacy rows without a linked doubt request';
  END IF;
END;
$$;
ALTER TABLE public.urgent_pass_usage ALTER COLUMN request_id SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_urgent_pass_usage_request
  ON public.urgent_pass_usage(request_id);

-- Extend the no-show review record without removing the legacy reporter fields.
ALTER TABLE public.session_no_shows
  ADD COLUMN IF NOT EXISTS refunded boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS reviewed_by uuid REFERENCES public.user_profiles(id),
  ADD COLUMN IF NOT EXISTS reviewed_at timestamptz;

-- Add salted, expiring verification-code storage to the existing booking
-- row. Existing legacy verification_code data is not copied into OTP fields.
ALTER TABLE public.session_bookings
  ADD COLUMN IF NOT EXISTS otp_hash text,
  ADD COLUMN IF NOT EXISTS otp_salt text,
  ADD COLUMN IF NOT EXISTS otp_hash_expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS otp_issued_at timestamptz,
  ADD COLUMN IF NOT EXISTS otp_resend_count integer NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.session_bookings.otp_hash IS
  'Salted SHA-256 hash of the one-time session closure code. Never store plaintext.';
COMMENT ON COLUMN public.session_bookings.otp_salt IS
  'Per-code random salt used to verify otp_hash.';

-- Publish the restored Mentor Desk tables for Supabase Realtime. Add only
-- tables that are not already members of the publication.
DO $$
DECLARE
  v_table text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;

  FOREACH v_table IN ARRAY ARRAY[
    'doubt_requests','session_bookings','mentor_availability','ratings',
    'announcements','messages','background_jobs'
  ] LOOP
    IF to_regclass('public.' || v_table) IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM pg_publication_tables
         WHERE pubname = 'supabase_realtime'
           AND schemaname = 'public'
           AND tablename = v_table
       ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', v_table);
    END IF;
  END LOOP;
END;
$$;
