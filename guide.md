# TeachCross Android ADB + APK Install Guide

This guide covers the exact local workflow for connecting your Android phone to your computer over ADB, building the Flutter APK, and installing it on the device.

## 1) Enable developer mode on the phone

On the Android device:

1. Open Settings
2. Tap About phone
3. Tap Build number 7 times to enable Developer options
4. Go back to Settings
5. Open Developer options
6. Turn on:
   - USB debugging
   - Wireless debugging (if using Wi‑Fi)

## 2) Connect by USB first (most reliable)

On your local machine, open a terminal and run:

```bash
adb devices
```

If the phone is connected by USB, you should see a device listed like:

```bash
List of devices attached
XXXXXXXX device
```

If it shows `unauthorized`:

- accept the USB debugging prompt on the phone
- run the command again

If adb does not see the device:

```bash
adb kill-server
adb start-server
adb devices
```

## 3) Connect over Wi‑Fi (wireless ADB)

If you want to use wireless debugging, use the pairing data from your phone:

- Pairing code: `357568`
- Pairing IP:port: `192.168.1.48:46253`
- Device connection IP:port: `192.168.1.48:36337`

Run:

```bash
adb pair 192.168.1.48:46253 357568
adb connect 192.168.1.48:36337
adb devices
```

If the device appears in the output, the phone is successfully connected.

Useful checks:

```bash
adb shell getprop ro.product.model
adb shell getprop ro.product.brand
```

If pairing fails:

- make sure the phone and your PC are on the same Wi‑Fi network
- make sure Wireless debugging is enabled
- generate a fresh pairing code from the phone if needed

> Important: this must be done from your local computer, not from the remote container.

## 4) Build the Flutter APK

From your local machine, open a terminal in the mobile app folder:

```bash
cd /path/to/SCORE/apps/mobile
flutter pub get
flutter clean
```

Then build the release APK:

```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY \
  --dart-define=FIREBASE_API_KEY=YOUR_FIREBASE_API_KEY \
  --dart-define=FIREBASE_APP_ID=YOUR_FIREBASE_APP_ID \
  --dart-define=FIREBASE_SENDER_ID=YOUR_FIREBASE_SENDER_ID \
  --dart-define=FIREBASE_PROJECT_ID=YOUR_FIREBASE_PROJECT_ID
```

The APK is created at:

```bash
build/app/outputs/flutter-apk/app-release.apk
```

Optional ABI-split build:

```bash
flutter build apk --release --dart-define=SUPABASE_URL=https://pdnrloftybrhuwefmrhp.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9 --dart-define=FIREBASE_API_KEY=AIzaSyCtE6cWXQ9xZA0kNY1vp3-V_YwaEbV7szM --dart-define=FIREBASE_APP_ID=1:587525976197:android:a3bb2a844c3e8998d179ec --dart-define=FIREBASE_SENDER_ID=587525976197 --dart-define=FIREBASE_PROJECT_ID=teachcross-38f29



This produces device-specific APKs like:

- `app-arm64-v8a-release.apk`
- `app-armeabi-v7a-release.apk`

## 5) Install the APK on the phone

With the device connected:

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

If using split APKs:

```bash
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

If the app is already installed and the install is rejected:

```bash
adb uninstall com.teachcross.app
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

## 6) Launch the app

Package ID:

```text
com.teachcross.app
```

Start the app manually:

```bash
adb shell am start -n com.teachcross.app/com.teachcross.app.MainActivity
```

## 7) Useful debug commands

Check device visibility:

```bash
adb devices
```

Read recent logs:

```bash
adb logcat -d | tail -n 200
```

List installed packages:

```bash
adb shell pm list packages | grep teachcross
```

Check the installed path:

```bash
adb shell pm path com.teachcross.app
```

## 8) Vercel / web deployment note

The web admin app is in the repo under `apps/admin`. It builds successfully and is deployable to Vercel from a machine with Vercel auth.

This environment is not authenticated to Vercel, so the deployment itself must be done from a local machine with a valid login. The app code itself is ready for deployment once your Vercel project is configured with the required environment variables.

## 9) Required environment variables for the app

The app expects these values at runtime, typically in Vercel or local shell exports:

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `OPENAI_API_KEY`
- `APILAYER_API_KEY`
- `GOOGLE_CLOUD_VISION_API_KEY`
- `FCM_PROJECT_ID`
- `FCM_CLIENT_EMAIL`
- `TEXTBEE_API_KEY`
- `Firebase` values for Android push: `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_SENDER_ID`, `FIREBASE_PROJECT_ID`

## 10) Quick copy-paste workflow

```bash
adb pair 192.168.1.48:46253 357568
adb connect 192.168.1.48:36337
adb devices

cd /path/to/SCORE/apps/mobile
flutter pub get
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY \
  --dart-define=FIREBASE_API_KEY=YOUR_FIREBASE_API_KEY \
  --dart-define=FIREBASE_APP_ID=YOUR_FIREBASE_APP_ID \
  --dart-define=FIREBASE_SENDER_ID=YOUR_FIREBASE_SENDER_ID \
  --dart-define=FIREBASE_PROJECT_ID=YOUR_FIREBASE_PROJECT_ID

adb install -r build/app/outputs/flutter-apk/app-release.apk
adb shell am start -n com.teachcross.app/com.teachcross.app.MainActivity
```

## Final note

This repo’s mobile app is designed for Android first, and the admin app is the web dashboard for schools. For physical device testing, the local machine must be used for ADB and APK installation; the remote environment cannot reach your phone over the same local network path.
