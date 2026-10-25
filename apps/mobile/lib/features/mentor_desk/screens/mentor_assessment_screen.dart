import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mentor_desk_design.dart';
import '../../../core/layout/responsive.dart';
import '../../../core/models/models.dart';
import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/widgets/states.dart';
import '../../mentor_desk/models/mentor_desk_models.dart';
import '../../mentor_desk/services/mentor_desk_service.dart';

final _serviceProvider = Provider<MentorDeskService>(
  (ref) => MentorDeskService(Supabase.instance.client),
);

const _scaleLabels = <String, String>{
  'unprepared': 'Unprepared',
  'needs_improvement': 'Needs improvement',
  'satisfactory': 'Satisfactory',
  'good': 'Good',
  'outstanding': 'Outstanding',
};

/// Mentor's private assessment of the student after closing a request.
/// Never visible to the student. Only the mentor + admins can see it.
class MentorAssessmentScreen extends ConsumerStatefulWidget {
  final String requestId;
  const MentorAssessmentScreen({super.key, required this.requestId});

  @override
  ConsumerState<MentorAssessmentScreen> createState() => _MentorAssessmentScreenState();
}

class _MentorAssessmentScreenState extends ConsumerState<MentorAssessmentScreen> {
  String? _preparation;
  String? _engagement;
  final _noteCtrl = TextEditingController();
  bool _submitting = false;
  bool _loading = true;
  String? _error;
  MentorAssessment? _existing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final identity = await ref.read(identityProvider.future);
    final service = ref.read(_serviceProvider);
    final existing = await service.getMentorAssessment(widget.requestId, identity.userId);
    if (!mounted) return;
    setState(() {
      _existing = existing;
      _loading = false;
      if (existing != null) {
        _preparation = existing.preparation;
        _engagement = existing.engagement;
        _noteCtrl.text = existing.privateNote ?? '';
      }
    });
  }

  Future<void> _submit() async {
    if (_preparation == null || _engagement == null) {
      setState(() => _error = 'Rate preparation and engagement.');
      return;
    }
    setState(() { _submitting = true; _error = null; });
    try {
      await ref.read(_serviceProvider).submitMentorAssessment(
            requestId: widget.requestId,
            preparation: _preparation!,
            engagement: _engagement!,
            privateNote: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Assessment saved (private).')));
      context.pop();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() { _submitting = false; _error = e.toString(); });
    }
  }

  Widget _scalePicker(String label, String? value, void Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: kGutter / 2),
        Wrap(
          spacing: kGutter / 2,
          runSpacing: kGutter / 2,
          children: _scaleLabels.entries.map((e) {
            final selected = value == e.key;
            return ChoiceChip(
              label: Text(e.value),
              selected: selected,
              onSelected: selected ? null : (s) => onChanged(s ? e.key : null),
              selectedColor: MDTier.teacher.soft,
              labelStyle: TextStyle(color: selected ? MDTier.teacher.solid : MDColors.ink600, fontWeight: selected ? FontWeight.w700 : FontWeight.normal),
              backgroundColor: MDColors.ink100.withValues(alpha: 0.4),
              side: BorderSide(color: selected ? MDTier.teacher.solid : MDColors.ink200.withValues(alpha: 0.3)),
            );
          }).toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const accent = MDTier.teacher;
    return Scaffold(
      backgroundColor: MDColors.ink50,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, title: const Text('Student assessment (private)')),
      body: _loading
          ? const LoadingView()
          : AdaptivePage(
              maxWidth: 600,
              child: ListView(
                padding: const EdgeInsets.all(kGutter * 1.5),
                children: [
                  const Text('Assess the student\'s preparation and engagement for this request.', style: TextStyle(fontSize: 15)),
                  const SizedBox(height: kGutter / 2),
                  const Text('This assessment is private — the student will never see it.', style: TextStyle(fontSize: 12, color: MDColors.ink600, fontStyle: FontStyle.italic)),
                  const SizedBox(height: kGutter * 2),
                  _scalePicker('Preparation', _preparation, (v) => setState(() => _preparation = v)),
                  const SizedBox(height: kGutter * 2),
                  _scalePicker('Engagement', _engagement, (v) => setState(() => _engagement = v)),
                  const SizedBox(height: kGutter * 2),
                  const Text('Private note (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: kGutter / 2),
                  TextField(
                    controller: _noteCtrl,
                    maxLines: 4,
                    decoration: InputDecoration(hintText: 'Notes only you and admins can see', border: OutlineInputBorder(borderRadius: BorderRadius.circular(kRadiusSm))),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: kGutter),
                    Text(_error!, style: const TextStyle(color: MDColors.danger, fontSize: 13)),
                  ],
                  const SizedBox(height: kGutter * 2),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: MDGlossButton(
                      onPressed: _submitting || _preparation == null || _engagement == null ? null : _submit,
                      child: _submitting
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(_existing == null ? 'Save assessment' : 'Update assessment'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
