-- ============================================================
-- 00034: reconcile Mentor Desk tables created before schema redesign.
--
-- Earlier CREATE TABLE IF NOT EXISTS migrations did not add columns
-- to pre-existing partial tables. Live audit found doubt_requests
-- contained only id/school_id and doubt_status_history used legacy
-- column names. Both tables currently contain zero rows. This migration
-- is additive and retains all legacy columns.
-- ============================================================

-- Extend legacy enums to the state model used by the current app.
ALTER TYPE public.doubt_status ADD VALUE IF NOT EXISTS 'pending_assignment';
ALTER TYPE public.doubt_status ADD VALUE IF NOT EXISTS 'in_progress';
ALTER TYPE public.doubt_status ADD VALUE IF NOT EXISTS 'answered';
ALTER TYPE public.doubt_status ADD VALUE IF NOT EXISTS 'reopened';

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
  ADD COLUMN IF NOT EXISTS status public.doubt_status NOT NULL DEFAULT 'waiting',
  ADD COLUMN IF NOT EXISTS assigned_mentor_id uuid REFERENCES public.user_profiles(id),
  ADD COLUMN IF NOT EXISTS assigned_teacher_id uuid REFERENCES public.teachers(id),
  ADD COLUMN IF NOT EXISTS named_mentor boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS first_reply_at timestamptz,
  ADD COLUMN IF NOT EXISTS resolved_at timestamptz,
  ADD COLUMN IF NOT EXISTS closed_at timestamptz,
  ADD COLUMN IF NOT EXISTS idempotency_key uuid,
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

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
  ADD COLUMN IF NOT EXISTS from_status public.doubt_status,
  ADD COLUMN IF NOT EXISTS to_status public.doubt_status,
  ADD COLUMN IF NOT EXISTS reason text,
  ADD COLUMN IF NOT EXISTS created_at timestamptz;

UPDATE public.doubt_status_history
SET actor_id = COALESCE(actor_id, changed_by),
    from_status = COALESCE(
      from_status,
      CASE WHEN old_status IN ('waiting', 'assigned', 'resolved', 'closed')
        THEN old_status::public.doubt_status ELSE NULL END
    ),
    to_status = COALESCE(
      to_status,
      CASE WHEN new_status IN ('waiting', 'assigned', 'resolved', 'closed')
        THEN new_status::public.doubt_status ELSE NULL END
    ),
    created_at = COALESCE(created_at, changed_at, now());

ALTER TABLE public.doubt_status_history
  ALTER COLUMN created_at SET DEFAULT now(),
  ALTER COLUMN created_at SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_doubt_status_history_request_created
  ON public.doubt_status_history(request_id, created_at DESC);

-- Compatibility relation used by the booking RPC. Subject enrolment is
-- derived from the student's active class enrolment and that class's
-- teacher/subject assignments; no second source of truth is introduced.
CREATE OR REPLACE VIEW public.student_subject_enrollments
WITH (security_invoker = true)
AS
SELECT DISTINCT ce.student_id, ce.class_id, ta.subject_id, true AS active
FROM public.class_enrollments ce
JOIN public.teaching_assignments ta
  ON ta.class_id = ce.class_id
 AND ta.school_id = ce.school_id
WHERE ce.unenrolled_at IS NULL
  AND ta.subject_id IS NOT NULL;

REVOKE ALL ON public.student_subject_enrollments FROM PUBLIC, anon, authenticated;

-- Older no-show rows use recorded_by/recorded_at. Add the current
-- review fields without removing the legacy audit columns.
ALTER TABLE public.session_no_shows
  ADD COLUMN IF NOT EXISTS school_id uuid REFERENCES public.schools(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS reported_by uuid REFERENCES public.user_profiles(id),
  ADD COLUMN IF NOT EXISTS reported_by_role text,
  ADD COLUMN IF NOT EXISTS refund_minutes integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS review_status text NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS reason text,
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();

UPDATE public.session_no_shows ns
SET school_id = COALESCE(ns.school_id, sb.school_id),
    reported_by = COALESCE(ns.reported_by, ns.recorded_by),
    reported_by_role = COALESCE(
      ns.reported_by_role,
      CASE WHEN ns.recorded_by = sb.student_id THEN 'student'
           WHEN ns.recorded_by = sb.mentor_id THEN 'mentor'
           ELSE NULL END
    ),
    created_at = COALESCE(ns.created_at, ns.recorded_at, now())
FROM public.session_bookings sb
WHERE sb.id = ns.booking_id;

ALTER TABLE public.mentor_subject_approvals
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

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
