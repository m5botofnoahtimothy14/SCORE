import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mentor_desk_design.dart';
import '../../../core/layout/responsive.dart';
import '../../../core/widgets/states.dart';
import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../mentor_desk/models/mentor_desk_models.dart';
import '../../mentor_desk/services/mentor_desk_service.dart';

final _serviceProvider = Provider<MentorDeskService>(
  (ref) => MentorDeskService(Supabase.instance.client),
);

/// Student Mentor Desk home — glossy, modern surface showing allowance,
/// open doubts, upcoming sessions, urgent pass and quick actions.
class MentorDeskHomeScreen extends ConsumerStatefulWidget {
  const MentorDeskHomeScreen({super.key});

  @override
  ConsumerState<MentorDeskHomeScreen> createState() => _MentorDeskHomeScreenState();
}

class _MentorDeskHomeScreenState extends ConsumerState<MentorDeskHomeScreen> {
  bool _loading = true;
  String? _error;
  List<AllowanceSummary> _allowances = const [];
  List<DoubtRequest> _recentDoubts = const [];
  List<SessionBooking> _upcomingSessions = const [];
  int _openDoubtCount = 0;
  int _remainingSessionMinutes = 0;
  bool _urgentPassAvailable = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final identity = await ref.read(identityProvider.future);
      final service = ref.read(_serviceProvider);
      final schoolId = identity.schoolId;
      final studentId = identity.userId;

      final allowances = await service.allowanceSummary(schoolId: schoolId, studentId: studentId);
      final doubts = await service.listDoubtRequests(schoolId: schoolId, studentId: studentId);
      final sessions = await service.listSessionBookings(studentId: studentId);

      int openDoubts = 0;
      int remaining = 0;
      bool urgent = false;
      for (final a in allowances) {
        openDoubts += a.openDoubts;
        remaining += a.remainingMinutes;
        if (a.urgentPassAvailable) urgent = true;
      }

      final upcoming = sessions.where((s) => s.status == 'confirmed' && s.scheduledAt != null).toList()
        ..sort((a, b) => a.scheduledAt!.compareTo(b.scheduledAt!));

      if (!mounted) return;
      setState(() {
        _allowances = allowances;
        _recentDoubts = doubts;
        _upcomingSessions = upcoming.take(4).toList();
        _openDoubtCount = openDoubts;
        _remainingSessionMinutes = remaining;
        _urgentPassAvailable = urgent;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is MentorDeskException ? e.message : 'Could not load Mentor Desk.';
        _loading = false;
      });
    }
  }

  String _greeting(String? name) {
    final h = DateTime.now().hour;
    final part = h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
    final n = (name ?? '').trim();
    return n.isEmpty ? part : '$part, ${n.split(' ').first}';
  }

  @override
  Widget build(BuildContext context) {
    final tier = ref.watch(identityProvider).value?.tier ?? AppTier.student;
    const accent = MDTier.student;

    return Scaffold(
      backgroundColor: MDColors.ink50,
      body: ref.watch(identityProvider).when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: e is IdentityException ? e.message : 'Could not load your identity.',
          onRetry: () => ref.invalidate(identityProvider),
        ),
        data: (identity) => CustomScrollView(
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
                      onPressed: () => _load(),
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
                    gradient: accent.gradient,
                    borderRadius: BorderRadius.circular(kRadiusLg),
                    boxShadow: [
                      BoxShadow(
                        color: accent.solid.withValues(alpha: 0.45),
                        blurRadius: 30,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      const MDBloom(color: Colors.white, size: 220, alignment: Alignment.topRight),
                      Padding(
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
                                        identity.schoolName.isEmpty ? identity.tier.label : identity.schoolName,
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.82),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.1,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _greeting(identity.displayName),
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
                                        'Your academic support desk — doubts, sessions and ratings.',
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
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 0),
              sliver: _loading
                  ? const SliverToBoxAdapter(child: LoadingView())
                  : _error != null
                      ? SliverToBoxAdapter(child: ErrorView(message: _error!, onRetry: _load))
                      : SliverMainAxisGroup(
                          slivers: [
                            _allowancesSliver(context),
                            const SliverPadding(padding: EdgeInsets.only(top: kGutter)),
                            _quickActionsSliver(context),
                            const SliverPadding(padding: EdgeInsets.only(top: kGutter)),
                            _openDoubtsSliver(context),
                            const SliverPadding(padding: EdgeInsets.only(top: kGutter)),
                            _upcomingSliver(context),
                            const SliverPadding(padding: EdgeInsets.only(bottom: kGutter + 80)),
                          ],
                        ),
               ),
             ],
         ),
       ),
     );
  }

  Widget _allowancesSliver(BuildContext context) {
    return SliverToBoxAdapter(
      child: Column(
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
                  value: '$_openDoubtCount',
                  tier: MDTier.student,
                  onTap: () => context.go('/mentor-desk/doubts'),
                ),
              ),
              const SizedBox(width: kGutter),
              Expanded(
                child: MDMetricTile(
                  icon: Icons.access_time_outlined,
                  label: 'Session minutes left',
                  value: '$_remainingSessionMinutes min',
                  tier: MDTier.student,
                  onTap: () => context.go('/mentor-desk/session/book'),
                ),
              ),
            ],
          ),
          const SizedBox(height: kGutter),
          Expanded(
            child: MDMetricTile(
              icon: Icons.flash_on_outlined,
              label: 'Urgent pass',
              value: _urgentPassAvailable ? 'Available' : 'Used',
              tier: MDTier.student,
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActionsSliver(BuildContext context) {
    return SliverToBoxAdapter(
      child: Column(
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
                  onTap: () => context.go('/mentor-desk/ratings'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _openDoubtsSliver(BuildContext context) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MDSectionHeader(title: 'Your doubts', actionLabel: 'See all', onAction: () => context.go('/mentor-desk/doubts')),
          const SizedBox(height: kGutter),
          if (_recentDoubts.isEmpty)
            const SizedBox(
              height: 160,
              child: const EmptyView(
                title: 'No open doubts',
                subtitle: 'Ask a doubt to get started.',
                icon: Icons.question_answer_outlined,
                actionLabel: 'Ask a Doubt',
              ),
            )
          else
            SizedBox(
              height: 130,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _recentDoubts.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final d = _recentDoubts[i];
                  return _DoubtCard(doubt: d, onTap: () => context.go('/mentor-desk/doubt/${d.id}'));
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _upcomingSliver(BuildContext context) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MDSectionHeader(title: 'Upcoming sessions', actionLabel: 'See all', onAction: () => context.go('/mentor-desk/sessions')),
          const SizedBox(height: kGutter),
          if (_upcomingSessions.isEmpty)
            const SizedBox(
              height: 160,
              child: const EmptyView(
                title: 'No upcoming sessions',
                subtitle: 'Book a session with a mentor.',
                icon: Icons.schedule_outlined,
                actionLabel: 'Book a Session',
              ),
            )
          else
            SizedBox(
              height: 160,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _upcomingSessions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final s = _upcomingSessions[i];
                  return _SessionCard(booking: s, onTap: () => context.go('/mentor-desk/session/${s.id}'));
                },
              ),
            ),
        ],
      ),
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
                  gradient: tier.gradient,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(color: tier.solid.withValues(alpha: 0.5), blurRadius: 12, offset: const Offset(0, 4)),
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

class _DoubtCard extends StatelessWidget {
  final DoubtRequest doubt;
  final VoidCallback onTap;
  const _DoubtCard({required this.doubt, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _statusColor(doubt.status);
    return SizedBox(
      width: 230,
      child: MDListCard(
        child: InkWell(
          borderRadius: BorderRadius.circular(kRadiusSm),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 9, height: 9,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(doubt.statusLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: MDColors.ink600)),
                    ),
                    if (doubt.urgent)
                      const Icon(Icons.flash_on, size: 15, color: MDColors.danger),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Text(doubt.question, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 8),
                Text(_ago(doubt.createdAt), style: const TextStyle(fontSize: 11.5, color: MDColors.ink600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'waiting': return MDColors.warning;
    case 'assigned': return MDColors.brand;
    case 'resolved': return MDColors.success;
    case 'closed': return MDColors.ink600;
    default: return MDColors.ink600;
  }
}

String _ago(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

class _SessionCard extends StatelessWidget {
  final SessionBooking booking;
  final VoidCallback onTap;
  const _SessionCard({required this.booking, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final time = booking.scheduledAt != null ? DateFormat('hh:mm a').format(booking.scheduledAt!.toLocal()) : 'TBD';
    return SizedBox(
      width: 230,
      child: MDListCard(
        child: InkWell(
          borderRadius: BorderRadius.circular(kRadiusSm),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 9, height: 9,
                  decoration: BoxDecoration(color: MDTier.student.solid, shape: BoxShape.circle),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Text(booking.topic, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 14, color: MDColors.ink600),
                    const SizedBox(width: 7),
                    Text(time, style: const TextStyle(fontSize: 13, color: MDColors.ink600)),
                    const Spacer(),
                    Text('${booking.durationMinutes} min', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MDColors.brand)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
