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

class AnnouncementsScreen extends ConsumerStatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  ConsumerState<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends ConsumerState<AnnouncementsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _announcements = [];
  String? _schoolId;

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
      _schoolId = identity.schoolId;
      final rows = await Supabase.instance.client
          .from('announcements')
          .select()
          .eq('school_id', _schoolId!)
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _announcements = (rows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
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
          onPressed: () => context.pop(),
        ),
        title: const Text('Notices', style: TextStyle(color: MDColors.ink900, fontWeight: FontWeight.w800)),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: MDColors.brand),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _announcements.isEmpty
                  ? const EmptyView(
                      title: 'No notices yet',
                      subtitle: 'Check back later for school announcements.',
                      icon: Icons.campaign_outlined,
                    )
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(
                        horizontalGutter(context),
                        8,
                        horizontalGutter(context),
                        MediaQuery.of(context).padding.bottom + 16,
                      ),
                      itemCount: _announcements.length,
                      itemBuilder: (context, index) {
                        final a = _announcements[index];
                        return _AnnouncementCard(a: a);
                      },
                    ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  final Map<String, dynamic> a;
  const _AnnouncementCard({required this.a});

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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: MDColors.info.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.campaign, color: MDColors.info, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a['title']?.toString() ?? 'Untitled',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: MDColors.ink900),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        a['created_at'] != null
                            ? DateFormat('EEE, MMM d · h:mm a').format(DateTime.parse(a['created_at'].toString()))
                            : '',
                        style: const TextStyle(fontSize: 11, color: MDColors.ink400),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (a['body'] != null) ...[
              const SizedBox(height: 12),
              Text(
                a['body'].toString(),
                style: const TextStyle(fontSize: 14, color: MDColors.ink700, height: 1.5),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}


