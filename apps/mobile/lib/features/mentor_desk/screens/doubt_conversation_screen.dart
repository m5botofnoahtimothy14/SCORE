import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mentor_desk_design.dart';
import '../../../core/layout/responsive.dart';
import '../../../core/widgets/states.dart';
import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../models/mentor_desk_models.dart';
import '../services/mentor_desk_service.dart';

final mentorDeskServiceProvider = Provider<MentorDeskService>((ref) {
  return MentorDeskService(Supabase.instance.client);
});

class MentorDoubtConversationScreen extends ConsumerStatefulWidget {
  final String requestId;
  const MentorDoubtConversationScreen({super.key, required this.requestId});

  @override
  ConsumerState<MentorDoubtConversationScreen> createState() => _MentorDoubtConversationScreenState();
}

class _MentorDoubtConversationScreenState extends ConsumerState<MentorDoubtConversationScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  bool _loading = true;
  String? _error;
  DoubtRequest? _doubt;
  List<DoubtMessage> _messages = [];
  List<File> _newImages = [];
  String? _schoolId;
  String? _myUserId;
  AppTier? _myTier;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final identity = await ref.read(identityProviderProvider.future);
      if (identity == null) throw Exception('No identity found');
      _schoolId = identity.schoolId;
      _myUserId = identity.userId;
      _myTier = identity.tier;

      final service = ref.read(mentorDeskServiceProvider);
      _doubt = await service.getDoubtRequest(widget.requestId);
      if (_doubt == null) throw Exception('Doubt request not found');

      // Load messages via the messages table (doubt_requests.conversation_id links them)
      final rows = await Supabase.instance.client
          .from('messages')
          .select('id, conversation_id, sender_id, body, status, created_at, updated_at')
          .eq('conversation_id', _doubt!.conversationId)
          .order('created_at', ascending: true);
      _messages = (rows as List)
          .map((r) => DoubtMessage.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();

      if (!mounted) return;
      setState(() { _loading = false; });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickImage() async {
    if (_newImages.length >= MentorDeskService.maxAttachments) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('You can attach up to 4 images.'),
        backgroundColor: MDColors.warning,
      ));
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (picked != null) {
      setState(() { _newImages.add(File(picked.path)); });
    }
  }

  void _removeImage(int index) {
    setState(() { _newImages.removeAt(index); });
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty && _newImages.isEmpty) return;
    if (_myUserId == null || _schoolId == null) return;

    setState(() { _loading = true; });
    try {
      final service = ref.read(mentorDeskServiceProvider);

      // Upload images first
      List<String> attachmentIds = [];
      if (_newImages.isNotEmpty) {
        attachmentIds = await service.uploadImages(
          schoolId: _schoolId!,
          conversationId: widget.requestId,
          files: _newImages,
        );
        _newImages.clear();
      }

      await service.replyDoubt(
        requestId: widget.requestId,
        body: _messageController.text.trim().isEmpty ? 'Attachment shared' : _messageController.text.trim(),
        attachmentId: attachmentIds.isNotEmpty ? attachmentIds.first : null,
      );

      _messageController.clear();
      if (!mounted) return;
      setState(() { _loading = false; });
      await _load();
    } on MentorDeskException catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.message; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MDColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MDColors.ink900),
          onPressed: () => context.canPop() ? context.pop() : context.go("/home"),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Doubt Conversation', style: TextStyle(color: MDColors.ink900, fontWeight: FontWeight.w800)),
            if (_doubt != null)
              Text(
                _doubt!.status.replaceAll('_', ' '),
                style: TextStyle(fontSize: 11, color: MDColors.ink400, fontWeight: FontWeight.w600),
              ),
          ],
        ),
        centerTitle: false,
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : Column(
                  children: [
                    Expanded(
                      child: _messages.isEmpty
                          ? const Center(
                              child: Text('No messages yet. Start the conversation.', style: TextStyle(color: MDColors.ink500)),
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              padding: EdgeInsets.fromLTRB(
                                horizontalGutter(context),
                                10,
                                horizontalGutter(context),
                                MediaQuery.of(context).padding.bottom + 16,
                              ),
                              itemCount: _messages.length,
                              itemBuilder: (context, index) {
                                final msg = _messages[index];
                                final isMine = msg.senderId == _myUserId;
                                return _MessageBubble(
                                  message: msg,
                                  isMine: isMine,
                                  tier: _myTier ?? AppTier.student,
                                );
                              },
                            ),
                    ),
                    _buildComposer(context),
                  ],
                ),
    );
  }

  Widget _buildComposer(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        horizontalGutter(context),
        10,
        horizontalGutter(context),
        MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: BoxDecoration(
        color: MDColors.surfaceCard,
        border: Border(top: BorderSide(color: MDColors.ink200)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (_newImages.isNotEmpty)
              SizedBox(
                height: 60,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _newImages.length,
                  itemBuilder: (context, index) {
                    return Stack(
                      children: [
                        Container(
                          width: 60, height: 60,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(kRadiusSm),
                            border: Border.all(color: MDColors.ink200),
                            image: DecorationImage(image: FileImage(_newImages[index]), fit: BoxFit.cover),
                          ),
                        ),
                        Positioned(
                          top: 2, right: 2,
                          child: GestureDetector(
                            onTap: () => _removeImage(index),
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(color: MDColors.danger, shape: BoxShape.circle),
                              child: const Icon(Icons.close, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            Expanded(
              child: MDGlossInput(
                controller: _messageController,
                hint: 'Type a message…',
                maxLines: 4,
                                textInputAction: TextInputAction.send,
                onSubmitted: _sendMessage,
              ),
            ),
            const SizedBox(width: 10),
            if (_newImages.isEmpty)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [MDColors.brand, MDColors.accent]),
                  borderRadius: BorderRadius.circular(kRadiusSm),
                  boxShadow: [
                    BoxShadow(color: MDColors.brand.withValues(alpha: 0.45), blurRadius: 12, offset: const Offset(0, 4)),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: _sendMessage,
                ),
              )
            else
              MDButton(
                onPressed: _pickImage,
                fullWidth: false,
                height: 44,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [Icon(Icons.add_a_photo, size: 16), SizedBox(width: 6), Text('Image', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final DoubtMessage message;
  final bool isMine;
  final AppTier tier;

  const _MessageBubble({required this.message, required this.isMine, required this.tier});

  @override
  Widget build(BuildContext context) {
    final accent = TierAccent.of(tier);
    final alignment = isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
            decoration: BoxDecoration(
              color: isMine ? accent.solid : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: isMine ? const Radius.circular(16) : Radius.zero,
                bottomRight: isMine ? Radius.zero : const Radius.circular(16),
              ),
              border: isMine ? null : Border.all(color: MDColors.ink200),
              boxShadow: isMine
                  ? [BoxShadow(color: accent.solid.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))]
                  : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.body.isNotEmpty)
                  Text(
                    message.body,
                    style: TextStyle(
                      fontSize: 14,
                      color: isMine ? Colors.white : MDColors.ink900,
                      height: 1.4,
                    ),
                  ),
                if (message.attachmentUrl != null && message.attachmentUrl!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      message.attachmentUrl!,
                      width: 160,
                      height: 120,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          width: 160, height: 120,
                          color: MDColors.ink100,
                          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTime(message.createdAt),
                      style: TextStyle(
                        fontSize: 10,
                        color: isMine ? Colors.white.withValues(alpha: 0.75) : MDColors.ink400,
                      ),
                    ),
                    if (!isMine && message.readAt != null) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.done_all, size: 12, color: MDColors.success),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '';
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inDays == 0) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
    return '${time.day}/${time.month}';
  }
}


