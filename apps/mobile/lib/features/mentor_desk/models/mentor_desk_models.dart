// Mentor Desk data models — mirrors the new DB schema (migration 00021).
// All parsing is null-safe.
class DoubtRequest {
  final String id;
  final String schoolId;
  final String conversationId;
  final String studentId;
  final String studentRecordId;
  final String subjectId;
  final String question;
  final String? chapter;
  final String? questionNumber;
  final String? explanation;
  final String? previousAttempts;
  final bool urgent;
  final String? urgentReason;
  final bool urgentPassUsed;
  final String status; // waiting | assigned | resolved | closed
  final String? assignedMentorId;
  final String? assignedTeacherId;
  final bool namedMentor;
  final DateTime? firstReplyAt;
  final DateTime? resolvedAt;
  final DateTime? closedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DoubtRequest({
    required this.id,
    required this.schoolId,
    required this.conversationId,
    required this.studentId,
    required this.studentRecordId,
    required this.subjectId,
    required this.question,
    this.chapter,
    this.questionNumber,
    this.explanation,
    this.previousAttempts,
    required this.urgent,
    this.urgentReason,
    required this.urgentPassUsed,
    required this.status,
    this.assignedMentorId,
    this.assignedTeacherId,
    required this.namedMentor,
    this.firstReplyAt,
    this.resolvedAt,
    this.closedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DoubtRequest.fromJson(Map<String, dynamic> j) => DoubtRequest(
        id: j['id'] as String,
        schoolId: j['school_id'] as String,
        conversationId: j['conversation_id'] as String,
        studentId: j['student_id'] as String,
        studentRecordId: j['student_record_id'] as String,
        subjectId: j['subject_id'] as String,
        question: j['question'] as String? ?? '',
        chapter: j['chapter'] as String?,
        questionNumber: j['question_number'] as String?,
        explanation: j['explanation'] as String?,
        previousAttempts: j['previous_attempts'] as String?,
        urgent: j['urgent'] as bool? ?? false,
        urgentReason: j['urgent_reason'] as String?,
        urgentPassUsed: j['urgent_pass_used'] as bool? ?? false,
        status: j['status'] as String? ?? 'waiting',
        assignedMentorId: j['assigned_mentor_id'] as String?,
        assignedTeacherId: j['assigned_teacher_id'] as String?,
        namedMentor: j['named_mentor'] as bool? ?? false,
        firstReplyAt: DateTime.tryParse(j['first_reply_at'] as String? ?? ''),
        resolvedAt: DateTime.tryParse(j['resolved_at'] as String? ?? ''),
        closedAt: DateTime.tryParse(j['closed_at'] as String? ?? ''),
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? '') ?? DateTime.now(),
      );

  bool get isOpen => status == 'waiting' || status == 'assigned';
  bool get isWaiting => status == 'waiting';
  bool get isAssigned => status == 'assigned';
  bool get isResolved => status == 'resolved';
  bool get isClosed => status == 'closed';

  String get statusLabel {
    switch (status) {
      case 'waiting': return 'Waiting for mentor';
      case 'assigned': return 'Assigned';
      case 'resolved': return 'Resolved';
      case 'closed': return 'Closed';
      default: return status;
    }
  }
}

class SessionBooking {
  final String id;
  final String schoolId;
  final String studentId;
  final String studentRecordId;
  final String mentorId;
  final String mentorRecordId;
  final String subjectId;
  final int durationMinutes;
  final String topic;
  final String? preparation;
  final DateTime requestedAt;
  final DateTime? scheduledAt;
  final DateTime? confirmedAt;
  final String? meetingLink;
  final String? meetingRoom;
  final String status; // requested | confirmed | cancelled_by_student | cancelled_by_mentor | completed | no_show_student | no_show_mentor | unverified_closed
  final int allowanceMinutesUsed;
  final DateTime? cancelledAt;
  final String? cancelledBy;
  final bool refunded;
  final String? verificationCode;
  final DateTime? codeExpiresAt;
  final int codeAttempts;
  final DateTime? codeLockedAt;
  final DateTime? codeVisibleAt;
  final DateTime? verifiedAt;
  final bool closedWithoutCode;
  final String? closeReason;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SessionBooking({
    required this.id,
    required this.schoolId,
    required this.studentId,
    required this.studentRecordId,
    required this.mentorId,
    required this.mentorRecordId,
    required this.subjectId,
    required this.durationMinutes,
    required this.topic,
    this.preparation,
    required this.requestedAt,
    this.scheduledAt,
    this.confirmedAt,
    this.meetingLink,
    this.meetingRoom,
    required this.status,
    required this.allowanceMinutesUsed,
    this.cancelledAt,
    this.cancelledBy,
    required this.refunded,
    this.verificationCode,
    this.codeExpiresAt,
    required this.codeAttempts,
    this.codeLockedAt,
    this.codeVisibleAt,
    this.verifiedAt,
    required this.closedWithoutCode,
    this.closeReason,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SessionBooking.fromJson(Map<String, dynamic> j) => SessionBooking(
        id: j['id'] as String,
        schoolId: j['school_id'] as String,
        studentId: j['student_id'] as String,
        studentRecordId: j['student_record_id'] as String,
        mentorId: j['mentor_id'] as String,
        mentorRecordId: j['mentor_record_id'] as String,
        subjectId: j['subject_id'] as String,
        durationMinutes: (j['duration_minutes'] as num?)?.toInt() ?? 0,
        topic: j['topic'] as String? ?? '',
        preparation: j['preparation'] as String?,
        requestedAt: DateTime.tryParse(j['requested_at'] as String? ?? '') ?? DateTime.now(),
        scheduledAt: DateTime.tryParse(j['scheduled_at'] as String? ?? ''),
        confirmedAt: DateTime.tryParse(j['confirmed_at'] as String? ?? ''),
        meetingLink: j['meeting_link'] as String?,
        meetingRoom: j['meeting_room'] as String?,
        status: j['status'] as String? ?? 'requested',
        allowanceMinutesUsed: (j['allowance_minutes_used'] as num?)?.toInt() ?? 0,
        cancelledAt: DateTime.tryParse(j['cancelled_at'] as String? ?? ''),
        cancelledBy: j['cancelled_by'] as String?,
        refunded: j['refunded'] as bool? ?? false,
        verificationCode: j['verification_code'] as String?,
        codeExpiresAt: DateTime.tryParse(j['code_expires_at'] as String? ?? ''),
        codeAttempts: (j['code_attempts'] as num?)?.toInt() ?? 0,
        codeLockedAt: DateTime.tryParse(j['code_locked_at'] as String? ?? ''),
        codeVisibleAt: DateTime.tryParse(j['code_visible_at'] as String? ?? ''),
        verifiedAt: DateTime.tryParse(j['verified_at'] as String? ?? ''),
        closedWithoutCode: j['closed_without_code'] as bool? ?? false,
        closeReason: j['close_reason'] as String?,
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? '') ?? DateTime.now(),
      );

  bool get isConfirmed => status == 'confirmed';
  bool get isRequested => status == 'requested';
  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled_by_student' || status == 'cancelled_by_mentor';
  bool get isNoShow => status == 'no_show_student' || status == 'no_show_mentor';
  bool get isVerified => verifiedAt != null;
  bool get codeLocked => codeLockedAt != null;
  bool get showCode => codeVisibleAt != null && DateTime.now().isAfter(codeVisibleAt!);

  String get statusLabel {
    switch (status) {
      case 'requested': return 'Awaiting confirmation';
      case 'confirmed': return 'Confirmed';
      case 'cancelled_by_student': return 'Cancelled by you';
      case 'cancelled_by_mentor': return 'Cancelled by mentor';
      case 'completed': return 'Completed';
      case 'no_show_student': return 'You did not join';
      case 'no_show_mentor': return 'Mentor did not join';
      case 'unverified_closed': return 'Closed (unverified)';
      default: return status;
    }
  }
}

class MentorAvailability {
  final String id;
  final String schoolId;
  final String teacherId;
  final String status; // available | away
  final DateTime updatedAt;

  const MentorAvailability({
    required this.id,
    required this.schoolId,
    required this.teacherId,
    required this.status,
    required this.updatedAt,
  });

  factory MentorAvailability.fromJson(Map<String, dynamic> j) => MentorAvailability(
        id: j['id'] as String,
        schoolId: j['school_id'] as String,
        teacherId: j['teacher_id'] as String,
        status: j['status'] as String? ?? 'away',
        updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? '') ?? DateTime.now(),
      );

  bool get isAvailable => status == 'available';
}

class Rating {
  final String id;
  final String schoolId;
  final String requestId;
  final String studentId;
  final String mentorId;
  final int rating;
  final String? comment;
  final DateTime createdAt;

  const Rating({
    required this.id,
    required this.schoolId,
    required this.requestId,
    required this.studentId,
    required this.mentorId,
    required this.rating,
    this.comment,
    required this.createdAt,
  });

  factory Rating.fromJson(Map<String, dynamic> j) => Rating(
        id: j['id'] as String,
        schoolId: j['school_id'] as String,
        requestId: j['request_id'] as String,
        studentId: j['student_id'] as String,
        mentorId: j['mentor_id'] as String,
        rating: (j['rating'] as num?)?.toInt() ?? 0,
        comment: j['comment'] as String?,
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
      );
}

class MentorAssessment {
  final String id;
  final String schoolId;
  final String requestId;
  final String mentorId;
  final String studentId;
  final String preparation;
  final String engagement;
  final String? privateNote;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MentorAssessment({
    required this.id,
    required this.schoolId,
    required this.requestId,
    required this.mentorId,
    required this.studentId,
    required this.preparation,
    required this.engagement,
    this.privateNote,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MentorAssessment.fromJson(Map<String, dynamic> j) => MentorAssessment(
        id: j['id'] as String,
        schoolId: j['school_id'] as String,
        requestId: j['request_id'] as String,
        mentorId: j['mentor_id'] as String,
        studentId: j['student_id'] as String,
        preparation: j['preparation'] as String? ?? '',
        engagement: j['engagement'] as String? ?? '',
        privateNote: j['private_note'] as String?,
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? '') ?? DateTime.now(),
      );
}

class MentorDeskSettings {
  final String id;
  final String schoolId;
  final int openDoubtLimit;
  final int sessionAllowanceMinutes;
  final int urgentPassesPerWeek;
  final int escalationThresholdMinutes;
  final int weekStartDay;
  final List<int> sessionLengths;
  final int verificationCodeDigits;
  final int codeVisibleMinutesBefore;
  final int maxVerificationAttempts;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MentorDeskSettings({
    required this.id,
    required this.schoolId,
    required this.openDoubtLimit,
    required this.sessionAllowanceMinutes,
    required this.urgentPassesPerWeek,
    required this.escalationThresholdMinutes,
    required this.weekStartDay,
    required this.sessionLengths,
    required this.verificationCodeDigits,
    required this.codeVisibleMinutesBefore,
    required this.maxVerificationAttempts,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MentorDeskSettings.fromJson(Map<String, dynamic> j) => MentorDeskSettings(
        id: j['id'] as String,
        schoolId: j['school_id'] as String,
        openDoubtLimit: (j['open_doubt_limit'] as num?)?.toInt() ?? 3,
        sessionAllowanceMinutes: (j['session_allowance_minutes'] as num?)?.toInt() ?? 120,
        urgentPassesPerWeek: (j['urgent_passes_per_week'] as num?)?.toInt() ?? 1,
        escalationThresholdMinutes: (j['escalation_threshold_minutes'] as num?)?.toInt() ?? 30,
        weekStartDay: (j['week_start_day'] as num?)?.toInt() ?? 1,
        sessionLengths: (j['session_lengths'] as List?)?.cast<int>().toList() ?? const [15, 30, 45],
        verificationCodeDigits: (j['verification_code_digits'] as num?)?.toInt() ?? 6,
        codeVisibleMinutesBefore: (j['code_visible_minutes_before'] as num?)?.toInt() ?? 10,
        maxVerificationAttempts: (j['max_verification_attempts'] as num?)?.toInt() ?? 5,
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? '') ?? DateTime.now(),
      );
}

class MentorSubjectApproval {
  final String id;
  final String schoolId;
  final String teacherId;
  final String subjectId;
  final String status; // pending | approved | rejected
  final String? approvedBy;
  final DateTime? approvedAt;
  final DateTime createdAt;

  const MentorSubjectApproval({
    required this.id,
    required this.schoolId,
    required this.teacherId,
    required this.subjectId,
    required this.status,
    this.approvedBy,
    this.approvedAt,
    required this.createdAt,
  });

  factory MentorSubjectApproval.fromJson(Map<String, dynamic> j) => MentorSubjectApproval(
        id: j['id'] as String,
        schoolId: j['school_id'] as String,
        teacherId: j['teacher_id'] as String,
        subjectId: j['subject_id'] as String,
        status: j['status'] as String? ?? 'pending',
        approvedBy: j['approved_by'] as String?,
        approvedAt: DateTime.tryParse(j['approved_at'] as String? ?? ''),
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
      );

  bool get isApproved => status == 'approved';
}

class SubjectWithName {
  final String id;
  final String name;
  final String? code;
  SubjectWithName({required this.id, required this.name, this.code});
  factory SubjectWithName.fromJson(Map<String, dynamic> j) => SubjectWithName(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Subject',
        code: j['code'] as String?,
      );
}

class AllowanceSummary {
  final String subjectId;
  final String subjectName;
  final int allowanceMinutes;
  final int usedMinutes;
  final int remainingMinutes;
  final int openDoubts;
  final bool urgentPassAvailable;
  AllowanceSummary({
    required this.subjectId,
    required this.subjectName,
    required this.allowanceMinutes,
    required this.usedMinutes,
    required this.remainingMinutes,
    required this.openDoubts,
    required this.urgentPassAvailable,
  });
}
