-- Migration 00042 — Support grades 6-12 (not just 10-12)
-- The production DB only supports grades 10-12. This migration
-- extends support to grades 6-12 for doubt submission, booking,
-- AI context, and curriculum.

-- ── 1. Update curriculum_documents grade constraint ──
ALTER TABLE public.curriculum_documents
  DROP CONSTRAINT IF EXISTS curriculum_documents_class_grade_check;
ALTER TABLE public.curriculum_documents
  ADD CONSTRAINT curriculum_documents_class_grade_check
  CHECK (class_grade IN (6,7,8,9,10,11,12));

-- ── 2. Update submit_doubt RPC to support grades 6-12 ──
CREATE OR REPLACE FUNCTION public.submit_doubt(
  p_subject_id UUID, p_question TEXT, p_chapter TEXT DEFAULT NULL,
  p_question_number TEXT DEFAULT NULL, p_explanation TEXT DEFAULT NULL,
  p_previous_attempts TEXT DEFAULT NULL, p_urgent BOOLEAN DEFAULT FALSE,
  p_urgent_reason TEXT DEFAULT NULL, p_attachment_ids UUID[] DEFAULT '{}'::UUID[],
  p_idempotency_key UUID DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_uid UUID:=auth.uid(); v_student students%ROWTYPE; v_settings mentor_desk_settings%ROWTYPE;
  v_school UUID; v_class UUID; v_tz TEXT; v_week DATE; v_reset TIMESTAMPTZ;
  v_used INTEGER; v_request UUID; v_conv UUID; v_urgent_used BOOLEAN:=FALSE;
  v_subject_name TEXT; v_teacher teachers%ROWTYPE; v_message JSONB;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success',false,'error','not_authenticated'); END IF;
  SELECT * INTO v_student FROM students WHERE user_id=v_uid AND is_active LIMIT 1;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'error','student_not_found'); END IF;
  v_school:=v_student.school_id;
  PERFORM pg_advisory_xact_lock(hashtext(v_uid::text||':submit-doubt'));
  SELECT ce.class_id INTO v_class FROM class_enrollments ce JOIN classes c ON c.id=ce.class_id
    WHERE ce.student_id=v_student.id AND ce.unenrolled_at IS NULL AND c.is_active
    ORDER BY ce.enrolled_at DESC LIMIT 1;
  IF v_class IS NULL THEN RETURN jsonb_build_object('success',false,'error','unsupported_class'); END IF;
  SELECT * INTO v_settings FROM mentor_desk_settings WHERE school_id=v_school;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'error','settings_not_configured'); END IF;
  IF p_idempotency_key IS NOT NULL AND EXISTS(SELECT 1 FROM doubt_requests WHERE student_id=v_uid AND idempotency_key=p_idempotency_key) THEN
    RETURN jsonb_build_object('success',true,'request_id',(SELECT id FROM doubt_requests WHERE student_id=v_uid AND idempotency_key=p_idempotency_key),'duplicate',true);
  END IF;
  IF p_attachment_ids IS NOT NULL AND array_length(p_attachment_ids,1) IS NOT NULL AND array_length(p_attachment_ids,1)>4 THEN
    RETURN jsonb_build_object('success',false,'error','too_many_attachments');
  END IF;
  IF p_question IS NULL OR length(trim(p_question))=0 OR length(p_question)>4000 THEN
    RETURN jsonb_build_object('success',false,'error','invalid_question');
  END IF;
  SELECT name INTO v_subject_name FROM subjects WHERE id=p_subject_id AND school_id=v_school AND is_active;
  IF v_subject_name IS NULL THEN RETURN jsonb_build_object('success',false,'error','invalid_subject'); END IF;
  IF NOT EXISTS(SELECT 1 FROM student_subject_enrollments WHERE student_id=v_student.id AND class_id=v_class AND subject_id=p_subject_id AND active) THEN
    RETURN jsonb_build_object('success',false,'error','subject_not_enrolled');
  END IF;
  SELECT COALESCE(timezone,'Asia/Kolkata') INTO v_tz FROM school_settings WHERE school_id=v_school;
  v_week:=tc_week_start(NOW(),COALESCE(v_tz,'Asia/Kolkata'));
  v_reset:=(date_trunc('week',NOW() AT TIME ZONE COALESCE(v_tz,'Asia/Kolkata'))+interval '1 week') AT TIME ZONE COALESCE(v_tz,'Asia/Kolkata');
  SELECT count(*) INTO v_used FROM student_doubt_quota_usage WHERE student_id=v_uid AND subject_id=p_subject_id AND week_start=v_week;
  IF v_used>=v_settings.weekly_doubt_allowance THEN
    RETURN jsonb_build_object('success',false,'error','weekly_quota_reached','remaining',0,'next_reset_at',v_reset);
  END IF;
  IF p_urgent AND (p_urgent_reason IS NULL OR length(trim(p_urgent_reason))=0) THEN
    RETURN jsonb_build_object('success',false,'error','urgent_reason_required');
  END IF;
  IF p_urgent AND EXISTS(SELECT 1 FROM student_doubt_quota_usage WHERE student_id=v_uid AND subject_id=p_subject_id AND week_start=v_week AND urgent) THEN
    RETURN jsonb_build_object('success',false,'error','urgent_pass_used');
  END IF;

  INSERT INTO conversations(school_id,type,title,created_by,is_active)
    VALUES(v_school,'mentor_desk','Doubt: '||left(p_question,60),v_uid,true) RETURNING id INTO v_conv;
  INSERT INTO conversation_members(conversation_id,user_id,role,can_send) VALUES(v_conv,v_uid,'student',true);
  INSERT INTO doubt_requests(school_id,conversation_id,student_id,student_record_id,class_id,subject_id,question,chapter,question_number,explanation,previous_attempts,urgent,urgent_reason,status,idempotency_key,created_at,updated_at)
    VALUES(v_school,v_conv,v_uid,v_student.id,v_class,p_subject_id,p_question,p_chapter,p_question_number,p_explanation,p_previous_attempts,p_urgent,p_urgent_reason,'pending_assignment',p_idempotency_key,NOW(),NOW()) RETURNING id INTO v_request;
  INSERT INTO student_doubt_quota_usage(school_id,student_id,subject_id,request_id,week_start,urgent)
    VALUES(v_school,v_uid,p_subject_id,v_request,v_week,p_urgent);
  INSERT INTO doubt_status_history(request_id,actor_id,from_status,to_status,reason) VALUES(v_request,v_uid,NULL,'pending_assignment','accepted_submission');
  v_message:=public.send_message(v_conv,v_uid,p_question,COALESCE(p_idempotency_key,gen_random_uuid())::TEXT,NULL,NULL);
  IF COALESCE((v_message->>'success')::BOOLEAN,FALSE) IS NOT TRUE THEN
    RAISE EXCEPTION 'doubt_message_rejected';
  END IF;
  IF array_length(p_attachment_ids,1) IS NOT NULL THEN
    UPDATE attachments SET message_id=(SELECT id FROM messages WHERE conversation_id=v_conv AND sender_id=v_uid ORDER BY created_at DESC LIMIT 1)
    WHERE id=ANY(p_attachment_ids) AND uploader_id=v_uid AND school_id=v_school AND message_id IS NULL;
  END IF;

  SELECT t.* INTO v_teacher FROM teachers t
    JOIN teaching_assignments ta ON ta.teacher_id=t.id AND ta.class_id=v_class AND ta.subject_id=p_subject_id AND ta.school_id=v_school
    JOIN mentor_subject_approvals ma ON ma.teacher_id=t.id AND ma.subject_id=p_subject_id AND ma.status='approved'
    WHERE t.school_id=v_school AND t.is_active
    ORDER BY (SELECT count(*) FROM doubt_requests prior WHERE prior.assigned_teacher_id=t.id AND prior.status IN ('assigned','in_progress')) ASC,t.id
    LIMIT 1;
  IF FOUND THEN
    UPDATE doubt_requests SET status='assigned',assigned_mentor_id=v_teacher.user_id,assigned_teacher_id=v_teacher.id,updated_at=NOW() WHERE id=v_request;
    INSERT INTO conversation_members(conversation_id,user_id,role,can_send) VALUES(v_conv,v_teacher.user_id,'teacher',true) ON CONFLICT(conversation_id,user_id) DO NOTHING;
    INSERT INTO doubt_status_history(request_id,actor_id,from_status,to_status) VALUES(v_request,v_uid,'pending_assignment','assigned');
    IF v_teacher.user_id IS NOT NULL THEN
      INSERT INTO notification_jobs(school_id,recipient_id,type,title,body,data,idempotency_key)
        VALUES(v_school,v_teacher.user_id,'urgent_doubt',CASE WHEN p_urgent THEN 'Urgent student doubt' ELSE 'New student doubt' END,
          'A student submitted a doubt in '||v_subject_name,jsonb_build_object('route','mentor-desk/queue','doubt_id',v_request),
          'doubt-assignment:'||v_request::TEXT) ON CONFLICT(idempotency_key) DO NOTHING;
    END IF;
  END IF;
  INSERT INTO audit_events(school_id,actor_id,action,target_type,target_id,outcome,metadata)
    VALUES(v_school,v_uid,'doubt.submit','doubt_request',v_request::TEXT,'success',jsonb_build_object('urgent',p_urgent,'subject_id',p_subject_id,'class_id',v_class));
  RETURN jsonb_build_object('success',true,'request_id',v_request,'conversation_id',v_conv,
    'status',CASE WHEN v_teacher.id IS NULL THEN 'pending_assignment' ELSE 'assigned' END,
    'urgent_pass_used',p_urgent,'remaining',GREATEST(0,v_settings.weekly_doubt_allowance-v_used-1),
    'urgent_available',NOT p_urgent AND NOT EXISTS(SELECT 1 FROM student_doubt_quota_usage WHERE student_id=v_uid AND subject_id=p_subject_id AND week_start=v_week AND urgent),
    'next_reset_at',v_reset);
END $$;

GRANT EXECUTE ON FUNCTION public.submit_doubt(UUID,TEXT,TEXT,TEXT,TEXT,TEXT,BOOLEAN,TEXT,UUID[],UUID) TO authenticated;

-- ── 3. Update book_session RPC to support grades 6-12 ──
CREATE OR REPLACE FUNCTION public.book_session(
  p_subject_id UUID, p_mentor_id UUID, p_duration_minutes INTEGER,
  p_scheduled_at TIMESTAMPTZ, p_topic TEXT, p_preparation TEXT DEFAULT NULL,
  p_attachment_ids UUID[] DEFAULT '{}'::UUID[]
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_uid UUID:=auth.uid(); v_student students%ROWTYPE; v_settings mentor_desk_settings%ROWTYPE;
  v_school UUID; v_class UUID; v_tz TEXT; v_week DATE; v_used INTEGER; v_booking UUID;
  v_teacher teachers%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success',false,'error','not_authenticated'); END IF;
  SELECT * INTO v_student FROM students WHERE user_id=v_uid AND is_active LIMIT 1;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'error','student_not_found'); END IF;
  v_school:=v_student.school_id;
  PERFORM pg_advisory_xact_lock(hashtext(v_uid::text||':book-session'));
  SELECT ce.class_id INTO v_class FROM class_enrollments ce JOIN classes c ON c.id=ce.class_id
    WHERE ce.student_id=v_student.id AND ce.unenrolled_at IS NULL AND c.is_active ORDER BY ce.enrolled_at DESC LIMIT 1;
  IF v_class IS NULL THEN RETURN jsonb_build_object('success',false,'error','unsupported_class'); END IF;
  SELECT * INTO v_settings FROM mentor_desk_settings WHERE school_id=v_school;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'error','settings_not_configured'); END IF;
  IF p_duration_minutes NOT IN (15,30) OR NOT p_duration_minutes=ANY(v_settings.session_lengths) THEN RETURN jsonb_build_object('success',false,'error','invalid_duration'); END IF;
  IF NOT EXISTS(SELECT 1 FROM student_subject_enrollments WHERE student_id=v_student.id AND class_id=v_class AND subject_id=p_subject_id AND active) THEN RETURN jsonb_build_object('success',false,'error','subject_not_enrolled'); END IF;
  IF p_topic IS NULL OR length(trim(p_topic))=0 OR p_scheduled_at<=NOW() THEN RETURN jsonb_build_object('success',false,'error','invalid_booking'); END IF;
  IF p_mentor_id IS NOT NULL THEN
    SELECT t.* INTO v_teacher FROM teachers t JOIN teaching_assignments ta ON ta.teacher_id=t.id
      JOIN mentor_subject_approvals ma ON ma.teacher_id=t.id AND ma.subject_id=p_subject_id AND ma.status='approved'
      WHERE t.user_id=p_mentor_id AND t.school_id=v_school AND t.is_active AND ta.class_id=v_class AND ta.subject_id=p_subject_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'error','mentor_not_approved'); END IF;
  ELSE
    SELECT t.* INTO v_teacher FROM teachers t JOIN teaching_assignments ta ON ta.teacher_id=t.id
      JOIN mentor_subject_approvals ma ON ma.teacher_id=t.id AND ma.subject_id=p_subject_id AND ma.status='approved'
      WHERE t.school_id=v_school AND t.is_active AND ta.class_id=v_class AND ta.subject_id=p_subject_id
      ORDER BY t.id LIMIT 1;
    IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'error','no_authorized_teacher'); END IF;
  END IF;
  SELECT COALESCE(timezone,'Asia/Kolkata') INTO v_tz FROM school_settings WHERE school_id=v_school;
  v_week:=tc_week_start(NOW(),COALESCE(v_tz,'Asia/Kolkata'));
  SELECT COALESCE(sum(CASE WHEN action='deduct' THEN minutes ELSE -minutes END),0)::INTEGER INTO v_used
    FROM allowance_transactions WHERE student_id=v_uid AND week_start=v_week;
  IF v_used+p_duration_minutes>v_settings.session_allowance_minutes THEN
    RETURN jsonb_build_object('success',false,'error','allowance_exceeded','remaining',GREATEST(0,v_settings.session_allowance_minutes-v_used));
  END IF;
  INSERT INTO session_bookings(school_id,student_id,student_record_id,mentor_id,mentor_record_id,subject_id,class_id,duration_minutes,topic,preparation,scheduled_at,status,allowance_minutes_used,reserved_minutes)
    VALUES(v_school,v_uid,v_student.id,v_teacher.user_id,v_teacher.id,p_subject_id,v_class,p_duration_minutes,p_topic,p_preparation,p_scheduled_at,'requested',p_duration_minutes,p_duration_minutes)
    RETURNING id INTO v_booking;
  INSERT INTO allowance_transactions(school_id,student_id,subject_id,booking_id,week_start,action,minutes,reason)
    VALUES(v_school,v_uid,p_subject_id,v_booking,v_week,'deduct',p_duration_minutes,'reservation');
  INSERT INTO audit_events(school_id,actor_id,action,target_type,target_id,outcome)
    VALUES(v_school,v_uid,'session.book','session_booking',v_booking::TEXT,'success');
  RETURN jsonb_build_object('success',true,'booking_id',v_booking,'status','requested','allowance_remaining',v_settings.session_allowance_minutes-v_used-p_duration_minutes);
END $$;

GRANT EXECUTE ON FUNCTION public.book_session(UUID,UUID,INTEGER,TIMESTAMPTZ,TEXT,TEXT,UUID[]) TO authenticated;

-- ── 4. Update student_learning_context RPC to support grades 6-12 ──
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

-- ── 5. Update match_curriculum_chunks RPC to support grades 6-12 ──
CREATE OR REPLACE FUNCTION public.match_curriculum_chunks(
  p_class_grade SMALLINT, p_subject TEXT, p_query public.vector(1536), p_limit INTEGER DEFAULT 6
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