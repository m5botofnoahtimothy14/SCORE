import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
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

class SessionDetailScreen extends ConsumerStatefulWidget {
  final String bookingId;
  const SessionDetailScreen({super.key, required this.bookingId});

  @override
  ConsumerState<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends ConsumerState<SessionDetailScreen> {
  final _codeController = TextEditingController();

  bool _loading = true;
  String? _error;
  SessionBooking? _booking;
  String? _myUserId;
  AppTier? _myTier;
  String? _schoolId;
  bool _codeVisible = false;
  int _codeAttemptsLeft = 5;
  bool _codeLocked = false;
  String? _verificationCode;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final identity = await ref.read(identityProviderProvider.future);
      if (identity == null) throw Exception('No identity found');
      _myUserId = identity.userId;
      _myTier = identity.tier;
      _schoolId = identity.schoolId;

      final service = ref.read(mentorDeskServiceProvider);
      _booking = await service.getSessionBooking(widget.bookingId);
      if (_booking == null) throw Exception('Session not found');

      if (!mounted) return;
      setState(() { _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _generateCode() async {
    if (_schoolId == null) return;
    setState(() { _loading = true; });
    try {
      final service = ref.read(mentorDeskServiceProvider);
      final data = await service.generateVerificationCode(widget.bookingId);
      if (!mounted) return;
      _verificationCode = data['verification_code'] as String?;
      setState(() { _codeVisible = true; _loading = false; _codeLocked = false; _codeAttemptsLeft = 5; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Verification code is now visible. Share it with your mentor.'),
        backgroundColor: MDColors.success,
      ));
    } on MentorDeskException catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.message; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() { _error = 'Please enter the verification code.'; });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final service = ref.read(mentorDeskServiceProvider);
      await service.verifySessionCode(bookingId: widget.bookingId, code: code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Session verified successfully!'),
        backgroundColor: MDColors.success,
        duration: Duration(seconds: 4),
      ));
      context.go('/mentor-desk');
    } on MentorDeskException catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.message; _codeAttemptsLeft = (_codeAttemptsLeft - 1).clamp(0, 5); });
      if (_codeAttemptsLeft == 0) {
        setState(() { _codeLocked = true; });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _recordNoShow(String reportedByRole) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record No-Show'),
        content: Text('Report that the ${reportedByRole == 'mentor' ? 'mentor' : 'student'} did not join? This may trigger a refund and administrative review.'),
        actions: [
          TextButton(onPressed: () => context.pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => context.pop(true), child: const Text('Report')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() { _loading = true; _error = null; });
    try {
      final service = ref.read(mentorDeskServiceProvider);
      await service.recordNoShow(bookingId: widget.bookingId, reportedByRole: reportedByRole, reason: 'Participant did not join');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No-show recorded. Administrative review created.'),
        backgroundColor: MDColors.warning,
        duration: Duration(seconds: 4),
      ));
      context.go('/mentor-desk');
    } on MentorDeskException catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.message; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Session'),
        content: const Text('Cancel this booking? Allowance will be refunded.'),
        actions: [
          TextButton(onPressed: () => context.pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => context.pop(true), child: const Text('Cancel Session')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() { _loading = true; _error = null; });
    try {
      final service = ref.read(mentorDeskServiceProvider);
      await service.cancelSession(bookingId: widget.bookingId, cancelledBy: _myUserId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Session cancelled. Allowance refunded.'),
        backgroundColor: MDColors.success,
        duration: Duration(seconds: 4),
      ));
      context.go('/mentor-desk');
    } on MentorDeskException catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.message; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
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
        title: const Text('Session', style: TextStyle(color: MDColors.ink900, fontWeight: FontWeight.w800)),
        centerTitle: false,
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _booking == null
                  ? const Center(child: Text('No session data', style: TextStyle(color: MDColors.ink500)))
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
                          _statusBanner(context),
                          const SizedBox(height: 20),
                          _infoCard(context),
                          const SizedBox(height: 20),
                          if (_booking!.status == 'confirmed' && _myTier == AppTier.student) ...[
                            _studentActions(context),
                            const SizedBox(height: 20),
                          ],
                          if (_booking!.status == 'confirmed' && _myTier == AppTier.teacher) ...[
                            _mentorActions(context),
                            const SizedBox(height: 20),
                          ],
                          _verificationSection(context),
                          const SizedBox(height: 20),
                          _noShowSection(context),
                          const SizedBox(height: 24),
                          if (_booking!.status == 'requested' || _booking!.status == 'confirmed')
                            _cancelButton(context),
                        ],
                      ),
                    ),
    );
  }

  Widget _statusBanner(BuildContext context) {
    final status = _booking!.status;
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(kRadiusLg),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 10, height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Status: ${status.replaceAll('_', ' ')}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: MDColors.ink700)),
                const SizedBox(height: 2),
                Text(_statusText(status),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'requested': return MDColors.warning;
      case 'confirmed': return MDColors.info;
      case 'completed': return MDColors.success;
      case 'cancelled_by_student':
      case 'cancelled_by_mentor': return MDColors.ink500;
      case 'no_show_student':
      case 'no_show_mentor': return MDColors.danger;
      case 'unverified_closed': return MDColors.danger;
      default: return MDColors.ink500;
    }
  }

  String _statusText(String status) {
    switch (status) {
      case 'requested': return 'Waiting for mentor confirmation';
      case 'confirmed': return 'Confirmed — scheduled';
      case 'completed': return 'Completed';
      case 'cancelled_by_student': return 'Cancelled by you';
      case 'cancelled_by_mentor': return 'Cancelled by mentor';
      case 'no_show_student': return 'You did not join';
      case 'no_show_mentor': return 'Mentor did not join';
      case 'unverified_closed': return 'Closed without verification';
      default: return status;
    }
  }

  Widget _infoCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MDColors.surfaceCard,
        borderRadius: BorderRadius.circular(kRadiusLg),
        border: Border.all(color: MDColors.ink200),
        boxShadow: [
          BoxShadow(color: MDColors.brand.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Topic', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: MDColors.ink500)),
                    const SizedBox(height: 4),
                    Text(_booking!.topic, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: MDColors.ink900)),
                  ],
                ),
              ),
              _Chip(label: '${_booking!.durationMinutes} min', color: MDColors.brand),
            ],
          ),
          const SizedBox(height: 16),
          _DetailRow(icon: Icons.person, label: 'Student', value: '${_booking!.studentFirstName ?? 'Student'} (${_booking!.studentIdNo ?? '—'})'),
          _DetailRow(icon: Icons.school, label: 'Mentor', value: '${_booking!.mentorFirstName ?? '—'} (${_booking!.mentorStaffIdNo ?? '—'})'),
          _DetailRow(icon: Icons.book, label: 'Subject', value: _booking!.subjectName ?? '—'),
          _DetailRow(icon: Icons.schedule, label: 'Scheduled', value: _booking!.scheduledAt != null ? DateFormat('EEE, MMM d · h:mm a').format(_booking!.scheduledAt!) : '—'),
          _DetailRow(icon: Icons.meeting_room, label: 'Meeting', value: _booking!.meetingLink != null ? 'Google Meet link' : (_booking!.meetingRoom ?? '—')),
          if (_booking!.googleMeetLink != null)
            _DetailRow(icon: Icons.videocam, label: 'Google Meet', value: 'Link available', isLink: true),
        ],
      ),
    );
  }

  Widget _studentActions(BuildContext context) {
    final canGenerate = _booking!.status == 'confirmed';
    final now = DateTime.now();
    final scheduledAt = _booking!.scheduledAt;
    final visibleAt = scheduledAt != null ? scheduledAt.subtract(const Duration(minutes: 10)) : null;
    final showCode = _verificationCode != null || (_booking!.verificationCode != null && visibleAt != null && now.isAfter(visibleAt));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Verification Code', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MDColors.ink700)),
        const SizedBox(height: 12),
        if (!canGenerate)
          MDButton(
            onPressed: _generateCode,
            child: const Text('Get Verification Code', style: TextStyle(fontWeight: FontWeight.w800)),
          )
        else if (!showCode)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: MDColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(kRadiusSm),
              border: Border.all(color: MDColors.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.access_time, color: MDColors.warning, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Code will be visible 10 minutes before the session starts.', style: TextStyle(fontSize: 13, color: MDColors.ink700)),
                ),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: MDColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(kRadiusSm),
              border: Border.all(color: MDColors.success.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.vpn_key, color: MDColors.success, size: 20),
                    SizedBox(width: 10),
                    Text('Verification Code', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MDColors.ink700)),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: MDColors.success,
                    borderRadius: BorderRadius.circular(kRadiusSm),
                  ),
                  child: Center(
                    child: Text(
                      _verificationCode ?? _booking!.verificationCode ?? '—',
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 4),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Read this code to your mentor at the end of the session.',
                    style: TextStyle(fontSize: 12, color: MDColors.ink600)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _mentorActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Complete Session', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MDColors.ink700)),
        const SizedBox(height: 12),
        MDButton(
          onPressed: () {
            setState(() { _codeVisible = true; });
          },
          child: const Text('Enter Verification Code', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: MDGlossOutlineButton(
                onPressed: () => _recordNoShow('student'),
                child: const Text('Student Did Not Join', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MDGlossOutlineButton(
                onPressed: () => _recordNoShow('mentor'),
                child: const Text('Mentor Did Not Join', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _verificationSection(BuildContext context) {
    if (!_codeVisible && _myTier != AppTier.teacher) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Verification Code', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MDColors.ink700)),
        const SizedBox(height: 12),
        if (_myTier == AppTier.teacher) ...[
          MDGlossInput(
            controller: _codeController,
            label: 'Enter 6-digit code from student',
            hint: '000000',
            keyboardType: TextInputType.number,
            errorText: _codeLocked ? 'Code entry locked — too many incorrect attempts' : null,
          ),
          const SizedBox(height: 12),
          if (_codeAttemptsLeft < 5)
            Text('$_codeAttemptsLeft attempt(s) left',
                style: TextStyle(fontSize: 12, color: _codeLocked ? MDColors.danger : MDColors.ink500, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          MDButton(
            onPressed: _codeLocked ? null : _verifyCode,
            loading: _loading,
            child: const Text('Verify Code', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: MDColors.info.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(kRadiusSm),
              border: Border.all(color: MDColors.info.withValues(alpha: 0.3)),
            ),
            child: const Center(
              child: Text('The mentor will enter the code you shared to verify the session.',
                  style: TextStyle(fontSize: 13, color: MDColors.ink700)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _noShowSection(BuildContext context) {
    if (_myTier != AppTier.teacher) return const SizedBox.shrink();
    if (_booking!.status == 'completed' || _booking!.status == 'no_show_student' || _booking!.status == 'no_show_mentor')
      return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('No-Show Report', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MDColors.ink700)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: MDButton(
                onPressed: () => _recordNoShow('student'),
                child: const Text('Student Did Not Join', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MDButton(
                onPressed: () => _recordNoShow('mentor'),
                child: const Text('Mentor Did Not Join', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _cancelButton(BuildContext context) {
    if (_booking!.status != 'requested' && _booking!.status != 'confirmed') return const SizedBox.shrink();
    return SizedBox(
      width: double.infinity,
      child: MDGlossOutlineButton(
        onPressed: _cancel,
        child: const Text('Cancel Session', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isLink;
  const _DetailRow({required this.icon, required this.label, required this.value, this.isLink = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: MDColors.brand),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: MDColors.ink500)),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isLink ? MDColors.brand : MDColors.ink900)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}





