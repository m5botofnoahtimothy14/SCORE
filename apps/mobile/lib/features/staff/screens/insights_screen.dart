// Leadership tier: whole-school numbers at a glance.
//
// RLS note: a head_teacher is NOT `tc_is_school_admin`, so several of these
// tables (students, safeguarding_incidents, moderation_review_cases,
// notification_jobs) are denied for that role. Every count therefore runs in its
// own try/catch and renders an em-dash when the server refuses it — a denial
// must never blank the screen.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/layout/responsive.dart';
import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';

/// Refines a base `select('id')` query before it is awaited.
typedef _CountRefiner = PostgrestFilterBuilder<List<Map<String, dynamic>>>
    Function(PostgrestFilterBuilder<List<Map<String, dynamic>>> query);

/// Counts rows in `table` for one school, or null when RLS denies the read.
Future<int?> _tryCount(
  SupabaseClient client,
  String table,
  String schoolId, [
  _CountRefiner? refine,
]) async {
  try {
    var query = client.from(table).select('id').eq('school_id', schoolId);
    if (refine != null) query = refine(query);
    return ((await query) as List).length;
  } catch (_) {
    return null;
  }
}

final _schoolInsightsProvider = FutureProvider<SchoolInsights>((ref) async {
  final identity = await ref.watch(identityProvider.future);
  final client = Supabase.instance.client;
  final schoolId = identity.schoolId;
  final since = DateTime.now()
      .toUtc()
      .subtract(const Duration(days: 7))
      .toIso8601String();

  // Index map — keep in sync with the Future.wait order below:
  // 0 teachers · 1 classes · 2 students · 3 announcements(7d)
  // 4 open incidents · 5 moderation queue · 6 failed notifications
  final counts = await Future.wait([
    _tryCount(client, 'teachers', schoolId),
    _tryCount(client, 'classes', schoolId),
    _tryCount(client, 'students', schoolId),
    _tryCount(
      client,
      'announcements',
      schoolId,
      (q) => q.gte('published_at', since),
    ),
    _tryCount(
      client,
      'safeguarding_incidents',
      schoolId,
      (q) => q.inFilter('status', const ['open', 'investigating']),
    ),
    _tryCount(
      client,
      'moderation_review_cases',
      schoolId,
      (q) => q.inFilter('status', const ['pending', 'under_review']),
    ),
    _tryCount(client, 'notification_jobs', schoolId, (q) => q.eq('status', 'failed')),
  ]);

  return SchoolInsights(
    people: [
      SchoolMetric(icon: Icons.groups_outlined, label: 'Staff', value: counts[0]),
      SchoolMetric(icon: Icons.meeting_room_outlined, label: 'Classes', value: counts[1]),
      SchoolMetric(icon: Icons.school_outlined, label: 'Students', value: counts[2]),
    ],
    safety: [
      SchoolMetric(
        icon: Icons.health_and_safety_outlined,
        label: 'Open incidents',
        value: counts[4],
      ),
      SchoolMetric(
        icon: Icons.fact_check_outlined,
        label: 'Moderation queue',
        value: counts[5],
      ),
    ],
    platform: [
      SchoolMetric(
        icon: Icons.campaign_outlined,
        label: 'Notices · 7 days',
        value: counts[3],
      ),
      SchoolMetric(
        icon: Icons.notifications_off_outlined,
        label: 'Failed notifications',
        value: counts[6],
      ),
    ],
  );
});

Future<void> _refreshInsights(WidgetRef ref) async {
  ref.invalidate(_schoolInsightsProvider);
  try {
    await ref.read(_schoolInsightsProvider.future);
  } catch (_) {
    // Failure is surfaced by the error state during the next build.
  }
}

/// One whole-school number; null means the server denied the read.
class SchoolMetric {
  final IconData icon;
  final String label;
  final int? value;

  const SchoolMetric({required this.icon, required this.label, required this.value});

  String get display => value?.toString() ?? '—';
  bool get denied => value == null;
}

class SchoolInsights {
  final List<SchoolMetric> people;
  final List<SchoolMetric> safety;
  final List<SchoolMetric> platform;

  const SchoolInsights({
    required this.people,
    required this.safety,
    required this.platform,
  });

  List<SchoolMetric> get all => [...people, ...safety, ...platform];

  bool get hasDeniedMetrics => all.any((m) => m.denied);
}

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final accent = TierAccent.of(AppTier.leadership);

    final identityAsync = ref.watch(identityProvider);
    final identity = identityAsync.valueOrNull;
    if (identity == null) {
      return Scaffold(
        body: identityAsync.hasError
            ? ErrorView(
                message: identityAsync.error.toString(),
                onRetry: () => ref.invalidate(identityProvider),
              )
            : const LoadingView(),
      );
    }

    final insightsAsync = ref.watch(_schoolInsightsProvider);
    if (!insightsAsync.hasValue) {
      return Scaffold(
        body: insightsAsync.hasError
            ? ErrorView(
                message: insightsAsync.error.toString(),
                onRetry: () => ref.invalidate(_schoolInsightsProvider),
              )
            : const LoadingView(),
      );
    }

    final insights = insightsAsync.requireValue;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Insights'),
        actions: [
          IconButton(
            icon: const Icon(Icons.apartment_outlined),
            onPressed: () => context.go('/staff'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refreshInsights(ref),
        child: AdaptivePage(
          child: ListView(
            // Horizontal padding comes from AdaptivePage.
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 28),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              GlossHero(
                accent: accent,
                eyebrow: 'Insights',
                title: 'School Overview',
                subtitle: identity.schoolName.isEmpty ? null : identity.schoolName,
              ),
              const SizedBox(height: 22),
              _section('People', insights.people, accent),
              const SizedBox(height: 22),
              _section('Safety', insights.safety, accent),
              const SizedBox(height: 22),
              _section('Platform', insights.platform, accent),
              if (insights.hasDeniedMetrics) ...[
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_outline, size: 14, color: theme.textTheme.bodySmall?.color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'A dash means your role is not permitted to read that data under the school\'s access rules.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title, List<SchoolMetric> metrics, TierAccent accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title),
        AdaptiveGrid(
          // Two-up stays the design; the third column only appears when there
          // is width for it.
          maxColumns: 3,
          minColumns: 2,
          itemExtent: 142,
          spacing: 12,
          children: [
            for (final m in metrics)
              MetricTile(icon: m.icon, label: m.label, value: m.display, accent: accent),
          ],
        ),
      ],
    );
  }
}