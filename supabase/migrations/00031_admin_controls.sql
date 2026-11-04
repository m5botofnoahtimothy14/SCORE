-- 00031_admin_controls.sql
-- Admin-facing RPCs for session allowance refunds ("Give Time Back") and
-- roll-number release. Idempotent and audited. SECURITY DEFINER so the
-- browser client cannot bypass the guards.

-- ============================================================
-- RPC: refund_session_allowance — idempotent "Give Time Back"
-- ============================================================
CREATE OR REPLACE FUNCTION public.refund_session_allowance(
  p_booking_id UUID,
  p_reason     TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid     UUID := auth.uid();
  v_booking session_bookings%ROWTYPE;
  v_week    DATE;
  v_role    TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO v_booking FROM session_bookings WHERE id = p_booking_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'booking_not_found');
  END IF;

  -- Caller must be an active admin in the booking's school.
  SELECT role INTO v_role
  FROM school_memberships
  WHERE user_id = v_uid AND school_id = v_booking.school_id AND is_active = TRUE
  LIMIT 1;
  IF v_role IS NULL OR v_role NOT IN ('platform_owner','school_admin','principal') THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authorized');
  END IF;

  IF v_booking.refunded THEN
    RETURN jsonb_build_object('success', TRUE, 'booking_id', p_booking_id, 'refunded', TRUE, 'idempotent', TRUE);
  END IF;

  IF COALESCE(v_booking.allowance_minutes_used, 0) <= 0 THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'nothing_to_refund');
  END IF;

  v_week := date_trunc('week', v_booking.requested_at)::DATE;

  UPDATE session_bookings
  SET refunded = TRUE, updated_at = NOW()
  WHERE id = p_booking_id AND refunded = FALSE;

  IF NOT FOUND THEN
    -- Race: another call refunded first.
    RETURN jsonb_build_object('success', TRUE, 'booking_id', p_booking_id, 'refunded', TRUE, 'idempotent', TRUE);
  END IF;

  INSERT INTO allowance_transactions(
    school_id, student_id, subject_id, booking_id, week_start,
    action, minutes, reason, created_at
  )
  VALUES (
    v_booking.school_id, v_booking.student_id, v_booking.subject_id,
    p_booking_id, v_week, 'refund', v_booking.allowance_minutes_used,
    COALESCE(p_reason, 'admin_refund'), NOW()
  );

  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome, metadata)
  VALUES (v_booking.school_id, v_uid, 'session.refund', 'session_booking', p_booking_id::TEXT, 'success',
          jsonb_build_object('reason', p_reason, 'minutes', v_booking.allowance_minutes_used));

  RETURN jsonb_build_object('success', TRUE, 'booking_id', p_booking_id, 'refunded', TRUE, 'minutes', v_booking.allowance_minutes_used);
END;
$$;

GRANT EXECUTE ON FUNCTION public.refund_session_allowance(UUID, TEXT) TO authenticated;

-- ============================================================
-- RPC: release_student_roll_number — dissociate a roll number
-- ============================================================
CREATE OR REPLACE FUNCTION public.release_student_roll_number(
  p_student_id UUID,
  p_reason     TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid     UUID := auth.uid();
  v_student students%ROWTYPE;
  v_role    TEXT;
  v_new_no  TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO v_student FROM students WHERE id = p_student_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'student_not_found');
  END IF;

  SELECT role INTO v_role
  FROM school_memberships
  WHERE user_id = v_uid AND school_id = v_student.school_id AND is_active = TRUE
  LIMIT 1;
  IF v_role IS NULL OR v_role NOT IN ('platform_owner','school_admin','principal') THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'not_authorized');
  END IF;

  -- Free the roll number while preserving history by suffixing the released record.
  v_new_no := v_student.student_id_no || '__released__' || to_char(NOW(), 'YYYYMMDDHH24MISS');

  UPDATE students
  SET user_id = NULL,
      is_active = FALSE,
      student_id_no = v_new_no,
      updated_at = NOW()
  WHERE id = p_student_id;

  INSERT INTO audit_events(school_id, actor_id, action, target_type, target_id, outcome, metadata)
  VALUES (v_student.school_id, v_uid, 'student.roll_number.release', 'student', p_student_id::TEXT, 'success',
          jsonb_build_object('reason', p_reason, 'original_no', v_student.student_id_no));

  RETURN jsonb_build_object('success', TRUE, 'student_id', p_student_id, 'released', TRUE);
END;
$$;

GRANT EXECUTE ON FUNCTION public.release_student_roll_number(UUID, TEXT) TO authenticated;