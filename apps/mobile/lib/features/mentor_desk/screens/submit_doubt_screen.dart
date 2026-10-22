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
import '../../../core/widgets/states.dart';
import '../../mentor_desk/models/mentor_desk_models.dart';
import '../../mentor_desk/services/mentor_desk_service.dart';

final _serviceProvider = Provider<MentorDeskService>(
  (ref) => MentorDeskService(Supabase.instance.client),
);

/// Guided doubt submission: subject -> question (text or attachment) -> optional
/// details -> attachments (up to 4) -> urgent pass -> summary -> send.
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
  List<XFile> _images = [];
  List<String> _attachmentIds = [];
  bool _urgent = false;
  bool _loadingSubjects = true;
  bool _submitting = false;
  String? _error;
  String? _schoolId;
  String? _studentId;
  bool _urgentAvailable = false;

  // Wizard state
  int _step = 0; // 0 subject, 1 question, 2 details, 3 summary

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

  bool get _canSubmit => _selectedSubject != null && _questionCtrl.text.trim().isNotEmpty && _images.length <= MentorDeskService.maxAttachments;

  Future<void> _pickImages() async {
    final remaining = MentorDeskService.maxAttachments - _images.length;
    if (remaining <= 0) return;
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(
      maxWidth: 1920,
      imageQuality: 85,
      limit: remaining,
    );
    if (picked.isEmpty) return;
    setState(() => _images.addAll(picked));
  }

  void _removeImage(int index) {
    setState(() => _images.removeAt(index));
  }

  String _mime(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
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
      // Upload images first (need a conversation id — use a placeholder, RPC links them)
      // We upload to a temp conversation path; submit_doubt will link attachments.
      final convId = const String.fromEnvironment('conversation_id', defaultValue: 'pending');
      final ids = await service.uploadImages(
        schoolId: _schoolId!,
        conversationId: convId,
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
    final accent = TierAccent.of(AppTier.student);

    return Scaffold(
      appBar: AppBar(title: const Text('Ask a Doubt')),
      body: _loadingSubjects
          ? const LoadingView()
          : AdaptivePage(
              maxWidth: 700,
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_step == 0) ...[
                      _SectionTitle('1 · Select subject'),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<SubjectWithName>(
                        value: _selectedSubject,
                        hint: const Text('Choose a subject'),
                        items: _subjects
                            .map((s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(s.name),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedSubject = v),
                        validator: (_) => _selectedSubject == null ? 'Select a subject' : null,
                        decoration: const InputDecoration(
                          labelText: 'Subject',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('Your subject list is configured by your school.'),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _selectedSubject == null ? null : () => setState(() => _step = 1),
                          child: const Text('Continue'),
                        ),
                      ),
                    ] else if (_step == 1) ...[
                      _SectionTitle('2 · Your question'),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _questionCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Question (one line)',
                          hintText: 'e.g. How do I solve this quadratic equation?',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your question' : null,
                      ),
                      const SizedBox(height: 10),
                      const Text('Or attach a photo of the question instead.', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _pickImages,
                            icon: const Icon(Icons.image_outlined, size: 18),
                            label: const Text('Attach image'),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (var i = 0; i < _images.length; i++)
                                  _ChipImage(image: _images[i], onRemove: () => _removeImage(i)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Text('Up to 4 images. Each is safety-reviewed before others see it.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          TextButton(onPressed: () => setState(() => _step = 0), child: const Text('Back')),
                          const Spacer(),
                          ElevatedButton(onPressed: _canSubmit ? () => setState(() => _step = 2) : null, child: const Text('Continue')),
                        ],
                      ),
                    ] else if (_step == 2) ...[
                      _SectionTitle('3 · Details (optional)'),
                      const SizedBox(height: 10),
                      _Field(controller: _chapterCtrl, label: 'Chapter', hint: 'e.g. Chapter 4'),
                      const SizedBox(height: 10),
                      _Field(controller: _qnCtrl, label: 'Question number', hint: 'e.g. Q3'),
                      const SizedBox(height: 10),
                      _Field(controller: _explanationCtrl, label: 'Explanation / what you tried', hint: 'Optional', maxLines: 3),
                      const SizedBox(height: 10),
                      _Field(controller: _attemptsCtrl, label: 'Previous attempts', hint: 'What have you tried so far?', maxLines: 3),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Checkbox(
                            value: _urgent,
                            onChanged: _urgentAvailable ? (v) => setState(() => _urgent = v ?? false) : null,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                text: 'Urgent request ',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                                children: [
                                  TextSpan(
                                    text: '(${_urgentAvailable ? 'available' : 'used this week'})',
                                    style: TextStyle(fontSize: 12, color: _urgentAvailable ? Colors.green : Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_urgent) ...[
                        const SizedBox(height: 10),
                        _Field(controller: _urgentReasonCtrl, label: 'Reason for urgency *', hint: 'Why is this urgent?', maxLines: 2),
                      ],
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          TextButton(onPressed: () => setState(() => _step = 1), child: const Text('Back')),
                          const Spacer(),
                          ElevatedButton(onPressed: () => setState(() => _step = 3), child: const Text('Review')),
                        ],
                      ),
                    ] else ...[
                      _SectionTitle('4 · Review before sending'),
                      const SizedBox(height: 10),
                      _ReviewRow(label: 'Subject', value: _selectedSubject!.name),
                      const SizedBox(height: 8),
                      _ReviewRow(label: 'Question', value: _questionCtrl.text.trim()),
                      if (_chapterCtrl.text.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _ReviewRow(label: 'Chapter', value: _chapterCtrl.text.trim()),
                      ],
                      if (_qnCtrl.text.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _ReviewRow(label: 'Question #', value: _qnCtrl.text.trim()),
                      ],
                      if (_explanationCtrl.text.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _ReviewRow(label: 'Explanation', value: _explanationCtrl.text.trim()),
                      ],
                      if (_attemptsCtrl.text.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _ReviewRow(label: 'Previous attempts', value: _attemptsCtrl.text.trim()),
                      ],
                      if (_images.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _ReviewRow(label: 'Attachments', value: '${_images.length} image${_images.length > 1 ? 's' : ''}'),
                      ],
                      if (_urgent) ...[
                        const SizedBox(height: 8),
                        _ReviewRow(label: 'Urgent', value: 'Yes — ${_urgentReasonCtrl.text.trim()}'),
                      ],
                      const SizedBox(height: 20),
                      if (_error != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          color: const Color(0xFFFEF2F2),
                          child: Text(_error!, style: const TextStyle(color: Color(0xFF991B1B), fontSize: 13)),
                        ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _submitting ? null : _uploadAndSubmit,
                          child: _submitting
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Submit Doubt'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(onPressed: () => setState(() => _step = 2), child: const Text('Edit details')),
                    ]],
                  ),
                ),
              ),
            );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: Color(0xFF64748B)));
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  const _Field({required this.controller, required this.label, required this.hint, this.maxLines = 1});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          ),
        ),
      ],
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
        SizedBox(width: 110, child: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)))),
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
              decoration: const BoxDecoration(color: Color(0xFFDC2626), shape: BoxShape.circle),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
