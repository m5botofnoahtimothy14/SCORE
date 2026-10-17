import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/models.dart';
import '../../../core/widgets/states.dart';

/// Class + school announcements addressed to this user (via
/// announcement_recipients — RLS guarantees only own rows are visible).
class AnnouncementsScreen extends ConsumerStatefulWidget {
  const AnnouncementsScreen({super.key});
  @override
  ConsumerState<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends ConsumerState<AnnouncementsScreen> {
  List<AnnouncementRecord> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final me = client.auth.currentUser!.id;
      final rows = await client
          .from('announcement_recipients')
          .select('announcement_id, announcements!inner(id, title, body, category, audience_type, requires_ack, published_at)')
          .eq('user_id', me)
          .order('announcement_id', ascending: false)
          .limit(50) as List;
      final items = rows
          .map((r) => AnnouncementRecord.fromJson(Map<String, dynamic>.from((r as Map)['announcements'] as Map)))
          .toList();
      // Acknowledgement flags
      if (items.isNotEmpty) {
        final receipts = await client
            .from('announcement_receipts')
            .select('announcement_id, acknowledged_at')
            .eq('user_id', me)
            .inFilter('announcement_id', items.map((a) => a.id).toList()) as List;
        final Map<String, bool> acked = {};
        for (final raw in receipts) {
          final m = raw as Map;
          acked[m['announcement_id'] as String] = m['acknowledged_at'] != null;
        }
        if (!mounted) return;
        setState(() {
          _items = items;
          _loading = false;
          _acked = acked;
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load notices. Check your connection.';
        _loading = false;
      });
    }
  }

  Map<String, bool> _acked = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notices')),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _items.isEmpty
                  ? const EmptyView(
                      title: 'No notices yet',
                      subtitle: 'School and class announcements will appear here.',
                      icon: Icons.campaign_outlined,
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _items.length,
                        itemBuilder: (context, i) {
                          final a = _items[i];
                          final needsAck = a.requiresAck && !(_acked[a.id] ?? false);
                          return Card(
                            child: ListTile(
                              leading: Icon(
                                a.isPriority ? Icons.warning : Icons.campaign,
                                color: a.isPriority ? const Color(0xFFDC2626) : const Color(0xFF1A56DB),
                              ),
                              title: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(a.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 4),
                                  Row(children: [
                                    _badge(a.category.replaceAll('_', ' ')),
                                    if (needsAck) ...[const SizedBox(width: 6), _badge('action needed', red: true)],
                                  ]),
                                ],
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.go('/announcements/${a.id}'),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }

  Widget _badge(String text, {bool red = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: red ? const Color(0xFFFEE2E2) : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 11, color: red ? const Color(0xFF991B1B) : const Color(0xFF1A56DB))),
    );
  }
}
