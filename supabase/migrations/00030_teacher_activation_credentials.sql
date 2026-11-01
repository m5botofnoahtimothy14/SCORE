-- ============================================================
-- Migration 00030: teacher activation credential storage.
-- Credentials are service-role-only. No client RLS policy is created.
-- ============================================================
CREATE TABLE IF NOT EXISTS public.teacher_activation_credentials (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
  teacher_id uuid NOT NULL REFERENCES public.teachers(id) ON DELETE CASCADE,
  code text NOT NULL,
  code_salt text,
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '7 days'),
  used_at timestamptz,
  failed_attempts integer NOT NULL DEFAULT 0,
  locked_until timestamptz,
  created_by uuid REFERENCES public.user_profiles(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (teacher_id)
);

ALTER TABLE public.teacher_activation_credentials
  ADD COLUMN IF NOT EXISTS code_salt text,
  ADD COLUMN IF NOT EXISTS failed_attempts integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS locked_until timestamptz;

ALTER TABLE public.teacher_activation_credentials ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS teacher_activation_credentials_admin
  ON public.teacher_activation_credentials;

REVOKE ALL ON TABLE public.teacher_activation_credentials
  FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON TABLE public.teacher_activation_credentials TO service_role;
