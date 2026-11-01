import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../models/mentor_desk_models.dart';
import '../services/mentor_desk_service.dart';

final _mentorServiceProvider = Provider((ref) => MentorDeskService(Supabase.instance.client));

class SubmitDoubtScreen extends ConsumerStatefulWidget {
  const SubmitDoubtScreen({super.key});

  @override
  ConsumerState<SubmitDoubtScreen> createState() => _SubmitDoubtScreenState();
}

class _SubmitDoubtScreenState extends ConsumerState<SubmitDoubtScreen> {
  final _question = TextEditingController();
  final _chapter = TextEditingController();
  final _questionNumber = TextEditingController();
  final _explanation = TextEditingController();
  final _previousAttempts = TextEditingController();
  final _urgentReason = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  bool _urgent = false;
  String? _error;
  String? _schoolId;
  List<SubjectWithName> _subjects = [];
  List<AllowanceSummary> _allowances = [];
  String? _subjectId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _question.dispose();
    _chapter.dispose();
    _questionNumber.dispose();
    _explanation.dispose();
    _previousAttempts.dispose();
    _urgentReason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final identity = await ref.read(identityProviderProvider.future);
      if (identity == null || identity.tier != AppTier.student) {
        throw Exception('Only student accounts can submit a doubt.');
      }
      final service = ref.read(_mentorServiceProvider);
      final subjects = await service.listSubjects(identity.schoolId);
      final allowances = await service.allowanceSummary(
        schoolId: identity.schoolId,
        studentId: identity.userId,
      );
      if (!mounted) return;
      setState(() {
        _schoolId = identity.schoolId;
        _subjects = subjects;
        _allowances = allowances;
        _subjectId = subjects.isEmpty ? null : subjects.first.id;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your subjects and weekly allowance. Check your account and connection.';
        _loading = false;
      });
    }
  }

  AllowanceSummary? get _selectedAllowance {
    for (final item in _allowances) {
      if (item.subjectId == _subjectId) return item;
    }
    return null;
  }

  Future<void> _submit() async {
    final subjectId = _subjectId;
    final schoolId = _schoolId;
    final question = _question.text.trim();
    if (subjectId == null || schoolId == null) {
      setState(() => _error = 'No subject is available for your account.');
      return;
    }
    if (question.length < 8) {
      setState(() => _error = 'Enter a clear question with at least 8 characters.');
      return;
    }
    if (_urgent && _urgentReason.text.trim().length < 8) {
      setState(() => _error = 'Add a short reason for the urgent request.');
      return;
    }
    final allowance = _selectedAllowance;
    if (allowance != null && allowance.remainingDoubts <= 0) {
      setState(() => _error = 'You have used this subject’s weekly doubt allowance.');
      return;
    }
    if (_urgent && allowance?.urgentPassAvailable != true) {
      setState(() => _error = 'Your urgent pass for this subject has already been used this week.');
      return;
    }

    setState(() { _submitting = true; _error = null; });
    try {
      final request = await ref.read(_mentorServiceProvider).submitDoubt(
        subjectId: subjectId,
        question: question,
        idempotencyKey: const Uuid().v4(),
        chapter: _chapter.text.trim().isEmpty ? null : _chapter.text.trim(),
        questionNumber: _questionNumber.text.trim().isEmpty ? null : _questionNumber.text.trim(),
        explanation: _explanation.text.trim().isEmpty ? null : _explanation.text.trim(),
        previousAttempts: _previousAttempts.text.trim().isEmpty ? null : _previousAttempts.text.trim(),
        urgent: _urgent,
        urgentReason: _urgent ? _urgentReason.text.trim() : null,
      );
      if (!mounted) return;
      context.go('/mentor-desk/doubt/${request.id}');
    } on MentorDeskException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not submit your doubt. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowance = _selectedAllowance;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Ask a doubt')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _subjects.isEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 12), OutlinedButton(onPressed: _load, child: const Text('Retry'))])))
              : _subjects.isEmpty
                  ? const Center(child: Text('No subjects are linked to your school account.'))
                  : ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        const Text('What do you need help with?', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppColors.ink900)),
                        const SizedBox(height: 6),
                        const Text('Give your mentor enough context to understand the problem.', style: TextStyle(fontSize: 13, color: AppColors.ink500)),
                        const SizedBox(height: 20),
                        _label('Subject'),
                        DropdownButtonFormField<String>(
                          value: _subjectId,
                          items: _subjects.map((subject) => DropdownMenuItem(value: subject.id, child: Text(subject.name))).toList(),
                          onChanged: _submitting ? null : (value) => setState(() {
                            _subjectId = value;
                            _urgent = false;
                            _error = null;
                          }),
                        ),
                        if (allowance != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13), border: Border.all(color: AppColors.ink200)),
                            child: Row(children: [
                              const Icon(Icons.info_outline_rounded, color: AppColors.accent, size: 18),
                              const SizedBox(width: 9),
                              Expanded(child: Text(
                                '${allowance.remainingDoubts} of ${allowance.weeklyDoubtAllowance} weekly doubts remaining · ${allowance.openDoubts} open',
                                style: const TextStyle(fontSize: 12, color: AppColors.ink700),
                              )),
                            ]),
                          ),
                        ],
                        const SizedBox(height: 18),
                        _label('Your question'),
                        TextField(
                          controller: _question,
                          minLines: 3,
                          maxLines: 6,
                          maxLength: 2000,
                          enabled: !_submitting,
                          decoration: const InputDecoration(hintText: 'Write the question clearly. Include the part you do not understand.'),
                        ),
                        const SizedBox(height: 14),
                        _label('Chapter or topic (optional)'),
                        TextField(controller: _chapter, enabled: !_submitting, maxLength: 120, decoration: const InputDecoration(hintText: 'Example: Laws of Motion')),
                        const SizedBox(height: 14),
                        _label('Question number (optional)'),
                        TextField(controller: _questionNumber, enabled: !_submitting, maxLength: 40, decoration: const InputDecoration(hintText: 'Example: Exercise 4.2, Q7')),
                        const SizedBox(height: 14),
                        _label('What have you tried? (optional)'),
                        TextField(controller: _explanation, enabled: !_submitting, minLines: 2, maxLines: 4, decoration: const InputDecoration(hintText: 'Explain the step where you got stuck.')),
                        const SizedBox(height: 14),
                        _label('Previous attempts (optional)'),
                        TextField(controller: _previousAttempts, enabled: !_submitting, minLines: 2, maxLines: 4, decoration: const InputDecoration(hintText: 'Add any working or method you have already tried.')),
                        const SizedBox(height: 12),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _urgent,
                          onChanged: _submitting || allowance?.urgentPassAvailable != true
                              ? null
                              : (value) => setState(() => _urgent = value ?? false),
                          title: const Text('Use this week’s urgent pass'),
                          subtitle: Text(allowance?.urgentPassAvailable == true
                              ? 'Use this only when the question needs prompt teacher attention.'
                              : 'Your urgent pass is not available for this subject this week.'),
                        ),
                        if (_urgent) ...[
                          const SizedBox(height: 8),
                          _label('Reason for urgent attention'),
                          TextField(controller: _urgentReason, enabled: !_submitting, minLines: 2, maxLines: 3, maxLength: 300, decoration: const InputDecoration(hintText: 'Explain why this cannot wait for the normal queue.')),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _submitting ? null : _submit,
                          child: _submitting
                              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Submit doubt'),
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
