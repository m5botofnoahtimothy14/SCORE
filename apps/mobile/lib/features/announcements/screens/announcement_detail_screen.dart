import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/models.dart';
import '../../../core/widgets/states.dart';

/// Announcement detail with acknowledgement recording (announcement_receipts).
/// Read state is local; acknowledgement is server-persisted and auditable.
class AnnouncementDetailScreen extends StatefulWidget {
  final String announcementId;
  const AnnouncementDetailScreen({super.key, required this.announcementId});

  @override
  State<AnnouncementDetailScreen> createState() => _AnnouncementDetailScreenState();
}

class _AnnouncementDetailScreenState extends State<AnnouncementDetailScreen> {
  AnnouncementRecord? _item;
  bool _loading = true;
  String? _error;
  bool _acked = false;
  bool _acking = false;

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
      // RLS: visible only if the user is a real recipient.
      final row = await client
          .from('announcements')
          .select()
          .eq('id', widget.announcementId)
          .eq('is_published', true)
          .maybeSingle();
      if (row == null) {
        if (mounted) {
          setState(() {
            _error = 'Notice not found or you do not have access.';
            _loading = false;
          });
        }
        return;
      }
      final rec = await client
          .from('announcement_recipients')
          .select('id')
          .eq('announcement_id', widget.announcementId)
          .eq('user_id', me)
          .maybeSingle();
      if (rec == null) {
        if (mounted) {
          setState(() {
            _error = 'Notice not found or you do not have access.';
            _loading = false;
          });
        }
        return;
      }
      final receipt = await client
          .from('announcement_receipts')
          .select('acknowledged_at')
          .eq('announcement_id', widget.announcementId)
          .eq('user_id', me)
          .maybeSingle();
      // Record read (idempotent upsert; acknowledgement stays separate).
      await client.from('announcement_receipts').upsert(
        {'announcement_id': widget.announcementId, 'user_id': me, 'read_at': DateTime.now().toIso8601String()},
        onConflict: 'announcement_id,user_id',
      );
      if (!mounted) return;
      setState(() {
        _item = AnnouncementRecord.fromJson(Map<String, dynamic>.from(row as Map));
        _acked = receipt != null && (receipt as Map)['acknowledged_at'] != null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not open this notice. Check your connection.';
        _loading = false;
      });
    }
  }

  Future<void> _acknowledge() async {
    setState(() => _acking = true);
    try {
      final client = Supabase.instance.client;
      final me = client.auth.currentUser!.id;
      await client.from('announcement_receipts').upsert(
        {
          'announcement_id': widget.announcementId,
          'user_id': me,
          'read_at': DateTime.now().toIso8601String(),
          'acknowledged_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'announcement_id,user_id',
      );
      if (mounted) setState(() => _acked = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not record acknowledgement. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _acking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notice')),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_item!.isPriority)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.warning, size: 16, color: Color(0xFFDC2626)),
                              SizedBox(width: 6),
                              Text('PRIORITY ALERT',
                                  style: TextStyle(color: Color(0xFF991B1B), fontWeight: FontWeight.bold, fontSize: 12)),
                            ],
                          ),
                        ),
                      const SizedBox(height: 12),
                      Text(_item!.title,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(_item!.publishedAt?.toLocal().toString().split('.').first ?? '',
                          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
                      const Divider(height: 32),
                      Text(_item!.body, style: const TextStyle(fontSize: 16, height: 1.5)),
                      if (_item!.requiresAck) ...[
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: (_acked || _acking) ? null : _acknowledge,
                            child: _acking
                                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : Text(_acked ? 'Acknowledged ✓' : 'Acknowledge receipt'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text('Acknowledgement is recorded for your school office.',
                            style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                      ],
                    ],
                  ),
                ),
    );
  }
}
