import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/services/auth_service.dart';
import '../../../core/widgets/states.dart';

/// Account + session info, notification settings entry, sign-out.
/// Never displays secrets; session expiry shown from the JWT itself.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _membership;
  String? _className;
  bool _loading = true;
  String? _error;

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
      final me = client.auth.currentUser!;
      final profile = await client.from('user_profiles').select().eq('id', me.id).maybeSingle();
      final membership = await client
          .from('school_memberships')
          .select('role, school_id, schools(name)')
          .eq('user_id', me.id)
          .eq('is_active', true)
          .order('joined_at', ascending: false)
          .limit(1)
          .maybeSingle();
      String? className;
      if (membership != null && (membership as Map)['role'] == 'student') {
        final s = await client
            .from('students')
            .select('id')
            .eq('user_id', me.id)
            .eq('school_id', (membership as Map)['school_id'])
            .maybeSingle();
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
      if (!mounted) return;
      setState(() {
        _profile = profile == null ? null : Map<String, dynamic>.from(profile as Map);
        _membership = membership == null ? null : Map<String, dynamic>.from(membership as Map);
        _className = className;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load profile. Check your connection.';
        _loading = false;
      });
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will stop receiving notifications on this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (confirm != true) return;
    await AuthService(Supabase.instance.client).signOut();
    if (mounted) context.go('/auth/school-select');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 32,
                              backgroundColor: const Color(0xFFEBF5FF),
                              child: Text(
                                ((_profile?['display_name'] as String?) ?? '?').substring(0, 1).toUpperCase(),
                                style: const TextStyle(
                                    fontSize: 28, color: Color(0xFF1A56DB), fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(_profile?['display_name'] as String? ?? 'Unknown',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(
                              '${(_membership?['role'] as String?)?.replaceAll('_', ' ') ?? ''}'
                              '${_className != null ? ' · $_className' : ''}',
                              style: const TextStyle(color: Color(0xFF6B7280)),
                            ),
                            Text(
                              (_membership?['schools'] as Map?)?['name'] as String? ?? '',
                              style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.notifications_outlined),
                            title: const Text('Notifications'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.go('/notification-settings'),
                          ),
                          const Divider(height: 1),
                          const ListTile(
                            leading: Icon(Icons.privacy_tip_outlined),
                            title: Text('Privacy'),
                            subtitle: Text(
                              'Your messages are visible only to conversation members and authorized safeguarding reviewers.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.info_outline),
                            title: const Text('Session'),
                            subtitle: Text(
                              Supabase.instance.client.auth.currentSession?.expiresAt != null
                                  ? 'Signed in · expires ${DateTime.fromMillisecondsSinceEpoch(Supabase.instance.client.auth.currentSession!.expiresAt! * 1000).toLocal()}'
                                  : 'Signed in',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.logout, color: Color(0xFFDC2626)),
                        label: const Text('Sign out', style: TextStyle(color: Color(0xFFDC2626))),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFFECACA)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _signOut,
                      ),
                    ),
                  ],
                ),
    );
  }
}
