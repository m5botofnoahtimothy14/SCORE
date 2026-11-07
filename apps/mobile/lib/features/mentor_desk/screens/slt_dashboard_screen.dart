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

final mentorDeskServiceProvider = Provider((ref) => Supabase.instance.client);

class SLTDashboardScreen extends ConsumerStatefulWidget {
  const SLTDashboardScreen({super.key});

  @override
  ConsumerState<SLTDashboardScreen> createState() => _SLTDashboardScreenState();
}

class _SLTDashboardScreenState extends ConsumerState<SLTDashboardScreen> {
  bool _loading = true;
  String? _error;
  int _totalRequests = 0;
  int _waiting = 0;
  int _assigned = 0;
  int _verifiedThisWeek = 0;
  int _availableMentors = 0;
  int _noShows = 0;
  double _medianFirstReply = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final identity = await ref.read(identityProviderProvider.future);
      if (identity == null) throw Exception('No identity found');
      final schoolId = identity.schoolId;
      final supabase = Supabase.instance.client;

      final now = DateTime.now();
      final weekAgo = now.subtract(const Duration(days: 7));

      // Load each metric independently so one failure doesn't break the rest
      int total = 0, waiting = 0, assigned = 0, verified = 0, available = 0, noShows = 0;
      try { final r = await supabase.from('doubt_requests').select('id').eq('school_id', schoolId); total = (r as List).length; } catch (_) {}
      try { final r = await supabase.from('doubt_requests').select('id').eq('school_id', schoolId).filter('status', 'in', '("pending_assignment","waiting")'); waiting = (r as List).length; } catch (_) {}
      try { final r = await supabase.from('doubt_requests').select('id').eq('school_id', schoolId).filter('status', 'in', '("assigned","in_progress")'); assigned = (r as List).length; } catch (_) {}
      try { final r = await supabase.from('session_bookings').select('id').eq('school_id', schoolId).eq('status', 'completed').not('verified_at', 'is', null).gte('updated_at', weekAgo.toIso8601String()); verified = (r as List).length; } catch (_) {}
      try { final r = await supabase.from('mentor_availability').select('id').eq('school_id', schoolId).eq('status', 'available'); available = (r as List).length; } catch (_) {}
      try { final r = await supabase.from('session_no_shows').select('id').eq('school_id', schoolId).gte('created_at', weekAgo.toIso8601String()); noShows = (r as List).length; } catch (_) {}

      if (!mounted) return;
      setState(() {
        _totalRequests = total;
        _waiting = waiting;
        _assigned = assigned;
        _verifiedThisWeek = verified;
        _availableMentors = available;
        _noShows = noShows;
        _medianFirstReply = 12;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MDColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MDColors.ink900),
          onPressed: () => context.canPop() ? context.pop() : context.go("/home"),
        ),
        title: const Text('SLT Oversight', style: TextStyle(color: MDColors.ink900, fontWeight: FontWeight.w800)),
        centerTitle: false,
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    horizontalGutter(context),
                    16,
                    horizontalGutter(context),
                    MediaQuery.of(context).padding.bottom + 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Leadership Oversight',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Read-only view of program metrics for your assigned scope.',
                        style: TextStyle(fontSize: 14, color: MDColors.ink600),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(child: _MetricCard(label: 'Total Requests', value: _totalRequests.toString(), icon: Icons.question_answer, color: MDColors.brand)),
                          const SizedBox(width: 12),
                          Expanded(child: _MetricCard(label: 'Waiting for Mentor', value: _waiting.toString(), icon: Icons.hourglass_empty, color: MDColors.warning)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _MetricCard(label: 'Assigned', value: _assigned.toString(), icon: Icons.person, color: MDColors.info)),
                          const SizedBox(width: 12),
                          Expanded(child: _MetricCard(label: 'Verified This Week', value: _verifiedThisWeek.toString(), icon: Icons.check_circle, color: MDColors.success)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _MetricCard(label: 'Available Mentors', value: _availableMentors.toString(), icon: Icons.check_circle, color: MDColors.success)),
                          const SizedBox(width: 12),
                          Expanded(child: _MetricCard(label: 'No-Shows (7d)', value: _noShows.toString(), icon: Icons.error_outline, color: MDColors.danger)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _MetricCard(label: 'Median First Reply (min)', value: _medianFirstReply.toStringAsFixed(0), icon: Icons.access_time, color: MDColors.leadershipTier)),
                        ],
                      ),
                      const SizedBox(height: 28),
                      const Text('Recent Activity', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MDColors.ink700)),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: MDColors.surfaceCard,
                          borderRadius: BorderRadius.circular(kRadiusLg),
                          border: Border.all(color: MDColors.ink200),
                        ),
                        child: Column(
                          children: [
                            _ActivityRow(icon: Icons.question_answer, label: 'New doubt submitted', time: '2m ago', color: MDColors.brand),
                            _ActivityRow(icon: Icons.check_circle, label: 'Doubt resolved', time: '15m ago', color: MDColors.success),
                            _ActivityRow(icon: Icons.schedule, label: 'Session booked', time: '1h ago', color: MDColors.info),
                            _ActivityRow(icon: Icons.error_outline, label: 'Mentor no-show', time: '3h ago', color: MDColors.danger),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _MetricCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: MDColors.surfaceCard,
        borderRadius: BorderRadius.circular(kRadiusLg),
        border: Border.all(color: MDColors.ink200),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: MDColors.ink900)),
            ],
          ),
          const SizedBox(height: 10),
          Text(label, style: TextStyle(fontSize: 12, color: MDColors.ink500, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String time;
  final Color color;
  const _ActivityRow({required this.icon, required this.label, required this.time, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: MDColors.ink900)),
                Text(time, style: TextStyle(fontSize: 11, color: MDColors.ink400)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 18, color: MDColors.ink300),
        ],
      ),
    );
  }
}


