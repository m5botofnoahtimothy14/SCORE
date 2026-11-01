# SCORE+ deployment configuration

This document lists configuration required by the application code. It contains variable names only. Do not commit secret values.

## Admin web

Vercel project settings:

- Root Directory: `apps/admin`
- Framework: Next.js
- Node.js runtime: 24.x
- Preview deployment protection: enabled
- Production domain: retain the existing project domain until a new SCORE+ domain is assigned

Required Vercel environment variables:

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`

The service-role key must be available only to server-side code. Never expose it through a `NEXT_PUBLIC_` variable.

## Supabase Edge Functions

The functions use the existing Supabase project URL and keys. Set the following secrets in the Supabase Edge Function environment:

### FCM notification delivery

- `FCM_PROJECT_ID`
- `FCM_CLIENT_EMAIL`
- `FCM_PRIVATE_KEY`

The private key must remain server-side. Store it as a secret. Do not place it in Flutter, Next.js client bundles, or Git.

### Internal notification dispatch

- `INTERNAL_WEBHOOK_SECRET`

Use the same strong random secret for the internal call from `publish-announcement` to `dispatch-notifications`. Do not use the Supabase anon key as this secret.

### In-app mentor calls

- `LIVEKIT_URL` — secure `wss://` endpoint for the SCORE+ LiveKit service
- `LIVEKIT_API_KEY`
- `LIVEKIT_API_SECRET`

The API secret is used only by `issue-video-token`. The Flutter app receives short-lived participant tokens. It must never receive the LiveKit API secret.

## Flutter application

The mobile application now uses `livekit_client` for in-app audio/video calls.

After changing `apps/mobile/pubspec.yaml`, resolve packages before building:

```bash
cd apps/mobile
flutter pub get
```

The project requires Dart SDK 3.10 or later. Android camera and microphone permissions and iOS usage descriptions are included in the application manifests.

Firebase configuration is still required for push notifications:

- Android: Firebase configuration for the Android application
- iOS: Firebase configuration and APNs setup
- Both: FCM service account credentials in the Supabase Edge Function environment

## Deployment order

1. Apply and verify the Supabase migrations.
2. Set Supabase Edge Function secrets.
3. Deploy the Edge Functions.
4. Resolve Flutter dependencies and build the mobile app.
5. Deploy the Next.js admin/public website from the `apps/admin` root.
6. Run the integration and device tests.

No database migration or production database change was made by the code-recovery pull request.
