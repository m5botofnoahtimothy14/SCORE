-- Migration 00037 — Auto-enroll students in Chemistry, Physics, Biology
-- Ensures all active students are enrolled in the three core science subjects
-- so that doubt submission and booking work without manual enrollment.

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
    -- Get the student's current class
    SELECT ce.class_id INTO v_class_id
    FROM class_enrollments ce
    WHERE ce.student_id = v_student.student_id
      AND ce.unenrolled_at IS NULL
    LIMIT 1;

    IF v_class_id IS NULL THEN
      CONTINUE;
    END IF;

    -- Enroll in Chemistry, Physics, Biology
    FOR v_subject IN
      SELECT id FROM subjects
      WHERE school_id = v_student.school_id
        AND lower(name) IN ('chemistry', 'physics', 'biology')
    LOOP
      INSERT INTO student_subject_enrollments (school_id, student_id, class_id, subject_id, active, assigned_by)
      VALUES (v_student.school_id, v_student.student_id, v_class_id, v_subject.id, TRUE, NULL)
      ON CONFLICT (student_id, subject_id) DO UPDATE SET active = TRUE;
    END LOOP;
  END LOOP;
END $$;