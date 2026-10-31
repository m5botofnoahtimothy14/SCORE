import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mentor_desk_design.dart';
import '../../../core/layout/responsive.dart';
import '../../../core/widgets/states.dart';
import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';

final _serviceProvider = Provider((ref) => Supabase.instance.client);

class MentorDeskHomeScreen extends ConsumerStatefulWidget {
  const MentorDeskHomeScreen({super.key});

  @override
  ConsumerState<MentorDeskHomeScreen> createState() => _MentorDeskHomeScreenState();
}

class _MentorDeskHomeScreenState extends ConsumerState<MentorDeskHomeScreen> {
  bool _loading = true;
  String? _error;
  int _openDoubts = 0;
  int _sessionMinutesLeft = 0;
  bool _urgentPassAvailable = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final identity = await ref.read(identityProviderProvider.future);
      if (identity == null) {
        if (!mounted) return;
        setState(() { _loading = false; _error = 'No identity found'; });
        return;
      }

      final supabase = Supabase.instance.client;
      final doubts = await supabase
          .from('doubt_requests')
          .select('id, status, question, created_at')
          .eq('student_id', identity.userId)
          .filter('status', 'in', '("pending_assignment","waiting","assigned","in_progress")');

      final sessions = await supabase
          .from('session_bookings')
          .select('allowance_minutes_used, status')
          .eq('student_id', identity.userId)
          .filter('status', 'in', '("confirmed","completed")');

      final settings = await supabase
          .from('mentor_desk_settings')
          .select('session_allowance_minutes')
          .eq('school_id', identity.schoolId)
          .maybeSingle();

      final allowance = settings?['session_allowance_minutes'] ?? 120;
      final used = sessions.fold<int>(
        0,
        (sum, s) => sum + ((s['allowance_minutes_used'] as num?)?.toInt() ?? 0),
      );

      if (!mounted) return;
      setState(() {
        _openDoubts = doubts.length;
        _sessionMinutesLeft = allowance - used;
        _urgentPassAvailable = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tier = MDTier.student;

    return Scaffold(
      backgroundColor: MDColors.ink50,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('SCORE+ Mentor Desk'),
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(kGutter, 10, kGutter, 0),
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
                              onPressed: _load,
                              icon: const Icon(Icons.refresh, size: 20),
                              tooltip: 'Refresh',
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(kGutter, 6, kGutter, 0),
                      sliver: SliverToBoxAdapter(
                        child: Container(
                          margin: const EdgeInsets.only(bottom: kGutter),
                          padding: const EdgeInsets.all(kGutter + 8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: tier.gradient),
                            borderRadius: BorderRadius.circular(kRadiusLg),
                            boxShadow: [
                              BoxShadow(
                                color: tier.solid.withValues(alpha: 0.45),
                                blurRadius: 30,
                                offset: const Offset(0, 14),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(right: 40, bottom: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'SCORE+ School',
                                            style: TextStyle(
                                              color: Colors.white.withValues(alpha: 0.82),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 1.1,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'Good morning, Student',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 26,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -0.4,
                                              height: 1.12,
                                            ),
                                          ),
                                          const SizedBox(height: 5),
                                          Text(
                                            'Your academic support desk - doubts, sessions and ratings.',
                                            style: TextStyle(
                                              color: Colors.white.withValues(alpha: 0.86),
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 0),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _allowancesSliver(context),
                            const SizedBox(height: kGutter),
                            _quickActionsSliver(context),
                            const SizedBox(height: kGutter),
                            _openDoubtsSliver(context),
                            const SizedBox(height: kGutter),
                            _upcomingSliver(context),
                            const SizedBox(height: kGutter + 80),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _allowancesSliver(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MDSectionHeader(title: 'Your weekly allowance'),
        const SizedBox(height: kGutter),
        Row(
          children: [
            Expanded(
              child: MDMetricTile(
                icon: Icons.question_answer_outlined,
                label: 'Open doubts',
                value: '$_openDoubts',
                tier: MDTier.student,
                onTap: () => context.go('/mentor-desk/doubts'),
              ),
            ),
            const SizedBox(width: kGutter),
            Expanded(
              child: MDMetricTile(
                icon: Icons.access_time_outlined,
                label: 'Session minutes left',
                value: '$_sessionMinutesLeft min',
                tier: MDTier.student,
                onTap: () => context.go('/mentor-desk/session/book'),
              ),
            ),
          ],
        ),
        const SizedBox(height: kGutter),
        MDMetricTile(
          icon: Icons.flash_on_outlined,
          label: 'Urgent pass',
          value: _urgentPassAvailable ? 'Available' : 'Used',
          tier: MDTier.student,
        ),
      ],
    );
  }

  Widget _quickActionsSliver(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MDSectionHeader(title: 'Get help'),
        const SizedBox(height: kGutter),
        Row(
          children: [
            Expanded(
              child: _GlossActionTile(
                icon: Icons.add_circle_outline,
                label: 'Ask a Doubt',
                subtitle: 'Guided submission flow',
                tier: MDTier.student,
                onTap: () => context.go('/mentor-desk/doubt/submit'),
              ),
            ),
            const SizedBox(width: kGutter),
            Expanded(
              child: _GlossActionTile(
                icon: Icons.schedule_outlined,
                label: 'Book a Session',
                subtitle: 'Pick mentor, time & length',
                tier: MDTier.student,
                onTap: () => context.go('/mentor-desk/session/book'),
              ),
            ),
          ],
        ),
        const SizedBox(height: kGutter),
        Row(
          children: [
            Expanded(
              child: _GlossActionTile(
                icon: Icons.forum_outlined,
                label: 'My Conversations',
                subtitle: 'Open threads & replies',
                tier: MDTier.student,
                onTap: () => context.go('/mentor-desk/doubts'),
              ),
            ),
            const SizedBox(width: kGutter),
            Expanded(
              child: _GlossActionTile(
                icon: Icons.rate_review_outlined,
                label: 'Give Feedback',
                subtitle: 'Rate closed support',
                tier: MDTier.student,
                onTap: () => context.go('/mentor-desk/rating'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _openDoubtsSliver(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MDSectionHeader(
          title: 'Your doubts',
          actionLabel: 'See all',
          onAction: () => context.go('/mentor-desk/doubts'),
        ),
        const SizedBox(height: kGutter),
        const SizedBox(
          height: 160,
          child: EmptyView(
            title: 'No open doubts',
            subtitle: 'Ask a doubt to get started.',
            icon: Icons.question_answer_outlined,
            actionLabel: 'Ask a Doubt',
          ),
        ),
      ],
    );
  }

  Widget _upcomingSliver(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MDSectionHeader(
          title: 'Upcoming sessions',
          actionLabel: 'See all',
          onAction: () => context.go('/mentor-desk/sessions'),
        ),
        const SizedBox(height: kGutter),
        const SizedBox(
          height: 160,
          child: EmptyView(
            title: 'No upcoming sessions',
            subtitle: 'Book a session with a mentor.',
            icon: Icons.schedule_outlined,
            actionLabel: 'Book a Session',
          ),
        ),
      ],
    );
  }
}

class _GlossActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final MDTier tier;
  final VoidCallback onTap;

  const _GlossActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.tier,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(kRadiusSm),
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadiusSm),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(kGutter),
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(kRadiusSm),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: tier.gradient),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: tier.solid.withValues(alpha: 0.5),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(icon, size: 20, color: Colors.white),
              ),
              const SizedBox(height: 14),
              Text(
                label,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11.5, color: scheme.onSurface.withValues(alpha: 0.65)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}