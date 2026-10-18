// Leadership tier: manage who is active at the school.
//
// Deactivating someone is destructive — it flips `school_memberships.is_active`
// too, so they lose access immediately — and RLS cannot restrict an UPDATE to a
// single column. The only safe path is the SECURITY DEFINER RPCs
// `set_staff_active` / `set_student_active` (migration 00018), so every toggle
// goes through those. They raise `insufficient_permissions` for roles that may
// not manage people, and that reason is surfaced verbatim rather than hidden
// behind a generic failure.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';

const _kTeachersTab = 0;
const _kStudentsTab = 1;

/// Both halves of the roster, loaded together so the segmented control never
/// blocks on a second round-trip.
final _rosterProvider = FutureProvider<_Roster>((ref) async {
  final identity = await ref.watch(identityProvider.future);
  final client = Supabase.instance.client;

  final teacherRows = await client
      .from('teachers')
      .select('id, first_name, last_name, staff_id_no, is_active, is_leadership, last_seen_at')
      .eq('school_id', identity.schoolId)
      .order('first_name') as List;

  final teachers = teacherRows.map((row) {
    final m = Map<String, dynamic>.from(row as Map);
    return RosterTeacher(
      id: (m['id'] ?? '').toString(),
      firstName: (m['first_name'] ?? '').toString(),
      lastName: (m['last_name'] ?? '').toString(),
      staffIdNo: (m['staff_id_no'] ?? '').toString(),
      isActive: m['is_active'] != false,
      isLeadership: m['is_leadership'] == true,
      lastSeenAt: DateTime.tryParse((m['last_seen_at'] ?? '').toString()),
    );
  }).toList();

  // Students may be unreadable for some roles; keep the teacher tab usable and
  // report the real reason on the student tab instead.
  var students = <RosterStudent>[];
  String? studentError;
  try {
    final studentRows = await client
        .from('students')
        .select('id, first_name, last_name, student_id_no, is_active')
        .eq('school_id', identity.schoolId)
        .order('first_name') as List;
    students = studentRows.map((row) {
      final m = Map<String, dynamic>.from(row as Map);
      return RosterStudent(
        id: (m['id'] ?? '').toString(),
        firstName: (m['first_name'] ?? '').toString(),
        lastName: (m['last_name'] ?? '').toString(),
        studentIdNo: (m['student_id_no'] ?? '').toString(),
        isActive: m['is_active'] != false,
      );
    }).toList();
  } catch (e) {
    studentError = e is PostgrestException
        ? _describeRosterError(e)
        : 'Could not load the student roster.';
  }

  return _Roster(teachers: teachers, students: students, studentError: studentError);
});

Future<void> _refreshRoster(WidgetRef ref) async {
  ref.invalidate(_rosterProvider);
  try {
    await ref.read(_rosterProvider.future);
  } catch (_) {
    // Surfaced by the error state on the next build.
  }
}

class _Roster {
  final List<RosterTeacher> teachers;
  final List<RosterStudent> students;
  final String? studentError;
  const _Roster({
    required this.teachers,
    required this.students,
    required this.studentError,
  });
}

class RosterTeacher {
  final String id;
  final String firstName;
  final String lastName;
  final String staffIdNo;
  final bool isActive;
  final bool isLeadership;
  final DateTime? lastSeenAt;

  const RosterTeacher({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.staffIdNo,
    required this.isActive,
    required this.isLeadership,
    required this.lastSeenAt,
  });

  String get fullName {
    final n = '$firstName $lastName'.trim();
    return n.isEmpty ? staffIdNo : n;
  }

  String get initial =>
      firstName.isNotEmpty ? firstName.substring(0, 1).toUpperCase() : '?';

  bool get isOnline {
    final seen = lastSeenAt;
    if (seen == null) return false;
    return DateTime.now().toUtc().difference(seen.toUtc()).inMinutes < 6;
  }
}

class RosterStudent {
  final String id;
  final String firstName;
  final String lastName;
  final String studentIdNo;
  final bool isActive;

  const RosterStudent({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.studentIdNo,
    required this.isActive,
  });

  String get fullName {
    final n = '$firstName $lastName'.trim();
    return n.isEmpty ? studentIdNo : n;
  }

  String get initial =>
      firstName.isNotEmpty ? firstName.substring(0, 1).toUpperCase() : '?';
}

/// Leadership roster management for staff and students.
class RosterManageScreen extends ConsumerWidget {
  const RosterManageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identityAsync = ref.watch(identityProvider);
    final identity = identityAsync.valueOrNull;

    if (identity == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Manage roster')),
        body: identityAsync.hasError
            ? ErrorView(
                message: identityAsync.error is IdentityException
                    ? (identityAsync.error! as IdentityException).message
                    : 'Could not load your profile. Try again.',
                onRetry: () => ref.invalidate(identityProvider),
              )
            : const LoadingView(),
      );
    }

    // Students manage nobody — including themselves.
    if (identity.tier == AppTier.student) {
      return Scaffold(
        appBar: AppBar(title: const Text('Manage roster')),
        body: const EmptyView(
          title: 'Not available',
          subtitle: 'Roster management is for teachers and school leadership.',
          icon: Icons.lock_outline,
        ),
      );
    }

    return _RosterManageBody(identity: identity);
  }
}

class _RosterManageBody extends ConsumerStatefulWidget {
  final AppIdentity identity;
  const _RosterManageBody({required this.identity});

  @override
  ConsumerState<_RosterManageBody> createState() => _RosterManageBodyState();
}

class _RosterManageBodyState extends ConsumerState<_RosterManageBody> {
  int _tab = _kTeachersTab;
  String _query = '';

  /// Ids with an RPC in flight, so their toggle can show progress.
  final Set<String> _busy = <String>{};

  String? _errorMessage;
  String? _errorCode;

  AppIdentity get identity => widget.identity;

  Future<void> _toggleTeacher(RosterTeacher teacher) async {
    final next = !teacher.isActive;
    if (!next) {
      final ok = await _confirmDeactivate(
        name: teacher.fullName,
        identifier: teacher.staffIdNo,
        noun: 'teacher',
      );
      if (!ok) return;
    }
    await _run(
      teacher.id,
      () => Supabase.instance.client.rpc(
        'set_staff_active',
        params: {'p_teacher_id': teacher.id, 'p_active': next},
      ),
    );
  }

  Future<void> _toggleStudent(RosterStudent student) async {
    final next = !student.isActive;
    if (!next) {
      final ok = await _confirmDeactivate(
        name: student.fullName,
        identifier: student.studentIdNo,
        noun: 'student',
      );
      if (!ok) return;
    }
    await _run(
      student.id,
      () => Supabase.instance.client.rpc(
        'set_student_active',
        params: {'p_student_id': student.id, 'p_active': next},
      ),
    );
  }

  Future<void> _run(String id, Future<Object?> Function() action) async {
    setState(() {
      _busy.add(id);
      _errorMessage = null;
      _errorCode = null;
    });
    try {
      await action();
      ref.invalidate(_rosterProvider);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _describeRosterError(e);
        _errorCode = e.code;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not reach the school server. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  /// Deactivation ends real access, so it is never a single tap.
  Future<bool> _confirmDeactivate({
    required String name,
    required String identifier,
    required String noun,
  }) async {
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(Icons.person_off_outlined, color: scheme.error),
        title: Text('Deactivate this $noun?'),
        content: Text(
          '$name ($identifier) is signed out of the school immediately. They lose '
          'access to classes, messages, notices and school files until someone '
          'reactivates them.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Deactivate $noun'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = TierAccent.of(identity.tier);
    final rosterAsync = ref.watch(_rosterProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Manage roster')),
      body: rosterAsync.when(
        loading: () => const LoadingView(message: 'Loading roster...'),
        error: (e, _) => ErrorView(
          message: e is PostgrestException
              ? _describeRosterError(e)
              : 'Could not load the roster. Try again.',
          onRetry: () => ref.invalidate(_rosterProvider),
        ),
        data: (roster) {
          final isTeachers = _tab == _kTeachersTab;
          final query = _query.trim().toLowerCase();

          final teachers =
              roster.teachers.where((t) => _matches(_teacherHaystack(t), query)).toList();
          final students = roster.students
              .where((s) => _matches(_studentHaystack(s), query))
              .toList();

          final total = isTeachers ? roster.teachers.length : roster.students.length;
          final activeCount = isTeachers
              ? roster.teachers.where((t) => t.isActive).length
              : roster.students.where((s) => s.isActive).length;
          final shown = isTeachers ? teachers.length : students.length;

          return RefreshIndicator(
            onRefresh: () => _refreshRoster(ref),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                GlossHero(
                  accent: accent,
                  eyebrow: 'Roster management',
                  title: 'Who has access',
                  subtitle: identity.schoolName.isEmpty
                      ? 'Deactivating someone signs them out of the school.'
                      : 'Deactivating someone signs them out of ${identity.schoolName}.',
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 124,
                        child: MetricTile(
                          icon: Icons.groups_outlined,
                          label: isTeachers ? 'Staff' : 'Students',
                          value: '$total',
                          accent: accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 124,
                        child: MetricTile(
                          icon: Icons.verified_outlined,
                          label: 'Active',
                          value: '$activeCount',
                          accent: accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 124,
                        child: MetricTile(
                          icon: Icons.person_off_outlined,
                          label: 'Inactive',
                          value: '${total - activeCount}',
                          accent: accent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _Segmented(
                  teachersSelected: isTeachers,
                  accent: accent,
                  onChanged: (t) => setState(() => _tab = t),
                ),
                const SizedBox(height: 14),
                if (_errorMessage != null) ...[
                  _ErrorBanner(message: _errorMessage!, code: _errorCode),
                  const SizedBox(height: 12),
                ],
                TextField(
                  textInputAction: TextInputAction.search,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: isTeachers
                        ? 'Search teacher name or staff ID'
                        : 'Search student name or ID',
                    prefixIcon: const Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text('$shown of $total', style: theme.textTheme.bodySmall),
                ),
                const SizedBox(height: 8),
                if (!isTeachers && roster.studentError != null)
                  SizedBox(
                    height: 200,
                    child: ErrorView(
                      message: roster.studentError!,
                      onRetry: () => ref.invalidate(_rosterProvider),
                    ),
                  )
                else if (isTeachers && teachers.isEmpty)
                  _EmptyRoster(
                    icon: Icons.person_search_outlined,
                    title: 'No staff match',
                    subtitle: query.isEmpty
                        ? 'This school has no teachers on the roster yet.'
                        : 'Try a different name or staff ID.',
                  )
                else if (!isTeachers && students.isEmpty)
                  _EmptyRoster(
                    icon: Icons.person_search_outlined,
                    title: 'No students match',
                    subtitle: query.isEmpty
                        ? 'This school has no students on the roster yet.'
                        : 'Try a different name or student ID.',
                  )
                else if (isTeachers)
                  for (final t in teachers) ...[
                    _TeacherRow(
                      teacher: t,
                      accent: accent,
                      isActive: t.isActive,
                      busy: _busy.contains(t.id),
                      onToggle: () => _toggleTeacher(t),
                    ),
                    const SizedBox(height: 10),
                  ]
                else
                  for (final s in students) ...[
                    _StudentRow(
                      student: s,
                      accent: accent,
                      isActive: s.isActive,
                      busy: _busy.contains(s.id),
                      onToggle: () => _toggleStudent(s),
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Two-way control switching between the staff and student rosters.
class _Segmented extends StatelessWidget {
  final bool teachersSelected;
  final TierAccent accent;
  final ValueChanged<int> onChanged;

  const _Segmented({
    required this.teachersSelected,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Segment(
              label: 'Teachers',
              icon: Icons.badge_outlined,
              selected: teachersSelected,
              accent: accent,
              onTap: () => onChanged(_kTeachersTab),
            ),
          ),
          Container(width: 1, height: 22, color: theme.dividerColor),
          Expanded(
            child: _Segment(
              label: 'Students',
              icon: Icons.school_outlined,
              selected: !teachersSelected,
              accent: accent,
              onTap: () => onChanged(_kStudentsTab),
            ),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final TierAccent accent;
  final VoidCallback onTap;

  const _Segment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: selected ? accent.solid : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? Colors.white : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TeacherRow extends StatelessWidget {
  final RosterTeacher teacher;
  final TierAccent accent;
  final bool isActive;
  final bool busy;
  final VoidCallback onToggle;

  const _TeacherRow({
    required this.teacher,
    required this.accent,
    required this.isActive,
    required this.busy,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 21,
              backgroundColor: teacher.isActive ? accent.soft : theme.colorScheme.surfaceContainerHighest,
              child: Text(
                teacher.initial,
                style: TextStyle(
                  color: teacher.isActive ? accent.onSoft : theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(teacher.fullName, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(teacher.staffIdNo, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (teacher.isLeadership)
                        _Pill(label: 'Leadership', fg: accent.onSoft, bg: accent.soft),
                      if (!teacher.isActive)
                        _Pill(
                          label: 'Inactive',
                          fg: AppColors.danger,
                          bg: AppColors.danger.withValues(alpha: 0.10),
                        )
                      else if (teacher.isOnline)
                        _Pill(
                          label: 'Online',
                          fg: AppColors.success,
                          bg: AppColors.success.withValues(alpha: 0.10),
                        )
                      else
                        _Pill(
                          label: _presenceLabel(teacher.lastSeenAt),
                          fg: theme.colorScheme.onSurfaceVariant,
                          bg: theme.colorScheme.surfaceContainerHighest,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            _Toggle(isActive: isActive, busy: busy, onToggle: onToggle),
          ],
        ),
      ),
    );
  }
}

class _StudentRow extends StatelessWidget {
  final RosterStudent student;
  final TierAccent accent;
  final bool isActive;
  final bool busy;
  final VoidCallback onToggle;

  const _StudentRow({
    required this.student,
    required this.accent,
    required this.isActive,
    required this.busy,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 21,
              backgroundColor:
                  student.isActive ? accent.soft : theme.colorScheme.surfaceContainerHighest,
              child: Text(
                student.initial,
                style: TextStyle(
                  color: student.isActive
                      ? accent.onSoft
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(student.fullName, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(student.studentIdNo, style: theme.textTheme.bodySmall),
                  if (!student.isActive) ...[
                    const SizedBox(height: 6),
                    _Pill(
                      label: 'Inactive',
                      fg: AppColors.danger,
                      bg: AppColors.danger.withValues(alpha: 0.10),
                    ),
                  ],
                ],
              ),
            ),
            _Toggle(isActive: isActive, busy: busy, onToggle: onToggle),
          ],
        ),
      ),
    );
  }
}

/// Active/inactive control for one person, replaced by a spinner while the
/// RPC is in flight. It names the action it will take rather than showing an
/// ambiguous switch that is pinned to `true`.
class _Toggle extends StatelessWidget {
  final bool isActive;
  final bool busy;
  final VoidCallback onToggle;
  const _Toggle({required this.isActive, required this.busy, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (isActive) {
      return SizedBox(
        width: 44,
        height: 44,
        child: IconButton(
          onPressed: onToggle,
          tooltip: 'Deactivate',
          icon: const Icon(Icons.person_off_outlined),
          color: Theme.of(context).colorScheme.error,
        ),
      );
    }
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        onPressed: onToggle,
        tooltip: 'Reactivate',
        icon: const Icon(Icons.person_add_alt_outlined),
        color: AppColors.success,
      ),
    );
  }
}

class _EmptyRoster extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyRoster({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: EmptyView(title: title, subtitle: subtitle, icon: icon),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color fg;
  final Color bg;
  const _Pill({required this.label, required this.fg, required this.bg});

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

class _ErrorBanner extends StatelessWidget {
  final String message;
  final String? code;
  const _ErrorBanner({required this.message, this.code});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 20, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurface),
                ),
                if (code != null && code!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Server said: $code', style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _teacherHaystack(RosterTeacher t) => '${t.fullName} ${t.staffIdNo}'.toLowerCase();
String _studentHaystack(RosterStudent s) => '${s.fullName} ${s.studentIdNo}'.toLowerCase();
bool _matches(String haystack, String query) =>
    query.isEmpty || haystack.contains(query);

String _presenceLabel(DateTime? seen) {
  if (seen == null) return 'Never seen';
  final minutes = DateTime.now().toUtc().difference(seen.toUtc()).inMinutes;
  if (minutes < 60) return 'Seen ${minutes}m ago';
  final hours = minutes ~/ 60;
  if (hours < 24) return 'Seen ${hours}h ago';
  return 'Seen ${hours ~/ 24}d ago';
}

/// The RPC's own reason, in plain words. `insufficient_permissions` means the
/// signed-in role may read the roster but not change it — never a connectivity
/// problem, and never reported as one.
String _describeRosterError(PostgrestException e) {
  final raw = e.message.trim();
  final lower = raw.toLowerCase();
  if (lower.contains('insufficient_permissions')) {
    return 'Your role cannot change who is active. Only a principal, school admin '
        'or platform owner can do this.';
  }
  if (lower.contains('not_found')) {
    return 'That person is no longer on this school roster.';
  }
  if (lower.contains('not_authenticated')) {
    return 'Your session has expired. Sign in again to manage the roster.';
  }
  if (lower.contains('row-level security')) {
    return 'Your role cannot change who is active at this school.';
  }
  if (raw.isNotEmpty && raw.length <= 160) return raw;
  return 'The change could not be saved. Please try again.';
}