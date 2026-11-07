import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/ai_ask_service.dart';
import '../../../core/design/design_system.dart';
import '../../../core/widgets/premium_card.dart';
import '../../../core/widgets/premium_states.dart';

class AiAskScreen extends StatefulWidget {
  const AiAskScreen({super.key});

  @override
  State<AiAskScreen> createState() => _AiAskScreenState();
}

class _AiAskScreenState extends State<AiAskScreen> {
  final _questionController = TextEditingController();
  late final AiAskService _service;
  AiAskContext? _context;
  AiAskResponse? _response;
  AiAskException? _error;
  String? _subject;
  bool _loadingContext = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _service = AiAskService(Supabase.instance.client);
    _loadContext();
  }

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  Future<void> _loadContext() async {
    setState(() { _loadingContext = true; _error = null; });
    try {
      final context = await _service.loadContext();
      if (!mounted) return;
      // Ensure default subjects are available if context has none
      final subjects = context.subjects.isNotEmpty
          ? context.subjects
          : ['Mathematics', 'Physics', 'Chemistry', 'Biology'];
      setState(() {
        _context = AiAskContext(grade: context.grade, subjects: subjects);
        _subject = subjects.isNotEmpty ? subjects.first : null;
      });
    } on AiAskException catch (error) {
      if (mounted) setState(() => _error = error);
    } catch (_) {
      if (mounted)
        setState(() => _error = const AiAskException('context_unavailable',
            'AI Ask could not load your learning subjects.'));
    } finally {
      if (mounted) setState(() => _loadingContext = false);
    }
  }

  Future<void> _ask() async {
    final question = _questionController.text.trim();
    final subject = _subject;
    if (question.isEmpty || subject == null || _submitting) return;
    setState(() { _submitting = true; _response = null; _error = null; });
    try {
      final answer = await _service.ask(subject: subject, question: question);
      if (mounted) setState(() => _response = answer);
    } on AiAskException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally { if (mounted) setState(() => _submitting = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SColor.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        title: const Text('AI Assistant', style: TextStyle(color: SColor.primaryText, fontWeight: FontWeight.w800)),
        centerTitle: false,
      ),
      body: SafeArea(
        child: _loadingContext
            ? const PremiumLoading()
            : SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(SLayout.gutter(context), 16, SLayout.gutter(context), 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ask your AI tutor', style: STextStyle.displayLarge.copyWith(fontSize: 26)),
                    const SizedBox(height: SSpace.sm),
                    Text('Answers are grounded in teacher-approved curriculum material for your enrolled subject. When the material is insufficient, the assistant will tell you and suggest asking your teacher.',
                        style: STextStyle.bodyMedium.copyWith(color: SColor.secondaryText, height: 1.6)),
                    const SizedBox(height: SSpace.lg),
                    if (_context != null) ...[
                      PremiumDropdown<String>(
                        label: 'Subject',
                        value: _subject,
                        items: _context!.subjects.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(growable: false),
                        onChanged: _submitting ? null : (value) => setState(() => _subject = value),
                      ),
                      const SizedBox(height: SSpace.md),
                      PremiumInput(
                        controller: _questionController,
                        label: 'Your question',
                        hint: 'Example: Explain why a balanced equation follows conservation of mass.',
                        maxLines: 5,
                        keyboardType: TextInputType.multiline,
                        onSubmitted: _submitting ? null : (_) => _ask(),
                      ),
                      const SizedBox(height: SSpace.md),
                      SizedBox(width: double.infinity, child: PremiumPrimaryButton(
                        onPressed: _submitting ? null : _ask,
                        child: _submitting ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: SColor.textInverse)) : const Text('Ask AI'),
                      )),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: SSpace.lg),
                      PremiumCard(
                        padding: const EdgeInsets.all(SSpace.md),
                        child: Row(children: [
                          const Icon(Icons.info_outline, color: SColor.error, size: 22),
                          const SizedBox(width: SSpace.md),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('AI Ask needs attention', style: STextStyle.headingSmall.copyWith(fontWeight: FontWeight.w800, color: SColor.error)),
                            const SizedBox(height: SSpace.xs),
                            Text(_error!.message, style: STextStyle.bodyMedium.copyWith(color: SColor.secondaryText)),
                          ])),
                          if (_error?.retryable == true || _context == null)
                            PremiumTextButton(onPressed: _context == null ? _loadContext : _ask, child: const Text('Try again')),
                        ]),
                      ),
                    ],
                    if (_response != null) ...[
                      const SizedBox(height: SSpace.lg),
                      _AnswerCard(response: _response!),
                    ],
                    const SizedBox(height: SSpace.lg),
                    PremiumCard(
                      padding: const EdgeInsets.all(SSpace.md),
                      child: Row(children: [
                        Icon(Icons.school_outlined, color: SColor.info, size: 22),
                        const SizedBox(width: SSpace.md),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('A supplement, not a replacement for your teacher', style: STextStyle.headingSmall.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: SSpace.xs),
                          Text('AI Ask does not provide exam answers or official school advice. If an answer is uncertain or incomplete, ask your teacher.',
                              style: STextStyle.bodyMedium.copyWith(color: SColor.secondaryText)),
                        ])),
                      ]),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _AnswerCard extends StatelessWidget {
  final AiAskResponse response;
  const _AnswerCard({required this.response});

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(response.isUncertain ? Icons.help_outline : Icons.verified_outlined, color: response.isUncertain ? SColor.warning : SColor.success),
          const SizedBox(width: SSpace.sm),
          Text(response.isUncertain ? 'Needs teacher review' : 'Answer', style: STextStyle.headingMedium.copyWith(fontWeight: FontWeight.w800)),
          const Spacer(),
          if (response.cached) const Tooltip(message: 'Previously prepared answer', child: Icon(Icons.history, size: 18, color: SColor.textMuted)),
        ]),
        const SizedBox(height: SSpace.md),
        Text(response.answer, style: STextStyle.bodyLarge.copyWith(height: 1.6)),
        if (response.citations.isNotEmpty) ...[
          const SizedBox(height: SSpace.md),
          Text('Approved sources', style: STextStyle.headingSmall.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: SSpace.sm),
          ...response.citations.map((c) => Padding(
            padding: const EdgeInsets.only(bottom: SSpace.xs),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.menu_book_outlined, size: 18, color: SColor.textMuted),
              const SizedBox(width: SSpace.sm),
              Expanded(child: Text(c.label, style: STextStyle.bodyMedium.copyWith(color: SColor.secondaryText))),
            ]),
          )),
        ],
        if (response.remaining != null) ...[
          const SizedBox(height: SSpace.md),
          Text('${response.remaining} AI Ask request${response.remaining == 1 ? '' : 's'} remaining this ${response.resetPeriod ?? 'period'}.',
              style: STextStyle.captionMuted),
        ],
      ]),
    );
  }
}
