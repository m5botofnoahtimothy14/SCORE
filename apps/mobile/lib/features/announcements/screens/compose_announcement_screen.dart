import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart';

class ComposeAnnouncementScreen extends ConsumerStatefulWidget {
  const ComposeAnnouncementScreen({super.key});

  @override
  ConsumerState<ComposeAnnouncementScreen> createState() => _ComposeAnnouncementScreenState();
}

class _ComposeAnnouncementScreenState extends ConsumerState<ComposeAnnouncementScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String _category = 'general';
  String _audience = 'school_wide';
  String? _classId;
  bool _requiresAck = false;
  bool _loading = false;
  bool _loadingClasses = false;
  String? _error;
  List<Map<String, dynamic>> _classes = [];

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _loadClasses(String schoolId) async {
    setState(() => _loadingClasses = true);
    try {
      final rows = await Supabase.instance.client
          .from('classes')
          .select('id, name')
          .eq('school_id', schoolId)
          .eq('is_active', true)
          .order('name');
      if (!mounted) return;
      setState(() => _classes = (rows as List).map((row) => Map<String, dynamic>.from(row as Map)).toList());
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load school classes.');
    } finally {
      if (mounted) setState(() => _loadingClasses = false);
    }
  }

  Future<void> _publish(String schoolId) async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty || body.isEmpty) {
      setState(() => _error = 'Enter an announcement title and message.');
      return;
    }
    if (_audience == 'class' && _classId == null) {
      setState(() => _error = 'Select a class for this announcement.');
      return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'publish-announcement',
        body: {
          'school_id': schoolId,
          'title': title,
          'body': body,
          'category': _category,
          'audience_type': _audience,
          'class_id': _audience == 'class' ? _classId : null,
          'requires_ack': _requiresAck,
        },
      );
      final data = response.data;
      if (data is! Map || data['success'] != true) {
        throw Exception(data is Map ? data['error']?.toString() ?? 'publish_failed' : 'publish_failed');
      }
      if (!mounted) return;
      final dispatch = data['dispatch_status']?.toString() ?? 'queued';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(dispatch == 'queued' ? 'Announcement published. Notifications are queued.' : 'Announcement published, but notifications were not queued.')),
      );
      context.go('/announcements');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not publish this announcement. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final identityAsync = ref.watch(identityProviderProvider);
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('New announcement')),
      body: identityAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Could not verify your account.')),
        data: (identity) {
          if (identity == null || identity.tier != AppTier.leadership) {
            return const Center(child: Text('Only school leadership can publish announcements.'));
          }
          if (_classes.isEmpty && !_loadingClasses) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _classes.isEmpty && !_loadingClasses) _loadClasses(identity.schoolId);
            });
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _fieldLabel('Title'),
              TextField(controller: _title, maxLength: 160, decoration: const InputDecoration(hintText: 'Enter a clear announcement title')),
              const SizedBox(height: 16),
              _fieldLabel('Message'),
              TextField(controller: _body, minLines: 6, maxLines: 12, maxLength: 12000, decoration: const InputDecoration(hintText: 'Write the notice for your school community')),
              const SizedBox(height: 16),
              _fieldLabel('Category'),
              DropdownButtonFormField<String>(
                value: _category,
                items: const [
                  DropdownMenuItem(value: 'general', child: Text('General')),
                  DropdownMenuItem(value: 'academic', child: Text('Academic')),
                  DropdownMenuItem(value: 'event', child: Text('Event')),
                  DropdownMenuItem(value: 'safety', child: Text('Safety')),
                  DropdownMenuItem(value: 'priority_alert', child: Text('Priority alert')),
                ],
                onChanged: _loading ? null : (value) => setState(() => _category = value ?? 'general'),
              ),
              const SizedBox(height: 16),
              _fieldLabel('Audience'),
              DropdownButtonFormField<String>(
                value: _audience,
                items: const [
                  DropdownMenuItem(value: 'school_wide', child: Text('Whole school')),
                  DropdownMenuItem(value: 'class', child: Text('One class')),
                  DropdownMenuItem(value: 'staff', child: Text('Staff')),
                  DropdownMenuItem(value: 'leadership', child: Text('Leadership')),
                ],
                onChanged: _loading ? null : (value) => setState(() {
                  _audience = value ?? 'school_wide';
                  _classId = null;
                }),
              ),
              if (_audience == 'class') ...[
                const SizedBox(height: 16),
                _fieldLabel('Class'),
                if (_loadingClasses)
                  const LinearProgressIndicator()
                else
                  DropdownButtonFormField<String>(
                    value: _classId,
                    items: _classes.map((item) => DropdownMenuItem<String>(
                      value: item['id'] as String,
                      child: Text(item['name']?.toString() ?? 'Class'),
                    )).toList(),
                    onChanged: _loading ? null : (value) => setState(() => _classId = value),
                    hint: const Text('Select a class'),
                  ),
              ],
              const SizedBox(height: 10),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _requiresAck,
                onChanged: _loading ? null : (value) => setState(() => _requiresAck = value ?? false),
                title: const Text('Requires acknowledgement'),
                subtitle: const Text('The notice requires a receipt confirmation.'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loading ? null : () => _publish(identity.schoolId),
                child: _loading ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Publish announcement'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _fieldLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink700)),
  );
}
