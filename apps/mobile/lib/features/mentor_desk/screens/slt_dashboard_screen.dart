import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/layout/responsive.dart';
import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mentor_desk_design.dart';
import '../../../core/widgets/states.dart';

final _client = Supabase.instance.client;

/// SLT oversight dashboard — read-only, scoped by administrator-granted
/// program/batch/campus/organisation. No private notes, private assessments,
/// session codes, or unrestricted conversations.
class SLTDashboardScreen extends ConsumerStatefulWidget {
  const SLTDashboardScreen({super.key});

  @override
  ConsumerState<SLTDashboardScreen> createState() => _SLTDashboardScreenState();
}

class _SLTDashboardScreenState extends ConsumerState<SLTDashboardScreen> {
  Map<String, dynamic> _metrics = {};
  List<Map<String, dynamic>> _subjectDemand = const [];
  List<Map<String, dynamic>> _recent = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final identity = await ref.read(identityProvider.future);
      final schoolId = identity.schoolId;
      final metrics = <String, dynamic>{};
      final total = await _client.from('doubt_requests').select('id').eq('school_id', schoolId);
      metrics['total_requests'] = (total as List).length;

      final waiting = await _client.from('doubt_requests').select('id').eq('school_id', schoolId).eq('status', 'waiting');
      metrics['waiting'] = (waiting as List).length;

      final assigned = await _client.from('doubt_requests').select('id').eq('school_id', schoolId).eq('status', 'assigned');
      metrics['assigned'] = (assigned as List).length;

      final resolved = await _client.from('doubt_requests').select('id').eq('school_id', schoolId).inFilter('status', ['resolved', 'closed']);
      metrics['resolved'] = (resolved as List).length;

      final confirmed = await _client.from('session_bookings').select('id').eq('school_id', schoolId).eq('status', 'confirmed');
      metrics['confirmed_sessions'] = (confirmed as List).length;

      final available = await _client.from('mentor_availability').select('id').eq('school_id', schoolId).eq('status', 'available');
      metrics['available_mentors'] = (available as List).length;

      final noShows = await _client.from('session_no_shows').select('id').eq('school_id', schoolId).eq('review_status', 'pending');
      metrics['pending_no_shows'] = (noShows as List).length;

      final subjRows = await _client.from('subjects').select('id, name').eq('school_id', schoolId);
      final subjectDemand = <Map<String, dynamic>>[];
      for (final s in (subjRows as List)) {
        final sid = (s as Map)['id'] as String;
        final cnt = await _client.from('doubt_requests').select('id').eq('school_id', schoolId).eq('subject_id', sid);
        subjectDemand.add({'name': (s)['name'] as String, 'count': (cnt as List).length});
      }
      subjectDemand.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

      final recentRows = await _client.from('doubt_requests').select('*, subjects(name)').eq('school_id', schoolId).order('created_at', ascending: false).limit(10);
      final recent = (recentRows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();

      if (!mounted) return;
      setState(() {
        _metrics = metrics;
        _subjectDemand = subjectDemand;
        _recent = recent;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = MDTier.slt;

    return Scaffold(
      backgroundColor: MDColors.ink50,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, title: const Text('SLT Oversight')),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : AdaptivePage(
                  maxWidth: 1100,
                  child: ListView(
                    padding: const EdgeInsets.all(kGutter),
                    children: [
                      const Text('Senior Leadership Team — Mentor Desk oversight', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: kGutter / 2),
                      const Text('Read-only. Scoped to your granted program / batch / campus.', style: TextStyle(fontSize: 12, color: MDColors.ink600)),
                      const SizedBox(height: kGutter * 2),
                      AdaptiveGrid(
                        minColumns: 2,
                        maxColumns: 4,
                        itemExtent: 110,
                        spacing: kGutter,
                        children: [
                          _MetricTile(icon: Icons.question_answer, label: 'Total requests', value: '${_metrics['total_requests'] ?? 0}', tier: MDTier.slt),
                          _MetricTile(icon: Icons.hourglass_bottom, label: 'Waiting', value: '${_metrics['waiting'] ?? 0}', tier: MDTier.slt),
                          _MetricTile(icon: Icons.person, label: 'Assigned', value: '${_metrics['assigned'] ?? 0}', tier: MDTier.slt),
                          _MetricTile(icon: Icons.check_circle, label: 'Resolved', value: '${_metrics['resolved'] ?? 0}', tier: MDTier.slt),
                          _MetricTile(icon: Icons.schedule, label: 'Confirmed sessions', value: '${_metrics['confirmed_sessions'] ?? 0}', tier: MDTier.slt),
                          _MetricTile(icon: Icons.check_circle_outline, label: 'Available mentors', value: '${_metrics['available_mentors'] ?? 0}', tier: MDTier.slt),
                          _MetricTile(icon: Icons.report_outlined, label: 'Pending no-shows', value: '${_metrics['pending_no_shows'] ?? 0}', tier: MDTier.slt),
                        ],
                      ),
                      const SizedBox(height: kGutter * 2),
                      const MDSectionHeader(title: 'Subject-level demand'),
                      const SizedBox(height: kGutter),
                      SizedBox(
                        height: 200,
                        child: _subjectDemand.isEmpty
                            ? const Center(child: Text('No data.'))
                            : ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _subjectDemand.length,
                                separatorBuilder: (_, __) => const SizedBox(width: kGutter),
                                itemBuilder: (context, i) {
                                  final d = _subjectDemand[i];
                                  return SizedBox(
                                    width: 140,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(d['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                                        const SizedBox(height: kGutter / 2),
                                        Container(
                                          height: 120,
                                          width: 20,
                                          decoration: BoxDecoration(color: MDColors.ink200.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(6)),
                                          child: FractionallySizedBox(
                                            alignment: Alignment.bottomCenter,
                                            heightFactor: ((d['count'] as int) / 10).clamp(0.0, 1.0),
                                            child: Container(color: accent.solid),
                                          ),
                                        ),
                                        const SizedBox(height: kGutter / 2),
                                        Text('${d['count']}', style: const TextStyle(fontSize: 12, color: MDColors.ink600)),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: kGutter * 2),
                      const MDSectionHeader(title: 'Recent requests'),
                      const SizedBox(height: kGutter),
                      if (_recent.isEmpty)
                        const EmptyView(title: 'No requests', subtitle: 'Nothing to show.', icon: Icons.inbox_outlined)
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          separatorBuilder: (_, __) => const SizedBox(height: kGutter / 2),
                          itemCount: _recent.length,
                          itemBuilder: (context, i) {
                            final r = _recent[i];
                            return MDListCard(
                              child: ListTile(
                                title: Text((r['question'] as String?) ?? ''),
                                subtitle: Text('${r['subjects'] is Map ? (r['subjects'] as Map)['name'] : 'Subject'} · ${r['status']}'),
                                trailing: Text(_ago(r['created_at'] as String?)),
                                onTap: () => context.go('/mentor-desk/doubt/${r['id']}'),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
    );
  }

  String _ago(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final MDTier tier;
  const _MetricTile({required this.icon, required this.label, required this.value, required this.tier});
  @override
  Widget build(BuildContext context) {
    return MDMetricTile(
      icon: icon,
      label: label,
      value: value,
      tier: tier,
    );
  }
}
