import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Rate this support')),
      body: _loading
          ? const LoadingView()
          : AdaptivePage(
              maxWidth: 600,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const Text('How would you rate the support you received?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final stars = i + 1;
                      return IconButton(
                        icon: Icon(stars <= _stars ? Icons.star : Icons.star_border, color: Colors.amber, size: 40),
                        onPressed: () => setState(() => _stars = stars),
                      );
                    }),
                  ),
                  const SizedBox(height: 24),
                  const Text('Comment (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _commentCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(hintText: 'Tell us what helped or what could be better', border: OutlineInputBorder()),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13)),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Submit rating'),
                    ),
                  ),
                  const Text('You can rate each request only once.', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                ],
              ),
            ),
    );
  }
}
