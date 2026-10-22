import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../../../core/layout/responsive.dart';
import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart' show SectionHeader, TierAccent, GlossHeroMentor, GlossMetricTile, GlossActionTile, glossyElevatedButton, glassCard;
import '../../../core/widgets/states.dart';
import '../../mentor_desk/models/mentor_desk_models.dart';
import '../../mentor_desk/services/mentor_desk_service.dart';

final _serviceProvider = Provider<MentorDeskService>(
  (ref) => MentorDeskService(Supabase.instance.client),
);

/// Student Mentor Desk home — glossy, professional surface showing allowance,
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
  StreamSubscription? _realtime;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _realtime?.cancel();
    super.dispose();
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

      _subscribeRealtime(service, schoolId, studentId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is MentorDeskException ? e.message : 'Could not load Mentor Desk.';
        _loading = false;
      });
    }
  }

  void _subscribeRealtime(MentorDeskService service, String schoolId, String studentId) {
    _realtime = service.client
        .from('doubt_requests')
        .stream(primaryKey: ['id'])
        .eq('student_id', studentId)
        .listen((_) {
      _load();
    });
    _realtime?.onError((_) {});
  }

  String _greeting(String? name) {
    final h = DateTime.now().hour;
    final part = h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
    final n = (name ?? '').trim();
    return n.isEmpty ? part : '$part, ${n.split(' ').first}';
  }

  @override
  Widget build(BuildContext context) {
    final identityAsync = ref.watch(identityProvider);

    return Scaffold(
      body: identityAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: e is IdentityException ? e.message : 'Could not load your identity.',
          onRetry: () => ref.invalidate(identityProvider),
        ),
        data: (identity) => AdaptivePage(
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
                        onPressed: () => _load(),
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
                  child: GlossHeroMentor(
                    accent: TierAccent.of(identity.tier),
                    eyebrow: identity.schoolName.isEmpty ? identity.tier.label : identity.schoolName,
                    title: _greeting(identity.displayName),
                    subtitle: 'Your academic support desk — doubts, sessions and ratings.',
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                sliver: _loading
                    ? const SliverToBoxAdapter(child: LoadingView())
                    : _error != null
                        ? SliverToBoxAdapter(child: ErrorView(message: _error!, onRetry: _load))
                        : SliverMainAxisGroup(
                            slivers: [
                              _allowancesSliver(context, identity),
                              const SliverPadding(padding: EdgeInsets.only(top: 16)),
                              _quickActionsSliver(context),
                              const SliverPadding(padding: EdgeInsets.only(top: 16)),
                              _openDoubtsSliver(context),
                              const SliverPadding(padding: EdgeInsets.only(top: 16)),
                              _upcomingSliver(context),
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _allowancesSliver(BuildContext context, AppIdentity identity) {
    final accent = TierAccent.of(identity.tier);
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Your weekly allowance'),
          const SizedBox(height: 12),
          AdaptiveGrid(
            minColumns: 2,
            maxColumns: 3,
            itemExtent: 170,
            spacing: 12,
            children: [
              GlossMetricTile(
                icon: Icons.question_answer_outlined,
                label: 'Open doubts',
                value: '$_openDoubtCount',
                accent: accent,
                onTap: () => context.go('/mentor-desk/doubt/submit'),
              ),
              GlossMetricTile(
                icon: Icons.access_time_outlined,
                label: 'Session minutes left',
                value: '$_remainingSessionMinutes min',
                accent: accent,
                onTap: () => context.go('/mentor-desk/session/book'),
              ),
              GlossMetricTile(
                icon: Icons.flash_on_outlined,
                label: 'Urgent pass',
                value: _urgentPassAvailable ? 'Available' : 'Used',
                accent: accent,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickActionsSliver(BuildContext context) {
    final accent = TierAccent.of(AppTier.student);
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Get help'),
          const SizedBox(height: 12),
          AdaptiveGrid(
            maxColumns: 2,
            itemExtent: 150,
            spacing: 12,
            children: [
              GlossActionTile(
                icon: Icons.add_circle_outline,
                label: 'Ask a Doubt',
                subtitle: 'Guided submission flow',
                accent: accent,
                onTap: () => context.go('/mentor-desk/doubt/submit'),
              ),
              GlossActionTile(
                icon: Icons.schedule_outlined,
                label: 'Book a Session',
                subtitle: 'Pick mentor, time & length',
                accent: accent,
                onTap: () => context.go('/mentor-desk/session/book'),
              ),
              GlossActionTile(
                icon: Icons.forum_outlined,
                label: 'My Conversations',
                subtitle: 'Open threads & replies',
                accent: accent,
                onTap: () => context.go('/mentor-desk/doubts'),
              ),
              GlossActionTile(
                icon: Icons.rate_review_outlined,
                label: 'Give Feedback',
                subtitle: 'Rate closed support',
                accent: accent,
                onTap: () => context.go('/mentor-desk/ratings'),
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
          SectionHeader(title: 'Your doubts', actionLabel: 'See all', onAction: () => context.go('/mentor-desk/doubts')),
          const SizedBox(height: 12),
          if (_recentDoubts.isEmpty)
            const SizedBox(
              height: 160,
              child: EmptyView(
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
          SectionHeader(title: 'Upcoming sessions', actionLabel: 'See all', onAction: () => context.go('/mentor-desk/sessions')),
          const SizedBox(height: 12),
          if (_upcomingSessions.isEmpty)
            const SizedBox(
              height: 160,
              child: EmptyView(
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

class _DoubtCard extends StatelessWidget {
  final DoubtRequest doubt;
  final VoidCallback onTap;
  const _DoubtCard({required this.doubt, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = TierAccent.of(AppTier.student);
    final color = _statusColor(doubt.status);
    return SizedBox(
      width: 230,
      child: Container(
        decoration: glassCard(color: Theme.of(context).cardColor.withValues(alpha: 0.9)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
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
                      child: Text(doubt.statusLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
                    ),
                    if (doubt.urgent)
                      const Icon(Icons.flash_on, size: 15, color: Color(0xFFDC2626)),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Text(doubt.question, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 8),
                Text(_ago(doubt.createdAt), style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
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
    case 'waiting': return const Color(0xFFD97706);
    case 'assigned': return const Color(0xFF2563EB);
    case 'resolved': return const Color(0xFF059669);
    case 'closed': return const Color(0xFF475569);
    default: return const Color(0xFF64748B);
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
    final accent = TierAccent.of(AppTier.student);
    final time = booking.scheduledAt != null ? DateFormat('hh:mm a').format(booking.scheduledAt!.toLocal()) : 'TBD';
    return SizedBox(
      width: 230,
      child: Container(
        decoration: glassCard(color: Theme.of(context).cardColor.withValues(alpha: 0.9)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 9, height: 9,
                  decoration: BoxDecoration(color: accent.solid, shape: BoxShape.circle),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Text(booking.topic, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 14, color: Color(0xFF64748B)),
                    const SizedBox(width: 7),
                    Text(time, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                    const Spacer(),
                    Text('${booking.durationMinutes} min', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF2563EB))),
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
