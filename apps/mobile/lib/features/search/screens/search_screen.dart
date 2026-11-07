import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mentor_desk_design.dart';
import '../../../core/layout/responsive.dart';
import '../../../core/widgets/states.dart';
import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _results = [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final q = _searchController.text.trim();
      if (q != _query) {
        _query = q;
        _search();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_query.isEmpty) {
      setState(() { _results = []; });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final identity = await ref.read(identityProviderProvider.future);
      if (identity == null) throw Exception('No identity found');
      final schoolId = identity.schoolId;
      final supabase = Supabase.instance.client;

      // Search announcements
      final announcements = await supabase
          .from('announcements')
          .select('id, title, body, created_at')
          .eq('school_id', schoolId)
          .ilike('title', '%$_query%')
          .limit(10);

      // Search doubt requests
      final doubts = await supabase
          .from('doubt_requests')
          .select('id, question, subject_id, status, created_at')
          .eq('school_id', schoolId)
          .ilike('question', '%$_query%')
          .limit(10);

      final results = <Map<String, dynamic>>[];
      for (final a in (announcements as List)) {
        results.add(Map<String, dynamic>.from(a as Map)..['type'] = 'announcement');
      }
      for (final d in (doubts as List)) {
        results.add(Map<String, dynamic>.from(d as Map)..['type'] = 'doubt');
      }

      if (!mounted) return;
      setState(() { _results = results; _loading = false; });
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
        title: const Text('Search', style: TextStyle(color: MDColors.ink900, fontWeight: FontWeight.w800)),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalGutter(context),
                8,
                horizontalGutter(context),
                8,
              ),
              child: MDGlossInput(
                controller: _searchController,
                hint: 'Search notices, doubts, topics…',
                errorText: null,
              ),
            ),
            Expanded(
              child: _loading
                  ? const LoadingView()
                  : _error != null
                      ? ErrorView(message: _error!, onRetry: _search)
                      : _results.isEmpty
                          ? EmptyView(
                              title: _query.isEmpty ? 'Search anything' : 'No results',
                              subtitle: _query.isEmpty ? 'Type to search notices and doubts.' : 'Try different keywords.',
                              icon: Icons.search,
                            )
                          : ListView.builder(
                              padding: EdgeInsets.fromLTRB(
                                horizontalGutter(context),
                                8,
                                horizontalGutter(context),
                                MediaQuery.of(context).padding.bottom + 16,
                              ),
                              itemCount: _results.length,
                              itemBuilder: (context, index) {
                                final r = _results[index];
                                final isAnnouncement = r['type'] == 'announcement';
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  decoration: BoxDecoration(
                                    color: MDColors.surfaceCard,
                                    borderRadius: BorderRadius.circular(kRadiusSm),
                                    border: Border.all(color: MDColors.ink200),
                                  ),
                                  child: ListTile(
                                    leading: Container(
                                      width: 40, height: 40,
                                      decoration: BoxDecoration(
                                        color: (isAnnouncement ? MDColors.info : MDColors.brand).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        isAnnouncement ? Icons.campaign : Icons.question_answer,
                                        color: isAnnouncement ? MDColors.info : MDColors.brand,
                                        size: 20,
                                      ),
                                    ),
                                    title: Text(
                                      r['title']?.toString() ?? r['question']?.toString() ?? 'Untitled',
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: MDColors.ink900),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      isAnnouncement ? 'Notice' : 'Doubt · ${r['status']}',
                                      style: const TextStyle(fontSize: 11, color: MDColors.ink500),
                                    ),
                                    trailing: const Icon(Icons.chevron_right, color: MDColors.ink400),
                                    onTap: () {
                                      if (isAnnouncement) {
                                        context.go('/announcements/${r['id']}');
                                      } else {
                                        context.go('/mentor-desk/doubt/${r['id']}');
                                      }
                                    },
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}


