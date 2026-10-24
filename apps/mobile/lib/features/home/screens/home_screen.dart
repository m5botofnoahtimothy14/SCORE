import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/layout/responsive.dart';
import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';

/// Role-aware dashboard. Each tier lands on Mentor Desk first — nothing more.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _openDoubts = 0;
  int _pendingSessions = 0;
  List<Map<String, dynamic>> _announcements = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadExtras());
  }

  Future<void> _loadExtras() async {
    try {
      final identity = await ref.read(identityProvider.future);
      final client = Supabase.instance.client;
      final me = identity.userId;
      final schoolId = identity.schoolId;

      // Open doubts for this student.
      int openDoubts = 0;
      if (identity.isStudent) {
        final rows = await client
            .from('doubt_requests')
            .select('id')
            .eq('student_id', me)
            .inFilter('status', ['waiting', 'assigned']);
        openDoubts = (rows as List).length;
      }

      // Unread announcements count.
      int unread = 0;
      try {
        final recips = await client
            .from('announcement_recipients')
            .select('id, acknowledged_at')
            .eq('user_id', me);
        for (final r in (recips as List)) {
          if ((r as Map)['acknowledged_at'] == null) unread++;
        }
      } catch (_) {}

      // Pending sessions needing mentor action.
      int pendingSessions = 0;
      if (!identity.isStudent) {
        final rows = await client
            .from('session_bookings')
            .select('id')
            .eq('school_id', schoolId)
            .eq('status', 'requested');
        pendingSessions = (rows as List).length;
      }

      List<Map<String, dynamic>> anns = const [];
      try {
        final recips = await client
            .from('announcement_recipients')
            .select('announcement_id, announcements!inner(id, title, body, category, published_at)')
            .eq('user_id', me)
            .order('announcement_id', ascending: false)
            .limit(3) as List;
        anns = recips
            .map((r) => Map<String, dynamic>.from((r as Map)['announcements'] as Map))
            .toList();
      } catch (_) {
        anns = const [];
      }

      if (!mounted) return;
      setState(() {
        _openDoubts = openDoubts;
        _pendingSessions = pendingSessions;
        _announcements = anns;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final identityAsync = ref.watch(identityProvider);

    return Scaffold(
      body: identityAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: e is IdentityException ? e.message : 'Could not load your dashboard.',
          onRetry: () => ref.invalidate(identityProvider),
        ),
        data: (identity) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(identityProvider);
            await ref.read(identityProvider.future);
            await _loadExtras();
          },
          child: _buildBody(identity),
        ),
      ),
    );
  }

  Widget _buildBody(AppIdentity identity) {
    final accent = TierAccent.of(identity.tier);
    return AdaptivePage(
      respectTopSafeArea: true,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'SCORE+ Mentor Desk',
                      style: Theme.of(context).appBarTheme.titleTextStyle,
                    ),
                  ),
                  IconButton(
                    onPressed: () => _loadExtras(),
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh',
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
            sliver: SliverToBoxAdapter(
              child: GlossHero(
                accent: accent,
                eyebrow: identity.schoolName.isEmpty ? identity.tier.label : identity.schoolName,
                title: _greeting(identity.displayName),
                subtitle: 'Your academic support desk — doubts, sessions and ratings.',
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(child: _metrics(identity, accent)),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(0, 18, 0, 0),
            sliver: SliverToBoxAdapter(
              child: SectionHeader(
                title: identity.tier == AppTier.student ? 'Your support' : 'Actions',
              ),
            ),
          ),
          SliverToBoxAdapter(child: _actions(identity, accent)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
            sliver: SliverToBoxAdapter(
              child: SectionHeader(
                title: 'Latest notices',
                actionLabel: 'See all',
                onAction: () => context.go('/announcements'),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 28),
            sliver: _announcements.isEmpty
                ? SliverToBoxAdapter(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Icon(Icons.campaign_outlined, size: 20, color: accent.solid),
                            const SizedBox(width: 10),
                            Text('No notices yet', style: Theme.of(context).textTheme.bodyMedium),
                          ],
                        ),
                      ),
                    ),
                  )
                : SliverList.separated(
                    itemCount: _announcements.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final a = _announcements[i];
                      final isAlert = a['category'] == 'priority_alert';
                      return Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          leading: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(11),
                              color: isAlert ? const Color(0xFFFEE2E2) : accent.soft,
                            ),
                            child: Icon(
                              isAlert ? Icons.warning_amber_rounded : Icons.campaign_outlined,
                              size: 20,
                              color: isAlert ? const Color(0xFFDC2626) : accent.onSoft,
                            ),
                          ),
                          title: Text(
                            (a['title'] ?? '').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            (a['body'] ?? '').toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.go('/announcements/${a['id']}'),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _greeting(String? name) {
    final h = DateTime.now().hour;
    final part = h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
    final n = (name ?? '').trim();
    return n.isEmpty ? part : '$part, ${n.split(' ').first}';
  }

  Widget _metrics(AppIdentity identity, TierAccent accent) {
    Widget grid(List<Widget> tiles) => AdaptiveGrid(
          minColumns: 2,
          itemExtent: 142,
          spacing: 10,
          children: tiles,
        );

    if (identity.isStudent) {
      return grid([
        MetricTile(
          icon: Icons.question_answer_outlined,
          label: 'Open doubts',
          value: '$_openDoubts',
          accent: accent,
          onTap: () => context.go('/mentor-desk'),
        ),
        MetricTile(
          icon: Icons.campaign_outlined,
          label: 'New notices',
          value: '${_announcements.length}',
          accent: accent,
          onTap: () => context.go('/announcements'),
        ),
      ]);
    }
    if (identity.isTeacher) {
      return grid([
        MetricTile(
          icon: Icons.list_outlined,
          label: 'Queue requests',
          value: '$_pendingSessions',
          accent: accent,
          onTap: () => context.go('/mentor-desk/queue'),
        ),
        MetricTile(
          icon: Icons.accessibility_outlined,
          label: 'Availability',
          value: 'Set status',
          accent: accent,
          onTap: () => context.go('/mentor-desk/availability'),
        ),
      ]);
    }
    return grid([
      MetricTile(
        icon: Icons.insights_outlined,
        label: 'SLT oversight',
        value: 'Live',
        accent: accent,
        onTap: () => context.go('/mentor-desk/slt'),
      ),
      MetricTile(
        icon: Icons.campaign_outlined,
        label: 'New notices',
        value: '${_announcements.length}',
        accent: accent,
        onTap: () => context.go('/announcements'),
      ),
    ]);
  }

  Widget _actions(AppIdentity identity, TierAccent accent) {
    final items = switch (identity.tier) {
      AppTier.student => <_Action>[
          _Action(Icons.support_agent_outlined, 'Mentor Desk', 'Ask doubts & book sessions',
              () => context.go('/mentor-desk')),
          _Action(Icons.forum_outlined, 'My Doubts', 'Open conversations & replies',
              () => context.go('/mentor-desk/doubt/submit')),
          _Action(Icons.schedule_outlined, 'Book a Session', 'Schedule mentor time',
              () => context.go('/mentor-desk/session/book')),
          _Action(Icons.rate_review_outlined, 'Give Feedback', 'Rate closed support',
              () => context.go('/mentor-desk/ratings')),
        ],
      AppTier.teacher => <_Action>[
          _Action(Icons.list_outlined, 'Mentor Queue', 'Waiting & assigned requests',
              () => context.go('/mentor-desk/queue')),
          _Action(Icons.accessibility_outlined, 'My Availability', 'Set Available / Away',
              () => context.go('/mentor-desk/availability')),
          _Action(Icons.schedule_outlined, 'My Sessions', 'Confirm & verify sessions',
              () => context.go('/mentor-desk/queue')),
          _Action(Icons.rate_review_outlined, 'Student Assessments', 'Private mentor notes',
              () => context.go('/mentor-desk/queue')),
        ],
      AppTier.leadership => <_Action>[
          _Action(Icons.insights_outlined, 'SLT Oversight', 'Whole-school Mentor Desk view',
              () => context.go('/mentor-desk/slt')),
          _Action(Icons.campaign_outlined, 'Send a notice', 'Reach your school',
              () => context.go('/announcements/compose')),
          _Action(Icons.announcement_outlined, 'All Notices', 'Published announcements',
              () => context.go('/announcements')),
        ],
    };

    return AdaptiveGrid(
      maxColumns: 2,
      itemExtent: 120,
      spacing: 8,
      children: [
        for (final a in items)
          Card(
            child: InkWell(
              onTap: a.onTap,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration:
                        BoxDecoration(borderRadius: BorderRadius.circular(11), color: accent.soft),
                    child: Icon(a.icon, size: 20, color: accent.onSoft),
                  ),
                  title: Text(a.title),
                  subtitle: Text(a.subtitle),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Action {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _Action(this.icon, this.title, this.subtitle, this.onTap);
}
