// Real messaging against Supabase: persistence via the server-side
// `send_message` RPC (all authorization enforced in Postgres), realtime via
// Supabase Realtime subscriptions (RLS still enforced), read receipts,
// reports, search, support-question status, and private file uploads.
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/models.dart';

class ChatException implements Exception {
  final String code;
  final String message;
  const ChatException(this.code, this.message);
  @override
  String toString() => message;
}

class _MessageRow {
  static MessageRecord fromJson(Map<String, dynamic> j, String me) =>
      MessageRecord.fromJson(j, me);
}

class ChatService {
  ChatService(this._client);
  final SupabaseClient _client;
  final _uuid = const Uuid();

  String get _userId => _client.auth.currentUser!.id;

  // ── Conversations ──────────────────────────────────────────
  Future<List<ConversationRecord>> listConversations() async {
    final memberships = await _client
        .from('conversation_members')
        .select('conversation_id, last_read_at, conversations!inner(id, school_id, type, class_id, title, updated_at)')
        .isFilter('removed_at', null)
        .eq('user_id', _userId)
        .order('joined_at', ascending: false);
    final List<ConversationRecord> out = [];
    for (final m in (memberships as List)) {
      final c = m['conversations'] as Map<String, dynamic>;
      final convId = c['id'] as String;
      // Last visible message (RLS hides blocked/others' pending automatically)
      final last = await _client
          .from('messages')
          .select('body, created_at')
          .eq('conversation_id', convId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      final lastReadAt = DateTime.tryParse(m['last_read_at'] as String? ?? '');
      int unread = 0;
      if (last != null) {
        final count = await _client
            .from('messages')
            .select('id')
            .eq('conversation_id', convId)
            .neq('sender_id', _userId)
            .eq('is_deleted', false);
        // Client-side unread estimate (approved-only per RLS; pending of others invisible)
        unread = (count as List).length;
        if (lastReadAt != null) {
          final newer = await _client
              .from('messages')
              .select('id')
              .eq('conversation_id', convId)
              .neq('sender_id', _userId)
              .gt('created_at', lastReadAt.toIso8601String());
          unread = (newer as List).length;
        }
      }
      out.add(ConversationRecord(
        id: convId,
        schoolId: c['school_id'] as String,
        type: c['type'] as String,
        classId: c['class_id'] as String?,
        title: c['title'] as String?,
        updatedAt: DateTime.tryParse(c['updated_at'] as String? ?? '') ?? DateTime.now(),
        unreadCount: unread,
        lastMessageBody: (last?['body'] as String?),
        lastMessageAt: DateTime.tryParse(last?['created_at'] as String? ?? ''),
      ));
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _attachPeerIdentity(out);
    return out;
  }

  /// Resolves who the other side of each conversation is, so a teacher always
  /// sees the student's name and class instead of a generic "Teacher Support".
  Future<void> _attachPeerIdentity(List<ConversationRecord> conversations) async {
    if (conversations.isEmpty) return;
    final ids = conversations.map((c) => c.id).toList();

    List<dynamic> memberRows = const [];
    try {
      memberRows = await _client
          .from('conversation_members')
          .select('conversation_id, user_id')
          .inFilter('conversation_id', ids)
          .isFilter('removed_at', null);
    } catch (e) {
      debugPrint('peer: members failed: $e');
    }

    final me = _userId;
    final peerOf = <String, List<String>>{};
    for (final r in memberRows) {
      final m = r as Map;
      final cid = m['conversation_id'] as String?;
      final uid = m['user_id'] as String?;
      if (cid == null || uid == null || uid == me) continue;
      (peerOf[cid] ??= <String>[]).add(uid);
    }
    final peerIds = peerOf.values.expand((e) => e).toSet().toList();
    if (peerIds.isEmpty) return;

    final names = <String, String>{};
    try {
      final profiles = await _client
          .from('user_profiles')
          .select('id, display_name')
          .inFilter('id', peerIds);
      for (final p in (profiles as List)) {
        final m = p as Map;
        final id = m['id'] as String?;
        if (id != null) names[id] = (m['display_name'] as String?) ?? '';
      }
    } catch (e) {
      debugPrint('peer: profiles failed: $e');
    }

    // Resolve student class labels for any peer that is a student.
    final studentOf = <String, Map<String, dynamic>>{};
    try {
      final studentRows = await _client
          .from('students')
          .select('id, user_id, first_name, last_name, student_id_no, class_enrollments(class_id, classes(name))')
          .inFilter('user_id', peerIds);
      for (final s in (studentRows as List)) {
        final m = Map<String, dynamic>.from(s as Map);
        final uid = m['user_id'] as String?;
        if (uid != null) studentOf[uid] = m;
      }
    } catch (e) {
      debugPrint('peer: students failed: $e');
    }

    for (var i = 0; i < conversations.length; i++) {
      final peers = peerOf[conversations[i].id];
      if (peers == null || peers.isEmpty) continue;
      final c = conversations[i];

      String? label;
      String? detail;
      var isStudent = false;

      // Prefer naming a student peer — that's the information a teacher needs.
      for (final uid in peers) {
        final s = studentOf[uid];
        if (s == null) continue;
        isStudent = true;
        final own = '${s['first_name'] ?? ''} ${s['last_name'] ?? ''}'.trim();
        final nm = names[uid];
        label = own.isNotEmpty
            ? own
            : ((nm != null && nm.isNotEmpty) ? nm : 'Student ${s['student_id_no'] ?? ''}');
        final enrollments = s['class_enrollments'] as List?;
        String? className;
        if (enrollments != null && enrollments.isNotEmpty) {
          final e0 = enrollments.first as Map;
          final cls = e0['classes'];
          if (cls is Map) className = cls['name'] as String?;
        }
        final idNo = s['student_id_no'] as String?;
        detail = [if (className != null && className.isNotEmpty) className, if (idNo != null) idNo]
            .where((x) => x.isNotEmpty)
            .join(' · ');
        break;
      }

      if (label == null) {
        // Otherwise fall back to any named staff peer.
        for (final uid in peers) {
          final nm = names[uid];
          if (nm != null && nm.isNotEmpty) {
            label = nm;
            detail = 'Staff';
            break;
          }
        }
      }

      if (label == null && c.title != null && c.title!.isNotEmpty) {
        label = c.title;
      }

      if (label == null) continue;

      conversations[i] = ConversationRecord(
        id: c.id,
        schoolId: c.schoolId,
        type: c.type,
        classId: c.classId,
        title: c.title,
        updatedAt: c.updatedAt,
        unreadCount: c.unreadCount,
        lastMessageBody: c.lastMessageBody,
        lastMessageAt: c.lastMessageAt,
        peerName: label,
        peerDetail: detail,
        peerIsStudent: isStudent,
      );
    }
  }

  /// Resolves who the other side of a conversation is. Used by the chat header
  /// so a teacher always sees the student's name and class, and a student
  /// always sees their teacher's name and whether they are around right now.
  ///
  /// Each lookup is guarded independently: RLS hides `students` from students
  /// and `teachers` from nobody with a membership, so one denied query must not
  /// wipe out the name we already resolved.
  Future<({String? name, String? detail, DateTime? lastSeenAt})> resolvePeer(
    String conversationId,
  ) async {
    // Explicit return type so the null-only record literal below is typed against
    // the same shape the caller expects.
    ({String? name, String? detail, DateTime? lastSeenAt}) empty() =>
        (name: null, detail: null, lastSeenAt: null);

    List<dynamic> members = const [];
    try {
      members = await _client
          .from('conversation_members')
          .select('user_id, role')
          .eq('conversation_id', conversationId)
          .isFilter('removed_at', null);
    } catch (e) {
      debugPrint('peer: members failed: $e');
      return empty();
    }
    final me = _userId;
    final peerIds = <String>[];
    for (final m in members) {
      final uid = (m as Map)['user_id'] as String?;
      if (uid != null && uid != me) peerIds.add(uid);
    }
    if (peerIds.isEmpty) return empty();

    final names = <String, String>{};
    try {
      final profiles = await _client
          .from('user_profiles')
          .select('id, display_name')
          .inFilter('id', peerIds);
      for (final p in (profiles as List)) {
        final m = p as Map;
        final id = m['id'] as String?;
        if (id != null) names[id] = (m['display_name'] as String?) ?? '';
      }
    } catch (e) {
      debugPrint('peer: profiles failed: $e');
    }

    // Teacher peers carry presence — a student wants to know if the teacher
    // they are about to message is actually there.
    final teacherLastSeen = <String, DateTime>{};
    try {
      final teacherRows = await _client
          .from('teachers')
          .select('user_id, last_seen_at')
          .inFilter('user_id', peerIds);
      for (final t in (teacherRows as List)) {
        final m = t as Map;
        final uid = m['user_id'] as String?;
        final seen = DateTime.tryParse(m['last_seen_at'] as String? ?? '');
        if (uid != null && seen != null) teacherLastSeen[uid] = seen;
      }
    } catch (e) {
      debugPrint('peer: teachers failed: $e');
    }

    // Students are only readable by staff, so this is expected to come back
    // empty (not throw) for a student caller.
    final studentByUser = <String, Map<String, dynamic>>{};
    try {
      final studentRows = await _client
          .from('students')
          .select('id, user_id, first_name, last_name, student_id_no, class_enrollments(class_id, classes(name))')
          .inFilter('user_id', peerIds);
      for (final s in (studentRows as List)) {
        final m = Map<String, dynamic>.from(s as Map);
        final uid = m['user_id'] as String?;
        if (uid != null) studentByUser[uid] = m;
      }
    } catch (e) {
      debugPrint('peer: students failed: $e');
    }

    for (final uid in peerIds) {
      final s = studentByUser[uid];
      if (s == null) continue;
      final nm = names[uid];
      final label = (nm != null && nm.isNotEmpty) ? nm : 'Student ${s['student_id_no'] ?? ''}';
      final enrollments = s['class_enrollments'] as List?;
      String? className;
      if (enrollments != null && enrollments.isNotEmpty) {
        final e0 = enrollments.first as Map;
        final cls = e0['classes'];
        if (cls is Map) className = cls['name'] as String?;
      }
      final idNo = s['student_id_no'] as String?;
      final detail = [
        if (className != null && className.isNotEmpty) className,
        if (idNo != null) idNo,
      ].where((x) => x.isNotEmpty).join(' · ');
      return (name: label, detail: detail, lastSeenAt: null);
    }

    for (final uid in peerIds) {
      final nm = names[uid];
      if (nm != null && nm.isNotEmpty) {
        return (name: nm, detail: 'Staff', lastSeenAt: teacherLastSeen[uid]);
      }
    }

    // No usable profile name, but we may still know they are a teacher online.
    for (final uid in peerIds) {
      if (teacherLastSeen.containsKey(uid)) {
        return (name: null, detail: 'Staff', lastSeenAt: teacherLastSeen[uid]);
      }
    }

    return empty();
  }

  // ── Messages ─────────────────────────────────────────────
  Future<MessageRecord> sendMessage({
    required String conversationId,
    required String body,
    String? replyToId,
    String? idempotencyKey,
    String? attachmentId,
  }) async {
    final key = idempotencyKey ?? _uuid.v4();
    late final Map<String, dynamic> res;
    try {
      final rpc = await _client.rpc('send_message', params: {
        'p_conversation_id': conversationId,
        'p_sender_id': _userId,
        'p_body': body,
        'p_idempotency_key': key,
        if (replyToId != null) 'p_reply_to_id': replyToId,
        if (attachmentId != null) 'p_attachment_id': attachmentId,
      });
      res = Map<String, dynamic>.from(rpc as Map);
    } catch (_) {
      throw const ChatException('network_error', 'Could not send. Check your connection and retry.');
    }
    if (res['success'] != true) {
      throw ChatException(res['error']?.toString() ?? 'send_failed', _sendErrorMessage(res['error']?.toString()));
    }
    final msg = await _client
        .from('messages')
        .select('*, attachments(*)')
        .eq('id', res['message_id'])
        .single();
    return _MessageRow.fromJson(Map<String, dynamic>.from(msg), _userId);
  }

  String _sendErrorMessage(String? code) {
    switch (code) {
      case 'not_a_member':
        return 'You are no longer a member of this conversation.';
      case 'send_not_permitted':
        return 'You do not have permission to send here.';
      case 'students_cannot_send_in_class_channel':
        return 'Students cannot post in class channels.';
      case 'empty_message':
        return 'Message cannot be empty.';
      case 'message_too_long':
        return 'Message is too long (max 4000 characters).';
      case 'attachment_not_found':
        return 'The attachment could not be linked. Please try uploading again.';
      default:
        return 'Message was not sent. Please retry.';
    }
  }

  Future<List<MessageRecord>> fetchMessages({required String conversationId, int limit = 30, String? beforeIso}) async {
    // Filters must precede order/limit in this postgrest version's builder.
    dynamic q = _client
        .from('messages')
        .select('*, attachments(*)')
        .eq('conversation_id', conversationId)
        .eq('is_deleted', false);
    if (beforeIso != null) q = q.lt('created_at', beforeIso);
    final rows = await q.order('created_at', ascending: false).limit(limit);
    return (rows as List)
        .map((r) => _MessageRow.fromJson(Map<String, dynamic>.from(r as Map), _userId))
        .toList();
  }

  /// Realtime stream of rows in this conversation (RLS-filtered server-side).
  Stream<List<Map<String, dynamic>>> watchConversation(String conversationId) {
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true);
  }

  /// Marks the conversation read. Uses a SECURITY DEFINER RPC (not a broad
  /// table UPDATE policy) so members can't self-escalate can_send/role, and
  /// so message_receipts (RLS with no client policies) can be written at all.
  Future<void> markRead({required String conversationId, required String messageId}) async {
    await _client.rpc('mark_conversation_read', params: {
      'p_conversation_id': conversationId,
    });
  }

  // ── Reports ──────────────────────────────────────────────
  Future<void> reportMessage({required String schoolId, required String messageId, required String reason, String? details}) async {
    try {
      await _client.from('message_reports').insert({
        'school_id': schoolId,
        'reporter_id': _userId,
        'message_id': messageId,
        'reason': reason,
        if (details != null && details.isNotEmpty) 'details': details,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw const ChatException('already_reported', 'You have already reported this message. Our team will review it.');
      }
      rethrow;
    }
  }

  // ── Search within the user's own conversations ────────────
  Future<List<MessageRecord>> searchMessages(String query) async {
    if (query.trim().length < 2) return [];
    final myConvs = await _client
        .from('conversation_members')
        .select('conversation_id')
        .eq('user_id', _userId)
        .isFilter('removed_at', null);
    final ids = (myConvs as List).map((m) => (m as Map)['conversation_id'] as String).toList();
    if (ids.isEmpty) return [];
    final rows = await _client
        .from('messages')
        .select('*, attachments(*)')
        .inFilter('conversation_id', ids)
        .textSearch('body', "'${query.replaceAll("'", "''")}'")
        .order('created_at', ascending: false)
        .limit(30);
    return (rows as List).map((r) => _MessageRow.fromJson(Map<String, dynamic>.from(r as Map), _userId)).toList();
  }

  // ── Support question status (teachers/admins change, audited via RLS-safe update) ──
  Future<void> updateQuestionStatus({required String questionId, required String toStatus, String? note}) async {
    final q = await _client.from('support_questions').select('id, conversation_id, status').eq('id', questionId).maybeSingle();
    if (q == null) throw const ChatException('not_found', 'Question not found.');
    await _client.from('support_questions').update({'status': toStatus}).eq('id', questionId);
    await _client.from('support_question_history').insert({
      'question_id': questionId,
      'changed_by': _userId,
      'from_status': (q as Map)['status'],
      'to_status': toStatus,
      if (note != null) 'note': note,
    });
  }

  Future<Map<String, dynamic>?> supportQuestionFor(String conversationId) async {
    return await _client
        .from('support_questions')
        .select()
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle()
        .then((v) => v == null ? null : Map<String, dynamic>.from(v as Map));
  }

  // ── Attachments: private upload → pending_scan → server moderation ──
  static const int maxBytesDefault = 10 * 1024 * 1024;
  static const imageMime = {'image/jpeg', 'image/png', 'image/webp', 'image/gif'};
  static const audioMime = {'audio/mpeg', 'audio/mp4', 'audio/ogg', 'audio/wav', 'audio/webm'};

  Future<AttachmentRecord> uploadAttachment({
    required String schoolId,
    required String conversationId,
    required String localPath,
    required String fileName,
    required String mimeType,
    required int sizeBytes,
    String? messageId,
  }) async {
    if (sizeBytes > maxBytesDefault) {
      throw const ChatException('file_too_large', 'File is too large (max 10 MB).');
    }
    if (!imageMime.contains(mimeType) && !audioMime.contains(mimeType) && mimeType != 'application/pdf') {
      throw const ChatException('unsupported_type', 'This file type is not supported.');
    }
    final type = imageMime.contains(mimeType) ? 'image' : (audioMime.contains(mimeType) ? 'audio' : 'document');
    final storagePath = '$schoolId/$conversationId/${_uuid.v4()}_$fileName';
    try {
      await _client.storage.from('attachments').uploadBinary(
            storagePath,
            await File(localPath).readAsBytes(),
            fileOptions: FileOptions(contentType: mimeType, upsert: false),
          );
    } catch (_) {
      throw const ChatException('upload_failed', 'Upload failed. Check your connection and retry.');
    }
    final row = await _client.from('attachments').insert({
      'message_id': messageId,
      'school_id': schoolId,
      'uploader_id': _userId,
      'type': type,
      'file_name': fileName,
      'mime_type': mimeType,
      'size_bytes': sizeBytes,
      'storage_path': storagePath,
      'status': 'pending_scan',
    }).select().single();
    // Moderation runs server-side (moderate-image webhook on insert).
    // The file stays invisible to others until approved — enforced by RLS.
    return AttachmentRecord.fromJson(Map<String, dynamic>.from(row));
  }

  Future<String> signedUrl(String storagePath) async {
    final res = await _client.storage.from('attachments').createSignedUrl(storagePath, 300);
    return res;
  }
}
