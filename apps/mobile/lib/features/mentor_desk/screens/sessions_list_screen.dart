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

class SessionsListScreen extends ConsumerStatefulWidget {
  const SessionsListScreen({super.key});

  @override
  ConsumerState<SessionsListScreen> createState() => _SessionsListScreenState();
}

class _SessionsListScreenState extends ConsumerState<SessionsListScreen> {
  bool _loading = true;
  String? _error;
  List<SessionBooking> _bookings = [];
  String? _myUserId;

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
      _myUserId = identity.userId;
      final rows = await Supabase.instance.client
          .from('session_bookings')
          .select()
          .eq('student_id', _myUserId!)
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _bookings = (rows as List)
            .map((r) => SessionBooking.fromJson(Map<String, dynamic>.from(r as Map)))
            .toList();
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
        title: const Text('Your Sessions', style: TextStyle(color: MDColors.ink900, fontWeight: FontWeight.w800)),
        centerTitle: false,
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _bookings.isEmpty
                  ? const EmptyView(
                      title: 'No sessions yet',
                      subtitle: 'Book a session with a mentor.',
                      icon: Icons.schedule_outlined,
                      actionLabel: 'Book a Session',
                    )
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(
                        horizontalGutter(context),
                        8,
                        horizontalGutter(context),
                        MediaQuery.of(context).padding.bottom + 16,
                      ),
                      itemCount: _bookings.length,
                      itemBuilder: (context, index) {
                        final b = _bookings[index];
                        return _SessionCard(b: b);
                      },
                    ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final SessionBooking b;
  const _SessionCard({required this.b});

  @override
  Widget build(BuildContext context) {
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
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(b.topic, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: MDColors.ink900)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(b.status).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _statusColor(b.status).withValues(alpha: 0.4)),
                  ),
                  child: Text(b.statusLabel,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: _statusColor(b.status), letterSpacing: 0.5)),
                ),
                const SizedBox(width: 10),
                Text('${b.durationMinutes} min · ${b.subjectName ?? 'Subject'}',
                    style: const TextStyle(fontSize: 12, color: MDColors.ink500)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              b.scheduledAt != null
                  ? DateFormat('EEE, MMM d · h:mm a').format(b.scheduledAt!)
                  : 'Not yet scheduled',
              style: const TextStyle(fontSize: 11, color: MDColors.ink400),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right, color: MDColors.ink400),
        onTap: () => context.go('/mentor-desk/session/${b.id}'),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'requested': return MDColors.warning;
      case 'confirmed': return MDColors.info;
      case 'completed': return MDColors.success;
      case 'cancelled_by_student':
      case 'cancelled_by_mentor': return MDColors.ink500;
      case 'no_show_student':
      case 'no_show_mentor':
      case 'unverified_closed': return MDColors.danger;
      default: return MDColors.ink500;
    }
  }
}


