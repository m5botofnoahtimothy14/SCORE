import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mentor_desk_design.dart';
import '../../../core/layout/responsive.dart';
import '../../../core/widgets/states.dart';
import '../../mentor_desk/services/mentor_desk_service.dart';

final _serviceProvider = Provider<MentorDeskService>(
  (ref) => MentorDeskService(Supabase.instance.client),
);

/// Rate a closed doubt/session (1–5 stars + optional comment). One rating per request.
class RatingScreen extends ConsumerStatefulWidget {
  final String requestId;
  const RatingScreen({super.key, required this.requestId});

  @override
  ConsumerState<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends ConsumerState<RatingScreen> {
  int _stars = 0;
  final _commentCtrl = TextEditingController();
  bool _submitting = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final service = ref.read(_serviceProvider);
    final ratings = await service.listRatingsForRequest(widget.requestId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (ratings.isNotEmpty) {
        _stars = ratings.first.rating;
        _commentCtrl.text = ratings.first.comment ?? '';
      }
    });
  }

  Future<void> _submit() async {
    if (_stars < 1 || _stars > 5) {
      setState(() => _error = 'Select a rating.');
      return;
    }
    setState(() { _submitting = true; _error = null; });
    try {
      await ref.read(_serviceProvider).submitRating(
            requestId: widget.requestId,
            rating: _stars,
            comment: _commentCtrl.text.trim().isEmpty ? null : _commentCtrl.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rating submitted.')));
      context.pop();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() { _submitting = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    const tier = MDTier.student;

    return Scaffold(
      backgroundColor: MDColors.ink50,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, title: const Text('Rate this support')),
      body: _loading
          ? const LoadingView()
          : AdaptivePage(
              maxWidth: 600,
              child: ListView(
                padding: const EdgeInsets.all(kGutter * 1.5),
                children: [
                  const Text('How would you rate the support you received?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(height: kGutter),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final stars = i + 1;
                      return IconButton(
                        icon: Icon(stars <= _stars ? Icons.star : Icons.star_border, color: MDColors.warning, size: 40),
                        onPressed: () => setState(() => _stars = stars),
                      );
                    }),
                  ),
                  const SizedBox(height: kGutter * 2),
                  const Text('Comment (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: kGutter / 2),
                  TextField(
                    controller: _commentCtrl,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Tell us what helped or what could be better',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(kRadiusSm),
                        borderSide: BorderSide(color: MDColors.ink200.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(kRadiusSm),
                        borderSide: BorderSide(color: tier.solid, width: 1.6),
                      ),
                    ),
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
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Submit rating'),
                    ),
                  ),
                  const SizedBox(height: kGutter),
                  const Text('You can rate each request only once.', style: TextStyle(fontSize: 11, color: MDColors.ink500)),
                ],
              ),
            ),
    );
  }
}
