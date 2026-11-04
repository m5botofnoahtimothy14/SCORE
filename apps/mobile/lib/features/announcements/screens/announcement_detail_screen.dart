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
      final rows = await Supabase.instance.client
          .from('announcements')
          .select()
          .eq('id', widget.announcementId)
          .maybeSingle();
      if (!mounted) return;
      if (rows == null) throw Exception('Announcement not found');
      setState(() { _announcement = Map<String, dynamic>.from(rows); _loading = false; });
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
        title: const Text('Notice Detail', style: TextStyle(color: MDColors.ink900, fontWeight: FontWeight.w800)),
        centerTitle: false,
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _announcement == null
                  ? const Center(child: Text('No data', style: TextStyle(color: MDColors.ink500)))
                  : SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        horizontalGutter(context),
                        16,
                        horizontalGutter(context),
                        MediaQuery.of(context).padding.bottom + 24,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: MDColors.surfaceCard,
                              borderRadius: BorderRadius.circular(kRadiusLg),
                              border: Border.all(color: MDColors.ink200),
                              boxShadow: [
                                BoxShadow(color: MDColors.brand.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2)),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 44, height: 44,
                                      decoration: BoxDecoration(
                                        color: MDColors.info.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(Icons.campaign, color: MDColors.info, size: 22),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Text(
                                        _announcement!['title']?.toString() ?? 'Untitled',
                                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: MDColors.ink900),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _announcement!['created_at'] != null
                                      ? DateFormat('EEE, MMM d, yyyy · h:mm a').format(DateTime.parse(_announcement!['created_at'].toString()))
                                      : '',
                                  style: const TextStyle(fontSize: 12, color: MDColors.ink400),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _announcement!['body']?.toString() ?? '',
                                  style: const TextStyle(fontSize: 15, color: MDColors.ink700, height: 1.6),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
    );
  }
}


