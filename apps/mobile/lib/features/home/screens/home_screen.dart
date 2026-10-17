import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/connectivity_service.dart';
import '../../../core/widgets/states.dart';

/// Home dashboard: membership, class, unread counts, latest announcements,
/// teacher-support entry point, quick links. All data from real backend.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _loading = true;
  String? _error;
  String? _displayName;
  String? _role;
  String? _schoolName;
  String? _className;
  int _unread = 0;
  List<Map<String, dynamic>> _announcements = [];
  String? _supportConvId;

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
      final client = Supabase.instance.client;
      final user = client.auth.currentUser!;
      final profile = await client.from('user_profiles').select().eq('id', user.id).maybeSingle();
      if (profile != null && (profile as Map)['is_active'] == false) {
        if (mounted) context.go('/suspended');
        return;
      }
      final membership = await client
          .from('school_memberships')
          .select('role, school_id, schools(name)')
          .eq('user_id', user.id)
          .eq('is_active', true)
          .order('joined_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (membership == null) {
        if (mounted) context.go('/access-denied');
        return;
      }
      final m = Map<String, dynamic>.from(membership as Map);
      final role = m['role'] as String;
      final schoolId = m['school_id'] as String;
      String? className;
      if (role == 'student') {
        final s = await client.from('students').select('id').eq('user_id', user.id).eq('school_id', schoolId).maybeSingle();
        if (s != null) {
          final enr = await client
              .from('class_enrollments')
              .select('classes(name)')
              .eq('student_id', (s as Map)['id'])
              .isFilter('unenrolled_at', null)
              .limit(1)
              .maybeSingle();
          if (enr != null) className = ((enr as Map)['classes'] as Map)['name'] as String?;
        }
      }
      // Unread estimate: messages newer than last_read per conversation
      final convMembers = await client
          .from('conversation_members')
          .select('conversation_id, last_read_at')
          .eq('user_id', user.id)
          .isFilter('removed_at', null) as List;
      int unread = 0;
      String? supportId;
      for (final cm in convMembers) {
        final c = Map<String, dynamic>.from(cm as Map);
        final cid = c['conversation_id'] as String;
        final lastRead = c['last_read_at'] as String?;
        var q = client.from('messages').select('id').eq('conversation_id', cid).neq('sender_id', user.id).eq('is_deleted', false);
        if (lastRead != null) q = q.gt('created_at', lastRead);
        unread += ((await q) as List).length;
        final conv = await client.from('conversations').select('type').eq('id', cid).maybeSingle();
        if (conv != null && (conv as Map)['type'] == 'student_support') supportId = cid;
      }
      // Latest announcements for this user
      List<Map<String, dynamic>> anns = [];
      try {
        final recips = await client
            .from('announcement_recipients')
            .select('announcement_id, announcements!inner(id, title, body, category, published_at)')
            .eq('user_id', user.id)
            .order('announcement_id', ascending: false)
            .limit(3) as List;
        anns = recips.map((r) => Map<String, dynamic>.from((r as Map)['announcements'] as Map)).toList();
      } catch (_) {
        anns = [];
      }
      if (!mounted) return;
      setState(() {
        _displayName = (profile as Map?)?['display_name'] as String?;
        _role = role;
        _schoolName = (m['schools'] as Map?)?['name'] as String?;
        _className = className;
        _unread = unread;
        _announcements = anns;
        _supportConvId = supportId;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your dashboard. Check your connection.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(isOnlineProvider).value ?? true;
    return Scaffold(
      appBar: AppBar(
        title: const Text('TeachCross'),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () => context.go('/search')),
          IconButton(icon: const Icon(Icons.notifications_outlined), onPressed: () => context.go('/notification-settings')),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const LoadingView()
            : _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (!online) const OfflineBanner(),
                      _HeaderCard(name: _displayName, role: _role, school: _schoolName, className: _className),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: _StatTile(icon: Icons.chat_bubble, label: 'Unread', value: '$_unread', onTap: () => context.go('/conversations'))),
                        const SizedBox(width: 12),
                        Expanded(child: _StatTile(icon: Icons.campaign, label: 'Notices', value: '${_announcements.length}', onTap: () => context.go('/announcements'))),
                      ]),
                      if (_supportConvId != null) ...[
                        const SizedBox(height: 12),
                        Card(
                          child: ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.support_agent)),
                            title: const Text('Teacher Support', style: TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: const Text('Ask your teaching team a question'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.go('/conversations/$_supportConvId'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Latest notices', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                          TextButton(onPressed: () => context.go('/announcements'), child: const Text('See all')),
                        ],
                      ),
                      if (_announcements.isEmpty)
                        const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No notices yet.', style: TextStyle(color: Color(0xFF6B7280))))),
                      for (final a in _announcements)
                        Card(
                          child: ListTile(
                            leading: Icon(
                              a['category'] == 'priority_alert' ? Icons.warning : Icons.campaign,
                              color: a['category'] == 'priority_alert' ? const Color(0xFFDC2626) : const Color(0xFF1A56DB),
                            ),
                            title: Text(a['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text((a['body'] ?? '').toString(),
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            onTap: () => context.go('/announcements/${a['id']}'),
                          ),
                        ),
                      const SizedBox(height: 16),
                      _QuickLinks(role: _role),
                    ],
                  ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final String? name;
  final String? role;
  final String? school;
  final String? className;
  const _HeaderCard({this.name, this.role, this.school, this.className});
  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1A56DB),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hello, ${name ?? 'there'}',
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('${_roleLabel(role)}${className != null ? ' · $className' : ''}\n${school ?? ''}',
                style: const TextStyle(color: Color(0xFFBFDBFE), fontSize: 13)),
          ],
        ),
      ),
    );
  }

  String _roleLabel(String? r) {
    switch (r) {
      case 'student':
        return 'Student';
      case 'teacher':
        return 'Teacher';
      case 'head_teacher':
        return 'Head Teacher';
      default:
        return r ?? '';
    }
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  const _StatTile({required this.icon, required this.label, required this.value, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, color: const Color(0xFF1A56DB)),
              const SizedBox(height: 8),
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              Text(label, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickLinks extends StatelessWidget {
  final String? role;
  const _QuickLinks({this.role});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _link(context, Icons.people_outline, 'Teacher directory', () => context.go('/directory')),
        _link(context, Icons.account_balance_outlined, 'School leadership', () => context.go('/leadership')),
        _link(context, Icons.person_outline, 'Profile & settings', () => context.go('/profile')),
      ],
    );
  }

  Widget _link(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return Card(
      child: ListTile(leading: Icon(icon), title: Text(label), trailing: const Icon(Icons.chevron_right), onTap: onTap),
    );
  }
}
