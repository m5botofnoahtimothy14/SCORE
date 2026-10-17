-- TeachCross combined schema (00001-00008, in order).
-- Generated fallback for Supabase Dashboard SQL editor pasting.
-- Preferred path is still: supabase link + supabase db push.

-- ============================================================
-- SOURCE: 00001_initial_schema.sql
-- ============================================================
-- ============================================================
-- TeachCross: Migration 00001 — Initial Schema
-- ============================================================
-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- ============================================================
-- SCHOOLS
-- ============================================================
CREATE TABLE schools (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
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
  id                          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
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
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
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
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
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
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
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
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
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
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
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
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
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
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
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
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
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
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
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
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
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
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  key             TEXT NOT NULL,                     -- e.g. "otp:+91XXXXXXXXXX"
  action          TEXT NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_rate_limit_key ON rate_limit_events(key, created_at);

-- ============================================================
-- SOURCE: 00002_conversations_messages.sql
-- ============================================================
-- ============================================================
-- TeachCross: Migration 00002 — Conversations & Messages
-- ============================================================

CREATE TYPE conversation_type AS ENUM (
  'student_teacher',      -- 1:1 student ↔ assigned teacher
  'student_support',      -- student + all their authorized teachers
  'staff',                -- teacher ↔ teacher(s)
  'class_channel',        -- class-level (teacher broadcasts)
  'leadership'            -- student/teacher ↔ principal/heads
);

-- ============================================================
-- CONVERSATIONS
-- ============================================================
CREATE TABLE conversations (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  type            conversation_type NOT NULL,
  class_id        UUID REFERENCES classes(id) ON DELETE SET NULL,
  title           TEXT,
  created_by      UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()   -- for sorting
);

CREATE INDEX idx_conversations_school    ON conversations(school_id);
CREATE INDEX idx_conversations_class     ON conversations(class_id);
CREATE INDEX idx_conversations_type      ON conversations(type);
CREATE INDEX idx_conversations_updated   ON conversations(school_id, updated_at DESC);

-- ============================================================
-- CONVERSATION MEMBERS
-- ============================================================
CREATE TYPE member_role AS ENUM ('student', 'teacher', 'admin_observer');

CREATE TABLE conversation_members (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  role            member_role NOT NULL,
  can_send        BOOLEAN NOT NULL DEFAULT TRUE,      -- false for read-only (class channel students)
  joined_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  removed_at      TIMESTAMPTZ,                        -- soft remove
  last_read_at    TIMESTAMPTZ,                        -- for unread counts
  UNIQUE (conversation_id, user_id)
);

CREATE INDEX idx_conv_members_conversation ON conversation_members(conversation_id);
CREATE INDEX idx_conv_members_user         ON conversation_members(user_id);
CREATE INDEX idx_conv_members_active       ON conversation_members(user_id) WHERE removed_at IS NULL;

-- ============================================================
-- MESSAGES
-- ============================================================
CREATE TYPE message_status AS ENUM (
  'pending_moderation',
  'approved',
  'blocked',
  'held_for_review',
  'deleted'
);

CREATE TABLE messages (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  idempotency_key     TEXT NOT NULL UNIQUE,          -- client-generated UUID, prevents duplicates
  conversation_id     UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  school_id           UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  sender_id           UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  body                TEXT,                          -- NULL for attachment-only messages
  status              message_status NOT NULL DEFAULT 'pending_moderation',
  is_deleted          BOOLEAN NOT NULL DEFAULT FALSE,
  deleted_at          TIMESTAMPTZ,
  deleted_by          UUID REFERENCES user_profiles(id),
  reply_to_id         UUID REFERENCES messages(id),
  metadata            JSONB DEFAULT '{}',
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_messages_conversation  ON messages(conversation_id, created_at DESC);
CREATE INDEX idx_messages_sender        ON messages(sender_id);
CREATE INDEX idx_messages_school        ON messages(school_id);
CREATE INDEX idx_messages_status        ON messages(status) WHERE status IN ('pending_moderation', 'held_for_review');
-- Full-text search index
CREATE INDEX idx_messages_fts           ON messages USING gin(to_tsvector('english', coalesce(body, '')));

-- ============================================================
-- MESSAGE RECEIPTS (delivery/read tracking)
-- ============================================================
CREATE TABLE message_receipts (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  message_id      UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  delivered_at    TIMESTAMPTZ,
  read_at         TIMESTAMPTZ,
  UNIQUE (message_id, user_id)
);

CREATE INDEX idx_receipts_message ON message_receipts(message_id);
CREATE INDEX idx_receipts_user    ON message_receipts(user_id);

-- ============================================================
-- ATTACHMENTS
-- ============================================================
CREATE TYPE attachment_type AS ENUM ('image', 'audio', 'document', 'video');
CREATE TYPE attachment_status AS ENUM (
  'uploading',
  'pending_scan',
  'approved',
  'quarantined',
  'rejected'
);

CREATE TABLE attachments (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  message_id      UUID REFERENCES messages(id) ON DELETE SET NULL,
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  uploader_id     UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  type            attachment_type NOT NULL,
  file_name       TEXT NOT NULL,
  mime_type       TEXT NOT NULL,
  size_bytes      BIGINT NOT NULL,
  storage_path    TEXT NOT NULL,                     -- Supabase Storage path
  status          attachment_status NOT NULL DEFAULT 'uploading',
  scan_result     JSONB DEFAULT '{}',                -- moderation scan output
  scanned_at      TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_attachments_message  ON attachments(message_id);
CREATE INDEX idx_attachments_uploader ON attachments(uploader_id);
CREATE INDEX idx_attachments_status   ON attachments(status) WHERE status IN ('pending_scan', 'quarantined');

-- ============================================================
-- STUDENT SUPPORT QUESTION STATES
-- ============================================================
CREATE TYPE question_status AS ENUM ('open', 'in_progress', 'answered', 'resolved');

CREATE TABLE support_questions (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  student_id      UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  status          question_status NOT NULL DEFAULT 'open',
  assigned_teacher_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_support_questions_conv ON support_questions(conversation_id);
CREATE INDEX idx_support_questions_student ON support_questions(student_id);

CREATE TABLE support_question_history (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  question_id     UUID NOT NULL REFERENCES support_questions(id) ON DELETE CASCADE,
  changed_by      UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  from_status     question_status,
  to_status       question_status NOT NULL,
  note            TEXT,
  changed_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- SOURCE: 00003_announcements.sql
-- ============================================================
-- ============================================================
-- TeachCross: Migration 00003 — Announcements
-- ============================================================

CREATE TYPE announcement_audience AS ENUM (
  'school_wide',
  'class',
  'staff',
  'leadership',
  'custom'
);

CREATE TYPE announcement_category AS ENUM (
  'general',
  'academic',
  'event',
  'safety',
  'priority_alert'
);

CREATE TABLE announcements (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id           UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  author_id           UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  title               TEXT NOT NULL,
  body                TEXT NOT NULL,
  category            announcement_category NOT NULL DEFAULT 'general',
  audience_type       announcement_audience NOT NULL,
  class_id            UUID REFERENCES classes(id) ON DELETE SET NULL, -- if audience=class
  requires_ack        BOOLEAN NOT NULL DEFAULT FALSE,
  is_published        BOOLEAN NOT NULL DEFAULT FALSE,
  published_at        TIMESTAMPTZ,
  scheduled_for       TIMESTAMPTZ,                   -- for scheduled publishing
  expires_at          TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_announcements_school     ON announcements(school_id, published_at DESC);
CREATE INDEX idx_announcements_class      ON announcements(class_id);
CREATE INDEX idx_announcements_category   ON announcements(category);
CREATE INDEX idx_announcements_scheduled  ON announcements(scheduled_for) WHERE scheduled_for IS NOT NULL AND is_published = FALSE;

-- ============================================================
-- ANNOUNCEMENT RECIPIENTS (resolved at publish time)
-- ============================================================
CREATE TABLE announcement_recipients (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  announcement_id     UUID NOT NULL REFERENCES announcements(id) ON DELETE CASCADE,
  user_id             UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  notified_at         TIMESTAMPTZ,
  notification_failed BOOLEAN NOT NULL DEFAULT FALSE,
  UNIQUE (announcement_id, user_id)
);

CREATE INDEX idx_announcement_recipients_ann  ON announcement_recipients(announcement_id);
CREATE INDEX idx_announcement_recipients_user ON announcement_recipients(user_id);

-- ============================================================
-- ANNOUNCEMENT ACKNOWLEDGEMENTS
-- ============================================================
CREATE TABLE announcement_receipts (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  announcement_id     UUID NOT NULL REFERENCES announcements(id) ON DELETE CASCADE,
  user_id             UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  read_at             TIMESTAMPTZ,
  acknowledged_at     TIMESTAMPTZ,
  UNIQUE (announcement_id, user_id)
);

CREATE INDEX idx_announcement_receipts_ann  ON announcement_receipts(announcement_id);
CREATE INDEX idx_announcement_receipts_user ON announcement_receipts(user_id);

-- ============================================================
-- SOURCE: 00004_moderation_audit_notifications.sql
-- ============================================================
-- ============================================================
-- TeachCross: Migration 00004 — Moderation, Safeguarding, Audit
-- ============================================================

-- ============================================================
-- MODERATION RESULTS
-- ============================================================
CREATE TYPE moderation_verdict AS ENUM (
  'approved',
  'warned',
  'held',
  'blocked',
  'escalated'
);

CREATE TABLE moderation_results (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  message_id      UUID REFERENCES messages(id) ON DELETE SET NULL,
  attachment_id   UUID REFERENCES attachments(id) ON DELETE SET NULL,
  provider        TEXT NOT NULL,                     -- 'openai'|'google_vision'|'internal'
  verdict         moderation_verdict NOT NULL,
  confidence      NUMERIC(5,4),                      -- 0.0000 – 1.0000
  categories      JSONB DEFAULT '{}',                -- raw category scores
  raw_response    JSONB DEFAULT '{}',
  provider_error  TEXT,                              -- if provider failed
  processed_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_moderation_message    ON moderation_results(message_id);
CREATE INDEX idx_moderation_attachment ON moderation_results(attachment_id);
CREATE INDEX idx_moderation_verdict    ON moderation_results(verdict) WHERE verdict IN ('held', 'blocked', 'escalated');

-- ============================================================
-- MODERATION REVIEW CASES
-- ============================================================
CREATE TYPE review_status AS ENUM (
  'pending',
  'under_review',
  'approved',
  'rejected',
  'escalated',
  'closed'
);

CREATE TABLE moderation_review_cases (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id           UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  moderation_result_id UUID REFERENCES moderation_results(id),
  reported_by         UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  assigned_to         UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  status              review_status NOT NULL DEFAULT 'pending',
  reason_code         TEXT,
  reviewer_notes      TEXT,
  disposition         TEXT,                          -- final decision text
  closed_at           TIMESTAMPTZ,
  closed_by           UUID REFERENCES user_profiles(id),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_review_cases_school   ON moderation_review_cases(school_id);
CREATE INDEX idx_review_cases_status   ON moderation_review_cases(status) WHERE status IN ('pending', 'under_review');
CREATE INDEX idx_review_cases_assigned ON moderation_review_cases(assigned_to);

-- ============================================================
-- SAFEGUARDING INCIDENTS
-- ============================================================
CREATE TYPE incident_severity AS ENUM ('low', 'medium', 'high', 'critical');
CREATE TYPE incident_status AS ENUM (
  'open',
  'investigating',
  'escalated_external',
  'resolved',
  'closed'
);

CREATE TABLE safeguarding_incidents (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id           UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  review_case_id      UUID REFERENCES moderation_review_cases(id),
  title               TEXT NOT NULL,
  description         TEXT,
  severity            incident_severity NOT NULL DEFAULT 'medium',
  status              incident_status NOT NULL DEFAULT 'open',
  involved_user_ids   UUID[] DEFAULT '{}',           -- users involved (restricted access)
  assigned_to         UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  investigation_notes TEXT,                          -- restricted field
  legal_reference     TEXT,
  resolved_at         TIMESTAMPTZ,
  resolved_by         UUID REFERENCES user_profiles(id),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_incidents_school  ON safeguarding_incidents(school_id);
CREATE INDEX idx_incidents_status  ON safeguarding_incidents(status);
CREATE INDEX idx_incidents_severity ON safeguarding_incidents(severity);

-- ============================================================
-- MESSAGE REPORTS (user-submitted)
-- ============================================================
CREATE TABLE message_reports (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  reporter_id     UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  message_id      UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  reason          TEXT NOT NULL,
  details         TEXT,
  review_case_id  UUID REFERENCES moderation_review_cases(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (reporter_id, message_id)                   -- one report per user per message
);

CREATE INDEX idx_message_reports_school ON message_reports(school_id);
CREATE INDEX idx_message_reports_message ON message_reports(message_id);

-- ============================================================
-- AUDIT EVENTS
-- ============================================================
CREATE TABLE audit_events (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id       UUID REFERENCES schools(id) ON DELETE SET NULL,
  actor_id        UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  action          TEXT NOT NULL,                     -- e.g. 'user.suspend', 'roster.import'
  target_type     TEXT,                              -- e.g. 'user', 'class', 'message'
  target_id       TEXT,                              -- UUID or other identifier
  outcome         TEXT NOT NULL,                     -- 'success'|'failure'|'rejected'
  reason          TEXT,
  correlation_id  TEXT,                              -- request/job trace ID
  ip_address      INET,
  metadata        JSONB DEFAULT '{}',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_school      ON audit_events(school_id, created_at DESC);
CREATE INDEX idx_audit_actor       ON audit_events(actor_id, created_at DESC);
CREATE INDEX idx_audit_action      ON audit_events(action);
CREATE INDEX idx_audit_target      ON audit_events(target_type, target_id);

-- Audit records are append-only; revoke UPDATE/DELETE from all roles except superuser
-- (enforced via RLS below)

-- ============================================================
-- INVESTIGATION REQUESTS
-- ============================================================
CREATE TYPE investigation_status AS ENUM (
  'requested',
  'approved',
  'active',
  'expired',
  'revoked',
  'closed'
);

CREATE TABLE investigation_requests (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id           UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  incident_id         UUID REFERENCES safeguarding_incidents(id),
  requested_by        UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  purpose             TEXT NOT NULL,
  legal_authorization TEXT,
  scope_description   TEXT NOT NULL,
  status              investigation_status NOT NULL DEFAULT 'requested',
  approved_by         UUID REFERENCES user_profiles(id),
  approved_at         TIMESTAMPTZ,
  access_expires_at   TIMESTAMPTZ,
  revoked_at          TIMESTAMPTZ,
  revoked_by          UUID REFERENCES user_profiles(id),
  closed_at           TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE investigation_approvals (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  request_id          UUID NOT NULL REFERENCES investigation_requests(id) ON DELETE CASCADE,
  approver_id         UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  decision            TEXT NOT NULL,                 -- 'approved'|'rejected'
  notes               TEXT,
  decided_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE investigation_access_events (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  request_id          UUID NOT NULL REFERENCES investigation_requests(id) ON DELETE CASCADE,
  investigator_id     UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  resource_type       TEXT NOT NULL,
  resource_id         TEXT NOT NULL,
  accessed_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- NOTIFICATION DEVICES (FCM tokens)
-- ============================================================
CREATE TABLE notification_devices (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  fcm_token       TEXT NOT NULL,
  device_id       TEXT,
  platform        TEXT NOT NULL DEFAULT 'android',
  app_version     TEXT,
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  registered_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at    TIMESTAMPTZ,
  UNIQUE (fcm_token)
);

CREATE INDEX idx_notification_devices_user   ON notification_devices(user_id);
CREATE INDEX idx_notification_devices_school ON notification_devices(school_id);
CREATE INDEX idx_notification_devices_active ON notification_devices(user_id) WHERE is_active = TRUE;

-- ============================================================
-- NOTIFICATION JOBS
-- ============================================================
CREATE TYPE notification_job_status AS ENUM ('pending', 'sent', 'failed', 'skipped');

CREATE TABLE notification_jobs (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  recipient_id    UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  device_id       UUID REFERENCES notification_devices(id) ON DELETE SET NULL,
  type            TEXT NOT NULL,                     -- 'message'|'announcement'|'alert'
  title           TEXT NOT NULL,
  body            TEXT NOT NULL,
  data            JSONB DEFAULT '{}',                -- deep link data
  status          notification_job_status NOT NULL DEFAULT 'pending',
  sent_at         TIMESTAMPTZ,
  failed_at       TIMESTAMPTZ,
  failure_reason  TEXT,
  idempotency_key TEXT UNIQUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notif_jobs_recipient ON notification_jobs(recipient_id);
CREATE INDEX idx_notif_jobs_status    ON notification_jobs(status) WHERE status = 'pending';

-- ============================================================
-- SUPPORT TICKETS
-- ============================================================
CREATE TYPE ticket_status AS ENUM ('open', 'in_progress', 'resolved', 'closed');

CREATE TABLE support_tickets (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  submitted_by    UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  assigned_to     UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  category        TEXT NOT NULL,
  subject         TEXT NOT NULL,
  description     TEXT NOT NULL,
  status          ticket_status NOT NULL DEFAULT 'open',
  resolved_at     TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- DATA RETENTION POLICIES
-- ============================================================
CREATE TABLE data_retention_policies (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  data_type       TEXT NOT NULL,                     -- 'messages'|'attachments'|'audit_events'
  retention_days  INTEGER NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (school_id, data_type)
);

-- Background jobs tracking
CREATE TYPE job_status AS ENUM ('queued', 'running', 'completed', 'failed', 'retrying');

CREATE TABLE background_jobs (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  type            TEXT NOT NULL,
  status          job_status NOT NULL DEFAULT 'queued',
  payload         JSONB DEFAULT '{}',
  attempts        INTEGER NOT NULL DEFAULT 0,
  max_attempts    INTEGER NOT NULL DEFAULT 3,
  last_error      TEXT,
  scheduled_for   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  started_at      TIMESTAMPTZ,
  completed_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_background_jobs_status ON background_jobs(status, scheduled_for) WHERE status IN ('queued', 'retrying');

-- ============================================================
-- SOURCE: 00005_rls_policies.sql
-- ============================================================
-- ============================================================
-- TeachCross: Migration 00005 — Row-Level Security Policies
-- ============================================================
-- This is the security layer. All policies enforce multi-tenant
-- isolation and role-based access. Never trust client-supplied IDs.
-- ============================================================

-- Helper function: get authenticated user's school memberships
CREATE OR REPLACE FUNCTION auth.user_school_ids()
RETURNS UUID[] AS $$
  SELECT ARRAY(
    SELECT school_id FROM school_memberships
    WHERE user_id = auth.uid() AND is_active = TRUE
  )
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Helper: check if user has a role in a school
CREATE OR REPLACE FUNCTION auth.has_school_role(p_school_id UUID, p_role school_role)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM school_memberships
    WHERE user_id = auth.uid()
      AND school_id = p_school_id
      AND role = p_role
      AND is_active = TRUE
  )
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Helper: check if user is admin or above in a school
CREATE OR REPLACE FUNCTION auth.is_school_admin(p_school_id UUID)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM school_memberships
    WHERE user_id = auth.uid()
      AND school_id = p_school_id
      AND role IN ('platform_owner', 'school_admin', 'principal')
      AND is_active = TRUE
  )
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Helper: check if user is platform owner
CREATE OR REPLACE FUNCTION auth.is_platform_owner()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM school_memberships
    WHERE user_id = auth.uid()
      AND role = 'platform_owner'
      AND is_active = TRUE
  )
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Helper: check conversation membership (active)
CREATE OR REPLACE FUNCTION auth.is_conversation_member(p_conversation_id UUID)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM conversation_members
    WHERE conversation_id = p_conversation_id
      AND user_id = auth.uid()
      AND removed_at IS NULL
  )
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Helper: get user's teacher record ID for a school
CREATE OR REPLACE FUNCTION auth.my_teacher_id(p_school_id UUID)
RETURNS UUID AS $$
  SELECT id FROM teachers
  WHERE user_id = auth.uid() AND school_id = p_school_id
  LIMIT 1
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Helper: get user's student record ID for a school
CREATE OR REPLACE FUNCTION auth.my_student_id(p_school_id UUID)
RETURNS UUID AS $$
  SELECT id FROM students
  WHERE user_id = auth.uid() AND school_id = p_school_id
  LIMIT 1
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- ============================================================
-- ENABLE RLS ON ALL TABLES
-- ============================================================
ALTER TABLE schools                       ENABLE ROW LEVEL SECURITY;
ALTER TABLE school_settings               ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_profiles                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE school_memberships            ENABLE ROW LEVEL SECURITY;
ALTER TABLE academic_years                ENABLE ROW LEVEL SECURITY;
ALTER TABLE subjects                      ENABLE ROW LEVEL SECURITY;
ALTER TABLE classes                       ENABLE ROW LEVEL SECURITY;
ALTER TABLE students                      ENABLE ROW LEVEL SECURITY;
ALTER TABLE teachers                      ENABLE ROW LEVEL SECURITY;
ALTER TABLE class_enrollments             ENABLE ROW LEVEL SECURITY;
ALTER TABLE teaching_assignments          ENABLE ROW LEVEL SECURITY;
ALTER TABLE student_activation_credentials ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_activation_records      ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversation_members          ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages                      ENABLE ROW LEVEL SECURITY;
ALTER TABLE message_receipts              ENABLE ROW LEVEL SECURITY;
ALTER TABLE attachments                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE announcements                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE announcement_recipients       ENABLE ROW LEVEL SECURITY;
ALTER TABLE announcement_receipts         ENABLE ROW LEVEL SECURITY;
ALTER TABLE moderation_results            ENABLE ROW LEVEL SECURITY;
ALTER TABLE moderation_review_cases       ENABLE ROW LEVEL SECURITY;
ALTER TABLE safeguarding_incidents        ENABLE ROW LEVEL SECURITY;
ALTER TABLE message_reports               ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_events                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE investigation_requests        ENABLE ROW LEVEL SECURITY;
ALTER TABLE investigation_approvals       ENABLE ROW LEVEL SECURITY;
ALTER TABLE investigation_access_events   ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_devices          ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_jobs             ENABLE ROW LEVEL SECURITY;
ALTER TABLE support_tickets               ENABLE ROW LEVEL SECURITY;
ALTER TABLE data_retention_policies       ENABLE ROW LEVEL SECURITY;
ALTER TABLE background_jobs               ENABLE ROW LEVEL SECURITY;
ALTER TABLE support_questions             ENABLE ROW LEVEL SECURITY;
ALTER TABLE support_question_history      ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- SCHOOLS — read for members, write for admins
-- ============================================================
CREATE POLICY schools_select ON schools FOR SELECT
  USING (id = ANY(auth.user_school_ids()));

CREATE POLICY schools_admin_all ON schools FOR ALL
  USING (auth.is_platform_owner());

-- ============================================================
-- SCHOOL_SETTINGS — read for admins of that school
-- ============================================================
CREATE POLICY school_settings_select ON school_settings FOR SELECT
  USING (auth.is_school_admin(school_id));

CREATE POLICY school_settings_update ON school_settings FOR UPDATE
  USING (auth.is_school_admin(school_id));

-- ============================================================
-- USER_PROFILES — users can see their own profile;
-- school members can see other members of shared schools
-- ============================================================
CREATE POLICY user_profiles_own ON user_profiles FOR ALL
  USING (id = auth.uid());

CREATE POLICY user_profiles_school_member ON user_profiles FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM school_memberships sm
      WHERE sm.user_id = user_profiles.id
        AND sm.school_id = ANY(auth.user_school_ids())
        AND sm.is_active = TRUE
    )
  );

-- ============================================================
-- SCHOOL_MEMBERSHIPS
-- ============================================================
CREATE POLICY memberships_own ON school_memberships FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY memberships_admin_school ON school_memberships FOR ALL
  USING (auth.is_school_admin(school_id));

-- ============================================================
-- ACADEMIC_YEARS, SUBJECTS, CLASSES — school members read
-- ============================================================
CREATE POLICY academic_years_select ON academic_years FOR SELECT
  USING (school_id = ANY(auth.user_school_ids()));

CREATE POLICY academic_years_admin ON academic_years FOR ALL
  USING (auth.is_school_admin(school_id));

CREATE POLICY subjects_select ON subjects FOR SELECT
  USING (school_id = ANY(auth.user_school_ids()));

CREATE POLICY subjects_admin ON subjects FOR ALL
  USING (auth.is_school_admin(school_id));

CREATE POLICY classes_select ON classes FOR SELECT
  USING (school_id = ANY(auth.user_school_ids()));

CREATE POLICY classes_admin ON classes FOR ALL
  USING (auth.is_school_admin(school_id));

-- ============================================================
-- STUDENTS — admins see all; teachers see their class students;
-- students see only themselves
-- ============================================================
CREATE POLICY students_admin ON students FOR ALL
  USING (auth.is_school_admin(school_id));

CREATE POLICY students_own ON students FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY students_teacher_view ON students FOR SELECT
  USING (
    school_id = ANY(auth.user_school_ids())
    AND EXISTS (
      SELECT 1 FROM teaching_assignments ta
        JOIN class_enrollments ce ON ce.class_id = ta.class_id
        JOIN teachers t ON t.id = ta.teacher_id
      WHERE t.user_id = auth.uid()
        AND ce.student_id = students.id
        AND ce.unenrolled_at IS NULL
    )
  );

-- ============================================================
-- TEACHERS — admins see all; teachers see colleagues in same school;
-- students see only their assigned teachers
-- ============================================================
CREATE POLICY teachers_admin ON teachers FOR ALL
  USING (auth.is_school_admin(school_id));

CREATE POLICY teachers_own ON teachers FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY teachers_colleague ON teachers FOR SELECT
  USING (
    school_id = ANY(auth.user_school_ids())
    AND auth.has_school_role(school_id, 'teacher')
  );

CREATE POLICY teachers_student_view ON teachers FOR SELECT
  USING (
    school_id = ANY(auth.user_school_ids())
    AND auth.has_school_role(school_id, 'student')
    AND EXISTS (
      SELECT 1 FROM teaching_assignments ta
        JOIN class_enrollments ce ON ce.class_id = ta.class_id
        JOIN students s ON s.id = ce.student_id
      WHERE ta.teacher_id = teachers.id
        AND s.user_id = auth.uid()
        AND ce.unenrolled_at IS NULL
    )
  );

-- ============================================================
-- CLASS_ENROLLMENTS & TEACHING_ASSIGNMENTS — admins full access
-- ============================================================
CREATE POLICY class_enrollments_admin ON class_enrollments FOR ALL
  USING (auth.is_school_admin(school_id));

CREATE POLICY class_enrollments_teacher ON class_enrollments FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM teaching_assignments ta
        JOIN teachers t ON t.id = ta.teacher_id
      WHERE ta.class_id = class_enrollments.class_id
        AND t.user_id = auth.uid()
    )
  );

CREATE POLICY class_enrollments_student ON class_enrollments FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM students s
      WHERE s.id = class_enrollments.student_id
        AND s.user_id = auth.uid()
    )
  );

CREATE POLICY teaching_assignments_admin ON teaching_assignments FOR ALL
  USING (auth.is_school_admin(school_id));

CREATE POLICY teaching_assignments_read ON teaching_assignments FOR SELECT
  USING (school_id = ANY(auth.user_school_ids()));

-- ============================================================
-- ACTIVATION CREDENTIALS — admin only (no student self-read!)
-- ============================================================
CREATE POLICY student_credentials_admin ON student_activation_credentials FOR ALL
  USING (auth.is_school_admin(school_id));

CREATE POLICY staff_activation_own ON staff_activation_records FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM teachers t
      WHERE t.id = staff_activation_records.teacher_id
        AND t.user_id = auth.uid()
    )
  );

CREATE POLICY staff_activation_admin ON staff_activation_records FOR ALL
  USING (auth.is_school_admin(school_id));

-- ============================================================
-- CONVERSATIONS — only members can see their conversations
-- ============================================================
CREATE POLICY conversations_member ON conversations FOR SELECT
  USING (auth.is_conversation_member(id));

CREATE POLICY conversations_admin ON conversations FOR ALL
  USING (auth.is_school_admin(school_id));

-- ============================================================
-- CONVERSATION_MEMBERS — only see members of your own conversations
-- ============================================================
CREATE POLICY conv_members_read ON conversation_members FOR SELECT
  USING (
    auth.is_conversation_member(conversation_id)
    OR user_id = auth.uid()
  );

CREATE POLICY conv_members_admin ON conversation_members FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM conversations c
      WHERE c.id = conversation_members.conversation_id
        AND auth.is_school_admin(c.school_id)
    )
  );

-- ============================================================
-- MESSAGES — CRITICAL: only approved messages visible to members
-- Students can only see approved messages in their own conversations
-- ============================================================
CREATE POLICY messages_member_read ON messages FOR SELECT
  USING (
    auth.is_conversation_member(conversation_id)
    AND (
      status = 'approved'
      OR sender_id = auth.uid()         -- can see own pending messages
    )
    AND is_deleted = FALSE
  );

CREATE POLICY messages_insert ON messages FOR INSERT
  WITH CHECK (
    sender_id = auth.uid()              -- must be the actual sender
    AND auth.is_conversation_member(conversation_id)
    AND EXISTS (
      SELECT 1 FROM conversation_members cm
      WHERE cm.conversation_id = messages.conversation_id
        AND cm.user_id = auth.uid()
        AND cm.can_send = TRUE
        AND cm.removed_at IS NULL
    )
  );

CREATE POLICY messages_admin_read ON messages FOR SELECT
  USING (auth.is_school_admin(school_id));

CREATE POLICY messages_admin_update ON messages FOR UPDATE
  USING (auth.is_school_admin(school_id));

-- ============================================================
-- ATTACHMENTS — only approved, conversation members can access
-- ============================================================
CREATE POLICY attachments_member_read ON attachments FOR SELECT
  USING (
    uploader_id = auth.uid()
    OR (
      status = 'approved'
      AND EXISTS (
        SELECT 1 FROM messages m
        WHERE m.id = attachments.message_id
          AND auth.is_conversation_member(m.conversation_id)
      )
    )
  );

CREATE POLICY attachments_insert ON attachments FOR INSERT
  WITH CHECK (uploader_id = auth.uid());

CREATE POLICY attachments_admin ON attachments FOR ALL
  USING (auth.is_school_admin(school_id));

-- ============================================================
-- ANNOUNCEMENTS — published announcements visible to recipients
-- ============================================================
CREATE POLICY announcements_recipient ON announcements FOR SELECT
  USING (
    is_published = TRUE
    AND EXISTS (
      SELECT 1 FROM announcement_recipients ar
      WHERE ar.announcement_id = announcements.id
        AND ar.user_id = auth.uid()
    )
  );

CREATE POLICY announcements_admin ON announcements FOR ALL
  USING (auth.is_school_admin(school_id));

CREATE POLICY announcements_teacher_insert ON announcements FOR INSERT
  WITH CHECK (
    author_id = auth.uid()
    AND auth.has_school_role(school_id, 'teacher')
    AND audience_type NOT IN ('school_wide')   -- teachers can't broadcast school-wide
  );

-- ============================================================
-- ANNOUNCEMENT_RECIPIENTS & RECEIPTS
-- ============================================================
CREATE POLICY ann_recipients_own ON announcement_recipients FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY ann_recipients_admin ON announcement_recipients FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM announcements a
      WHERE a.id = announcement_recipients.announcement_id
        AND auth.is_school_admin(a.school_id)
    )
  );

CREATE POLICY ann_receipts_own ON announcement_receipts FOR ALL
  USING (user_id = auth.uid());

CREATE POLICY ann_receipts_admin ON announcement_receipts FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM announcements a
      WHERE a.id = announcement_receipts.announcement_id
        AND auth.is_school_admin(a.school_id)
    )
  );

-- ============================================================
-- MODERATION — admin only
-- ============================================================
CREATE POLICY moderation_results_admin ON moderation_results FOR ALL
  USING (auth.is_school_admin(school_id));

CREATE POLICY review_cases_admin ON moderation_review_cases FOR ALL
  USING (auth.is_school_admin(school_id));

-- ============================================================
-- SAFEGUARDING — admin + assigned reviewer only
-- ============================================================
CREATE POLICY incidents_admin ON safeguarding_incidents FOR ALL
  USING (auth.is_school_admin(school_id));

CREATE POLICY incidents_assigned ON safeguarding_incidents FOR SELECT
  USING (assigned_to = auth.uid());

-- ============================================================
-- MESSAGE REPORTS — reporters can see their own; admins see all
-- ============================================================
CREATE POLICY reports_own ON message_reports FOR ALL
  USING (reporter_id = auth.uid());

CREATE POLICY reports_admin ON message_reports FOR SELECT
  USING (auth.is_school_admin(school_id));

-- ============================================================
-- AUDIT EVENTS — READ ONLY for admins; NO UPDATE/DELETE
-- ============================================================
CREATE POLICY audit_admin_read ON audit_events FOR SELECT
  USING (
    (school_id IS NULL AND auth.is_platform_owner())
    OR auth.is_school_admin(school_id)
  );

-- Intentionally NO UPDATE or DELETE policy — audit records are immutable
-- Even admins cannot modify audit history via RLS

-- ============================================================
-- INVESTIGATION REQUESTS — platform owner + school admin
-- ============================================================
CREATE POLICY investigation_admin ON investigation_requests FOR ALL
  USING (auth.is_school_admin(school_id) OR auth.is_platform_owner());

CREATE POLICY investigation_requested_by ON investigation_requests FOR SELECT
  USING (requested_by = auth.uid());

CREATE POLICY inv_approvals_admin ON investigation_approvals FOR ALL
  USING (auth.is_platform_owner());

CREATE POLICY inv_access_events_admin ON investigation_access_events FOR ALL
  USING (auth.is_platform_owner());

-- ============================================================
-- NOTIFICATION DEVICES — own only; admins can see for their school
-- ============================================================
CREATE POLICY notif_devices_own ON notification_devices FOR ALL
  USING (user_id = auth.uid());

CREATE POLICY notif_devices_admin ON notification_devices FOR SELECT
  USING (auth.is_school_admin(school_id));

-- ============================================================
-- NOTIFICATION JOBS — user sees own; admins see school
-- ============================================================
CREATE POLICY notif_jobs_own ON notification_jobs FOR SELECT
  USING (recipient_id = auth.uid());

CREATE POLICY notif_jobs_admin ON notification_jobs FOR ALL
  USING (auth.is_school_admin(school_id));

-- ============================================================
-- SUPPORT TICKETS — own; admin sees all for school
-- ============================================================
CREATE POLICY tickets_own ON support_tickets FOR ALL
  USING (submitted_by = auth.uid());

CREATE POLICY tickets_admin ON support_tickets FOR ALL
  USING (auth.is_school_admin(school_id));

-- ============================================================
-- BACKGROUND JOBS — platform admin only
-- ============================================================
CREATE POLICY background_jobs_platform ON background_jobs FOR ALL
  USING (auth.is_platform_owner());

-- ============================================================
-- SUPPORT QUESTIONS
-- ============================================================
CREATE POLICY support_questions_student ON support_questions FOR ALL
  USING (student_id = auth.uid());

CREATE POLICY support_questions_teacher ON support_questions FOR SELECT
  USING (auth.is_conversation_member(conversation_id));

CREATE POLICY support_questions_admin ON support_questions FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM conversations c
      WHERE c.id = support_questions.conversation_id
        AND auth.is_school_admin(c.school_id)
    )
  );

CREATE POLICY support_q_history_read ON support_question_history FOR SELECT
  USING (changed_by = auth.uid() OR
    EXISTS (
      SELECT 1 FROM support_questions sq
        JOIN conversations c ON c.id = sq.conversation_id
      WHERE sq.id = support_question_history.question_id
        AND (auth.is_school_admin(c.school_id)
             OR auth.is_conversation_member(sq.conversation_id))
    )
  );

-- ============================================================
-- SOURCE: 00006_functions_triggers.sql
-- ============================================================
-- ============================================================
-- TeachCross: Migration 00006 — Database Functions & Triggers
-- ============================================================

-- Auto-update updated_at timestamps
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER schools_updated_at          BEFORE UPDATE ON schools          FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER school_settings_updated_at  BEFORE UPDATE ON school_settings  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER user_profiles_updated_at    BEFORE UPDATE ON user_profiles    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER students_updated_at         BEFORE UPDATE ON students         FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER teachers_updated_at         BEFORE UPDATE ON teachers         FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER conversations_updated_at    BEFORE UPDATE ON conversations    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER messages_updated_at         BEFORE UPDATE ON messages         FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER announcements_updated_at    BEFORE UPDATE ON announcements    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER review_cases_updated_at     BEFORE UPDATE ON moderation_review_cases FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER incidents_updated_at        BEFORE UPDATE ON safeguarding_incidents  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER tickets_updated_at          BEFORE UPDATE ON support_tickets  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER support_q_updated_at        BEFORE UPDATE ON support_questions FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Update conversation updated_at when a new message arrives
CREATE OR REPLACE FUNCTION update_conversation_on_message()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE conversations SET updated_at = NOW()
  WHERE id = NEW.conversation_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER messages_update_conversation
  AFTER INSERT ON messages
  FOR EACH ROW EXECUTE FUNCTION update_conversation_on_message();

-- ============================================================
-- SECURE STUDENT ACTIVATION
-- Validates activation code and creates user membership
-- Called from Edge Function (service role) — NOT directly by client
-- ============================================================
CREATE OR REPLACE FUNCTION activate_student(
  p_school_id       UUID,
  p_student_id_no   TEXT,
  p_activation_code TEXT,
  p_auth_user_id    UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_student         students%ROWTYPE;
  v_credential      student_activation_credentials%ROWTYPE;
  v_class_id        UUID;
BEGIN
  -- 1. Find student record (timing-safe: don't reveal existence via error detail)
  SELECT * INTO v_student
  FROM students
  WHERE school_id = p_school_id
    AND student_id_no = p_student_id_no
    AND is_active = TRUE;

  IF NOT FOUND THEN
    -- Generic error: do not reveal whether ID exists
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_credentials');
  END IF;

  -- 2. Check activation credential
  SELECT * INTO v_credential
  FROM student_activation_credentials
  WHERE student_id = v_student.id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'no_activation_code');
  END IF;

  IF v_credential.used_at IS NOT NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'code_already_used');
  END IF;

  IF v_credential.expires_at < NOW() THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'code_expired');
  END IF;

  -- 3. Verify code (bcrypt comparison done server-side)
  IF v_credential.code != crypt(p_activation_code, v_credential.code) THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_credentials');
  END IF;

  -- 4. Mark code used
  UPDATE student_activation_credentials
  SET used_at = NOW()
  WHERE id = v_credential.id;

  -- 5. Link auth user to student record
  UPDATE students SET user_id = p_auth_user_id, updated_at = NOW()
  WHERE id = v_student.id;

  -- 6. Create user_profile if not exists
  INSERT INTO user_profiles(id, display_name, is_active)
  VALUES (p_auth_user_id, v_student.first_name || ' ' || v_student.last_name, TRUE)
  ON CONFLICT (id) DO NOTHING;

  -- 7. Create school membership
  INSERT INTO school_memberships(user_id, school_id, role, is_active)
  VALUES (p_auth_user_id, p_school_id, 'student', TRUE)
  ON CONFLICT (user_id, school_id, role) DO UPDATE SET is_active = TRUE;

  -- 8. Get current class enrollment
  SELECT ce.class_id INTO v_class_id
  FROM class_enrollments ce
  WHERE ce.student_id = v_student.id
    AND ce.unenrolled_at IS NULL
  LIMIT 1;

  -- 9. Create support conversation if not exists
  IF v_class_id IS NOT NULL THEN
    PERFORM create_student_support_conversation(v_student.id, v_class_id, p_school_id, p_auth_user_id);
  END IF;

  RETURN jsonb_build_object(
    'success', TRUE,
    'student_id', v_student.id,
    'class_id', v_class_id
  );
END;
$$;

-- ============================================================
-- CREATE STUDENT SUPPORT CONVERSATION
-- Creates the student ↔ their teachers support conversation
-- ============================================================
CREATE OR REPLACE FUNCTION create_student_support_conversation(
  p_student_id    UUID,
  p_class_id      UUID,
  p_school_id     UUID,
  p_student_user_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_conv_id UUID;
  v_teacher RECORD;
BEGIN
  -- Check if already exists
  SELECT c.id INTO v_conv_id
  FROM conversations c
    JOIN conversation_members cm ON cm.conversation_id = c.id
  WHERE c.school_id = p_school_id
    AND c.type = 'student_support'
    AND c.class_id = p_class_id
    AND cm.user_id = p_student_user_id
    AND cm.role = 'student'
    AND cm.removed_at IS NULL
  LIMIT 1;

  IF v_conv_id IS NOT NULL THEN
    RETURN v_conv_id;
  END IF;

  -- Create the conversation
  INSERT INTO conversations(school_id, type, class_id, created_by, title)
  VALUES (p_school_id, 'student_support', p_class_id, p_student_user_id, 'Teacher Support')
  RETURNING id INTO v_conv_id;

  -- Add student as member (can send)
  INSERT INTO conversation_members(conversation_id, user_id, role, can_send)
  VALUES (v_conv_id, p_student_user_id, 'student', TRUE);

  -- Add all teachers assigned to this class
  FOR v_teacher IN
    SELECT t.user_id
    FROM teaching_assignments ta
      JOIN teachers t ON t.id = ta.teacher_id
    WHERE ta.class_id = p_class_id
      AND t.user_id IS NOT NULL
      AND t.is_active = TRUE
  LOOP
    INSERT INTO conversation_members(conversation_id, user_id, role, can_send)
    VALUES (v_conv_id, v_teacher.user_id, 'teacher', TRUE)
    ON CONFLICT (conversation_id, user_id) DO NOTHING;
  END LOOP;

  RETURN v_conv_id;
END;
$$;

-- ============================================================
-- SECURE TEACHER ACTIVATION
-- Called from Edge Function after OTP verification
-- ============================================================
CREATE OR REPLACE FUNCTION activate_teacher(
  p_school_id       UUID,
  p_staff_id_no     TEXT,
  p_auth_user_id    UUID,
  p_phone           TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_teacher teachers%ROWTYPE;
  v_class   RECORD;
BEGIN
  -- Find teacher in roster
  SELECT * INTO v_teacher
  FROM teachers
  WHERE school_id = p_school_id
    AND staff_id_no = p_staff_id_no
    AND is_active = TRUE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_credentials');
  END IF;

  -- Verify phone matches roster (anti-impersonation)
  IF v_teacher.phone != p_phone THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_credentials');
  END IF;

  -- Link auth user
  UPDATE teachers SET user_id = p_auth_user_id, updated_at = NOW()
  WHERE id = v_teacher.id;

  -- Create profile
  INSERT INTO user_profiles(id, display_name, phone, is_active)
  VALUES (p_auth_user_id, v_teacher.first_name || ' ' || v_teacher.last_name, p_phone, TRUE)
  ON CONFLICT (id) DO UPDATE SET phone = p_phone, display_name = EXCLUDED.display_name;

  -- Create membership with appropriate role
  INSERT INTO school_memberships(user_id, school_id, role, is_active)
  VALUES (
    p_auth_user_id,
    p_school_id,
    CASE WHEN v_teacher.is_leadership THEN 'head_teacher' ELSE 'teacher' END,
    TRUE
  )
  ON CONFLICT (user_id, school_id, role) DO UPDATE SET is_active = TRUE;

  -- Create staff conversations with assigned class students who are already activated
  FOR v_class IN
    SELECT DISTINCT ta.class_id FROM teaching_assignments ta
    WHERE ta.teacher_id = v_teacher.id
  LOOP
    -- The student support conversations will include this teacher
    -- (handled retroactively when teacher activates after students)
    INSERT INTO conversation_members(conversation_id, user_id, role, can_send)
    SELECT c.id, p_auth_user_id, 'teacher', TRUE
    FROM conversations c
      JOIN conversation_members cm ON cm.conversation_id = c.id AND cm.role = 'student'
      JOIN students s ON s.user_id = cm.user_id
      JOIN class_enrollments ce ON ce.student_id = s.id AND ce.class_id = v_class.class_id AND ce.unenrolled_at IS NULL
    WHERE c.school_id = p_school_id
      AND c.type = 'student_support'
      AND c.class_id = v_class.class_id
    ON CONFLICT (conversation_id, user_id) DO NOTHING;
  END LOOP;

  RETURN jsonb_build_object('success', TRUE, 'teacher_id', v_teacher.id);
END;
$$;

-- ============================================================
-- SEND MESSAGE (enforces all security checks server-side)
-- ============================================================
CREATE OR REPLACE FUNCTION send_message(
  p_conversation_id UUID,
  p_sender_id       UUID,
  p_body            TEXT,
  p_idempotency_key TEXT,
  p_reply_to_id     UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_conv conversations%ROWTYPE;
  v_member conversation_members%ROWTYPE;
  v_msg_id UUID;
  v_school_id UUID;
BEGIN
  -- 1. Verify caller is the sender
  IF p_sender_id != auth.uid() THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'forbidden');
  END IF;

  -- 2. Get conversation
  SELECT * INTO v_conv FROM conversations WHERE id = p_conversation_id;
  IF NOT FOUND OR NOT v_conv.is_active THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'conversation_not_found');
  END IF;

  v_school_id := v_conv.school_id;

  -- 3. Verify membership and send permission
  SELECT * INTO v_member
  FROM conversation_members
  WHERE conversation_id = p_conversation_id
    AND user_id = p_sender_id
    AND removed_at IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_a_member');
  END IF;

  IF NOT v_member.can_send THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'send_not_permitted');
  END IF;

  -- 4. Block student-to-student: class_channel students cannot send
  IF v_conv.type = 'class_channel' AND v_member.role = 'student' THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'students_cannot_send_in_class_channel');
  END IF;

  -- 5. Validate body
  IF p_body IS NULL OR length(trim(p_body)) = 0 THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'empty_message');
  END IF;

  IF length(p_body) > 4000 THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'message_too_long');
  END IF;

  -- 6. Insert message (starts as pending_moderation)
  INSERT INTO messages(
    idempotency_key, conversation_id, school_id,
    sender_id, body, status, reply_to_id
  )
  VALUES (
    p_idempotency_key, p_conversation_id, v_school_id,
    p_sender_id, p_body, 'pending_moderation', p_reply_to_id
  )
  ON CONFLICT (idempotency_key) DO NOTHING
  RETURNING id INTO v_msg_id;

  IF v_msg_id IS NULL THEN
    -- Duplicate — return the existing message id
    SELECT id INTO v_msg_id FROM messages WHERE idempotency_key = p_idempotency_key;
    RETURN jsonb_build_object('success', TRUE, 'message_id', v_msg_id, 'duplicate', TRUE);
  END IF;

  -- 7. Log audit event
  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome)
  VALUES (v_school_id, p_sender_id, 'message.send', 'message', v_msg_id::TEXT, 'success');

  RETURN jsonb_build_object('success', TRUE, 'message_id', v_msg_id);
END;
$$;

-- ============================================================
-- PLATFORM BOOTSTRAP — create initial platform owner
-- Called ONCE during deployment via service role
-- ============================================================
CREATE OR REPLACE FUNCTION bootstrap_platform_owner(
  p_email     TEXT,
  p_school_name TEXT,
  p_school_code TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_school_id UUID;
  v_existing_count INTEGER;
BEGIN
  -- Prevent re-bootstrap if platform owners already exist
  SELECT COUNT(*) INTO v_existing_count
  FROM school_memberships WHERE role = 'platform_owner';

  IF v_existing_count > 0 THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'already_bootstrapped');
  END IF;

  -- Create first school
  INSERT INTO schools(name, code) VALUES (p_school_name, p_school_code)
  RETURNING id INTO v_school_id;

  INSERT INTO school_settings(school_id) VALUES (v_school_id);

  RETURN jsonb_build_object(
    'success', TRUE,
    'school_id', v_school_id,
    'note', 'Create admin user via Supabase Auth, then assign platform_owner role in school_memberships'
  );
END;
$$;

-- ============================================================
-- SOURCE: 00007_storage.sql
-- ============================================================
-- ============================================================
-- TeachCross: Migration 00007 — Storage, helpers, realtime
-- ============================================================

-- ── Private storage buckets (never public) ─────────────────
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  ('attachments', 'attachments', FALSE, 15728640, ARRAY[
    'image/jpeg','image/png','image/webp','image/gif',
    'audio/mpeg','audio/mp4','audio/ogg','audio/wav','audio/webm',
    'application/pdf'
  ]),
  ('avatars', 'avatars', FALSE, 2097152, ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT (id) DO NOTHING;

-- Storage access: only authenticated conversation members may read an
-- attachment object; path convention: <school_id>/<conversation_id>/<file>.
-- Owner (uploader path prefix is the school id, not user id) — so enforce
-- via DB membership checks in a helper function.
CREATE OR REPLACE FUNCTION auth.can_read_attachment(p_school_id UUID, p_conversation_id UUID)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM conversation_members cm
    JOIN conversations c ON c.id = cm.conversation_id
    WHERE cm.conversation_id = p_conversation_id
      AND cm.user_id = auth.uid()
      AND cm.removed_at IS NULL
      AND c.school_id = p_school_id
  ) OR auth.is_school_admin(p_school_id);
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Attachments bucket policies (objects carry school/conv ids in first segments)
CREATE POLICY attachments_read ON storage.objects FOR SELECT
  USING (
    bucket_id = 'attachments'
    AND auth.can_read_attachment(
      (string_to_array(name, '/'))[1]::UUID,
      (string_to_array(name, '/'))[2]::UUID
    )
  );

CREATE POLICY attachments_upload ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'attachments'
    AND auth.uid() IS NOT NULL
  );

CREATE POLICY attachments_delete_admin ON storage.objects FOR DELETE
  USING (
    bucket_id = 'attachments'
    AND auth.is_school_admin((string_to_array(name, '/'))[1]::UUID)
  );

CREATE POLICY avatars_own ON storage.objects FOR ALL
  USING (bucket_id = 'avatars' AND auth.uid()::TEXT = (storage.foldername(name))[1])
  WITH CHECK (bucket_id = 'avatars' AND auth.uid()::TEXT = (storage.foldername(name))[1]);

-- ── Issue / rotate a student activation code (admin-only) ──
-- Stores a pgcrypto-hashed code compatible with activate_student().
CREATE OR REPLACE FUNCTION issue_student_code(
  p_student_id UUID,
  p_plain_code TEXT,
  p_days_valid INTEGER DEFAULT 7
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_student students%ROWTYPE;
BEGIN
  SELECT * INTO v_student FROM students WHERE id = p_student_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'student_not_found');
  END IF;

  IF NOT (auth.is_school_admin(v_student.school_id) OR auth.is_platform_owner()) THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'forbidden');
  END IF;

  IF p_plain_code IS NULL OR length(p_plain_code) < 6 OR length(p_plain_code) > 32 THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'weak_code');
  END IF;

  INSERT INTO student_activation_credentials(school_id, student_id, code, expires_at, used_at, created_by)
  VALUES (
    v_student.school_id, v_student.id,
    crypt(p_plain_code, gen_salt('bf', 10)),
    NOW() + (COALESCE(p_days_valid, 7) || ' days')::INTERVAL,
    NULL, auth.uid()
  )
  ON CONFLICT (student_id) DO UPDATE SET
    code = EXCLUDED.code,
    expires_at = EXCLUDED.expires_at,
    used_at = NULL,
    created_by = EXCLUDED.created_by,
    created_at = NOW();

  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome)
  VALUES (v_student.school_id, auth.uid(), 'enrollment.code.issued', 'student', p_student_id::TEXT, 'success');

  RETURN jsonb_build_object('success', TRUE, 'expires_in_days', COALESCE(p_days_valid, 7));
END;
$$;

-- ── Reassign a student to another class (admin-only, audited) ──
CREATE OR REPLACE FUNCTION reassign_student_class(
  p_student_id UUID,
  p_new_class_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_student students%ROWTYPE;
  v_class classes%ROWTYPE;
BEGIN
  SELECT * INTO v_student FROM students WHERE id = p_student_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', FALSE, 'error', 'student_not_found'); END IF;
  SELECT * INTO v_class FROM classes WHERE id = p_new_class_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', FALSE, 'error', 'class_not_found'); END IF;
  IF v_student.school_id != v_class.school_id THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'cross_school');
  END IF;
  IF NOT (auth.is_school_admin(v_student.school_id) OR auth.is_platform_owner()) THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'forbidden');
  END IF;

  UPDATE class_enrollments SET unenrolled_at = NOW()
  WHERE student_id = p_student_id AND unenrolled_at IS NULL;

  INSERT INTO class_enrollments(school_id, class_id, student_id)
  VALUES (v_student.school_id, p_new_class_id, p_student_id);

  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome, reason)
  VALUES (v_student.school_id, auth.uid(), 'class.reassign', 'student', p_student_id::TEXT, 'success', p_reason);

  RETURN jsonb_build_object('success', TRUE, 'class_id', p_new_class_id);
END;
$$;

-- ── Publish due scheduled announcements (called by pg_cron / edge cron) ──
CREATE OR REPLACE FUNCTION publish_due_announcements()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_count INTEGER := 0;
BEGIN
  UPDATE announcements
  SET is_published = TRUE, published_at = NOW(), updated_at = NOW()
  WHERE is_published = FALSE
    AND scheduled_for IS NOT NULL
    AND scheduled_for <= NOW();
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN jsonb_build_object('success', TRUE, 'published', v_count);
END;
$$;

-- ── Realtime publication for authorized live updates ────────
-- (RLS still enforced on realtime subscriptions.)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;
END $$;

ALTER PUBLICATION supabase_realtime ADD TABLE messages;
ALTER PUBLICATION supabase_realtime ADD TABLE conversations;
ALTER PUBLICATION supabase_realtime ADD TABLE conversation_members;
ALTER PUBLICATION supabase_realtime ADD TABLE announcements;
ALTER PUBLICATION supabase_realtime ADD TABLE announcement_recipients;
ALTER PUBLICATION supabase_realtime ADD TABLE announcement_receipts;
ALTER PUBLICATION supabase_realtime ADD TABLE attachments;
ALTER PUBLICATION supabase_realtime ADD TABLE support_questions;
ALTER PUBLICATION supabase_realtime ADD TABLE notification_jobs;

-- ============================================================
-- SOURCE: 00008_activation_sha256.sql
-- ============================================================
// ============================================================
// Migration 00008 — SHA-256 activation codes (server-issued)
// Allows the DMS API to issue codes without pgcrypto round-trips.
// activate_student() now accepts BOTH legacy crypt hashes ($2…)
// and SHA-256 hex (64 lowercase hex chars), compared server-side.
// ============================================================

CREATE OR REPLACE FUNCTION activate_student(
  p_school_id       UUID,
  p_student_id_no   TEXT,
  p_activation_code TEXT,
  p_auth_user_id    UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_student         students%ROWTYPE;
  v_credential      student_activation_credentials%ROWTYPE;
  v_class_id        UUID;
  v_match           BOOLEAN := FALSE;
BEGIN
  SELECT * INTO v_student
  FROM students
  WHERE school_id = p_school_id
    AND student_id_no = p_student_id_no
    AND is_active = TRUE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_credentials');
  END IF;

  SELECT * INTO v_credential
  FROM student_activation_credentials
  WHERE student_id = v_student.id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'no_activation_code');
  END IF;

  IF v_credential.used_at IS NOT NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'code_already_used');
  END IF;

  IF v_credential.expires_at < NOW() THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'code_expired');
  END IF;

  -- Accept crypt hashes (legacy, issued via issue_student_code) or
  -- SHA-256 hex (issued via DMS API). Comparison stays server-side.
  IF left(v_credential.code, 3) = '$2a' OR left(v_credential.code, 3) = '$2b' THEN
    v_match := (v_credential.code = crypt(p_activation_code, v_credential.code));
  ELSE
    v_match := (v_credential.code = encode(digest(p_activation_code, 'sha256'), 'hex'));
  END IF;

  IF NOT v_match THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_credentials');
  END IF;

  UPDATE student_activation_credentials
  SET used_at = NOW()
  WHERE id = v_credential.id;

  UPDATE students SET user_id = p_auth_user_id, updated_at = NOW()
  WHERE id = v_student.id;

  INSERT INTO user_profiles(id, display_name, is_active)
  VALUES (p_auth_user_id, v_student.first_name || ' ' || v_student.last_name, TRUE)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO school_memberships(user_id, school_id, role, is_active)
  VALUES (p_auth_user_id, p_school_id, 'student', TRUE)
  ON CONFLICT (user_id, school_id, role) DO UPDATE SET is_active = TRUE;

  SELECT ce.class_id INTO v_class_id
  FROM class_enrollments ce
  WHERE ce.student_id = v_student.id
    AND ce.unenrolled_at IS NULL
  LIMIT 1;

  IF v_class_id IS NOT NULL THEN
    PERFORM create_student_support_conversation(v_student.id, v_class_id, p_school_id, p_auth_user_id);
  END IF;

  RETURN jsonb_build_object(
    'success', TRUE,
    'student_id', v_student.id,
    'class_id', v_class_id
  );
END;
$$;
