-- ============================================================
-- 00019 — Moderation scoring snapshots (F1 / ML data pipeline).
--
-- Stores per-category, per-audience precision / recall / F1
-- snapshots computed by the score-moderation edge function so
-- the admin dashboard can display ML scoring metrics over time.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.moderation_score_snapshots (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id         uuid REFERENCES public.schools(id) ON DELETE CASCADE,
  computed_at       timestamptz NOT NULL DEFAULT now(),
  total_reviews     integer NOT NULL DEFAULT 0,
  total_predictions integer NOT NULL DEFAULT 0,
  metrics           jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at        timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.moderation_score_snapshots ENABLE ROW LEVEL SECURITY;

-- Leadership + admins can read snapshots for their school.
DROP POLICY IF EXISTS score_snapshots_read ON public.moderation_score_snapshots;
CREATE POLICY score_snapshots_read ON public.moderation_score_snapshots FOR SELECT
  USING (
    public.tc_is_platform_owner()
    OR public.tc_is_school_admin(school_id)
    OR public.tc_has_school_role(school_id, 'head_teacher')
  );

-- Service role (edge function) inserts snapshots.
DROP POLICY IF EXISTS score_snapshots_service_insert ON public.moderation_score_snapshots;
CREATE POLICY score_snapshots_service_insert ON public.moderation_score_snapshots FOR INSERT
  WITH CHECK (true);

-- Index for fast "latest snapshot per school" queries.
CREATE INDEX IF NOT EXISTS moderation_score_snapshots_school_computed_idx
  ON public.moderation_score_snapshots (school_id, computed_at DESC);

-- Index for latest overall snapshot.
CREATE INDEX IF NOT EXISTS moderation_score_snapshots_computed_at_idx
  ON public.moderation_score_snapshots (computed_at DESC);
