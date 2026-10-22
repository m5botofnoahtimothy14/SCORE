import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';
import '../../mentor_desk/models/mentor_desk_models.dart';
import '../../mentor_desk/services/mentor_desk_service.dart';

final _serviceProvider = Provider<MentorDeskService>(
  (ref) => MentorDeskService(Supabase.instance.client),
);

/// Mentor queue: Asked for you / Waiting (shared) / My active. Shared queue
/// ordered: urgent first, escalated (>threshold), then oldest.
class MentorQueueScreen extends ConsumerStatefulWidget {
  const MentorQueueScreen({super.key});

  @override
  ConsumerState<MentorQueueScreen> createState() => _MentorQueueScreenState();
}

class _MentorQueueScreenState extends ConsumerState<MentorQueueScreen> {
  String _tab = 'waiting'; // waiting | asked | active
  List<DoubtRequest> _waiting = const [];
  List<DoubtRequest> _asked = const [];
  List<DoubtRequest> _active = const [];
  bool _loading = true;
  String? _error;
  String? _schoolId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final identity = await ref.read(identityProvider.future);
    _schoolId = identity.schoolId;
    final service = ref.read(_serviceProvider);
    final client = Supabase.instance.client;
    final rows = await client
        .from('doubt_requests')
        .select()
        .eq('school_id', _schoolId!)
        .order('created_at', ascending: false);
    final all = (rows as List)
        .map((r) => DoubtRequest.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
    final now = DateTime.now();
    final threshold = Duration(minutes: 30);
    final waiting = all.where((d) => d.status == 'waiting').toList()
      ..sort((a, b) {
        if (a.urgent != b.urgent) return b.urgent ? -1 : 1;
        final aEsc = now.difference(a.createdAt) > threshold;
        final bEsc = now.difference(b.createdAt) > threshold;
        if (aEsc != bEsc) return aEsc ? -1 : 1;
        return a.createdAt.compareTo(b.createdAt);
      });
    final me = Supabase.instance.client.auth.currentUser!.id;
    final asked = all.where((d) => d.status == 'assigned' && d.assignedMentorId == me).toList();
    final active = asked;
    if (!mounted) return;
    setState(() {
      _waiting = waiting;
      _asked = asked;
      _active = active;
      _loading = false;
    });
  }

  Future<void> _claim(DoubtRequest d) async {
    try {
      await ref.read(_serviceProvider).claimDoubt(d.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request claimed.')));
      _load();
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = TierAccent.of(AppTier.teacher);
    return Scaffold(
      appBar: AppBar(title: const Text('Mentor Queue')),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : Column(
                  children: [
                    ToggleButtons(
                      isSelected: [_tab == 'waiting', _tab == 'asked', _tab == 'active'],
                      onPressed: (i) => setState(() => _tab = ['waiting', 'asked', 'active'][i]),
                      children: const [
                        Icon(Icons.hourglass_bottom),
                        Icon(Icons.person),
                        Icon(Icons.auto_fix_high),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: _tab == 'waiting'
                          ? _List(doubts: _waiting, onClaim: _claim, empty: 'No requests waiting.')
                          : _tab == 'asked'
                              ? _List(doubts: _asked, onClaim: null, empty: 'No requests assigned to you.')
                              : _List(doubts: _active, onClaim: null, empty: 'No active requests.'),
                    ),
                  ],
                ),
    );
  }
}

class _List extends StatelessWidget {
  final List<DoubtRequest> doubts;
  final void Function(DoubtRequest)? onClaim;
  final String empty;
  const _List({required this.doubts, this.onClaim, required this.empty});
  @override
  Widget build(BuildContext context) {
    if (doubts.isEmpty) {
      return Center(child: EmptyView(title: empty, subtitle: 'Check back later.', icon: Icons.inbox_outlined));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemCount: doubts.length,
      itemBuilder: (context, i) {
        final d = doubts[i];
        return _Row(doubt: d, onClaim: onClaim);
      },
    );
  }
}

class _Row extends StatelessWidget {
  final DoubtRequest doubt;
  final void Function(DoubtRequest)? onClaim;
  const _Row({required this.doubt, this.onClaim});
  @override
  Widget build(BuildContext context) {
    final accent = TierAccent.of(AppTier.teacher);
    final waited = DateTime.now().difference(doubt.createdAt);
    final urgent = doubt.urgent;
    final escalated = waited.inMinutes > 30;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        title: Text(doubt.question, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                if (urgent) ...[
                  const Icon(Icons.flash_on, size: 14, color: Color(0xFFDC2626)),
                  const SizedBox(width: 6),
                  const Text('Urgent', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFDC2626))),
                  const SizedBox(width: 8),
                ],
                if (escalated) ...[
                  const Icon(Icons.warning_amber, size: 14, color: Color(0xFFD97706)),
                  const SizedBox(width: 6),
                  const Text('Escalated', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFD97706))),
                  const SizedBox(width: 8),
                ],
                Text('${waited.inMinutes}m waited', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
              ],
            ),
          ],
        ),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(doubt.statusLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _statusColor(doubt.status))),
            if (doubt.namedMentor) const Text('Named mentor', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
            if (onClaim != null && doubt.status == 'waiting') ...[
              const SizedBox(height: 6),
              SizedBox(
                width: 70,
                height: 32,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: accent.solid, foregroundColor: Colors.white),
                  onPressed: () => onClaim!(doubt),
                  icon: const Icon(Icons.handyman, size: 14),
                  label: const Text('Pick up', style: TextStyle(fontSize: 11)),
                ),
              ),
            ],
          ],
        ),
        onTap: () => context.go('/mentor-desk/doubt/${doubt.id}'),
      ),
    );
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
}
