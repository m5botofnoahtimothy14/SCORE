import 'dart:async';

import 'package:flutter/material.dart';import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';

import 'core/config/app_config.dart';
import 'core/config/router.dart';
import 'core/legal/eula_gate.dart';
import 'core/notifications/notification_service.dart';
import 'core/startup/startup_coordinator.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';

final FlutterLocalNotificationsPlugin localNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// Background FCM handler â€” must be top-level
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.showLocalNotification(message, localNotificationsPlugin);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Fail fast with a readable message if build-time config is missing.
  try {
    AppConfig.validate();
  } catch (e) {
    runApp(_ConfigErrorApp(message: e.toString()));
    return;
  }

  // Orientation is deliberately not locked: every screen reflows from 600px
  // up, so tablets and foldables get the extra width in landscape instead of
  // a stretched portrait layout. Phones simply render the compact layout.
  await SystemChrome.setPreferredOrientations(DeviceOrientation.values);

  // Read the EULA acceptance before the first frame so the consent gate
  // never flashes over an already-consented user. A storage failure is
  // handled inside the store and simply asks again on next launch.
  await EulaStore.load();

  // Firebase is optional at runtime: without FIREBASE_* build defines the
  // app runs with push disabled and says so truthfully in settings.
  var pushEnabled = false;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    pushEnabled = true;
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('Firebase not configured â€” push notifications disabled: $e');
  }

  // Initialize local notifications (channels always; FCM only if ready)
  await NotificationService.initialize(localNotificationsPlugin, pushEnabled: pushEnabled);

  // Initialize Supabase
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      autoRefreshToken: true,
      persistSession: true,
    ),
    realtimeClientOptions: const RealtimeClientOptions(
      logLevel: RealtimeLogLevel.info,
    ),
  );

  runApp(
    const ProviderScope(
      child: SCOREApp(),
    ),
  );

  // The splash screen owns the boot sequence: it restores the session,
  // resolves the identity, registers the push token and starts the presence
  // heartbeat while the brand moment is on screen, so the first real screen
  // is already populated. The coordinator is idempotent, so calling it here
  // as well only matters if the splash is skipped.
  StartupCoordinator.ensureStarted();
}

class _ConfigErrorApp extends StatelessWidget {
  final String message;
  const _ConfigErrorApp({required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.settings_outlined, size: 64, color: Colors.orange),
                const SizedBox(height: 16),
                const Text(
                  'App not configured',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SCOREApp extends ConsumerWidget {
  const SCOREApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'SCORE+',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
