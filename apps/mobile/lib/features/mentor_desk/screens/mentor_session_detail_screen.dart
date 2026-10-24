import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mentor_desk_design.dart';
import '../../../core/layout/responsive.dart';
import '../../../core/widgets/states.dart';
import '../../mentor_desk/models/mentor_desk_models.dart';
import '../../mentor_desk/services/mentor_desk_service.dart';

final _serviceProvider = Provider<MentorDeskService>(
  (ref) => MentorDeskService(Supabase.instance.client),
);

/// Mentor session detail: confirm schedule, enter verification code, close
/// without code (exception), record no-show.
class MentorSessionDetailScreen extends ConsumerStatefulWidget {
  final String bookingId;
  const MentorSessionDetailScreen({super.key, required this.bookingId});

  @override
  ConsumerState<MentorSessionDetailScreen> createState() => _MentorSessionDetailScreenState();
}

class _MentorSessionDetailScreenState extends ConsumerState<MentorSessionDetailScreen> {
  SessionBooking? _booking;
  bool _loading = true;
  String? _error;
  final _codeCtrl = TextEditingController();
  String? _closeReason;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final service = ref.read(_serviceProvider);
    final booking = await service.getSessionBooking(widget.bookingId);
    if (!mounted) return;
    setState(() { _booking = booking; _loading = false; });
  }

  Future<void> _confirm() async {
    try {
      await ref.read(_serviceProvider).confirmSession(
            bookingId: widget.bookingId,
            scheduledAt: _booking!.scheduledAt!,
            durationMinutes: _booking!.durationMinutes,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session confirmed.')));
      _load();
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    try {
      await ref.read(_serviceProvider).verifySessionCode(bookingId: widget.bookingId, code: code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session verified and completed.')));
      _load();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _closeWithoutCode() async {
    final reason = _closeReason;
    if (reason == null || reason.trim().isEmpty) {
      setState(() => _error = 'A reason is required.');
      return;
    }
    try {
      await ref.read(_serviceProvider).closeSessionWithoutCode(bookingId: widget.bookingId, reason: reason.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session closed without code (flagged for review).')));
      _load();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _reportStudentNoShow() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Student didn't join?"),
        content: const Text('Record a student no-show. Creates an administrative review record.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Record')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(_serviceProvider).recordNoShow(bookingId: widget.bookingId, reportedByRole: 'mentor');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Student no-show recorded.')));
      _load();
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = MDTier.teacher;
    return Scaffold(
      backgroundColor: MDColors.ink50,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, title: const Text('Session')),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _booking == null
                  ? ErrorView(message: 'Session not found.', onRetry: _load)
                  : AdaptivePage(
                      maxWidth: 700,
                      child: ListView(
                        padding: const EdgeInsets.all(kGutter),
                        children: [
                          _StatusHeader(booking: _booking!, tier: accent),
                          const SizedBox(height: kGutter),
                          _InfoRow(icon: Icons.schedule, label: 'Status', value: _booking!.statusLabel, color: Color(int.parse('0xFF${_statusColorName(_booking!.status)}'))),
                          const SizedBox(height: kGutter),
                          if (_booking!.scheduledAt != null)
                            _InfoRow(icon: Icons.access_time, label: 'Date & time', value: DateFormat('EEE, MMM d, y • hh:mm a').format(_booking!.scheduledAt!.toLocal())),
                          const SizedBox(height: kGutter),
                          _InfoRow(icon: Icons.access_alarm, label: 'Duration', value: '${_booking!.durationMinutes} minutes'),
                          const SizedBox(height: kGutter),
                          if (_booking!.meetingLink != null && _booking!.meetingLink!.isNotEmpty)
                            _InfoRow(icon: Icons.videocam, label: 'Meeting link', value: _booking!.meetingLink!),
                          const SizedBox(height: kGutter),
                          _InfoRow(icon: Icons.subject, label: 'Topic', value: _booking!.topic),
                          const SizedBox(height: kGutter * 2),
                          MDSectionHeader(title: 'Actions'),
                          const SizedBox(height: kGutter),
                          if (_booking!.isRequested) ...[
                            _ConfirmCard(
                              booking: _booking!,
                              accent: accent,
                              onConfirm: _confirm,
                            ),
                            const SizedBox(height: kGutter),
                          ],
                          if (_booking!.isConfirmed && !_booking!.isCompleted && !_booking!.isNoShow) ...[
                            _CodeEntryCard(
                              codeCtrl: _codeCtrl,
                              error: _error,
                              onVerify: _verifyCode,
                              canVerify: !_booking!.codeLocked,
                            ),
                            const SizedBox(height: kGutter),
                            _CloseWithoutCodeCard(
                              reasonCtrl: TextEditingController(text: _closeReason ?? ''),
                              onSave: (reason) {
                                setState(() => _closeReason = reason);
                                _closeWithoutCode();
                              },
                            ),
                            const SizedBox(height: kGutter),
                            SizedBox(
                              width: double.infinity,
                              child: MDGlossOutlineButton(
                                onPressed: _reportStudentNoShow,
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [Icon(Icons.report_outlined, size: 18), SizedBox(width: 8), Text("Student didn't join")],
                                ),
                              ),
                            ),
                            const SizedBox(height: kGutter),
                          ],
                          if (_booking!.closedWithoutCode)
                            const Text('Closed without verification code — flagged for administrative review.', style: TextStyle(color: MDColors.danger, fontSize: 13)),
                          if (_booking!.isCompleted)
                            const Text('Session verified and completed.', style: TextStyle(color: MDColors.success, fontWeight: FontWeight.w600)),
                        ],
                        ),
                        ),
      );
  }
}

String _statusColorName(String status) {
  switch (status) {
    case 'confirmed': return '059669';
    case 'requested': return 'D97706';
    case 'completed': return '059669';
    case 'cancelled_by_student': return '475569';
    case 'cancelled_by_mentor': return 'DC2626';
    case 'no_show_mentor': return 'DC2626';
    case 'no_show_student': return 'D97706';
    case 'unverified_closed': return '64748B';
    default: return '64748B';
  }
}

class _StatusHeader extends StatelessWidget {
  final SessionBooking booking;
  final MDTier tier;
  const _StatusHeader({required this.booking, required this.tier});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(kGutter),
      decoration: BoxDecoration(
        gradient: tier.gradient,
        borderRadius: BorderRadius.circular(kRadiusLg),
        boxShadow: [
          BoxShadow(color: tier.solid.withValues(alpha: 0.45), blurRadius: 30, offset: const Offset(0, 14)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(booking.topic, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
            child: Text(booking.statusLabel, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;
  const _InfoRow({required this.icon, required this.label, required this.value, this.color});
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(width: 34, height: 34, decoration: BoxDecoration(color: MDTier.teacher.soft, borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 18, color: MDTier.teacher.onSoft)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: MDColors.ink600)),
              const SizedBox(height: 2),
               Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
             ],
           ),
         ),
          ],
        );
  }
}

class _ConfirmCard extends StatelessWidget {
  final SessionBooking booking;
  final MDTier accent;
  final VoidCallback onConfirm;
  const _ConfirmCard({required this.booking, required this.accent, required this.onConfirm});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(kGutter),
      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(kRadiusSm), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Confirm this session', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: kGutter / 2),
          TextField(decoration: InputDecoration(labelText: 'Meeting link (optional)', hintText: 'https://meet.example/...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(kRadiusSm)))),
          const SizedBox(height: kGutter),
          SizedBox(width: double.infinity, child: MDGlossButton(onPressed: () => onConfirm(), child: const Text('Confirm schedule'))),
        ],
      ),
    );
  }
}

class _CodeEntryCard extends StatelessWidget {
  final TextEditingController codeCtrl;
  final String? error;
  final VoidCallback onVerify;
  final bool canVerify;
  const _CodeEntryCard({required this.codeCtrl, this.error, required this.onVerify, required this.canVerify});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(kGutter),
      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(kRadiusSm), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Verify session code', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: kGutter / 2),
          const Text('The student reads the 6-digit code to you at the end of the session.', style: TextStyle(fontSize: 12, color: MDColors.ink600)),
          const SizedBox(height: kGutter),
          TextField(
            controller: codeCtrl,
            maxLength: 6,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: '6-digit code', border: OutlineInputBorder(borderRadius: BorderRadius.circular(kRadiusSm))),
          ),
          if (error != null) ...[
            const SizedBox(height: kGutter / 2),
            Text(error!, style: const TextStyle(color: MDColors.danger, fontSize: 12)),
          ],
          const SizedBox(height: kGutter),
          SizedBox(width: double.infinity, child: MDGlossButton(onPressed: canVerify ? onVerify : null, child: const Text('Verify code'))),
        ],
      ),
    );
  }
}

class _CloseWithoutCodeCard extends StatelessWidget {
  final TextEditingController reasonCtrl;
  final void Function(String reason) onSave;
  const _CloseWithoutCodeCard({required this.reasonCtrl, required this.onSave});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(kGutter),
      decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(kRadiusSm), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Close without code (exception)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: MDColors.danger)),
          const SizedBox(height: kGutter / 2),
          const Text('Only through the designated exception workflow. Flagged for review.', style: TextStyle(fontSize: 11, color: MDColors.ink600)),
          const SizedBox(height: kGutter),
          TextField(
            controller: reasonCtrl,
            maxLines: 3,
            decoration: InputDecoration(labelText: 'Reason *', border: OutlineInputBorder(borderRadius: BorderRadius.circular(kRadiusSm))),
          ),
          const SizedBox(height: kGutter),
          SizedBox(width: double.infinity, child: MDGlossOutlineButton(onPressed: () => onSave(reasonCtrl.text), child: const Text('Close without code'))),
        ],
      ),
    );
  }
}
