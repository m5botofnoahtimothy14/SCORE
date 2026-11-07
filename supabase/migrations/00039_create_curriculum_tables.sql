-- Migration 00039 — Create curriculum tables for AI/RAG
-- These tables were created in 00023 but not applied to production.
-- Create them so the curriculum-rag edge function can work.

-- Enable vector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- ── curriculum_documents ──
CREATE TABLE IF NOT EXISTS public.curriculum_documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id UUID REFERENCES public.schools(id) ON DELETE CASCADE,
  class_grade SMALLINT NOT NULL CHECK(class_grade IN (10,11,12)),
  subject TEXT NOT NULL CHECK(subject IN ('Physics','Chemistry','Biology','Mathematics')),
  chapter TEXT,
  topic TEXT,
  source_title TEXT NOT NULL,
  source_url TEXT NOT NULL,
  document_identifier TEXT NOT NULL,
  license_name TEXT NOT NULL,
  license_url TEXT NOT NULL,
  storage_path TEXT,
  curriculum_year TEXT NOT NULL,
  academic_year TEXT NOT NULL,
  content_version INTEGER NOT NULL DEFAULT 1,
  approval_status TEXT NOT NULL DEFAULT 'pending' CHECK(approval_status IN ('pending','approved','rejected','inactive')),
  approved_by UUID REFERENCES public.user_profiles(id),
  approved_at TIMESTAMPTZ,
  ingested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(document_identifier, content_version)
);

CREATE INDEX IF NOT EXISTS curriculum_documents_active_scope
  ON public.curriculum_documents(class_grade, subject, approval_status);

-- ── curriculum_chunks ──
CREATE TABLE IF NOT EXISTS public.curriculum_chunks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id UUID NOT NULL REFERENCES public.curriculum_documents(id) ON DELETE CASCADE,
  chunk_index INTEGER NOT NULL,
  page_number INTEGER,
  section TEXT,
  content TEXT NOT NULL,
  content_hash TEXT NOT NULL,
  embedding public.vector(1536),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(document_id, chunk_index),
  UNIQUE(document_id, content_hash)
);

CREATE INDEX IF NOT EXISTS curriculum_chunks_document
  ON public.curriculum_chunks(document_id, chunk_index);

-- HNSW index for vector similarity search
CREATE INDEX IF NOT EXISTS curriculum_chunks_embedding_hnsw
  ON public.curriculum_chunks
  USING hnsw (embedding public.vector_cosine_ops);

-- ── RLS ──
ALTER TABLE public.curriculum_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.curriculum_chunks ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY curriculum_document_admin ON public.curriculum_documents FOR ALL
    USING (school_id IS NULL OR public.tc_is_school_admin(school_id))
    WITH CHECK (school_id IS NULL OR public.tc_is_school_admin(school_id));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- No SELECT policy on chunks or private original documents (service role only)

-- ── Storage bucket ──
INSERT INTO storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
VALUES ('curriculum-private', 'curriculum-private', FALSE, 52428800, ARRAY['text/plain','application/pdf'])
ON CONFLICT(id) DO NOTHING;