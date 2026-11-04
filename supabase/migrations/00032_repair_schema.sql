-- 00032_repair_schema.sql
-- Repair production schema drift: doubt_requests was created with only
-- (id, school_id) and mentor_desk_settings is missing weekly_doubt_allowance.
-- All statements are idempotent (ADD COLUMN IF NOT EXISTS).

ALTER TABLE public.doubt_requests
  ADD COLUMN IF NOT EXISTS conversation_id     UUID REFERENCES public.conversations(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS student_id          UUID REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS student_record_id   UUID REFERENCES public.students(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS class_id            UUID REFERENCES public.classes(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS subject_id          UUID REFERENCES public.subjects(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS question            TEXT,
  ADD COLUMN IF NOT EXISTS chapter             TEXT,
  ADD COLUMN IF NOT EXISTS question_number     TEXT,
  ADD COLUMN IF NOT EXISTS explanation         TEXT,
  ADD COLUMN IF NOT EXISTS previous_attempts   TEXT,
  ADD COLUMN IF NOT EXISTS urgent              BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS urgent_reason       TEXT,
  ADD COLUMN IF NOT EXISTS urgent_pass_used    BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS status              public.doubt_status NOT NULL DEFAULT 'waiting',
  ADD COLUMN IF NOT EXISTS assigned_mentor_id  UUID REFERENCES public.user_profiles(id),
  ADD COLUMN IF NOT EXISTS assigned_teacher_id UUID REFERENCES public.teachers(id),
  ADD COLUMN IF NOT EXISTS named_mentor        BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS first_reply_at      TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS resolved_at        TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS closed_at          TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS idempotency_key    UUID,
  ADD COLUMN IF NOT EXISTS created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- Backfill NOT NULL constraints where safe (only if no nulls).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.doubt_requests WHERE question IS NULL) THEN
    ALTER TABLE public.doubt_requests ALTER COLUMN question SET NOT NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.doubt_requests WHERE subject_id IS NULL) THEN
    ALTER TABLE public.doubt_requests ALTER COLUMN subject_id SET NOT NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.doubt_requests WHERE student_id IS NULL) THEN
    ALTER TABLE public.doubt_requests ALTER COLUMN student_id SET NOT NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.doubt_requests WHERE student_record_id IS NULL) THEN
    ALTER TABLE public.doubt_requests ALTER COLUMN student_record_id SET NOT NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.doubt_requests WHERE conversation_id IS NULL) THEN
    ALTER TABLE public.doubt_requests ALTER COLUMN conversation_id SET NOT NULL;
  END IF;
END $$;

ALTER TABLE public.mentor_desk_settings
  ADD COLUMN IF NOT EXISTS weekly_doubt_allowance INTEGER NOT NULL DEFAULT 3;

-- Ensure doubt_status enum has all values used by the app (idempotent).
DO $$ BEGIN CREATE TYPE public.doubt_status AS ENUM ('pending_assignment','waiting','assigned','in_progress','answered','resolved','reopened','closed'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TYPE public.doubt_status ADD VALUE IF NOT EXISTS 'pending_assignment'; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN ALTER TYPE public.doubt_status ADD VALUE IF NOT EXISTS 'in_progress'; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN ALTER TYPE public.doubt_status ADD VALUE IF NOT EXISTS 'answered'; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN ALTER TYPE public.doubt_status ADD VALUE IF NOT EXISTS 'reopened'; EXCEPTION WHEN others THEN NULL; END $$;

-- Default for status column must be a valid enum value.
ALTER TABLE public.doubt_requests ALTER COLUMN status SET DEFAULT 'waiting';