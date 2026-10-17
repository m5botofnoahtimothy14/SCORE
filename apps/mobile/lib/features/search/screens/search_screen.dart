import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../conversations/services/chat_service.dart';
import '../../../core/models/models.dart';

final _chatProvider = Provider<ChatService>(
  (ref) => ChatService(Supabase.instance.client),
);

/// Search within the user's own authorized conversations and notices.
/// Never queries outside RLS-visible rows.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _query = TextEditingController();
  List<MessageRecord> _results = [];
  bool _searching = false;
  String? _error;
  bool _searched = false;

  Future<void> _run() async {
    final q = _query.text.trim();
    if (q.length < 2) {
      setState(() {
        _error = 'Type at least 2 characters to search.';
        _searched = false;
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await ref.read(_chatProvider).searchMessages(q);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searched = true;
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Search failed. Check your connection.';
        _searching = false;
      });
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _query,
                    decoration: const InputDecoration(
                      hintText: 'Search your messages...',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: (_) => _run(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(onPressed: _searching ? null : _run, icon: const Icon(Icons.arrow_forward)),
              ],
            ),
          ),
          if (_searching) const LinearProgressIndicator(),
          Expanded(
            child: _error != null
                ? Center(child: Text(_error!, style: const TextStyle(color: Color(0xFF6B7280))))
                : !_searched
                    ? const Center(
                        child: Text('Search across your conversations.',
                            style: TextStyle(color: Color(0xFF9CA3AF))),
                      )
                    : _results.isEmpty
                        ? const Center(
                            child: Text('No messages found.',
                                style: TextStyle(color: Color(0xFF9CA3AF))),
                          )
                        : ListView.builder(
                            itemCount: _results.length,
                            itemBuilder: (context, i) {
                              final m = _results[i];
                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                child: ListTile(
                                  title: Text(m.body ?? '(attachment)',
                                      maxLines: 2, overflow: TextOverflow.ellipsis),
                                  subtitle: Text(m.createdAt.toLocal().toString().split('.').first,
                                      style: const TextStyle(fontSize: 12)),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => context.go('/conversations/${m.conversationId}'),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
