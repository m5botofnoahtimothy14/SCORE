import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/layout/responsive.dart';
import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';

/// Role-aware dashboard. A student, a teacher and a leader each get a home
/// screen built from what their tier can actually do — nothing more.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _unread = 0;
  int _pendingRequests = 0;
  List<Map<String, dynamic>> _announcements = const [];
  String? _supportConvId;
  bool _loadingExtras = true;

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

      final convMembers = await client
          .from('conversation_members')
          .select('conversation_id, last_read_at')
          .eq('user_id', me)
          .isFilter('removed_at', null) as List;

      int unread = 0;
      String? supportId;
      for (final cm in convMembers) {
        final c = Map<String, dynamic>.from(cm as Map);
        final cid = c['conversation_id'] as String;
        final lastRead = c['last_read_at'] as String?;
        var q = client
            .from('messages')
            .select('id')
            .eq('conversation_id', cid)
            .neq('sender_id', me)
            .eq('is_deleted', false);
        if (lastRead != null) q = q.gt('created_at', lastRead);
        unread += ((await q) as List).length;
        final conv =
            await client.from('conversations').select('type').eq('id', cid).maybeSingle();
        if (conv != null && (conv as Map)['type'] == 'student_support') supportId = cid;
      }

      int pending = 0;
      if (identity.tier != AppTier.student && supportId != null) {
        final rows = await client
            .from('support_questions')
            .select('id')
            .eq('conversation_id', supportId)
            .inFilter('status', ['open', 'in_progress']);
        pending = (rows as List).length;
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
        _unread = unread;
        _pendingRequests = pending;
        _announcements = anns;
        _supportConvId = supportId;
        _loadingExtras = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingExtras = false);
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
      // No app bar on this screen, so the notch/status bar is ours to avoid.
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
                      'TeachCross',
                      style: Theme.of(context).appBarTheme.titleTextStyle,
                    ),
                  ),
                  IconButton(
                    onPressed: () => context.go('/search'),
                    icon: const Icon(Icons.search),
                    tooltip: 'Search',
                  ),
                  IconButton(
                    onPressed: () => context.go('/notification-settings'),
                    icon: const Icon(Icons.notifications_none_rounded),
                    tooltip: 'Notification settings',
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
                subtitle: identity.subtitle,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
            sliver: SliverToBoxAdapter(child: _metrics(identity, accent)),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(0, 18, 0, 0),
            sliver: SliverToBoxAdapter(
              child: SectionHeader(
                title: identity.tier == AppTier.student ? 'Your classroom' : 'Actions',
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
    // Two tiles always; `minColumns` keeps them paired on a phone exactly as
    // before, and the grid simply stops splitting them on wider screens.
    Widget grid(List<Widget> tiles) => AdaptiveGrid(
          minColumns: 2,
          // Room for the tallest possible tile: icon + number + a two-line
          // label. Anything shorter would clip, anything taller just breathes.
          itemExtent: 142,
          spacing: 10,
          children: tiles,
        );

    if (identity.tier == AppTier.student) {
      return grid([
        MetricTile(
          icon: Icons.mark_chat_unread_outlined,
          label: 'Unread messages',
          value: '$_unread',
          accent: accent,
          onTap: () => context.go('/conversations'),
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
    if (identity.tier == AppTier.teacher) {
      return grid([
        MetricTile(
          icon: Icons.people_alt_outlined,
          label: 'My students',
          value: _loadingExtras ? '—' : '${identity.classIds.length} cls',
          accent: accent,
          onTap: () => context.go('/my-students'),
        ),
        MetricTile(
          icon: Icons.inbox_outlined,
          label: 'Open requests',
          value: _loadingExtras ? '—' : '$_pendingRequests',
          accent: accent,
          onTap: () => context.go('/support-queue'),
        ),
      ]);
    }
    return grid([
      MetricTile(
        icon: Icons.mark_chat_unread_outlined,
        label: 'Unread',
        value: '$_unread',
        accent: accent,
        onTap: () => context.go('/conversations'),
      ),
      MetricTile(
        icon: Icons.insights_outlined,
        label: 'School insights',
        value: 'Live',
        accent: accent,
        onTap: () => context.go('/insights'),
      ),
    ]);
  }

  Widget _actions(AppIdentity identity, TierAccent accent) {
    final items = switch (identity.tier) {
      AppTier.student => <_Action>[
          _Action(Icons.groups_outlined, 'My class', 'Teachers & class info',
              () => context.go('/my-class')),
          _Action(Icons.forum_outlined, 'Messages', 'Talk to your teachers',
              () => context.go('/conversations')),
          if (_supportConvId != null)
            _Action(Icons.support_agent_outlined, 'Teacher Support', 'Ask a question',
                () => context.go('/conversations/$_supportConvId')),
          _Action(Icons.apartment_outlined, 'School leadership', 'Contact the leadership',
              () => context.go('/leadership')),
        ],
      AppTier.teacher => <_Action>[
          _Action(Icons.people_alt_outlined, 'My students', 'Everyone you teach',
              () => context.go('/my-students')),
          _Action(Icons.inbox_outlined, 'Student requests', 'Resolve support questions',
              () => context.go('/support-queue')),
          _Action(Icons.forum_outlined, 'Messages', 'Conversations with students',
              () => context.go('/conversations')),
          _Action(Icons.campaign_outlined, 'Send a notice', 'Reach your classes',
              () => context.go('/announcements')),
        ],
      AppTier.leadership => <_Action>[
          _Action(Icons.insights_outlined, 'Insights', 'Whole-school snapshot',
              () => context.go('/insights')),
          _Action(Icons.apartment_outlined, 'Staff directory', 'Manage your team',
              () => context.go('/staff')),
          _Action(Icons.person_add_alt_outlined, 'Add teacher', 'Propose a new hire to the office',
              () => context.go('/staff/request')),
          _Action(Icons.manage_accounts_outlined, 'Manage roster', 'Activate or deactivate people',
              () => context.go('/staff/roster')),
          _Action(Icons.folder_outlined, 'School files', 'Everything uploaded at school',
              () => context.go('/staff/files')),
          _Action(Icons.groups_outlined, 'My students', 'Your classes',
              () => context.go('/my-students')),
          _Action(Icons.inbox_outlined, 'Student requests', 'Support queue',
              () => context.go('/support-queue')),
        ],
    };

    // Stacked on a phone (unchanged), two-up from tablet width on.
    return AdaptiveGrid(
      maxColumns: 2,
      // Matches the height the stacked list had on a phone.
      itemExtent: 76,
      spacing: 8,
      children: [
        for (final a in items)
          Card(
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
              onTap: a.onTap,
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