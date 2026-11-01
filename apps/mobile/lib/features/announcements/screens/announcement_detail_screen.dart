import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/identity_provider.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final row = await Supabase.instance.client
          .from('announcements')
          .select('id, title, body, category, audience_type, published_at, created_at, requires_ack')
          .eq('id', widget.announcementId)
          .maybeSingle();
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
                          const Text('This notice requires acknowledgement. Ask your school administrator how to confirm receipt if the acknowledgement control is not available.', style: TextStyle(fontSize: 12, color: AppColors.ink500)),
                        ],
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
