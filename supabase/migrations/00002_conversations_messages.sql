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
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  question_id     UUID NOT NULL REFERENCES support_questions(id) ON DELETE CASCADE,
  changed_by      UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  from_status     question_status,
  to_status       question_status NOT NULL,
  note            TEXT,
  changed_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
