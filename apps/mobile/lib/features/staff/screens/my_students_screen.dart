import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/layout/responsive.dart';
import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';

class _StudentRow {
  final String id;
  final String name;
  final String studentIdNo;
  final String? className;
  final bool isActive;
  const _StudentRow({
    required this.id,
    required this.name,
    required this.studentIdNo,
    this.className,
    required this.isActive,
  });
}

/// Teacher surface: every student assigned to this teacher's classes, grouped
/// by class, so a teacher always knows exactly who they are speaking with.
class MyStudentsScreen extends ConsumerStatefulWidget {
  const MyStudentsScreen({super.key});

  @override
  ConsumerState<MyStudentsScreen> createState() => _MyStudentsScreenState();
}

class _MyStudentsScreenState extends ConsumerState<MyStudentsScreen> {
  bool _loading = true;
  String? _error;
  String _query = '';
  String _classFilter = '';
  List<_StudentRow> _students = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final identity = await ref.read(identityProvider.future);
      final client = Supabase.instance.client;
      final teacherId = identity.teacherId;

      if (teacherId == null) {
        if (!mounted) return;
        setState(() {
          _students = const [];
          _loading = false;
        });
        return;
      }

      // Classes this teacher teaches.
      final classIds = identity.classIds;
      if (classIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _students = const [];
          _loading = false;
        });
        return;
      }

      final classRows = await client
          .from('classes')
          .select('id, name')
          .inFilter('id', classIds)
          .eq('school_id', identity.schoolId);
      final classNames = <String, String>{};
      for (final c in (classRows as List)) {
        final m = c as Map;
        classNames[m['id'] as String] = (m['name'] as String?) ?? '';
      }

      final enr = await client
          .from('class_enrollments')
          .select('student_id, class_id')
          .inFilter('class_id', classIds)
          .eq('school_id', identity.schoolId)
          .isFilter('unenrolled_at', null);

      final byStudent = <String, String?>{};
      for (final e in (enr as List)) {
        final m = e as Map;
        final sid = m['student_id'] as String?;
        final cid = m['class_id'] as String?;
        if (sid != null && cid != null) byStudent[sid] = classNames[cid];
      }

      if (byStudent.isEmpty) {
        if (!mounted) return;
        setState(() {
          _students = const [];
          _loading = false;
        });
        return;
      }

      final rows = await client
          .from('students')
          .select('id, first_name, last_name, student_id_no, is_active')
          .inFilter('id', byStudent.keys.toList())
          .eq('school_id', identity.schoolId)
          .order('first_name');

      final students = (rows as List).map((r) {
        final m = r as Map;
        final id = m['id'] as String;
        return _StudentRow(
          id: id,
          name: '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim(),
          studentIdNo: (m['student_id_no'] as String?) ?? '',
          className: byStudent[id],
          isActive: m['is_active'] == true,
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _students = students;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is IdentityException ? e.message : 'Could not load your students.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = TierAccent.of(AppTier.teacher);

    final filtered = _students.where((s) {
      if (_classFilter.isNotEmpty && s.className != _classFilter) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return '${s.name} ${s.studentIdNo} ${s.className ?? ''}'.toLowerCase().contains(q);
    }).toList();

    final classes = <String>{
      for (final s in _students)
        if (s.className != null) s.className!,
    }.toList()
      ..sort();

    return Scaffold(
      appBar: AppBar(title: const Text('My Students')),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: AdaptivePage(
                    child: CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate([
                            GlossHero(
                              accent: accent,
                              eyebrow: 'My caseload',
                              title: '${_students.length} ${_students.length == 1 ? 'Student' : 'Students'}',
                              subtitle: _students.isEmpty
                                  ? 'No students are assigned to your classes yet.'
                                  : 'Across ${classes.length} ${classes.length == 1 ? 'class' : 'classes'} you teach.',
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          style: const TextStyle(color: Colors.white, fontSize: 14),
                                          cursorColor: Colors.white,
                                          decoration: InputDecoration(
                                            isDense: true,
                                            hintText: 'Search name or student ID',
                                            hintStyle: TextStyle(
                                              color: Colors.white.withValues(alpha: 0.7),
                                              fontSize: 14,
                                            ),
                                            prefixIcon: Icon(
                                              Icons.search,
                                              size: 20,
                                              color: Colors.white.withValues(alpha: 0.85),
                                            ),
                                            filled: true,
                                            fillColor: Colors.white.withValues(alpha: 0.16),
                                            contentPadding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 12),
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(12),
                                              borderSide: BorderSide(
                                                  color: Colors.white.withValues(alpha: 0.25)),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(12),
                                              borderSide: BorderSide(
                                                  color: Colors.white.withValues(alpha: 0.25)),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(12),
                                              borderSide:
                                                  BorderSide(color: Colors.white.withValues(alpha: 0.7)),
                                            ),
                                          ),
                                          onChanged: (v) => setState(() => _query = v),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ]),
                        ),
                      ),
                      if (classes.length > 1)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
                          sliver: SliverToBoxAdapter(
                            child: SizedBox(
                              height: 36,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: [
                                  _FilterChip(
                                    label: 'All classes',
                                    selected: _classFilter.isEmpty,
                                    accent: accent,
                                    onTap: () => setState(() => _classFilter = ''),
                                  ),
                                  for (final c in classes)
                                    _FilterChip(
                                      label: c,
                                      selected: _classFilter == c,
                                      accent: accent,
                                      onTap: () => setState(() => _classFilter = c),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(0, 14, 0, 24),
                        sliver: filtered.isEmpty
                            ? SliverToBoxAdapter(
                                child: Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(28),
                                    child: Center(
                                      child: Column(
                                        children: [
                                          Icon(Icons.groups_outlined,
                                              size: 44, color: accent.solid.withValues(alpha: 0.5)),
                                          const SizedBox(height: 12),
                                          Text(
                                            _students.isEmpty
                                                ? 'No students assigned yet'
                                                : 'No students match your search',
                                            style: Theme.of(context).textTheme.titleMedium,
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            _students.isEmpty
                                                ? 'Students appear here once they are enrolled into your classes.'
                                                : 'Try a different name, ID or class filter.',
                                            textAlign: TextAlign.center,
                                            style: Theme.of(context).textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : SliverList.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (context, i) =>
_StudentCard(student: filtered[i], accent: accent),
                                ),
                      ),
                      ],
                    ),
                  ),
                ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final TierAccent accent;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: selected ? accent.soft : Colors.transparent,
            border: Border.all(
              color: selected ? accent.solid.withValues(alpha: 0.35) : Theme.of(context).dividerColor,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? accent.onSoft : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _StudentCard extends StatelessWidget {
  final _StudentRow student;
  final TierAccent accent;
  const _StudentCard({required this.student, required this.accent});

  @override
  Widget build(BuildContext context) {
    final initials = student.name.isEmpty
        ? '?'
        : student.name
            .split(' ')
            .where((w) => w.isNotEmpty)
            .take(2)
            .map((w) => w[0].toUpperCase())
            .join();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 21,
              backgroundColor: accent.soft,
              child: Text(
                initials,
                style: TextStyle(
                  color: accent.onSoft,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          student.name.isEmpty ? 'Unnamed student' : student.name,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (!student.isActive) ...[
                        const SizedBox(width: 6),
                        const _Pill(label: 'Inactive', color: Color(0xFF64748B), bg: Color(0xFFF1F5F9)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (student.studentIdNo.isNotEmpty) student.studentIdNo,
                      if (student.className != null && student.className!.isNotEmpty) student.className!,
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Message student',
              onPressed: () => context.go('/conversations'),
              icon: Icon(Icons.chat_bubble_outline, color: accent.solid),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;
  const _Pill({required this.label, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}