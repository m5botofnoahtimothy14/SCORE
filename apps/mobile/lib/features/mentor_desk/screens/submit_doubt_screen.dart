import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
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
  final _picker = ImagePicker();

  bool _loading = false;
  String? _error;
  String? _subjectId;
  List<SubjectWithName> _subjects = [];
  String? _schoolId;
  List<XFile> _selectedImages = [];

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
      // If no subjects from DB, provide defaults: Chemistry, Physics, Biology
      if (_subjects.isEmpty) {
        _subjects = [
          SubjectWithName(id: 'mathematics', name: 'Mathematics'),
          SubjectWithName(id: 'physics', name: 'Physics'),
          SubjectWithName(id: 'chemistry', name: 'Chemistry'),
          SubjectWithName(id: 'biology', name: 'Biology'),
        ];
      }
      if (!mounted) return;
      setState(() { _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_selectedImages.length >= MentorDeskService.maxAttachments) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('You can attach up to 4 images.'),
        backgroundColor: MDColors.warning,
      ));
      return;
    }
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 75);
      if (picked != null) {
        setState(() { _selectedImages.add(picked); });
      }
    } catch (e) {
      if (mounted) setState(() { _error = 'Failed to pick image: $e'; });
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
      final identity = await ref.read(identityProviderProvider.future);
      if (identity == null) throw Exception('No identity found');

      // Upload images first
      List<String> attachmentIds = [];
      if (_selectedImages.isNotEmpty) {
        // Create a temporary conversation ID for upload path
        final tempConvId = 'doubt-${DateTime.now().millisecondsSinceEpoch}';
        attachmentIds = await service.uploadXFiles(
          schoolId: identity.schoolId,
          conversationId: tempConvId,
          files: _selectedImages,
        );
      }

      await service.submitDoubt(
        subjectId: _subjectId!,
        question: _questionController.text.trim(),
        urgent: false,
        attachmentIds: attachmentIds,
      );
      if (!mounted) return;
      setState(() { _loading = false; _selectedImages.clear(); });
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
          onPressed: () => context.canPop() ? context.pop() : context.go("/home"),
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
                          hint: _subjects.isEmpty
                              ? const Text('No subjects available')
                              : null,
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
                        const SizedBox(height: 16),
                        // Attachments
                        Row(
                          children: [
                            Text('Attachments (optional)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MDColors.ink700)),
                            const Spacer(),
                            TextButton.icon(
                              icon: const Icon(Icons.photo_library, size: 18),
                              label: const Text('Gallery'),
                              onPressed: () => _pickImage(ImageSource.gallery),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.camera_alt, size: 18),
                              label: const Text('Camera'),
                              onPressed: () => _pickImage(ImageSource.camera),
                            ),
                          ],
                        ),
                        if (_selectedImages.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 80,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _selectedImages.length,
                              itemBuilder: (context, index) {
                                return Stack(
                                  children: [
                                    Container(
                                      width: 80, height: 80,
                                      margin: const EdgeInsets.only(right: 8),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(kRadiusSm),
                                        border: Border.all(color: MDColors.ink200),
                                        image: DecorationImage(
                                          image: FileImage(File(_selectedImages[index].path)),
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 2, right: 2,
                                      child: GestureDetector(
                                        onTap: () => setState(() { _selectedImages.removeAt(index); }),
                                        child: Container(
                                          padding: const EdgeInsets.all(3),
                                          decoration: const BoxDecoration(color: MDColors.danger, shape: BoxShape.circle),
                                          child: const Icon(Icons.close, size: 14, color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
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


