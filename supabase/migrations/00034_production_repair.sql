-- ============================================================
-- Migration 00034 — Production Repair (safe, incremental, no drops)
-- ============================================================
-- Repairs schema drift and conflicting definitions so the
-- mobile edge functions and Flutter app work in production.
-- All statements are idempotent (ADD COLUMN IF NOT EXISTS,
-- CREATE OR REPLACE FUNCTION). No tables are dropped.
-- ============================================================

-- ── 1. student_activation_credentials: ensure both code and
--    code_hash/code_salt columns exist. The edge function reads
--    `code` and accepts both bcrypt ($2a/$2b) and SHA-256 hex.
ALTER TABLE public.student_activation_credentials
  ADD COLUMN IF NOT EXISTS code TEXT,
  ADD COLUMN IF NOT EXISTS code_hash TEXT,
  ADD COLUMN IF NOT EXISTS code_salt TEXT;

-- Backfill code_hash from code where code looks like a SHA-256 hex
-- and code_hash is null, so the 00029 RPC path also works.
UPDATE public.student_activation_credentials
SET code_hash = code
WHERE code_hash IS NULL
  AND code IS NOT NULL
  AND length(code) = 64
  AND code ~ '^[0-9a-f]{64}$';

-- ── 2. activate_teacher: restore the 4-param signature that
--    the verify-otp edge function calls:
--    (p_school_id, p_staff_id_no, p_auth_user_id, p_phone)
--    Migration 00029 overwrote this with a 3-param version.
CREATE OR REPLACE FUNCTION public.activate_teacher(
  p_school_id UUID,
  p_staff_id_no TEXT,
  p_auth_user_id UUID,
  p_phone TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_teacher teachers%ROWTYPE;
BEGIN
  SELECT * INTO v_teacher
  FROM teachers
  WHERE school_id = p_school_id
    AND staff_id_no = p_staff_id_no
    AND is_active = TRUE
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'teacher_not_found');
  END IF;

  -- Anti-impersonation: phone must match roster
  IF v_teacher.phone IS DISTINCT FROM p_phone THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_credentials');
  END IF;

  -- Create profile FIRST (teachers.user_id FK -> user_profiles.id)
  INSERT INTO user_profiles(id, display_name, phone, is_active)
  VALUES (p_auth_user_id, v_teacher.first_name || ' ' || v_teacher.last_name, p_phone, TRUE)
  ON CONFLICT (id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    phone = EXCLUDED.phone,
    is_active = TRUE,
    updated_at = NOW();

  -- Link auth user to teacher record
  UPDATE teachers
  SET user_id = p_auth_user_id, updated_at = NOW()
  WHERE id = v_teacher.id AND user_id IS NULL;

  -- Create school membership
  INSERT INTO school_memberships(user_id, school_id, role, is_active, joined_at)
  VALUES (
    p_auth_user_id,
    p_school_id,
    (CASE WHEN v_teacher.is_leadership THEN 'head_teacher' ELSE 'teacher' END)::school_role,
    TRUE,
    NOW()
  )
  ON CONFLICT (user_id, school_id, role) DO UPDATE SET
    is_active = TRUE,
    joined_at = NOW();

  RETURN jsonb_build_object(
    'success', TRUE,
    'teacher_id', v_teacher.id,
    'school_id', v_teacher.school_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.activate_teacher(UUID, TEXT, UUID, TEXT) TO authenticated;

-- ── 3. session_bookings: ensure all OTP / Google Meet / status
--    columns exist (from 00023, 00024, 00025). Idempotent.
ALTER TABLE public.session_bookings
  ADD COLUMN IF NOT EXISTS class_id UUID REFERENCES public.classes(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS reserved_minutes INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS actual_minutes INTEGER,
  ADD COLUMN IF NOT EXISTS started_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS ended_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS otp_hash TEXT,
  ADD COLUMN IF NOT EXISTS otp_salt TEXT,
  ADD COLUMN IF NOT EXISTS otp_hash_expires_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS otp_resend_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS code_attempts INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS code_locked_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS verification_code TEXT,
  ADD COLUMN IF NOT EXISTS code_expires_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS code_visible_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS google_meet_link TEXT,
  ADD COLUMN IF NOT EXISTS google_calendar_event_id TEXT,
  ADD COLUMN IF NOT EXISTS google_meet_created_at TIMESTAMPTZ;

-- Backfill reserved_minutes from allowance_minutes_used where zero.
UPDATE public.session_bookings SET reserved_minutes = allowance_minutes_used WHERE reserved_minutes = 0;

-- ── 4. doubt_requests: ensure all columns exist (from 00023, 00032).
--    status is kept as TEXT (00023) with a CHECK constraint, which is
--    what the RPCs and Flutter models expect.
ALTER TABLE public.doubt_requests
  ADD COLUMN IF NOT EXISTS conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS student_id UUID REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS student_record_id UUID REFERENCES public.students(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS class_id UUID REFERENCES public.classes(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS subject_id UUID REFERENCES public.subjects(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS question TEXT,
  ADD COLUMN IF NOT EXISTS chapter TEXT,
  ADD COLUMN IF NOT EXISTS question_number TEXT,
  ADD COLUMN IF NOT EXISTS explanation TEXT,
  ADD COLUMN IF NOT EXISTS previous_attempts TEXT,
  ADD COLUMN IF NOT EXISTS urgent BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS urgent_reason TEXT,
  ADD COLUMN IF NOT EXISTS urgent_pass_used BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'pending_assignment',
  ADD COLUMN IF NOT EXISTS assigned_mentor_id UUID REFERENCES public.user_profiles(id),
  ADD COLUMN IF NOT EXISTS assigned_teacher_id UUID REFERENCES public.teachers(id),
  ADD COLUMN IF NOT EXISTS named_mentor BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS first_reply_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS resolved_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS closed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS idempotency_key UUID,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- Ensure the status column covers all values used by the app.
-- If status is an enum type, add missing values.
-- If status is TEXT, add a CHECK constraint.
DO $$
DECLARE
  v_col_type TEXT;
BEGIN
  SELECT data_type INTO v_col_type
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'doubt_requests'
    AND column_name = 'status';

  IF v_col_type = 'USER-DEFINED' THEN
    -- It's an enum type; add missing values.
    BEGIN ALTER TYPE public.doubt_status ADD VALUE IF NOT EXISTS 'submitted'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN ALTER TYPE public.doubt_status ADD VALUE IF NOT EXISTS 'pending_assignment'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN ALTER TYPE public.doubt_status ADD VALUE IF NOT EXISTS 'assigned'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN ALTER TYPE public.doubt_status ADD VALUE IF NOT EXISTS 'in_progress'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN ALTER TYPE public.doubt_status ADD VALUE IF NOT EXISTS 'answered'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN ALTER TYPE public.doubt_status ADD VALUE IF NOT EXISTS 'closed'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN ALTER TYPE public.doubt_status ADD VALUE IF NOT EXISTS 'reopened'; EXCEPTION WHEN OTHERS THEN NULL; END;
  ELSIF v_col_type = 'text' THEN
    -- It's TEXT; add CHECK constraint if missing.
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conrelid = 'public.doubt_requests'::regclass
        AND conname = 'doubt_requests_status_check'
    ) THEN
      ALTER TABLE public.doubt_requests
        ADD CONSTRAINT doubt_requests_status_check
        CHECK (status IN ('submitted','pending_assignment','assigned','in_progress','answered','closed','reopened'));
    END IF;
  END IF;
END $$;

-- ── 5. teacher_activation_credentials: ensure code / code_hash /
--    code_salt columns exist (00030 creates `code`; make sure all
--    are present for the edge function).
ALTER TABLE public.teacher_activation_credentials
  ADD COLUMN IF NOT EXISTS code TEXT,
  ADD COLUMN IF NOT EXISTS code_hash TEXT,
  ADD COLUMN IF NOT EXISTS code_salt TEXT;

-- ── 6. Recreate the activate_student RPC (00029 version) so it reads
--    from `code` (which may be bcrypt or SHA-256) and matches the
--    columns that exist after step 1.
CREATE OR REPLACE FUNCTION public.activate_student(
  p_student_id_no TEXT,
  p_activation_code TEXT,
  p_device_secret TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_student students%ROWTYPE;
  v_credential student_activation_credentials%ROWTYPE;
  v_school_id UUID;
  v_user_id UUID := auth.uid();
  v_class_id UUID;
  v_match BOOLEAN := FALSE;
BEGIN
  SELECT * INTO v_student FROM students
  WHERE student_id_no = p_student_id_no AND is_active = TRUE
  LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'student_not_found');
  END IF;
  v_school_id := v_student.school_id;

  SELECT * INTO v_credential FROM student_activation_credentials
  WHERE student_id = v_student.id
    AND used_at IS NULL AND expires_at > NOW()
  LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_credentials');
  END IF;

  -- Accept bcrypt ($2a/$2b) or SHA-256 hex codes, compared server-side.
  IF left(v_credential.code, 3) = '$2a' OR left(v_credential.code, 3) = '$2b' THEN
    v_match := (v_credential.code = crypt(p_activation_code, v_credential.code));
  ELSIF v_credential.code_hash IS NOT NULL THEN
    v_match := (v_credential.code_hash = encode(digest(p_activation_code, 'sha256'), 'hex'));
  ELSE
    v_match := (v_credential.code = encode(digest(p_activation_code, 'sha256'), 'hex'));
  END IF;

  IF NOT v_match THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_credentials');
  END IF;

  UPDATE student_activation_credentials
  SET used_at = NOW() WHERE id = v_credential.id;

  UPDATE students
  SET user_id = v_user_id, updated_at = NOW()
  WHERE id = v_student.id AND user_id IS NULL;

  INSERT INTO user_profiles(id, display_name, is_active, created_at, updated_at)
  VALUES (v_user_id, v_student.first_name || ' ' || v_student.last_name, TRUE, NOW(), NOW())
  ON CONFLICT (id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    is_active = TRUE,
    updated_at = NOW();

  INSERT INTO school_memberships(user_id, school_id, role, is_active, joined_at)
  VALUES (v_user_id, v_school_id, 'student', TRUE, NOW())
  ON CONFLICT (user_id, school_id, role) DO UPDATE SET
    is_active = TRUE, joined_at = NOW();

  SELECT ce.class_id INTO v_class_id
  FROM class_enrollments ce
  WHERE ce.student_id = v_student.id AND ce.unenrolled_at IS NULL
  LIMIT 1;

  RETURN jsonb_build_object(
    'success', TRUE,
    'student_id', v_student.id,
    'class_id', v_class_id,
    'school_id', v_school_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.activate_student(TEXT, TEXT, TEXT) TO authenticated;

-- ── 7. Indexes for query performance (idempotent).
CREATE INDEX IF NOT EXISTS idx_session_bookings_student_status
  ON public.session_bookings(student_id, status);
CREATE INDEX IF NOT EXISTS idx_session_bookings_mentor_status
  ON public.session_bookings(mentor_id, status);
CREATE INDEX IF NOT EXISTS idx_session_bookings_otp_visible
  ON public.session_bookings(code_visible_at) WHERE code_visible_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_doubt_requests_student_status
  ON public.doubt_requests(student_id, status);
CREATE INDEX IF NOT EXISTS idx_doubt_requests_subject_status
  ON public.doubt_requests(subject_id, status);

-- ── 8. Ensure realtime publication includes the tables the Flutter
--    app subscribes to (idempotent).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;
END $$;

DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE messages; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE doubt_requests; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE session_bookings; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE mentor_availability; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE ratings; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE announcements; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
