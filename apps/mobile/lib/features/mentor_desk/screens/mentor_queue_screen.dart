import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../models/mentor_desk_models.dart';
import '../services/mentor_desk_service.dart';

final _mentorServiceProvider = Provider((ref) => MentorDeskService(Supabase.instance.client));

class MentorQueueScreen extends ConsumerStatefulWidget {
  const MentorQueueScreen({super.key});

  @override
  ConsumerState<MentorQueueScreen> createState() => _MentorQueueScreenState();
}

class _MentorQueueScreenState extends ConsumerState<MentorQueueScreen> {
  bool _loading = true;
  String? _error;
  List<DoubtRequest> _requests = [];
  Map<String, String> _subjects = {};
  String? _claimingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final identity = await ref.read(identityProviderProvider.future);
      if (identity == null) throw Exception('Account not found');
      final service = ref.read(_mentorServiceProvider);
      final rows = await service.client
          .from('doubt_requests')
          .select()
          .eq('school_id', identity.schoolId)
          .inFilter('status', ['pending_assignment', 'waiting', 'assigned', 'in_progress'])
          .order('urgent', ascending: false)
          .order('created_at', ascending: true);
      final requests = (rows as List)
          .map((row) => DoubtRequest.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList();
      final subjects = await service.listSubjects(identity.schoolId);
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _subjects = {for (final subject in subjects) subject.id: subject.name};
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = 'Could not load the mentor queue. Check your account and connection.'; _loading = false; });
    }
  }

  Future<void> _claim(DoubtRequest request) async {
    setState(() => _claimingId = request.id);
    try {
      await ref.read(_mentorServiceProvider).claimDoubt(request.id);
      await _load();
    } on MentorDeskException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not claim this request.');
    } finally {
      if (mounted) setState(() => _claimingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Mentor queue'),
        actions: [IconButton(onPressed: _load, tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _requests.isEmpty
              ? _EmptyState(message: _error!, retry: _load)
              : _requests.isEmpty
                  ? const _EmptyState(message: 'No open student requests at this time.')
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _requests.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final request = _requests[index];
                          final subject = _subjects[request.subjectId] ?? 'Subject';
                          return Container(
                            padding: const EdgeInsets.all(15),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.ink200)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: Text(subject, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.accent))),
                                    if (request.urgent) const Chip(label: Text('URGENT'), visualDensity: VisualDensity.compact, side: BorderSide.none, backgroundColor: Color(0xFFFFE4E6)),
                                    const SizedBox(width: 5),
                                    Text(request.statusLabel, style: const TextStyle(fontSize: 10, color: AppColors.ink500)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(request.question, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w700, color: AppColors.ink900)),
                                if (request.chapter != null) Padding(padding: const EdgeInsets.only(top: 5), child: Text(request.chapter!, style: const TextStyle(fontSize: 11, color: AppColors.ink500))),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    if (request.status == 'waiting')
                                      OutlinedButton(
                                        onPressed: _claimingId == request.id ? null : () => _claim(request),
                                        child: _claimingId == request.id ? const SizedBox(height: 15, width: 15, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Claim request'),
                                      ),
                                    const Spacer(),
                                    TextButton.icon(
                                      onPressed: () => context.go('/mentor-desk/doubt/${request.id}'),
                                      icon: const Icon(Icons.forum_outlined, size: 17),
                                      label: const Text('Open'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message, this.retry});
  final String message;
  final VoidCallback? retry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(26),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.inbox_outlined, size: 42, color: AppColors.ink400),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.ink600)),
        if (retry != null) ...[
          const SizedBox(height: 14),
          OutlinedButton(onPressed: retry, child: const Text('Retry')),
        ],
      ]),
    ),
  );
}
