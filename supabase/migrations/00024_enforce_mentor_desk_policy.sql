-- ============================================================
-- Migration 00024 — Mentor Desk server policy enforcement
-- ============================================================

-- Convert legacy rows after status type was expanded and preserve history.
UPDATE public.doubt_requests SET status=CASE status
  WHEN 'waiting' THEN 'pending_assignment'
  WHEN 'resolved' THEN 'answered'
  ELSE status END;
ALTER TABLE public.doubt_requests ADD COLUMN IF NOT EXISTS idempotency_key UUID;
CREATE UNIQUE INDEX IF NOT EXISTS doubt_student_idempotency ON public.doubt_requests(student_id,idempotency_key) WHERE idempotency_key IS NOT NULL;

-- Align operational defaults/config to the product contract. Do not grant
-- extra quota when legacy settings had higher allowances.
ALTER TABLE public.mentor_desk_settings
  ALTER COLUMN session_allowance_minutes SET DEFAULT 60,
  ALTER COLUMN session_lengths SET DEFAULT '{15,30}';
UPDATE public.mentor_desk_settings SET
  session_allowance_minutes=LEAST(session_allowance_minutes,60),
  session_lengths=ARRAY[15,30],
  urgent_passes_per_week=1,
  weekly_doubt_allowance=3,
  updated_at=NOW();

-- Function parameter change: idempotency key gets a default, but original RPC
-- signatures remain usable by the current client.
DROP FUNCTION IF EXISTS public.submit_doubt(UUID,TEXT,TEXT,TEXT,TEXT,TEXT,BOOLEAN,TEXT,UUID[]);
CREATE OR REPLACE FUNCTION public.submit_doubt(
  p_subject_id UUID,p_question TEXT,p_chapter TEXT DEFAULT NULL,p_question_number TEXT DEFAULT NULL,
  p_explanation TEXT DEFAULT NULL,p_previous_attempts TEXT DEFAULT NULL,p_urgent BOOLEAN DEFAULT FALSE,
  p_urgent_reason TEXT DEFAULT NULL,p_attachment_ids UUID[] DEFAULT '{}'::UUID[],p_idempotency_key UUID DEFAULT NULL
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
  IF v_class IS NULL OR NOT EXISTS(SELECT 1 FROM classes WHERE id=v_class AND grade IN ('10','11','12')) THEN
    RETURN jsonb_build_object('success',false,'error','unsupported_class');
  END IF;
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
  IF COALESCE(array_length(p_attachment_ids,1),0)>4 THEN RETURN jsonb_build_object('success',false,'error','too_many_attachments'); END IF;
  SELECT name INTO v_subject_name FROM subjects WHERE id=p_subject_id AND school_id=v_school AND is_active;
  IF v_subject_name IS NULL OR lower(v_subject_name) NOT IN ('physics','chemistry','biology','mathematics') THEN
    RETURN jsonb_build_object('success',false,'error','invalid_subject');
  END IF;
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

  -- Deterministic authorized teacher assignment: same school, current student
  -- class + subject assignment, active teacher, and approved Mentor Desk subject.
  SELECT t.* INTO v_teacher FROM teachers t
    JOIN teaching_assignments ta ON ta.teacher_id=t.id AND ta.class_id=v_class AND ta.subject_id=p_subject_id AND ta.school_id=v_school
    JOIN mentor_subject_approvals ma ON ma.teacher_id=t.id AND ma.subject_id=p_subject_id AND ma.status='approved'
    WHERE t.school_id=v_school AND t.is_active
    ORDER BY (SELECT count(*) FROM doubt_requests prior WHERE prior.assigned_teacher_id=t.id AND prior.status IN ('assigned','in_progress')) ASC,t.id
    LIMIT 1;
  IF FOUND THEN
    UPDATE doubt_requests SET status='assigned',assigned_mentor_id=v_teacher.user_id,assigned_teacher_id=v_teacher.id,updated_at=NOW() WHERE id=v_request;
    INSERT INTO conversation_members(conversation_id,user_id,role,can_send) VALUES(v_conv,v_teacher.user_id,'teacher',true) ON CONFLICT(conversation_id,user_id) DO NOTHING;
    INSERT INTO doubt_status_history(request_id,actor_id,from_status,to_status,reason) VALUES(v_request,v_uid,'pending_assignment','assigned','auto_assignment');
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
REVOKE ALL ON FUNCTION public.submit_doubt(UUID,TEXT,TEXT,TEXT,TEXT,TEXT,BOOLEAN,TEXT,UUID[],UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_doubt(UUID,TEXT,TEXT,TEXT,TEXT,TEXT,BOOLEAN,TEXT,UUID[],UUID) TO authenticated;

-- Secure teacher claim, reply and status changes against current class+subject
-- assignment, not merely shared school membership or stale conversation members.
CREATE OR REPLACE FUNCTION public.claim_doubt(p_request_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_uid UUID:=auth.uid(); v_req doubt_requests%ROWTYPE; v_teacher teachers%ROWTYPE;
BEGIN
  SELECT * INTO v_req FROM doubt_requests WHERE id=p_request_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'error','request_not_found'); END IF;
  SELECT t.* INTO v_teacher FROM teachers t JOIN teaching_assignments ta ON ta.teacher_id=t.id
    JOIN mentor_subject_approvals ma ON ma.teacher_id=t.id AND ma.subject_id=v_req.subject_id AND ma.status='approved'
    WHERE t.user_id=v_uid AND t.is_active AND t.school_id=v_req.school_id AND ta.class_id=v_req.class_id AND ta.subject_id=v_req.subject_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'error','not_assigned_for_class_subject'); END IF;
  IF v_req.status NOT IN ('pending_assignment','waiting') THEN RETURN jsonb_build_object('success',false,'error','request_not_waiting'); END IF;
  UPDATE doubt_requests SET status='assigned',assigned_mentor_id=v_uid,assigned_teacher_id=v_teacher.id,updated_at=NOW() WHERE id=p_request_id;
  INSERT INTO conversation_members(conversation_id,user_id,role,can_send) VALUES(v_req.conversation_id,v_uid,'teacher',true) ON CONFLICT(conversation_id,user_id) DO NOTHING;
  INSERT INTO doubt_status_history(request_id,actor_id,from_status,to_status) VALUES(p_request_id,v_uid,v_req.status,'assigned');
  RETURN jsonb_build_object('success',true,'request_id',p_request_id,'status','assigned');
END $$;

CREATE OR REPLACE FUNCTION public.reply_doubt(p_request_id UUID,p_body TEXT,p_attachment_id UUID DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_uid UUID:=auth.uid(); v_req doubt_requests%ROWTYPE; v_teacher teachers%ROWTYPE; v_result JSONB;
BEGIN
  SELECT * INTO v_req FROM doubt_requests WHERE id=p_request_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'error','request_not_found'); END IF;
  IF v_req.student_id<>v_uid AND v_req.assigned_mentor_id IS DISTINCT FROM v_uid THEN RETURN jsonb_build_object('success',false,'error','not_authorized'); END IF;
  IF v_req.assigned_mentor_id=v_uid THEN
    SELECT t.* INTO v_teacher FROM teachers t JOIN teaching_assignments ta ON ta.teacher_id=t.id
      JOIN mentor_subject_approvals ma ON ma.teacher_id=t.id AND ma.subject_id=v_req.subject_id AND ma.status='approved'
      WHERE t.user_id=v_uid AND t.is_active AND t.school_id=v_req.school_id AND ta.class_id=v_req.class_id AND ta.subject_id=v_req.subject_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'error','assignment_changed'); END IF;
  END IF;
  IF v_req.status IN ('closed','answered') THEN RETURN jsonb_build_object('success',false,'error','doubt_not_open'); END IF;
  v_result:=public.send_message(v_req.conversation_id,v_uid,p_body,gen_random_uuid()::TEXT,NULL,p_attachment_id);
  IF v_req.assigned_mentor_id=v_uid AND v_req.status IN ('assigned','in_progress') THEN
    UPDATE doubt_requests SET status='in_progress',first_reply_at=COALESCE(first_reply_at,NOW()),updated_at=NOW() WHERE id=p_request_id;
    IF v_req.status<>'in_progress' THEN INSERT INTO doubt_status_history(request_id,actor_id,from_status,to_status) VALUES(p_request_id,v_uid,v_req.status,'in_progress'); END IF;
  END IF;
  INSERT INTO audit_events(school_id,actor_id,action,target_type,target_id,outcome) VALUES(v_req.school_id,v_uid,'doubt.reply','doubt_request',p_request_id::TEXT,'success');
  RETURN jsonb_build_object('success',true,'request_id',p_request_id);
END $$;

CREATE OR REPLACE FUNCTION public.resolve_doubt(p_request_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_uid UUID:=auth.uid(); v_req doubt_requests%ROWTYPE; v_teacher teachers%ROWTYPE;
BEGIN
  SELECT * INTO v_req FROM doubt_requests WHERE id=p_request_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'error','request_not_found'); END IF;
  IF v_req.assigned_mentor_id IS DISTINCT FROM v_uid THEN RETURN jsonb_build_object('success',false,'error','not_assigned_mentor'); END IF;
  SELECT t.* INTO v_teacher FROM teachers t JOIN teaching_assignments ta ON ta.teacher_id=t.id
    JOIN mentor_subject_approvals ma ON ma.teacher_id=t.id AND ma.subject_id=v_req.subject_id AND ma.status='approved'
    WHERE t.user_id=v_uid AND t.is_active AND t.school_id=v_req.school_id AND ta.class_id=v_req.class_id AND ta.subject_id=v_req.subject_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'error','assignment_changed'); END IF;
  IF v_req.status NOT IN ('assigned','in_progress') THEN RETURN jsonb_build_object('success',false,'error','invalid_transition'); END IF;
  UPDATE doubt_requests SET status='answered',resolved_at=NOW(),updated_at=NOW() WHERE id=p_request_id;
  INSERT INTO doubt_status_history(request_id,actor_id,from_status,to_status) VALUES(p_request_id,v_uid,v_req.status,'answered');
  RETURN jsonb_build_object('success',true,'request_id',p_request_id,'status','answered');
END $$;

CREATE OR REPLACE FUNCTION public.close_doubt(p_request_id UUID,p_reason TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_uid UUID:=auth.uid(); v_req doubt_requests%ROWTYPE;
BEGIN
  SELECT * INTO v_req FROM doubt_requests WHERE id=p_request_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'error','request_not_found'); END IF;
  IF v_req.student_id<>v_uid THEN RETURN jsonb_build_object('success',false,'error','not_the_student'); END IF;
  IF v_req.status NOT IN ('answered','resolved') THEN RETURN jsonb_build_object('success',false,'error','invalid_transition'); END IF;
  UPDATE doubt_requests SET status='closed',closed_at=NOW(),updated_at=NOW() WHERE id=p_request_id;
  INSERT INTO doubt_status_history(request_id,actor_id,from_status,to_status,reason) VALUES(p_request_id,v_uid,v_req.status,'closed',p_reason);
  RETURN jsonb_build_object('success',true,'request_id',p_request_id,'status','closed');
END $$;

CREATE OR REPLACE FUNCTION public.reopen_doubt(p_request_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_uid UUID:=auth.uid(); v_req doubt_requests%ROWTYPE;
BEGIN
  SELECT * INTO v_req FROM doubt_requests WHERE id=p_request_id FOR UPDATE;
  IF NOT FOUND OR v_req.student_id<>v_uid THEN RETURN jsonb_build_object('success',false,'error','not_the_student'); END IF;
  IF v_req.status<>'closed' THEN RETURN jsonb_build_object('success',false,'error','invalid_transition'); END IF;
  UPDATE doubt_requests SET status='reopened',closed_at=NULL,updated_at=NOW() WHERE id=p_request_id;
  INSERT INTO doubt_status_history(request_id,actor_id,from_status,to_status) VALUES(p_request_id,v_uid,'closed','reopened');
  RETURN jsonb_build_object('success',true,'request_id',p_request_id,'status','reopened');
END $$;

-- Session allowance is one account-wide student budget/week, reservations count
-- immediately. Confirmations cannot change duration or assigned scope.
CREATE OR REPLACE FUNCTION public.book_session(
  p_subject_id UUID,p_mentor_id UUID,p_duration_minutes INTEGER,p_scheduled_at TIMESTAMPTZ,
  p_topic TEXT,p_preparation TEXT DEFAULT NULL,p_attachment_ids UUID[] DEFAULT '{}'::UUID[]
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_uid UUID:=auth.uid(); v_student students%ROWTYPE; v_settings mentor_desk_settings%ROWTYPE;
  v_school UUID; v_class UUID;  v_tz TEXT; v_week DATE; v_used INTEGER; v_booking UUID;
  v_teacher teachers%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success',false,'error','not_authenticated'); END IF;
  SELECT * INTO v_student FROM students WHERE user_id=v_uid AND is_active LIMIT 1;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'error','student_not_found'); END IF;
  v_school:=v_student.school_id;
  PERFORM pg_advisory_xact_lock(hashtext(v_uid::text||':book-session'));
  SELECT ce.class_id INTO v_class FROM class_enrollments ce JOIN classes c ON c.id=ce.class_id
    WHERE ce.student_id=v_student.id AND ce.unenrolled_at IS NULL AND c.is_active ORDER BY ce.enrolled_at DESC LIMIT 1;
  IF v_class IS NULL OR NOT EXISTS(SELECT 1 FROM classes WHERE id=v_class AND grade IN ('10','11','12')) THEN RETURN jsonb_build_object('success',false,'error','unsupported_class'); END IF;
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

CREATE OR REPLACE FUNCTION public.confirm_session(p_booking_id UUID,p_scheduled_at TIMESTAMPTZ,p_duration_minutes INTEGER,p_meeting_link TEXT DEFAULT NULL,p_meeting_room TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_uid UUID:=auth.uid(); v_booking session_bookings%ROWTYPE; v_teacher teachers%ROWTYPE;
BEGIN
  SELECT * INTO v_booking FROM session_bookings WHERE id=p_booking_id FOR UPDATE;
  IF NOT FOUND OR v_booking.status<>'requested' THEN RETURN jsonb_build_object('success',false,'error','booking_not_requested'); END IF;
  IF v_uid IS DISTINCT FROM v_booking.mentor_id THEN RETURN jsonb_build_object('success',false,'error','not_the_mentor'); END IF;
  IF p_duration_minutes<>v_booking.reserved_minutes OR p_duration_minutes NOT IN (15,30) THEN RETURN jsonb_build_object('success',false,'error','invalid_duration'); END IF;
  SELECT t.* INTO v_teacher FROM teachers t JOIN teaching_assignments ta ON ta.teacher_id=t.id
    JOIN mentor_subject_approvals ma ON ma.teacher_id=t.id AND ma.subject_id=v_booking.subject_id AND ma.status='approved'
    WHERE t.user_id=v_uid AND t.is_active AND t.school_id=v_booking.school_id AND ta.class_id=v_booking.class_id AND ta.subject_id=v_booking.subject_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'error','assignment_changed'); END IF;
  UPDATE session_bookings SET status='confirmed',scheduled_at=p_scheduled_at,confirmed_at=NOW(),meeting_link=p_meeting_link,meeting_room=p_meeting_room,updated_at=NOW() WHERE id=p_booking_id;
  INSERT INTO audit_events(school_id,actor_id,action,target_type,target_id,outcome) VALUES(v_booking.school_id,v_uid,'session.confirm','session_booking',p_booking_id::TEXT,'success');
  RETURN jsonb_build_object('success',true,'booking_id',p_booking_id,'status','confirmed');
END $$;

CREATE OR REPLACE FUNCTION public.cancel_session(p_booking_id UUID,p_cancelled_by UUID DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_uid UUID:=auth.uid(); v_booking session_bookings%ROWTYPE; v_tz TEXT; v_week DATE;
BEGIN
  SELECT * INTO v_booking FROM session_bookings WHERE id=p_booking_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'error','booking_not_found'); END IF;
  IF v_uid NOT IN (v_booking.student_id,v_booking.mentor_id) THEN RETURN jsonb_build_object('success',false,'error','not_a_participant'); END IF;
  IF v_booking.status NOT IN ('requested','confirmed') OR v_booking.started_at IS NOT NULL THEN RETURN jsonb_build_object('success',false,'error','booking_not_cancellable'); END IF;
  IF v_booking.refunded THEN RETURN jsonb_build_object('success',true,'status',v_booking.status,'refunded',true); END IF;
  SELECT COALESCE(timezone,'Asia/Kolkata') INTO v_tz FROM school_settings WHERE school_id=v_booking.school_id;
  v_week:=tc_week_start(NOW(),COALESCE(v_tz,'Asia/Kolkata'));
  UPDATE session_bookings SET status=CASE WHEN v_uid=v_booking.student_id THEN 'cancelled_by_student'::booking_status ELSE 'cancelled_by_mentor'::booking_status END,
    refunded=true,cancelled_at=NOW(),cancelled_by=v_uid,updated_at=NOW() WHERE id=p_booking_id;
  INSERT INTO allowance_transactions(school_id,student_id,subject_id,booking_id,week_start,action,minutes,reason)
    VALUES(v_booking.school_id,v_booking.student_id,v_booking.subject_id,p_booking_id,v_week,'refund',v_booking.reserved_minutes,'cancel_before_start');
  INSERT INTO audit_events(school_id,actor_id,action,target_type,target_id,outcome) VALUES(v_booking.school_id,v_uid,'session.cancel','session_booking',p_booking_id::TEXT,'success');
  RETURN jsonb_build_object('success',true,'booking_id',p_booking_id,'refunded',true);
END $$;

-- Student explicitly starts a confirmed meeting; OTP is generated after ending.
CREATE OR REPLACE FUNCTION public.start_teacher_session(p_booking_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_booking session_bookings%ROWTYPE;
BEGIN
  SELECT * INTO v_booking FROM session_bookings WHERE id=p_booking_id FOR UPDATE;
  IF NOT FOUND OR v_booking.student_id<>auth.uid() AND v_booking.mentor_id<>auth.uid() THEN RETURN jsonb_build_object('success',false,'error','not_a_participant'); END IF;
  IF v_booking.status<>'confirmed' THEN RETURN jsonb_build_object('success',false,'error','booking_not_confirmed'); END IF;
  IF v_booking.started_at IS NOT NULL THEN RETURN jsonb_build_object('success',true,'started_at',v_booking.started_at,'idempotent',true); END IF;
  UPDATE session_bookings SET started_at=NOW(),updated_at=NOW() WHERE id=p_booking_id;
  RETURN jsonb_build_object('success',true,'started_at',NOW());
END $$;

CREATE OR REPLACE FUNCTION public.generate_verification_code(p_booking_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE  v_uid UUID:=auth.uid(); v_booking session_bookings%ROWTYPE; v_code TEXT; v_salt TEXT; v_exp TIMESTAMPTZ; v_now TIMESTAMPTZ:=NOW();
BEGIN
  SELECT * INTO v_booking FROM session_bookings WHERE id=p_booking_id FOR UPDATE;
  IF NOT FOUND OR v_booking.student_id<>v_uid THEN RETURN jsonb_build_object('success',false,'error','not_the_student'); END IF;
  IF v_booking.status<>'confirmed' OR v_booking.started_at IS NULL THEN RETURN jsonb_build_object('success',false,'error','session_not_started'); END IF;
  IF v_booking.otp_hash IS NOT NULL AND v_booking.otp_hash_expires_at>v_now THEN
    RETURN jsonb_build_object('success',false,'error','code_already_issued','expires_at',v_booking.otp_hash_expires_at);
  END IF;
  IF v_booking.otp_resend_count>=3 THEN RETURN jsonb_build_object('success',false,'error','resend_limit_reached'); END IF;
  v_salt:=encode(gen_random_bytes(16),'hex');
  v_code:=lpad((('x'||substr(encode(gen_random_bytes(8),'hex'),1,16))::bit(64)::bigint::numeric % 1000000)::text,6,'0');
  v_exp:=v_now+interval '30 minutes';
  UPDATE session_bookings SET otp_hash=encode(digest(v_code||':'||v_salt||':'||p_booking_id::TEXT||':'||v_uid::TEXT,'sha256'),'hex'),
    otp_salt=v_salt,otp_issued_at=v_now,otp_hash_expires_at=v_exp,otp_resend_count=otp_resend_count+1,
    code_attempts=0,code_locked_at=NULL,verification_code=NULL,code_expires_at=NULL,code_visible_at=v_now,updated_at=v_now
    WHERE id=p_booking_id;
  INSERT INTO audit_events(school_id,actor_id,action,target_type,target_id,outcome) VALUES(v_booking.school_id,v_uid,'session.code.generated','session_booking',p_booking_id::TEXT,'success');
  RETURN jsonb_build_object('success',true,'verification_code',v_code,'expires_at',v_exp,'instructions','Share this one-time code with your assigned teacher to confirm this session.');
END $$;

CREATE OR REPLACE FUNCTION public.verify_session_code(p_booking_id UUID,p_code TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_uid UUID:=auth.uid(); v_booking session_bookings%ROWTYPE; v_hash TEXT; v_week DATE; v_tz TEXT;
BEGIN
  SELECT * INTO v_booking FROM session_bookings WHERE id=p_booking_id FOR UPDATE;
  IF NOT FOUND OR v_booking.mentor_id IS DISTINCT FROM v_uid THEN RETURN jsonb_build_object('success',false,'error','not_the_mentor'); END IF;
  IF v_booking.status='completed' AND v_booking.verified_at IS NOT NULL THEN RETURN jsonb_build_object('success',true,'status','completed','idempotent',true); END IF;
  IF v_booking.status<>'confirmed' OR v_booking.started_at IS NULL THEN RETURN jsonb_build_object('success',false,'error','booking_not_confirmed'); END IF;
  IF v_booking.otp_hash IS NULL THEN RETURN jsonb_build_object('success',false,'error','no_code'); END IF;
  IF v_booking.otp_hash_expires_at<=NOW() THEN RETURN jsonb_build_object('success',false,'error','code_expired'); END IF;
  IF v_booking.code_locked_at IS NOT NULL THEN RETURN jsonb_build_object('success',false,'error','code_locked'); END IF;
  UPDATE session_bookings SET code_attempts=code_attempts+1 WHERE id=p_booking_id;
  v_hash:=encode(digest(COALESCE(p_code,'')||':'||v_booking.otp_salt||':'||p_booking_id::TEXT||':'||v_booking.student_id::TEXT,'sha256'),'hex');
  IF v_hash<>v_booking.otp_hash THEN
    IF v_booking.code_attempts+1>=5 THEN UPDATE session_bookings SET code_locked_at=NOW() WHERE id=p_booking_id; END IF;
    INSERT INTO audit_events(school_id,actor_id,action,target_type,target_id,outcome,metadata) VALUES(v_booking.school_id,v_uid,'session.code.failed','session_booking',p_booking_id::TEXT,'failure',jsonb_build_object('attempt',v_booking.code_attempts+1));
    RETURN jsonb_build_object('success',false,'error',CASE WHEN v_booking.code_attempts+1>=5 THEN 'code_locked' ELSE 'incorrect_code' END);
  END IF;
  SELECT COALESCE(timezone,'Asia/Kolkata') INTO v_tz FROM school_settings WHERE school_id=v_booking.school_id;
  v_week:=tc_week_start(NOW(),COALESCE(v_tz,'Asia/Kolkata'));
  IF EXISTS(SELECT 1 FROM allowance_transactions WHERE booking_id=p_booking_id AND reason='verified_actual_use') THEN
    RETURN jsonb_build_object('success',true,'status','completed','idempotent',true);
  END IF;
  UPDATE session_bookings SET status='completed',verified_at=NOW(),ended_at=COALESCE(ended_at,NOW()),actual_minutes=LEAST(reserved_minutes,GREATEST(1,CEIL(EXTRACT(EPOCH FROM (NOW()-started_at))/60.0)::INTEGER)),
    allowance_minutes_used=reserved_minutes,otp_hash=NULL,otp_salt=NULL,otp_hash_expires_at=NULL,verification_code=NULL,updated_at=NOW() WHERE id=p_booking_id AND status='confirmed';
  INSERT INTO allowance_transactions(school_id,student_id,subject_id,booking_id,week_start,action,minutes,reason)
    VALUES(v_booking.school_id,v_booking.student_id,v_booking.subject_id,p_booking_id,v_week,'refund',
      GREATEST(0,v_booking.reserved_minutes-LEAST(v_booking.reserved_minutes,GREATEST(1,CEIL(EXTRACT(EPOCH FROM (NOW()-v_booking.started_at))/60.0)::INTEGER))),'verified_actual_use');
  INSERT INTO audit_events(school_id,actor_id,action,target_type,target_id,outcome) VALUES(v_booking.school_id,v_uid,'session.verify','session_booking',p_booking_id::TEXT,'success');
  RETURN jsonb_build_object('success',true,'booking_id',p_booking_id,'status','completed','actual_minutes',LEAST(v_booking.reserved_minutes,GREATEST(1,CEIL(EXTRACT(EPOCH FROM (NOW()-v_booking.started_at))/60.0)::INTEGER)));
END $$;

-- Legacy exception closure is admin-only and remains explicitly unverified.
CREATE OR REPLACE FUNCTION public.close_session_without_code(p_booking_id UUID,p_reason TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_booking session_bookings%ROWTYPE;
BEGIN
  SELECT * INTO v_booking FROM session_bookings WHERE id=p_booking_id FOR UPDATE;
  IF NOT FOUND OR NOT public.tc_is_school_admin(v_booking.school_id) THEN RETURN jsonb_build_object('success',false,'error','forbidden'); END IF;
  IF v_booking.status<>'confirmed' OR p_reason IS NULL OR length(trim(p_reason))<8 THEN RETURN jsonb_build_object('success',false,'error','invalid_exception'); END IF;
  UPDATE session_bookings SET status='unverified_closed',closed_without_code=true,close_reason=p_reason,ended_at=NOW(),updated_at=NOW() WHERE id=p_booking_id;
  INSERT INTO audit_events(school_id,actor_id,action,target_type,target_id,outcome,metadata) VALUES(v_booking.school_id,auth.uid(),'session.close_without_code','session_booking',p_booking_id::TEXT,'success',jsonb_build_object('reason',p_reason));
  RETURN jsonb_build_object('success',true,'status','unverified_closed');
END $$;
