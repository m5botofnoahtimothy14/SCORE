import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/states.dart';

/// Directory of teachers the signed-in user is authorized to see.
/// RLS scopes this automatically: students see only their assigned
/// teachers, teachers see colleagues, nothing else.
class DirectoryScreen extends StatefulWidget {
  const DirectoryScreen({super.key});
  @override
  State<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends State<DirectoryScreen> {
  List<Map<String, dynamic>> _teachers = [];
  bool _loading = true;
  String? _error;
  String _query = '';

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
          .select('user_id, first_name, last_name, is_leadership')
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

  @override
  Widget build(BuildContext context) {
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
                                return Card(
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: const Color(0xFFEBF5FF),
                                      child: Text(
                                        ((t['first_name'] as String?) ?? '?').substring(0, 1),
                                        style: const TextStyle(
                                            color: Color(0xFF1A56DB), fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    title: Text('${t['first_name']} ${t['last_name']}',
                                        style: const TextStyle(fontWeight: FontWeight.w600)),
                                    subtitle: t['is_leadership'] == true
                                        ? const Text('School leadership')
                                        : null,
                                    trailing: OutlinedButton(
                                      onPressed: () => _openDirectChat(t),
                                      child: const Text('Message'),
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

  /// Opens the existing 1:1 conversation if one exists; otherwise directs
  /// the student to the Teacher Support room (students cannot create chats).
  Future<void> _openDirectChat(Map<String, dynamic> teacher) async {
    final teacherUserId = teacher['user_id'] as String?;
    if (teacherUserId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This teacher has not activated their account yet.')),
        );
      }
      return;
    }
    try {
      final client = Supabase.instance.client;
      final me = client.auth.currentUser!.id;
      final mine = await client
          .from('conversation_members')
          .select('conversation_id, conversations!inner(id, type)')
          .eq('user_id', me)
          .isFilter('removed_at', null) as List;
      String? directId;
      for (final m in mine) {
        final c = (m as Map)['conversations'] as Map;
        if (c['type'] != 'student_teacher') continue;
        final other = await client
            .from('conversation_members')
            .select('user_id')
            .eq('conversation_id', c['id'])
            .eq('user_id', teacherUserId)
            .isFilter('removed_at', null)
            .maybeSingle();
        if (other != null) {
          directId = c['id'] as String;
          break;
        }
      }
      if (!mounted) return;
      if (directId != null) {
        context.go('/conversations/$directId');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No direct chat yet — ask via your Teacher Support conversation.'),
          ),
        );
        context.go('/conversations');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open chat. Try again.')),
        );
      }
    }
  }
}
