// Typed data models - mirrors packages/contracts (Supabase rows).
// All parsing is null-safe.
class SchoolRecord {
  final String id;
  final String name;
  final String code;
  final String? city;
  final String? state;
  final String? logoUrl;
  const SchoolRecord({
    required this.id,
    required this.name,
    required this.code,
    this.city,
    this.state,
    this.logoUrl,
  });
  factory SchoolRecord.fromJson(Map<String, dynamic> j) => SchoolRecord(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        code: j['code'] as String? ?? '',
        city: j['city'] as String?,
        state: j['state'] as String?,
        logoUrl: j['logo_url'] as String?,
      );
}

class MembershipRecord {
  final String role;
  final String schoolId;
  final Map<String, dynamic>? school;
  const MembershipRecord({required this.role, required this.schoolId, this.school});
  factory MembershipRecord.fromJson(Map<String, dynamic> j) => MembershipRecord(
        role: j['role'] as String? ?? '',
        schoolId: j['school_id'] as String? ?? '',
        school: j['schools'] as Map<String, dynamic>?,
      );
  bool get isStudent => role == 'student';
  bool get isTeacher => role == 'teacher' || role == 'head_teacher';
}

class ConversationRecord {
  final String id;
  final String schoolId;
  final String type;
  final String? classId;
  final String? title;
  final DateTime updatedAt;
  final int unreadCount;
  final String? lastMessageBody;
  final DateTime? lastMessageAt;
  const ConversationRecord({
    required this.id,
    required this.schoolId,
    required this.type,
    this.classId,
    this.title,
    required this.updatedAt,
    this.unreadCount = 0,
    this.lastMessageBody,
    this.lastMessageAt,
  });
  String displayTitle() {
    if (title != null && title!.isNotEmpty) return title!;
    switch (type) {
      case 'student_support':
        return 'Teacher Support';
      case 'class_channel':
        return 'Class Channel';
      case 'staff':
        return 'Staff Chat';
      case 'leadership':
        return 'School Leadership';
      default:
        return 'Conversation';
    }
  }
}

class MessageRecord {
  final String id;
  final String conversationId;
  final String senderId;
  final String? body;
  final String status; // approved | pending_moderation | held_for_review | blocked
  final DateTime createdAt;
  final bool isMine;
  final List<AttachmentRecord> attachments;
  const MessageRecord({
    required this.id,
    required this.conversationId,
    required this.senderId,
    this.body,
    required this.status,
    required this.createdAt,
    this.isMine = false,
    this.attachments = const [],
  });
  factory MessageRecord.fromJson(Map<String, dynamic> j, String myUserId) => MessageRecord(
        id: j['id'] as String,
        conversationId: j['conversation_id'] as String,
        senderId: j['sender_id'] as String,
        body: j['body'] as String?,
        status: j['status'] as String? ?? 'approved',
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
        isMine: j['sender_id'] == myUserId,
        attachments: ((j['attachments'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(AttachmentRecord.fromJson)
            .toList(),
      );
  bool get isPending => status == 'pending_moderation' || status == 'held_for_review';
}

class AttachmentRecord {
  final String id;
  final String type;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final String storagePath;
  final String status;
  const AttachmentRecord({
    required this.id,
    required this.type,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.storagePath,
    required this.status,
  });
  factory AttachmentRecord.fromJson(Map<String, dynamic> j) => AttachmentRecord(
        id: j['id'] as String,
        type: j['type'] as String? ?? 'image',
        fileName: j['file_name'] as String? ?? '',
        mimeType: j['mime_type'] as String? ?? '',
        sizeBytes: (j['size_bytes'] as num?)?.toInt() ?? 0,
        storagePath: j['storage_path'] as String? ?? '',
        status: j['status'] as String? ?? 'pending_scan',
      );
}

class AnnouncementRecord {
  final String id;
  final String title;
  final String body;
  final String category;
  final String audienceType;
  final bool requiresAck;
  final DateTime? publishedAt;
  final DateTime? acknowledgedAt;
  const AnnouncementRecord({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.audienceType,
    required this.requiresAck,
    this.publishedAt,
    this.acknowledgedAt,
  });
  factory AnnouncementRecord.fromJson(Map<String, dynamic> j) => AnnouncementRecord(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        category: j['category'] as String? ?? 'general',
        audienceType: j['audience_type'] as String? ?? 'school_wide',
        requiresAck: j['requires_ack'] as bool? ?? false,
        publishedAt: DateTime.tryParse(j['published_at'] as String? ?? ''),
        acknowledgedAt: null,
      );
  bool get isPriority => category == 'priority_alert';
}

class TeacherEntry {
  final String userId;
  final String name;
  final String? subject;
  const TeacherEntry({required this.userId, required this.name, this.subject});
}
