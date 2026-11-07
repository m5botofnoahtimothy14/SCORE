-- Migration 00038 — Create student_subject_enrollments + auto-enroll
-- The production DB is missing this table (created in 00023 but not applied).
-- Create it and auto-enroll all students in Chemistry, Physics, Biology.

-- ── 1. Create the table ──
CREATE TABLE IF NOT EXISTS public.student_subject_enrollments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  class_id UUID NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  subject_id UUID NOT NULL REFERENCES public.subjects(id) ON DELETE CASCADE,
  assigned_by UUID REFERENCES public.user_profiles(id),
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(student_id, subject_id)
);

CREATE INDEX IF NOT EXISTS student_subject_enrollment_lookup
  ON public.student_subject_enrollments(student_id, active, subject_id);

ALTER TABLE public.student_subject_enrollments ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY student_subject_enrollment_read ON public.student_subject_enrollments FOR SELECT
    USING (
      EXISTS (SELECT 1 FROM public.students s WHERE s.id = student_id AND s.user_id = auth.uid())
      OR public.tc_is_school_admin(school_id)
      OR EXISTS (SELECT 1 FROM public.teachers t JOIN public.teaching_assignments ta ON ta.teacher_id=t.id
                 WHERE t.user_id=auth.uid() AND ta.class_id=student_subject_enrollments.class_id
                   AND ta.subject_id=student_subject_enrollments.subject_id)
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY student_subject_enrollment_admin ON public.student_subject_enrollments FOR ALL
    USING (public.tc_is_school_admin(school_id)) WITH CHECK (public.tc_is_school_admin(school_id));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ── 2. Auto-enroll all students in Chemistry, Physics, Biology ──
DO $$
DECLARE
  v_student RECORD;
  v_subject RECORD;
  v_class_id UUID;
BEGIN
  FOR v_student IN
    SELECT s.id AS student_id, s.school_id
    FROM students s
    WHERE s.is_active = TRUE
  LOOP
    SELECT ce.class_id INTO v_class_id
    FROM class_enrollments ce
    WHERE ce.student_id = v_student.student_id
      AND ce.unenrolled_at IS NULL
    LIMIT 1;

    IF v_class_id IS NULL THEN
      CONTINUE;
    END IF;

    FOR v_subject IN
      SELECT id FROM subjects
      WHERE school_id = v_student.school_id
        AND lower(name) IN ('chemistry', 'physics', 'biology')
    LOOP
      INSERT INTO student_subject_enrollments (school_id, student_id, class_id, subject_id, active, assigned_by)
      VALUES (v_student.school_id, v_student.student_id, v_class_id, v_subject.id, TRUE, NULL)
      ON CONFLICT (student_id, subject_id) DO UPDATE SET active = TRUE, updated_at = NOW();
    END LOOP;
  END LOOP;
END $$;

-- ── 3. Also create subjects if they don't exist ──
-- (Chemistry, Physics, Biology for each school)
DO $$
DECLARE
  v_school RECORD;
BEGIN
  FOR v_school IN SELECT id FROM schools WHERE is_active = TRUE
  LOOP
    INSERT INTO subjects (school_id, name, code, description)
    VALUES (v_school.id, 'Chemistry', 'CHEM', 'Chemistry subject')
    ON CONFLICT (school_id, name) DO NOTHING;
    INSERT INTO subjects (school_id, name, code, description)
    VALUES (v_school.id, 'Physics', 'PHYS', 'Physics subject')
    ON CONFLICT (school_id, name) DO NOTHING;
    INSERT INTO subjects (school_id, name, code, description)
    VALUES (v_school.id, 'Biology', 'BIO', 'Biology subject')
    ON CONFLICT (school_id, name) DO NOTHING;
  END LOOP;
END $$;