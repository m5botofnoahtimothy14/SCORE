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
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id          UUID NOT NULL REFERENCES investigation_requests(id) ON DELETE CASCADE,
  approver_id         UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  decision            TEXT NOT NULL,                 -- 'approved'|'rejected'
  notes               TEXT,
  decided_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE investigation_access_events (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  data_type       TEXT NOT NULL,                     -- 'messages'|'attachments'|'audit_events'
  retention_days  INTEGER NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (school_id, data_type)
);

-- Background jobs tracking
CREATE TYPE job_status AS ENUM ('queued', 'running', 'completed', 'failed', 'retrying');

CREATE TABLE background_jobs (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
