import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mentor_desk_design.dart';
import '../../../core/layout/responsive.dart';
import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/legal/eula_gate.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identityAsync = ref.watch(identityProviderProvider);
    final identity = identityAsync.valueOrNull;

    return Scaffold(
      backgroundColor: MDColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Profile', style: TextStyle(color: MDColors.ink900, fontWeight: FontWeight.w800)),
        centerTitle: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontalGutter(context),
            16,
            horizontalGutter(context),
            MediaQuery.of(context).padding.bottom + 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: MDColors.surfaceCard,
                  borderRadius: BorderRadius.circular(kRadiusLg),
                  border: Border.all(color: MDColors.ink200),
                  boxShadow: [
                    BoxShadow(color: MDColors.brand.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      identity?.displayName ?? 'User',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      identity?.subtitle ?? '',
                      style: TextStyle(fontSize: 13, color: MDColors.ink500),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      identity?.tier.label ?? '',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MDColors.brand),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _ProfileTile(
                icon: Icons.article_outlined,
                title: 'Terms & EULA',
                subtitle: 'End User Licence Agreement — registered under Indian law',
                onTap: () => context.go('/legal/eula'),
              ),
              const SizedBox(height: 10),
              _ProfileTile(
                icon: Icons.settings_outlined,
                title: 'Notification Settings',
                subtitle: 'Manage push notifications and alerts',
                onTap: () => context.go('/notification-settings'),
              ),
              const SizedBox(height: 10),
              _ProfileTile(
                icon: Icons.logout,
                title: 'Sign Out',
                subtitle: 'Sign out of this device',
                onTap: () async {
                  await Supabase.instance.client.auth.signOut();
                  context.go('/auth/role-select');
                },
              ),
              const SizedBox(height: 20),
              Text(
                'SCORE+™ · CRIMSON',
                style: TextStyle(
                  fontSize: 11,
                  color: MDColors.ink400,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
              Text(
                'Registered under the laws of India · Bengaluru, Karnataka',
                style: TextStyle(fontSize: 11, color: MDColors.ink400),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ProfileTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadiusSm),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: MDColors.surfaceCard,
            borderRadius: BorderRadius.circular(kRadiusSm),
            border: Border.all(color: MDColors.ink200),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: MDColors.brand.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: MDColors.brand, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: MDColors.ink900)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: MDColors.ink500)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: MDColors.ink400),
            ],
          ),
        ),
      ),
    );
  }
}

class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MDColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MDColors.ink900),
          onPressed: () => context.canPop() ? context.pop() : context.go("/home"),
        ),
        title: const Text('Notification Settings', style: TextStyle(color: MDColors.ink900, fontWeight: FontWeight.w800)),
        centerTitle: false,
      ),
      body: const Center(
        child: Text('Notification Settings', style: TextStyle(color: MDColors.ink500)),
      ),
    );
  }
}


