-- Teacher activation credentials (one-time codes, hashed)
CREATE TABLE IF NOT EXISTS teacher_activation_credentials (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id     UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  teacher_id    UUID NOT NULL REFERENCES teachers(id) ON DELETE CASCADE,
  code          TEXT NOT NULL,
  expires_at    TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '7 days'),
  used_at       TIMESTAMPTZ,
  created_by    UUID,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (teacher_id)
);

CREATE INDEX IF NOT EXISTS idx_teacher_activation_school ON teacher_activation_credentials(school_id);

ALTER TABLE teacher_activation_credentials ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY teacher_activation_credentials_admin ON teacher_activation_credentials
    FOR ALL USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
