import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../models/mentor_desk_models.dart';
import '../services/mentor_desk_service.dart';

final _mentorServiceProvider = Provider((ref) => MentorDeskService(Supabase.instance.client));

class MentorSessionDetailScreen extends ConsumerStatefulWidget {
  final String bookingId;
  const MentorSessionDetailScreen({super.key, required this.bookingId});

  @override
  ConsumerState<MentorSessionDetailScreen> createState() => _MentorSessionDetailScreenState();
}

class _MentorSessionDetailScreenState extends ConsumerState<MentorSessionDetailScreen> {
  final _codeController = TextEditingController();
  SessionBooking? _booking;
  bool _loading = true;
  bool _working = false;
  String? _error;

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
      final booking = await ref.read(_mentorServiceProvider).getSessionBooking(widget.bookingId);
      if (!mounted) return;
      setState(() { _booking = booking; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = 'Could not load this session.'; _loading = false; });
    }
  }

  Future<void> _confirm() async {
    final booking = _booking;
    if (booking == null) return;
    setState(() { _working = true; _error = null; });
    try {
      await ref.read(_mentorServiceProvider).confirmSession(
        bookingId: booking.id,
        scheduledAt: booking.scheduledAt ?? booking.requestedAt,
        durationMinutes: booking.durationMinutes,
      );
      await _load();
    } on MentorDeskException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not confirm this session.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the six-digit code from the student.');
      return;
    }
    setState(() { _working = true; _error = null; });
    try {
      await ref.read(_mentorServiceProvider).verifySessionCode(bookingId: widget.bookingId, code: code);
      _codeController.clear();
      await _load();
    } on MentorDeskException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not verify this code.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final booking = _booking;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Mentor session'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : booking == null
              ? Center(child: Text(_error ?? 'Session not found.'))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.ink200)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(booking.statusLabel.toUpperCase(), style: const TextStyle(fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.w800, color: AppColors.teacherTier)),
                        const SizedBox(height: 8),
                        Text(booking.topic, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink900)),
                        const SizedBox(height: 12),
                        Text('Duration: ${booking.durationMinutes} minutes', style: const TextStyle(fontSize: 12, color: AppColors.ink600)),
                        Text('Scheduled: ${_date(booking.scheduledAt ?? booking.requestedAt)}', style: const TextStyle(fontSize: 12, color: AppColors.ink600)),
                      ]),
                    ),
                    if (booking.isRequested) ...[
                      const SizedBox(height: 18),
                      const Text('Confirm this booking to make the session available to the student.', style: TextStyle(fontSize: 13, color: AppColors.ink500)),
                      const SizedBox(height: 10),
                      FilledButton(onPressed: _working ? null : _confirm, child: Text(_working ? 'Confirming…' : 'Confirm session')),
                    ],
                    if (['confirmed', 'in_progress'].contains(booking.status) && booking.hasGoogleMeet) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.ink200)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('GOOGLE MEET SESSION', style: TextStyle(fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.w800, color: AppColors.accent)),
                          const SizedBox(height: 7),
                          const Text('Your meeting link is ready. Join at the scheduled time. Your assigned teacher will admit you.', style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.ink600)),
                          const SizedBox(height: 12),
                          SizedBox(width: double.infinity, child: FilledButton.icon(
                            onPressed: _working ? null : () async {
                              final opened = await MentorDeskService.openMeetLink(booking.googleMeetLink);
                              if (!opened && mounted) setState(() => _error = 'Could not open the Google Meet link. Check your browser and try again.');
                            },
                            icon: const Icon(Icons.video_call_rounded),
                            label: const Text('Join Google Meet'),
                          )),
                        ]),
                      ),
                    ],
                    if (['confirmed', 'in_progress'].contains(booking.status) && !booking.hasGoogleMeet) ...[
                      const SizedBox(height: 14),
                      _InfoCard(title: 'Meeting link pending', body: 'Your assigned teacher is preparing the protected Google Meet session. Refresh this page before the scheduled time.'),
                    ],
                    if (booking.isConfirmed && booking.isStarted && !booking.isVerified) ...[
                      const SizedBox(height: 20),
                      const Text('Verify student code', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink900)),
                      const SizedBox(height: 6),
                      const Text('Ask the student to share the one-time code shown in their session screen.', style: TextStyle(fontSize: 12, color: AppColors.ink500)),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _codeController,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: const InputDecoration(hintText: 'Six-digit code'),
                      ),
                      FilledButton(onPressed: _working ? null : _verify, child: Text(_working ? 'Verifying…' : 'Verify code')),
                    ],
                    if (booking.isVerified)
                      Container(margin: const EdgeInsets.only(top: 18), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)), child: const Text('Student code verified. The session is confirmed as attended.', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w700))),
                    if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12))),
                  ],
                ),
    );
  }

  String _date(DateTime date) {
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} · ${TimeOfDay.fromDateTime(local).format(context)}';
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String body;

  const _InfoCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(
            color: AppColors.ink900,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          )),
          const SizedBox(height: 5),
          Text(body, style: const TextStyle(
            color: AppColors.ink600,
            fontSize: 12,
            height: 1.45,
          )),
        ],
      ),
    );
  }
}
