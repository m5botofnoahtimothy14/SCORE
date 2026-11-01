import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../models/mentor_desk_models.dart';
import '../services/mentor_desk_service.dart';

final _mentorServiceProvider = Provider((ref) => MentorDeskService(Supabase.instance.client));

class StudentDoubtsScreen extends ConsumerStatefulWidget {
  const StudentDoubtsScreen({super.key});

  @override
  ConsumerState<StudentDoubtsScreen> createState() => _StudentDoubtsScreenState();
}

class _StudentDoubtsScreenState extends ConsumerState<StudentDoubtsScreen> {
  bool _loading = true;
  String? _error;
  List<DoubtRequest> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final identity = await ref.read(identityProviderProvider.future);
      if (identity == null || identity.tier != AppTier.student) throw Exception('Student account required');
      final items = await ref.read(_mentorServiceProvider).listDoubtRequests(
        schoolId: identity.schoolId,
        studentId: identity.userId,
      );
      if (!mounted) return;
      setState(() { _items = items; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = 'Could not load your doubt requests.'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('My doubts'),
        actions: [
          IconButton(onPressed: _load, tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded)),
          IconButton(onPressed: () => context.go('/mentor-desk/doubt/submit'), tooltip: 'Ask a doubt', icon: const Icon(Icons.add_rounded)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 12), OutlinedButton(onPressed: _load, child: const Text('Retry'))])))
              : _items.isEmpty
                  ? const Center(child: Text('You have not submitted a doubt yet.'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 9),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final closed = item.isClosed;
                          return Container(
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: AppColors.ink200)),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              leading: Icon(item.urgent ? Icons.priority_high_rounded : Icons.question_answer_outlined, color: item.urgent ? AppColors.danger : AppColors.accent),
                              title: Text(item.question, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink900)),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: Text('${item.statusLabel} · ${_date(item.createdAt)}', style: const TextStyle(fontSize: 11, color: AppColors.ink500)),
                              ),
                              trailing: closed
                                  ? IconButton(tooltip: 'Rate support', onPressed: () => context.go('/mentor-desk/rating/${item.id}'), icon: const Icon(Icons.star_outline_rounded, color: AppColors.warning))
                                  : const Icon(Icons.chevron_right_rounded),
                              onTap: () => context.go('/mentor-desk/doubt/${item.id}'),
                            ),
                          );
                        },
                      ),
                    ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/mentor-desk/doubt/submit'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Ask a doubt'),
      ),
    );
  }

  String _date(DateTime value) => '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
}

class StudentSessionsScreen extends ConsumerStatefulWidget {
  const StudentSessionsScreen({super.key});

  @override
  ConsumerState<StudentSessionsScreen> createState() => _StudentSessionsScreenState();
}

class _StudentSessionsScreenState extends ConsumerState<StudentSessionsScreen> {
  bool _loading = true;
  String? _error;
  List<SessionBooking> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final identity = await ref.read(identityProviderProvider.future);
      if (identity == null || identity.tier != AppTier.student) throw Exception('Student account required');
      final items = await ref.read(_mentorServiceProvider).listSessionBookings(studentId: identity.userId);
      if (!mounted) return;
      setState(() { _items = items; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = 'Could not load your sessions.'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('My sessions'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 12), OutlinedButton(onPressed: _load, child: const Text('Retry'))])))
              : _items.isEmpty
                  ? const Center(child: Text('You have no session bookings yet.'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 9),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final scheduled = item.scheduledAt?.toLocal();
                          return Container(
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: AppColors.ink200)),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              leading: const Icon(Icons.calendar_month_outlined, color: AppColors.accent),
                              title: Text(item.topic, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink900)),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: Text('${item.statusLabel} · ${item.durationMinutes} min · ${scheduled == null ? 'Time pending' : _date(scheduled)}', style: const TextStyle(fontSize: 11, color: AppColors.ink500)),
                              ),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () => context.go('/mentor-desk/session/${item.id}'),
                            ),
                          );
                        },
                      ),
                    ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/mentor-desk/session/book'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Book a session'),
      ),
    );
  }

  String _date(DateTime value) => '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
}
