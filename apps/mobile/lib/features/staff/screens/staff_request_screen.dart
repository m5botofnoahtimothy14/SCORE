// Leadership tier: propose a new teacher to the school office.
//
// Migration 00018 adds `staff_add_requests`. Leadership may INSERT and SELECT
// their own school's rows, but there is deliberately **no UPDATE policy**:
// only a principal / school_admin / platform_owner may move a request out of
// 'pending', and that is done in the web DMS. This screen therefore submits the
// proposal, tracks its status, and never tries to approve anything itself.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';

/// Roles that can actually decide a request. Everyone else only waits.
const _approverRoles = <String>{'principal', 'school_admin', 'platform_owner'};

/// Every staffing request raised at the signed-in user's school, newest first.
final _staffAddRequestsProvider = FutureProvider<List<StaffAddRequest>>((ref) async {
  final identity = await ref.watch(identityProvider.future);
  final client = Supabase.instance.client;

  final rows = await client
      .from('staff_add_requests')
      .select('id, first_name, last_name, staff_id_no, phone, email, subject, note, status, created_at')
      .eq('school_id', identity.schoolId)
      .order('created_at', ascending: false) as List;

  return rows.map((row) {
    final m = Map<String, dynamic>.from(row as Map);
    return StaffAddRequest(
      id: (m['id'] ?? '').toString(),
      firstName: (m['first_name'] ?? '').toString(),
      lastName: (m['last_name'] ?? '').toString(),
      staffIdNo: (m['staff_id_no'] ?? '').toString(),
      phone: _optText(m['phone']),
      email: _optText(m['email']),
      subject: _optText(m['subject']),
      note: _optText(m['note']),
      status: (m['status'] ?? 'pending').toString(),
      createdAt: DateTime.tryParse((m['created_at'] ?? '').toString()),
    );
  }).toList();
});

Future<void> _refreshRequests(WidgetRef ref) async {
  ref.invalidate(_staffAddRequestsProvider);
  try {
    await ref.read(_staffAddRequestsProvider.future);
  } catch (_) {
    // Surfaced by the error state on the next build.
  }
}

/// A staffing proposal awaiting an administrator's decision.
class StaffAddRequest {
  final String id;
  final String firstName;
  final String lastName;
  final String staffIdNo;
  final String? phone;
  final String? email;
  final String? subject;
  final String? note;
  final String status;
  final DateTime? createdAt;

  const StaffAddRequest({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.staffIdNo,
    required this.status,
    required this.createdAt,
    this.phone,
    this.email,
    this.subject,
    this.note,
  });

  String get fullName {
    final n = '$firstName $lastName'.trim();
    return n.isEmpty ? staffIdNo : n;
  }

  String get initial =>
      firstName.isNotEmpty ? firstName.substring(0, 1).toUpperCase() : '?';

  bool get isPending => status == 'pending';
}

/// Propose a teacher to the office and follow the request to a decision.
class StaffRequestScreen extends ConsumerWidget {
  const StaffRequestScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identityAsync = ref.watch(identityProvider);
    final identity = identityAsync.valueOrNull;

    if (identity == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Add teacher')),
        body: identityAsync.hasError
            ? ErrorView(
                message: identityAsync.error is IdentityException
                    ? (identityAsync.error! as IdentityException).message
                    : 'Could not load your profile. Try again.',
                onRetry: () => ref.invalidate(identityProvider),
              )
            : const LoadingView(),
      );
    }

    // Students never reach this surface — the office conversation is staff-only.
    if (identity.tier == AppTier.student) {
      return Scaffold(
        appBar: AppBar(title: const Text('Add teacher')),
        body: const EmptyView(
          title: 'Not available',
          subtitle: 'Only teachers and school leadership can propose new staff.',
          icon: Icons.lock_outline,
        ),
      );
    }

    return _StaffRequestForm(identity: identity);
  }
}

class _StaffRequestForm extends ConsumerStatefulWidget {
  final AppIdentity identity;
  const _StaffRequestForm({required this.identity});

  @override
  ConsumerState<_StaffRequestForm> createState() => _StaffRequestFormState();
}

class _StaffRequestFormState extends ConsumerState<_StaffRequestForm> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _staffIdCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  bool _submitting = false;
  String? _submittedName;
  String? _errorMessage;
  String? _errorCode;

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _staffIdCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _subjectCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  AppIdentity get identity => widget.identity;

  /// True when the signed-in user is one of the roles that decides requests.
  bool get _isApprover => _approverRoles.contains(identity.role);

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _errorMessage = null;
      _errorCode = null;
    });

    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    final staffIdNo = _staffIdCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final subject = _subjectCtrl.text.trim();
    final note = _noteCtrl.text.trim();

    try {
      await Supabase.instance.client.from('staff_add_requests').insert({
        'school_id': identity.schoolId,
        'requested_by': identity.userId,
        'first_name': firstName,
        'last_name': lastName,
        'staff_id_no': staffIdNo,
        'status': 'pending',
        if (phone.isNotEmpty) 'phone': phone,
        if (email.isNotEmpty) 'email': email,
        if (subject.isNotEmpty) 'subject': subject,
        if (note.isNotEmpty) 'note': note,
      });

      ref.invalidate(_staffAddRequestsProvider);
      _formKey.currentState?.reset();
      _firstNameCtrl.clear();
      _lastNameCtrl.clear();
      _staffIdCtrl.clear();
      _phoneCtrl.clear();
      _emailCtrl.clear();
      _subjectCtrl.clear();
      _noteCtrl.clear();

      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submittedName = '$firstName $lastName'.trim();
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorCode = e.code;
        _errorMessage = _describeRequestError(e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMessage = 'Could not reach the school server. Please try again.';
      });
    }
  }

  /// Keeps the server's own reason visible instead of flattening every
  /// rejection into a generic failure.
  static String _describeRequestError(PostgrestException e) {
    final raw = e.message.trim();
    final lower = raw.toLowerCase();
    if (e.code == '23505' || lower.contains('duplicate key')) {
      return 'That Staff ID already has a request.';
    }
    if (lower.contains('insufficient_permissions')) {
      return 'Your role cannot raise staffing requests. Ask a principal or school admin.';
    }
    if (lower.contains('row-level security')) {
      return 'Your role cannot raise staffing requests at this school.';
    }
    if (lower.contains('not_authenticated')) {
      return 'Your session has expired. Sign in again to send a request.';
    }
    if (raw.isNotEmpty && raw.length <= 160) return raw;
    return 'The request could not be sent. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = TierAccent.of(identity.tier);
    final requestsAsync = ref.watch(_staffAddRequestsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Add teacher')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _refreshRequests(ref),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              GlossHero(
                accent: accent,
                eyebrow: 'Staffing request',
                title: 'Propose a teacher',
                subtitle: identity.schoolName.isEmpty
                    ? 'Send the office a candidate and track their approval.'
                    : 'Send ${identity.schoolName} a candidate and track their approval.',
              ),
              const SizedBox(height: 16),
              if (_submittedName != null) ...[
                _SuccessCard(
                  name: _submittedName!,
                  onDismiss: () => setState(() => _submittedName = null),
                ),
                const SizedBox(height: 14),
              ],
              if (_errorMessage != null) ...[
                _ErrorBanner(message: _errorMessage!, code: _errorCode),
                const SizedBox(height: 14),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeader(title: 'Candidate'),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _firstNameCtrl,
                                textInputAction: TextInputAction.next,
                                textCapitalization: TextCapitalization.words,
                                decoration: const InputDecoration(labelText: 'First name'),
                                validator: _required('Enter a first name.'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: _lastNameCtrl,
                                textInputAction: TextInputAction.next,
                                textCapitalization: TextCapitalization.words,
                                decoration: const InputDecoration(labelText: 'Last name'),
                                validator: _required('Enter a last name.'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _staffIdCtrl,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Staff ID',
                            hintText: 'e.g. T-1042',
                            helperText: 'Must be unique at your school.',
                          ),
                          validator: _required('Enter the staff ID used by the office.'),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _phoneCtrl,
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(labelText: 'Phone'),
                                validator: (v) {
                                  final t = (v ?? '').trim();
                                  if (t.isEmpty) return null;
                                  if (t.replaceAll(RegExp(r'[0-9+\-\s]'), '').isNotEmpty) {
                                    return 'Use digits, spaces or + only.';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: _emailCtrl,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(labelText: 'Email'),
                                validator: (v) {
                                  final t = (v ?? '').trim();
                                  if (t.isEmpty) return null;
                                  if (!t.contains('@') || !t.contains('.')) {
                                    return 'Enter a valid email.';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _subjectCtrl,
                          textInputAction: TextInputAction.next,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Subject (optional)',
                            hintText: 'e.g. Mathematics',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _noteCtrl,
                          minLines: 3,
                          maxLines: 6,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Note for the office (optional)',
                            alignLabelWithHint: true,
                            hintText: 'Why does this person belong on the staff?',
                          ),
                        ),
                        const SizedBox(height: 18),
                        ElevatedButton(
                          onPressed: _submitting ? null : _submit,
                          child: _submitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Send request'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _ApprovalNotice(isApprover: _isApprover),
              const SizedBox(height: 20),
              SectionHeader(
                title: 'Requests',
                actionLabel: requestsAsync.hasValue
                    ? '${requestsAsync.requireValue.length} total'
                    : null,
              ),
              requestsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: LoadingView(message: 'Loading requests...'),
                ),
                error: (e, _) => SizedBox(
                  height: 200,
                  child: ErrorView(
                    message: e is PostgrestException
                        ? _describeRequestError(e)
                        : 'Could not load staffing requests.',
                    onRetry: () => ref.invalidate(_staffAddRequestsProvider),
                  ),
                ),
                data: (requests) {
                  if (requests.isEmpty) {
                    return const SizedBox(
                      height: 200,
                      child: EmptyView(
                        title: 'No requests yet',
                        subtitle: 'Propose a teacher above and the office will see it here.',
                        icon: Icons.person_add_alt_outlined,
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final r in requests) ...[
                        _RequestCard(request: r),
                        const SizedBox(height: 10),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Requests are decided by the school office. Nothing here grants access on its own.',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared validator for the fields the database marks NOT NULL.
FormFieldValidator<String> _required(String message) =>
    (value) => (value ?? '').trim().isEmpty ? message : null;

String? _optText(Object? value) {
  final text = (value ?? '').toString().trim();
  return text.isEmpty ? null : text;
}

/// Explains who actually decides the request — the app never approves.
class _ApprovalNotice extends StatelessWidget {
  final bool isApprover;
  const _ApprovalNotice({required this.isApprover});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = TierAccent.of(AppTier.leadership);
    final heading = isApprover ? 'Decided in the web DMS' : 'Awaiting administrator approval';
    final body = isApprover
        ? 'You hold an approving role. Approve or reject this request from the web '
            'admin console — this screen only tracks the decision.'
        : 'Only a principal, school admin or platform owner can approve this. It '
            'stays "Pending" until the office decides, and you can check back here.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.soft.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.25 : 1,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.solid.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isApprover ? Icons.verified_user_outlined : Icons.hourglass_top,
              size: 20, color: accent.onSoft),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  heading,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700, color: accent.onSoft),
                ),
                const SizedBox(height: 4),
                Text(body, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Confirmation that the proposal landed and what happens next.
class _SuccessCard extends StatelessWidget {
  final String name;
  final VoidCallback onDismiss;
  const _SuccessCard({required this.name, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline, size: 22, color: AppColors.success),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Request sent for $name',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurface),
                ),
                const SizedBox(height: 4),
                Text(
                  'It is now with the school office. An administrator has to approve it '
                  'before this person becomes staff — you will see the status below change.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: onDismiss,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  child: const Text('Propose another'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One request as a card, with its decision (or lack of one).
class _RequestCard extends StatelessWidget {
  final StaffAddRequest request;
  const _RequestCard({required this.request});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = TierAccent.of(AppTier.leadership);
    final (fg, bg) = switch (request.status) {
      'approved' => (AppColors.success, AppColors.success.withValues(alpha: 0.10)),
      'rejected' => (AppColors.danger, AppColors.danger.withValues(alpha: 0.10)),
      _ => (AppColors.warning, AppColors.warning.withValues(alpha: 0.12)),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 21,
                  backgroundColor: accent.soft,
                  child: Text(
                    request.initial,
                    style: TextStyle(color: accent.onSoft, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(request.fullName, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        '${request.staffIdNo} · ${_formatStamp(request.createdAt)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                _Pill(
                  label: _prettyStatus(request.status),
                  fg: fg,
                  bg: bg,
                ),
              ],
            ),
            if (request.subject != null || request.phone != null || request.email != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (request.subject != null)
                    _Pill(
                      label: request.subject!,
                      fg: theme.colorScheme.onSurfaceVariant,
                      bg: theme.colorScheme.surfaceContainerHighest,
                    ),
                  if (request.phone != null)
                    _Pill(
                      label: request.phone!,
                      fg: theme.colorScheme.onSurfaceVariant,
                      bg: theme.colorScheme.surfaceContainerHighest,
                    ),
                  if (request.email != null)
                    _Pill(
                      label: request.email!,
                      fg: theme.colorScheme.onSurfaceVariant,
                      bg: theme.colorScheme.surfaceContainerHighest,
                    ),
                ],
              ),
            ],
            if (request.note != null) ...[
              const SizedBox(height: 10),
              Text(request.note!, style: theme.textTheme.bodySmall),
            ],
            if (request.isPending) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.schedule, size: 14, color: theme.textTheme.bodySmall?.color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Awaiting administrator approval',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color fg;
  final Color bg;
  const _Pill({required this.label, required this.fg, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9)),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}

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
                if (code != null && code!.isNotEmpty) ...[
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

String _prettyStatus(String status) => switch (status) {
      'approved' => 'Approved',
      'rejected' => 'Rejected',
      _ => 'Pending',
    };

String _formatStamp(DateTime? value) {
  if (value == null) return 'date unknown';
  final d = value.toLocal();
  return '${_two(d.day)}/${_two(d.month)}/${d.year}';
}

String _two(int n) => n.toString().padLeft(2, '0');