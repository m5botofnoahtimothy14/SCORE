import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/ai_ask_service.dart';

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
    setState(() {
      _loadingContext = true;
      _error = null;
    });
    try {
      final context = await _service.loadContext();
      if (!mounted) return;
      setState(() {
        _context = context;
        _subject = context.subjects.first;
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
    setState(() {
      _submitting = true;
      _response = null;
      _error = null;
    });
    try {
      final answer = await _service.ask(subject: subject, question: question);
      if (mounted) setState(() => _response = answer);
    } on AiAskException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('AI Ask')),
      body: SafeArea(
        child: _loadingContext
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(20), children: [
                Text('Learn from approved material',
                    style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                    'Answers are grounded in teacher-approved curriculum material for your enrolled subject. Check the sources and ask your teacher when you need more help.',
                    style: theme.textTheme.bodyMedium),
                const SizedBox(height: 20),
                if (_context != null) ...[
                  DropdownButtonFormField<String>(
                    value: _subject,
                    decoration: const InputDecoration(
                        labelText: 'Subject', border: OutlineInputBorder()),
                    items: _context!.subjects
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(growable: false),
                    onChanged: _submitting
                        ? null
                        : (value) => setState(() => _subject = value),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _questionController,
                    minLines: 5,
                    maxLines: 9,
                    maxLength: 2000,
                    enabled: !_submitting,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                        alignLabelWithHint: true,
                        labelText: 'What would you like help with?',
                        hintText:
                            'Example: Explain why a balanced equation follows conservation of mass.',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _submitting ? null : _ask,
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_awesome_outlined),
                    label: Text(
                        _submitting ? 'Finding approved sources…' : 'Ask AI'),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 18),
                  _NoticeCard(
                      icon: Icons.info_outline,
                      title: 'AI Ask needs attention',
                      body: _error!.message,
                      actionLabel: _error!.retryable || _context == null
                          ? 'Try again'
                          : null,
                      onAction: _context == null ? _loadContext : _ask),
                ],
                if (_response != null) ...[
                  const SizedBox(height: 22),
                  _AnswerCard(response: _response!)
                ],
                const SizedBox(height: 22),
                const _NoticeCard(
                    icon: Icons.school_outlined,
                    title: 'A supplement, not a replacement for your teacher',
                    body:
                        'AI Ask does not provide exam answers or official school advice. If an answer is uncertain, incomplete, or does not match your classwork, ask your teacher.'),
              ]),
      ),
    );
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.response});
  final AiAskResponse response;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
        child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(response.isUncertain
              ? Icons.help_outline
              : Icons.verified_outlined),
          const SizedBox(width: 8),
          Text(response.isUncertain ? 'Needs teacher review' : 'Answer',
              style: theme.textTheme.titleMedium),
          const Spacer(),
          if (response.cached)
            const Tooltip(
                message: 'Previously prepared answer',
                child: Icon(Icons.history, size: 18))
        ]),
        const SizedBox(height: 12),
        Text(response.answer,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.55)),
        if (response.citations.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text('Approved sources', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final citation in response.citations)
            Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.menu_book_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(citation.label,
                              style: theme.textTheme.bodySmall))
                    ])),
        ],
        if (response.remaining != null) ...[
          const SizedBox(height: 12),
          Text(
              '${response.remaining} AI Ask request${response.remaining == 1 ? '' : 's'} remaining this ${response.resetPeriod ?? 'period'}.',
              style: theme.textTheme.bodySmall)
        ],
      ]),
    ));
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard(
      {required this.icon,
      required this.title,
      required this.body,
      this.actionLabel,
      this.onAction});
  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(body),
                    if (actionLabel != null && onAction != null)
                      TextButton(onPressed: onAction, child: Text(actionLabel!))
                  ])),
            ])),
      );
}
