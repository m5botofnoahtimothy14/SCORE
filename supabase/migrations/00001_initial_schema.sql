-- ============================================================
-- TeachCross: Migration 00001 — Initial Schema
-- ============================================================
-- Enable extensions (pgcrypto is pre-enabled on Supabase; IF NOT EXISTS keeps this idempotent)
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- ============================================================
-- SCHOOLS
-- ============================================================
CREATE TABLE schools (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name            TEXT NOT NULL,
  code            TEXT NOT NULL UNIQUE,           -- short unique code e.g. "DPSN"
  address         TEXT,
  city            TEXT,
  state           TEXT,
  country         TEXT NOT NULL DEFAULT 'India',
  phone           TEXT,
  email           TEXT,
  logo_url        TEXT,
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE school_settings (
  id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id                   UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  allow_student_id_only_login BOOLEAN NOT NULL DEFAULT FALSE, -- lower security option
  require_activation_code     BOOLEAN NOT NULL DEFAULT TRUE,
  otp_provider                TEXT DEFAULT 'twilio',          -- 'twilio'|'msg91'
  moderation_provider         TEXT DEFAULT 'openai',          -- 'openai'|'google'
  image_safety_provider       TEXT DEFAULT 'google_vision',
  max_file_size_mb            INTEGER NOT NULL DEFAULT 10,
  retention_days              INTEGER NOT NULL DEFAULT 365,
  timezone                    TEXT NOT NULL DEFAULT 'Asia/Kolkata',
  academic_year_start_month   INTEGER NOT NULL DEFAULT 4,     -- April
  updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (school_id)
);

-- ============================================================
-- USERS (linked to Supabase Auth)
-- ============================================================
-- Extends auth.users with profile data
CREATE TABLE user_profiles (
  id              UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name    TEXT NOT NULL,
  phone           TEXT,
  avatar_url      TEXT,
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  suspended_at    TIMESTAMPTZ,
  suspension_reason TEXT,
  suspended_by    UUID,                               -- admin user id
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- SCHOOL MEMBERSHIPS (user ↔ school, with role)
-- ============================================================
CREATE TYPE school_role AS ENUM (
  'platform_owner',
  'school_admin',
  'principal',
  'head_teacher',
  'teacher',
  'student'
);

CREATE TABLE school_memberships (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  role            school_role NOT NULL,
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  joined_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, school_id, role)
);

CREATE INDEX idx_school_memberships_user    ON school_memberships(user_id);
CREATE INDEX idx_school_memberships_school  ON school_memberships(school_id);
CREATE INDEX idx_school_memberships_role    ON school_memberships(role);

-- ============================================================
-- ACADEMIC YEARS
-- ============================================================
CREATE TABLE academic_years (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,                     -- e.g. "2025-26"
  starts_on       DATE NOT NULL,
  ends_on         DATE NOT NULL,
  is_current      BOOLEAN NOT NULL DEFAULT FALSE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (school_id, name)
);

CREATE INDEX idx_academic_years_school ON academic_years(school_id);

-- Only one current year per school (partial unique index)
CREATE UNIQUE INDEX idx_academic_years_current
  ON academic_years(school_id)
  WHERE is_current = TRUE;

-- ============================================================
-- SUBJECTS
-- ============================================================
CREATE TABLE subjects (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,
  code            TEXT,
  description     TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (school_id, name)
);

CREATE INDEX idx_subjects_school ON subjects(school_id);

-- ============================================================
-- CLASSES
-- ============================================================
CREATE TABLE classes (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  academic_year_id UUID NOT NULL REFERENCES academic_years(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,                     -- e.g. "Grade 8-A"
  grade           TEXT NOT NULL,                     -- e.g. "8"
  section         TEXT,                              -- e.g. "A"
  capacity        INTEGER,
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (school_id, academic_year_id, grade, section)
);

CREATE INDEX idx_classes_school       ON classes(school_id);
CREATE INDEX idx_classes_academic_year ON classes(academic_year_id);

-- ============================================================
-- STUDENTS ROSTER (admin-managed, source of truth)
-- ============================================================
CREATE TABLE students (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  user_id         UUID REFERENCES user_profiles(id) ON DELETE SET NULL, -- set when activated
  student_id_no   TEXT NOT NULL,                     -- school-issued ID
  first_name      TEXT NOT NULL,
  last_name       TEXT NOT NULL,
  date_of_birth   DATE,
  gender          TEXT,
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  enrolled_on     DATE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (school_id, student_id_no)
);

CREATE INDEX idx_students_school   ON students(school_id);
CREATE INDEX idx_students_user     ON students(user_id);
CREATE INDEX idx_students_id_no    ON students(school_id, student_id_no);

-- ============================================================
-- TEACHERS ROSTER
-- ============================================================
CREATE TABLE teachers (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  user_id         UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  staff_id_no     TEXT NOT NULL,                     -- school-issued staff ID
  first_name      TEXT NOT NULL,
  last_name       TEXT NOT NULL,
  phone           TEXT NOT NULL,
  email           TEXT,
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  is_leadership   BOOLEAN NOT NULL DEFAULT FALSE,    -- principal / head
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (school_id, staff_id_no)
);

CREATE INDEX idx_teachers_school ON teachers(school_id);
CREATE INDEX idx_teachers_user   ON teachers(user_id);

-- ============================================================
-- CLASS ENROLLMENTS (student → class)
-- ============================================================
CREATE TABLE class_enrollments (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  class_id        UUID NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
  student_id      UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  enrolled_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  unenrolled_at   TIMESTAMPTZ,                       -- soft removal
  UNIQUE (class_id, student_id)
);

CREATE INDEX idx_class_enrollments_class   ON class_enrollments(class_id);
CREATE INDEX idx_class_enrollments_student ON class_enrollments(student_id);
CREATE INDEX idx_class_enrollments_school  ON class_enrollments(school_id);

-- ============================================================
-- TEACHING ASSIGNMENTS (teacher → class + subject)
-- ============================================================
CREATE TABLE teaching_assignments (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  teacher_id      UUID NOT NULL REFERENCES teachers(id) ON DELETE CASCADE,
  class_id        UUID NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
  subject_id      UUID REFERENCES subjects(id) ON DELETE SET NULL,
  is_class_teacher BOOLEAN NOT NULL DEFAULT FALSE,   -- class/homeroom teacher
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (teacher_id, class_id, subject_id)
);

CREATE INDEX idx_teaching_assignments_teacher ON teaching_assignments(teacher_id);
CREATE INDEX idx_teaching_assignments_class   ON teaching_assignments(class_id);
CREATE INDEX idx_teaching_assignments_school  ON teaching_assignments(school_id);

-- ============================================================
-- STUDENT ACTIVATION CREDENTIALS
-- ============================================================
CREATE TABLE student_activation_credentials (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  student_id      UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  code            TEXT NOT NULL,                     -- hashed activation code
  expires_at      TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '7 days'),
  used_at         TIMESTAMPTZ,
  created_by      UUID,                              -- admin user id
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (student_id)                                -- one active code per student
);

CREATE INDEX idx_student_activation_school ON student_activation_credentials(school_id);

-- ============================================================
-- STAFF ACTIVATION RECORDS (OTP verification log)
-- ============================================================
CREATE TABLE staff_activation_records (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  teacher_id      UUID NOT NULL REFERENCES teachers(id) ON DELETE CASCADE,
  otp_hash        TEXT,                              -- hashed OTP
  otp_expires_at  TIMESTAMPTZ,
  otp_verified_at TIMESTAMPTZ,
  attempt_count   INTEGER NOT NULL DEFAULT 0,
  locked_until    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (teacher_id)
);

-- Rate limit tracking for login/OTP
CREATE TABLE rate_limit_events (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key             TEXT NOT NULL,                     -- e.g. "otp:+91XXXXXXXXXX"
  action          TEXT NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_rate_limit_key ON rate_limit_events(key, created_at);
