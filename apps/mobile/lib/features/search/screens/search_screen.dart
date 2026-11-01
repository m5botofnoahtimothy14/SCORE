import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  static const _items = <_SearchItem>[
    _SearchItem('Home', 'Your SCORE+ dashboard', Icons.home_outlined, '/home', ['dashboard', 'start']),
    _SearchItem('AI Ask', 'Curriculum-based learning support', Icons.auto_awesome_outlined, '/ai-ask', ['ai', 'questions', 'study', 'learning']),
    _SearchItem('Mentor Desk', 'Student doubts and teacher support', Icons.support_agent_outlined, '/mentor-desk', ['doubt', 'help', 'mentor', 'teacher']),
    _SearchItem('Announcements', 'School notices and updates', Icons.campaign_outlined, '/announcements', ['notices', 'news', 'updates']),
    _SearchItem('Profile', 'Your account and preferences', Icons.person_outline, '/profile', ['account', 'settings', 'preferences']),
    _SearchItem('Notification settings', 'Manage notification preferences', Icons.notifications_outlined, '/notification-settings', ['alerts', 'push', 'notifications']),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final results = _items.where((item) {
      if (q.isEmpty) return true;
      return item.title.toLowerCase().contains(q) ||
          item.description.toLowerCase().contains(q) ||
          item.keywords.any((word) => word.contains(q));
    }).toList(growable: false);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Explore SCORE+')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            Text('Find a tool', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text('Search the features available in your app.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.ink500)),
            const SizedBox(height: 18),
            TextField(
              controller: _controller,
              onChanged: (value) => setState(() => _query = value),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search AI Ask, Mentor Desk, notices…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty ? null : IconButton(
                  tooltip: 'Clear search',
                  onPressed: () {
                    _controller.clear();
                    setState(() => _query = '');
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.ink200)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.ink200)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.accent, width: 1.5)),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(q.isEmpty ? 'AVAILABLE TOOLS' : 'SEARCH RESULTS', style: Theme.of(context).textTheme.labelLarge?.copyWith(letterSpacing: 1.0, color: AppColors.ink500)),
                Text('${results.length} found', style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
            const SizedBox(height: 8),
            if (results.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 42),
                child: Column(
                  children: [
                    const Icon(Icons.search_off_rounded, size: 42, color: AppColors.ink300),
                    const SizedBox(height: 12),
                    Text('No matching tools', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    const Text('Try a different keyword.', style: TextStyle(color: AppColors.ink500, fontSize: 12)),
                  ],
                ),
              )
            else
              ...results.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => context.go(item.route),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.ink200),
                      ),
                      child: Row(
                        children: [
                          Container(
                            height: 42,
                            width: 42,
                            decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                            child: Icon(item.icon, color: AppColors.accent),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink900)),
                                const SizedBox(height: 3),
                                Text(item.description, style: const TextStyle(fontSize: 12, color: AppColors.ink500)),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.ink400),
                        ],
                      ),
                    ),
                  ),
                ),
              )),
          ],
        ),
      ),
    );
  }
}

class _SearchItem {
  const _SearchItem(this.title, this.description, this.icon, this.route, this.keywords);
  final String title;
  final String description;
  final IconData icon;
  final String route;
  final List<String> keywords;
}
