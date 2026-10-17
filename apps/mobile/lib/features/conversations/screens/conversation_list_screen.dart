import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/chat_service.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/states.dart';

final _chatProvider = Provider<ChatService>(
  (ref) => ChatService(Supabase.instance.client),
);

/// List of the user's authorized conversations with unread badges.
/// Realtime updates via Postgres changes subscription (RLS-enforced).
class ConversationListScreen extends ConsumerStatefulWidget {
  const ConversationListScreen({super.key});
  @override
  ConsumerState<ConversationListScreen> createState() => _ConversationListScreenState();
}

class _ConversationListScreenState extends ConsumerState<ConversationListScreen> {
  List<ConversationRecord> _convs = [];
  List<ConversationRecord> _filtered = [];
  bool _loading = true;
  String? _error;
  final _search = TextEditingController();
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _search.dispose();
    super.dispose();
  }

  void _subscribe() {
    final client = Supabase.instance.client;
    _channel = client.channel('conv-list')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        callback: (_) => _load(silent: true),
      )
      ..subscribe();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final convs = await ref.read(_chatProvider).listConversations();
      if (!mounted) return;
      setState(() {
        _convs = convs;
        _applyFilter();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load conversations. Check your connection.';
        _loading = false;
      });
    }
  }

  void _applyFilter() {
    final q = _search.text.toLowerCase();
    _filtered = q.isEmpty
        ? _convs
        : _convs.where((c) => c.displayTitle().toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(_applyFilter),
              decoration: const InputDecoration(hintText: 'Search conversations...', prefixIcon: Icon(Icons.search)),
            ),
          ),
          Expanded(
            child: _loading
                ? const LoadingView()
                : _error != null
                    ? ErrorView(message: _error!, onRetry: _load)
                    : _filtered.isEmpty
                        ? EmptyView(
                            title: _convs.isEmpty ? 'No conversations yet' : 'No matches',
                            subtitle: _convs.isEmpty
                                ? 'Your conversations with teachers will appear here.'
                                : 'Try a different search.',
                            icon: Icons.chat_bubble_outline,
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              itemCount: _filtered.length,
                              itemBuilder: (context, i) {
                                final c = _filtered[i];
                                return Card(
                                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: const Color(0xFFEBF5FF),
                                      child: Icon(_iconFor(c.type), color: const Color(0xFF1A56DB)),
                                    ),
                                    title: Text(c.displayTitle(),
                                        style: const TextStyle(fontWeight: FontWeight.w600)),
                                    subtitle: Text(
                                      c.lastMessageBody ?? 'No messages yet',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: c.unreadCount > 0
                                        ? Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF1A56DB),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text('${c.unreadCount}',
                                                style: const TextStyle(color: Colors.white, fontSize: 12)),
                                          )
                                        : null,
                                    onTap: () => context.go('/conversations/${c.id}'),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'student_support':
        return Icons.support_agent;
      case 'class_channel':
        return Icons.groups_outlined;
      case 'staff':
        return Icons.work_outline;
      case 'leadership':
        return Icons.account_balance_outlined;
      default:
        return Icons.person_outline;
    }
  }
}
