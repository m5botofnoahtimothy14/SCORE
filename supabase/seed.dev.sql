-- ============================================================
-- TeachCross: Development seed (NEVER run against production)
-- Usage: psql "$DATABASE_URL" -f supabase/seed.dev.sql
-- Creates: 1 school, settings, academic year, 2 classes, 2 subjects,
-- 2 teachers roster rows, 3 students roster rows, enrollments, assignments.
-- Auth users + activation codes are created by scripts/bootstrap.mjs,
-- not here (no plaintext secrets in SQL).
-- ============================================================
BEGIN;

-- School
INSERT INTO schools (id, name, code, city, state, country, is_active)
VALUES ('11111111-1111-1111-1111-111111111111', 'Demo Public School', 'DEMO', 'New Delhi', 'Delhi', 'India', TRUE)
ON CONFLICT (code) DO NOTHING;

INSERT INTO school_settings (school_id, allow_student_id_only_login, require_activation_code, otp_provider, moderation_provider, image_safety_provider, max_file_size_mb, retention_days, timezone)
VALUES ('11111111-1111-1111-1111-111111111111', FALSE, TRUE, 'twilio', 'openai', 'google_vision', 10, 365, 'Asia/Kolkata')
ON CONFLICT (school_id) DO NOTHING;

-- Academic year
INSERT INTO academic_years (id, school_id, name, starts_on, ends_on, is_current)
VALUES ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', '2026-27', '2026-04-01', '2027-03-31', TRUE)
ON CONFLICT (school_id, name) DO NOTHING;

-- Subjects
INSERT INTO subjects (school_id, name, code) VALUES
  ('11111111-1111-1111-1111-111111111111', 'Mathematics', 'MATH'),
  ('11111111-1111-1111-1111-111111111111', 'Science', 'SCI')
ON CONFLICT (school_id, name) DO NOTHING;

-- Classes
INSERT INTO classes (id, school_id, academic_year_id, name, grade, section, is_active)
VALUES
  ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'Grade 8-A', '8', 'A', TRUE),
  ('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'Grade 8-B', '8', 'B', TRUE)
ON CONFLICT (school_id, academic_year_id, grade, section) DO NOTHING;

-- Teacher roster (unlinked until OTP activation)
INSERT INTO teachers (school_id, staff_id_no, first_name, last_name, phone, email, is_active, is_leadership)
VALUES
  ('11111111-1111-1111-1111-111111111111', 'T001', 'Asha', 'Sharma', '+911234567890', 'asha@demo.edu', TRUE, FALSE),
  ('11111111-1111-1111-1111-111111111111', 'T002', 'Rahul', 'Verma', '+911234567891', 'rahul@demo.edu', TRUE, TRUE)
ON CONFLICT (school_id, staff_id_no) DO NOTHING;

-- Student roster (unlinked until activation)
INSERT INTO students (school_id, student_id_no, first_name, last_name, is_active)
VALUES
  ('11111111-1111-1111-1111-111111111111', 'S1001', 'Aarav', 'Kumar', TRUE),
  ('11111111-1111-1111-1111-111111111111', 'S1002', 'Diya', 'Singh', TRUE),
  ('11111111-1111-1111-1111-111111111111', 'S1003', 'Kabir', 'Mehta', TRUE)
ON CONFLICT (school_id, student_id_no) DO NOTHING;

-- Enrollments: S1001 + S1002 in 8-A, S1003 in 8-B
INSERT INTO class_enrollments (school_id, class_id, student_id)
SELECT '11111111-1111-1111-1111-111111111111', c.id, s.id
FROM (VALUES
  ('S1001', '33333333-3333-3333-3333-333333333333'),
  ('S1002', '33333333-3333-3333-3333-333333333333'),
  ('S1003', '44444444-4444-4444-4444-444444444444')
) AS v(sid, cid)
JOIN students s ON s.school_id = '11111111-1111-1111-1111-111111111111' AND s.student_id_no = v.sid
JOIN classes c ON c.id = v.cid::UUID
ON CONFLICT (class_id, student_id) DO NOTHING;

-- Teaching assignments: T001 teaches MATH to 8-A (class teacher), T002 SCI to 8-A + 8-B
INSERT INTO teaching_assignments (school_id, teacher_id, class_id, subject_id, is_class_teacher)
SELECT '11111111-1111-1111-1111-111111111111', t.id, c.id, sub.id, v.is_ct
FROM (VALUES
  ('T001', '33333333-3333-3333-3333-333333333333', 'MATH', TRUE),
  ('T002', '33333333-3333-3333-3333-333333333333', 'SCI', FALSE),
  ('T002', '44444444-4444-4444-4444-444444444444', 'SCI', FALSE)
) AS v(staff, cid, scode, is_ct)
JOIN teachers t ON t.school_id = '11111111-1111-1111-1111-111111111111' AND t.staff_id_no = v.staff
JOIN classes c ON c.id = v.cid::UUID
JOIN subjects sub ON sub.school_id = '11111111-1111-1111-1111-111111111111' AND sub.code = v.scode
ON CONFLICT (teacher_id, class_id, subject_id) DO NOTHING;

-- Data retention defaults
INSERT INTO data_retention_policies (school_id, data_type, retention_days) VALUES
  ('11111111-1111-1111-1111-111111111111', 'messages', 365),
  ('11111111-1111-1111-1111-111111111111', 'attachments', 365),
  ('11111111-1111-1111-1111-111111111111', 'audit_events', 1825)
ON CONFLICT (school_id, data_type) DO NOTHING;

COMMIT;
