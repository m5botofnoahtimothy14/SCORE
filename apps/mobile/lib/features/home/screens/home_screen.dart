import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(identityProviderProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: identity.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _HomeMessage(
            title: 'Your dashboard is not available',
            message: 'We could not load your account details. Check your connection and try again.',
            actionLabel: 'Retry',
            onAction: () => ref.invalidate(identityProviderProvider),
          ),
          data: (user) {
            if (user == null) {
              return _HomeMessage(
                title: 'Account setup is incomplete',
                message: 'Your school account is not linked to an active membership. Contact your school administrator.',
                actionLabel: 'Refresh',
                onAction: () => ref.invalidate(identityProviderProvider),
              );
            }
            return _DashboardContent(user: user);
          },
        ),
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({required this.user});
  final AppIdentity user;

  @override
  Widget build(BuildContext context) {
    final actions = _actionsFor(user.tier);
    final greeting = user.displayName.trim().isEmpty ? 'Welcome' : 'Welcome, ${user.displayName.trim()}';

    return RefreshIndicator(
      onRefresh: () async {
        // Rebuilding the provider refreshes the account context without changing server data.
        await Future<void>.delayed(const Duration(milliseconds: 250));
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        children: [
          Row(
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: AppColors.brand,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Text('S+', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SCORE+', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink900, letterSpacing: 0.3)),
                    Text('School community platform', style: TextStyle(fontSize: 12, color: AppColors.ink500)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Search features',
                onPressed: () => context.go('/search'),
                icon: const Icon(Icons.search_rounded),
              ),
              IconButton(
                tooltip: 'Profile',
                onPressed: () => context.go('/profile'),
                icon: const Icon(Icons.account_circle_outlined),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text(greeting, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text(
            '${user.subtitle}  ·  ${user.schoolName.isEmpty ? 'SCORE+ account' : user.schoolName}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.ink500),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(color: AppColors.brand.withValues(alpha: 0.14), blurRadius: 24, offset: const Offset(0, 10)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.tier.label.toUpperCase(), style: const TextStyle(color: Color(0xFFBBD3F8), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
                const SizedBox(height: 10),
                const Text('Your school.\nConnected.', style: TextStyle(color: Colors.white, fontSize: 25, height: 1.12, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Text(
                  _descriptionFor(user.tier),
                  style: const TextStyle(color: Color(0xFFD8E4F5), fontSize: 13, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('QUICK ACCESS', style: Theme.of(context).textTheme.labelLarge?.copyWith(letterSpacing: 1.1, color: AppColors.ink500)),
              Text('${actions.length} tools', style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
          const SizedBox(height: 12),
          GridView.builder(
            itemCount: actions.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 148,
            ),
            itemBuilder: (context, index) {
              final item = actions[index];
              return _ActionCard(
                icon: item.icon,
                title: item.title,
                subtitle: item.subtitle,
                color: item.color,
                onTap: () => context.go(item.route),
              );
            },
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.ink200),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_outlined, color: AppColors.success, size: 21),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Account access is role-based', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink900)),
                      SizedBox(height: 4),
                      Text('SCORE+ shows tools that match your school role. Keep your sign-in details private.', style: TextStyle(fontSize: 12, height: 1.45, color: AppColors.ink500)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _descriptionFor(AppTier tier) => switch (tier) {
    AppTier.student => 'Open your learning tools, ask curriculum questions and connect with your school support team.',
    AppTier.teacher => 'Manage support requests, set availability and keep up with school announcements.',
    AppTier.leadership => 'Review school operations, oversee Mentor Desk activity and publish school updates.',
  };

  static List<_HomeAction> _actionsFor(AppTier tier) => switch (tier) {
    AppTier.student => const [
      _HomeAction('AI Ask', 'Curriculum-based help', Icons.auto_awesome_outlined, '/ai-ask', AppColors.accent),
      _HomeAction('Mentor Desk', 'Ask for teacher support', Icons.support_agent_outlined, '/mentor-desk', AppColors.studentTier),
      _HomeAction('Announcements', 'School notices', Icons.campaign_outlined, '/announcements', AppColors.teacherTier),
      _HomeAction('Explore', 'Find SCORE+ tools', Icons.grid_view_rounded, '/search', AppColors.leadershipTier),
    ],
    AppTier.teacher => const [
      _HomeAction('Mentor Queue', 'Review student requests', Icons.inbox_outlined, '/mentor-desk/queue', AppColors.teacherTier),
      _HomeAction('Availability', 'Manage session times', Icons.event_available_outlined, '/mentor-desk/availability', AppColors.accent),
      _HomeAction('Announcements', 'School notices', Icons.campaign_outlined, '/announcements', AppColors.studentTier),
      _HomeAction('Explore', 'Find SCORE+ tools', Icons.grid_view_rounded, '/search', AppColors.leadershipTier),
    ],
    AppTier.leadership => const [
      _HomeAction('Leadership', 'School oversight', Icons.insights_outlined, '/mentor-desk/slt', AppColors.leadershipTier),
      _HomeAction('Mentor Desk', 'Support operations', Icons.support_agent_outlined, '/mentor-desk', AppColors.teacherTier),
      _HomeAction('Announcements', 'Publish school notices', Icons.campaign_outlined, '/announcements', AppColors.studentTier),
      _HomeAction('Explore', 'Find SCORE+ tools', Icons.grid_view_rounded, '/search', AppColors.accent),
    ],
  };
}

class _HomeAction {
  const _HomeAction(this.title, this.subtitle, this.icon, this.route, this.color);
  final String title;
  final String subtitle;
  final IconData icon;
  final String route;
  final Color color;
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.icon, required this.title, required this.subtitle, required this.color, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: AppColors.ink200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 38,
                width: 38,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.ink900)),
              const SizedBox(height: 3),
              Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, height: 1.3, color: AppColors.ink500)),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeMessage extends StatelessWidget {
  const _HomeMessage({required this.title, required this.message, this.actionLabel, this.onAction});
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_circle_outlined, size: 48, color: AppColors.ink400),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
