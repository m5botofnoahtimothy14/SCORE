-- ============================================================
-- Migration 00023 — CBSE learning, weekly quotas, RAG and secure closure
-- Existing school/class/roster records are retained. New mutations are
-- restricted to SECURITY DEFINER functions / authenticated Edge Functions.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA extensions;

-- Operational configuration. Values are read by the server, not duplicated
-- in mobile code. Monday 00:00 in school_settings.timezone is the quota boundary.
ALTER TABLE public.mentor_desk_settings
  ALTER COLUMN session_allowance_minutes SET DEFAULT 60,
  ALTER COLUMN session_lengths SET DEFAULT '{15,30}';
UPDATE public.mentor_desk_settings
  SET session_allowance_minutes = LEAST(session_allowance_minutes, 60),
      session_lengths = ARRAY[15,30],
      urgent_passes_per_week = 1,
      updated_at = NOW();
ALTER TABLE public.mentor_desk_settings
  ADD COLUMN IF NOT EXISTS weekly_doubt_allowance INTEGER NOT NULL DEFAULT 3,
  ADD COLUMN IF NOT EXISTS otp_expiry_minutes INTEGER NOT NULL DEFAULT 30,
  ADD COLUMN IF NOT EXISTS otp_resend_limit INTEGER NOT NULL DEFAULT 3,
  ADD COLUMN IF NOT EXISTS max_ai_requests INTEGER NOT NULL DEFAULT 10,
  ADD COLUMN IF NOT EXISTS ai_reset_period TEXT NOT NULL DEFAULT 'week',
  ADD COLUMN IF NOT EXISTS ai_question_max_chars INTEGER NOT NULL DEFAULT 2000,
  ADD COLUMN IF NOT EXISTS ai_answer_max_tokens INTEGER NOT NULL DEFAULT 800,
  ADD COLUMN IF NOT EXISTS ai_timeout_seconds INTEGER NOT NULL DEFAULT 25;

-- Explicit subject enrolment; do not infer that every student takes every subject.
CREATE TABLE public.student_subject_enrollments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  class_id UUID NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  subject_id UUID NOT NULL REFERENCES public.subjects(id) ON DELETE CASCADE,
  assigned_by UUID REFERENCES public.user_profiles(id),
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(student_id, subject_id)
);
CREATE INDEX student_subject_enrollment_lookup
  ON public.student_subject_enrollments(student_id, active, subject_id);
ALTER TABLE public.student_subject_enrollments ENABLE ROW LEVEL SECURITY;
CREATE POLICY student_subject_enrollment_read ON public.student_subject_enrollments FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM public.students s WHERE s.id = student_id AND s.user_id = auth.uid())
    OR public.tc_is_school_admin(school_id)
    OR EXISTS (SELECT 1 FROM public.teachers t JOIN public.teaching_assignments ta ON ta.teacher_id=t.id
               WHERE t.user_id=auth.uid() AND ta.class_id=student_subject_enrollments.class_id
                 AND ta.subject_id=student_subject_enrollments.subject_id)
  );
CREATE POLICY student_subject_enrollment_admin ON public.student_subject_enrollments FOR ALL
  USING (public.tc_is_school_admin(school_id)) WITH CHECK (public.tc_is_school_admin(school_id));

-- Keep the student's authoritative class on each doubt for historical access
-- after class assignment changes. Existing doubts are safely backfilled.
ALTER TABLE public.doubt_requests ADD COLUMN IF NOT EXISTS class_id UUID REFERENCES public.classes(id);
UPDATE public.doubt_requests dr SET class_id = ce.class_id
FROM public.class_enrollments ce
WHERE dr.student_record_id=ce.student_id AND ce.unenrolled_at IS NULL AND dr.class_id IS NULL;
ALTER TABLE public.doubt_requests ALTER COLUMN status DROP DEFAULT;
ALTER TABLE public.doubt_requests ALTER COLUMN status TYPE TEXT USING status::TEXT;
ALTER TABLE public.doubt_requests ALTER COLUMN status SET DEFAULT 'pending_assignment';
UPDATE public.doubt_requests SET status = CASE status
  WHEN 'waiting' THEN 'pending_assignment'
  WHEN 'resolved' THEN 'answered'
  ELSE status END;
ALTER TABLE public.doubt_requests
  ADD CONSTRAINT doubt_requests_status_v2 CHECK
    (status IN ('submitted','pending_assignment','assigned','in_progress','answered','closed','reopened'));

-- Audit every status transition; never delete the original question or messages.
CREATE TABLE public.doubt_status_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id UUID NOT NULL REFERENCES public.doubt_requests(id) ON DELETE CASCADE,
  actor_id UUID REFERENCES public.user_profiles(id),
  from_status TEXT,
  to_status TEXT NOT NULL,
  reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.doubt_status_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY doubt_history_participants_read ON public.doubt_status_history FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.doubt_requests d WHERE d.id=request_id
    AND (d.student_id=auth.uid() OR d.assigned_mentor_id=auth.uid() OR public.tc_is_school_admin(d.school_id))));

-- Students/teachers may read only in-scope records. Direct client writes are
-- removed so quota/status/assignment fields cannot be forged through PostgREST.
DROP POLICY IF EXISTS doubt_requests_student ON public.doubt_requests;
DROP POLICY IF EXISTS doubt_requests_mentor ON public.doubt_requests;
DROP POLICY IF EXISTS doubt_requests_admin ON public.doubt_requests;
CREATE POLICY doubt_requests_student_read ON public.doubt_requests FOR SELECT
  USING (student_id=auth.uid());
CREATE POLICY doubt_requests_teacher_read ON public.doubt_requests FOR SELECT
  USING (assigned_mentor_id=auth.uid() OR public.tc_is_school_admin(school_id) OR EXISTS (
    SELECT 1 FROM public.teachers t JOIN public.teaching_assignments ta ON ta.teacher_id=t.id
    WHERE t.user_id=auth.uid() AND t.is_active AND ta.class_id=doubt_requests.class_id
      AND ta.subject_id=doubt_requests.subject_id AND ta.school_id=doubt_requests.school_id));

-- Preserve secure quota records for all accepted historical doubts. Each request
-- consumes one count in its subject's school-local Monday-start week.
CREATE TABLE public.student_doubt_quota_usage (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  subject_id UUID NOT NULL REFERENCES public.subjects(id) ON DELETE CASCADE,
  request_id UUID NOT NULL UNIQUE REFERENCES public.doubt_requests(id) ON DELETE CASCADE,
  week_start DATE NOT NULL,
  urgent BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(student_id, subject_id, week_start, request_id)
);
INSERT INTO public.student_doubt_quota_usage(school_id,student_id,subject_id,request_id,week_start,urgent,created_at)
SELECT d.school_id,d.student_id,d.subject_id,d.id,
       public.tc_week_start(d.created_at, COALESCE(ss.timezone,'Asia/Kolkata')),
       d.urgent,d.created_at
FROM public.doubt_requests d
JOIN public.school_settings ss ON ss.school_id=d.school_id
ON CONFLICT (request_id) DO NOTHING;
CREATE INDEX student_doubt_quota_week_lookup
  ON public.student_doubt_quota_usage(student_id,subject_id,week_start);
CREATE UNIQUE INDEX student_one_urgent_doubt_per_subject_week
  ON public.student_doubt_quota_usage(student_id,subject_id,week_start) WHERE urgent;
ALTER TABLE public.student_doubt_quota_usage ENABLE ROW LEVEL SECURITY;
CREATE POLICY student_doubt_quota_read ON public.student_doubt_quota_usage FOR SELECT
  USING (student_id=auth.uid() OR public.tc_is_school_admin(school_id));

-- Session accounting: the ledger is the reservation/consumption source of truth.
ALTER TABLE public.session_bookings
  ADD COLUMN IF NOT EXISTS class_id UUID REFERENCES public.classes(id),
  ADD COLUMN IF NOT EXISTS reserved_minutes INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS actual_minutes INTEGER,
  ADD COLUMN IF NOT EXISTS started_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS ended_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS otp_hash TEXT,
  ADD COLUMN IF NOT EXISTS otp_issued_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS otp_resend_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS otp_hash_expires_at TIMESTAMPTZ;
UPDATE public.session_bookings SET reserved_minutes=allowance_minutes_used WHERE reserved_minutes=0;
UPDATE public.session_bookings b SET class_id=ce.class_id
FROM public.class_enrollments ce
WHERE ce.student_id=b.student_record_id AND ce.unenrolled_at IS NULL AND b.class_id IS NULL;
ALTER TABLE public.session_bookings ALTER COLUMN verification_code DROP DEFAULT;
UPDATE public.session_bookings SET verification_code=NULL;

-- Never expose verification material or permit direct participant updates.
DROP POLICY IF EXISTS session_bookings_participant ON public.session_bookings;
DROP POLICY IF EXISTS session_bookings_admin ON public.session_bookings;
CREATE POLICY session_bookings_participant_read ON public.session_bookings FOR SELECT
  USING (student_id=auth.uid() OR mentor_id=auth.uid() OR public.tc_is_school_admin(school_id));

-- Prevent client modifications to accounting ledgers; read only by owner/admin.
DROP POLICY IF EXISTS allowance_transactions_student ON public.allowance_transactions;
DROP POLICY IF EXISTS allowance_transactions_admin ON public.allowance_transactions;
CREATE POLICY allowance_ledger_read ON public.allowance_transactions FOR SELECT
  USING (student_id=auth.uid() OR public.tc_is_school_admin(school_id));

-- Admin-managed approved knowledge base. The private storage bucket is never
-- readable by mobile clients; only approved active chunks enter retrieval.
CREATE TABLE public.curriculum_documents (
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
CREATE INDEX curriculum_documents_active_scope ON public.curriculum_documents(class_grade,subject,approval_status);
CREATE TABLE public.curriculum_chunks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id UUID NOT NULL REFERENCES public.curriculum_documents(id) ON DELETE CASCADE,
  chunk_index INTEGER NOT NULL,
  page_number INTEGER,
  section TEXT,
  content TEXT NOT NULL,
  content_hash TEXT NOT NULL,
  embedding extensions.vector(1536),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(document_id,chunk_index),
  UNIQUE(document_id,content_hash)
);
CREATE INDEX curriculum_chunks_document ON public.curriculum_chunks(document_id,chunk_index);
CREATE INDEX curriculum_chunks_embedding_hnsw ON public.curriculum_chunks
  USING hnsw (embedding extensions.vector_cosine_ops);
ALTER TABLE public.curriculum_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.curriculum_chunks ENABLE ROW LEVEL SECURITY;
CREATE POLICY curriculum_document_admin ON public.curriculum_documents FOR ALL
  USING (school_id IS NULL OR public.tc_is_school_admin(school_id))
  WITH CHECK (school_id IS NULL OR public.tc_is_school_admin(school_id));
-- No authenticated SELECT policy on chunks or private original documents.
INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES ('curriculum-private','curriculum-private',FALSE,52428800,ARRAY['text/plain','application/pdf'])
ON CONFLICT(id) DO NOTHING;

-- Teacher-reviewed evaluation rows are required before release. The corpus is
-- intentionally empty until open-license sources are reviewed and approved.
CREATE TABLE public.curriculum_evaluation_cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  class_grade SMALLINT NOT NULL CHECK(class_grade IN (10,11,12)),
  subject TEXT NOT NULL CHECK(subject IN ('Physics','Chemistry','Biology','Mathematics')),
  question TEXT NOT NULL,
  expected_answer TEXT NOT NULL,
  expected_document_identifier TEXT,
  reviewer_id UUID NOT NULL REFERENCES public.user_profiles(id),
  reviewed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  active BOOLEAN NOT NULL DEFAULT TRUE
);
ALTER TABLE public.curriculum_evaluation_cases ENABLE ROW LEVEL SECURITY;
CREATE POLICY curriculum_evaluation_admin ON public.curriculum_evaluation_cases FOR ALL
  USING (public.tc_is_platform_owner()) WITH CHECK (public.tc_is_platform_owner());

-- Per-student, per-school configurable usage accounting. Pending reservations
-- count against the cap to make concurrent requests safe; only delivered answers
-- are charged, and failed reservations are released.
CREATE TABLE public.student_ai_usage (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  idempotency_key UUID NOT NULL,
  period_start DATE NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('pending','succeeded','failed')),
  question_hash TEXT NOT NULL,
  answer JSONB,
  latency_ms INTEGER,
  input_tokens INTEGER,
  output_tokens INTEGER,
  cost_microunits BIGINT,
  reserved_until TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  UNIQUE(student_id,idempotency_key)
);
CREATE INDEX student_ai_usage_period ON public.student_ai_usage(student_id,period_start,status);
ALTER TABLE public.student_ai_usage ENABLE ROW LEVEL SECURITY;
CREATE POLICY student_ai_usage_read ON public.student_ai_usage FOR SELECT
  USING(student_id=auth.uid() OR public.tc_is_school_admin(school_id));

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
      (SELECT id FROM subjects WHERE school_id=v_student.school_id AND lower(name)=lower(p_subject) AND is_active)
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
REVOKE ALL ON FUNCTION public.match_curriculum_chunks(SMALLINT,TEXT,extensions.vector,INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.match_curriculum_chunks(SMALLINT,TEXT,extensions.vector,INTEGER) TO authenticated;

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
REVOKE ALL ON FUNCTION public.begin_student_ai_request(UUID,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.begin_student_ai_request(UUID,TEXT) TO authenticated;

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
REVOKE ALL ON FUNCTION public.finish_student_ai_request(UUID,BOOLEAN,JSONB,INTEGER,INTEGER,INTEGER,BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.finish_student_ai_request(UUID,BOOLEAN,JSONB,INTEGER,INTEGER,INTEGER,BIGINT) TO authenticated;

CREATE OR REPLACE FUNCTION public.student_learning_context()
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE v_uid UUID:=auth.uid(); v_student students%ROWTYPE; v_class classes%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_student FROM students WHERE user_id=v_uid AND is_active LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'student_not_found'; END IF;
  SELECT c.* INTO v_class FROM class_enrollments ce JOIN classes c ON c.id=ce.class_id
    WHERE ce.student_id=v_student.id AND ce.unenrolled_at IS NULL AND c.is_active LIMIT 1;
  IF NOT FOUND OR v_class.grade !~ '^(10|11|12)$' THEN RAISE EXCEPTION 'unsupported_class'; END IF;
  RETURN jsonb_build_object('school_id',v_student.school_id,'class_id',v_class.id,'class_grade',v_class.grade::INTEGER,
    'subjects',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',s.id,'name',s.name)) FROM student_subject_enrollments e
      JOIN subjects s ON s.id=e.subject_id AND s.school_id=v_student.school_id
      WHERE e.student_id=v_student.id AND e.class_id=v_class.id AND e.active
      AND lower(s.name) IN ('physics','chemistry','biology','mathematics')),'[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION public.student_learning_context() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.student_learning_context() TO authenticated;

CREATE OR REPLACE FUNCTION public.get_student_learning_allowances()
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE v_uid UUID:=auth.uid(); v_student students%ROWTYPE; v_settings mentor_desk_settings%ROWTYPE;
  v_tz TEXT; v_week DATE; v_reset TIMESTAMPTZ; v_session_used INTEGER;
BEGIN
  SELECT * INTO v_student FROM students WHERE user_id=v_uid AND is_active LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'student_not_found'; END IF;
  SELECT * INTO v_settings FROM mentor_desk_settings WHERE school_id=v_student.school_id;
  SELECT COALESCE(timezone,'Asia/Kolkata') INTO v_tz FROM school_settings WHERE school_id=v_student.school_id;
  v_week:=public.tc_week_start(NOW(),v_tz);
  v_reset:=(date_trunc('week',NOW() AT TIME ZONE v_tz)+interval '1 week') AT TIME ZONE v_tz;
  SELECT COALESCE(sum(CASE WHEN action='deduct' THEN minutes ELSE -minutes END),0)::INTEGER INTO v_session_used
    FROM allowance_transactions WHERE student_id=v_uid AND week_start=v_week;
  RETURN jsonb_build_object('timezone',v_tz,'week_start',v_week,'next_reset_at',v_reset,
    'session_allowance_minutes',COALESCE(v_settings.session_allowance_minutes,60),
    'session_used_minutes',v_session_used,
    'session_remaining_minutes',GREATEST(0,COALESCE(v_settings.session_allowance_minutes,60)-v_session_used),
    'doubt_allowance',COALESCE(v_settings.weekly_doubt_allowance,3),
    'subjects',COALESCE((SELECT jsonb_agg(jsonb_build_object('subject_id',s.id,'subject_name',s.name,
      'used',(SELECT count(*) FROM student_doubt_quota_usage q WHERE q.student_id=v_uid AND q.subject_id=s.id AND q.week_start=v_week),
      'urgent_available',NOT EXISTS(SELECT 1 FROM student_doubt_quota_usage q WHERE q.student_id=v_uid AND q.subject_id=s.id AND q.week_start=v_week AND q.urgent))
      ORDER BY s.name) FROM student_subject_enrollments e JOIN subjects s ON s.id=e.subject_id
      WHERE e.student_id=v_student.id AND e.active AND e.class_id=(SELECT class_id FROM class_enrollments ce WHERE ce.student_id=v_student.id AND ce.unenrolled_at IS NULL LIMIT 1)
        AND lower(s.name) IN ('physics','chemistry','biology','mathematics')),'[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION public.get_student_learning_allowances() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_student_learning_allowances() TO authenticated;

-- Admin audit for knowledge approval/configuration changes.
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
REVOKE ALL ON FUNCTION public.approve_curriculum_document(UUID,BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.approve_curriculum_document(UUID,BOOLEAN) TO authenticated;
