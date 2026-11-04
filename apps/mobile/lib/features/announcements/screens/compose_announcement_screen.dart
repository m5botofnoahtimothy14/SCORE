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

class ComposeAnnouncementScreen extends ConsumerStatefulWidget {
  const ComposeAnnouncementScreen({super.key});

  @override
  ConsumerState<ComposeAnnouncementScreen> createState() => _ComposeAnnouncementScreenState();
}

class _ComposeAnnouncementScreenState extends ConsumerState<ComposeAnnouncementScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  String? _error;
  String? _schoolId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final identity = await ref.read(identityProviderProvider.future);
      if (identity == null) throw Exception('No identity found');
      _schoolId = identity.schoolId;
      if (!mounted) return;
      setState(() { _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _publish() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      final identity = await ref.read(identityProviderProvider.future);
      if (identity == null) throw Exception('No identity found');
      await Supabase.instance.client.from('announcements').insert({
        'school_id': _schoolId,
        'title': _titleController.text.trim(),
        'body': _bodyController.text.trim(),
        'author_id': identity.userId,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Announcement published'),
        backgroundColor: MDColors.success,
        duration: Duration(seconds: 4),
      ));
      context.go('/announcements');
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
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
        title: const Text('Compose Notice', style: TextStyle(color: MDColors.ink900, fontWeight: FontWeight.w800)),
        centerTitle: false,
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    horizontalGutter(context),
                    16,
                    horizontalGutter(context),
                    MediaQuery.of(context).padding.bottom + 24,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Compose a Notice', style: Theme.of(context).textTheme.headlineMedium),
                        const SizedBox(height: 8),
                        Text('Share important information with your school.',
                            style: TextStyle(fontSize: 14, color: MDColors.ink600)),
                        const SizedBox(height: 24),
                        MDGlossInput(
                          controller: _titleController,
                          label: 'Title *',
                          hint: 'Enter the notice title',
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Title is required' : null,
                        ),
                        const SizedBox(height: 16),
                        MDGlossInput(
                          controller: _bodyController,
                          label: 'Body *',
                          hint: 'Enter the notice content',
                          maxLines: 8,
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Body is required' : null,
                        ),
                        const SizedBox(height: 28),
                        MDButton(
                          onPressed: _publish,
                          loading: _loading,
                          child: const Text('Publish Notice', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}


