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
import '../models/mentor_desk_models.dart';
import '../services/mentor_desk_service.dart';

final mentorDeskServiceProvider = Provider<MentorDeskService>((ref) {
  return MentorDeskService(Supabase.instance.client);
});

class SubmitDoubtScreen extends ConsumerStatefulWidget {
  const SubmitDoubtScreen({super.key});
  @override
  ConsumerState<SubmitDoubtScreen> createState() => _SubmitDoubtScreenState();
}

class _SubmitDoubtScreenState extends ConsumerState<SubmitDoubtScreen> {
  final _formKey = GlobalKey<FormState>();
  final _questionController = TextEditingController();

  bool _loading = false;
  String? _error;
  String? _subjectId;
  List<SubjectWithName> _subjects = [];
  String? _schoolId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final identity = await ref.read(identityProviderProvider.future);
      if (identity == null) throw Exception('No identity found');
      _schoolId = identity.schoolId;
      final service = ref.read(mentorDeskServiceProvider);
      _subjects = await service.listSubjects(_schoolId!);
      if (!mounted) return;
      setState(() { _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_subjectId == null) {
      setState(() { _error = 'Please select a subject.'; });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final service = ref.read(mentorDeskServiceProvider);
      await service.submitDoubt(
        subjectId: _subjectId!,
        question: _questionController.text.trim(),
        urgent: false,
        attachmentIds: [],
      );
      if (!mounted) return;
      setState(() { _loading = false; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Doubt submitted successfully'),
        backgroundColor: MDColors.success,
        duration: Duration(seconds: 4),
      ));
      context.go('/mentor-desk');
    } on MentorDeskException catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.message; });
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
        title: const Text('Ask a Doubt', style: TextStyle(color: MDColors.ink900, fontWeight: FontWeight.w800)),
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
                        Text('Submit your doubt', style: Theme.of(context).textTheme.headlineMedium),
                        const SizedBox(height: 24),
                        DropdownButtonFormField<String>(
                          value: _subjectId,
                          decoration: InputDecoration(
                            labelText: 'Subject *',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(kRadiusSm),
                            ),
                          ),
                          items: _subjects.map((s) {
                            return DropdownMenuItem<String>(
                              value: s.id,
                              child: Text(s.name),
                            );
                          }).toList(),
                          onChanged: (id) => setState(() { _subjectId = id; }),
                          validator: (v) => v == null ? 'Subject is required' : null,
                        ),
                        const SizedBox(height: 16),
                        MDGlossInput(
                          controller: _questionController,
                          label: 'Your question *',
                          hint: 'Enter your question in one line',
                          maxLines: 2,
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your question' : null,
                        ),
                        const SizedBox(height: 24),
                        MDButton(
                          onPressed: _submit,
                          loading: _loading,
                          child: const Text('Submit Doubt', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}


