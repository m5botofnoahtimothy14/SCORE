# TeachCross Mobile (Flutter)

Secure school communication client for students and teachers
(Android first; architecture supports a future iOS release).

## Prerequisites

- Flutter 3.24+ (`flutter --version`)
- A Supabase project with migrations in `supabase/` applied
- Firebase project for push notifications (Android)

## Configure

All secrets are injected at build time via `--dart-define`. Nothing is
hardcoded and nothing is committed.

```sh
flutter pub get
```

## Run (development)

```sh
flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key> \
  --dart-define=FIREBASE_API_KEY=<key> \
  --dart-define=FIREBASE_APP_ID=<app-id> \
  --dart-define=FIREBASE_SENDER_ID=<sender-id> \
  --dart-define=FIREBASE_PROJECT_ID=<project-id>
```

Without `FIREBASE_*` values the app runs but push stays disabled with a
truthful status in Notification Settings (no fake success).

## Build (release APK / AAB)

```sh
flutter build apk --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... [FIREBASE_*...]
flutter build appbundle --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... [FIREBASE_*...]
```

Firebase setup: add `android/app/google-services.json` from the Firebase
console (not committed), apply the Google Services plugin in
`android/app/build.gradle`, and confirm the `POST_NOTIFICATIONS`
permission + channels (`messages`, `announcements`, `priority_alerts`,
`admin_alerts`) in the manifest.

Generate the Android project (once) with:

```sh
flutter create --platforms=android . --project-name teachcross_mobile --org com.teachcross
```

Then ensure `android/app/src/main/AndroidManifest.xml` contains:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<application ...>
    <service android:name="com.google.firebase.MESSAGING_EVENT"
        android:exported="false">
        <intent-filter>
            <action android:name="com.google.firebase.MESSAGING_EVENT"/>
        </intent-filter>
    </service>
    <meta-data android:name="com.google.firebase.messaging.default_notification_channel_id"
        android:value="messages"/>
</application>
```

Notification channels themselves are created at runtime by
`NotificationService.initialize` (see
`lib/core/notifications/notification_service.dart`).

## Analyze / format

```sh
flutter analyze
dart format lib
```

## Notes

- Students sign in with school-issued Student ID + activation code
  (verified server-side; no email/phone needed).
- Teachers verify Staff ID + phone via SMS OTP (real provider required).
- No public admin entry point exists in this app — administration is
  exclusively in `apps/admin`.
