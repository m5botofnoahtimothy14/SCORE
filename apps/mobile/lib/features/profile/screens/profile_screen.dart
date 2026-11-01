import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/services/auth_service.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out of SCORE+?'),
        content: const Text('This device will stop receiving notifications for this account.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(authServiceProvider).signOut();
      ref.invalidate(identityProviderProvider);
      if (context.mounted) context.go('/auth/role-select');
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign-out failed. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(identityProviderProvider);
    final email = Supabase.instance.client.auth.currentUser?.email;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Profile')),
      body: identity.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Could not load your profile.')),
        data: (user) {
          if (user == null) {
            return const Center(child: Text('No active school account was found.'));
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.ink200),
                ),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: AppColors.brand.withValues(alpha: 0.10),
                      child: Text(
                        _initials(user.displayName),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.brand),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(user.displayName, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(user.tier.label, style: const TextStyle(color: AppColors.ink500, fontSize: 13)),
                    if (email != null) ...[
                      const SizedBox(height: 4),
                      Text(email, style: const TextStyle(color: AppColors.ink500, fontSize: 12)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _ProfileInfoCard(
                title: 'Account information',
                rows: [
                  ('Role', user.role.replaceAll('_', ' ')),
                  ('School', user.schoolName.isEmpty ? 'School account' : user.schoolName),
                  ('School ID', user.schoolId),
                  ('Account ID', user.userId),
                ],
              ),
              const SizedBox(height: 18),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.ink200)),
                tileColor: Colors.white,
                leading: const Icon(Icons.notifications_outlined, color: AppColors.brand),
                title: const Text('Notification settings'),
                subtitle: const Text('Manage school update alerts on this device'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/notification-settings'),
              ),
              const SizedBox(height: 22),
              OutlinedButton.icon(
                onPressed: () => _signOut(context, ref),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sign out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.danger),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return 'S+';
    return parts.take(2).map((part) => part[0].toUpperCase()).join();
  }
}

class _ProfileInfoCard extends StatelessWidget {
  const _ProfileInfoCard({required this.title, required this.rows});
  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.ink200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink900)),
          const SizedBox(height: 12),
          for (final row in rows) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 92, child: Text(row.$1, style: const TextStyle(fontSize: 12, color: AppColors.ink500))),
                Expanded(child: Text(row.$2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink700))),
              ],
            ),
            if (row != rows.last) const Divider(height: 18),
          ],
        ],
      ),
    );
  }
}

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends ConsumerState<NotificationSettingsScreen> {
  AuthorizationStatus? _status;
  bool _loading = true;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final status = await NotificationService.permissionStatus();
    if (!mounted) return;
    setState(() {
      _status = status;
      _loading = false;
    });
  }

  Future<void> _requestPermission() async {
    setState(() => _requesting = true);
    final status = await NotificationService.requestPermission();
    await NotificationService.registerCurrentDevice();
    if (!mounted) return;
    setState(() {
      _status = status;
      _requesting = false;
    });
  }

  String get _statusLabel {
    if (!NotificationService.pushEnabled) return 'Push service not configured';
    return switch (_status) {
      AuthorizationStatus.authorized => 'Enabled',
      AuthorizationStatus.provisional => 'Quiet delivery enabled',
      AuthorizationStatus.denied => 'Blocked in device settings',
      AuthorizationStatus.notDetermined => 'Not requested',
      null => 'Checking status',
    };
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _status == AuthorizationStatus.authorized ||
        _status == AuthorizationStatus.provisional;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Notification settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.ink200),
            ),
            child: Row(
              children: [
                Container(
                  height: 46,
                  width: 46,
                  decoration: BoxDecoration(
                    color: enabled ? AppColors.success.withValues(alpha: 0.10) : AppColors.ink100,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.notifications_active_outlined, color: enabled ? AppColors.success : AppColors.ink500),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('School notifications', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink900)),
                      const SizedBox(height: 4),
                      Text(_loading ? 'Checking device permission…' : _statusLabel, style: const TextStyle(fontSize: 12, color: AppColors.ink500)),
                    ],
                  ),
                ),
                if (!_loading && enabled)
                  const Icon(Icons.check_circle, color: AppColors.success),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'SCORE+ uses device notifications for school announcements and important account updates. Your school account and device must be active.',
            style: TextStyle(fontSize: 13, height: 1.55, color: AppColors.ink600),
          ),
          const SizedBox(height: 22),
          if (NotificationService.pushEnabled && _status != AuthorizationStatus.denied)
            FilledButton(
              onPressed: _loading || _requesting || enabled ? null : _requestPermission,
              child: _requesting
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(enabled ? 'Notifications enabled' : 'Enable notifications'),
            ),
          if (_status == AuthorizationStatus.denied)
            const Text(
              'Notifications are blocked by the device. Open your phone settings, find SCORE+, and allow notifications.',
              style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.ink500),
            ),
          if (!NotificationService.pushEnabled)
            const Text(
              'Push notification credentials are not configured in this app build. Other SCORE+ features can still work.',
              style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.ink500),
            ),
        ],
      ),
    );
  }
}
