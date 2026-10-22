// Mentor Desk service — talks to Supabase RPCs (server-enforced authorization)
// and tables (RLS). Every mutation goes through a SECURITY DEFINER RPC.
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

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
    final settings = await getSettings(schoolId);
    if (settings == null) return [];

    final subjects = await listSubjects(schoolId);
    final weekStart = _weekStart(DateTime.now());

    final summaries = <AllowanceSummary>[];
    for (final sub in subjects) {
      final usedRows = await _client
          .from('session_bookings')
          .select('allowance_minutes_used')
          .eq('student_id', studentId)
          .eq('subject_id', sub.id)
          .inFilter('status', ['confirmed', 'completed'])
          .gte('created_at', weekStart.toIso8601String());
      int used = 0;
      for (final r in (usedRows as List)) {
        used += ((r as Map)['allowance_minutes_used'] as num?)?.toInt() ?? 0;
      }

      final doubtRows = await _client
          .from('doubt_requests')
          .select('id')
          .eq('student_id', studentId)
          .eq('subject_id', sub.id)
          .inFilter('status', ['waiting', 'assigned']);
      final openDoubts = (doubtRows as List).length;

      final urgentRows = await _client
          .from('urgent_pass_usage')
          .select('id')
          .eq('student_id', studentId)
          .eq('subject_id', sub.id)
          .eq('week_start', weekStart.toIso8601String());
      final urgentUsed = (urgentRows as List).isNotEmpty;

      summaries.add(AllowanceSummary(
        subjectId: sub.id,
        subjectName: sub.name,
        allowanceMinutes: settings.sessionAllowanceMinutes,
        usedMinutes: used,
        remainingMinutes: (settings.sessionAllowanceMinutes - used).clamp(0, settings.sessionAllowanceMinutes),
        openDoubts: openDoubts,
        urgentPassAvailable: settings.urgentPassesPerWeek > 0 && !urgentUsed,
      ));
    }
    return summaries;
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
  // Submit a doubt (RPC: submit_doubt)
  // p_attachment_ids are attachment rows already uploaded (pending_scan), owned by the student
  // =========================================================================
  Future<DoubtRequest> submitDoubt({
    required String subjectId,
    required String question,
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
    if (req == null) throw MentorDeskException('not_found', 'Doubt created but could not be reloaded.');
    return req;
  }

  String _submitErrorMessage(String? code) {
    switch (code) {
      case 'not_authenticated': return 'Please sign in again.';
      case 'student_not_found': return 'Student record not found.';
      case 'settings_not_configured': return 'Mentor Desk is not configured for your school.';
      case 'invalid_subject': return 'Invalid subject.';
      case 'doubt_limit_reached': return 'You already have the maximum number of open doubts for this subject.';
      case 'urgent_reason_required': return 'A reason is required for an urgent request.';
      case 'urgent_pass_used': return 'You have already used your urgent pass for this subject this week.';
      default: return 'Could not submit the doubt. Please try again.';
    }
  }

  // =========================================================================
  // Claim a doubt (mentor RPC: claim_doubt)
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
      case 'not_approved_for_subject': return 'You are not approved for this subject.';
      case 'request_not_found': return 'Request not found.';
      case 'request_not_waiting': return 'This request is no longer waiting.';
      case 'named_mentor_only': return 'This request is assigned to a specific mentor.';
      case 'already_claimed': return 'Another mentor already claimed this request.';
      default: return 'Could not claim the request. Please try again.';
    }
  }

  // =========================================================================
  // Reply to a doubt (RPC: reply_doubt) — auto-assigns if waiting
  // p_attachmentId is an already-uploaded attachment row id
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
      case 'not_a_member': return 'You are not part of this conversation.';
      case 'request_not_found': return 'Request not found.';
      default: return 'Could not send the reply. Please try again.';
    }
  }

  // =========================================================================
  // Resolve a doubt (mentor RPC: resolve_doubt)
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
      case 'request_not_found': return 'Request not found.';
      case 'already_closed': return 'This request is already closed.';
      default: return 'Could not resolve the request.';
    }
  }

  // =========================================================================
  // Reopen a doubt (student RPC: reopen_doubt)
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
      case 'request_not_found': return 'Request not found.';
      default: return 'Could not reopen the request.';
    }
  }

  // =========================================================================
  // Book a session (RPC: book_session)
  // =========================================================================
  Future<SessionBooking> bookSession({
    required String subjectId,
    String? mentorId, // null = any available mentor
    required int durationMinutes,
    required DateTime scheduledAt,
    required String topic,
    String? preparation,
    List<String> attachmentIds = const [],
  }) async {
    final res = await _client.rpc('book_session', params: {
      'p_subject_id': subjectId,
      if (mentorId != null) 'p_mentor_id': mentorId,
      'p_duration_minutes': durationMinutes,
      'p_scheduled_at': scheduledAt.toIso8601String(),
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
    if (booking == null) throw MentorDeskException('not_found', 'Booking created but could not be reloaded.');
    return booking;
  }

  String _bookErrorMessage(String? code) {
    switch (code) {
      case 'not_authenticated': return 'Please sign in again.';
      case 'student_not_found': return 'Student record not found.';
      case 'settings_not_configured': return 'Mentor Desk is not configured for your school.';
      case 'invalid_subject': return 'Invalid subject.';
      case 'invalid_duration': return 'Invalid session length.';
      case 'mentor_not_found': return 'Mentor not found.';
      case 'mentor_not_approved': return 'Mentor is not approved for this subject.';
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
  // Confirm a session (mentor RPC: confirm_session)
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
      'p_scheduled_at': scheduledAt.toIso8601String(),
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
      default: return 'Could not confirm the session.';
    }
  }

  // =========================================================================
  // Cancel a session (RPC: cancel_session) — refunds allowance
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
      case 'booking_not_requested': return 'This booking cannot be cancelled.';
      default: return 'Could not cancel the session.';
    }
  }

  // =========================================================================
  // Verification code (student RPC: generate_verification_code)
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
      case 'booking_not_confirmed': return 'The session is not confirmed.';
      case 'code_not_yet_visible': return 'The code will be available 10 minutes before the session.';
      default: return 'Could not get the verification code.';
    }
  }

  // =========================================================================
  // Verify session code (mentor RPC: verify_session_code)
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
      case 'no_code': return 'No verification code has been issued.';
      case 'code_locked': return 'Too many incorrect attempts — code entry is locked.';
      case 'code_expired': return 'The verification code has expired.';
      case 'incorrect_code': return 'Incorrect verification code.';
      default: return 'Verification failed. Please try again.';
    }
  }

  // =========================================================================
  // Close session without code (mentor RPC: close_session_without_code)
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
      case 'not_the_mentor': return 'Only the mentor can close the session.';
      case 'booking_not_found': return 'Booking not found.';
      case 'booking_not_confirmed': return 'The session is not confirmed.';
      case 'reason_required': return 'A reason is required.';
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
    required List<XFile> files,
  }) async {
    if (files.length > maxAttachments) {
      throw MentorDeskException('too_many_files', 'You can attach up to $maxAttachments images.');
    }
    final ids = <String>[];
    for (final f in files) {
      final bytes = await f.readAsBytes();
      if (bytes.length > maxBytes) {
        throw MentorDeskException('file_too_large', '${f.name} is too large (max 10 MB).');
      }
      final mime = _mime(f.name);
      if (!imageMime.contains(mime)) {
        throw MentorDeskException('unsupported_type', '${f.name} is not a supported image type.');
      }
      final storagePath = '$schoolId/$conversationId/mentor_desk/${_uuid.v4()}_${f.name}';
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
        'file_name': f.name,
        'mime_type': mime,
        'size_bytes': bytes.length,
        'storage_path': storagePath,
        'status': 'pending_scan',
      }).select().single();
      ids.add((row as Map)['id'] as String);
    }
    return ids;
  }

  String _mime(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  Future<String> signedUrl(String storagePath) async {
    final res = await _client.storage.from('attachments').createSignedUrl(storagePath, 300);
    return res;
  }
}
