-- Curriculum RAG and AI usage regression checks.
-- Run after migrations 00034-00036 in a non-production project.
DO $$
DECLARE
  v_signature text;
  v_function regprocedure;
  v_table text;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_extension WHERE extname = 'vector'
  ) THEN
    RAISE EXCEPTION 'pgvector extension is missing';
  END IF;

  FOREACH v_table IN ARRAY ARRAY[
    'curriculum_documents',
    'curriculum_chunks',
    'curriculum_evaluation_cases',
    'student_ai_usage',
    'student_subject_enrollments'
  ] LOOP
    IF to_regclass('public.' || v_table) IS NULL THEN
      RAISE EXCEPTION 'Missing AI/RAG table: public.%', v_table;
    END IF;
  END LOOP;

  FOREACH v_signature IN ARRAY ARRAY[
    'public.student_learning_context()',
    'public.get_student_learning_allowances()',
    'public.match_curriculum_chunks(smallint,text,extensions.vector,integer)',
    'public.begin_student_ai_request(uuid,text)',
    'public.finish_student_ai_request(uuid,boolean,jsonb,integer,integer,integer,bigint)',
    'public.approve_curriculum_document(uuid,boolean)'
  ] LOOP
    v_function := to_regprocedure(v_signature);
    IF v_function IS NULL THEN
      RAISE EXCEPTION 'Missing learning/RAG RPC: %', v_signature;
    END IF;
    IF NOT has_function_privilege('authenticated', v_function, 'EXECUTE') THEN
      RAISE EXCEPTION 'Authenticated role cannot execute learning/RAG RPC: %', v_signature;
    END IF;
    IF has_function_privilege('anon', v_function, 'EXECUTE') THEN
      RAISE EXCEPTION 'Anonymous role can execute learning/RAG RPC: %', v_signature;
    END IF;
  END LOOP;

  IF NOT (
    SELECT relrowsecurity FROM pg_class
    WHERE oid = 'public.curriculum_documents'::regclass
  ) OR NOT (
    SELECT relrowsecurity FROM pg_class
    WHERE oid = 'public.curriculum_chunks'::regclass
  ) OR NOT (
    SELECT relrowsecurity FROM pg_class
    WHERE oid = 'public.student_ai_usage'::regclass
  ) THEN
    RAISE EXCEPTION 'RLS is disabled on a curriculum or AI usage table';
  END IF;

  IF has_table_privilege('authenticated', 'public.curriculum_chunks', 'SELECT') THEN
    RAISE EXCEPTION 'Authenticated clients can read curriculum chunks directly';
  END IF;

  IF has_table_privilege('authenticated', 'public.student_ai_usage', 'INSERT')
     OR has_table_privilege('authenticated', 'public.student_ai_usage', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.student_ai_usage', 'DELETE') THEN
    RAISE EXCEPTION 'Authenticated clients can modify AI usage records directly';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.mentor_desk_settings
    WHERE session_allowance_minutes > 60
       OR session_lengths <> ARRAY[15,30]
       OR urgent_passes_per_week <> 1
  ) THEN
    RAISE EXCEPTION 'Mentor Desk settings exceed the configured session/urgent limits';
  END IF;
END;
$$;
