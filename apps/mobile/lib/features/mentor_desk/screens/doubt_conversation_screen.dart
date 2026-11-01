import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../models/mentor_desk_models.dart';
import '../services/mentor_desk_service.dart';

final _mentorServiceProvider = Provider((ref) => MentorDeskService(Supabase.instance.client));

class MentorDoubtConversationScreen extends ConsumerStatefulWidget {
  final String requestId;
  const MentorDoubtConversationScreen({super.key, required this.requestId});

  @override
  ConsumerState<MentorDoubtConversationScreen> createState() => _MentorDoubtConversationScreenState();
}

class _MentorDoubtConversationScreenState extends ConsumerState<MentorDoubtConversationScreen> {
  final _messageController = TextEditingController();
  DoubtRequest? _request;
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final service = ref.read(_mentorServiceProvider);
      final request = await service.getDoubtRequest(widget.requestId);
      if (request == null) throw Exception('Doubt request not found.');
      final rows = await service.client
          .from('messages')
          .select('id, sender_id, body, status, created_at')
          .eq('conversation_id', request.conversationId)
          .order('created_at');
      if (!mounted) return;
      setState(() {
        _request = request;
        _messages = (rows as List).map((row) => Map<String, dynamic>.from(row as Map)).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = 'Could not load this conversation. Check your access and connection.'; _loading = false; });
    }
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    final request = _request;
    if (text.isEmpty || request == null) return;
    setState(() { _sending = true; _error = null; });
    try {
      await ref.read(_mentorServiceProvider).replyDoubt(requestId: request.id, body: text);
      _messageController.clear();
      await _load();
    } on MentorDeskException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not send your reply. Please try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _changeStatus({required bool resolve}) async {
    final request = _request;
    if (request == null) return;
    try {
      final service = ref.read(_mentorServiceProvider);
      if (resolve) {
        await service.resolveDoubt(request.id);
      } else {
        await service.reopenDoubt(request.id);
      }
      await _load();
    } on MentorDeskException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not update this request.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(identityProviderProvider).valueOrNull;
    final request = _request;
    final myId = Supabase.instance.client.auth.currentUser?.id;
    final isStudent = identity?.tier == AppTier.student;
    final canReply = request != null && !request.isClosed && request.status != 'resolved';

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Doubt conversation'),
        actions: [
          IconButton(onPressed: _load, tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && request == null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : request == null
                  ? const Center(child: Text('Request not found.'))
                  : Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                          color: Colors.white,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(request.statusLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.accent))),
                                  if (request.urgent) const Chip(label: Text('URGENT'), backgroundColor: Color(0xFFFFE4E6), side: BorderSide.none, visualDensity: VisualDensity.compact),
                                ],
                              ),
                              Text(request.question, style: const TextStyle(fontSize: 15, height: 1.4, fontWeight: FontWeight.w700, color: AppColors.ink900)),
                              if (request.chapter != null && request.chapter!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(request.chapter!, style: const TextStyle(fontSize: 12, color: AppColors.ink500)),
                              ],
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _messages.length,
                              itemBuilder: (context, index) {
                                final message = _messages[index];
                                final mine = message['sender_id'] == myId;
                                final body = message['body']?.toString() ?? '';
                                final date = DateTime.tryParse(message['created_at']?.toString() ?? '');
                                return Align(
                                  alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                                  child: Container(
                                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                    decoration: BoxDecoration(
                                      color: mine ? AppColors.brand : Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: mine ? null : Border.all(color: AppColors.ink200),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(body, style: TextStyle(fontSize: 13, height: 1.45, color: mine ? Colors.white : AppColors.ink700)),
                                        const SizedBox(height: 5),
                                        Text(date == null ? '' : '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}', style: TextStyle(fontSize: 9, color: mine ? Colors.white70 : AppColors.ink400)),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        if (_error != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 11))),
                        if (request.isResolved && isStudent)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: OutlinedButton.icon(
                              onPressed: () => _changeStatus(resolve: false),
                              icon: const Icon(Icons.replay_rounded),
                              label: const Text('Reopen request'),
                            ),
                          ),
                        if (request.isOpen && !isStudent)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () => _changeStatus(resolve: true),
                                icon: const Icon(Icons.check_circle_outline),
                                label: const Text('Mark resolved'),
                              ),
                            ),
                          ),
                        if (canReply)
                          SafeArea(
                            top: false,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _messageController,
                                      minLines: 1,
                                      maxLines: 4,
                                      decoration: InputDecoration(
                                        hintText: 'Write a reply…',
                                        filled: true,
                                        fillColor: Colors.white,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton.filled(
                                    onPressed: _sending ? null : _send,
                                    icon: _sending ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded),
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
