import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/layout/responsive.dart';
import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart' show SectionHeader, TierAccent;
import '../../../core/widgets/states.dart';
import '../../mentor_desk/models/mentor_desk_models.dart';
import '../../mentor_desk/services/mentor_desk_service.dart';

final _serviceProvider = Provider<MentorDeskService>(
  (ref) => MentorDeskService(Supabase.instance.client),
);

/// Session detail for the student: status, schedule, meeting link, verification
/// code (10 min before), cancel, no-show report.
class SessionDetailScreen extends ConsumerStatefulWidget {
  final String bookingId;
  const SessionDetailScreen({super.key, required this.bookingId});

  @override
  ConsumerState<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends ConsumerState<SessionDetailScreen> {
  SessionBooking? _booking;
  bool _loading = true;
  String? _error;
  String? _code;
  bool _codeLoading = false;
  bool _codeVisible = false;
  String? _me;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _load() async {
    final client = Supabase.instance.client;
    _me = client.auth.currentUser!.id;
    final service = ref.read(_serviceProvider);
    final booking = await service.getSessionBooking(widget.bookingId);
    if (!mounted) return;
    setState(() { _booking = booking; _loading = false; });
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel this session?'),
        content: const Text('Your session allowance will be refunded.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel session')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(_serviceProvider).cancelSession(bookingId: widget.bookingId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session cancelled. Allowance refunded.')));
      _load();
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cancel failed: $e')));
    }
  }

  Future<void> _getCode() async {
    setState(() { _codeLoading = true; });
    try {
      final data = await ref.read(_serviceProvider).generateVerificationCode(widget.bookingId);
      if (!mounted) return;
      setState(() {
        _code = data['verification_code'] as String?;
        _codeVisible = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verification code revealed.')));
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _codeLoading = false);
    }
  }

  Future<void> _reportNoShow() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Mentor did not join?'),
        content: const Text('Report a no-show. Your session time will be refunded and the case reviewed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Report')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(_serviceProvider).recordNoShow(
            bookingId: widget.bookingId,
            reportedByRole: 'student',
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No-show reported. Allowance refunded.')));
      _load();
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
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

  @override
  Widget build(BuildContext context) {
    final accent = TierAccent.of(AppTier.student);

    return Scaffold(
      appBar: AppBar(title: const Text('Session')),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _booking == null
                  ? ErrorView(message: 'Session not found.', onRetry: _load)
                  : AdaptivePage(
                      maxWidth: 700,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _StatusHeader(booking: _booking!),
                          const SizedBox(height: 16),
                          _InfoRow(icon: Icons.schedule, label: 'Status', value: _booking!.statusLabel, color: Color(int.parse('0xFF${_statusColorName(_booking!.status)}'))),
                          const SizedBox(height: 10),
                          if (_booking!.scheduledAt != null)
                            _InfoRow(icon: Icons.access_time, label: 'Date & time', value: DateFormat('EEE, MMM d, y • hh:mm a').format(_booking!.scheduledAt!.toLocal())),
                          const SizedBox(height: 10),
                          _InfoRow(icon: Icons.access_alarm, label: 'Duration', value: '${_booking!.durationMinutes} minutes'),
                          const SizedBox(height: 10),
                          if (_booking!.meetingLink != null && _booking!.meetingLink!.isNotEmpty)
                            _InfoRow(icon: Icons.videocam, label: 'Meeting link', value: _booking!.meetingLink!),
                          if (_booking!.meetingRoom != null && _booking!.meetingRoom!.isNotEmpty)
                            _InfoRow(icon: Icons.meeting_room, label: 'Room', value: _booking!.meetingRoom!),
                          const SizedBox(height: 10),
                          _InfoRow(icon: Icons.subject, label: 'Topic', value: _booking!.topic),
                          const SizedBox(height: 10),
                          if (_booking!.preparation != null && _booking!.preparation!.isNotEmpty)
                            _InfoRow(icon: Icons.note, label: 'Preparation', value: _booking!.preparation!),
                          const SizedBox(height: 20),
                          const SectionHeader(title: 'Actions'),
                          const SizedBox(height: 10),
                          if (_booking!.isRequested) ...[
                            SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _cancel, icon: const Icon(Icons.cancel, size: 18), label: const Text('Cancel request'))),
                            const SizedBox(height: 10),
                          ],
                          if (_booking!.isConfirmed) ...[
                            if (_booking!.showCode && _booking!.verificationCode != null && !_booking!.codeLocked) ...[
                              _CodeCard(code: _code, codeLoading: _codeLoading, onReveal: _getCode, alreadyRevealed: _codeVisible),
                              const SizedBox(height: 10),
                            ] else if (_booking!.showCode) ...[
                              SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _getCode, icon: const Icon(Icons.vpn_key, size: 18), label: const Text('Reveal verification code'))),
                              const SizedBox(height: 10),
                            ],
                            if (_booking!.meetingLink != null && _booking!.meetingLink!.isNotEmpty)
                              SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.launch, size: 18), label: const Text('Open meeting link'))),
                            const SizedBox(height: 10),
                            if (_booking!.status == 'confirmed')
                              SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _reportNoShow, icon: const Icon(Icons.report_outlined, size: 18), label: const Text("Mentor didn't join"))),
                            const SizedBox(height: 10),
                            SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _cancel, icon: const Icon(Icons.cancel, size: 18), label: const Text('Cancel session'))),
                          ],
                          if (_booking!.isNoShow && _booking!.status == 'no_show_mentor') ...[
                            SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _reportNoShow, icon: const Icon(Icons.report_outlined, size: 18), label: const Text("Mentor didn't join"))),
                            const SizedBox(height: 10),
                          ],
                          if (_booking!.isCompleted)
                            SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: () => context.go('/mentor-desk/rating/${_booking!.id}'), icon: const Icon(Icons.rate_review, size: 18), label: const Text('Rate this session'))),
                          if (_booking!.closedWithoutCode)
                            const Text('Session closed without verification code. Pending administrative review.', style: TextStyle(color: Color(0xFFDC2626), fontSize: 13)),
                        ],
                      ),
                    ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  final SessionBooking booking;
  const _StatusHeader({required this.booking});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [TierAccent.of(AppTier.student).start, TierAccent.of(AppTier.student).end]),
        borderRadius: BorderRadius.circular(20),
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
        Container(width: 34, height: 34, decoration: BoxDecoration(color: TierAccent.of(AppTier.student).soft, borderRadius: BorderRadius.circular(10)), child: Icon(icon, size: 18, color: TierAccent.of(AppTier.student).onSoft)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              const SizedBox(height: 2),
              Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      ],
    );
  }
}

class _CodeCard extends StatelessWidget {
  final String? code;
  final bool codeLoading;
  final VoidCallback onReveal;
  final bool alreadyRevealed;
  const _CodeCard({required this.code, required this.codeLoading, required this.onReveal, required this.alreadyRevealed});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Verification code', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
                  child: codeLoading
                      ? const CircularProgressIndicator()
                      : Text(
                          alreadyRevealed && code != null ? code! : '········',
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: 4, fontFamily: 'monospace'),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              if (!alreadyRevealed)
                SizedBox(
                  height: 56,
                  child: OutlinedButton(onPressed: onReveal, child: const Text('Reveal')),
                )
              else
                const Icon(Icons.vpn_key, color: Color(0xFF2563EB)),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Show this code to the mentor at the end of the session. The mentor enters it to verify.', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
        ],
      ),
    );
  }
}
