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

class MentorAssessmentScreen extends ConsumerStatefulWidget {
  final String requestId;
  const MentorAssessmentScreen({super.key, required this.requestId});

  @override
  ConsumerState<MentorAssessmentScreen> createState() => _MentorAssessmentScreenState();
}

class _MentorAssessmentScreenState extends ConsumerState<MentorAssessmentScreen> {
  String? _preparation;
  String? _engagement;
  final _privateNoteController = TextEditingController();
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  String? _myUserId;

  static const List<String> _scales = ['unprepared', 'developing', 'satisfactory', 'strong', 'outstanding'];
  static const Map<String, String> _scaleLabels = {
    'unprepared': 'Unprepared',
    'developing': 'Developing',
    'satisfactory': 'Satisfactory',
    'strong': 'Strong',
    'outstanding': 'Outstanding',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _privateNoteController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final identity = await ref.read(identityProviderProvider.future);
      _myUserId = identity?.userId;
      final service = ref.read(mentorDeskServiceProvider);
      final existing = await service.getMentorAssessment(widget.requestId, _myUserId ?? '');
      if (existing != null && mounted) {
        _preparation = existing.preparation;
        _engagement = existing.engagement;
        _privateNoteController.text = existing.privateNote ?? '';
      }
      if (!mounted) return;
      setState(() { _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _submit() async {
    if (_preparation == null || _engagement == null) {
      setState(() { _error = 'Please rate both preparation and engagement.'; });
      return;
    }
    setState(() { _submitting = true; _error = null; });
    try {
      final service = ref.read(mentorDeskServiceProvider);
      await service.submitMentorAssessment(
        requestId: widget.requestId,
        preparation: _preparation!,
        engagement: _engagement!,
        privateNote: _privateNoteController.text.trim().isEmpty ? null : _privateNoteController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Assessment saved (private).'),
        backgroundColor: MDColors.success,
        duration: Duration(seconds: 4),
      ));
      context.pop();
    } on MentorDeskException catch (e) {
      if (!mounted) return;
      setState(() { _submitting = false; _error = e.message; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _submitting = false; _error = e.toString(); });
    }
  }

  Widget _scalePicker(String key, String title, String? value, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MDColors.ink700)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _scales.map((s) {
            final selected = value == s;
            return ChoiceChip(
              label: Text(_scaleLabels[s]!),
              selected: selected,
              onSelected: (v) => onChanged(v ? s : null),
              selectedColor: MDColors.teacherTier.withValues(alpha: 0.15),
              checkmarkColor: MDColors.teacherTier,
              backgroundColor: MDColors.ink50,
              labelStyle: TextStyle(
                fontWeight: FontWeight.w700,
                color: selected ? MDColors.teacherTier : MDColors.ink700,
              ),
              side: BorderSide(
                color: selected ? MDColors.teacherTier : MDColors.ink300,
                width: selected ? 2 : 1,
              ),
            );
          }).toList(),
        ),
      ],
    );
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
        title: const Text('Student Assessment (Private)', style: TextStyle(color: MDColors.ink900, fontWeight: FontWeight.w800)),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: MDColors.teacherTier.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(kRadiusLg),
                          border: Border.all(color: MDColors.teacherTier.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.assignment, color: MDColors.teacherTier, size: 24),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text('Private Assessment',
                                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: MDColors.ink900)),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: MDColors.teacherTier,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text('PRIVATE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'This assessment is visible only to you and authorised administrators. It is never shown to the student.',
                              style: TextStyle(fontSize: 13, color: MDColors.ink600),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _scalePicker('preparation', 'Student Preparation', _preparation, (v) => setState(() { _preparation = v; })),
                      const SizedBox(height: 24),
                      _scalePicker('engagement', 'Student Engagement', _engagement, (v) => setState(() { _engagement = v; })),
                      const SizedBox(height: 24),
                      MDGlossInput(
                        controller: _privateNoteController,
                        label: 'Private Note (optional)',
                        hint: 'Notes only you and admins can see…',
                        maxLines: 4,
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        child: MDButton(
                          onPressed: _submitting ? null : _submit,
                          loading: _submitting,
                          child: const Text('Save Assessment', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}


