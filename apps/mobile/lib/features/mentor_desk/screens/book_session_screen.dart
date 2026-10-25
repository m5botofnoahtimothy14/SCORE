import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mentor_desk_design.dart';
import '../../../core/layout/responsive.dart';
import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/widgets/states.dart';
import '../../mentor_desk/models/mentor_desk_models.dart';
import '../../mentor_desk/services/mentor_desk_service.dart';

final _serviceProvider = Provider<MentorDeskService>(
  (ref) => MentorDeskService(Supabase.instance.client),
);

/// Book a session: subject -> mentor -> date/time -> length -> topic/prep ->
/// attachments (up to 4) -> submit. Allowance enforced server-side.
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

  String? _schoolId;
  String? _studentId;
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  final List<XFile> _images = [];

  final String _mode = 'any'; // 'any' | 'specific'
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
    final service = ref.read(_serviceProvider);
    final subjects = await service.listSubjects(_schoolId!);
    if (!mounted) return;
    setState(() {
      _subjects = subjects;
      _loading = false;
    });
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

  bool get _canSubmit =>
      _selectedSubject != null &&
      _topicCtrl.text.trim().isNotEmpty &&
      _scheduledAt != null &&
      _images.length <= MentorDeskService.maxAttachments;

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
    const String? mentorId = null; // any available mentor
    setState(() { _submitting = true; _error = null; });

    try {
      final service = ref.read(_serviceProvider);
      final ids = await service.uploadImages(
        schoolId: _schoolId!,
        conversationId: 'pending-booking',
        files: _images,
      );

      final booking = await service.bookSession(
        subjectId: _selectedSubject!.id,
        mentorId: mentorId,
        durationMinutes: _duration,
        scheduledAt: _scheduledAt!,
        topic: _topicCtrl.text.trim(),
        preparation: _prepCtrl.text.trim().isEmpty ? null : _prepCtrl.text.trim(),
        attachmentIds: ids,
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

  @override
  Widget build(BuildContext context) {
    const tier = MDTier.student;

    return Scaffold(
      backgroundColor: MDColors.ink50,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, title: const Text('Book a Session')),
      body: _loading
          ? const LoadingView()
          : AdaptivePage(
              maxWidth: 700,
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(kGutter),
                  children: [
                    const MDSectionHeader(title: '1 · Subject'),
                    const SizedBox(height: kGutter),
                    DropdownButtonFormField<SubjectWithName>(
                      initialValue: _selectedSubject,
                      hint: const Text('Choose a subject'),
                      items: _subjects
                          .map((s) => DropdownMenuItem(value: s, child: Text(s.name)))
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
                    const SizedBox(height: kGutter * 2),
                    const MDSectionHeader(title: '2 · Date & time'),
                    const SizedBox(height: kGutter),
                    _DateTimeTile(
                      label: 'Date',
                      value: _selectedDate == null ? 'Pick a date' : DateFormat('EEE, MMM d').format(_selectedDate!),
                      onTap: _pickDateTime,
                    ),
                    const SizedBox(height: kGutter),
                    _DateTimeTile(
                      label: 'Time',
                      value: _selectedTime == null ? 'Pick a time' : _selectedTime!.format(context),
                      onTap: () async {
                        final time = await showTimePicker(context: context, initialTime: _selectedTime ?? TimeOfDay.now());
                        if (time != null) setState(() => _selectedTime = time);
                      },
                    ),
                    const SizedBox(height: kGutter),
                    const Text('Session length', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: kGutter / 2),
                    Wrap(
                      spacing: kGutter,
                      runSpacing: kGutter,
                      children: [15, 30, 45].map((m) {
                        final selected = _duration == m;
                        return MDChip(
                          label: '$m min',
                          selected: selected,
                          color: tier.solid,
                          onSelected: (_) => setState(() => _duration = m),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: kGutter * 2),
                    const MDSectionHeader(title: '3 · Topic & preparation'),
                    const SizedBox(height: kGutter),
                    MDGlossInput(
                      controller: _topicCtrl,
                      label: 'Topic',
                      hint: 'e.g. Quadratic equations',
                      validator: (v) => v == null || v.trim().isEmpty ? 'Enter a topic' : null,
                    ),
                    const SizedBox(height: kGutter),
                    MDGlossInput(
                      controller: _prepCtrl,
                      label: 'Preparation (optional)',
                      hint: 'What should the mentor know?',
                      maxLines: 3,
                    ),
                    const SizedBox(height: kGutter * 2),
                    const MDSectionHeader(title: '4 · Attachments (up to 4 images)'),
                    const SizedBox(height: kGutter),
                    Row(
                      children: [
                        Expanded(
                          child: MDGlossOutlineButton(
                            onPressed: _pickImages,
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.image_outlined, size: 18),
                                SizedBox(width: 8),
                                Text('Attach image'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
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

class _DateTimeTile extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  const _DateTimeTile({required this.label, required this.value, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: MDColors.ink50.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(kRadiusSm),
        border: Border.all(color: MDColors.ink200.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MDColors.ink600)),
                const SizedBox(height: 6),
                Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: MDColors.ink900)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: MDColors.ink400),
        ],
      ),
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
