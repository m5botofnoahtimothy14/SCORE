import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mentor_desk_design.dart';
import '../../../core/layout/responsive.dart';
import '../../../core/widgets/states.dart';
import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../models/mentor_desk_models.dart';
import '../services/mentor_desk_service.dart';

final mentorDeskServiceProvider = Provider<MentorDeskService>((ref) {
  return MentorDeskService(Supabase.instance.client);
});

class MentorQueueScreen extends ConsumerStatefulWidget {
  const MentorQueueScreen({super.key});

  @override
  ConsumerState<MentorQueueScreen> createState() => _MentorQueueScreenState();
}

class _MentorQueueScreenState extends ConsumerState<MentorQueueScreen>
    with TickerProviderStateMixin {
  int _tabIndex = 0; // 0 = Asked for you, 1 = Waiting, 2 = My active

  bool _loading = true;
  String? _error;
  List<DoubtRequest> _askedForYou = [];
  List<DoubtRequest> _waiting = [];
  List<DoubtRequest> _myActive = [];
  String? _myUserId;
  String? _schoolId;
  AppTier? _myTier;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(vsync: this, length: 3);
    _tabController.addListener(() {
      if (!mounted) return;
      setState(() { _tabIndex = _tabController.index; });
    });
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final identity = await ref.read(identityProviderProvider.future);
      if (identity == null) throw Exception('No identity found');
      _myUserId = identity.userId;
      _myTier = identity.tier;
      _schoolId = identity.schoolId;

      final supabase = Supabase.instance.client;

      // Load all doubt requests for the school
      final rows = await supabase
          .from('doubt_requests')
          .select()
          .eq('school_id', _schoolId!)
          .order('created_at', ascending: false);

      final all = (rows as List)
          .map((r) => DoubtRequest.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();

      final now = DateTime.now();
      final thresholdMinutes = 30;

      _askedForYou = all.where((r) => r.namedMentor && r.assignedMentorId == _myUserId).toList();
      _myActive = all.where((r) => r.assignedMentorId == _myUserId && !r.namedMentor).toList();
      _waiting = all.where((r) {
        final status = r.status;
        return status == 'pending_assignment' || status == 'waiting';
      }).toList()..sort((a, b) {
        final aUrgent = a.urgent;
        final bUrgent = b.urgent;
        if (aUrgent != bUrgent) return bUrgent ? -1 : 1;
        final aWait = now.difference(a.createdAt).inMinutes;
        final bWait = now.difference(b.createdAt).inMinutes;
        final aEsc = aWait > thresholdMinutes;
        final bEsc = bWait > thresholdMinutes;
        if (aEsc != bEsc) return aEsc ? -1 : 1;
        return a.createdAt.compareTo(b.createdAt);
      });

      if (!mounted) return;
      setState(() { _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _claim(DoubtRequest request) async {
    setState(() { _loading = true; });
    try {
      final service = ref.read(mentorDeskServiceProvider);
      await service.claimDoubt(request.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Request claimed.'),
        backgroundColor: MDColors.success,
        duration: Duration(seconds: 3),
      ));
      await _load();
    } on MentorDeskException catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.message; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _resolve(DoubtRequest request) async {
    setState(() { _loading = true; });
    try {
      final service = ref.read(mentorDeskServiceProvider);
      await service.resolveDoubt(request.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Request resolved.'),
        backgroundColor: MDColors.success,
        duration: Duration(seconds: 3),
      ));
      await _load();
    } on MentorDeskException catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.message; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  List<DoubtRequest> get _currentList {
    switch (_tabIndex) {
      case 0: return _askedForYou;
      case 1: return _waiting;
      default: return _myActive;
    }
  }

  String _tabTitle(int i) => switch (i) {
    0 => 'Asked for You',
    1 => 'Waiting (Shared Queue)',
    _ => 'My Active',
  };

  IconData _tabIcon(int i) => switch (i) {
    0 => Icons.person,
    1 => Icons.queue,
    _ => Icons.check_circle,
  };

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
        title: const Text('Mentor Queue', style: TextStyle(color: MDColors.ink900, fontWeight: FontWeight.w800)),
        centerTitle: false,
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : Column(
                  children: [
                    _buildTabs(context),
                    Expanded(
                      child: _currentList.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _tabIndex == 1 ? Icons.inbox : Icons.assignment_outlined,
                                    size: 56,
                                    color: MDColors.ink300,
                                  ),
                                  const SizedBox(height: 16),
                                  Text('No ${_tabTitle(_tabIndex).toLowerCase()}',
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: MDColors.ink900)),
                                  const SizedBox(height: 8),
                                  Text(_tabIndex == 1 ? 'No waiting requests right now.' : 'No active requests.',
                                      style: TextStyle(fontSize: 13, color: MDColors.ink500)),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: EdgeInsets.fromLTRB(
                                horizontalGutter(context),
                                8,
                                horizontalGutter(context),
                                MediaQuery.of(context).padding.bottom + 16,
                              ),
                              itemCount: _currentList.length,
                              itemBuilder: (context, index) {
                                final req = _currentList[index];
                                return _RequestCard(
                                  request: req,
                                  onClaim: () => _claim(req),
                                  onResolve: () => _resolve(req),
                                  isMine: req.assignedMentorId == _myUserId,
                                  canClaim: _tabIndex == 1 && req.assignedMentorId == null,
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildTabs(BuildContext context) {
    final tabs = [
      Tab(icon: Icon(_tabIcon(0)), text: _tabTitle(0)),
      Tab(icon: Icon(_tabIcon(1)), text: _tabTitle(1)),
      Tab(icon: Icon(_tabIcon(2)), text: _tabTitle(2)),
    ];
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: tabs,
          labelColor: MDColors.brand,
          unselectedLabelColor: MDColors.ink500,
          indicatorColor: MDColors.brand,
        ),
        const SizedBox(height: 8),
        Container(
          padding: EdgeInsets.symmetric(horizontal: horizontalGutter(context)),
          child: Text(
            _tabIndex == 1
                ? 'Queue ordered by urgent \u2192 escalated \u2192 oldest. Escalation threshold: 30 min.'
                : 'Requests assigned to you.',
            style: TextStyle(fontSize: 11.5, color: MDColors.ink500),
          ),
        ),
      ],
    );
  }
}

class _RequestCard extends StatelessWidget {
  final DoubtRequest request;
  final VoidCallback onClaim;
  final VoidCallback onResolve;
  final bool isMine;
  final bool canClaim;

  const _RequestCard({
    required this.request,
    required this.onClaim,
    required this.onResolve,
    required this.isMine,
    required this.canClaim,
  });

  @override
  Widget build(BuildContext context) {
    final waitMinutes = DateTime.now().difference(request.createdAt).inMinutes;
    final isUrgent = request.urgent;
    final isEscalated = waitMinutes > 30;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: MDColors.surfaceCard,
        borderRadius: BorderRadius.circular(kRadiusLg),
        border: Border.all(color: MDColors.ink200),
        boxShadow: [
          BoxShadow(color: MDColors.brand.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.question,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: MDColors.ink900),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (isUrgent)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: MDColors.danger.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: MDColors.danger.withValues(alpha: 0.4)),
                              ),
                              child: const Text('URGENT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: MDColors.danger, letterSpacing: 0.8)),
                            ),
                          if (isUrgent) const SizedBox(width: 8),
                          if (isEscalated)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: MDColors.warning.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: MDColors.warning.withValues(alpha: 0.4)),
                              ),
                              child: const Text('ESCALATED', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: MDColors.warning, letterSpacing: 0.8)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Text(
                  '${waitMinutes}m',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: isEscalated ? MDColors.danger : MDColors.ink500),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${request.subjectName ?? 'Subject'} \u00b7 ${request.studentName ?? 'Student'}',
                    style: const TextStyle(fontSize: 12, color: MDColors.ink500),
                  ),
                ),
                if (request.urgentReason != null && request.urgentReason!.isNotEmpty)
                  SizedBox(
                    width: 200,
                    child: Text(
                      'Reason: ${request.urgentReason}',
                      style: const TextStyle(fontSize: 11, color: MDColors.danger, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (canClaim)
                  Expanded(
                    child: MDButton(
                      onPressed: onClaim,
                      fullWidth: false,
                      height: 44,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [Icon(Icons.handyman, size: 16), SizedBox(width: 6), Text('Pick Up', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800))],
                      ),
                    ),
                  ),
                if (canClaim) const SizedBox(width: 10),
                if (isMine)
                  Expanded(
                    child: MDGlossOutlineButton(
                      onPressed: onResolve,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [Icon(Icons.check_circle_outline, size: 16), SizedBox(width: 6), Text('Resolve', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800))],
                      ),
                    ),
                  ),
              ],
            ),
            if (request.assignedMentorId != null && !isMine)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Assigned to another mentor',
                    style: TextStyle(fontSize: 11, color: MDColors.ink500, fontStyle: FontStyle.italic)),
              ),
          ],
        ),
      ),
    );
  }
}


