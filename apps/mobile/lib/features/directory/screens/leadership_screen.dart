import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/states.dart';

/// Approved school leadership contacts (principal / heads), subject to
/// backend policy. Students see only designated leadership contacts.
class LeadershipScreen extends StatefulWidget {
  const LeadershipScreen({super.key});
  @override
  State<LeadershipScreen> createState() => _LeadershipScreenState();
}

class _LeadershipScreenState extends State<LeadershipScreen> {
  List<Map<String, dynamic>> _leaders = [];
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
      final rows = await Supabase.instance.client
          .from('teachers')
          .select('user_id, first_name, last_name')
          .eq('is_active', true)
          .eq('is_leadership', true)
          .order('first_name') as List;
      if (!mounted) return;
      setState(() {
        _leaders = rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load leadership contacts. Check your connection.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('School Leadership')),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _leaders.isEmpty
                  ? const EmptyView(
                      title: 'No contacts listed',
                      subtitle: 'Your school has not published leadership contacts.',
                      icon: Icons.account_balance_outlined,
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _leaders.length,
                        itemBuilder: (context, i) {
                          final l = _leaders[i];
                          return Card(
                            child: ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: Color(0xFFDEF7EC),
                                child: Icon(Icons.shield_outlined, color: Color(0xFF0E9F6E)),
                              ),
                              title: Text('${l['first_name']} ${l['last_name']}',
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: const Text('School leadership'),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
