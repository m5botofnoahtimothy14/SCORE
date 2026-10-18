// Leadership tier: whole-school staff directory.
//
// RLS note: migration 00017 (`teachers_leadership`) lets head_teacher /
// principal / school_admin / platform_owner read every teacher row of their own
// school. The `.eq('school_id', ...)` is scoping, not enforcement — tenant
// isolation is enforced server-side by RLS.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';

/// Client-side search text (name or staff id).
final _staffSearchProvider = StateProvider<String>((ref) => '');

/// Toggle: restrict the list to staff flagged as leadership.
final _staffLeadershipOnlyProvider = StateProvider<bool>((ref) => false);

/// The school's staff roster, with subject names merged in.
final _staffDirectoryProvider = FutureProvider<List<StaffMember>>((ref) async {
  final identity = await ref.watch(identityProvider.future);
  final client = Supabase.instance.client;

  final rows = await client
      .from('teachers')
      .select('id, staff_id_no, first_name, last_name, is_leadership, is_active')
      .eq('school_id', identity.schoolId)
      .order('first_name') as List;

  // `teachers` has no FK to `subjects`, so subject names are resolved through
  // teaching_assignments -> subjects (readable by every school member).
  final subjectsByTeacher = <String, List<String>>{};
  try {
    final assignments = await client
        .from('teaching_assignments')
        .select('teacher_id, subjects(name)')
        .eq('school_id', identity.schoolId) as List;
    for (final a in assignments) {
      final m = Map<String, dynamic>.from(a as Map);
      final teacherId = m['teacher_id'] as String?;
      final subject = m['subjects'];
      final name = subject is Map ? subject['name'] as String? : null;
      if (teacherId == null || name == null) continue;
      final list = subjectsByTeacher.putIfAbsent(teacherId, () => <String>[]);
      if (!list.contains(name)) list.add(name);
    }
  } catch (_) {
    // Subject chips are supplementary — never fail the directory over them.
  }

  return rows.map((row) {
    final m = Map<String, dynamic>.from(row as Map);
    final id = (m['id'] ?? '').toString();
    return StaffMember(
      id: id,
      staffIdNo: (m['staff_id_no'] ?? '').toString(),
      firstName: (m['first_name'] ?? '').toString(),
      lastName: (m['last_name'] ?? '').toString(),
      isLeadership: m['is_leadership'] == true,
      isActive: m['is_active'] != false,
      subjects: subjectsByTeacher[id] ?? const <String>[],
    );
  }).toList();
});

Future<void> _refreshDirectory(WidgetRef ref) async {
  ref.invalidate(_staffDirectoryProvider);
  try {
    await ref.read(_staffDirectoryProvider.future);
  } catch (_) {
    // Failure is surfaced by the error state during the next build.
  }
}

class StaffDirectoryScreen extends ConsumerWidget {
  const StaffDirectoryScreen({super.key});

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

    final staffAsync = ref.watch(_staffDirectoryProvider);
    if (!staffAsync.hasValue) {
      return Scaffold(
        body: staffAsync.hasError
            ? ErrorView(
                message: staffAsync.error.toString(),
                onRetry: () => ref.invalidate(_staffDirectoryProvider),
              )
            : const LoadingView(),
      );
    }

    final staff = staffAsync.requireValue;
    final query = ref.watch(_staffSearchProvider).trim().toLowerCase();
    final leadershipOnly = ref.watch(_staffLeadershipOnlyProvider);

    final filtered = staff.where((m) {
      if (leadershipOnly && !m.isLeadership) return false;
      if (query.isEmpty) return true;
      return m.fullName.toLowerCase().contains(query) ||
          m.staffIdNo.toLowerCase().contains(query);
    }).toList();

    final leadershipCount = staff.where((m) => m.isLeadership).length;
    final activeCount = staff.where((m) => m.isActive).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Directory'),
        actions: [
          IconButton(
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => context.go('/insights'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refreshDirectory(ref),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            GlossHero(
              accent: accent,
              eyebrow: 'Leadership',
              title: 'Staff Directory',
              subtitle: identity.schoolName.isEmpty ? null : identity.schoolName,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    icon: Icons.groups_outlined,
                    label: 'Total staff',
                    value: '${staff.length}',
                    accent: accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Metric(
                    icon: Icons.workspace_premium_outlined,
                    label: 'Leadership',
                    value: '$leadershipCount',
                    accent: accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Metric(
                    icon: Icons.verified_outlined,
                    label: 'Active',
                    value: '$activeCount',
                    accent: accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              textInputAction: TextInputAction.search,
              onChanged: (v) => ref.read(_staffSearchProvider.notifier).state = v,
              decoration: const InputDecoration(
                hintText: 'Search name or staff ID',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilterChip(
                  label: const Text('Leadership only'),
                  avatar: Icon(
                    leadershipOnly ? Icons.check_circle : Icons.workspace_premium_outlined,
                    size: 18,
                    color: leadershipOnly ? accent.onSoft : null,
                  ),
                  selected: leadershipOnly,
                  showCheckmark: false,
                  onSelected: (v) =>
                      ref.read(_staffLeadershipOnlyProvider.notifier).state = v,
                ),
                const Spacer(),
                Text('${filtered.length} of ${staff.length}', style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 12),
            if (filtered.isEmpty)
              const SizedBox(
                height: 220,
                child: EmptyView(
                  title: 'No staff match',
                  subtitle: 'Try a different name or staff ID, or turn off the leadership filter.',
                  icon: Icons.person_search_outlined,
                ),
              )
            else
              for (final member in filtered) ...[
                _StaffCard(member: member, accent: accent),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

/// A roster row as the signed-in leader is allowed to see it.
class StaffMember {
  final String id;
  final String staffIdNo;
  final String firstName;
  final String lastName;
  final bool isLeadership;
  final bool isActive;
  final List<String> subjects;

  const StaffMember({
    required this.id,
    required this.staffIdNo,
    required this.firstName,
    required this.lastName,
    required this.isLeadership,
    required this.isActive,
    required this.subjects,
  });

  String get fullName {
    final n = '$firstName $lastName'.trim();
    return n.isEmpty ? staffIdNo : n;
  }

  String get initial =>
      firstName.isNotEmpty ? firstName.substring(0, 1).toUpperCase() : '?';
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final TierAccent accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 124,
      child: MetricTile(icon: icon, label: label, value: value, accent: accent),
    );
  }
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({required this.member, required this.accent});

  final StaffMember member;
  final TierAccent accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 21,
                  backgroundColor: accent.soft,
                  child: Text(
                    member.initial,
                    style: TextStyle(color: accent.onSoft, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(member.fullName, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(member.staffIdNo, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (member.isLeadership)
                  _Pill(label: 'Leadership', fg: accent.onSoft, bg: accent.soft),
                if (!member.isActive)
                  _Pill(
                    label: 'Inactive',
                    fg: AppColors.danger,
                    bg: AppColors.danger.withValues(alpha: 0.10),
                  ),
                for (final s in member.subjects)
                  _Pill(
                    label: s,
                    fg: scheme.onSurfaceVariant,
                    bg: scheme.surfaceContainerHighest,
                  ),
                if (member.subjects.isEmpty)
                  _Pill(
                    label: 'No subjects assigned',
                    fg: scheme.onSurfaceVariant,
                    bg: scheme.surfaceContainerHighest,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.fg, required this.bg});

  final String label;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9)),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}