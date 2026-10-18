// Compose a notice.
//
// Teachers post to the classes they actually teach; leadership may also post
// school-wide and raise a priority alert. Every rule here (class assignment,
// school_wide, priority_alert) is re-checked server-side by the
// `publish-announcement` edge function — this screen only hides what the
// signed-in user cannot use, and always surfaces the server's own error
// string rather than flattening it into "network error".
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';

/// Categories the edge function accepts. `priority_alert` is reserved for
/// school administration, so it is only offered to leadership.
const _kCategories = <String>['general', 'academic', 'event', 'priority_alert'];

const _kPriorityCaption = 'Priority alerts are sent by school administration';

const _kClassAudience = 'class';
const _kSchoolAudience = 'school_wide';

/// One targetable class, resolved from the `classes` table.
class _ClassOption {
  final String id;
  final String name;
  const _ClassOption({required this.id, required this.name});
}

/// Classes this user may target: a teacher's own teaching assignments, or the
/// whole school for leadership.
final _classOptionsProvider = FutureProvider.autoDispose<List<_ClassOption>>((ref) async {
  final identity = await ref.watch(identityProvider.future);
  final client = Supabase.instance.client;

  final teacherClassIds = identity.classIds;
  if (identity.isTeacher && teacherClassIds.isEmpty) return const [];

  final base = client
      .from('classes')
      .select('id, name')
      .eq('school_id', identity.schoolId);
  final rows = await (identity.isTeacher
          ? base.inFilter('id', teacherClassIds).order('name')
          : base.order('name')) as List;
  final options = <_ClassOption>[];
  for (final row in rows) {
    final m = row as Map;
    final id = m['id'] as String?;
    if (id == null) continue;
    final name = (m['name'] as String?)?.trim() ?? '';
    options.add(_ClassOption(id: id, name: name.isEmpty ? id : name));
  }
  return options;
});

/// Staff-only composer for a new announcement.
class ComposeAnnouncementScreen extends ConsumerWidget {
  const ComposeAnnouncementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identityAsync = ref.watch(identityProvider);
    final identity = identityAsync.valueOrNull;

    if (identity == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('New notice')),
        body: identityAsync.hasError
            ? ErrorView(
                message: 'Could not load your profile. Try again.',
                onRetry: () => ref.invalidate(identityProvider),
              )
            : const LoadingView(),
      );
    }

    // The route is for staff only; students get a clear dead end, not a form
    // that the server would reject anyway.
    if (identity.tier == AppTier.student) {
      return Scaffold(
        appBar: AppBar(title: const Text('New notice')),
        body: const EmptyView(
          title: 'Not available',
          subtitle: 'Posting notices is for teachers and school leadership.',
          icon: Icons.lock_outline,
        ),
      );
    }

    return _ComposeForm(identity: identity);
  }
}

class _ComposeForm extends ConsumerStatefulWidget {
  final AppIdentity identity;
  const _ComposeForm({required this.identity});

  @override
  ConsumerState<_ComposeForm> createState() => _ComposeFormState();
}

class _ComposeFormState extends ConsumerState<_ComposeForm> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();

  String _category = 'general';
  String _audience = _kClassAudience;
  String? _classId;
  bool _requiresAck = false;
  bool _submitting = false;

  /// Message shown inline, plus the raw `error` string returned by the edge
  /// function so the real reason is never hidden behind a generic failure.
  String? _errorMessage;
  String? _errorCode;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  AppIdentity get identity => widget.identity;

  /// School administration may raise priority alerts and reach the whole
  /// school; teachers are limited to the classes they teach.
  bool get isAdmin => identity.tier == AppTier.leadership;

  List<String> get _audienceOptions =>
      isAdmin ? const [_kClassAudience, _kSchoolAudience] : const [_kClassAudience];

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final classes = ref.read(_classOptionsProvider).valueOrNull ?? const <_ClassOption>[];
    final classId = _classId ?? (classes.isEmpty ? null : classes.first.id);
    if (_audience == _kClassAudience && classId == null) {
      setState(() {
        _errorCode = null;
        _errorMessage = 'Choose which class should receive this notice.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _errorCode = null;
      _errorMessage = null;
    });

    try {
      final client = Supabase.instance.client;
      final res = await client.functions.invoke(
        'publish-announcement',
        body: {
          'school_id': identity.schoolId,
          'title': _titleCtrl.text.trim(),
          'body': _bodyCtrl.text.trim(),
          'category': _category,
          'audience_type': _audience,
          'class_id': _audience == _kClassAudience ? classId : null,
          'requires_ack': _requiresAck,
        },
      );

      // Non-2xx replies throw FunctionException; a 200 carrying
      // `success: false` is still a rejection.
      final data = res.data;
      if (data is Map && data['success'] == false) {
        _fail(data['error']?.toString());
        return;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notice published.')),
      );
      context.go('/announcements');
    } on FunctionException catch (e) {
      final details = e.details;
      _fail(details is Map ? details['error']?.toString() : null);
    } catch (_) {
      // Only a true transport failure lands here — a rejected publish always
      // arrives as a FunctionException carrying the server's `error` string.
      _fail(null);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _fail(String? code) {
    if (!mounted) return;
    setState(() {
      _errorCode = code;
      _errorMessage = _friendlyError(code);
    });
  }

  static String _friendlyError(String? code) => switch (code) {
        'missing_fields' => 'Add a title and a message before publishing.',
        'unauthorized' => 'Your session has expired. Sign in again to publish.',
        'forbidden' => 'Your role is not allowed to publish notices.',
        'insufficient_permissions_for_audience' =>
          'Only school leadership can send a notice to the whole school.',
        'priority_alerts_require_admin' => _kPriorityCaption,
        'not_assigned_to_class' =>
          'You are not assigned to that class, so this notice cannot target it.',
        'failed_to_create' => 'The notice could not be saved. Please try again.',
        'server_error' => 'The school server could not publish this notice. Try again.',
        null => 'The notice could not be published. Please try again.',
        _ => 'The notice could not be published.',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = TierAccent.of(identity.tier);
    final school = identity.schoolName.isEmpty ? 'your school' : identity.schoolName;
    final classesAsync = ref.watch(_classOptionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('New notice')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              GlossHero(
                accent: accent,
                eyebrow: 'New notice',
                title: 'Post an announcement',
                subtitle: isAdmin
                    ? 'Send to one class, or to everyone at $school.'
                    : 'Send a notice to the classes you teach.',
              ),
              const SizedBox(height: 18),
              if (_errorMessage != null) ...[
                _ErrorBanner(
                  message: _errorMessage!,
                  code: _errorCode,
                ),
                const SizedBox(height: 14),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(title: 'Message'),
                      TextFormField(
                        controller: _titleCtrl,
                        textInputAction: TextInputAction.next,
                        maxLength: 140,
                        decoration: const InputDecoration(
                          labelText: 'Title',
                          hintText: 'e.g. Science fair on Friday',
                        ),
                        validator: (v) => (v ?? '').trim().isEmpty ? 'Give the notice a title.' : null,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _bodyCtrl,
                        minLines: 5,
                        maxLines: 10,
                        keyboardType: TextInputType.multiline,
                        decoration: const InputDecoration(
                          labelText: 'Details',
                          alignLabelWithHint: true,
                          hintText: 'What should this class know?',
                        ),
                        validator: (v) {
                          final text = (v ?? '').trim();
                          if (text.isEmpty) return 'Write the notice message.';
                          if (text.length < 10) return 'Use at least 10 characters.';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(title: 'Category'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final c in _kCategories)
                            _Choice(
                              label: _pretty(c),
                              selected: _category == c,
                              enabled: c != 'priority_alert' || isAdmin,
                              tooltip: c == 'priority_alert' ? _kPriorityCaption : null,
                              accent: accent,
                              onTap: () => setState(() => _category = c),
                            ),
                        ],
                      ),
                      if (!isAdmin) ...[
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.lock_outline, size: 14, color: theme.textTheme.bodySmall?.color),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(_kPriorityCaption, style: theme.textTheme.bodySmall),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(title: 'Audience'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final a in _audienceOptions)
                            _Choice(
                              label: a == _kSchoolAudience ? 'Whole school' : 'One class',
                              selected: _audience == a,
                              accent: accent,
                              onTap: () => setState(() => _audience = a),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (_audience == _kSchoolAudience)
                        Text(
                          'Everyone at $school receives this notice.',
                          style: theme.textTheme.bodySmall,
                        )
                      else
                        _classPicker(classesAsync, theme, accent),
                      const Divider(height: 28),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _requiresAck,
                        onChanged: (v) => setState(() => _requiresAck = v),
                        title: Text('Require acknowledgement', style: theme.textTheme.titleMedium),
                        subtitle: Text(
                          'Recipients must confirm they have read this notice.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              ElevatedButton(
                onPressed: _submitting || classesAsync.hasError ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Publish notice'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _classPicker(AsyncValue<List<_ClassOption>> classesAsync, ThemeData theme, TierAccent accent) {
    if (classesAsync.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: LinearProgressIndicator(),
      );
    }
    if (classesAsync.hasError) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 16, color: theme.colorScheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Could not load your classes. Pull to retry.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            TextButton(
              onPressed: () => ref.invalidate(_classOptionsProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final classes = classesAsync.valueOrNull ?? const <_ClassOption>[];
    if (classes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          identity.isTeacher
              ? 'You are not assigned to a class yet, so there is nobody to notify.'
              : 'This school has no classes yet.',
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    final selected = _classId ?? classes.first.id;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: DropdownButtonFormField<String>(
        initialValue: selected,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Class'),
        items: [
          for (final c in classes)
            DropdownMenuItem(
              value: c.id,
              child: Text(c.name, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) => setState(() => _classId = v),
      ),
    );
  }
}

/// Themed choice chip used for category and audience.
class _Choice extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final String? tooltip;
  final TierAccent accent;
  final VoidCallback onTap;

  const _Choice({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
    this.enabled = true,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chip = ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: enabled ? (_) => onTap() : null,
      showCheckmark: false,
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        color: selected
            ? Colors.white
            : enabled
                ? theme.textTheme.bodyMedium?.color
                : theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
      ),
      backgroundColor: accent.soft.withValues(alpha: theme.brightness == Brightness.dark ? 0.25 : 1),
      selectedColor: accent.solid,
      side: BorderSide(
        color: selected ? accent.solid : theme.dividerColor,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    );

    if (tooltip == null || enabled) return chip;
    return Tooltip(message: tooltip!, child: chip);
  }
}

/// Inline failure banner carrying the edge function's own `error` string.
class _ErrorBanner extends StatelessWidget {
  final String message;
  final String? code;

  const _ErrorBanner({required this.message, this.code});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 20, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurface),
                ),
                if (code != null) ...[
                  const SizedBox(height: 4),
                  Text('Server said: $code', style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _pretty(String value) {
  final text = value.replaceAll('_', ' ');
  if (text.isEmpty) return text;
  return '${text[0].toUpperCase()}${text.substring(1)}';
}