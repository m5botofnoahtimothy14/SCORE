import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../models/mentor_desk_models.dart';
import '../services/mentor_desk_service.dart';

final _mentorServiceProvider = Provider((ref) => MentorDeskService(Supabase.instance.client));

class MentorAssessmentScreen extends ConsumerStatefulWidget {
  final String requestId;
  const MentorAssessmentScreen({super.key, required this.requestId});

  @override
  ConsumerState<MentorAssessmentScreen> createState() => _MentorAssessmentScreenState();
}

class _MentorAssessmentScreenState extends ConsumerState<MentorAssessmentScreen> {
  static const _scale = ['unprepared', 'developing', 'satisfactory', 'strong', 'outstanding'];
  final _privateNote = TextEditingController();
  String _preparation = 'satisfactory';
  String _engagement = 'satisfactory';
  DoubtRequest? _request;
  MentorAssessment? _existing;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _privateNote.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final identity = await ref.read(identityProviderProvider.future);
      if (identity == null || identity.tier == AppTier.student) throw Exception('Mentor access is required.');
      final service = ref.read(_mentorServiceProvider);
      final request = await service.getDoubtRequest(widget.requestId);
      if (request == null) throw Exception('Request not found.');
      final existing = await service.getMentorAssessment(widget.requestId, identity.userId);
      if (!mounted) return;
      setState(() {
        _request = request;
        _existing = existing;
        if (existing != null) {
          _preparation = existing.preparation;
          _engagement = existing.engagement;
          _privateNote.text = existing.privateNote ?? '';
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = 'Could not load the private assessment. Check your access.'; _loading = false; });
    }
  }

  Future<void> _submit() async {
    if (_request == null) return;
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(_mentorServiceProvider).submitMentorAssessment(
        requestId: widget.requestId,
        preparation: _preparation,
        engagement: _engagement,
        privateNote: _privateNote.text.trim().isEmpty ? null : _privateNote.text.trim(),
      );
      await _load();
    } on MentorDeskException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save the assessment.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = _request;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Private mentor assessment')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : request == null
              ? Center(child: Text(_error ?? 'Request not found.'))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: AppColors.ink200)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Student request', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.accent)),
                        const SizedBox(height: 8),
                        Text(request.question, style: const TextStyle(fontSize: 14, height: 1.45, fontWeight: FontWeight.w700, color: AppColors.ink900)),
                        const SizedBox(height: 6),
                        Text(request.statusLabel, style: const TextStyle(fontSize: 11, color: AppColors.ink500)),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    const Text('Preparation', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 7),
                    DropdownButtonFormField<String>(
                      value: _preparation,
                      items: _scale.map((value) => DropdownMenuItem(value: value, child: Text(_label(value)))).toList(),
                      onChanged: _saving ? null : (value) => setState(() => _preparation = value ?? _preparation),
                    ),
                    const SizedBox(height: 18),
                    const Text('Engagement', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 7),
                    DropdownButtonFormField<String>(
                      value: _engagement,
                      items: _scale.map((value) => DropdownMenuItem(value: value, child: Text(_label(value)))).toList(),
                      onChanged: _saving ? null : (value) => setState(() => _engagement = value ?? _engagement),
                    ),
                    const SizedBox(height: 18),
                    const Text('Private note', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 7),
                    TextField(controller: _privateNote, minLines: 3, maxLines: 6, maxLength: 2000, decoration: const InputDecoration(hintText: 'Visible only to authorised mentor and leadership roles.')),
                    if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12))),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: _saving ? null : _submit,
                      child: _saving ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(_existing == null ? 'Save assessment' : 'Update assessment'),
                    ),
                  ],
                ),
    );
  }

  static String _label(String value) => value[0].toUpperCase() + value.substring(1);
}
