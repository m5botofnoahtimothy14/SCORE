import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart';

class AnnouncementsScreen extends ConsumerStatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  ConsumerState<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends ConsumerState<AnnouncementsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final identity = await ref.read(identityProviderProvider.future);
      if (identity == null) throw Exception('Your school account is not available.');
      final rows = await Supabase.instance.client
          .from('announcements')
          .select('id, title, body, category, audience_type, published_at, created_at, requires_ack')
          .eq('school_id', identity.schoolId)
          .eq('is_published', true)
          .order('published_at', ascending: false)
          .limit(100);
      if (!mounted) return;
      setState(() {
        _items = (rows as List).map((row) => Map<String, dynamic>.from(row as Map)).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load school notices. Check your connection and try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(identityProviderProvider).valueOrNull;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('School announcements'),
        actions: [
          if (identity?.isLeadership == true)
            IconButton(
              tooltip: 'Compose announcement',
              onPressed: () => context.go('/announcements/compose'),
              icon: const Icon(Icons.add_rounded),
            ),
          IconButton(onPressed: _load, tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _MessageState(message: _error!, onRetry: _load)
              : _items.isEmpty
                  ? const _MessageState(message: 'There are no published announcements yet.')
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final date = DateTime.tryParse(item['published_at']?.toString() ?? item['created_at']?.toString() ?? '');
                          final category = item['category']?.toString() ?? 'general';
                          return Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => context.go('/announcements/${item['id']}'),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppColors.ink200),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        _CategoryChip(category: category),
                                        const Spacer(),
                                        if (item['requires_ack'] == true)
                                          const Icon(Icons.fact_check_outlined, size: 16, color: AppColors.ink500),
                                        if (date != null) ...[
                                          const SizedBox(width: 6),
                                          Text(_date(date), style: const TextStyle(fontSize: 11, color: AppColors.ink500)),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Text(item['title']?.toString() ?? 'Announcement', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink900)),
                                    const SizedBox(height: 6),
                                    Text(
                                      item['body']?.toString() ?? '',
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13, height: 1.45, color: AppColors.ink600),
                                    ),
                                    const SizedBox(height: 10),
                                    const Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Text('Read notice', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accent)),
                                        SizedBox(width: 5),
                                        Icon(Icons.arrow_forward_rounded, size: 15, color: AppColors.accent),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }

  static String _date(DateTime date) => '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category});
  final String category;

  @override
  Widget build(BuildContext context) {
    final label = category.replaceAll('_', ' ').toUpperCase();
    final color = category == 'priority_alert' || category == 'safety'
        ? AppColors.danger
        : category == 'academic'
            ? AppColors.accent
            : AppColors.teacherTier;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 9, letterSpacing: 0.5, fontWeight: FontWeight.w800, color: color)),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.campaign_outlined, size: 42, color: AppColors.ink400),
          const SizedBox(height: 14),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.ink600)),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ],
      ),
    ),
  );
}
