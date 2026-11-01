import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../models/mentor_desk_models.dart';
import '../services/mentor_desk_service.dart';

final _mentorServiceProvider = Provider((ref) => MentorDeskService(Supabase.instance.client));

class SessionDetailScreen extends ConsumerStatefulWidget {
  final String bookingId;
  const SessionDetailScreen({super.key, required this.bookingId});

  @override
  ConsumerState<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends ConsumerState<SessionDetailScreen> {
  SessionBooking? _booking;
  bool _loading = true;
  bool _working = false;
  String? _error;
  String? _verificationCode;
  DateTime? _codeExpiresAt;
  static const _secureStorage = FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final booking = await ref.read(_mentorServiceProvider).getSessionBooking(widget.bookingId);
      final savedCode = await _secureStorage.read(key: 'scoreplus_session_code_${widget.bookingId}');
      final savedExpiry = await _secureStorage.read(key: 'scoreplus_session_code_expiry_${widget.bookingId}');
      final expiry = DateTime.tryParse(savedExpiry ?? '');
      if (!mounted) return;
      setState(() {
        _booking = booking;
        if (savedCode != null && expiry != null && expiry.isAfter(DateTime.now())) {
          _verificationCode = savedCode;
          _codeExpiresAt = expiry;
        } else {
          _verificationCode = null;
          _codeExpiresAt = expiry;
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = 'Could not load this session.'; _loading = false; });
    }
  }

  Future<void> _startSession() async {
    setState(() { _working = true; _error = null; });
    try {
      final service = ref.read(_mentorServiceProvider);
      if (_booking?.isStarted != true) {
        await service.startTeacherSession(widget.bookingId);
      }
      final expiry = _codeExpiresAt;
      if (_verificationCode == null || expiry == null || !expiry.isAfter(DateTime.now())) {
        final code = await service.generateVerificationCode(widget.bookingId);
        final value = code['verification_code']?.toString();
        final expiresAt = DateTime.tryParse(code['expires_at']?.toString() ?? '');
        if (value == null || expiresAt == null) {
          throw Exception('The server did not return a valid session code.');
        }
        await _secureStorage.write(key: 'scoreplus_session_code_${widget.bookingId}', value: value);
        await _secureStorage.write(key: 'scoreplus_session_code_expiry_${widget.bookingId}', value: expiresAt.toIso8601String());
        if (!mounted) return;
        setState(() {
          _verificationCode = value;
          _codeExpiresAt = expiresAt;
        });
      }
      await _load();
    } on MentorDeskException catch (error) {
      if (mounted) setState(() => _error = error.message);
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not start the session or issue a new code.');
      await _load();
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this session?'),
        content: const Text('The school session allowance will be handled by the booking rules.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep session')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Cancel session')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() { _working = true; _error = null; });
    try {
      await ref.read(_mentorServiceProvider).cancelSession(bookingId: widget.bookingId);
      await _load();
    } on MentorDeskException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not cancel the session.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(identityProviderProvider).valueOrNull;
    final booking = _booking;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Session details'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))]),
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
                        Text(booking.statusLabel.toUpperCase(), style: const TextStyle(fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.w800, color: AppColors.accent)),
                        const SizedBox(height: 9),
                        Text(booking.topic, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.ink900)),
                        const SizedBox(height: 12),
                        _InfoRow(label: 'Duration', value: '${booking.durationMinutes} minutes'),
                        _InfoRow(label: 'Scheduled', value: _dateTime(booking.scheduledAt)),
                        _InfoRow(label: 'Status', value: booking.statusLabel),
                      ]),
                    ),
                    if (booking.preparation != null && booking.preparation!.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _InfoCard(title: 'Preparation', body: booking.preparation!),
                    ],
                    if (booking.isStarted && ['confirmed', 'in_progress'].contains(booking.status)) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => context.go('/mentor-desk/call/${booking.id}'),
                        icon: const Icon(Icons.video_call_rounded),
                        label: const Text('Join in-app call'),
                      ),
                    ],
                    if (_verificationCode != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(18)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('ONE-TIME SESSION CODE', style: TextStyle(color: Colors.white70, fontSize: 10, letterSpacing: 1.1, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          SelectableText(_verificationCode!, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 6)),
                          const SizedBox(height: 6),
                          Text('Share this code with your assigned teacher. It is stored securely on this device and expires at ${_dateTime(_codeExpiresAt)}.', style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)),
                        ]),
                      ),
                    ],
                    if (booking.status == 'confirmed' && !booking.isVerified && identity?.tier == AppTier.student && (!booking.isStarted || _verificationCode == null)) ...[
                      const SizedBox(height: 18),
                      FilledButton.icon(onPressed: _working ? null : _startSession, icon: const Icon(Icons.play_arrow_rounded), label: Text(_working ? 'Working…' : booking.isStarted ? 'Generate session code' : 'Start session and get code')),
                    ],
                    if ((booking.status == 'requested' || booking.status == 'confirmed') && !booking.isStarted) ...[
                      const SizedBox(height: 10),
                      OutlinedButton(onPressed: _working ? null : _cancel, child: const Text('Cancel booking')),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                    ],
                  ],
                ),
    );
  }

  String _dateTime(DateTime? date) {
    if (date == null) return 'Not scheduled';
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} · ${TimeOfDay.fromDateTime(local).format(context)}';
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.body});
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: AppColors.ink200)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 7),
      Text(body, style: const TextStyle(fontSize: 13, height: 1.45, color: AppColors.ink600)),
    ]),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 7),
    child: Row(children: [
      SizedBox(width: 92, child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.ink500))),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.ink700))),
    ]),
  );
}
