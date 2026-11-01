import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';

class AnnouncementDetailScreen extends ConsumerStatefulWidget {
  final String announcementId;
  const AnnouncementDetailScreen({super.key, required this.announcementId});

  @override
  ConsumerState<AnnouncementDetailScreen> createState() => _AnnouncementDetailScreenState();
}

class _AnnouncementDetailScreenState extends ConsumerState<AnnouncementDetailScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _announcement;
  bool _acknowledged = false;
  bool _acknowledging = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final client = Supabase.instance.client;
      final row = await client
          .from('announcements')
          .select('id, title, body, category, audience_type, published_at, created_at, requires_ack')
          .eq('id', widget.announcementId)
          .maybeSingle();
      if (row != null) {
        final userId = client.auth.currentUser?.id;
        if (userId != null) {
          final receipt = await client
              .from('announcement_receipts')
              .select('id, acknowledged_at')
              .eq('announcement_id', widget.announcementId)
              .eq('user_id', userId)
              .maybeSingle();
          if (receipt == null) {
            await client.from('announcement_receipts').insert({
              'announcement_id': widget.announcementId,
              'user_id': userId,
              'read_at': DateTime.now().toUtc().toIso8601String(),
            });
          } else {
            await client.from('announcement_receipts').update({
              'read_at': DateTime.now().toUtc().toIso8601String(),
            }).eq('id', receipt['id']);
          }
          if (!mounted) return;
          setState(() => _acknowledged = receipt?['acknowledged_at'] != null);
        }
      }
      if (!mounted) return;
      setState(() {
        _announcement = row == null ? null : Map<String, dynamic>.from(row);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = 'Could not load this announcement.'; _loading = false; });
    }
  }

  Future<void> _acknowledge() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    setState(() { _acknowledging = true; _error = null; });
    try {
      final client = Supabase.instance.client;
      final now = DateTime.now().toUtc().toIso8601String();
      final receipt = await client
          .from('announcement_receipts')
          .select('id')
          .eq('announcement_id', widget.announcementId)
          .eq('user_id', userId)
          .maybeSingle();
      if (receipt == null) {
        await client.from('announcement_receipts').insert({
          'announcement_id': widget.announcementId,
          'user_id': userId,
          'read_at': now,
          'acknowledged_at': now,
        });
      } else {
        await client.from('announcement_receipts').update({
          'read_at': now,
          'acknowledged_at': now,
        }).eq('id', receipt['id']);
      }
      if (mounted) setState(() => _acknowledged = true);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save your acknowledgement.');
    } finally {
      if (mounted) setState(() => _acknowledging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _announcement;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Announcement')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : item == null
                  ? const Center(child: Text('This announcement is not available to your account.'))
                  : ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Text(
                          (item['category']?.toString() ?? 'general').replaceAll('_', ' ').toUpperCase(),
                          style: const TextStyle(fontSize: 10, letterSpacing: 1.1, fontWeight: FontWeight.w800, color: AppColors.accent),
                        ),
                        const SizedBox(height: 12),
                        Text(item['title']?.toString() ?? 'Announcement', style: Theme.of(context).textTheme.headlineMedium),
                        const SizedBox(height: 10),
                        Text(_date(item['published_at']?.toString() ?? item['created_at']?.toString()), style: const TextStyle(fontSize: 12, color: AppColors.ink500)),
                        const SizedBox(height: 22),
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.ink200)),
                          child: SelectableText(item['body']?.toString() ?? '', style: const TextStyle(fontSize: 15, height: 1.65, color: AppColors.ink700)),
                        ),
                        if (item['requires_ack'] == true) ...[
                          const SizedBox(height: 18),
                          if (_acknowledged)
                            const Row(children: [Icon(Icons.verified_rounded, color: AppColors.success, size: 18), SizedBox(width: 8), Text('Acknowledgement recorded', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w700))])
                          else
                            FilledButton.icon(onPressed: _acknowledging ? null : _acknowledge, icon: const Icon(Icons.check_circle_outline), label: Text(_acknowledging ? 'Saving…' : 'Acknowledge notice')),
                        ],
                        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12))),
                      ],
                    ),
    );
  }

  String _date(String? raw) {
    final date = DateTime.tryParse(raw ?? '');
    if (date == null) return 'Published by your school';
    return 'Published ${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
