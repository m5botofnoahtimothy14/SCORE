-- ============================================================
-- 00036: restore the CBSE curriculum RAG and student AI quota schema.
-- The live project did not contain these tables or RPCs. No corpus data
-- is inserted. Only approved, licensed documents can enter retrieval.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA extensions;

ALTER TABLE public.mentor_desk_settings
  ALTER COLUMN session_allowance_minutes SET DEFAULT 60,
  ALTER COLUMN session_lengths SET DEFAULT '{15,30}';

ALTER TABLE public.mentor_desk_settings
  ADD COLUMN IF NOT EXISTS otp_expiry_minutes integer NOT NULL DEFAULT 30,
  ADD COLUMN IF NOT EXISTS otp_resend_limit integer NOT NULL DEFAULT 3,
  ADD COLUMN IF NOT EXISTS max_ai_requests integer NOT NULL DEFAULT 10,
  ADD COLUMN IF NOT EXISTS ai_reset_period text NOT NULL DEFAULT 'week',
  ADD COLUMN IF NOT EXISTS ai_question_max_chars integer NOT NULL DEFAULT 2000,
  ADD COLUMN IF NOT EXISTS ai_answer_max_tokens integer NOT NULL DEFAULT 800,
  ADD COLUMN IF NOT EXISTS ai_timeout_seconds integer NOT NULL DEFAULT 25;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.mentor_desk_settings'::regclass
      AND conname='mentor_desk_ai_reset_period_check'
  ) THEN
    ALTER TABLE public.mentor_desk_settings
      ADD CONSTRAINT mentor_desk_ai_reset_period_check
      CHECK (ai_reset_period IN ('day','week','month'));
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.mentor_desk_settings'::regclass
      AND conname='mentor_desk_ai_limits_check'
  ) THEN
    ALTER TABLE public.mentor_desk_settings
      ADD CONSTRAINT mentor_desk_ai_limits_check
      CHECK (
        max_ai_requests BETWEEN 1 AND 1000
        AND ai_question_max_chars BETWEEN 100 AND 10000
        AND ai_answer_max_tokens BETWEEN 100 AND 4000
        AND ai_timeout_seconds BETWEEN 5 AND 120
        AND otp_expiry_minutes BETWEEN 1 AND 60
        AND otp_resend_limit BETWEEN 1 AND 5
      );
  END IF;
END;
$$;

-- Enforce the one-hour weekly session allowance and the 15/30 minute choices.
UPDATE public.mentor_desk_settings
SET session_allowance_minutes = LEAST(session_allowance_minutes, 60),
    session_lengths = ARRAY[15,30],
    urgent_passes_per_week = 1,
    updated_at = now();

INSERT INTO public.mentor_desk_settings(school_id)
SELECT s.id FROM public.schools s
ON CONFLICT (school_id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.curriculum_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid REFERENCES public.schools(id) ON DELETE CASCADE,
  class_grade smallint NOT NULL CHECK (class_grade IN (10,11,12)),
  subject text NOT NULL CHECK (subject IN ('Physics','Chemistry','Biology','Mathematics')),
  chapter text,
  topic text,
  source_title text NOT NULL,
  source_url text NOT NULL,
  document_identifier text NOT NULL,
  license_name text NOT NULL,
  license_url text NOT NULL,
  storage_path text,
  curriculum_year text NOT NULL,
  academic_year text NOT NULL,
  content_version integer NOT NULL DEFAULT 1,
  approval_status text NOT NULL DEFAULT 'pending'
    CHECK (approval_status IN ('pending','approved','rejected','inactive')),
  approved_by uuid REFERENCES public.user_profiles(id),
  approved_at timestamptz,
  ingested_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(document_identifier, content_version)
);

CREATE INDEX IF NOT EXISTS curriculum_documents_active_scope
  ON public.curriculum_documents(class_grade, subject, approval_status);

CREATE TABLE IF NOT EXISTS public.curriculum_chunks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id uuid NOT NULL REFERENCES public.curriculum_documents(id) ON DELETE CASCADE,
  chunk_index integer NOT NULL,
  page_number integer,
  section text,
  content text NOT NULL,
  content_hash text NOT NULL,
  embedding extensions.vector(1536),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(document_id, chunk_index),
  UNIQUE(document_id, content_hash)
);

CREATE INDEX IF NOT EXISTS curriculum_chunks_document
  ON public.curriculum_chunks(document_id, chunk_index);
CREATE INDEX IF NOT EXISTS curriculum_chunks_embedding_hnsw
  ON public.curriculum_chunks USING hnsw (embedding extensions.vector_cosine_ops);

CREATE TABLE IF NOT EXISTS public.curriculum_evaluation_cases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  class_grade smallint NOT NULL CHECK (class_grade IN (10,11,12)),
  subject text NOT NULL CHECK (subject IN ('Physics','Chemistry','Biology','Mathematics')),
  question text NOT NULL,
  expected_answer text NOT NULL,
  expected_document_identifier text,
  reviewer_id uuid NOT NULL REFERENCES public.user_profiles(id),
  reviewed_at timestamptz NOT NULL DEFAULT now(),
  active boolean NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS public.student_ai_usage (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id uuid NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  idempotency_key uuid NOT NULL,
  period_start date NOT NULL,
  status text NOT NULL CHECK (status IN ('pending','succeeded','failed')),
  question_hash text NOT NULL,
  answer jsonb,
  latency_ms integer,
  input_tokens integer,
  output_tokens integer,
  cost_microunits bigint,
  reserved_until timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  UNIQUE(student_id, idempotency_key)
);

CREATE INDEX IF NOT EXISTS student_ai_usage_period
  ON public.student_ai_usage(student_id, period_start, status);

ALTER TABLE public.curriculum_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.curriculum_chunks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.curriculum_evaluation_cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_ai_usage ENABLE ROW LEVEL SECURITY;

-- Global curriculum can only be managed by the platform owner. A school can
-- manage only its own documents. Students never read source documents directly.
DROP POLICY IF EXISTS curriculum_document_admin ON public.curriculum_documents;
CREATE POLICY curriculum_documents_admin_manage
  ON public.curriculum_documents FOR ALL TO authenticated
  USING (
    public.tc_is_platform_owner()
    OR (school_id IS NOT NULL AND public.tc_is_school_admin(school_id))
  )
  WITH CHECK (
    public.tc_is_platform_owner()
    OR (school_id IS NOT NULL AND public.tc_is_school_admin(school_id))
  );

DROP POLICY IF EXISTS curriculum_evaluation_admin ON public.curriculum_evaluation_cases;
CREATE POLICY curriculum_evaluation_platform_owner
  ON public.curriculum_evaluation_cases FOR ALL TO authenticated
  USING (public.tc_is_platform_owner())
  WITH CHECK (public.tc_is_platform_owner());

DROP POLICY IF EXISTS student_ai_usage_read ON public.student_ai_usage;
CREATE POLICY student_ai_usage_student_admin_read
  ON public.student_ai_usage FOR SELECT TO authenticated
  USING (
    student_id = auth.uid()
    OR public.tc_is_school_admin(school_id)
  );

-- Chunks have no direct client policy. The checked retrieval RPC is the only
-- client path to chunk content. AI usage can only be changed by its RPCs.
REVOKE ALL ON public.curriculum_chunks FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.student_ai_usage FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.curriculum_documents FROM PUBLIC, anon;
REVOKE ALL ON public.curriculum_evaluation_cases FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.curriculum_documents TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.curriculum_evaluation_cases TO authenticated;
GRANT SELECT ON public.student_ai_usage TO authenticated;
GRANT ALL ON public.curriculum_documents, public.curriculum_chunks,
  public.curriculum_evaluation_cases, public.student_ai_usage TO service_role;

INSERT INTO storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'curriculum-private',
  'curriculum-private',
  false,
  52428800,
  ARRAY['text/plain','application/pdf']
)
ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.match_curriculum_chunks(
  p_class_grade SMALLINT,p_subject TEXT,p_query extensions.vector(1536),p_limit INTEGER DEFAULT 6
) RETURNS TABLE(chunk_id UUID,content TEXT,chapter TEXT,topic TEXT,source_title TEXT,
  document_identifier TEXT,page_number INTEGER,section TEXT,similarity REAL)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_uid UUID:=auth.uid(); v_student students%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_student FROM students WHERE user_id=v_uid AND is_active LIMIT 1;
  IF NOT FOUND OR p_class_grade NOT IN (10,11,12) OR NOT EXISTS(
    SELECT 1 FROM class_enrollments ce JOIN classes c ON c.id=ce.class_id
    WHERE ce.student_id=v_student.id AND ce.unenrolled_at IS NULL AND c.is_active
      AND c.grade= p_class_grade::TEXT
  ) THEN RAISE EXCEPTION 'student_context_not_found'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM class_enrollments ce JOIN classes c ON c.id=ce.class_id
    JOIN student_subject_enrollments e ON e.student_id=ce.student_id AND e.class_id=ce.class_id AND e.subject_id IN
      (SELECT id FROM subjects WHERE school_id=v_student.school_id AND lower(name)=lower(p_subject))
    WHERE ce.student_id=v_student.id AND ce.unenrolled_at IS NULL AND c.is_active
      AND c.grade=p_class_grade::TEXT AND e.active
  ) THEN RAISE EXCEPTION 'subject_not_enrolled'; END IF;
  RETURN QUERY SELECT cc.id,cc.content,cd.chapter,cd.topic,cd.source_title,cd.document_identifier,
    cc.page_number,cc.section,(1-(cc.embedding <=> p_query))::REAL
  FROM curriculum_chunks cc JOIN curriculum_documents cd ON cd.id=cc.document_id
  WHERE cd.class_grade=p_class_grade AND lower(cd.subject)=lower(p_subject)
    AND cd.approval_status='approved' AND cc.embedding IS NOT NULL
    AND (cd.school_id IS NULL OR cd.school_id=v_student.school_id)
  ORDER BY cc.embedding <=> p_query LIMIT LEAST(GREATEST(p_limit,1),10);
END $$;

CREATE OR REPLACE FUNCTION public.begin_student_ai_request(p_idempotency_key UUID,p_question_hash TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_uid UUID:=auth.uid(); v_student students%ROWTYPE; v_settings mentor_desk_settings%ROWTYPE;
  v_week DATE; v_count INTEGER; v_existing student_ai_usage%ROWTYPE; v_period TEXT;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success',false,'error','not_authenticated'); END IF;
  SELECT * INTO v_student FROM students WHERE user_id=v_uid AND is_active LIMIT 1;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'error','student_not_found'); END IF;
  IF p_question_hash IS NULL OR length(p_question_hash)<>64 OR p_question_hash !~ '^[0-9a-f]{64}$' THEN
    RETURN jsonb_build_object('success',false,'error','invalid_question_hash');
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext(v_uid::text||':curriculum-ai'));
  SELECT * INTO v_settings FROM mentor_desk_settings WHERE school_id=v_student.school_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'error','settings_not_configured'); END IF;
  SELECT * INTO v_existing FROM student_ai_usage WHERE student_id=v_uid AND idempotency_key=p_idempotency_key;
  IF FOUND THEN
    IF v_existing.status='succeeded' THEN RETURN jsonb_build_object('success',true,'cached',true,'answer',v_existing.answer); END IF;
    IF v_existing.status='pending' AND v_existing.reserved_until>NOW() THEN RETURN jsonb_build_object('success',false,'error','request_in_progress'); END IF;
    DELETE FROM student_ai_usage WHERE id=v_existing.id;
  END IF;
  v_period:=v_settings.ai_reset_period;
  IF v_period NOT IN ('day','week','month') THEN v_period:='week'; END IF;
  v_week:=CASE v_period WHEN 'day' THEN (NOW() AT TIME ZONE COALESCE((SELECT timezone FROM school_settings WHERE school_id=v_student.school_id),'Asia/Kolkata'))::DATE
    WHEN 'month' THEN date_trunc('month',NOW() AT TIME ZONE COALESCE((SELECT timezone FROM school_settings WHERE school_id=v_student.school_id),'Asia/Kolkata'))::DATE
    ELSE public.tc_week_start(NOW(),COALESCE((SELECT timezone FROM school_settings WHERE school_id=v_student.school_id),'Asia/Kolkata')) END;
  UPDATE student_ai_usage SET status='failed',reserved_until=NULL,completed_at=NOW()
    WHERE student_id=v_uid AND status='pending' AND reserved_until<NOW();
  SELECT count(*) INTO v_count FROM student_ai_usage WHERE student_id=v_uid AND period_start=v_week AND status IN ('pending','succeeded');
  IF v_count>=v_settings.max_ai_requests THEN RETURN jsonb_build_object('success',false,'error','usage_limit_reached','remaining',0,'reset_period',v_period); END IF;
  INSERT INTO student_ai_usage(school_id,student_id,idempotency_key,period_start,status,question_hash,reserved_until)
    VALUES(v_student.school_id,v_uid,p_idempotency_key,v_week,'pending',p_question_hash,NOW()+interval '60 seconds');
  RETURN jsonb_build_object('success',true,'cached',false,'remaining',v_settings.max_ai_requests-v_count-1,'reset_period',v_period);
END $$;

CREATE OR REPLACE FUNCTION public.finish_student_ai_request(
  p_idempotency_key UUID,p_success BOOLEAN,p_answer JSONB DEFAULT NULL,p_latency_ms INTEGER DEFAULT NULL,
  p_input_tokens INTEGER DEFAULT NULL,p_output_tokens INTEGER DEFAULT NULL,p_cost_microunits BIGINT DEFAULT NULL
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  UPDATE student_ai_usage SET status=CASE WHEN p_success THEN 'succeeded' ELSE 'failed' END,
    answer=CASE WHEN p_success THEN p_answer ELSE NULL END,latency_ms=p_latency_ms,
    input_tokens=p_input_tokens,output_tokens=p_output_tokens,cost_microunits=p_cost_microunits,
    reserved_until=NULL,completed_at=NOW()
  WHERE student_id=auth.uid() AND idempotency_key=p_idempotency_key AND status='pending';
  RETURN FOUND;
END $$;

CREATE OR REPLACE FUNCTION public.approve_curriculum_document(p_document_id UUID,p_approved BOOLEAN)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_doc curriculum_documents%ROWTYPE;
BEGIN
  SELECT * INTO v_doc FROM curriculum_documents WHERE id=p_document_id FOR UPDATE;
  IF NOT FOUND OR NOT public.tc_is_platform_owner() AND (v_doc.school_id IS NULL OR NOT public.tc_is_school_admin(v_doc.school_id)) THEN
    RETURN jsonb_build_object('success',false,'error','forbidden');
  END IF;
  UPDATE curriculum_documents SET approval_status=CASE WHEN p_approved THEN 'approved' ELSE 'rejected' END,
    approved_by=CASE WHEN p_approved THEN auth.uid() ELSE NULL END,
    approved_at=CASE WHEN p_approved THEN NOW() ELSE NULL END,updated_at=NOW() WHERE id=p_document_id;
  IF p_approved THEN
    UPDATE curriculum_documents SET approval_status='inactive',updated_at=NOW()
      WHERE document_identifier=v_doc.document_identifier AND id<>v_doc.id AND approval_status='approved';
  END IF;
  INSERT INTO audit_events(school_id,actor_id,action,target_type,target_id,outcome,metadata)
    VALUES(v_doc.school_id,auth.uid(),'curriculum.approval','curriculum_document',p_document_id::TEXT,'success',
      jsonb_build_object('previous_status',v_doc.approval_status,'new_status',CASE WHEN p_approved THEN 'approved' ELSE 'rejected' END));
  RETURN jsonb_build_object('success',true);
END $$;

-- Explicit authenticated-only RPC permissions. The functions validate the
-- caller's student or school-admin context internally.
DO $$
DECLARE
  v_signature text;
  v_function regprocedure;
BEGIN
  FOREACH v_signature IN ARRAY ARRAY[
    'public.match_curriculum_chunks(smallint,text,extensions.vector,integer)',
    'public.begin_student_ai_request(uuid,text)',
    'public.finish_student_ai_request(uuid,boolean,jsonb,integer,integer,integer,bigint)',
    'public.approve_curriculum_document(uuid,boolean)'
  ] LOOP
    v_function := to_regprocedure(v_signature);
    IF v_function IS NOT NULL THEN
      EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', v_function);
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', v_function);
    END IF;
  END LOOP;
END;
$$;
