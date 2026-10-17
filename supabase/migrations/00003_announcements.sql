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
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  announcement_id     UUID NOT NULL REFERENCES announcements(id) ON DELETE CASCADE,
  user_id             UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  read_at             TIMESTAMPTZ,
  acknowledged_at     TIMESTAMPTZ,
  UNIQUE (announcement_id, user_id)
);

CREATE INDEX idx_announcement_receipts_ann  ON announcement_receipts(announcement_id);
CREATE INDEX idx_announcement_receipts_user ON announcement_receipts(user_id);
