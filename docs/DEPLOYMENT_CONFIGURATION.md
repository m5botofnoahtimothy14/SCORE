# SCORE+ deployment configuration

This document lists configuration required by the application code. It contains variable names only. Never commit secret values.

## Admin web

Vercel project settings:
- Root Directory: `apps/admin`
- Framework: Next.js
- Node.js runtime: 24.x
- Preview deployment protection: enabled

Required Vercel environment variables:
- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`

The service-role key must remain server-side. Never expose it through a `NEXT_PUBLIC_` variable.

## Google Workspace / Google Meet

Each school connects its own paid Google Workspace account. The integration does not use one global refresh token.

Enable the Google Calendar API and Google Meet REST API in the Google Cloud project used by SCORE+. Configure the OAuth consent screen with these scopes:
- `openid`
- `email`
- `https://www.googleapis.com/auth/calendar.events`
- `https://www.googleapis.com/auth/meetings.space.created`

The school administrator connects the Workspace account from **Admin Dashboard → Mentor Desk → Google Workspace**. SCORE+ stores the refresh token in Supabase Vault. The public configuration table stores only the Vault secret ID. Never put refresh tokens in app code, normal tables, browser storage, Vercel client variables, or Git.

Required Supabase Edge Function secrets:
- `GOOGLE_CLIENT_ID`
- `GOOGLE_CLIENT_SECRET`
- `GOOGLE_REDIRECT_URI` — exact URL of the `google-workspace-oauth` Edge Function
- `GOOGLE_OAUTH_STATE_SECRET` — long random secret used to sign OAuth state
- `SCORE_ADMIN_URL` — trusted HTTPS origin of the SCORE+ admin website

The redirect URI must exactly match the URI registered in the Google Cloud OAuth client.

### School setup

1. A school administrator signs in to the SCORE+ admin website.
2. Open **Mentor Desk → Google Workspace** and select **Connect Google Workspace**.
3. Sign in with the school's Workspace account and approve the requested scopes.
4. Set the school's Calendar ID and IANA time zone. Use `primary` for the connected account's primary calendar.
5. Confirm that each assigned teacher has an active record with a School ID in `teachers.staff_id_no` and the correct Workspace email in `teachers.email`.

The connected Workspace account owns the Calendar event and Meet space. SCORE+ creates a restricted Meet space with moderation enabled. It adds only the assigned teacher's roster email as a co-host. It does not add a student email or send the meeting link by email. The student signs in with School ID and receives the link inside the booked session screen. The teacher admits the student from the Meet waiting room.

The meeting URL is stored in the separate `session_google_meet_links` table. Its row-level security policy permits reads only by the booked student and assigned teacher while the booking is confirmed or in progress. The URL is not stored in the ordinary booking row. Do not reuse a meeting link between bookings.

## Other Supabase Edge Function secrets

Existing notification functions may still require:
- `FCM_PROJECT_ID`
- `FCM_CLIENT_EMAIL`
- `FCM_PRIVATE_KEY`
- `INTERNAL_WEBHOOK_SECRET`

Keep all private keys and webhook secrets server-side.

## Flutter application

The mobile app opens Google Meet in the system browser or installed Meet app through `url_launcher`. It does not use LiveKit for Mentor Desk sessions.

After changing `apps/mobile/pubspec.yaml`, resolve packages:
```bash
cd apps/mobile
flutter pub get
```

Firebase configuration is still required for push notifications and APNs on iOS.

## Database migration and deployment order

Migrations `00027`–`00033` add the redesigned school and Mentor Desk schema, activation credential hardening, Google Workspace integration, and production access boundaries.

- `00032_google_workspace_meet.sql` adds school Workspace settings, Vault-backed credential references, meeting-space identifiers, server-only meeting creation claims, and participant-only meeting-link retrieval.
- `00033_production_security_boundaries.sql` removes client access to activation hashes and OTP records, restricts sensitive `SECURITY DEFINER` functions, and restores participant-only booking reads. It also hardens notification-device registration.
- `supabase/tests/00033_security_boundaries.sql` contains SQL regression checks. Run it in a non-production test project after the migration.

**Database drift warning:** the live project migration history was checked. It currently records migrations through `00026`, while this repository contains `00027`–`00033`. The live schema already contains some objects from later work, so migration history alone does not prove which DDL is safe to apply. Do not run a blind production `supabase db push`. First compare every migration with the live schema, resolve duplicate migration-history entries, and prepare a reviewed baseline or forward-only reconciliation plan. Preserve all existing records.

### Activation account behaviour

The student and teacher activation Edge Functions verify one-time codes through service-role-only database RPCs. After successful activation, they set a password-backed Supabase account using a device-generated secret. The synthetic `.invalid` email is an account identifier, not a mailbox. The mobile app stores the credential in the platform keystore. If a user loses the device credential, the school must issue a fresh activation code through the approved admin process. Duplicate IDs across schools are rejected rather than resolved to an arbitrary school.

After migration history is reconciled:
1. Apply and verify migrations in a development Supabase project.
2. Run `supabase/tests/00033_security_boundaries.sql` and the application test suites.
3. Set Google OAuth, notification, and internal webhook secrets.
4. Deploy the activation, OTP, notification, AI, and Google Workspace Edge Functions from the reviewed release.
5. Connect a test school's Workspace account.
6. Test activation, returning-device sign-in, 15-minute and 30-minute bookings, OTP closure, and participant-only Meet access with separate student and teacher accounts.
7. Run `flutter pub get`, build the app, and test on Android and iOS.
8. Build and deploy the Next.js admin website after its checks pass.

No production migration, Edge Function deployment, or Vercel deployment was performed by this recovery branch.
