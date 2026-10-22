import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/layout/responsive.dart';
import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';

/// Search across the user's own Mentor Desk doubts and sessions.
/// Never queries outside RLS-visible rows.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchResult {
  final String type; // 'doubt' | 'session'
  final String id;
  final String title;
  final String subtitle;
  final String route;
  const _SearchResult({
    required this.type,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.route,
  });
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _query = TextEditingController();
  List<_SearchResult> _results = [];
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
      final identity = await ref.read(identityProvider.future);
      final client = Supabase.instance.client;
      final me = identity.userId;

      final List<_SearchResult> results = [];

      // Search doubts.
      final doubtRows = await client
          .from('doubt_requests')
          .select('id, question, status, created_at')
          .eq('student_id', me)
          .ilike('question', '%$q%')
          .order('created_at', ascending: false);
      for (final r in (doubtRows as List)) {
        final m = Map<String, dynamic>.from(r as Map);
        results.add(_SearchResult(
          type: 'doubt',
          id: m['id'] as String,
          title: (m['question'] as String?) ?? 'Doubt',
          subtitle: 'Doubt · ${(m['status'] as String?) ?? ''}',
          route: '/mentor-desk/doubt/${m['id']}',
        ));
      }

      // Search sessions.
      final sessionRows = await client
          .from('session_bookings')
          .select('id, topic, status, created_at')
          .eq('student_id', me)
          .ilike('topic', '%$q%')
          .order('created_at', ascending: false);
      for (final r in (sessionRows as List)) {
        final m = Map<String, dynamic>.from(r as Map);
        results.add(_SearchResult(
          type: 'session',
          id: m['id'] as String,
          title: (m['topic'] as String?) ?? 'Session',
          subtitle: 'Session · ${(m['status'] as String?) ?? ''}',
          route: '/mentor-desk/session/${m['id']}',
        ));
      }

      results.sort((a, b) => a.title.compareTo(b.title));

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
                      hintText: 'Search your doubts & sessions...',
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
                        child: Text('Search across your doubts and sessions.',
                            style: TextStyle(color: Color(0xFF9CA3AF))),
                      )
                    : _results.isEmpty
                        ? const Center(
                            child: Text('No matches found.',
                                style: TextStyle(color: Color(0xFF9CA3AF))),
                          )
                        : ListView.builder(
                            itemCount: _results.length,
                            itemBuilder: (context, i) {
                              final m = _results[i];
                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: ListTile(
                                  title: Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                                  subtitle: Text(m.subtitle,
                                      style: const TextStyle(fontSize: 12)),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => context.go(m.route),
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
