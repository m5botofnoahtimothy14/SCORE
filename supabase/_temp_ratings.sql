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
