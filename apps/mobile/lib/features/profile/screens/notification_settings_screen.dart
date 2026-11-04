import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mentor_desk_design.dart';
import '../../../core/layout/responsive.dart';

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends ConsumerState<NotificationSettingsScreen> {
  bool _pushEnabled = true;
  bool _doubtReplies = true;
  bool _sessionUpdates = true;
  bool _announcements = true;
  bool _ratingReminders = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MDColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MDColors.ink900),
          onPressed: () => context.pop(),
        ),
        title: const Text('Notification Settings', style: TextStyle(color: MDColors.ink900, fontWeight: FontWeight.w800)),
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
              Text('Notification Preferences', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text('Control what notifications you receive.', style: TextStyle(fontSize: 14, color: MDColors.ink600)),
              const SizedBox(height: 24),
              _SettingsTile(
                icon: Icons.notifications,
                title: 'Push Notifications',
                subtitle: 'Enable or disable all push notifications',
                value: _pushEnabled,
                onChanged: (v) => setState(() { _pushEnabled = v; }),
              ),
              const SizedBox(height: 12),
              _SettingsTile(
                icon: Icons.forum,
                title: 'Doubt Replies',
                subtitle: 'New replies on your doubt requests',
                value: _doubtReplies,
                onChanged: (v) => setState(() { _doubtReplies = v; }),
              ),
              const SizedBox(height: 12),
              _SettingsTile(
                icon: Icons.schedule,
                title: 'Session Updates',
                subtitle: 'Session confirmations, changes, and reminders',
                value: _sessionUpdates,
                onChanged: (v) => setState(() { _sessionUpdates = v; }),
              ),
              const SizedBox(height: 12),
              _SettingsTile(
                icon: Icons.campaign,
                title: 'Announcements',
                subtitle: 'School-wide notices and announcements',
                value: _announcements,
                onChanged: (v) => setState(() { _announcements = v; }),
              ),
              const SizedBox(height: 12),
              _SettingsTile(
                icon: Icons.rate_review,
                title: 'Rating Reminders',
                subtitle: 'Reminders to rate completed support sessions',
                value: _ratingReminders,
                onChanged: (v) => setState(() { _ratingReminders = v; }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MDColors.surfaceCard,
        borderRadius: BorderRadius.circular(kRadiusSm),
        border: Border.all(color: MDColors.ink200),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
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
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: MDColors.brand,
          ),
        ],
      ),
    );
  }
}


