import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mentor_desk_design.dart';
import '../../../core/layout/responsive.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/states.dart';
import '../../mentor_desk/models/mentor_desk_models.dart';
import '../../mentor_desk/services/mentor_desk_service.dart';

final _serviceProvider = Provider<MentorDeskService>(
  (ref) => MentorDeskService(Supabase.instance.client),
);

/// Persistent doubt conversation: student + assigned mentor messages, status
/// chip, resolve/reopen actions, attachment previews, realtime updates.
class MentorDoubtConversationScreen extends ConsumerStatefulWidget {
  final String requestId;
  const MentorDoubtConversationScreen({super.key, required this.requestId});

  @override
  ConsumerState<MentorDoubtConversationScreen> createState() => _MentorDoubtConversationScreenState();
}

class _MentorDoubtConversationScreenState extends ConsumerState<MentorDoubtConversationScreen> {
  DoubtRequest? _doubt;
  bool _loading = true;
  String? _error;
  String? _convId;
  bool _isTeacher = false;
  bool _isStudent = false;
  bool _canResolve = false;
  bool _canReopen = false;
  bool _canRate = false;
  bool _alreadyRated = false;
  String? _schoolId;
  String? _me;

  final _input = TextEditingController();
  List<MessageRecord> _messages = [];
  bool _sending = false;
  String? _sendError;
  bool _uploading = false;
  StreamSubscription? _realtime;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _realtime?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final client = Supabase.instance.client;
      final me = client.auth.currentUser!.id;
      _me = me;
      final service = ref.read(_serviceProvider);
      final doubt = await service.getDoubtRequest(widget.requestId);
      if (doubt == null) {
        if (mounted) setState(() { _error = 'Doubt not found.'; _loading = false; });
        return;
      }
      _convId = doubt.conversationId;
      _schoolId = doubt.schoolId;

      final membership = await client
          .from('school_memberships')
          .select('role')
          .eq('user_id', me)
          .eq('school_id', doubt.schoolId)
          .eq('is_active', true)
          .limit(1)
          .maybeSingle();
      final role = membership != null ? (membership as Map)['role'] as String : '';
      _isStudent = role == 'student';
      _isTeacher = role == 'teacher' || role == 'head_teacher';

      _canReopen = _isStudent && doubt.studentId == me && (doubt.isResolved || doubt.isClosed);
      _canResolve = _isTeacher && doubt.assignedMentorId == me && doubt.isOpen;

      final ratings = await service.listRatingsForRequest(widget.requestId);
      _alreadyRated = ratings.any((r) => r.studentId == me);
      _canRate = _isStudent && doubt.studentId == me && (doubt.isResolved || doubt.isClosed) && !_alreadyRated;

      await _loadMessages();

      if (!mounted) return;
      setState(() {
        _doubt = doubt;
        _loading = false;
      });

      _subscribeRealtime();
    } catch (_) {
      if (mounted) setState(() { _error = 'Could not open the doubt.'; _loading = false; });
    }
  }

  Future<void> _loadMessages() async {
    if (_convId == null) return;
    final msgs = await Supabase.instance.client
        .from('messages')
        .select('*, attachments(*)')
        .eq('conversation_id', _convId!)
        .eq('is_deleted', false)
        .order('created_at', ascending: true);
    if (!mounted) return;
    setState(() => _messages = (msgs as List)
        .map((r) => MessageRecord.fromJson(Map<String, dynamic>.from(r as Map), _me!))
        .toList());
  }

  void _subscribeRealtime() {
    if (_convId == null) return;
    _realtime = ref.read(_serviceProvider).client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', _convId!)
        .listen((_) => _loadMessages());
    _realtime?.onError((_) {});
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending || _convId == null) return;
    setState(() { _sending = true; _sendError = null; });
    try {
      await Supabase.instance.client.rpc('send_message', params: {
        'p_conversation_id': _convId,
        'p_sender_id': _me,
        'p_body': text,
        'p_idempotency_key': const Uuid().v4(),
      });
      _input.clear();
      await _loadMessages();
    } catch (e) {
      if (mounted) setState(() => _sendError = 'Message was not sent. Please retry.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickImage() async {
    if (_uploading || _schoolId == null || _convId == null) return;
    final picked = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1920, imageQuality: 85);
    if (picked == null) return;
    setState(() { _uploading = true; _sendError = null; });
    try {
      final service = ref.read(_serviceProvider);
      final ids = await service.uploadImages(
        schoolId: _schoolId!,
        conversationId: _convId!,
        files: [picked],
      );
      final text = _input.text.trim();
      await Supabase.instance.client.rpc('send_message', params: {
        'p_conversation_id': _convId,
        'p_sender_id': _me,
        'p_body': text.isEmpty ? null : text,
        'p_idempotency_key': const Uuid().v4(),
        'p_attachment_id': ids.first,
      });
      _input.clear();
      await _loadMessages();
    } on MentorDeskException catch (e) {
      if (mounted) setState(() => _sendError = e.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _resolve() async {
    try {
      await ref.read(_serviceProvider).resolveDoubt(widget.requestId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked resolved.')));
      _init();
    } on MentorDeskException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _reopen() async {
    try {
      await ref.read(_serviceProvider).reopenDoubt(widget.requestId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reopened.')));
      _init();
    } on MentorDeskException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _rate(int stars) async {
    try {
      await ref.read(_serviceProvider).submitRating(requestId: widget.requestId, rating: stars);
      if (!mounted) return;
      setState(() { _canRate = false; _alreadyRated = true; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thanks for rating!')));
      _init();
    } on MentorDeskException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = MDTier.student;

    return Scaffold(
      backgroundColor: MDColors.ink50,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text('Doubt Conversation'),
            if (_doubt != null) ...[
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: _statusColor(_doubt!.status), shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Flexible(child: Text(_doubt!.statusLabel, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600))),
                ],
              ),
            ],
          ],
        ),
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _init)
              : Column(
                  children: [
                    Expanded(
                      child: _messages.isEmpty
                          ? const Center(child: Text('No messages yet. Start the conversation below.', style: TextStyle(color: MDColors.ink600)))
                          : ListView.builder(
                              padding: const EdgeInsets.all(kGutter),
                              itemCount: _messages.length,
                              itemBuilder: (context, i) {
                                final m = _messages[i];
                                return _Bubble(message: m, me: _me ?? '');
                              },
                            ),
                    ),
                    if (_canResolve || _canReopen || _canRate) _actionBar(),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(kGutter, 4, kGutter, kGutter),
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
                                maxLines: 4,
                                decoration: InputDecoration(
                                  hintText: 'Type a reply...',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(kRadiusSm),
                                    borderSide: BorderSide(color: MDColors.ink200.withValues(alpha: 0.3)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(kRadiusSm),
                                    borderSide: BorderSide(color: accent.solid, width: 1.6),
                                  ),
                                ),
                                onSubmitted: (_) => _send(),
                              ),
                            ),
                            const SizedBox(width: kGutter / 2),
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

  Widget _actionBar() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(kGutter),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.85),
        border: Border(top: BorderSide(color: MDColors.ink200.withValues(alpha: 0.2))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_canResolve)
            SizedBox(
              width: double.infinity,
              child: MDGlossOutlineButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Resolve this doubt?'),
                      content: const Text('The student will be able to rate the support once resolved.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                        ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Resolve')),
                      ],
                    ),
                  );
                  if (ok == true) _resolve();
                },
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_outline, size: 18),
                    SizedBox(width: 8),
                    Text('Mark resolved'),
                  ],
                ),
              ),
            ),
          if (_canReopen)
            SizedBox(
              width: double.infinity,
              child: MDGlossOutlineButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Reopen this doubt?'),
                      content: const Text('The conversation returns to the waiting queue for a mentor.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                        ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reopen')),
                      ],
                    ),
                  );
                  if (ok == true) _reopen();
                },
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.restore, size: 18),
                    SizedBox(width: 8),
                    Text('Reopen conversation'),
                  ],
                ),
              ),
            ),
          if (_canRate)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: kGutter),
                const Text('Rate this support (1–5 stars)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: kGutter / 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(5, (i) {
                    final stars = i + 1;
                    return IconButton(
                      icon: const Icon(Icons.star, color: MDColors.warning, size: 30),
                      onPressed: () => _rate(stars),
                    );
                  }),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'waiting': return MDColors.warning;
      case 'assigned': return MDColors.brand;
      case 'resolved': return MDColors.success;
      case 'closed': return MDColors.ink600;
      default: return MDColors.ink600;
    }
  }
}

class _Bubble extends StatelessWidget {
  final MessageRecord message;
  final String me;
  const _Bubble({required this.message, required this.me});
  @override
  Widget build(BuildContext context) {
    final mine = message.senderId == me;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 560),
        decoration: BoxDecoration(
          color: mine ? const Color(0xFF1A56DB) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: mine ? null : Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.body != null && message.body!.isNotEmpty)
              Text(message.body!, style: TextStyle(color: mine ? Colors.white : const Color(0xFF111827))),
            for (final a in message.attachments)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _AttachmentView(attachment: a),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}', style: TextStyle(color: mine ? const Color(0xFFBFDBFE) : const Color(0xFF9CA3AF), fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
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
  bool get _isApprovedImage => widget.attachment.type == 'image' && widget.attachment.status == 'approved';
  @override
  void initState() {
    super.initState();
    if (_isApprovedImage) _url = ref.read(_serviceProvider).signedUrl(widget.attachment.storagePath);
  }
  @override
  Widget build(BuildContext context) {
    final a = widget.attachment;
    if (a.type != 'image') return _stub(Icons.attach_file, a.fileName.isEmpty ? a.type : a.fileName);
    if (!_isApprovedImage) {
      final blocked = a.status == 'rejected' || a.status == 'blocked' || a.status == 'quarantined';
      return _stub(blocked ? Icons.block : Icons.shield_outlined, blocked ? 'Image blocked by safety review' : 'Image under safety review');
    }
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return _stub(Icons.image_outlined, 'Loading image...');
        if (!snap.hasData) return _stub(Icons.broken_image_outlined, 'Image unavailable');
        return ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(snap.data!, width: 220, fit: BoxFit.cover));
      },
    );
  }
  Widget _stub(IconData icon, String label) {
    return Container(width: 220, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(10)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 18, color: const Color(0xFF6B7280)), const SizedBox(width: 8), Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)), maxLines: 2, overflow: TextOverflow.ellipsis)]));
  }
}
