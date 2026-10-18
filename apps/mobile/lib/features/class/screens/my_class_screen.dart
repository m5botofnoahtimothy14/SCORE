import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';

/// A teacher on the signed-in student's teaching team.
class _ClassTeacher {
  final String id;
  final String firstName;
  final String lastName;
  final bool isLeadership;
  final List<String> subjects;

  const _ClassTeacher({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.isLeadership,
    required this.subjects,
  });

  String get name => '$firstName $lastName'.trim();
  String get initial => firstName.isEmpty ? '?' : firstName.substring(0, 1).toUpperCase();
  String? get subjectLine => subjects.isEmpty ? null : subjects.join(' · ');
}

/// Teaching team for [classId].
///
/// Classmates are deliberately never queried: RLS on `students` only lets a
/// student read their own row, so a roster is not available at any privilege
/// level. `teachers` is reachable through `teachers_student_view`, which is
/// scoped to teachers assigned to a class the student is enrolled in.
final _classTeachersProvider =
    FutureProvider.autoDispose.family<List<_ClassTeacher>, String?>((ref, classId) async {
  if (classId == null) return const <_ClassTeacher>[];

  final client = Supabase.instance.client;

  // Subjects hang off teaching_assignments, not teachers, so they are resolved
  // in the same select rather than as a nested embed.
  final rows = await client
      .from('teaching_assignments')
      .select('teacher_id, subjects(name), teachers!inner(id, first_name, last_name, is_leadership)')
      .eq('class_id', classId) as List;

  final byId = <String, _ClassTeacher>{};
  for (final row in rows) {
    final r = Map<String, dynamic>.from(row as Map);
    final embedded = r['teachers'];
    if (embedded is! Map) continue;
    final t = Map<String, dynamic>.from(embedded);
    final id = t['id'] as String?;
    if (id == null) continue;

    final subjectNames = <String>[];
    final subjects = r['subjects'];
    if (subjects is Map && subjects['name'] is String) {
      subjectNames.add(subjects['name'] as String);
    }

    final previous = byId[id];
    byId[id] = _ClassTeacher(
      id: id,
      firstName: (t['first_name'] as String?) ?? '',
      lastName: (t['last_name'] as String?) ?? '',
      isLeadership: t['is_leadership'] == true,
      subjects: {...?previous?.subjects, ...subjectNames}.toList()..sort(),
    );
  }

  return byId.values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
});

/// How many conversations the student is an active member of. Scoped to the
/// student's own `conversation_members` rows, so it needs no elevated access.
final _conversationCountProvider =
    FutureProvider.autoDispose.family<int, String>((ref, userId) async {
  final rows = await Supabase.instance.client
      .from('conversation_members')
      .select('conversation_id')
      .eq('user_id', userId)
      .isFilter('removed_at', null) as List;
  return rows.length;
});

/// Student-facing class view: who is on the teaching team and how to reach them.
class MyClassScreen extends ConsumerWidget {
  const MyClassScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identityAsync = ref.watch(identityProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('My Class')),
      body: identityAsync.when(
        loading: () => const LoadingView(message: 'Loading your class...'),
        error: (error, _) => ErrorView(
          message: 'Could not load your class. Check your connection.',
          onRetry: () => ref.invalidate(identityProvider),
        ),
        data: (identity) => _MyClassBody(identity: identity),
      ),
    );
  }
}

class _MyClassBody extends ConsumerWidget {
  final AppIdentity identity;

  const _MyClassBody({required this.identity});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = TierAccent.of(AppTier.student);
    final classId = identity.classId;
    final teachersAsync = ref.watch(_classTeachersProvider(classId));
    final conversationsAsync = ref.watch(_conversationCountProvider(identity.userId));
    final teacherCount = teachersAsync.valueOrNull?.length;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(identityProvider);
        ref.invalidate(_classTeachersProvider(classId));
        ref.invalidate(_conversationCountProvider(identity.userId));
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          GlossHero(
            accent: accent,
            eyebrow: 'My Class',
            title: identity.className ?? 'Class not assigned',
            subtitle: identity.subtitle,
          ),
          const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: MetricTile(
                    icon: Icons.school_outlined,
                    label: 'Class teachers',
                    value: teacherCount?.toString() ?? '—',
                    accent: accent,
                    onTap: () => context.go('/directory'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MetricTile(
                    icon: Icons.forum_outlined,
                    label: 'My conversations',
                    value: conversationsAsync.valueOrNull?.toString() ?? '—',
                    accent: accent,
                    onTap: () => context.go('/conversations'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (classId == null)
            const _NoClassCard()
          else ...[
            SectionHeader(
              title: 'Your teachers',
              actionLabel: 'Directory',
              onAction: () => context.go('/directory'),
            ),
            ..._teacherSection(context, ref, teachersAsync, accent),
          ],
          const SizedBox(height: 22),
          _AskTeacherCard(onTap: () => context.go('/conversations')),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  List<Widget> _teacherSection(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<_ClassTeacher>> teachersAsync,
    TierAccent accent,
  ) {
    return [
      teachersAsync.when(
        loading: () => const SizedBox(height: 180, child: LoadingView(message: 'Loading teachers...')),
        error: (error, _) => SizedBox(
          height: 180,
          child: ErrorView(
            message: 'Could not load your teachers. Check your connection.',
            onRetry: () => ref.invalidate(_classTeachersProvider(identity.classId)),
          ),
        ),
        data: (teachers) => teachers.isEmpty
            ? const _EmptyTeachersCard()
            : Column(
                children: [
                  for (final teacher in teachers) ...[
                    _TeacherCard(teacher: teacher, accent: accent),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
      ),
    ];
  }
}

class _TeacherCard extends StatelessWidget {
  final _ClassTeacher teacher;
  final TierAccent accent;

  const _TeacherCard({required this.teacher, required this.accent});

  @override
  Widget build(BuildContext context) {
    final subject = teacher.subjectLine;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: accent.soft,
              child: Text(
                teacher.initial,
                style: TextStyle(color: accent.onSoft, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          teacher.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (teacher.isLeadership) ...[
                        const SizedBox(width: 8),
                        const _LeadershipChip(),
                      ],
                    ],
                  ),
                  if (subject != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => context.go('/directory'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: const Text('Message'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeadershipChip extends StatelessWidget {
  const _LeadershipChip();

  @override
  Widget build(BuildContext context) {
    final leadership = TierAccent.of(AppTier.leadership);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: leadership.soft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Leadership',
        style: TextStyle(
          color: leadership.onSoft,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AskTeacherCard extends StatelessWidget {
  final VoidCallback onTap;

  const _AskTeacherCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = TierAccent.of(AppTier.student);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: accent.gradient,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.solid.withValues(alpha: 0.24),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.support_agent, color: Colors.white, size: 21),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Ask a teacher',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Send a question to your teaching team',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.9)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoClassCard extends StatelessWidget {
  const _NoClassCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            const Icon(Icons.help_outline, size: 40, color: AppColors.ink300),
            const SizedBox(height: 12),
            Text('No class assigned yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text(
              'Ask the school office to enrol you in a class. Once you are assigned, '
              'your class details and teaching team appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.ink500, fontSize: 13.5, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyTeachersCard extends StatelessWidget {
  const _EmptyTeachersCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            const Icon(Icons.groups_outlined, size: 40, color: AppColors.ink300),
            const SizedBox(height: 12),
            Text('No teachers assigned', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text(
              'Your class has no teaching team assigned yet. Contact the school office if this looks wrong.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.ink500, fontSize: 13.5, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}