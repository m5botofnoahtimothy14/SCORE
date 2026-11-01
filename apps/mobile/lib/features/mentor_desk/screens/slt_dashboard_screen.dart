import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart';

class SLTDashboardScreen extends ConsumerStatefulWidget {
  const SLTDashboardScreen({super.key});

  @override
  ConsumerState<SLTDashboardScreen> createState() => _SLTDashboardScreenState();
}

class _SLTDashboardScreenState extends ConsumerState<SLTDashboardScreen> {
  bool _loading = true;
  String? _error;
  int _openDoubts = 0;
  int _urgentDoubts = 0;
  int _activeTeachers = 0;
  int _activeStudents = 0;
  int _upcomingSessions = 0;
  List<Map<String, dynamic>> _recent = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final identity = await ref.read(identityProviderProvider.future);
      if (identity == null || identity.tier != AppTier.leadership) {
        throw Exception('Leadership access is required.');
      }
      final client = Supabase.instance.client;
      final results = await Future.wait([
        client.from('doubt_requests').select('id, question, status, urgent, created_at').eq('school_id', identity.schoolId).order('created_at', ascending: false).limit(300),
        client.from('teachers').select('id').eq('school_id', identity.schoolId).eq('is_active', true),
        client.from('students').select('id').eq('school_id', identity.schoolId).eq('is_active', true),
        client.from('session_bookings').select('id, status, scheduled_at').eq('school_id', identity.schoolId).inFilter('status', ['requested', 'confirmed']).limit(300),
      ]);
      final doubts = (results[0] as List).map((row) => Map<String, dynamic>.from(row as Map)).toList();
      final teachers = results[1] as List;
      final students = results[2] as List;
      final sessions = results[3] as List;
      final open = doubts.where((row) => ['pending_assignment', 'waiting', 'assigned', 'in_progress'].contains(row['status'])).toList();
      final urgent = open.where((row) => row['urgent'] == true).length;
      if (!mounted) return;
      setState(() {
        _openDoubts = open.length;
        _urgentDoubts = urgent;
        _activeTeachers = teachers.length;
        _activeStudents = students.length;
        _upcomingSessions = sessions.length;
        _recent = doubts.take(8).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = 'Could not load the leadership overview. Check access and connection.'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('School oversight'), actions: [IconButton(onPressed: _load, tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded))]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(18),
                    children: [
                      const Text('Operational overview', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink900)),
                      const SizedBox(height: 5),
                      const Text('A current view of Mentor Desk activity and school membership.', style: TextStyle(fontSize: 12, color: AppColors.ink500)),
                      const SizedBox(height: 18),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 1.55,
                        children: [
                          _Metric(title: 'Open doubts', value: '$_openDoubts', icon: Icons.question_answer_outlined, color: AppColors.accent),
                          _Metric(title: 'Urgent doubts', value: '$_urgentDoubts', icon: Icons.priority_high_rounded, color: AppColors.danger),
                          _Metric(title: 'Active teachers', value: '$_activeTeachers', icon: Icons.co_present_outlined, color: AppColors.teacherTier),
                          _Metric(title: 'Active students', value: '$_activeStudents', icon: Icons.school_outlined, color: AppColors.studentTier),
                          _Metric(title: 'Open sessions', value: '$_upcomingSessions', icon: Icons.calendar_month_outlined, color: AppColors.leadershipTier),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Text('Recent student requests', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink900)),
                      const SizedBox(height: 10),
                      if (_recent.isEmpty)
                        const Text('No requests have been recorded yet.', style: TextStyle(color: AppColors.ink500, fontSize: 13))
                      else
                        ..._recent.map((item) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.ink200)),
                          child: Row(
                            children: [
                              Icon(item['urgent'] == true ? Icons.priority_high_rounded : Icons.chat_bubble_outline, color: item['urgent'] == true ? AppColors.danger : AppColors.accent),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(item['question']?.toString() ?? 'Student request', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink900)),
                                  const SizedBox(height: 4),
                                  Text((item['status']?.toString() ?? 'unknown').replaceAll('_', ' '), style: const TextStyle(fontSize: 11, color: AppColors.ink500)),
                                ]),
                              ),
                            ],
                          ),
                        )),
                    ],
                  ),
                ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.title, required this.value, required this.icon, required this.color});
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: AppColors.ink200)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Icon(icon, color: color, size: 20),
      Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.ink900)),
      Text(title, style: const TextStyle(fontSize: 11, color: AppColors.ink500)),
    ]),
  );
}
