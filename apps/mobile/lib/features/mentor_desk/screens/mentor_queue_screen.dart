import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mentor_desk_design.dart';
import '../../../core/layout/responsive.dart';
import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
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

    final List<DoubtRequest> allDoubts = (rows as List)
        .map((r) => DoubtRequest.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();

    final now = DateTime.now();
    const threshold = Duration(minutes: 30);

    final waiting = allDoubts.where((d) => d.status == 'waiting').toList()
      ..sort((a, b) {
        if (a.urgent != b.urgent) return b.urgent ? -1 : 1;
        final aEsc = now.difference(a.createdAt) > threshold;
        final bEsc = now.difference(b.createdAt) > threshold;
        if (aEsc != bEsc) return aEsc ? -1 : 1;
        return a.createdAt.compareTo(b.createdAt);
      });

    final me = Supabase.instance.client.auth.currentUser!.id;
    final asked = allDoubts.where((d) => d.status == 'assigned' && d.assignedMentorId == me).toList();
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
    const accent = MDTier.teacher;

    return Scaffold(
      backgroundColor: MDColors.ink50,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, title: const Text('Mentor Queue')),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.all(kGutter),
                      padding: const EdgeInsets.symmetric(horizontal: kGutter / 2, vertical: kGutter / 4),
                      decoration: BoxDecoration(
                        color: MDColors.ink100.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(kRadiusSm),
                        border: Border.all(color: MDColors.ink200.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _TabChip(
                              label: 'Waiting',
                              selected: _tab == 'waiting',
                              onTap: () => setState(() => _tab = 'waiting'),
                              icon: Icons.hourglass_bottom,
                            ),
                          ),
                          Expanded(
                            child: _TabChip(
                              label: 'Asked for you',
                              selected: _tab == 'asked',
                              onTap: () => setState(() => _tab = 'asked'),
                              icon: Icons.person,
                            ),
                          ),
                          Expanded(
                            child: _TabChip(
                              label: 'My active',
                              selected: _tab == 'active',
                              onTap: () => setState(() => _tab = 'active'),
                              icon: Icons.auto_fix_high,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: kGutter),
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

class _TabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData icon;
  const _TabChip({required this.label, required this.selected, required this.onTap, required this.icon});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(kRadiusSm),
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadiusSm),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: kGutter / 2),
          decoration: BoxDecoration(
            color: selected ? accentStart.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(kRadiusSm),
            border: Border.all(color: selected ? accentSolid : scheme.primary.withValues(alpha: 0.15)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: selected ? accentSolid : MDColors.ink600),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: selected ? accentSolid : MDColors.ink600)),
            ],
          ),
        ),
      ),
    );
  }
}

final Color accentSolid = MDTier.teacher.solid;
final Color accentStart = MDTier.teacher.start;

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
      padding: const EdgeInsets.all(kGutter),
      separatorBuilder: (_, __) => const SizedBox(height: kGutter / 2),
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
    const accent = MDTier.teacher;
    final waited = DateTime.now().difference(doubt.createdAt);
    final urgent = doubt.urgent;
    final escalated = waited.inMinutes > 30;
    return MDListCard(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: kGutter / 2, vertical: kGutter / 4),
        title: Text(doubt.question, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: kGutter / 4),
            Row(
              children: [
                if (urgent) ...[
                  const Icon(Icons.flash_on, size: 14, color: MDColors.danger),
                  const SizedBox(width: kGutter / 4),
                  const Text('Urgent', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: MDColors.danger)),
                  const SizedBox(width: kGutter / 2),
                ],
                if (escalated) ...[
                  const Icon(Icons.warning_amber, size: 14, color: MDColors.warning),
                  const SizedBox(width: kGutter / 4),
                  const Text('Escalated', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: MDColors.warning)),
                  const SizedBox(width: kGutter / 2),
                ],
                Text('${waited.inMinutes}m waited', style: const TextStyle(fontSize: 11, color: MDColors.ink600)),
              ],
            ),
          ],
        ),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(doubt.statusLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _statusColor(doubt.status))),
            if (doubt.namedMentor) const Text('Named mentor', style: TextStyle(fontSize: 10, color: MDColors.ink600)),
            if (onClaim != null && doubt.status == 'waiting') ...[
              const SizedBox(height: kGutter / 2),
              SizedBox(
                width: 70,
                height: 32,
                child: MDGlossButton(
                  height: 32,
                  padding: EdgeInsets.zero,
                  onPressed: () { if (onClaim != null) onClaim!(doubt); },
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [Icon(Icons.handyman, size: 14), SizedBox(width: 6), Text('Pick up', style: TextStyle(fontSize: 11))],
                  ),
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
      case 'waiting': return MDColors.warning;
      case 'assigned': return MDColors.brand;
      case 'resolved': return MDColors.success;
      case 'closed': return MDColors.ink600;
      default: return MDColors.ink600;
    }
  }
}
