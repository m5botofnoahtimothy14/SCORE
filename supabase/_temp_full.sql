-- ============================================================
-- TeachCross Complete Database Schema (Production Ready)
-- ============================================================

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_net";
CREATE EXTENSION IF NOT EXISTS "pg_cron";

-- ============================================================
-- SCHOOLS
-- ============================================================
CREATE TABLE IF NOT EXISTS schools (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name          TEXT NOT NULL,
  code          TEXT NOT NULL UNIQUE,
  address       TEXT,
  city          TEXT,
  state         TEXT,
  country       TEXT NOT NULL DEFAULT 'India',
  phone         TEXT,
  email         TEXT,
  logo_url      TEXT,
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- SCHOOL SETTINGS
-- ============================================================
CREATE TABLE IF NOT EXISTS school_settings (
  id                          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id                   UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE UNIQUE,
  allow_student_id_only_login BOOLEAN NOT NULL DEFAULT FALSE,
  require_activation_code     BOOLEAN NOT NULL DEFAULT TRUE,
  otp_provider                TEXT DEFAULT 'textbee',
  moderation_provider         TEXT DEFAULT 'openai',
  image_safety_provider       TEXT DEFAULT 'openai_vision',
  max_file_size_mb            INTEGER NOT NULL DEFAULT 10,
  retention_days              INTEGER NOT NULL DEFAULT 365,
  timezone                    TEXT NOT NULL DEFAULT 'Asia/Kolkata',
  academic_year_start_month   INTEGER NOT NULL DEFAULT 4,
  google_meet_enabled         BOOLEAN NOT NULL DEFAULT FALSE,
  google_calendar_id          TEXT DEFAULT 'primary',
  google_time_zone            TEXT DEFAULT 'Asia/Kolkata',
  updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- USER PROFILES
-- ============================================================
CREATE TABLE IF NOT EXISTS user_profiles (
  id                UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name      TEXT NOT NULL,
  phone             TEXT,
  avatar_url        TEXT,
  is_active         BOOLEAN NOT NULL DEFAULT TRUE,
  suspended_at      TIMESTAMPTZ,
  suspension_reason TEXT,
  suspended_by      UUID REFERENCES user_profiles(id),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- SCHOOL MEMBERSHIPS
-- ============================================================
DO $$ BEGIN CREATE TYPE school_role AS ENUM (
  'platform_owner',
  'school_admin',
  'principal',
  'head_teacher',
  'teacher',
  'student'
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS school_memberships (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  school_id   UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  role        school_role NOT NULL,
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  joined_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, school_id, role)
);

CREATE INDEX IF NOT EXISTS idx_school_memberships_user    ON school_memberships(user_id);
CREATE INDEX IF NOT EXISTS idx_school_memberships_school  ON school_memberships(school_id);
CREATE INDEX IF NOT EXISTS idx_school_memberships_role    ON school_memberships(role);

-- ============================================================
-- ACADEMIC YEARS
-- ============================================================
CREATE TABLE IF NOT EXISTS academic_years (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id   UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  starts_on   DATE NOT NULL,
  ends_on     DATE NOT NULL,
  is_current  BOOLEAN NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (school_id, name)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_academic_years_current ON academic_years(school_id) WHERE is_current = TRUE;
CREATE INDEX IF NOT EXISTS idx_academic_years_school ON academic_years(school_id);

-- ============================================================
-- SUBJECTS
-- ============================================================
CREATE TABLE IF NOT EXISTS subjects (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id   UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  code        TEXT,
  description TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (school_id, name)
);

CREATE INDEX IF NOT EXISTS idx_subjects_school ON subjects(school_id);

-- ============================================================
-- CLASSES
-- ============================================================
CREATE TABLE IF NOT EXISTS classes (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  academic_year_id UUID NOT NULL REFERENCES academic_years(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,
  grade           TEXT NOT NULL,
  section         TEXT,
  capacity        INTEGER,
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (school_id, academic_year_id, grade, section)
);

CREATE INDEX IF NOT EXISTS idx_classes_school        ON classes(school_id);
CREATE INDEX IF NOT EXISTS idx_classes_academic_year ON classes(academic_year_id);

-- ============================================================
-- STUDENTS ROSTER
-- ============================================================
CREATE TABLE IF NOT EXISTS students (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  user_id         UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  student_id_no   TEXT NOT NULL,
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

CREATE INDEX IF NOT EXISTS idx_students_school   ON students(school_id);
CREATE INDEX IF NOT EXISTS idx_students_user     ON students(user_id);
CREATE INDEX IF NOT EXISTS idx_students_id_no    ON students(school_id, student_id_no);

-- ============================================================
-- TEACHERS ROSTER
-- ============================================================
CREATE TABLE IF NOT EXISTS teachers (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  user_id         UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  staff_id_no     TEXT NOT NULL,
  first_name      TEXT NOT NULL,
  last_name       TEXT NOT NULL,
  phone           TEXT NOT NULL,
  email           TEXT,
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  is_leadership   BOOLEAN NOT NULL DEFAULT FALSE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (school_id, staff_id_no)
);

CREATE INDEX IF NOT EXISTS idx_teachers_school ON teachers(school_id);
CREATE INDEX IF NOT EXISTS idx_teachers_user   ON teachers(user_id);

-- ============================================================
-- CLASS ENROLLMENTS
-- ============================================================
CREATE TABLE IF NOT EXISTS class_enrollments (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id      UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  class_id       UUID NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
  student_id     UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  enrolled_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  unenrolled_at  TIMESTAMPTZ,
  UNIQUE (class_id, student_id)
);

CREATE INDEX IF NOT EXISTS idx_class_enrollments_class   ON class_enrollments(class_id);
CREATE INDEX IF NOT EXISTS idx_class_enrollments_student ON class_enrollments(student_id);
CREATE INDEX IF NOT EXISTS idx_class_enrollments_school  ON class_enrollments(school_id);

-- ============================================================
-- TEACHING ASSIGNMENTS
-- ============================================================
CREATE TABLE IF NOT EXISTS teaching_assignments (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  teacher_id      UUID NOT NULL REFERENCES teachers(id) ON DELETE CASCADE,
  class_id        UUID NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
  subject_id      UUID REFERENCES subjects(id) ON DELETE SET NULL,
  is_class_teacher BOOLEAN NOT NULL DEFAULT FALSE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (teacher_id, class_id, subject_id)
);

CREATE INDEX IF NOT EXISTS idx_teaching_assignments_teacher ON teaching_assignments(teacher_id);
CREATE INDEX IF NOT EXISTS idx_teaching_assignments_class   ON teaching_assignments(class_id);
CREATE INDEX IF NOT EXISTS idx_teaching_assignments_school  ON teaching_assignments(school_id);

-- ============================================================
-- STUDENT ACTIVATION CREDENTIALS
-- ============================================================
CREATE TABLE IF NOT EXISTS student_activation_credentials (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id     UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  student_id    UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  code_hash     TEXT NOT NULL,
  code_salt     TEXT NOT NULL,
  expires_at    TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '7 days'),
  used_at       TIMESTAMPTZ,
  created_by    UUID REFERENCES user_profiles(id),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (student_id)
);

CREATE INDEX IF NOT EXISTS idx_student_activation_school ON student_activation_credentials(school_id);

-- ============================================================
-- STAFF ACTIVATION RECORDS
-- ============================================================
CREATE TABLE IF NOT EXISTS staff_activation_records (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id      UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  teacher_id     UUID NOT NULL REFERENCES teachers(id) ON DELETE CASCADE,
  otp_hash       TEXT,
  otp_salt       TEXT,
  otp_expires_at TIMESTAMPTZ,
  otp_verified_at TIMESTAMPTZ,
  attempt_count  INTEGER NOT NULL DEFAULT 0,
  locked_until   TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (teacher_id)
);

-- ============================================================
-- RATE LIMIT EVENTS
-- ============================================================
CREATE TABLE IF NOT EXISTS rate_limit_events (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  key        TEXT NOT NULL,
  action     TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_rate_limit_key ON rate_limit_events(key, created_at);

-- ============================================================
-- CONVERSATIONS & MESSAGES
-- ============================================================
DO $$ BEGIN CREATE TYPE conversation_type AS ENUM (
  'student_teacher',
  'student_support',
  'staff',
  'class_channel',
  'leadership',
  'mentor_desk'
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS conversations (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id   UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  type        conversation_type NOT NULL,
  class_id    UUID REFERENCES classes(id) ON DELETE CASCADE,
  title       TEXT,
  created_by  UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_conversations_school    ON conversations(school_id);
CREATE INDEX IF NOT EXISTS idx_conversations_class     ON conversations(class_id);
CREATE INDEX IF NOT EXISTS idx_conversations_type      ON conversations(type);
CREATE INDEX IF NOT EXISTS idx_conversations_updated   ON conversations(school_id, updated_at DESC);

DO $$ BEGIN CREATE TYPE member_role AS ENUM ('student', 'teacher', 'admin_observer'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS conversation_members (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  user_id        UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  role           member_role NOT NULL DEFAULT 'student',
  can_send       BOOLEAN NOT NULL DEFAULT TRUE,
  joined_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  removed_at     TIMESTAMPTZ,
  last_read_at   TIMESTAMPTZ,
  UNIQUE (conversation_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_conversation_members_conv ON conversation_members(conversation_id);
CREATE INDEX IF NOT EXISTS idx_conversation_members_user ON conversation_members(user_id);

DO $$ BEGIN CREATE TYPE message_status AS ENUM (
  'pending_moderation', 'approved', 'blocked', 'held_for_review', 'deleted'
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS messages (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  school_id      UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  sender_id      UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  body           TEXT,
  status         message_status NOT NULL DEFAULT 'pending_moderation',
  is_deleted     BOOLEAN NOT NULL DEFAULT FALSE,
  reply_to_id    UUID REFERENCES messages(id),
  idempotency_key TEXT NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id, created_at);
CREATE INDEX IF NOT EXISTS idx_messages_sender ON messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_messages_idempotency ON messages(idempotency_key);

-- ============================================================
-- ATTACHMENTS
-- ============================================================
DO $$ BEGIN CREATE TYPE attachment_type AS ENUM ('image', 'audio', 'document', 'video'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE attachment_status AS ENUM ('uploading', 'pending_scan', 'approved', 'quarantined', 'rejected'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS attachments (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  message_id  UUID REFERENCES messages(id) ON DELETE CASCADE,
  school_id   UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  uploader_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  type        attachment_type NOT NULL,
  file_name   TEXT NOT NULL,
  mime_type   TEXT NOT NULL,
  size_bytes  INTEGER NOT NULL,
  storage_path TEXT NOT NULL,
  status      attachment_status NOT NULL DEFAULT 'pending_scan',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_attachments_message ON attachments(message_id);
CREATE INDEX IF NOT EXISTS idx_attachments_uploader ON attachments(uploader_id);
CREATE INDEX IF NOT EXISTS idx_attachments_status   ON attachments(status);

-- ============================================================
-- ANNOUNCEMENTS
-- ============================================================
DO $$ BEGIN CREATE TYPE announcement_audience AS ENUM ('school_wide', 'class', 'staff', 'leadership', 'custom'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE announcement_category AS ENUM ('general', 'academic', 'event', 'safety', 'priority_alert'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS announcements (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id      UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  author_id      UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  title          TEXT NOT NULL,
  body           TEXT NOT NULL,
  category       announcement_category NOT NULL DEFAULT 'general',
  audience_type  announcement_audience NOT NULL DEFAULT 'school_wide',
  class_id       UUID REFERENCES classes(id) ON DELETE CASCADE,
  requires_ack   BOOLEAN NOT NULL DEFAULT FALSE,
  is_published   BOOLEAN NOT NULL DEFAULT FALSE,
  published_at   TIMESTAMPTZ,
  expires_at     TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_announcements_school ON announcements(school_id);
CREATE INDEX IF NOT EXISTS idx_announcements_class  ON announcements(class_id);
CREATE INDEX IF NOT EXISTS idx_announcements_pub    ON announcements(is_published, published_at);

-- ============================================================
-- MODERATION
-- ============================================================
DO $$ BEGIN CREATE TYPE moderation_verdict AS ENUM ('approved', 'warned', 'held', 'blocked', 'escalated'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS moderation_events (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id   UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  message_id  UUID REFERENCES messages(id) ON DELETE CASCADE,
  attachment_id UUID REFERENCES attachments(id) ON DELETE CASCADE,
  verdict     moderation_verdict NOT NULL,
  provider    TEXT NOT NULL,
  confidence  NUMERIC(3,2),
  categories  JSONB DEFAULT '{}',
  reviewed_by UUID REFERENCES user_profiles(id),
  reviewed_at TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_moderation_events_school ON moderation_events(school_id);
CREATE INDEX IF NOT EXISTS idx_moderation_events_message ON moderation_events(message_id);

-- ============================================================
-- AUDIT EVENTS
-- ============================================================
CREATE TABLE IF NOT EXISTS audit_events (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id   UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  actor_id    UUID REFERENCES user_profiles(id),
  action      TEXT NOT NULL,
  target_type TEXT NOT NULL,
  target_id   TEXT,
  outcome     TEXT NOT NULL DEFAULT 'success',
  metadata    JSONB DEFAULT '{}',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_events_school ON audit_events(school_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_events_actor  ON audit_events(actor_id);

-- ============================================================
-- BACKGROUND JOBS
-- ============================================================
DO $$ BEGIN CREATE TYPE job_status AS ENUM ('queued', 'running', 'completed', 'failed', 'retrying'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS background_jobs (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  type         TEXT NOT NULL,
  status       job_status NOT NULL DEFAULT 'queued',
  payload      JSONB DEFAULT '{}',
  attempts     INTEGER NOT NULL DEFAULT 0,
  max_attempts INTEGER NOT NULL DEFAULT 3,
  last_error   TEXT,
  scheduled_for TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  started_at   TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_background_jobs_status ON background_jobs(status, scheduled_for) WHERE status IN ('queued', 'retrying');

-- ============================================================
-- DATA RETENTION POLICIES
-- ============================================================
CREATE TABLE IF NOT EXISTS data_retention_policies (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id    UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  data_type    TEXT NOT NULL,
  retention_days INTEGER NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (school_id, data_type)
);

-- ============================================================
-- MENTOR DESK SETTINGS
-- ============================================================
CREATE TABLE IF NOT EXISTS mentor_desk_settings (
  id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id                   UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE UNIQUE,
  open_doubt_limit            INTEGER NOT NULL DEFAULT 3,
  session_allowance_minutes   INTEGER NOT NULL DEFAULT 120,
  urgent_passes_per_week      INTEGER NOT NULL DEFAULT 1,
  escalation_threshold_minutes INTEGER NOT NULL DEFAULT 30,
  week_start_day              INTEGER NOT NULL DEFAULT 1,
  session_lengths             INTEGER[] NOT NULL DEFAULT '{15,30}',
  verification_code_digits    INTEGER NOT NULL DEFAULT 6,
  code_visible_minutes_before INTEGER NOT NULL DEFAULT 10,
  max_verification_attempts   INTEGER NOT NULL DEFAULT 5,
  created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_mentor_desk_settings_school ON mentor_desk_settings(school_id);

-- ============================================================
-- MENTOR SUBJECT APPROVALS
-- ============================================================
DO $$ BEGIN CREATE TYPE mentor_approval_status AS ENUM ('pending', 'approved', 'rejected'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS mentor_subject_approvals (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id      UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  teacher_id     UUID NOT NULL REFERENCES teachers(id) ON DELETE CASCADE,
  subject_id     UUID NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
  status         mentor_approval_status NOT NULL DEFAULT 'pending',
  approved_by    UUID REFERENCES user_profiles(id),
  approved_at    TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (teacher_id, subject_id)
);

-- ============================================================
-- MENTOR AVAILABILITY
-- ============================================================
DO $$ BEGIN CREATE TYPE availability_status AS ENUM ('available', 'away'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS mentor_availability (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id   UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  teacher_id  UUID NOT NULL REFERENCES teachers(id) ON DELETE CASCADE,
  status      availability_status NOT NULL DEFAULT 'away',
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (teacher_id)
);

-- ============================================================
-- DOUBT REQUESTS
-- ============================================================
DO $$ BEGIN CREATE TYPE doubt_status AS ENUM (
  'pending_assignment', 'waiting', 'assigned', 'in_progress',
  'answered', 'resolved', 'reopened', 'closed'
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS doubt_requests (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id         UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  conversation_id   UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  student_id        UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  student_record_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  class_id          UUID REFERENCES classes(id) ON DELETE SET NULL,
  subject_id        UUID NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
  question          TEXT NOT NULL,
  chapter           TEXT,
  question_number   TEXT,
  explanation       TEXT,
  previous_attempts TEXT,
  urgent            BOOLEAN NOT NULL DEFAULT FALSE,
  urgent_reason     TEXT,
  urgent_pass_used  BOOLEAN NOT NULL DEFAULT FALSE,
  status            doubt_status NOT NULL DEFAULT 'pending_assignment',
  assigned_mentor_id UUID REFERENCES user_profiles(id),
  assigned_teacher_id UUID REFERENCES teachers(id),
  named_mentor      BOOLEAN NOT NULL DEFAULT FALSE,
  first_reply_at    TIMESTAMPTZ,
  resolved_at       TIMESTAMPTZ,
  closed_at         TIMESTAMPTZ,
  idempotency_key   UUID,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_doubt_requests_student ON doubt_requests(student_id, status);
CREATE INDEX IF NOT EXISTS idx_doubt_requests_subject ON doubt_requests(subject_id, status);
CREATE INDEX IF NOT EXISTS idx_doubt_requests_status  ON doubt_requests(status) WHERE status IN ('pending_assignment','waiting','assigned','in_progress');
CREATE INDEX IF NOT EXISTS idx_doubt_requests_mentor  ON doubt_requests(assigned_mentor_id) WHERE assigned_mentor_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_doubt_requests_created ON doubt_requests(created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS doubt_student_idempotency ON doubt_requests(student_id, idempotency_key) WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS doubt_status_history (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id  UUID NOT NULL REFERENCES doubt_requests(id) ON DELETE CASCADE,
  actor_id    UUID NOT NULL REFERENCES user_profiles(id),
  from_status doubt_status,
  to_status   doubt_status NOT NULL,
  reason      TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_doubt_status_history_request ON doubt_status_history(request_id);

-- ============================================================
-- SESSION BOOKINGS
-- ============================================================
DO $$ BEGIN CREATE TYPE booking_status AS ENUM (
  'requested', 'confirmed', 'cancelled_by_student', 'cancelled_by_mentor',
  'completed', 'no_show_student', 'no_show_mentor', 'unverified_closed'
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS session_bookings (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id          UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  student_id         UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  student_record_id  UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  class_id           UUID REFERENCES classes(id) ON DELETE SET NULL,
  mentor_id          UUID REFERENCES user_profiles(id),
  mentor_record_id   UUID REFERENCES teachers(id),
  subject_id         UUID NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
  duration_minutes   INTEGER NOT NULL,
  reserved_minutes   INTEGER NOT NULL,
  topic              TEXT NOT NULL,
  preparation        TEXT,
  requested_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  scheduled_at       TIMESTAMPTZ,
  confirmed_at       TIMESTAMPTZ,
  started_at         TIMESTAMPTZ,
  ended_at           TIMESTAMPTZ,
  actual_minutes     INTEGER,
  meeting_link       TEXT,
  meeting_room       TEXT,
  google_meet_link   TEXT,
  google_calendar_event_id TEXT,
  google_meet_created_at TIMESTAMPTZ,
  status             booking_status NOT NULL DEFAULT 'requested',
  allowance_minutes_used INTEGER NOT NULL DEFAULT 0,
  cancelled_at       TIMESTAMPTZ,
  cancelled_by       UUID REFERENCES user_profiles(id),
  refunded           BOOLEAN NOT NULL DEFAULT FALSE,
  verification_code  TEXT,
  code_expires_at    TIMESTAMPTZ,
  code_attempts      INTEGER NOT NULL DEFAULT 0,
  code_locked_at     TIMESTAMPTZ,
  code_visible_at    TIMESTAMPTZ,
  verified_at        TIMESTAMPTZ,
  closed_without_code BOOLEAN NOT NULL DEFAULT FALSE,
  close_reason       TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_session_bookings_student ON session_bookings(student_id, status);
CREATE INDEX IF NOT EXISTS idx_session_bookings_mentor  ON session_bookings(mentor_id, status);
CREATE INDEX IF NOT EXISTS idx_session_bookings_scheduled ON session_bookings(scheduled_at) WHERE status = 'confirmed';
CREATE INDEX IF NOT EXISTS idx_session_bookings_subject ON session_bookings(subject_id, status);
CREATE INDEX IF NOT EXISTS idx_session_bookings_google_event ON session_bookings(google_calendar_event_id) WHERE google_calendar_event_id IS NOT NULL;

-- ============================================================
-- SESSION NO-SHOWS
-- ============================================================
DO $$ BEGIN CREATE TYPE no_show_type AS ENUM ('student_no_show', 'mentor_no_show'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS session_no_shows (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id      UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  booking_id     UUID NOT NULL REFERENCES session_bookings(id) ON DELETE CASCADE,
  reported_by    UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  reported_by_role TEXT NOT NULL,
  no_show_type   no_show_type NOT NULL,
  refund_minutes INTEGER NOT NULL DEFAULT 0,
  refunded       BOOLEAN NOT NULL DEFAULT FALSE,
  review_status  TEXT NOT NULL DEFAULT 'pending',
  reviewed_by    UUID REFERENCES user_profiles(id),
  reviewed_at    TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_session_no_shows_booking ON session_no_shows(booking_id);
CREATE INDEX IF NOT EXISTS idx_session_no_shows_review  ON session_no_shows(review_status) WHERE review_status = 'pending';

-- ============================================================
-- RATINGS
-- ============================================================
CREATE TABLE IF NOT EXISTS ratings (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id   UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  request_id  UUID NOT NULL REFERENCES doubt_requests(id) ON DELETE CASCADE,
  student_id  UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  mentor_id   UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  rating      INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment     TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (request_id, student_id)
);

CREATE INDEX IF NOT EXISTS idx_ratings_request ON ratings(request_id);
CREATE INDEX IF NOT EXISTS idx_ratings_mentor  ON ratings(mentor_id);

-- ============================================================
-- MENTOR ASSESSMENTS
-- ============================================================
DO $$ BEGIN CREATE TYPE engagement_scale AS ENUM (
  'unprepared', 'developing', 'satisfactory', 'strong', 'outstanding'
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS mentor_assessments (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id     UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  request_id    UUID NOT NULL REFERENCES doubt_requests(id) ON DELETE CASCADE,
  mentor_id     UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  student_id    UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  preparation   engagement_scale NOT NULL,
  engagement    engagement_scale NOT NULL,
  private_note  TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (request_id, mentor_id)
);

CREATE INDEX IF NOT EXISTS idx_mentor_assessments_request ON mentor_assessments(request_id);
CREATE INDEX IF NOT EXISTS idx_mentor_assessments_mentor  ON mentor_assessments(mentor_id);

-- ============================================================
-- ALLOWANCE TRANSACTIONS
-- ============================================================
DO $$ BEGIN CREATE TYPE allowance_action AS ENUM ('deduct', 'refund'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS allowance_transactions (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id          UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  student_id         UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  subject_id         UUID NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
  booking_id         UUID REFERENCES session_bookings(id) ON DELETE SET NULL,
  week_start         DATE NOT NULL,
  action             allowance_action NOT NULL,
  minutes            INTEGER NOT NULL,
  reason             TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_allowance_student_week ON allowance_transactions(student_id, subject_id, week_start);
CREATE INDEX IF NOT EXISTS idx_allowance_booking      ON allowance_transactions(booking_id);

-- ============================================================
-- URGENT PASS USAGE
-- ============================================================
CREATE TABLE IF NOT EXISTS urgent_pass_usage (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id    UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  student_id   UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  subject_id   UUID NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
  request_id   UUID NOT NULL REFERENCES doubt_requests(id) ON DELETE CASCADE,
  week_start   DATE NOT NULL,
  consumed_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (student_id, subject_id, week_start)
);

CREATE INDEX IF NOT EXISTS idx_urgent_pass_student_week ON urgent_pass_usage(student_id, subject_id, week_start);

-- ============================================================
-- SLT ACCESS GRANTS
-- ============================================================
DO $$ BEGIN CREATE TYPE slt_scope_type AS ENUM ('program', 'batch', 'campus', 'organisation'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS slt_access_grants (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id     UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  user_id       UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  granted_by    UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  scope_type    slt_scope_type NOT NULL,
  scope_value   TEXT NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  revoked_at    TIMESTAMPTZ,
  UNIQUE (user_id, scope_type, scope_value)
);

CREATE INDEX IF NOT EXISTS idx_slt_access_user ON slt_access_grants(user_id) WHERE revoked_at IS NULL;

-- ============================================================
-- VIDEO ROOMS
-- ============================================================
CREATE TABLE IF NOT EXISTS video_rooms (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id     UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  booking_id    UUID NOT NULL REFERENCES session_bookings(id) ON DELETE CASCADE,
  room_name     TEXT NOT NULL UNIQUE,
  provider      TEXT NOT NULL DEFAULT 'google_meet',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (booking_id)
);

-- ============================================================
-- VIDEO PARTICIPANT EVENTS
-- ============================================================
CREATE TABLE IF NOT EXISTS video_participant_events (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id     UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  booking_id    UUID NOT NULL REFERENCES session_bookings(id) ON DELETE CASCADE,
  user_id       UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  role          TEXT NOT NULL,
  event_type    TEXT NOT NULL CHECK (event_type IN ('join','leave','reconnect','disconnect')),
  connected_at  TIMESTAMPTZ,
  disconnected_at TIMESTAMPTZ,
  duration_seconds INTEGER,
  metadata      JSONB DEFAULT '{}',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_video_events_booking ON video_participant_events(booking_id, created_at);

-- ============================================================
-- RECORDING CONSENTS
-- ============================================================
CREATE TABLE IF NOT EXISTS recording_consents (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id     UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  booking_id    UUID NOT NULL REFERENCES session_bookings(id) ON DELETE CASCADE,
  user_id       UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  role          TEXT NOT NULL,
  consented     BOOLEAN NOT NULL DEFAULT FALSE,
  guardian_consent BOOLEAN NOT NULL DEFAULT FALSE,
  decided_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (booking_id, user_id)
);

-- ============================================================
-- SESSION RECORDINGS
-- ============================================================
CREATE TABLE IF NOT EXISTS session_recordings (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id     UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  booking_id    UUID NOT NULL REFERENCES session_bookings(id) ON DELETE CASCADE,
  storage_path  TEXT NOT NULL,
  status        TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','recording','completed','failed','deleted')),
  started_at    TIMESTAMPTZ,
  ended_at      TIMESTAMPTZ,
  duration_seconds INTEGER,
  size_bytes    BIGINT,
  expires_at    TIMESTAMPTZ,
  deleted_at    TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_session_recordings_booking ON session_recordings(booking_id);

-- ============================================================
-- ENABLE RLS ON ALL TABLES
-- ============================================================
ALTER TABLE schools ENABLE ROW LEVEL SECURITY;
ALTER TABLE school_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE school_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE academic_years ENABLE ROW LEVEL SECURITY;
ALTER TABLE subjects ENABLE ROW LEVEL SECURITY;
ALTER TABLE classes ENABLE ROW LEVEL SECURITY;
ALTER TABLE students ENABLE ROW LEVEL SECURITY;
ALTER TABLE teachers ENABLE ROW LEVEL SECURITY;
ALTER TABLE class_enrollments ENABLE ROW LEVEL SECURITY;
ALTER TABLE teaching_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE student_activation_credentials ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_activation_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE rate_limit_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversation_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE announcements ENABLE ROW LEVEL SECURITY;
ALTER TABLE moderation_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE background_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE data_retention_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE mentor_desk_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE mentor_subject_approvals ENABLE ROW LEVEL SECURITY;
ALTER TABLE mentor_availability ENABLE ROW LEVEL SECURITY;
ALTER TABLE doubt_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE doubt_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE session_bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE session_no_shows ENABLE ROW LEVEL SECURITY;
ALTER TABLE ratings ENABLE ROW LEVEL SECURITY;
ALTER TABLE mentor_assessments ENABLE ROW LEVEL SECURITY;
ALTER TABLE allowance_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE urgent_pass_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE slt_access_grants ENABLE ROW LEVEL SECURITY;
ALTER TABLE video_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE video_participant_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE recording_consents ENABLE ROW LEVEL SECURITY;
ALTER TABLE session_recordings ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================
CREATE OR REPLACE FUNCTION tc_user_school_ids() RETURNS UUID[] AS $$
  SELECT array_agg(DISTINCT school_id) FROM school_memberships
  WHERE user_id = auth.uid() AND is_active = TRUE;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION tc_is_school_admin(school_id UUID) RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM school_memberships
    WHERE user_id = auth.uid() AND school_id = $1 AND is_active = TRUE
    AND role IN ('platform_owner', 'school_admin', 'principal')
  );
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION tc_week_start(p_ts TIMESTAMPTZ, p_tz TEXT) RETURNS DATE AS $$
  SELECT (p_ts AT TIME ZONE p_tz)::DATE - EXTRACT(ISODOW FROM (p_ts AT TIME ZONE p_tz))::INTEGER + 1;
$$ LANGUAGE sql STABLE;

-- ============================================================
-- REALTIME PUBLICATION
-- ============================================================
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
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE background_jobs; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
