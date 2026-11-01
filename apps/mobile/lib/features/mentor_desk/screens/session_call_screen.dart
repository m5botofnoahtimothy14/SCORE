import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart';

class SessionCallScreen extends ConsumerStatefulWidget {
  final String bookingId;
  const SessionCallScreen({super.key, required this.bookingId});

  @override
  ConsumerState<SessionCallScreen> createState() => _SessionCallScreenState();
}

class _SessionCallScreenState extends ConsumerState<SessionCallScreen> {
  Room? _room;
  bool _connecting = true;
  bool _connected = false;
  bool _microphoneEnabled = true;
  bool _cameraEnabled = true;
  bool _ending = false;
  int _remainingSeconds = 0;
  DateTime? _callDeadline;
  Timer? _deadlineTimer;
  String? _error;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    _deadlineTimer?.cancel();
    _callDeadline = null;
    setState(() { _connecting = true; _error = null; _remainingSeconds = 0; });
    Room? room;
    try {
      final previousRoom = _room;
      if (previousRoom != null) {
        previousRoom.removeListener(_onRoomChanged);
        await previousRoom.disconnect();
        previousRoom.dispose();
      }
      final response = await Supabase.instance.client.functions.invoke(
        'issue-video-token',
        body: {'booking_id': widget.bookingId},
      );
      final data = response.data;
      if (data is! Map || data['success'] != true) {
        final code = data is Map ? data['error']?.toString() : null;
        throw Exception(_friendlyError(code));
      }
      final url = data['url']?.toString();
      final token = data['token']?.toString();
      final expiry = DateTime.tryParse(data['expires_at']?.toString() ?? '');
      if (url == null || token == null || url.isEmpty || token.isEmpty || expiry == null) {
        throw Exception('The video service returned an invalid connection token.');
      }
      if (!expiry.isAfter(DateTime.now())) {
        throw Exception('The booked session time has ended.');
      }

      room = Room();
      room.addListener(_onRoomChanged);
      if (mounted) setState(() => _room = room);
      await room.connect(
        url,
        token,
        roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
      );
      await room.localParticipant.setMicrophoneEnabled(true);
      try {
        await room.localParticipant.setCameraEnabled(true);
      } catch (_) {
        if (mounted) setState(() => _cameraEnabled = false);
      }
      await AudioManager.instance.setSpeakerOutputPreferred(true);
      if (!mounted) return;
      setState(() {
        _connected = true;
        _connecting = false;
      });
      _startSessionDeadline(expiry);
    } catch (error) {
      if (room != null) {
        room.removeListener(_onRoomChanged);
        await room.disconnect();
        room.dispose();
      }
      if (!mounted) return;
      if (identical(_room, room)) _room = null;
      setState(() {
        _error = error is FunctionException
            ? _friendlyError(error.details?.toString())
            : error.toString().replaceFirst('Exception: ', '');
        _connecting = false;
        _connected = false;
      });
    }
  }

  static String _friendlyError(String? code) => switch (code) {
    'video_not_configured' => 'In-app calling is not configured on the server yet.',
    'booking_not_confirmed' => 'This session is not confirmed for a call.',
    'booking_not_started' => 'The student must start the session before anyone can join.',
    'session_time_elapsed' => 'The booked session time has ended.',
    'invalid_session_duration' => 'This booking has an invalid session duration.',
    'not_a_participant' => 'Your account is not a participant in this session.',
    'booking_not_found' => 'The session could not be found.',
    _ => 'Could not connect to the in-app call. Please try again.',
  };

  void _onRoomChanged() {
    if (mounted) setState(() {});
  }

  void _startSessionDeadline(DateTime deadline) {
    _deadlineTimer?.cancel();
    _callDeadline = deadline.toLocal();
    void updateRemaining() {
      final remaining = _callDeadline!.difference(DateTime.now()).inSeconds;
      if (remaining <= 0) {
        _deadlineTimer?.cancel();
        unawaited(_expireCall());
      } else if (mounted) {
        setState(() => _remainingSeconds = remaining);
      }
    }

    _deadlineTimer = Timer.periodic(const Duration(seconds: 1), (_) => updateRemaining());
    updateRemaining();
  }

  Future<void> _disconnectRoom() async {
    _deadlineTimer?.cancel();
    final room = _room;
    _room = null;
    if (room != null) {
      room.removeListener(_onRoomChanged);
      await room.disconnect();
      room.dispose();
    }
  }

  String _sessionRoute() {
    final identity = ref.read(identityProviderProvider).valueOrNull;
    return identity?.isTeacher == true || identity?.isLeadership == true
        ? '/mentor-desk/session/${widget.bookingId}/mentor'
        : '/mentor-desk/session/${widget.bookingId}';
  }

  Future<void> _expireCall() async {
    if (_ending) return;
    _ending = true;
    await _disconnectRoom();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('The booked session time has ended.')),
    );
    context.go(_sessionRoute());
  }

  Future<void> _toggleMicrophone() async {
    final room = _room;
    if (room == null) return;
    final next = !_microphoneEnabled;
    try {
      await room.localParticipant.setMicrophoneEnabled(next);
      if (mounted) setState(() => _microphoneEnabled = next);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not change microphone state.');
    }
  }

  Future<void> _toggleCamera() async {
    final room = _room;
    if (room == null) return;
    final next = !_cameraEnabled;
    try {
      await room.localParticipant.setCameraEnabled(next);
      if (mounted) setState(() => _cameraEnabled = next);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not change camera state.');
    }
  }

  Future<void> _endCall() async {
    if (_ending) return;
    setState(() => _ending = true);
    await _disconnectRoom();
    if (!mounted) return;
    context.go(_sessionRoute());
  }

  @override
  void dispose() {
    _deadlineTimer?.cancel();
    final room = _room;
    if (room != null) {
      room.removeListener(_onRoomChanged);
      unawaited(room.disconnect().whenComplete(room.dispose));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    final remoteParticipants = room?.remoteParticipants.values.toList() ?? [];
    final localParticipant = room?.localParticipant;

    return Scaffold(
      backgroundColor: const Color(0xFF07111F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF07111F),
        foregroundColor: Colors.white,
        title: Text(_connected ? 'SCORE+ mentor session' : 'Connecting to session'),
        actions: [
          if (_connected)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(children: [
                Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle)),
                const SizedBox(width: 7),
                const Text('LIVE', style: TextStyle(fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.w800)),
                const SizedBox(width: 10),
                Text(
                  '${(_remainingSeconds ~/ 60).toString().padLeft(2, '0')}:${(_remainingSeconds % 60).toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ]),
            ),
        ],
      ),
      body: _connecting
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _error != null && !_connected
              ? _CallError(message: _error!, onRetry: _connect, onBack: _endCall)
              : Column(
                  children: [
                    Expanded(
                      child: remoteParticipants.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.video_call_outlined, color: Colors.white54, size: 56),
                                  const SizedBox(height: 14),
                                  const Text('Waiting for the other participant…', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 6),
                                  const Text('Keep this screen open while they join.', style: TextStyle(color: Colors.white60, fontSize: 12)),
                                  if (localParticipant != null) ...[
                                    const SizedBox(height: 22),
                                    SizedBox(
                                      width: 150,
                                      height: 190,
                                      child: _ParticipantVideo(participant: localParticipant, local: true),
                                    ),
                                  ],
                                ],
                              ),
                            )
                          : GridView.builder(
                              padding: const EdgeInsets.all(12),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: remoteParticipants.length == 1 ? 1 : 2,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: 0.85,
                              ),
                              itemCount: remoteParticipants.length,
                              itemBuilder: (context, index) => _ParticipantVideo(participant: remoteParticipants[index]),
                            ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Text(_error!, style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12)),
                      ),
                    SafeArea(
                      top: false,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                        decoration: const BoxDecoration(color: Color(0xFF0E1B2D), border: Border(top: BorderSide(color: Color(0xFF26364A)))),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _CallControl(
                              icon: _microphoneEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
                              label: _microphoneEnabled ? 'Mute' : 'Unmute',
                              active: _microphoneEnabled,
                              onTap: _toggleMicrophone,
                            ),
                            _CallControl(
                              icon: _cameraEnabled ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                              label: _cameraEnabled ? 'Camera off' : 'Camera on',
                              active: _cameraEnabled,
                              onTap: _toggleCamera,
                            ),
                            _CallControl(
                              icon: Icons.call_end_rounded,
                              label: 'End call',
                              active: false,
                              danger: true,
                              onTap: _endCall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _ParticipantVideo extends StatelessWidget {
  const _ParticipantVideo({required this.participant, this.local = false});
  final Participant participant;
  final bool local;

  @override
  Widget build(BuildContext context) {
    VideoTrack? videoTrack;
    for (final publication in participant.videoTracks.values) {
      if (publication.track is VideoTrack && !publication.muted &&
          (local || publication.subscribed)) {
        videoTrack = publication.track as VideoTrack;
        break;
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (videoTrack != null)
            VideoTrackRenderer(videoTrack)
          else
            Container(
              color: const Color(0xFF17283D),
              child: Center(
                child: CircleAvatar(
                  radius: 30,
                  backgroundColor: const Color(0xFF29415F),
                  child: Text(
                    _initial(participant.name ?? participant.identity),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 10,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.58), borderRadius: BorderRadius.circular(20)),
              child: Text(
                (participant.name?.isNotEmpty == true ? participant.name! : participant.identity) + (local ? ' (You)' : ''),
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _initial(String value) => value.isEmpty ? '?' : value[0].toUpperCase();
}

class _CallControl extends StatelessWidget {
  const _CallControl({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final String label;
  final bool active;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        height: 54,
        width: 54,
        decoration: BoxDecoration(
          color: danger ? const Color(0xFFDC2626) : active ? const Color(0xFF1E3857) : const Color(0xFF334155),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
      const SizedBox(height: 7),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
    ]),
  );
}

class _CallError extends StatelessWidget {
  const _CallError({required this.message, required this.onRetry, required this.onBack});
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.videocam_off_outlined, color: Colors.white54, size: 48),
        const SizedBox(height: 14),
        Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 14)),
        const SizedBox(height: 18),
        FilledButton(onPressed: onRetry, child: const Text('Retry connection')),
        TextButton(onPressed: onBack, child: const Text('Back to session', style: TextStyle(color: Colors.white70))),
      ]),
    ),
  );
}
