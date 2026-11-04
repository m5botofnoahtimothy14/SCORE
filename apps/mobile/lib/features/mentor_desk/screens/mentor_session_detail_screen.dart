import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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

class MentorSessionDetailScreen extends ConsumerStatefulWidget {
  final String bookingId;
  const MentorSessionDetailScreen({super.key, required this.bookingId});

  @override
  ConsumerState<MentorSessionDetailScreen> createState() => _MentorSessionDetailScreenState();
}

class _MentorSessionDetailScreenState extends ConsumerState<MentorSessionDetailScreen> {
  final _codeController = TextEditingController();

  bool _loading = true;
  String? _error;
  SessionBooking? _booking;
  String? _myUserId;
  bool _codeLocked = false;
  int _codeAttemptsLeft = 5;

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
      context.pop();
    } on MentorDeskException catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.message; _codeAttemptsLeft = (_codeAttemptsLeft - 1).clamp(0, 5); });
      if (_codeAttemptsLeft == 0) setState(() { _codeLocked = true; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _createMeetLink() async {
    setState(() { _loading = true; _error = null; });
    try {
      final service = ref.read(mentorDeskServiceProvider);
      final data = await service.createGoogleMeet(widget.bookingId);
      if (!mounted) return;
      final meetLink = data['meet_link'] as String?;
      if (meetLink != null) {
        _booking = await service.getSessionBooking(widget.bookingId);
      }
      if (!mounted) return;
      setState(() { _loading = false; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Google Meet link created.'),
        backgroundColor: MDColors.success,
        duration: Duration(seconds: 4),
      ));
    } on MentorDeskException catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.message; });
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
        content: Text('Report that the ${reportedByRole == 'mentor' ? 'mentor' : 'student'} did not join? This creates an administrative review record.'),
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
        content: Text('No-show recorded. Review created.'),
        backgroundColor: MDColors.warning,
        duration: Duration(seconds: 4),
      ));
      context.pop();
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
        title: const Text('Session Detail', style: TextStyle(color: MDColors.ink900, fontWeight: FontWeight.w800)),
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
                          Container(
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
                                const Text('Session', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: MDColors.ink900)),
                                const SizedBox(height: 8),
                                Text(_booking!.topic, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: MDColors.ink900)),
                                const SizedBox(height: 16),
                                _DetailRow(icon: Icons.person, label: 'Student', value: '${_booking!.studentFirstName ?? 'Student'} (${_booking!.studentIdNo ?? '—'})'),
                                _DetailRow(icon: Icons.schedule, label: 'Scheduled', value: _booking!.scheduledAt != null ? DateFormat('EEE, MMM d · h:mm a').format(_booking!.scheduledAt!) : '—'),
                                _DetailRow(icon: Icons.access_time, label: 'Duration', value: '${_booking!.durationMinutes} minutes'),
                                _DetailRow(icon: Icons.videocam, label: 'Meeting Link', value: _booking!.meetingLink ?? _booking!.meetingRoom ?? '—'),
                                _DetailRow(icon: Icons.schedule, label: 'Status', value: _booking!.status.replaceAll('_', ' ')),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          if (_booking!.status == 'confirmed' || _booking!.status == 'started') ...[
                            const Text('Verification Code', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MDColors.ink700)),
                            const SizedBox(height: 12),
                            MDGlossInput(
                              controller: _codeController,
                              label: 'Enter 6-digit code shown by student',
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
                              child: const Text('Verify Session', style: TextStyle(fontWeight: FontWeight.w800)),
                            ),
                            const SizedBox(height: 24),
                          ],

                          const Text('Actions', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MDColors.ink700)),
                          const SizedBox(height: 12),
                          if (_booking!.meetUrl == null || _booking!.meetUrl!.isEmpty)
                            MDButton(
                              onPressed: _createMeetLink,
                              loading: _loading,
                              child: const Text('Create Google Meet Link', style: TextStyle(fontWeight: FontWeight.w800)),
                            ),
                          if (_booking!.meetUrl != null && _booking!.meetUrl!.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: MDColors.success.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(kRadiusSm),
                                border: Border.all(color: MDColors.success.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.videocam, color: MDColors.success, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Meeting link available',
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MDColors.ink700),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      final uri = Uri.parse(_booking!.meetUrl!);
                                      if (await canLaunchUrl(uri)) {
                                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                                      }
                                    },
                                    child: const Text('Open'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
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
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow({required this.icon, required this.label, required this.value});

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
                Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: MDColors.ink900)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}



