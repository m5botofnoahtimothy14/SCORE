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

class RatingScreen extends ConsumerStatefulWidget {
  final String requestId;
  const RatingScreen({super.key, required this.requestId});

  @override
  ConsumerState<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends ConsumerState<RatingScreen> {
  int _rating = 0;
  final _commentController = TextEditingController();
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  bool _alreadyRated = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final service = ref.read(mentorDeskServiceProvider);
      final ratings = await service.listRatingsForRequest(widget.requestId);
      if (!mounted) return;
      setState(() {
        _alreadyRated = ratings.isNotEmpty;
        if (_alreadyRated) {
          _rating = ratings.first.rating;
          _commentController.text = ratings.first.comment ?? '';
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      setState(() { _error = 'Please select a rating.'; });
      return;
    }
    setState(() { _submitting = true; _error = null; });
    try {
      final service = ref.read(mentorDeskServiceProvider);
      await service.submitRating(
        requestId: widget.requestId,
        rating: _rating,
        comment: _commentController.text.trim().isEmpty ? null : _commentController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Thank you for your feedback!'),
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
        title: const Text('Rate This Support', style: TextStyle(color: MDColors.ink900, fontWeight: FontWeight.w800)),
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
                      if (_alreadyRated)
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: MDColors.success.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(kRadiusLg),
                            border: Border.all(color: MDColors.success.withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.check_circle, color: MDColors.success, size: 24),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text('You have already rated this request.',
                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: MDColors.ink900)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text('Rating: ${'★' * _rating}${'☆' * (5 - _rating)}',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: MDColors.warning)),
                              if (_commentController.text.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(_commentController.text, style: TextStyle(fontSize: 14, color: MDColors.ink700)),
                              ],
                            ],
                          ),
                        ),
                      if (_alreadyRated) const SizedBox(height: 24),
                      Text(
                        'How would you rate this support?',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your rating helps mentors improve and is shared with your school.',
                        style: TextStyle(fontSize: 14, color: MDColors.ink600),
                      ),
                      const SizedBox(height: 24),
                      Center(
                        child: Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: List.generate(5, (i) {
                            final star = i + 1;
                            final selected = _rating >= star;
                            return GestureDetector(
                              onTap: _alreadyRated ? null : () => setState(() { _rating = star; }),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    selected ? Icons.star : Icons.star_border,
                                    size: 48,
                                    color: selected ? MDColors.warning : MDColors.ink300,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    star.toString(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: selected ? MDColors.warning : MDColors.ink500,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: 32),
                      MDGlossInput(
                        controller: _commentController,
                        label: 'Comment (optional)',
                        hint: 'What did you find helpful?…',
                        maxLines: 4,
                        errorText: null,
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        child: MDButton(
                          onPressed: _alreadyRated || _submitting ? null : _submit,
                          loading: _submitting,
                          child: const Text('Submit Rating', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}


