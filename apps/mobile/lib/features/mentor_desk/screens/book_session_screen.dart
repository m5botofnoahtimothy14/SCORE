import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
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

/// Book a session: subject -> mentor (any or specific) -> date/time -> length ->
/// topic/prep -> attachments (up to 4) -> submit. Allowance enforced server-side.
class BookSessionScreen extends ConsumerStatefulWidget {
  const BookSessionScreen({super.key});

  @override
  ConsumerState<BookSessionScreen> createState() => _BookSessionScreenState();
}

class _BookSessionScreenState extends ConsumerState<BookSessionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _topicCtrl = TextEditingController();
  final _prepCtrl = TextEditingController();

  List<SubjectWithName> _subjects = const [];
  SubjectWithName? _selectedSubject;
  List<MentorSubjectApproval> _approvals = const [];
  List<Map<String, dynamic>> _mentors = []; // {id, name, subjectId, available}

  String? _schoolId;
  String? _studentId;
  String? _teacherId;
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  List<XFile> _images = [];
  List<String> _attachmentIds = [];

  String _mode = 'any'; // 'any' | 'specific'
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  int _duration = 30;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _topicCtrl.dispose();
    _prepCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final identity = await ref.read(identityProvider.future);
    _schoolId = identity.schoolId;
    _studentId = identity.userId;
    _teacherId = identity.teacherId;
    final service = ref.read(_serviceProvider);
    final subjects = await service.listSubjects(_schoolId!);
    if (!mounted) return;
    setState(() {
      _subjects = subjects;
      _loading = false;
    });
  }

  Future<void> _loadMentorsForSubject() async {
    if (_selectedSubject == null) return;
    final service = ref.read(_serviceProvider);
    // Find teachers approved for this subject who are active
    final client = Supabase.instance.client;
    final approvals = await service.listMyApprovals(_teacherId!);
    _approvals = approvals;
    setState(() {});
  }

  Future<void> _pickImages() async {
    final remaining = MentorDeskService.maxAttachments - _images.length;
    if (remaining <= 0) return;
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(maxWidth: 1920, imageQuality: 85, limit: remaining);
    if (picked.isEmpty) return;
    setState(() => _images.addAll(picked));
  }

  void _removeImage(int index) => setState(() => _images.removeAt(index));

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (date == null) return;
    final time = await showTimePicker(context: context, initialTime: _selectedTime ?? TimeOfDay.now());
    if (time == null) return;
    setState(() {
      _selectedDate = date;
      _selectedTime = time;
    });
  }

  DateTime? get _scheduledAt {
    if (_selectedDate == null || _selectedTime == null) return null;
    return DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day,
        _selectedTime!.hour, _selectedTime!.minute);
  }

  bool get _canSubmit {
    final settings = MentorDeskService.maxAttachments;
    return _selectedSubject != null &&
        _topicCtrl.text.trim().isNotEmpty &&
        _scheduledAt != null &&
        _images.length <= settings;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedSubject == null) {
      setState(() => _error = 'Select a subject.');
      return;
    }
    if (_scheduledAt == null) {
      setState(() => _error = 'Pick a date and time.');
      return;
    }
    final String? mentorId = _mode == 'specific' ? _selectedMentor?.id : null;
    setState(() { _submitting = true; _error = null; });

    try {
      final service = ref.read(_serviceProvider);
      // Upload images to a temp path; the booking RPC links them.
      final ids = await service.uploadImages(
        schoolId: _schoolId!,
        conversationId: 'pending-booking',
        files: _images,
      );
      _attachmentIds = ids;

      final booking = await service.bookSession(
        subjectId: _selectedSubject!.id,
        mentorId: mentorId,
        durationMinutes: _duration,
        scheduledAt: _scheduledAt!,
        topic: _topicCtrl.text.trim(),
        preparation: _prepCtrl.text.trim().isEmpty ? null : _prepCtrl.text.trim(),
        attachmentIds: _attachmentIds,
      );

      if (!mounted) return;
      setState(() => _submitting = false);
      context.go('/mentor-desk/session/${booking.id}');
    } on MentorDeskException catch (e) {
      if (!mounted) return;
      setState(() { _submitting = false; _error = e.message; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _submitting = false; _error = 'Could not book the session. Please try again.'; });
    }
  }

  MentorSubjectApproval? get _selectedMentor {
    if (_mode != 'specific') return null;
    return _approvals.where((a) => a.isApproved).firstOrNull;
  }

  bool get _subjectHasApprovedMentor =>
      _approvals.any((a) => a.isApproved);

  @override
  Widget build(BuildContext context) {
    final accent = TierAccent.of(AppTier.student);

    return Scaffold(
      appBar: AppBar(title: const Text('Book a Session')),
      body: _loading
          ? const LoadingView()
          : AdaptivePage(
              maxWidth: 700,
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _SectionTitle('1 · Subject'),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<SubjectWithName>(
                      value: _selectedSubject,
                      hint: const Text('Choose a subject'),
                      items: _subjects
                          .map((s) => DropdownMenuItem(value: s, child: Text(s.name)))
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          _selectedSubject = v;
                          _approvals = const [];
                        });
                        _loadMentorsForSubject();
                      },
                      validator: (_) => _selectedSubject == null ? 'Select a subject' : null,
                      decoration: const InputDecoration(labelText: 'Subject', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),
                    if (_selectedSubject != null) ...[
                      const Text('Choose a mentor', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Expanded(child: Text('Any available mentor')),
                          Switch(value: _mode == 'specific', onChanged: (v) => setState(() => _mode = v ? 'specific' : 'any')),
                          const Expanded(child: Text('Specific mentor', textAlign: TextAlign.right)),
                        ],
                      ),
                      if (_mode == 'specific') ...[
                        const SizedBox(height: 10),
                        if (!_subjectHasApprovedMentor)
                          const Text('No approved mentor for this subject yet.', style: TextStyle(color: Color(0xFFDC2626), fontSize: 13)),
                        if (_subjectHasApprovedMentor)
                          DropdownButtonFormField<MentorSubjectApproval>(
                            value: _approvals.isNotEmpty ? _approvals.first : null,
                            items: _approvals
                                .where((a) => a.isApproved)
                                .map((a) => DropdownMenuItem(
                                      value: a,
                                      child: Text('Mentor · ${a.subjectId.substring(0, 6)}'),
                                    ))
                                .toList(),
                            onChanged: (v) => setState(() {}),
                            decoration: const InputDecoration(labelText: 'Mentor', border: OutlineInputBorder()),
                          ),
                      ],
                      const SizedBox(height: 16),
                    ],
                    _SectionTitle('2 · Date & time'),
                    const SizedBox(height: 10),
                    ListTile(
                      leading: const Icon(Icons.calendar_today, size: 20),
                      title: Text(_selectedDate == null ? 'Pick a date' : DateFormat('EEE, MMM d').format(_selectedDate!)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _pickDateTime,
                    ),
                    ListTile(
                      leading: const Icon(Icons.access_time, size: 20),
                      title: Text(_selectedTime == null ? 'Pick a time' : _selectedTime!.format(context)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        final time = await showTimePicker(context: context, initialTime: _selectedTime ?? TimeOfDay.now());
                        if (time != null) setState(() => _selectedTime = time);
                      },
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [15, 30, 45].map((m) {
                        final selected = _duration == m;
                        return FilterChip(
                          label: Text('$m min'),
                          selected: selected,
                          onSelected: (_) => setState(() => _duration = m),
                          avatar: selected ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    _SectionTitle('3 · Topic & preparation'),
                    const SizedBox(height: 10),
                    _Field(controller: _topicCtrl, label: 'Topic', hint: 'e.g. Quadratic equations', validator: (v) => v == null || v.trim().isEmpty ? 'Enter a topic' : null),
                    const SizedBox(height: 10),
                    _Field(controller: _prepCtrl, label: 'Preparation (optional)', hint: 'What should the mentor know?', maxLines: 3),
                    const SizedBox(height: 16),
                    _SectionTitle('4 · Attachments (up to 4 images)'),
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
                    const SizedBox(height: 24),
                    if (_error != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        color: const Color(0xFFFEF2F2),
                        child: Text(_error!, style: const TextStyle(color: Color(0xFF991B1B), fontSize: 13)),
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _submitting || !_canSubmit ? null : _submit,
                        child: _submitting
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Request Session'),
                      ),
                    ),
                  ],
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
  final String? Function(String?)? validator;
  const _Field({required this.controller, required this.label, required this.hint, this.maxLines = 1, this.validator});
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
          validator: validator,
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

class _ChipImage extends StatelessWidget {
  final XFile image;
  final VoidCallback onRemove;
  const _ChipImage({required this.image, required this.onRemove});
  @override
  Widget build(BuildContext context) {
    return Stack(clipBehavior: Clip.none, children: [
      Container(width: 64, height: 64, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE5E7EB)), image: DecorationImage(image: FileImage(File(image.path)), fit: BoxFit.cover))),
      Positioned(right: -6, top: -6, child: GestureDetector(onTap: onRemove, child: Container(width: 20, height: 20, decoration: const BoxDecoration(color: Color(0xFFDC2626), shape: BoxShape.circle), child: const Icon(Icons.close, size: 14, color: Colors.white)))),
    ]);
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
