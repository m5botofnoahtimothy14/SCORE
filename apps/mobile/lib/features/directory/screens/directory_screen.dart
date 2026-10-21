import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/identity_provider.dart';
import '../../../core/widgets/presence_dot.dart';
import '../../../core/widgets/states.dart';

/// Safe single-letter avatar initial (handles null/empty names).
String _initialOf(dynamic value) {
  final s = value?.toString().trim() ?? '';
  return s.isEmpty ? '?' : s.substring(0, 1).toUpperCase();
}

/// Directory of teachers the signed-in user is authorized to see.
/// RLS scopes this automatically: students see only their assigned
/// teachers, teachers see colleagues, nothing else.
///
/// Each row carries a presence dot driven by `teachers.last_seen_at`, and — for
/// students only — a Message button that opens (or creates) the personal 1:1
/// chat via the `start_teacher_conversation` RPC.
class DirectoryScreen extends ConsumerStatefulWidget {
  const DirectoryScreen({super.key});
  @override
  ConsumerState<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends ConsumerState<DirectoryScreen> {
  List<Map<String, dynamic>> _teachers = [];
  bool _loading = true;
  String? _error;
  String _query = '';

  /// Row id of the teacher whose chat is currently being opened, so only that
  /// button shows a spinner.
  String? _openingTeacherId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await Supabase.instance.client
          .from('teachers')
          .select('id, user_id, first_name, last_name, is_leadership, last_seen_at')
          .eq('is_active', true)
          .order('first_name') as List;
      if (!mounted) return;
      setState(() {
        _teachers = rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the directory. Check your connection.';
        _loading = false;
      });
    }
  }

  DateTime? _lastSeenOf(Map<String, dynamic> teacher) =>
      DateTime.tryParse(teacher['last_seen_at'] as String? ?? '');

  @override
  Widget build(BuildContext context) {
    // Only students may open a personal chat with a teacher. Staff see the
    // directory (presence is still useful) but get no Message affordance.
    final isStudent = ref.watch(identityProvider).valueOrNull?.isStudent ?? false;

    final filtered = _query.isEmpty
        ? _teachers
        : _teachers
            .where((t) => '${t['first_name']} ${t['last_name']}'.toLowerCase().contains(_query.toLowerCase()))
            .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Teachers')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(hintText: 'Search teachers...', prefixIcon: Icon(Icons.search)),
            ),
          ),
          Expanded(
            child: _loading
                ? const LoadingView()
                : _error != null
                    ? ErrorView(message: _error!, onRetry: _load)
                    : filtered.isEmpty
                        ? const EmptyView(
                            title: 'No teachers visible',
                            subtitle: 'Only teachers assigned to you appear here.',
                            icon: Icons.people_outline,
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: filtered.length,
                              itemBuilder: (context, i) {
                                final t = filtered[i];
                                final id = t['id'] as String?;
                                final opening = id != null && _openingTeacherId == id;
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: const Color(0xFFEBF5FF),
                                          child: Text(
                                            _initialOf(t['first_name']),
                                            style: const TextStyle(
                                                color: Color(0xFF1A56DB), fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        // The name and the presence line share
                                        // one flexible column, so the text always
                                        // wraps horizontally inside the space the
                                        // row leaves for it — never one letter
                                        // per line.
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                '${t['first_name'] ?? ''} ${t['last_name'] ?? ''}'.trim(),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.w600, fontSize: 15),
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Flexible(
                                                    child: PresenceDot(
                                                      lastSeen: _lastSeenOf(t),
                                                      labelStyle: TextStyle(
                                                        fontSize: 12.5,
                                                        fontWeight: FontWeight.w600,
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurface
                                                            .withValues(alpha: 0.75),
                                                      ),
                                                    ),
                                                  ),
                                                  if (t['is_leadership'] == true) ...[
                                                    const SizedBox(width: 8),
                                                    Flexible(
                                                      child: Text(
                                                        'School leadership',
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodySmall,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (isStudent) ...[
                                          const SizedBox(width: 8),
                                          OutlinedButton(
                                            onPressed: opening || id == null
                                                ? null
                                                : () => _openDirectChat(t),
                                            child: opening
                                                ? const SizedBox(
                                                    height: 16,
                                                    width: 16,
                                                    child: CircularProgressIndicator(strokeWidth: 2),
                                                  )
                                                : const Text('Message'),
                                          ),
                                        ],
                                      ],
                                    ),
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

  /// Opens (or creates) the student's personal 1:1 chat with this teacher.
  /// The server owns the authorization rules: it returns the existing thread
  /// when there is one, and rejects with `teacher_unavailable` /
  /// `not_a_member` / `not_authenticated` otherwise.
  Future<void> _openDirectChat(Map<String, dynamic> teacher) async {
    final teacherId = teacher['id'] as String?;
    if (teacherId == null) {
      _toast('This teacher has not activated their account yet.');
      return;
    }

    setState(() => _openingTeacherId = teacherId);
    try {
      final convId = await Supabase.instance.client
          .rpc('start_teacher_conversation', params: {'p_teacher_id': teacherId});
      if (!mounted) return;
      final id = convId as String?;
      if (id == null || id.isEmpty) {
        _toast('Could not open the chat. Try again.');
        return;
      }
      context.go('/conversations/$id');
    } catch (e) {
      if (mounted) _toast(_errorFor(e));
    } finally {
      if (mounted) setState(() => _openingTeacherId = null);
    }
  }

  String _errorFor(Object e) {
    final raw = e.toString();
    if (raw.contains('teacher_unavailable')) {
      return 'This teacher is not available for direct messages right now.';
    }
    if (raw.contains('not_a_member')) {
      return 'You are not a member of this school.';
    }
    if (raw.contains('not_authenticated')) {
      return 'Please sign in again to message a teacher.';
    }
    return 'Could not open chat. Try again.';
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
