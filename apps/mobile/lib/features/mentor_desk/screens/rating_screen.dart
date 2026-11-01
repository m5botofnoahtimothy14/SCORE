import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../models/mentor_desk_models.dart';
import '../services/mentor_desk_service.dart';

final _mentorServiceProvider = Provider((ref) => MentorDeskService(Supabase.instance.client));

class RatingScreen extends ConsumerStatefulWidget {
  final String requestId;
  const RatingScreen({super.key, required this.requestId});

  @override
  ConsumerState<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends ConsumerState<RatingScreen> {
  final _comment = TextEditingController();
  DoubtRequest? _request;
  int _rating = 5;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _alreadyRated = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final identity = await ref.read(identityProviderProvider.future);
      if (identity == null || identity.tier != AppTier.student) throw Exception('Student access is required.');
      final service = ref.read(_mentorServiceProvider);
      final request = await service.getDoubtRequest(widget.requestId);
      if (request == null) throw Exception('Request not found.');
      final ratings = await service.listRatingsForRequest(widget.requestId);
      final existing = ratings.where((item) => item.studentId == identity.userId).toList();
      if (!mounted) return;
      setState(() {
        _request = request;
        _alreadyRated = existing.isNotEmpty;
        if (existing.isNotEmpty) {
          _rating = existing.first.rating;
          _comment.text = existing.first.comment ?? '';
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = 'Could not load this rating form.'; _loading = false; });
    }
  }

  Future<void> _submit() async {
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(_mentorServiceProvider).submitRating(
        requestId: widget.requestId,
        rating: _rating,
        comment: _comment.text.trim().isEmpty ? null : _comment.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thank you. Your rating was saved.')));
      Navigator.of(context).pop();
    } on MentorDeskException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not submit your rating.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Rate mentor support')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _request == null
              ? Center(child: Text(_error ?? 'Request not found.'))
              : ListView(
                  padding: const EdgeInsets.all(22),
                  children: [
                    const Icon(Icons.star_rate_rounded, size: 48, color: AppColors.warning),
                    const SizedBox(height: 12),
                    const Text('How helpful was the support?', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink900)),
                    const SizedBox(height: 8),
                    Text(_request!.question, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.ink500)),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) => IconButton(
                        onPressed: _saving || _alreadyRated ? null : () => setState(() => _rating = index + 1),
                        iconSize: 34,
                        icon: Icon(index < _rating ? Icons.star_rounded : Icons.star_outline_rounded, color: AppColors.warning),
                      )),
                    ),
                    Center(child: Text('$_rating out of 5', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.ink600))),
                    const SizedBox(height: 22),
                    const Text('Comment (optional)', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    TextField(controller: _comment, minLines: 3, maxLines: 5, maxLength: 1000, enabled: !_alreadyRated, decoration: const InputDecoration(hintText: 'Share what helped you or what could improve.')),
                    if (_alreadyRated) const Text('You have already rated this request.', style: TextStyle(color: AppColors.ink500, fontSize: 12)),
                    if (!_request!.isClosed) const Text('You can rate this request after it is closed.', style: TextStyle(color: AppColors.ink500, fontSize: 12)),
                    if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12))),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: _saving || _alreadyRated || !_request!.isClosed ? null : _submit,
                      child: _saving ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Submit rating'),
                    ),
                  ],
                ),
    );
  }
}
