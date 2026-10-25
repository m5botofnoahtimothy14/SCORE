import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/layout/responsive.dart';
import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mentor_desk_design.dart';
import '../../../core/widgets/states.dart';
import '../../mentor_desk/models/mentor_desk_models.dart';
import '../../mentor_desk/services/mentor_desk_service.dart';

final _serviceProvider = Provider<MentorDeskService>(
  (ref) => MentorDeskService(Supabase.instance.client),
);

class SubmitDoubtScreen extends ConsumerStatefulWidget {
  const SubmitDoubtScreen({super.key});

  @override
  ConsumerState<SubmitDoubtScreen> createState() => _SubmitDoubtScreenState();
}

class _SubmitDoubtScreenState extends ConsumerState<SubmitDoubtScreen> {
  final _formKey = GlobalKey<FormState>();
  final _questionCtrl = TextEditingController();
  final _chapterCtrl = TextEditingController();
  final _qnCtrl = TextEditingController();
  final _explanationCtrl = TextEditingController();
  final _attemptsCtrl = TextEditingController();
  final _urgentReasonCtrl = TextEditingController();

  List<SubjectWithName> _subjects = const [];
  SubjectWithName? _selectedSubject;
  final List<XFile> _images = [];
  List<String> _attachmentIds = [];
  bool _urgent = false;
  bool _loadingSubjects = true;
  bool _submitting = false;
  String? _error;
  String? _schoolId;
  String? _studentId;
  bool _urgentAvailable = false;

  int _step = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _questionCtrl.dispose();
    _chapterCtrl.dispose();
    _qnCtrl.dispose();
    _explanationCtrl.dispose();
    _attemptsCtrl.dispose();
    _urgentReasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final identity = await ref.read(identityProvider.future);
    _schoolId = identity.schoolId;
    _studentId = identity.userId;
    final service = ref.read(_serviceProvider);
    final subjects = await service.listSubjects(_schoolId!);
    final allowances = await service.allowanceSummary(schoolId: _schoolId!, studentId: _studentId!);
    _urgentAvailable = allowances.any((a) => a.urgentPassAvailable);
    if (!mounted) return;
    setState(() {
      _subjects = subjects;
      _loadingSubjects = false;
    });
  }

  bool get _canSubmit =>
      _selectedSubject != null && _questionCtrl.text.trim().isNotEmpty && _images.length <= MentorDeskService.maxAttachments;

  Future<void> _pickImages() async {
    final remaining = MentorDeskService.maxAttachments - _images.length;
    if (remaining <= 0) return;
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(maxWidth: 1920, imageQuality: 85, limit: remaining);
    if (picked.isEmpty) return;
    setState(() => _images.addAll(picked));
  }

  void _removeImage(int index) {
    setState(() => _images.removeAt(index));
  }

  Future<void> _uploadAndSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedSubject == null) {
      setState(() => _error = 'Please select a subject.');
      return;
    }
    if (_urgent && !_urgentAvailable) {
      setState(() => _error = 'You have no urgent pass available for this subject this week.');
      return;
    }
    if (_urgent && _urgentReasonCtrl.text.trim().isEmpty) {
      setState(() => _error = 'A reason is required for an urgent request.');
      return;
    }
    setState(() { _submitting = true; _error = null; });

    try {
      final service = ref.read(_serviceProvider);
      final ids = await service.uploadImages(
        schoolId: _schoolId!,
        conversationId: 'pending',
        files: _images,
      );
      _attachmentIds = ids;

      final req = await service.submitDoubt(
        subjectId: _selectedSubject!.id,
        question: _questionCtrl.text.trim(),
        chapter: _chapterCtrl.text.trim().isEmpty ? null : _chapterCtrl.text.trim(),
        questionNumber: _qnCtrl.text.trim().isEmpty ? null : _qnCtrl.text.trim(),
        explanation: _explanationCtrl.text.trim().isEmpty ? null : _explanationCtrl.text.trim(),
        previousAttempts: _attemptsCtrl.text.trim().isEmpty ? null : _attemptsCtrl.text.trim(),
        urgent: _urgent,
        urgentReason: _urgent ? _urgentReasonCtrl.text.trim() : null,
        attachmentIds: _attachmentIds,
      );

      if (!mounted) return;
      setState(() => _submitting = false);
      context.go('/mentor-desk/doubt/${req.id}');
    } on MentorDeskException catch (e) {
      if (!mounted) return;
      setState(() { _submitting = false; _error = e.message; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _submitting = false; _error = 'Could not submit the doubt. Please try again.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    const tier = MDTier.student;

    return Scaffold(
      backgroundColor: MDColors.ink50,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Ask a Doubt'),
      ),
      body: _loadingSubjects
          ? const LoadingView()
          : AdaptivePage(
              maxWidth: 700,
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(kGutter),
                  children: [
                    if (_step == 0) ...[
                      const MDSectionHeader(title: '1 · Select subject'),
                      const SizedBox(height: kGutter),
                      DropdownButtonFormField<SubjectWithName>(
                        initialValue: _selectedSubject,
                        hint: const Text('Choose a subject'),
                        items: _subjects
                            .map((s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(s.name),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedSubject = v),
                        validator: (_) => _selectedSubject == null ? 'Select a subject' : null,
                        decoration: InputDecoration(
                          labelText: 'Subject',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(kRadiusSm)),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(kRadiusSm),
                            borderSide: BorderSide(color: tier.solid, width: 1.6),
                          ),
                        ),
                      ),
                      const SizedBox(height: kGutter),
                      const Text('Your subject list is configured by your school.', style: TextStyle(fontSize: 12, color: MDColors.ink600)),
                      const SizedBox(height: kGutter),
                      SizedBox(
                        width: double.infinity,
                        child: MDGlossButton(
                          onPressed: _selectedSubject == null ? null : () => setState(() => _step = 1),
                          child: const Text('Continue'),
                        ),
                      ),
                    ] else if (_step == 1) ...[
                      const MDSectionHeader(title: '2 · Your question'),
                      const SizedBox(height: kGutter),
                      MDGlossInput(
                        controller: _questionCtrl,
                        label: 'Question (one line)',
                        hint: 'e.g. How do I solve this quadratic equation?',
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your question' : null,
                        maxLines: 3,
                      ),
                      const SizedBox(height: kGutter),
                      const Text('Or attach a photo of the question instead.', style: TextStyle(fontSize: 12, color: MDColors.ink600)),
                      const SizedBox(height: kGutter),
                      SizedBox(
                        width: double.infinity,
                        child: MDGlossOutlineButton(
                          onPressed: () { _pickImages(); },
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.image_outlined, size: 18),
                              SizedBox(width: kGutter / 2),
                              Text('Attach image'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: kGutter),
                      const Text('Up to 4 images. Each is safety-reviewed before others see it.', style: TextStyle(fontSize: 12, color: MDColors.ink600)),
                      const SizedBox(height: kGutter),
                      Wrap(
                        spacing: kGutter,
                        runSpacing: kGutter,
                        children: [
                          for (var i = 0; i < _images.length; i++)
                            _ChipImage(image: _images[i], onRemove: () => _removeImage(i)),
                        ],
                      ),
                      const SizedBox(height: kGutter * 2),
                      Row(
                        children: [
                          TextButton(onPressed: () => setState(() => _step = 0), child: const Text('Back')),
                          const Spacer(),
                          MDGlossButton(
                            onPressed: _canSubmit ? () => setState(() => _step = 2) : null,
                            child: const Text('Continue'),
                          ),
                        ],
                      ),
                    ] else if (_step == 2) ...[
                      const MDSectionHeader(title: '3 · Details (optional)'),
                      const SizedBox(height: kGutter),
                      MDGlossInput(controller: _chapterCtrl, label: 'Chapter', hint: 'e.g. Chapter 4'),
                      const SizedBox(height: kGutter),
                      MDGlossInput(controller: _qnCtrl, label: 'Question number', hint: 'e.g. Q3'),
                      const SizedBox(height: kGutter),
                      MDGlossInput(controller: _explanationCtrl, label: 'Explanation / what you tried', hint: 'Optional', maxLines: 3),
                      const SizedBox(height: kGutter),
                      MDGlossInput(controller: _attemptsCtrl, label: 'Previous attempts', hint: 'What have you tried so far?', maxLines: 3),
                      const SizedBox(height: kGutter * 2),
                      Row(
                        children: [
                          Checkbox(
                            value: _urgent,
                            onChanged: _urgentAvailable ? (v) => setState(() => _urgent = v ?? false) : null,
                          ),
                          const SizedBox(width: kGutter / 2),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                text: 'Urgent request ',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                                children: [
                                  TextSpan(
                                    text: '(${_urgentAvailable ? 'available' : 'used this week'})',
                                    style: TextStyle(fontSize: 12, color: _urgentAvailable ? MDColors.success : MDColors.ink600),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_urgent) ...[
                        const SizedBox(height: kGutter),
                        MDGlossInput(controller: _urgentReasonCtrl, label: 'Reason for urgency *', hint: 'Why is this urgent?', maxLines: 2),
                      ],
                      const SizedBox(height: kGutter * 2),
                      Row(
                        children: [
                          TextButton(onPressed: () => setState(() => _step = 1), child: const Text('Back')),
                          const Spacer(),
                          MDGlossButton(onPressed: () => setState(() => _step = 3), child: const Text('Review')),
                        ],
                      ),
                    ] else ...[
                      const MDSectionHeader(title: '4 · Review before sending'),
                      const SizedBox(height: kGutter),
                      _ReviewRow(label: 'Subject', value: _selectedSubject!.name),
                      const SizedBox(height: kGutter),
                      _ReviewRow(label: 'Question', value: _questionCtrl.text.trim()),
                      if (_chapterCtrl.text.trim().isNotEmpty) ...[
                        const SizedBox(height: kGutter),
                        _ReviewRow(label: 'Chapter', value: _chapterCtrl.text.trim()),
                      ],
                      if (_qnCtrl.text.trim().isNotEmpty) ...[
                        const SizedBox(height: kGutter),
                        _ReviewRow(label: 'Question #', value: _qnCtrl.text.trim()),
                      ],
                      if (_explanationCtrl.text.trim().isNotEmpty) ...[
                        const SizedBox(height: kGutter),
                        _ReviewRow(label: 'Explanation', value: _explanationCtrl.text.trim()),
                      ],
                      if (_attemptsCtrl.text.trim().isNotEmpty) ...[
                        const SizedBox(height: kGutter),
                        _ReviewRow(label: 'Previous attempts', value: _attemptsCtrl.text.trim()),
                      ],
                      if (_images.isNotEmpty) ...[
                        const SizedBox(height: kGutter),
                        _ReviewRow(label: 'Attachments', value: '${_images.length} image${_images.length > 1 ? 's' : ''}'),
                      ],
                      if (_urgent) ...[
                        const SizedBox(height: kGutter),
                        _ReviewRow(label: 'Urgent', value: 'Yes — ${_urgentReasonCtrl.text.trim()}'),
                      ],
                      const SizedBox(height: kGutter * 2),
                      if (_error != null)
                        Container(
                          padding: const EdgeInsets.all(kGutter),
                          color: const Color(0xFFFEF2F2),
                          child: Text(_error!, style: const TextStyle(color: MDColors.danger, fontSize: 13)),
                        ),
                      const SizedBox(height: kGutter),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: MDGlossButton(
                          onPressed: _submitting ? null : () { _uploadAndSubmit(); },
                          child: _submitting
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Submit Doubt'),
                        ),
                      ),
                      const SizedBox(height: kGutter),
                      TextButton(onPressed: () => setState(() => _step = 2), child: const Text('Edit details')),
                    ],
                   ],
              ),
            ),
            ),
      );
  }
}

class _ReviewRow extends StatelessWidget {
  final String label;
  final String value;
  const _ReviewRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 110, child: Text(label, style: const TextStyle(fontSize: 13, color: MDColors.ink600))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
      ],
    );
  }
}

class _ChipImage extends StatelessWidget {
  final XFile image;
  final VoidCallback onRemove;
  const _ChipImage({required this.image, required this.onRemove});
  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            image: DecorationImage(image: FileImage(File(image.path)), fit: BoxFit.cover),
          ),
        ),
        Positioned(
          right: -6, top: -6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 20, height: 20,
              decoration: const BoxDecoration(color: MDColors.danger, shape: BoxShape.circle),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
