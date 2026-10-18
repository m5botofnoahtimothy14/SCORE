// Teacher presence heartbeat.
//
// `touch_my_presence()` stamps `teachers.last_seen_at` for the signed-in user.
// The app pings once on start and again whenever it returns to the foreground,
// so "Online" in the directory and the chat header means "seen in the last
// three minutes" rather than "ever logged in".
//
// Everything here is deliberately fire-and-forget: presence is a nicety, so a
// failed or slow ping must never delay startup, surface an error, or crash the
// app. The signed-in role is read straight from `school_memberships` (server
// enforced) rather than from a cached provider, so a stale cache can't make a
// student look like staff — and the RPC itself only updates the caller's own
// teacher row anyway.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PresenceService {
  PresenceService._();

  /// Membership roles that represent a teacher at the app level.
  static const Set<String> _teacherRoles = {'teacher', 'head_teacher'};

  /// How often to refresh while the app is in the foreground, so a teacher who
  /// keeps the app open does not silently fall back to "Offline".
  static const Duration _tick = Duration(minutes: 1);

  static bool _started = false;
  static Timer? _timer;

  /// Records that the signed-in teacher is online. Never throws and never
  /// awaits anything the caller cares about — call it and move on.
  static Future<void> pump() async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;

      // Role comes from the server, not from a cached provider.
      final rows = await client
          .from('school_memberships')
          .select('role')
          .eq('user_id', user.id)
          .eq('is_active', true);
      if (rows.isEmpty) return;

      var isTeacher = false;
      for (final r in rows) {
        final role = (r as Map)['role'] as String?;
        if (role != null && _teacherRoles.contains(role)) {
          isTeacher = true;
          break;
        }
      }
      if (!isTeacher) return;

      await client.rpc('touch_my_presence');
    } catch (e) {
      // Offline, signed out, or RPC unavailable — presence is best-effort.
      debugPrint('presence: heartbeat skipped: $e');
    }
  }

  /// Wires the heartbeat to the app lifecycle: one ping now, another every
  /// time the app resumes. Safe to call more than once.
  static void start() {
    if (_started) return;
    _started = true;

    WidgetsBinding.instance.addObserver(_observer);
    unawaited(pump());
    _startTimer();
  }

  static void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_tick, (_) => pump());
  }

  static void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  static final _observer = _PresenceLifecycle();
}

class _PresenceLifecycle extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // Re-ping immediately: the device may have been asleep for hours.
        unawaited(PresenceService.pump());
        PresenceService._startTimer();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        PresenceService._stopTimer();
    }
  }
}