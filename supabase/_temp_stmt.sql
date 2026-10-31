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
)