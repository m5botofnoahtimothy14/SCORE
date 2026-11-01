import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../notifications/notification_service.dart';

class StartupCoordinator {
  static bool _started = false;
  static StreamSubscription<dynamic>? _authSubscription;

  static Future<void> ensureStarted() async {
    if (_started) return;
    _started = true;

    final client = Supabase.instance.client;
    if (client.auth.currentSession != null) {
      unawaited(NotificationService.registerCurrentDevice());
    }

    _authSubscription = client.auth.onAuthStateChange.listen((state) {
      if (state.session != null) {
        unawaited(NotificationService.registerCurrentDevice());
      }
    });
  }

  static Future<void> dispose() async {
    await _authSubscription?.cancel();
    _authSubscription = null;
    _started = false;
  }
}
