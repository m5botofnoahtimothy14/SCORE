-- Create match_curriculum_chunks RPC (from migration 00023)
CREATE OR REPLACE FUNCTION public.match_curriculum_chunks(
  p_class_grade SMALLINT,
  p_subject TEXT,
  p_query public.vector(1536),
  p_limit INTEGER DEFAULT 6
) RETURNS TABLE(chunk_id UUID, content TEXT, chapter TEXT, topic TEXT, source_title TEXT,
  document_identifier TEXT, page_number INTEGER, section TEXT, similarity REAL)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE v_uid UUID:=auth.uid(); v_student students%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_student FROM students WHERE user_id=v_uid AND is_active LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'student_not_found'; END IF;
  RETURN QUERY SELECT cc.id, cc.content, cd.chapter, cd.topic, cd.source_title, cd.document_identifier,
    cc.page_number, cc.section, (1-(cc.embedding <=> p_query))::REAL
  FROM curriculum_chunks cc JOIN curriculum_documents cd ON cd.id=cc.document_id
  WHERE cd.class_grade=p_class_grade AND lower(cd.subject)=lower(p_subject)
    AND cd.approval_status='approved' AND cc.embedding IS NOT NULL
  ORDER BY cc.embedding <=> p_query LIMIT LEAST(GREATEST(p_limit,1),10);
END $$;

GRANT EXECUTE ON FUNCTION public.match_curriculum_chunks(SMALLINT, TEXT, public.vector, INTEGER) TO authenticated;

-- Create student_learning_context RPC (from migration 00023)
CREATE OR REPLACE FUNCTION public.student_learning_context()
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE v_uid UUID:=auth.uid(); v_student students%ROWTYPE; v_class classes%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_student FROM students WHERE user_id=v_uid AND is_active LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'student_not_found'; END IF;
  SELECT c.* INTO v_class FROM class_enrollments ce JOIN classes c ON c.id=ce.class_id
    WHERE ce.student_id=v_student.id AND ce.unenrolled_at IS NULL AND c.is_active LIMIT 1;
  IF NOT FOUND THEN
    -- Return default context if no class found
    RETURN jsonb_build_object('school_id', v_student.school_id, 'class_id', NULL, 'class_grade', 10,
      'subjects', '["Chemistry","Physics","Biology"]'::jsonb);
  END IF;
  RETURN jsonb_build_object('school_id', v_student.school_id, 'class_id', v_class.id, 'class_grade', COALESCE(v_class.grade::INTEGER, 10),
    'subjects', COALESCE((SELECT jsonb_agg(jsonb_build_object('id',s.id,'name',s.name)) FROM student_subject_enrollments e
      JOIN subjects s ON s.id=e.subject_id AND s.school_id=v_student.school_id
      WHERE e.student_id=v_student.id AND e.class_id=v_class.id AND e.active
      AND lower(s.name) IN ('physics','chemistry','biology','mathematics')),'[]'::jsonb));
END $$;

GRANT EXECUTE ON FUNCTION public.student_learning_context() TO authenticated;

-- Create begin_student_ai_request RPC (from migration 00023)
CREATE OR REPLACE FUNCTION public.begin_student_ai_request(p_idempotency_key UUID, p_question_hash TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  -- Simple implementation: always allow (rate limiting can be added later)
  RETURN jsonb_build_object('success', true, 'cached', false, 'remaining', 10, 'reset_period', 'week');
END $$;

GRANT EXECUTE ON FUNCTION public.begin_student_ai_request(UUID, TEXT) TO authenticated;

-- Create finish_student_ai_request RPC (from migration 00023)
CREATE OR REPLACE FUNCTION public.finish_student_ai_request(
  p_idempotency_key UUID, p_success BOOLEAN, p_answer JSONB DEFAULT NULL,
  p_latency_ms INTEGER DEFAULT NULL, p_input_tokens INTEGER DEFAULT NULL,
  p_output_tokens INTEGER DEFAULT NULL, p_cost_microunits BIGINT DEFAULT NULL
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  RETURN true;
END $$;

GRANT EXECUTE ON FUNCTION public.finish_student_ai_request(UUID, BOOLEAN, JSONB, INTEGER, INTEGER, INTEGER, BIGINT) TO authenticated;