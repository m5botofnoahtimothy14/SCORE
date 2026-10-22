import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SchoolSelectScreen extends ConsumerStatefulWidget {
  const SchoolSelectScreen({super.key});

  @override
  ConsumerState<SchoolSelectScreen> createState() => _SchoolSelectScreenState();
}

class _SchoolSelectScreenState extends ConsumerState<SchoolSelectScreen> {
  List<Map<String, dynamic>> _schools = [];
  bool _loading = true;
  String? _error;
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _filtered = [];

  @override
  void initState() {
    super.initState();
    _loadSchools();
  }

  Future<void> _loadSchools() async {
    try {
      // Public directory view (unauthenticated): id, name, code, city, state, logo.
      // Contact details stay behind RLS on the base table.
      final data = await Supabase.instance.client
          .from('public_schools')
          .select('id, name, code, city, state, logo_url')
          .order('name');

      if (!mounted) return;
      setState(() {
        _schools = List<Map<String, dynamic>>.from(data);
        _filtered = _schools;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load schools. Please check your connection.';
        _loading = false;
      });
    }
  }

  void _filter(String query) {
    setState(() {
      final q = query.trim().toLowerCase();
      if (q.isEmpty) {
        _filtered = _schools;
        return;
      }
      _filtered = _schools
          .where((s) =>
              (s['name']?.toString().toLowerCase() ?? '').contains(q) ||
              (s['code']?.toString().toLowerCase() ?? '').contains(q))
          .toList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.asset('assets/images/logo.png', height: 40, errorBuilder: (_, __, ___) =>
                    const Icon(Icons.school, size: 40, color: Color(0xFF1A56DB))),
                  const SizedBox(height: 24),
                    Text(
                    'Welcome to SCORE+',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Select your school to continue',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _searchController,
                    onChanged: _filter,
                    decoration: const InputDecoration(
                      hintText: 'Search your school...',
                      prefixIcon: Icon(Icons.search, color: Color(0xFF9CA3AF)),
                    ),
                  ),
                ],
              ),
            ),

            // School list
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _ErrorState(
                          message: _error!,
                          onRetry: () { setState(() { _loading = true; _error = null; }); _loadSchools(); },
                        )
                      : _filtered.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.search_off, size: 64, color: Color(0xFFD1D5DB)),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No schools found',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: const Color(0xFF6B7280),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              itemCount: _filtered.length,
                              itemBuilder: (context, index) {
                                final school = _filtered[index];
                                return _SchoolCard(
                                  school: school,
                                  onTap: () => _showEnrollmentChoice(context, school),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEnrollmentChoice(BuildContext context, Map<String, dynamic> school) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              school['name'],
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '${school['city'] ?? ''}, ${school['state'] ?? ''}',
              style: const TextStyle(color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 24),
            Text('I am a...', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            _RoleButton(
              icon: Icons.person,
              label: 'Student',
              color: const Color(0xFF1A56DB),
              onTap: () {
                Navigator.pop(context);
                context.go('/auth/student-enroll?school_id=${school['id']}');
              },
            ),
            const SizedBox(height: 12),
            _RoleButton(
              icon: Icons.school,
              label: 'Teacher / Staff',
              color: const Color(0xFF0E9F6E),
              onTap: () {
                Navigator.pop(context);
                context.go('/auth/teacher-enroll?school_id=${school['id']}');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _SchoolCard extends StatelessWidget {
  final Map<String, dynamic> school;
  final VoidCallback onTap;
  const _SchoolCard({required this.school, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFEBF5FF),
          child: school['logo_url'] != null
              ? ClipOval(child: Image.network(school['logo_url'], width: 40, height: 40, fit: BoxFit.cover))
              : Text(
                  (school['code']?.toString().isNotEmpty ?? false)
                      ? school['code'].toString().substring(0, 1)
                      : 'S',
                  style: const TextStyle(
                    color: Color(0xFF1A56DB),
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
        title: Text(
          school['name'],
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: school['city'] != null
            ? Text('${school['city']}, ${school['state'] ?? ''}',
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13))
            : null,
        trailing: const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
        onTap: onTap,
      ),
    );
  }
}

class _RoleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _RoleButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: Icon(icon, color: color),
        label: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          side: BorderSide(color: color),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: onTap,
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, size: 64, color: Color(0xFFD1D5DB)),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF6B7280))),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: onRetry, child: const Text('Try Again')),
          ],
        ),
      ),
    );
  }
}
