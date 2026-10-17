import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../services/chat_service.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/states.dart';

final _chatProvider = Provider<ChatService>(
  (ref) => ChatService(Supabase.instance.client),
);

/// Full conversation: paginated history, realtime inserts, send with retry +
/// idempotency, image attachments (private, moderated), report action,
/// support-question status chip (teachers), read receipts, offline notice.
class ConversationScreen extends ConsumerStatefulWidget {
  final String conversationId;
  const ConversationScreen({super.key, required this.conversationId});

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<MessageRecord> _messages = []; // newest first
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  String? _sendError;
  bool _sending = false;
  bool _uploading = false;
  String _title = 'Conversation';
  String? _schoolId;
  String? _convType;
  Map<String, dynamic>? _question;
  bool _isTeacher = false;
  StreamSubscription? _realtimeSub;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _init();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) _loadMore();
    });
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final client = Supabase.instance.client;
      final me = client.auth.currentUser!.id;
      final conv = await client.from('conversations').select('id, school_id, type, title').eq('id', widget.conversationId).maybeSingle();
      if (conv == null) {
        if (mounted) {
          setState(() {
            _error = 'Conversation not found or you no longer have access.';
            _loading = false;
          });
        }
        return;
      }
      final c = Map<String, dynamic>.from(conv as Map);
      final membership = await client
          .from('school_memberships')
          .select('role')
          .eq('user_id', me)
          .eq('school_id', c['school_id'])
          .eq('is_active', true)
          .limit(1)
          .maybeSingle();
      final role = membership != null ? (membership as Map)['role'] as String : '';
      final question = await ref.read(_chatProvider).supportQuestionFor(widget.conversationId);
      await _loadPage();
      if (!mounted) return;
      setState(() {
        _title = _titleFor(c['type'] as String, c['title'] as String?);
        _schoolId = c['school_id'] as String;
        _convType = c['type'] as String;
        _question = question;
        _isTeacher = role == 'teacher' || role == 'head_teacher';
      });
      _subscribeRealtime();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not open conversation. Check your connection.';
          _loading = false;
        });
      }
    }
  }

  void _subscribeRealtime() {
    _realtimeSub = ref
        .read(_chatProvider)
        .watchConversation(widget.conversationId)
        .listen((rows) async {
      // Re-insert path: fetch newest page tail and merge unseen ids.
      try {
        final fresh = await ref
            .read(_chatProvider)
            .fetchMessages(conversationId: widget.conversationId, limit: 10);
        if (!mounted) return;
        final known = _messages.map((m) => m.id).toSet();
        final unseen = fresh.where((m) => !known.contains(m.id)).toList();
        if (unseen.isEmpty) return;
        setState(() {
          _messages = [...unseen, ..._messages]
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        });
        if (unseen.any((m) => !m.isMine)) {
          await ref.read(_chatProvider).markRead(
                conversationId: widget.conversationId,
                messageId: unseen.firstWhere((m) => !m.isMine).id,
              );
        }
      } catch (_) {/* best effort */}
    });
  }

  String _titleFor(String type, String? title) {
    if (title != null && title.isNotEmpty) return title;
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

  Future<void> _loadPage() async {
    final msgs = await ref
        .read(_chatProvider)
        .fetchMessages(conversationId: widget.conversationId, limit: 30);
    if (!mounted) return;
    setState(() {
      _messages = msgs;
      _loading = false;
      _hasMore = msgs.length == 30;
    });
    if (msgs.isNotEmpty) {
      final others = msgs.where((m) => !m.isMine);
      if (others.isNotEmpty) {
        try {
          await ref.read(_chatProvider).markRead(
                conversationId: widget.conversationId,
                messageId: others.first.id,
              );
        } catch (_) {}
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _messages.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final older = await ref.read(_chatProvider).fetchMessages(
            conversationId: widget.conversationId,
            limit: 30,
            beforeIso: _messages.last.createdAt.toIso8601String(),
          );
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, ...older];
        _hasMore = older.length == 30;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    if (_convType == 'class_channel' && !_isTeacher) {
      setState(() => _sendError = 'Students cannot post in class channels.');
      return;
    }
    setState(() {
      _sending = true;
      _sendError = null;
    });
    final key = const Uuid().v4();
    try {
      final msg = await ref.read(_chatProvider).sendMessage(
            conversationId: widget.conversationId,
            body: text,
            idempotencyKey: key,
          );
      _input.clear();
      if (!mounted) return;
      setState(() {
        // Prepend; realtime will dedupe by id on merge.
        if (!_messages.any((m) => m.id == msg.id)) {
          _messages = [msg, ..._messages];
        }
      });
      _scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    } on ChatException catch (e) {
      if (mounted) setState(() => _sendError = e.message);
    } catch (_) {
      if (mounted) setState(() => _sendError = 'Message was not sent. Please retry.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _mimeFromName(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  Future<void> _pickImage() async {
    if (_uploading || _schoolId == null) return;
    if (_convType == 'class_channel' && !_isTeacher) {
      setState(() => _sendError = 'Students cannot post in class channels.');
      return;
    }
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() {
      _uploading = true;
      _sendError = null;
    });
    try {
      final bytes = await picked.length();
      final attachment = await ref.read(_chatProvider).uploadAttachment(
            schoolId: _schoolId!,
            conversationId: widget.conversationId,
            localPath: picked.path,
            fileName: picked.name,
            mimeType: _mimeFromName(picked.name),
            sizeBytes: bytes,
          );
      // Link the upload to a real message (empty body allowed with attachment).
      final caption = _input.text.trim();
      final msg = await ref.read(_chatProvider).sendMessage(
            conversationId: widget.conversationId,
            body: caption,
            attachmentId: attachment.id,
          );
      _input.clear();
      if (!mounted) return;
      setState(() {
        if (!_messages.any((m) => m.id == msg.id)) {
          _messages = [msg, ..._messages];
        }
      });
      _scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(attachment.status == 'approved'
              ? 'Image shared.'
              : 'Image shared — visible to others after automatic safety review.'),
        ),
      );
    } on ChatException catch (e) {
      if (mounted) setState(() => _sendError = e.message);
    } catch (_) {
      if (mounted) setState(() => _sendError = 'Could not share the image. Please try again.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _report(MessageRecord m) {
    final reasons = ['Bullying or harassment', 'Inappropriate content', 'Spam', 'Safety concern', 'Other'];
    String selected = reasons.first;
    final details = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report message'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: selected,
              items: reasons.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
              onChanged: (v) => selected = v ?? selected,
            ),
            TextField(controller: details, decoration: const InputDecoration(hintText: 'Details (optional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final note = details.text;
              Navigator.pop(ctx);
              try {
                await ref.read(_chatProvider).reportMessage(
                      schoolId: _schoolId!,
                      messageId: m.id,
                      reason: selected,
                      details: note,
                    );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Reported. Our safeguarding team will review it.')),
                  );
                }
              } on ChatException catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                }
              }
            },
            child: const Text('Report'),
          ),
        ],
      ),
    ).whenComplete(details.dispose);
  }

  Future<void> _changeQuestionStatus(String to) async {
    if (_question == null) return;
    try {
      await ref.read(_chatProvider).updateQuestionStatus(questionId: _question!['id'] as String, toStatus: to);
      final q = await ref.read(_chatProvider).supportQuestionFor(widget.conversationId);
      if (mounted) setState(() => _question = q);
    } on ChatException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (_convType == 'student_support' && _question != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _QuestionChip(
                status: _question!['status'] as String? ?? 'open',
                isTeacher: _isTeacher,
                onChange: _changeQuestionStatus,
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const LoadingView()
                : _error != null
                    ? ErrorView(message: _error!, onRetry: () {
                        setState(() {
                          _loading = true;
                          _error = null;
                        });
                        _init();
                      })
                    : _messages.isEmpty
                        ? const EmptyView(
                            title: 'No messages yet',
                            subtitle: 'Start the conversation below.',
                            icon: Icons.chat_bubble_outline,
                          )
                        : ListView.builder(
                            controller: _scroll,
                            reverse: true,
                            padding: const EdgeInsets.all(12),
                            itemCount: _messages.length + (_loadingMore ? 1 : 0),
                            itemBuilder: (context, i) {
                              if (i == _messages.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Center(child: CircularProgressIndicator()),
                                );
                              }
                              final m = _messages[i];
                              return _Bubble(
                                message: m,
                                onReport: m.isMine ? null : () => _report(m),
                              );
                            },
                          ),
          ),
          if (_sendError != null)
            Container(
              width: double.infinity,
              color: const Color(0xFFFEF2F2),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(_sendError!, style: const TextStyle(color: Color(0xFF991B1B), fontSize: 12)),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  IconButton(
                    icon: _uploading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.image_outlined),
                    onPressed: _uploading ? null : _pickImage,
                    tooltip: 'Share image',
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(hintText: 'Type a message...'),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: _sending
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send),
                    onPressed: _sending ? null : _send,
                    tooltip: 'Send',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final MessageRecord message;
  final VoidCallback? onReport;
  const _Bubble({required this.message, this.onReport});

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onReport,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          decoration: BoxDecoration(
            color: mine ? const Color(0xFF1A56DB) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: mine ? null : Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.body != null && message.body!.isNotEmpty)
                Text(message.body!,
                    style: TextStyle(color: mine ? Colors.white : const Color(0xFF111827))),
              for (final a in message.attachments)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _AttachmentView(attachment: a),
                ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _time(message.createdAt),
                    style: TextStyle(color: mine ? const Color(0xFFBFDBFE) : const Color(0xFF9CA3AF), fontSize: 11),
                  ),
                  if (mine) ...[
                    const SizedBox(width: 4),
                    Icon(
                      message.isPending ? Icons.schedule : Icons.done_all,
                      size: 14,
                      color: mine ? const Color(0xFFBFDBFE) : const Color(0xFF9CA3AF),
                    ),
                  ],
                ],
              ),
              if (message.isPending && !mine)
                const SizedBox.shrink(),
              if (message.isPending && mine)
                const Text('Sending / under review...',
                    style: TextStyle(color: Color(0xFFBFDBFE), fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  String _time(DateTime dt) {
    final l = dt.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}

class _AttachmentView extends ConsumerStatefulWidget {
  final AttachmentRecord attachment;
  const _AttachmentView({required this.attachment});
  @override
  ConsumerState<_AttachmentView> createState() => _AttachmentViewState();
}

class _AttachmentViewState extends ConsumerState<_AttachmentView> {
  Future<String>? _url;

  bool get _isApprovedImage =>
      widget.attachment.type == 'image' && widget.attachment.status == 'approved';

  @override
  void initState() {
    super.initState();
    if (_isApprovedImage) {
      _url = ref.read(_chatProvider).signedUrl(widget.attachment.storagePath);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.attachment;
    if (a.type != 'image') {
      return _stub(Icons.attach_file, a.fileName.isEmpty ? a.type : a.fileName);
    }
    if (!_isApprovedImage) {
      final blocked = a.status == 'rejected' || a.status == 'blocked' || a.status == 'quarantined';
      return _stub(
        blocked ? Icons.block : Icons.shield_outlined,
        blocked ? 'Image blocked by safety review' : 'Image under safety review',
      );
    }
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _stub(Icons.image_outlined, 'Loading image...');
        }
        if (!snap.hasData) {
          return _stub(Icons.broken_image_outlined, 'Image unavailable');
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            snap.data!,
            width: 220,
            fit: BoxFit.cover,
            loadingBuilder: (c, child, progress) =>
                progress == null ? child : _stub(Icons.image_outlined, 'Loading image...'),
            errorBuilder: (c, e, s) => _stub(Icons.broken_image_outlined, 'Image unavailable'),
          ),
        );
      },
    );
  }

  Widget _stub(IconData icon, String label) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF6B7280)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionChip extends StatelessWidget {
  final String status;
  final bool isTeacher;
  final ValueChanged<String> onChange;
  const _QuestionChip({required this.status, required this.isTeacher, required this.onChange});

  @override
  Widget build(BuildContext context) {
    const order = ['open', 'in_progress', 'answered', 'resolved'];
    return PopupMenuButton<String>(
      enabled: isTeacher,
      tooltip: isTeacher ? 'Change status' : 'Question status: $status',
      onSelected: onChange,
      itemBuilder: (_) => order.map((s) => PopupMenuItem(value: s, child: Text(s.replaceAll('_', ' ')))).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: status == 'resolved' ? const Color(0xFFDEF7EC) : const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(status.replaceAll('_', ' '),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
