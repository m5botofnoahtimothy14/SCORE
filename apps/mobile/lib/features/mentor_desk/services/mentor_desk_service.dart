// Mentor Desk service — talks to Supabase RPCs (server-enforced authorization)
// and tables (RLS). Every mutation goes through a SECURITY DEFINER RPC.
// Updated for migration 00024 (class-based assignments, OTP verification) +
// migration 00025 (Google Meet calendar scheduling).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/models.dart';
import '../models/mentor_desk_models.dart';

class MentorDeskException implements Exception {
  final String code;
  final String message;
  const MentorDeskException(this.code, this.message);
  @override
  String toString() => message;
}

class MentorDeskService {
  MentorDeskService(this._client);
  final SupabaseClient _client;
  final _uuid = const Uuid();

  SupabaseClient get client => _client;

  String get _userId => _client.auth.currentUser!.id;

  // =========================================================================
  // Settings
  // =========================================================================
  Future<MentorDeskSettings?> getSettings(String schoolId) async {
    final row = await _client
        .from('mentor_desk_settings')
        .select()
        .eq('school_id', schoolId)
        .maybeSingle();
    if (row == null) return null;
    return MentorDeskSettings.fromJson(Map<String, dynamic>.from(row));
  }

  Future<GoogleMeetConfig?> getGoogleMeetConfig(String schoolId) async {
    final row = await _client
        .from('google_meet_config')
        .select()
        .eq('school_id', schoolId)
        .maybeSingle();
    if (row == null) return null;
    return GoogleMeetConfig.fromJson(Map<String, dynamic>.from(row));
  }

  // =========================================================================
  // Subjects (centrally configured list for this school)
  // =========================================================================
  Future<List<SubjectWithName>> listSubjects(String schoolId) async {
    final rows = await _client
        .from('subjects')
        .select('id, name, code')
        .eq('school_id', schoolId)
        .order('name');
    return (rows as List)
        .map((r) => SubjectWithName.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  // =========================================================================
  // Allowance summary per subject (student view)
  // =========================================================================
  Future<List<AllowanceSummary>> allowanceSummary({
    required String schoolId,
    required String studentId,
  }) async {
    final data = await _client.rpc('get_student_learning_allowances');
    final payload = Map<String, dynamic>.from(data as Map);
    final limit = (payload['doubt_allowance'] as num?)?.toInt() ?? 3;
    final rows = (payload['subjects'] as List? ?? const []);
    return rows.map((value) {
      final row = Map<String, dynamic>.from(value as Map);
      final used = (row['used'] as num?)?.toInt() ?? 0;
      return AllowanceSummary(
        subjectId: row['subject_id'] as String,
        subjectName: row['subject_name'] as String? ?? 'Subject',
        allowanceMinutes: limit,
        usedMinutes: used,
        remainingMinutes: (limit - used).clamp(0, limit),
        openDoubts: (row['open_doubts'] as num?)?.toInt() ?? 0,
        urgentPassAvailable: row['urgent_available'] == true,
        sessionAllowanceMinutes: (payload['session_allowance_minutes'] as num?)?.toInt() ?? 60,
        sessionUsedMinutes: (payload['session_used_minutes'] as num?)?.toInt() ?? 0,
        sessionRemainingMinutes: (payload['session_remaining_minutes'] as num?)?.toInt() ?? 0,
        nextResetAt: DateTime.tryParse(payload['next_reset_at'] as String? ?? ''),
      );
    }).toList();
  }

  DateTime _weekStart(DateTime d) {
    final iso = d.toUtc();
    final dow = iso.weekday; // 1=Mon .. 7=Sun
    return DateTime.utc(iso.year, iso.month, iso.day).subtract(Duration(days: dow - 1));
  }

  // =========================================================================
  // Student doubt requests
  // =========================================================================
  Future<List<DoubtRequest>> listDoubtRequests({
    required String schoolId,
    required String studentId,
  }) async {
    final rows = await _client
        .from('doubt_requests')
        .select()
        .eq('student_id', studentId)
        .order('updated_at', ascending: false);
    return (rows as List)
        .map((r) => DoubtRequest.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<DoubtRequest?> getDoubtRequest(String requestId) async {
    final row = await _client
        .from('doubt_requests')
        .select()
        .eq('id', requestId)
        .maybeSingle();
    if (row == null) return null;
    return DoubtRequest.fromJson(Map<String, dynamic>.from(row));
  }

  // =========================================================================
  // Submit a doubt (RPC: submit_doubt) — migration 00024 signature
  // p_attachment_ids are attachment rows already uploaded (pending_scan), owned by the student
  // =========================================================================
  Future<DoubtRequest> submitDoubt({
    required String subjectId,
    required String question,
    String? idempotencyKey,
    String? chapter,
    String? questionNumber,
    String? explanation,
    String? previousAttempts,
    bool urgent = false,
    String? urgentReason,
    List<String> attachmentIds = const [],
  }) async {
    final res = await _client.rpc('submit_doubt', params: {
      'p_subject_id': subjectId,
      'p_question': question,
      if (idempotencyKey != null) 'p_idempotency_key': idempotencyKey,
      if (chapter != null) 'p_chapter': chapter,
      if (questionNumber != null) 'p_question_number': questionNumber,
      if (explanation != null) 'p_explanation': explanation,
      if (previousAttempts != null) 'p_previous_attempts': previousAttempts,
      'p_urgent': urgent,
      if (urgentReason != null) 'p_urgent_reason': urgentReason,
      'p_attachment_ids': attachmentIds,
    });
    final data = Map<String, dynamic>.from(res as Map);
    if (data['success'] != true) {
      throw MentorDeskException(
        data['error']?.toString() ?? 'submit_failed',
        _submitErrorMessage(data['error']?.toString()),
      );
    }
    final reqId = data['request_id'] as String;
    final req = await getDoubtRequest(reqId);
    if (req == null) throw const MentorDeskException('not_found', 'Doubt created but could not be reloaded.');
    return req;
  }

  String _submitErrorMessage(String? code) {
    switch (code) {
      case 'not_authenticated': return 'Please sign in again.';
      case 'student_not_found': return 'Student record not found.';
      case 'unsupported_class': return 'Your class is not supported for Mentor Desk.';
      case 'settings_not_configured': return 'Mentor Desk is not configured for your school.';
      case 'invalid_subject': return 'Invalid subject.';
      case 'subject_not_enrolled': return 'You are not enrolled in this subject. Ask your school to update your subject assignment.';
      case 'weekly_quota_reached': return 'You have used this subject\'s weekly doubt allowance. Your allowance resets at the configured week boundary.';
      case 'too_many_attachments': return 'You can attach up to 4 images.';
      case 'invalid_question': return 'Please enter a valid question.';
      case 'urgent_reason_required': return 'A reason is required for an urgent request.';
      case 'urgent_pass_used': return 'You have already used your urgent pass for this subject this week.';
      default: return 'Could not submit the doubt. Please try again.';
    }
  }

  // =========================================================================
  // Claim a doubt (mentor RPC: claim_doubt) — migration 00024
  // =========================================================================
  Future<void> claimDoubt(String requestId) async {
    final res = await _client.rpc('claim_doubt', params: {'p_request_id': requestId});
    final data = Map<String, dynamic>.from(res as Map);
    if (data['success'] != true) {
      throw MentorDeskException(
        data['error']?.toString() ?? 'claim_failed',
        _claimErrorMessage(data['error']?.toString()),
      );
    }
  }

  String _claimErrorMessage(String? code) {
    switch (code) {
      case 'not_authenticated': return 'Please sign in again.';
      case 'not_a_teacher': return 'Only teachers can claim requests.';
      case 'not_assigned_for_class_subject': return 'You are not assigned to this class and subject.';
      case 'request_not_found': return 'Request not found.';
      case 'request_not_waiting': return 'This request is no longer waiting.';
      default: return 'Could not claim the request. Please try again.';
    }
  }

  // =========================================================================
  // Reply to a doubt (RPC: reply_doubt) — migration 00024
  // =========================================================================
  Future<void> replyDoubt({
    required String requestId,
    required String body,
    String? attachmentId,
  }) async {
    final res = await _client.rpc('reply_doubt', params: {
      'p_request_id': requestId,
      'p_body': body,
      if (attachmentId != null) 'p_attachment_id': attachmentId,
    });
    final data = Map<String, dynamic>.from(res as Map);
    if (data['success'] != true) {
      throw MentorDeskException(
        data['error']?.toString() ?? 'reply_failed',
        _replyErrorMessage(data['error']?.toString()),
      );
    }
  }

  String _replyErrorMessage(String? code) {
    switch (code) {
      case 'not_authenticated': return 'Please sign in again.';
      case 'not_authorized': return 'You are not part of this conversation.';
      case 'assignment_changed': return 'The assignment for this request has changed.';
      case 'request_not_found': return 'Request not found.';
      case 'doubt_not_open': return 'This request is no longer open.';
      default: return 'Could not send the reply. Please try again.';
    }
  }

  // =========================================================================
  // Resolve a doubt (mentor RPC: resolve_doubt) — migration 00024
  // =========================================================================
  Future<void> resolveDoubt(String requestId) async {
    final res = await _client.rpc('resolve_doubt', params: {'p_request_id': requestId});
    final data = Map<String, dynamic>.from(res as Map);
    if (data['success'] != true) {
      throw MentorDeskException(
        data['error']?.toString() ?? 'resolve_failed',
        _resolveErrorMessage(data['error']?.toString()),
      );
    }
  }

  String _resolveErrorMessage(String? code) {
    switch (code) {
      case 'not_authenticated': return 'Please sign in again.';
      case 'not_assigned_mentor': return 'Only the assigned mentor can resolve this.';
      case 'assignment_changed': return 'The assignment for this request has changed.';
      case 'invalid_transition': return 'This request cannot be resolved in its current state.';
      case 'request_not_found': return 'Request not found.';
      default: return 'Could not resolve the request.';
    }
  }

  // =========================================================================
  // Reopen a doubt (student RPC: reopen_doubt) — migration 00024
  // =========================================================================
  Future<void> reopenDoubt(String requestId) async {
    final res = await _client.rpc('reopen_doubt', params: {'p_request_id': requestId});
    final data = Map<String, dynamic>.from(res as Map);
    if (data['success'] != true) {
      throw MentorDeskException(
        data['error']?.toString() ?? 'reopen_failed',
        _reopenErrorMessage(data['error']?.toString()),
      );
    }
  }

  String _reopenErrorMessage(String? code) {
    switch (code) {
      case 'not_authenticated': return 'Please sign in again.';
      case 'not_the_student': return 'Only the student can reopen this request.';
      case 'invalid_transition': return 'This request cannot be reopened.';
      case 'request_not_found': return 'Request not found.';
      default: return 'Could not reopen the request.';
    }
  }

  // =========================================================================
  // Book a session (RPC: book_session) — migration 00024
  // Duration must be 15 or 30 minutes. Teacher auto-assigned when mentorId is null.
  // =========================================================================
  Future<SessionBooking> bookSession({
    required String subjectId,
    String? mentorId, // null = any available teacher for class+subject
    required int durationMinutes,
    required DateTime scheduledAt,
    required String topic,
    String? preparation,
    List<String> attachmentIds = const [],
  }) async {
    if (durationMinutes != 15 && durationMinutes != 30) {
      throw const MentorDeskException('invalid_duration', 'Session length must be 15 or 30 minutes.');
    }
    final res = await _client.rpc('book_session', params: {
      'p_subject_id': subjectId,
      if (mentorId != null) 'p_mentor_id': mentorId,
      'p_duration_minutes': durationMinutes,
      'p_scheduled_at': scheduledAt.toUtc().toIso8601String(),
      'p_topic': topic,
      if (preparation != null) 'p_preparation': preparation,
      'p_attachment_ids': attachmentIds,
    });
    final data = Map<String, dynamic>.from(res as Map);
    if (data['success'] != true) {
      throw MentorDeskException(
        data['error']?.toString() ?? 'book_failed',
        _bookErrorMessage(data['error']?.toString()),
      );
    }
    final bookingId = data['booking_id'] as String;
    final booking = await getSessionBooking(bookingId);
    if (booking == null) throw const MentorDeskException('not_found', 'Booking created but could not be reloaded.');
    return booking;
  }

  String _bookErrorMessage(String? code) {
    switch (code) {
      case 'not_authenticated': return 'Please sign in again.';
      case 'student_not_found': return 'Student record not found.';
      case 'unsupported_class': return 'Your class is not supported for Mentor Desk.';
      case 'settings_not_configured': return 'Mentor Desk is not configured for your school.';
      case 'invalid_subject': return 'Invalid subject.';
      case 'subject_not_enrolled': return 'You are not enrolled in this subject.';
      case 'invalid_duration': return 'Invalid session length (15 or 30 minutes).';
      case 'invalid_booking': return 'Invalid booking details.';
      case 'mentor_not_approved': return 'Mentor is not approved for this subject.';
      case 'no_authorized_teacher': return 'No authorized teacher available for this subject.';
      case 'allowance_exceeded': return 'This session exceeds your remaining weekly allowance.';
      default: return 'Could not book the session. Please try again.';
    }
  }

  // =========================================================================
  // Session bookings
  // =========================================================================
  Future<List<SessionBooking>> listSessionBookings({
    required String studentId,
  }) async {
    final rows = await _client
        .from('session_bookings')
        .select()
        .eq('student_id', studentId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => SessionBooking.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<List<SessionBooking>> listMentorSessionBookings({
    required String mentorId,
  }) async {
    final rows = await _client
        .from('session_bookings')
        .select()
        .eq('mentor_id', mentorId)
        .order('scheduled_at', ascending: true, nullsFirst: false);
    return (rows as List)
        .map((r) => SessionBooking.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<SessionBooking?> getSessionBooking(String bookingId) async {
    final row = await _client
        .from('session_bookings')
        .select()
        .eq('id', bookingId)
        .maybeSingle();
    if (row == null) return null;
    return SessionBooking.fromJson(Map<String, dynamic>.from(row));
  }

  // =========================================================================
  // Start a teacher/session (RPC: start_teacher_session) — migration 00024
  // Student explicitly starts a confirmed meeting before OTP is issued.
  // =========================================================================
  Future<void> startTeacherSession(String bookingId) async {
    final res = await _client.rpc('start_teacher_session', params: {'p_booking_id': bookingId});
    final data = Map<String, dynamic>.from(res as Map);
    if (data['success'] != true) {
      throw MentorDeskException(
        data['error']?.toString() ?? 'start_failed',
        _startErrorMessage(data['error']?.toString()),
      );
    }
  }

  String _startErrorMessage(String? code) {
    switch (code) {
      case 'not_authenticated': return 'Please sign in again.';
      case 'not_a_participant': return 'Only a participant can start this session.';
      case 'booking_not_found': return 'Booking not found.';
      case 'booking_not_confirmed': return 'The session is not confirmed.';
      default: return 'Could not start the session.';
    }
  }

  // =========================================================================
  // Confirm a session (mentor RPC: confirm_session) — migration 00024
  // Duration must equal the reserved (booked) duration.
  // =========================================================================
  Future<void> confirmSession({
    required String bookingId,
    required DateTime scheduledAt,
    required int durationMinutes,
    String? meetingLink,
    String? meetingRoom,
  }) async {
    final res = await _client.rpc('confirm_session', params: {
      'p_booking_id': bookingId,
      'p_scheduled_at': scheduledAt.toUtc().toIso8601String(),
      'p_duration_minutes': durationMinutes,
      if (meetingLink != null) 'p_meeting_link': meetingLink,
      if (meetingRoom != null) 'p_meeting_room': meetingRoom,
    });
    final data = Map<String, dynamic>.from(res as Map);
    if (data['success'] != true) {
      throw MentorDeskException(
        data['error']?.toString() ?? 'confirm_failed',
        _confirmErrorMessage(data['error']?.toString()),
      );
    }
  }

  String _confirmErrorMessage(String? code) {
    switch (code) {
      case 'not_authenticated': return 'Please sign in again.';
      case 'not_the_mentor': return 'Only the assigned mentor can confirm.';
      case 'booking_not_found': return 'Booking not found.';
      case 'booking_not_requested': return 'This booking cannot be confirmed.';
      case 'invalid_duration': return 'Duration must match the booked length.';
      case 'assignment_changed': return 'The assignment for this booking has changed.';
      default: return 'Could not confirm the session.';
    }
  }

  // =========================================================================
  // Cancel a session (RPC: cancel_session) — migration 00024
  // Refunds allowance; cannot cancel once started.
  // =========================================================================
  Future<void> cancelSession({required String bookingId, String? cancelledBy}) async {
    final res = await _client.rpc('cancel_session', params: {
      'p_booking_id': bookingId,
      if (cancelledBy != null) 'p_cancelled_by': cancelledBy,
    });
    final data = Map<String, dynamic>.from(res as Map);
    if (data['success'] != true) {
      throw MentorDeskException(
        data['error']?.toString() ?? 'cancel_failed',
        _cancelErrorMessage(data['error']?.toString()),
      );
    }
  }

  String _cancelErrorMessage(String? code) {
    switch (code) {
      case 'not_authenticated': return 'Please sign in again.';
      case 'not_a_participant': return 'Only a participant can cancel.';
      case 'booking_not_found': return 'Booking not found.';
      case 'booking_not_cancellable': return 'This session cannot be cancelled.';
      default: return 'Could not cancel the session.';
    }
  }

  // =========================================================================
  // Verification code (student RPC: generate_verification_code) — migration 00024
  // Requires the session to be started first. Returns a hashed OTP code.
  // =========================================================================
  Future<Map<String, dynamic>> generateVerificationCode(String bookingId) async {
    final res = await _client.rpc('generate_verification_code', params: {'p_booking_id': bookingId});
    final data = Map<String, dynamic>.from(res as Map);
    if (data['success'] != true) {
      throw MentorDeskException(
        data['error']?.toString() ?? 'code_failed',
        _codeErrorMessage(data['error']?.toString()),
      );
    }
    return data;
  }

  String _codeErrorMessage(String? code) {
    switch (code) {
      case 'not_authenticated': return 'Please sign in again.';
      case 'not_the_student': return 'Only the student can view the code.';
      case 'booking_not_found': return 'Booking not found.';
      case 'session_not_started': return 'The session must be started before a code can be issued.';
      case 'code_already_issued': return 'A code has already been issued for this session.';
      case 'resend_limit_reached': return 'Resend limit reached for this session.';
      default: return 'Could not get the verification code.';
    }
  }

  // =========================================================================
  // Verify session code (mentor RPC: verify_session_code) — migration 00024
  // Mentor enters the student's OTP code (hashed server-side).
  // =========================================================================
  Future<void> verifySessionCode({required String bookingId, required String code}) async {
    final res = await _client.rpc('verify_session_code', params: {
      'p_booking_id': bookingId,
      'p_code': code,
    });
    final data = Map<String, dynamic>.from(res as Map);
    if (data['success'] != true) {
      throw MentorDeskException(
        data['error']?.toString() ?? 'verify_failed',
        _verifyErrorMessage(data['error']?.toString()),
      );
    }
  }

  String _verifyErrorMessage(String? code) {
    switch (code) {
      case 'not_authenticated': return 'Please sign in again.';
      case 'not_the_mentor': return 'Only the mentor can verify.';
      case 'booking_not_found': return 'Booking not found.';
      case 'booking_not_confirmed': return 'The session is not confirmed.';
      case 'session_not_started': return 'The session has not been started.';
      case 'no_code': return 'No verification code has been issued.';
      case 'code_locked': return 'Too many incorrect attempts — code entry is locked.';
      case 'code_expired': return 'The verification code has expired.';
      case 'incorrect_code': return 'Incorrect verification code.';
      default: return 'Verification failed. Please try again.';
    }
  }

  // =========================================================================
  // Close session without code — migration 00024 (admin only)
  // =========================================================================
  Future<void> closeSessionWithoutCode({required String bookingId, required String reason}) async {
    final res = await _client.rpc('close_session_without_code', params: {
      'p_booking_id': bookingId,
      'p_reason': reason,
    });
    final data = Map<String, dynamic>.from(res as Map);
    if (data['success'] != true) {
      throw MentorDeskException(
        data['error']?.toString() ?? 'close_failed',
        _closeErrorMessage(data['error']?.toString()),
      );
    }
  }

  String _closeErrorMessage(String? code) {
    switch (code) {
      case 'not_authenticated': return 'Please sign in again.';
      case 'forbidden': return 'Only school administrators can close sessions without a code.';
      case 'booking_not_found': return 'Booking not found.';
      case 'invalid_exception': return 'Invalid closure request.';
      default: return 'Could not close the session.';
    }
  }

  // =========================================================================
  // Record no-show (RPC: record_no_show)
  // =========================================================================
  Future<Map<String, dynamic>> recordNoShow({
    required String bookingId,
    required String reportedByRole, // 'student' | 'mentor'
    String? reason,
  }) async {
    final res = await _client.rpc('record_no_show', params: {
      'p_booking_id': bookingId,
      'p_reported_by_role': reportedByRole,
      if (reason != null) 'p_reason': reason,
    });
    final data = Map<String, dynamic>.from(res as Map);
    if (data['success'] != true) {
      throw MentorDeskException(
        data['error']?.toString() ?? 'no_show_failed',
        _noShowErrorMessage(data['error']?.toString()),
      );
    }
    return data;
  }

  String _noShowErrorMessage(String? code) {
    switch (code) {
      case 'not_authenticated': return 'Please sign in again.';
      case 'not_a_participant': return 'Only a participant can report a no-show.';
      case 'booking_not_found': return 'Booking not found.';
      case 'already_resolved': return 'This session has already been resolved.';
      default: return 'Could not record the no-show.';
    }
  }

  // =========================================================================
  // Submit rating (student RPC: submit_rating)
  // =========================================================================
  Future<void> submitRating({
    required String requestId,
    required int rating, // 1-5
    String? comment,
  }) async {
    final res = await _client.rpc('submit_rating', params: {
      'p_request_id': requestId,
      'p_rating': rating,
      if (comment != null) 'p_comment': comment,
    });
    final data = Map<String, dynamic>.from(res as Map);
    if (data['success'] != true) {
      throw MentorDeskException(
        data['error']?.toString() ?? 'rating_failed',
        _ratingErrorMessage(data['error']?.toString()),
      );
    }
  }

  String _ratingErrorMessage(String? code) {
    switch (code) {
      case 'not_authenticated': return 'Please sign in again.';
      case 'invalid_rating': return 'Rating must be between 1 and 5.';
      case 'request_not_found': return 'Request not found.';
      case 'not_the_student': return 'Only the student can rate.';
      case 'request_not_closed': return 'You can only rate a closed request.';
      default: return 'Could not submit the rating.';
    }
  }

  // =========================================================================
  // Ratings
  // =========================================================================
  Future<List<Rating>> listRatingsForRequest(String requestId) async {
    final rows = await _client
        .from('ratings')
        .select()
        .eq('request_id', requestId);
    return (rows as List)
        .map((r) => Rating.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  // =========================================================================
  // Submit mentor assessment (mentor RPC: submit_mentor_assessment)
  // =========================================================================
  Future<void> submitMentorAssessment({
    required String requestId,
    required String preparation, // engagement_scale enum
    required String engagement,
    String? privateNote,
  }) async {
    final res = await _client.rpc('submit_mentor_assessment', params: {
      'p_request_id': requestId,
      'p_preparation': preparation,
      'p_engagement': engagement,
      if (privateNote != null) 'p_private_note': privateNote,
    });
    final data = Map<String, dynamic>.from(res as Map);
    if (data['success'] != true) {
      throw MentorDeskException(
        data['error']?.toString() ?? 'assessment_failed',
        _assessmentErrorMessage(data['error']?.toString()),
      );
    }
  }

  String _assessmentErrorMessage(String? code) {
    switch (code) {
      case 'not_authenticated': return 'Please sign in again.';
      case 'not_assigned_mentor': return 'Only the assigned mentor can assess.';
      case 'request_not_found': return 'Request not found.';
      case 'request_not_closed': return 'You can only assess a closed request.';
      default: return 'Could not submit the assessment.';
    }
  }

  Future<MentorAssessment?> getMentorAssessment(String requestId, String mentorId) async {
    final row = await _client
        .from('mentor_assessments')
        .select()
        .eq('request_id', requestId)
        .eq('mentor_id', mentorId)
        .maybeSingle();
    if (row == null) return null;
    return MentorAssessment.fromJson(Map<String, dynamic>.from(row));
  }

  // =========================================================================
  // Mentor availability
  // =========================================================================
  Future<void> setAvailability(String status) async {
    await _client.rpc('set_mentor_availability', params: {'p_status': status});
  }

  Future<List<MentorAvailability>> listAvailability(String schoolId) async {
    final rows = await _client
        .from('mentor_availability')
        .select()
        .eq('school_id', schoolId);
    return (rows as List)
        .map((r) => MentorAvailability.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  // =========================================================================
  // Mentor subject approvals (mentor view: which subjects am I approved for)
  // =========================================================================
  Future<List<MentorSubjectApproval>> listMyApprovals(String teacherId) async {
    final rows = await _client
        .from('mentor_subject_approvals')
        .select()
        .eq('teacher_id', teacherId);
    return (rows as List)
        .map((r) => MentorSubjectApproval.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  // =========================================================================
  // Attachments: upload an image (private, pending_scan) -> returns attachment row id
  // Up to 4 images per submission.
  // =========================================================================
  static const int maxAttachments = 4;
  static const int maxBytes = 10 * 1024 * 1024;
  static const Set<String> imageMime = {'image/jpeg', 'image/png', 'image/webp', 'image/gif'};

  Future<List<String>> uploadImages({
    required String schoolId,
    required String conversationId,
    required List<File> files,
  }) async {
    if (files.length > maxAttachments) {
      throw const MentorDeskException('too_many_files', 'You can attach up to $maxAttachments images.');
    }
    final ids = <String>[];
    for (final f in files) {
      final bytes = await f.readAsBytes();
      if (bytes.length > maxBytes) {
        throw MentorDeskException('file_too_large', '${f.path.split('/').last} is too large (max 10 MB).');
      }
      final mime = _mime(f.path);
      if (!imageMime.contains(mime)) {
        throw MentorDeskException('unsupported_type', '${f.path.split('/').last} is not a supported image type.');
      }
      final storagePath = '$schoolId/$conversationId/mentor_desk/${_uuid.v4()}_${f.path.split('/').last}';
      await _client.storage.from('attachments').uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: false),
          );
      final row = await _client.from('attachments').insert({
        'message_id': null,
        'school_id': schoolId,
        'uploader_id': _userId,
        'type': 'image',
        'file_name': f.path.split('/').last,
        'mime_type': mime,
        'size_bytes': bytes.length,
        'storage_path': storagePath,
        'status': 'pending_scan',
      }).select().single();
      ids.add((row as Map)['id'] as String);
    }
    return ids;
  }

  /// Upload images from XFile (image_picker). Wrapper for compatibility.
  Future<List<String>> uploadXFiles({
    required String schoolId,
    required String conversationId,
    required List<XFile> files,
  }) async {
    final dartFiles = files.map((f) => File(f.path)).toList();
    return uploadImages(schoolId: schoolId, conversationId: conversationId, files: dartFiles);
  }

  String _mime(String path) {
    final n = path.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  Future<String> signedUrl(String storagePath) async {
    final res = await _client.storage.from('attachments').createSignedUrl(storagePath, 300);
    return res;
  }

  // =========================================================================
  // Google Meet calendar scheduling (migration 00025)
  // =========================================================================
  /// Requests (or returns existing) Google Meet link for a confirmed booking.
  /// Calls the create-google-meet edge function which talks to Google Calendar API.
  Future<Map<String, dynamic>> createGoogleMeet(String bookingId) async {
    final res = await _client.functions.invoke('create-google-meet', body: {'booking_id': bookingId});
    final data = Map<String, dynamic>.from(res.data as Map? ?? {});
    if (data['success'] != true) {
      throw MentorDeskException(
        data['error']?.toString() ?? 'google_meet_failed',
        _googleMeetErrorMessage(data['error']?.toString()),
      );
    }
    return data;
  }

  /// Read-only fetch of the stored Google Meet link for a booking.
  Future<Map<String, dynamic>> getGoogleMeetLink(String bookingId) async {
    final res = await _client.rpc('get_google_meet_link', params: {'p_booking_id': bookingId});
    final data = Map<String, dynamic>.from(res as Map);
    if (data['success'] != true) {
      throw MentorDeskException(
        data['error']?.toString() ?? 'google_meet_fetch_failed',
        _googleMeetErrorMessage(data['error']?.toString()),
      );
    }
    return data;
  }

  String _googleMeetErrorMessage(String? code) {
    switch (code) {
      case 'not_authenticated': return 'Please sign in again.';
      case 'not_a_participant': return 'Only a participant can access the meeting link.';
      case 'booking_not_found': return 'Booking not found.';
      case 'booking_not_confirmed': return 'The session is not confirmed.';
      case 'google_meet_not_configured': return 'Google Meet is not configured for your school.';
      case 'google_credentials_not_configured': return 'Google Calendar credentials are not configured.';
      case 'google_calendar_api_failed': return 'Google Calendar API request failed.';
      case 'google_meet_link_not_created': return 'Could not create a Google Meet link.';
      case 'db_update_failed': return 'Could not save the meeting link.';
      default: return 'Could not create the Google Meet link. Please try again.';
    }
  }

  /// Launch the Google Meet link in the system browser.
  static Future<bool> openMeetLink(String? meetLink) async {
    if (meetLink == null || meetLink.isEmpty) return false;
    final uri = Uri.parse(meetLink);
    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }
}
