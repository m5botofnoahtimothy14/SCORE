import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../models/mentor_desk_models.dart';
import '../services/mentor_desk_service.dart';

final _mentorServiceProvider = Provider((ref) => MentorDeskService(Supabase.instance.client));

class BookSessionScreen extends ConsumerStatefulWidget {
  const BookSessionScreen({super.key});

  @override
  ConsumerState<BookSessionScreen> createState() => _BookSessionScreenState();
}

class _BookSessionScreenState extends ConsumerState<BookSessionScreen> {
  final _topic = TextEditingController();
  final _preparation = TextEditingController();
  List<SubjectWithName> _subjects = [];
  String? _subjectId;
  DateTime _scheduledAt = DateTime.now().add(const Duration(days: 1));
  int _duration = 15;
  int _sessionMinutesRemaining = 60;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _topic.dispose();
    _preparation.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final identity = await ref.read(identityProviderProvider.future);
      if (identity == null || identity.tier != AppTier.student) {
        throw Exception('Session booking is available to student accounts.');
      }
      final service = ref.read(_mentorServiceProvider);
      final subjects = await service.listSubjects(identity.schoolId);
      final allowance = await service.allowanceSummary(schoolId: identity.schoolId, studentId: identity.userId);
      if (!mounted) return;
      setState(() {
        _subjects = subjects;
        _subjectId = subjects.isEmpty ? null : subjects.first.id;
        _sessionMinutesRemaining = allowance.isEmpty ? 0 : allowance.first.sessionRemainingMinutes;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = 'Could not load your subjects. Check your account and connection.'; _loading = false; });
    }
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt.isBefore(DateTime.now()) ? DateTime.now().add(const Duration(days: 1)) : _scheduledAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_scheduledAt));
    if (time == null) return;
    final next = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (next.isBefore(DateTime.now().add(const Duration(minutes: 10)))) {
      setState(() => _error = 'Choose a time at least 10 minutes from now.');
      return;
    }
    setState(() { _scheduledAt = next; _error = null; });
  }

  Future<void> _submit() async {
    if (_subjectId == null || _topic.text.trim().isEmpty) {
      setState(() => _error = 'Choose a subject and enter a session topic.');
      return;
    }
    if (_duration > _sessionMinutesRemaining) {
      setState(() => _error = 'You have $_sessionMinutesRemaining session minutes remaining. Choose a shorter session or check your weekly allowance.');
      return;
    }
    if (_scheduledAt.isBefore(DateTime.now().add(const Duration(minutes: 10)))) {
      setState(() => _error = 'Choose a future session time.');
      return;
    }
    setState(() { _submitting = true; _error = null; });
    try {
      final booking = await ref.read(_mentorServiceProvider).bookSession(
        subjectId: _subjectId!,
        durationMinutes: _duration,
        scheduledAt: _scheduledAt,
        topic: _topic.text.trim(),
        preparation: _preparation.text.trim().isEmpty ? null : _preparation.text.trim(),
      );
      if (!mounted) return;
      context.go('/mentor-desk/session/${booking.id}');
    } on MentorDeskException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not book the session. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Book a mentor session')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _subjects.isEmpty
              ? _ErrorState(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    const Text('Plan a focused session', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink900)),
                    const SizedBox(height: 6),
                    const Text('Choose a subject, a time and the support you need. A teacher is assigned by the school rules.', style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.ink500)),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13), border: Border.all(color: AppColors.ink200)),
                      child: Row(children: [
                        const Icon(Icons.timelapse_rounded, color: AppColors.accent, size: 18),
                        const SizedBox(width: 9),
                        Text('Weekly session time remaining: $_sessionMinutesRemaining minutes', style: const TextStyle(fontSize: 12, color: AppColors.ink700)),
                      ]),
                    ),
                    const SizedBox(height: 18),
                    _label('Subject'),
                    DropdownButtonFormField<String>(
                      value: _subjectId,
                      items: _subjects.map((subject) => DropdownMenuItem(value: subject.id, child: Text(subject.name))).toList(),
                      onChanged: _submitting ? null : (value) => setState(() => _subjectId = value),
                      hint: const Text('Select subject'),
                    ),
                    const SizedBox(height: 18),
                    _label('Session length'),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 15, label: Text('15 minutes')),
                        ButtonSegment(value: 30, label: Text('30 minutes')),
                      ],
                      selected: {_duration},
                      onSelectionChanged: _submitting ? null : (value) => setState(() => _duration = value.first),
                    ),
                    const SizedBox(height: 18),
                    _label('Date and time'),
                    OutlinedButton.icon(
                      onPressed: _submitting ? null : _pickDate,
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: Text('${_scheduledAt.day.toString().padLeft(2, '0')}/${_scheduledAt.month.toString().padLeft(2, '0')}/${_scheduledAt.year}  ·  ${TimeOfDay.fromDateTime(_scheduledAt).format(context)}'),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15), alignment: Alignment.centerLeft),
                    ),
                    const SizedBox(height: 18),
                    _label('What do you need help with?'),
                    TextField(controller: _topic, maxLength: 240, decoration: const InputDecoration(hintText: 'Example: Understand a Physics chapter')),
                    const SizedBox(height: 12),
                    _label('Preparation (optional)'),
                    TextField(controller: _preparation, minLines: 3, maxLines: 5, decoration: const InputDecoration(hintText: 'Share the topic, question or work you want to review.')),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                    ],
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Request session'),
                    ),
                  ],
                ),
    );
  }

  Widget _label(String value) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink700)),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
      ]),
    ),
  );
}
