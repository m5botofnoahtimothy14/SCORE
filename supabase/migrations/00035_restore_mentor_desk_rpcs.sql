-- ============================================================
-- 00035: restore Mentor Desk RPCs against the reconciled schema.
-- Functions use auth.uid() and enforce student/teacher/admin scope.
-- ============================================================

CREATE OR REPLACE FUNCTION public.tc_week_start(p_ts TIMESTAMPTZ, p_tz TEXT)
RETURNS DATE
LANGUAGE sql STABLE
AS $$
  SELECT (p_ts AT TIME ZONE p_tz)::DATE
         - EXTRACT(ISODOW FROM (p_ts AT TIME ZONE p_tz))::INTEGER + 1;
$$;

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

CREATE OR REPLACE FUNCTION public.record_no_show(
  p_booking_id   UUID,
  p_reported_by_role TEXT,
  p_reason       TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid     UUID := auth.uid();
  v_booking session_bookings%ROWTYPE;
  v_ns_type no_show_type;
  v_refund  INTEGER;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO v_booking FROM session_bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'booking_not_found');
  END IF;

  -- Participant reports the other party
  IF v_uid = v_booking.student_id THEN
    v_ns_type := 'mentor_no_show';
    v_refund := v_booking.allowance_minutes_used;
  ELSIF v_uid = v_booking.mentor_id THEN
    v_ns_type := 'student_no_show';
    v_refund := 0; -- student no-show: no refund to student
  ELSE
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_a_participant');
  END IF;

  IF v_booking.status IN ('no_show_student', 'no_show_mentor', 'completed') THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'already_resolved');
  END IF;

  INSERT INTO session_no_shows(
    school_id, booking_id, reported_by, reported_by_role,
    no_show_type, refund_minutes, review_status, created_at
  )
  VALUES (
    v_booking.school_id, p_booking_id, v_uid, p_reported_by_role,
    v_ns_type, v_refund, 'pending', NOW()
  );

  IF v_ns_type = 'mentor_no_show' THEN
    -- Refund the student's allowance
    UPDATE session_bookings
    SET status = 'no_show_mentor', refunded = TRUE, updated_at = NOW()
    WHERE id = p_booking_id AND status = 'confirmed';

    INSERT INTO allowance_transactions(
      school_id, student_id, subject_id, booking_id,
      date_trunc('week', v_booking.requested_at)::DATE,
      action, minutes, reason, created_at
    )
    VALUES (
      v_booking.school_id, v_booking.student_id, v_booking.subject_id,
      p_booking_id, date_trunc('week', v_booking.requested_at)::DATE,
      'refund', v_refund, 'mentor_no_show', NOW()
    );
  ELSE
    UPDATE session_bookings
    SET status = 'no_show_student', updated_at = NOW()
    WHERE id = p_booking_id AND status = 'confirmed';
  END IF;

  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome)
  VALUES (v_booking.school_id, v_uid, 'session.no_show', 'session_booking', p_booking_id::TEXT, 'success');

  RETURN jsonb_build_object(
    'success', TRUE,
    'booking_id', p_booking_id,
    'no_show_type', v_ns_type,
    'refund_minutes', v_refund
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.set_mentor_availability(p_status availability_status)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_teacher teachers%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT * INTO v_teacher
  FROM teachers
  WHERE user_id = auth.uid() AND is_active = TRUE
  LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_a_teacher';
  END IF;

  INSERT INTO mentor_availability(school_id, teacher_id, status, updated_at)
  VALUES (v_teacher.school_id, v_teacher.id, p_status, NOW())
  ON CONFLICT (teacher_id) DO UPDATE
    SET status = EXCLUDED.status, updated_at = NOW();

  PERFORM public.touch_my_presence();
END;
$$;

CREATE OR REPLACE FUNCTION public.approve_mentor_subject(
  p_teacher_id UUID,
  p_subject_id UUID,
  p_approved   BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_school UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authenticated');
  END IF;

  SELECT t.school_id INTO v_school FROM teachers WHERE id = p_teacher_id;
  IF v_school IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'teacher_not_found');
  END IF;

  IF NOT public.tc_is_school_admin(v_school) THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'forbidden');
  END IF;

  INSERT INTO mentor_subject_approvals(
    school_id, teacher_id, subject_id,
    status, approved_by, approved_at, created_at
  )
  VALUES (
    v_school, p_teacher_id, p_subject_id,
    CASE WHEN p_approved THEN 'approved' ELSE 'rejected' END,
    auth.uid(), NOW(), NOW()
  )
  ON CONFLICT (teacher_id, subject_id) DO UPDATE
    SET status = CASE WHEN p_approved THEN 'approved' ELSE 'rejected' END,
        approved_by = auth.uid(),
        approved_at = NOW(),
        updated_at = NOW();

  RETURN jsonb_build_object('success', TRUE);
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_rating(
  p_request_id UUID,
  p_rating     INTEGER,
  p_comment    TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid  UUID := auth.uid();
  v_req  doubt_requests%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authenticated');
  END IF;

  IF p_rating < 1 OR p_rating > 5 THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'invalid_rating');
  END IF;

  SELECT * INTO v_req FROM doubt_requests WHERE id = p_request_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'request_not_found');
  END IF;

  IF v_req.student_id IS DISTINCT FROM v_uid THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_the_student');
  END IF;

  -- Accept answered/resolved/reopened-closed states
  IF v_req.status <> 'answered' AND v_req.status <> 'resolved' AND v_req.status <> 'closed' THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'request_not_closed');
  END IF;

  INSERT INTO ratings(school_id, request_id, student_id, mentor_id, rating, comment)
  VALUES (v_req.school_id, p_request_id, v_uid, v_req.assigned_mentor_id, p_rating, p_comment)
  ON CONFLICT (request_id, student_id) DO UPDATE
    SET rating = EXCLUDED.rating,
        comment = EXCLUDED.comment,
        created_at = NOW();

  UPDATE doubt_requests
  SET status = 'closed', closed_at = NOW(), updated_at = NOW()
  WHERE id = p_request_id AND status IN ('answered', 'resolved');

  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome)
  VALUES (v_req.school_id, v_uid, 'rating.submit', 'rating', p_request_id::TEXT, 'success');

  RETURN jsonb_build_object('success', TRUE, 'request_id', p_request_id, 'rating', p_rating);
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_mentor_assessment(
  p_request_id   UUID,
  p_preparation  engagement_scale,
  p_engagement   engagement_scale,
  p_private_note TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid  UUID := auth.uid();
  v_req  doubt_requests%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO v_req FROM doubt_requests WHERE id = p_request_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'request_not_found');
  END IF;

  IF v_uid IS DISTINCT FROM v_req.assigned_mentor_id THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_assigned_mentor');
  END IF;

  IF v_req.status <> 'answered' AND v_req.status <> 'resolved' AND v_req.status <> 'closed' THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'request_not_closed');
  END IF;

  INSERT INTO mentor_assessments(
    school_id, request_id, mentor_id, student_id,
    preparation, engagement, private_note, created_at, updated_at
  )
  VALUES (v_req.school_id, p_request_id, v_uid, v_req.student_id,
          p_preparation, p_engagement, p_private_note, NOW(), NOW())
  ON CONFLICT (request_id, mentor_id) DO UPDATE
    SET preparation = EXCLUDED.preparation,
        engagement = EXCLUDED.engagement,
        private_note = EXCLUDED.private_note,
        updated_at = NOW();

  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome)
  VALUES (v_req.school_id, v_uid, 'mentor.assessment', 'mentor_assessment', p_request_id::TEXT, 'success');

  RETURN jsonb_build_object('success', TRUE, 'request_id', p_request_id);
END;
$$;

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

CREATE OR REPLACE FUNCTION public.submit_doubt(
  p_subject_id uuid,
  p_question text,
  p_chapter text DEFAULT NULL,
  p_question_number text DEFAULT NULL,
  p_explanation text DEFAULT NULL,
  p_previous_attempts text DEFAULT NULL,
  p_urgent boolean DEFAULT false,
  p_urgent_reason text DEFAULT NULL,
  p_attachment_ids uuid[] DEFAULT '{}'::uuid[],
  p_idempotency_key uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_student public.students%ROWTYPE;
  v_settings public.mentor_desk_settings%ROWTYPE;
  v_school uuid;
  v_class uuid;
  v_timezone text;
  v_week_start date;
  v_week_start_ts timestamptz;
  v_next_reset timestamptz;
  v_used_normal integer := 0;
  v_normal_limit integer := 3;
  v_request uuid;
  v_conversation uuid;
  v_subject_name text;
  v_teacher public.teachers%ROWTYPE;
  v_message jsonb;
  v_valid_attachments integer := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  IF p_question IS NULL OR length(trim(p_question)) < 2 OR length(p_question) > 4000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_question');
  END IF;
  IF COALESCE(cardinality(p_attachment_ids), 0) > 4 THEN
    RETURN jsonb_build_object('success', false, 'error', 'too_many_attachments');
  END IF;

  SELECT * INTO v_student
  FROM public.students
  WHERE user_id = v_uid AND is_active = true
  LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'student_not_found');
  END IF;
  v_school := v_student.school_id;

  PERFORM pg_advisory_xact_lock(hashtext(v_uid::text || ':mentor-desk-doubt'));

  IF p_idempotency_key IS NOT NULL THEN
    SELECT id, conversation_id INTO v_request, v_conversation
    FROM public.doubt_requests
    WHERE student_id = v_uid AND idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true, 'request_id', v_request,
        'conversation_id', v_conversation, 'duplicate', true
      );
    END IF;
  END IF;

  SELECT ce.class_id INTO v_class
  FROM public.class_enrollments ce
  JOIN public.classes c ON c.id = ce.class_id
  WHERE ce.student_id = v_student.id
    AND ce.unenrolled_at IS NULL
    AND c.is_active = true
  ORDER BY ce.enrolled_at DESC
  LIMIT 1;

  IF v_class IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.classes
    WHERE id = v_class AND grade IN ('10', '11', '12')
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'unsupported_class');
  END IF;

  SELECT * INTO v_settings
  FROM public.mentor_desk_settings
  WHERE school_id = v_school;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'settings_not_configured');
  END IF;
  v_normal_limit := LEAST(COALESCE(v_settings.weekly_doubt_allowance, 3), 3);

  SELECT s.name INTO v_subject_name
  FROM public.subjects s
  WHERE s.id = p_subject_id
    AND s.school_id = v_school
    AND s.is_active = true
    AND lower(s.name) IN ('physics', 'chemistry', 'biology', 'mathematics');

  IF v_subject_name IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_subject');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.student_subject_enrollments e
    WHERE e.student_id = v_student.id
      AND e.class_id = v_class
      AND e.subject_id = p_subject_id
      AND e.active = true
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'subject_not_enrolled');
  END IF;

  IF cardinality(COALESCE(p_attachment_ids, '{}'::uuid[])) > 0 THEN
    SELECT count(*) INTO v_valid_attachments
    FROM public.attachments a
    WHERE a.id = ANY(p_attachment_ids)
      AND a.uploader_id = v_uid
      AND a.school_id = v_school
      AND a.message_id IS NULL;
    IF v_valid_attachments <> cardinality(p_attachment_ids) THEN
      RETURN jsonb_build_object('success', false, 'error', 'invalid_attachment');
    END IF;
  END IF;

  SELECT COALESCE(ss.timezone, 'Asia/Kolkata') INTO v_timezone
  FROM public.school_settings ss
  WHERE ss.school_id = v_school;
  v_timezone := COALESCE(v_timezone, 'Asia/Kolkata');
  v_week_start := public.tc_week_start(now(), v_timezone);
  v_week_start_ts := v_week_start::timestamp AT TIME ZONE v_timezone;
  v_next_reset := (v_week_start::timestamp + interval '7 days') AT TIME ZONE v_timezone;

  IF p_urgent THEN
    IF p_urgent_reason IS NULL OR length(trim(p_urgent_reason)) < 3 THEN
      RETURN jsonb_build_object('success', false, 'error', 'urgent_reason_required');
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.urgent_pass_usage u
      WHERE u.student_id = v_uid
        AND u.subject_id = p_subject_id
        AND u.week_start = v_week_start
    ) THEN
      RETURN jsonb_build_object('success', false, 'error', 'urgent_pass_used');
    END IF;
  ELSE
    SELECT count(*) INTO v_used_normal
    FROM public.doubt_requests d
    WHERE d.student_id = v_uid
      AND d.subject_id = p_subject_id
      AND d.urgent = false
      AND d.created_at >= v_week_start_ts;
    IF v_used_normal >= v_normal_limit THEN
      RETURN jsonb_build_object(
        'success', false, 'error', 'weekly_quota_reached',
        'remaining', 0, 'next_reset_at', v_next_reset
      );
    END IF;
  END IF;

  INSERT INTO public.conversations(school_id, type, class_id, title, created_by, is_active)
  VALUES (v_school, 'mentor_desk', v_class, 'Doubt: ' || left(p_question, 60), v_uid, true)
  RETURNING id INTO v_conversation;

  INSERT INTO public.conversation_members(conversation_id, user_id, role, can_send)
  VALUES (v_conversation, v_uid, 'student', true);

  INSERT INTO public.doubt_requests(
    school_id, conversation_id, student_id, student_record_id, class_id,
    subject_id, question, chapter, question_number, explanation,
    previous_attempts, urgent, urgent_reason, status, idempotency_key,
    created_at, updated_at
  )
  VALUES (
    v_school, v_conversation, v_uid, v_student.id, v_class,
    p_subject_id, trim(p_question), p_chapter, p_question_number, p_explanation,
    p_previous_attempts, p_urgent, p_urgent_reason, 'pending_assignment',
    p_idempotency_key, now(), now()
  )
  RETURNING id INTO v_request;

  IF p_urgent THEN
    INSERT INTO public.urgent_pass_usage(
      school_id, student_id, subject_id, request_id, week_start
    )
    VALUES (v_school, v_uid, p_subject_id, v_request, v_week_start)
    ON CONFLICT (student_id, subject_id, week_start) DO NOTHING;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'urgent_pass_used';
    END IF;
    UPDATE public.doubt_requests SET urgent_pass_used = true WHERE id = v_request;
  END IF;

  INSERT INTO public.doubt_status_history(request_id, actor_id, from_status, to_status, reason)
  VALUES (v_request, v_uid, NULL, 'pending_assignment', 'accepted_submission');

  v_message := public.send_message(
    v_conversation, v_uid, trim(p_question),
    COALESCE(p_idempotency_key, gen_random_uuid())::text, NULL, NULL
  );
  IF COALESCE((v_message->>'success')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'doubt_message_rejected';
  END IF;

  IF cardinality(COALESCE(p_attachment_ids, '{}'::uuid[])) > 0 THEN
    UPDATE public.attachments
    SET message_id = (
      SELECT m.id FROM public.messages m
      WHERE m.conversation_id = v_conversation
        AND m.sender_id = v_uid
      ORDER BY m.created_at DESC
      LIMIT 1
    )
    WHERE id = ANY(p_attachment_ids)
      AND uploader_id = v_uid
      AND school_id = v_school
      AND message_id IS NULL;
  END IF;

  SELECT t.* INTO v_teacher
  FROM public.teachers t
  JOIN public.teaching_assignments ta
    ON ta.teacher_id = t.id
   AND ta.class_id = v_class
   AND ta.subject_id = p_subject_id
   AND ta.school_id = v_school
  JOIN public.mentor_subject_approvals ma
    ON ma.teacher_id = t.id
   AND ma.subject_id = p_subject_id
   AND ma.status = 'approved'
  WHERE t.school_id = v_school
    AND t.is_active = true
    AND t.user_id IS NOT NULL
  ORDER BY (
    SELECT count(*)
    FROM public.doubt_requests prior
    WHERE prior.assigned_teacher_id = t.id
      AND prior.status IN ('assigned', 'in_progress')
  ), t.id
  LIMIT 1;

  IF FOUND THEN
    UPDATE public.doubt_requests
    SET status = 'assigned',
        assigned_mentor_id = v_teacher.user_id,
        assigned_teacher_id = v_teacher.id,
        updated_at = now()
    WHERE id = v_request;

    IF v_teacher.user_id IS NOT NULL THEN
      INSERT INTO public.conversation_members(conversation_id, user_id, role, can_send)
      VALUES (v_conversation, v_teacher.user_id, 'teacher', true)
      ON CONFLICT (conversation_id, user_id) DO NOTHING;

      INSERT INTO public.doubt_status_history(
        request_id, actor_id, from_status, to_status, reason
      )
      VALUES (v_request, v_uid, 'pending_assignment', 'assigned', 'auto_assignment');

      INSERT INTO public.notification_jobs(
        school_id, recipient_id, type, title, body, data, idempotency_key
      )
      VALUES (
        v_school, v_teacher.user_id, 'urgent_doubt',
        CASE WHEN p_urgent THEN 'Urgent student doubt' ELSE 'New student doubt' END,
        'A student submitted a doubt in ' || v_subject_name,
        jsonb_build_object('route', 'mentor-desk/queue', 'doubt_id', v_request),
        'doubt-assignment:' || v_request::text
      )
      ON CONFLICT (idempotency_key) DO NOTHING;
    END IF;
  END IF;

  INSERT INTO public.audit_events(
    school_id, actor_id, action, target_type, target_id, outcome, metadata
  )
  VALUES (
    v_school, v_uid, 'doubt.submit', 'doubt_request', v_request::text, 'success',
    jsonb_build_object('urgent', p_urgent, 'subject_id', p_subject_id, 'class_id', v_class)
  );

  RETURN jsonb_build_object(
    'success', true,
    'request_id', v_request,
    'conversation_id', v_conversation,
    'status', CASE WHEN v_teacher.id IS NULL THEN 'pending_assignment' ELSE 'assigned' END,
    'urgent_pass_used', p_urgent,
    'remaining', GREATEST(0, v_normal_limit - v_used_normal - CASE WHEN p_urgent THEN 0 ELSE 1 END),
    'urgent_available', NOT EXISTS (
      SELECT 1 FROM public.urgent_pass_usage u
      WHERE u.student_id = v_uid AND u.subject_id = p_subject_id AND u.week_start = v_week_start
    ),
    'next_reset_at', v_next_reset
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_student_learning_allowances()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_student public.students%ROWTYPE;
  v_settings public.mentor_desk_settings%ROWTYPE;
  v_timezone text := 'Asia/Kolkata';
  v_week_start date;
  v_reset timestamptz;
  v_session_used integer := 0;
  v_class uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_student FROM public.students WHERE user_id = v_uid AND is_active LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'student_not_found'; END IF;
  SELECT * INTO v_settings FROM public.mentor_desk_settings WHERE school_id = v_student.school_id;
  SELECT COALESCE(timezone, 'Asia/Kolkata') INTO v_timezone
  FROM public.school_settings WHERE school_id = v_student.school_id;
  v_timezone := COALESCE(v_timezone, 'Asia/Kolkata');
  v_week_start := public.tc_week_start(now(), v_timezone);
  v_reset := (v_week_start::timestamp + interval '7 days') AT TIME ZONE v_timezone;
  SELECT ce.class_id INTO v_class
  FROM public.class_enrollments ce
  JOIN public.classes c ON c.id = ce.class_id
  WHERE ce.student_id = v_student.id AND ce.unenrolled_at IS NULL AND c.is_active
  ORDER BY ce.enrolled_at DESC LIMIT 1;
  SELECT COALESCE(sum(CASE WHEN action = 'deduct' THEN minutes ELSE -minutes END), 0)::integer
  INTO v_session_used
  FROM public.allowance_transactions
  WHERE student_id = v_uid AND week_start = v_week_start;

  RETURN jsonb_build_object(
    'timezone', v_timezone,
    'week_start', v_week_start,
    'next_reset_at', v_reset,
    'session_allowance_minutes', COALESCE(v_settings.session_allowance_minutes, 60),
    'session_used_minutes', v_session_used,
    'session_remaining_minutes', GREATEST(0, COALESCE(v_settings.session_allowance_minutes, 60) - v_session_used),
    'doubt_allowance', LEAST(COALESCE(v_settings.weekly_doubt_allowance, 3), 3),
    'subjects', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'subject_id', s.id,
        'subject_name', s.name,
        'used', (
          SELECT count(*) FROM public.doubt_requests d
          WHERE d.student_id = v_uid AND d.subject_id = s.id
            AND d.urgent = false
            AND d.created_at >= v_week_start::timestamp AT TIME ZONE v_timezone
        ),
        'urgent_available', NOT EXISTS (
          SELECT 1 FROM public.urgent_pass_usage u
          WHERE u.student_id = v_uid AND u.subject_id = s.id AND u.week_start = v_week_start
        )
      ) ORDER BY s.name)
      FROM public.student_subject_enrollments e
      JOIN public.subjects s ON s.id = e.subject_id
      WHERE e.student_id = v_student.id
        AND e.class_id = v_class
        AND e.active = true
        AND lower(s.name) IN ('physics', 'chemistry', 'biology', 'mathematics')
    ), '[]'::jsonb)
  );
END;
$$;

-- Participant-scoped read policies for Mentor Desk data.
-- Remove stale policies first. This prevents permissive legacy policies
-- from widening access through PostgreSQL's OR-combination of policies.
DO $
DECLARE
  v_table text;
  v_policy record;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'doubt_requests',
    'doubt_status_history',
    'ratings',
    'mentor_assessments',
    'mentor_availability',
    'mentor_subject_approvals',
    'allowance_transactions',
    'urgent_pass_usage',
    'session_no_shows',
    'mentor_desk_settings'
  ] LOOP
    FOR v_policy IN
      SELECT policyname FROM pg_policies
      WHERE schemaname = 'public' AND tablename = v_table
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', v_policy.policyname, v_table);
    END LOOP;
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', v_table);
  END LOOP;
END;
$;

CREATE POLICY doubt_requests_participants_read
  ON public.doubt_requests FOR SELECT TO authenticated
  USING (
    student_id = auth.uid()
    OR assigned_mentor_id = auth.uid()
    OR public.tc_is_school_admin(school_id)
  );

CREATE POLICY doubt_status_history_participants_read
  ON public.doubt_status_history FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.doubt_requests d
      WHERE d.id = request_id
        AND (
          d.student_id = auth.uid()
          OR d.assigned_mentor_id = auth.uid()
          OR public.tc_is_school_admin(d.school_id)
        )
    )
  );

CREATE POLICY ratings_participants_read
  ON public.ratings FOR SELECT TO authenticated
  USING (
    student_id = auth.uid()
    OR mentor_id = auth.uid()
    OR public.tc_is_school_admin(school_id)
  );

-- Mentor private notes are not visible to students.
CREATE POLICY mentor_assessments_mentor_admin_read
  ON public.mentor_assessments FOR SELECT TO authenticated
  USING (
    mentor_id = auth.uid()
    OR public.tc_is_school_admin(school_id)
  );

CREATE POLICY mentor_availability_school_read
  ON public.mentor_availability FOR SELECT TO authenticated
  USING (school_id = ANY(public.tc_user_school_ids()));

CREATE POLICY mentor_subject_approvals_school_read
  ON public.mentor_subject_approvals FOR SELECT TO authenticated
  USING (
    public.tc_is_school_admin(school_id)
    OR (
      school_id = ANY(public.tc_user_school_ids())
      AND status = 'approved'
    )
    OR EXISTS (
      SELECT 1 FROM public.teachers t
      WHERE t.id = teacher_id AND t.user_id = auth.uid()
    )
  );

CREATE POLICY allowance_transactions_student_admin_read
  ON public.allowance_transactions FOR SELECT TO authenticated
  USING (
    student_id = auth.uid()
    OR public.tc_is_school_admin(school_id)
  );

CREATE POLICY urgent_pass_usage_student_admin_read
  ON public.urgent_pass_usage FOR SELECT TO authenticated
  USING (
    student_id = auth.uid()
    OR public.tc_is_school_admin(school_id)
  );

CREATE POLICY session_no_shows_participant_admin_read
  ON public.session_no_shows FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.session_bookings b
      WHERE b.id = booking_id
        AND (
          b.student_id = auth.uid()
          OR b.mentor_id = auth.uid()
          OR public.tc_is_school_admin(b.school_id)
        )
    )
  );

CREATE POLICY mentor_desk_settings_school_read
  ON public.mentor_desk_settings FOR SELECT TO authenticated
  USING (school_id = ANY(public.tc_user_school_ids()));

CREATE POLICY mentor_desk_settings_admin_write
  ON public.mentor_desk_settings FOR ALL TO authenticated
  USING (public.tc_is_school_admin(school_id))
  WITH CHECK (public.tc_is_school_admin(school_id));

GRANT SELECT ON public.doubt_requests,
  public.doubt_status_history,
  public.ratings,
  public.mentor_assessments,
  public.mentor_availability,
  public.mentor_subject_approvals,
  public.allowance_transactions,
  public.urgent_pass_usage,
  public.session_no_shows
TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE
  ON public.mentor_desk_settings TO authenticated;

-- Client RPC allowlist for the Mentor Desk API.
DO $$
DECLARE
  v_signature text;
  v_function regprocedure;
BEGIN
  FOREACH v_signature IN ARRAY ARRAY[
    'public.submit_doubt(uuid,text,text,text,text,text,boolean,text,uuid[],uuid)',
    'public.claim_doubt(uuid)',
    'public.reply_doubt(uuid,text,uuid)',
    'public.resolve_doubt(uuid)',
    'public.close_doubt(uuid,text)',
    'public.reopen_doubt(uuid)',
    'public.book_session(uuid,uuid,integer,timestamp with time zone,text,text,uuid[])',
    'public.confirm_session(uuid,timestamp with time zone,integer,text,text)',
    'public.cancel_session(uuid,uuid)',
    'public.start_teacher_session(uuid)',
    'public.generate_verification_code(uuid)',
    'public.verify_session_code(uuid,text)',
    'public.close_session_without_code(uuid,text)',
    'public.record_no_show(uuid,text,text)',
    'public.set_mentor_availability(public.availability_status)',
    'public.approve_mentor_subject(uuid,uuid,boolean)',
    'public.submit_rating(uuid,integer,text)',
    'public.submit_mentor_assessment(uuid,public.engagement_scale,public.engagement_scale,text)',
    'public.get_student_learning_allowances()',
    'public.student_learning_context()'
  ] LOOP
    v_function := to_regprocedure(v_signature);
    IF v_function IS NOT NULL THEN
      EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', v_function);
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', v_function);
    END IF;
  END LOOP;
END;
$$;
