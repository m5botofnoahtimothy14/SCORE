import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';

/// Teacher surface: student support questions this teacher can act on.
/// A teacher can move a request through its lifecycle — this is the
/// "slightly elevated control" teachers get, scoped to their own conversations.
class SupportQueueScreen extends ConsumerStatefulWidget {
  const SupportQueueScreen({super.key});

  @override
  ConsumerState<SupportQueueScreen> createState() => _SupportQueueScreenState();
}

class _SupportQueueScreenState extends ConsumerState<SupportQueueScreen> {
  bool _loading = true;
  String? _error;
  String _filter = 'open';
  final Map<String, Map<String, dynamic>> _questions = {};

  static const _statuses = <String>['open', 'in_progress', 'resolved', 'closed'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final identity = await ref.read(identityProvider.future);
      final client = Supabase.instance.client;

      // Support questions live on conversations this teacher belongs to.
      final memberships = await client
          .from('conversation_members')
          .select('conversation_id')
          .eq('user_id', identity.userId)
          .isFilter('removed_at', null);
      final convIds = (memberships as List)
          .map((m) => (m as Map)['conversation_id'] as String)
          .whereType<String>()
          .toList();

      if (convIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _questions.clear();
          _loading = false;
        });
        return;
      }

      final rows = await client
          .from('support_questions')
          .select('id, conversation_id, student_id, status, created_at, updated_at')
          .inFilter('conversation_id', convIds)
          .eq('status', _filter)
          .order('created_at', ascending: false)
          .limit(100);

      final map = <String, Map<String, dynamic>>{};
      for (final r in (rows as List)) {
        final m = Map<String, dynamic>.from(r as Map);
        map[m['conversation_id'] as String] = m;
      }

      if (!mounted) return;
      setState(() {
        _questions
          ..clear()
          ..addAll(map);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is IdentityException ? e.message : 'Could not load support requests.';
        _loading = false;
      });
    }
  }

  Future<void> _setStatus(String questionId, String status) async {
    try {
      final client = Supabase.instance.client;
      final identity = await ref.read(identityProvider.future);
      final res = await client
          .from('support_questions')
          .update({'status': status})
          .eq('id', questionId);
      final err = res.error;
      if (err != null) throw err;

      await client.from('support_question_history').insert({
        'question_id': questionId,
        'changed_by': identity.userId,
        'to_status': status,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Marked as ${status.replaceAll('_', ' ')}.')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is IdentityException ? e.message : 'Could not update.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = TierAccent.of(AppTier.teacher);
    final entries = _questions.entries.toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Student Requests')),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: Column(
                    children: [
                      SizedBox(
                        height: 36,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          children: [
                            for (final s in _statuses)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: InkWell(
                                  onTap: () {
                                    setState(() => _filter = s);
                                    _load();
                                  },
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      color: _filter == s ? accent.soft : Colors.transparent,
                                      border: Border.all(
                                        color: _filter == s
                                            ? accent.solid.withValues(alpha: 0.35)
                                            : Theme.of(context).dividerColor,
                                      ),
                                    ),
                                    child: Text(
                                      s.replaceAll('_', ' '),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _filter == s
                                            ? accent.onSoft
                                            : Theme.of(context).colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: entries.isEmpty
                            ? ListView(
                                children: [
                                  const SizedBox(height: 40),
                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(28),
                                      child: Column(
                                        children: [
                                          Icon(Icons.inbox_outlined,
                                              size: 44, color: accent.solid.withValues(alpha: 0.5)),
                                          const SizedBox(height: 12),
                                          Text(
                                            'No ${_filter.replaceAll('_', ' ')} requests',
                                            style: Theme.of(context).textTheme.titleMedium,
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'Student questions from your classes appear here.',
                                            textAlign: TextAlign.center,
                                            style: Theme.of(context).textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                                itemCount: entries.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (context, i) {
                                  final e = entries[i];
                                  final status = (e.value['status'] as String?) ?? 'open';
                                  return Card(
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  'Support conversation',
                                                  style: Theme.of(context).textTheme.titleMedium,
                                                ),
                                              ),
                                              _StatusPill(status: status, accent: accent),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Opened ${_relative(e.value['created_at'] as String?)}',
                                            style: Theme.of(context).textTheme.bodySmall,
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              TextButton.icon(
                                                onPressed: () => context.go('/conversations/${e.key}'),
                                                icon: const Icon(Icons.forum_outlined, size: 18),
                                                label: const Text('Open chat'),
                                              ),
                                              const Spacer(),
                                              if (status == 'open')
                                                TextButton(
                                                  onPressed: () => _setStatus(e.value['id'] as String, 'in_progress'),
                                                  child: const Text('Start'),
                                                ),
                                              if (status == 'in_progress')
                                                TextButton(
                                                  onPressed: () => _setStatus(e.value['id'] as String, 'resolved'),
                                                  child: const Text('Resolve'),
                                                ),
                                              if (status == 'resolved')
                                                TextButton(
                                                  onPressed: () => _setStatus(e.value['id'] as String, 'closed'),
                                                  child: const Text('Close'),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
    );
  }

  static String _relative(String? iso) {
    if (iso == null) return 'recently';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return 'recently';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  final TierAccent accent;
  const _StatusPill({required this.status, required this.accent});

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg) = switch (status) {
      'resolved' => (const Color(0xFF047857), const Color(0xFFECFDF5)),
      'closed' => (const Color(0xFF475569), const Color(0xFFF1F5F9)),
      'in_progress' => (const Color(0xFFB45309), const Color(0xFFFFFBEB)),
      _ => (accent.onSoft, accent.soft),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(7)),
      child: Text(
        status.replaceAll('_', ' '),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}