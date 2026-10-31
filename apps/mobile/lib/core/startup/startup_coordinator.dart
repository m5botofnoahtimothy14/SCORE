import 'package:supabase_flutter/supabase_flutter.dart';

class StartupCoordinator {
  static bool _started = false;

  static Future<void> ensureStarted() async {
    if (_started) return;
    _started = true;

    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      // Session already restored by Supabase client
    }
  }
}