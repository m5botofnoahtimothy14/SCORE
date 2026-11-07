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

class DoubtsListScreen extends ConsumerStatefulWidget {
  const DoubtsListScreen({super.key});

  @override
  ConsumerState<DoubtsListScreen> createState() => _DoubtsListScreenState();
}

class _DoubtsListScreenState extends ConsumerState<DoubtsListScreen> {
  bool _loading = true;
  String? _error;
  List<DoubtRequest> _doubts = [];
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
          .from('doubt_requests')
          .select()
          .eq('student_id', _myUserId!)
          .order('updated_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _doubts = (rows as List)
            .map((r) => DoubtRequest.fromJson(Map<String, dynamic>.from(r as Map)))
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
        title: const Text('Your Doubts', style: TextStyle(color: MDColors.ink900, fontWeight: FontWeight.w800)),
        centerTitle: false,
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _doubts.isEmpty
                  ? const EmptyView(
                      title: 'No doubts yet',
                      subtitle: 'Ask a doubt to get started.',
                      icon: Icons.question_answer_outlined,
                      actionLabel: 'Ask a Doubt',
                    )
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(
                        horizontalGutter(context),
                        8,
                        horizontalGutter(context),
                        MediaQuery.of(context).padding.bottom + 16,
                      ),
                      itemCount: _doubts.length,
                      itemBuilder: (context, index) {
                        final d = _doubts[index];
                        return _DoubtCard(d: d);
                      },
                    ),
    );
  }
}

class _DoubtCard extends StatelessWidget {
  final DoubtRequest d;
  const _DoubtCard({required this.d});

  @override
  Widget build(BuildContext context) {
    final waitMinutes = DateTime.now().difference(d.createdAt).inMinutes;
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
        title: Text(d.question, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: MDColors.ink900)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(d.status).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _statusColor(d.status).withValues(alpha: 0.4)),
                  ),
                  child: Text(d.statusLabel,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: _statusColor(d.status), letterSpacing: 0.5)),
                ),
                const SizedBox(width: 10),
                Text('${d.subjectName ?? 'Subject'} · ${d.studentName ?? 'Student'}',
                    style: const TextStyle(fontSize: 12, color: MDColors.ink500)),
              ],
            ),
            const SizedBox(height: 6),
            Text('${waitMinutes}m ago · ${d.urgent ? 'Urgent' : 'Standard'}',
                style: const TextStyle(fontSize: 11, color: MDColors.ink400)),
          ],
        ),
        trailing: const Icon(Icons.chevron_right, color: MDColors.ink400),
        onTap: () {
          context.go('/mentor-desk/doubt/${d.id}');
        },
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending_assignment':
      case 'waiting': return MDColors.warning;
      case 'assigned':
      case 'in_progress': return MDColors.info;
      case 'resolved':
      case 'closed': return MDColors.success;
      default: return MDColors.ink500;
    }
  }
}


