// Firebase options — values injected at build time via --dart-define.
// NEVER hardcode API keys. Example:
//   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... \
//     --dart-define=FIREBASE_API_KEY=... --dart-define=FIREBASE_APP_ID=... \
//     --dart-define=FIREBASE_PROJECT_ID=... --dart-define=FIREBASE_SENDER_ID=...
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    const apiKey = String.fromEnvironment('FIREBASE_API_KEY', defaultValue: '');
    const appId = String.fromEnvironment('FIREBASE_APP_ID', defaultValue: '');
    const messagingSenderId = String.fromEnvironment('FIREBASE_SENDER_ID', defaultValue: '');
    const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: '');
    if (apiKey.isEmpty || appId.isEmpty || messagingSenderId.isEmpty || projectId.isEmpty) {
      throw UnsupportedError(
        'Firebase is not configured. Rebuild with --dart-define=FIREBASE_API_KEY=... '
        'FIREBASE_APP_ID=... FIREBASE_SENDER_ID=... FIREBASE_PROJECT_ID=... '
        'See apps/mobile/README.md. Push notifications stay disabled until configured.',
      );
    }
    return const FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
    );
  }
}
