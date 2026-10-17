# TeachCross — Keys & Credentials Checklist

Everything below is needed for a production deployment. Demo (local
device + Supabase Cloud free project) needs only item 1; the rest unlock
the full feature set. Nothing here is committed — see `.env.example`.

## 1. Supabase project (REQUIRED — backend, demo + prod)

- **Where**: https://supabase.com → New project (free tier works for demo).
- **You give us**: `Project URL`, `anon public key`, `service_role key`
  (Project Settings → API), plus the `Project ref` for CLI linking.
- **Used for**: Postgres (migrations `supabase/migrations/00001–00008`),
  Auth, Realtime, Storage, Edge Functions.
- **We run**: `supabase link --project-ref <ref>` → `supabase db push`
  → `supabase functions deploy ...` → `supabase secrets set ...` →
  `node scripts/bootstrap.mjs` (first admin) → DMS + mobile builds with
  your URL/anon key.

## 2. Firebase (REQUIRED for push on real devices)

- **Where**: https://console.firebase.google.com → create project →
  Add Android app (package `com.teachcross.teachcross_mobile`).
- **You give us**:
  - `google-services.json` (goes to `apps/mobile/android/app/`, never committed)
  - `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_SENDER_ID`, `FIREBASE_PROJECT_ID`
    (for `--dart-define` mobile builds)
  - `FCM_SERVER_KEY` or service-account JSON (entered as
    `FCM_SERVER_KEY` secret for the `dispatch-notifications` function)
- **Used for**: push delivery + Android channels (already coded).

## 3. OpenAI API key (REQUIRED for auto text moderation)

- **Where**: https://platform.openai.com/api-keys
- **You give us**: `OPENAI_API_KEY` → set as edge-function secret.
- **Without it**: messages are held for human review (fail-closed, by design).

## 4. Google Cloud Vision key (REQUIRED for auto image safety)

- **Where**: Google Cloud Console → enable Vision API → API key.
- **You give us**: `GOOGLE_CLOUD_VISION_API_KEY` → edge-function secret.
- **Without it**: uploads stay quarantined until a reviewer approves.

## 5. SMS provider (REQUIRED for teacher OTP login)

- **Option A (India)**: https://msg91.com → `MSG91_AUTH_KEY` +
  `MSG91_OTP_TEMPLATE_ID` (DLT-approved OTP template).
- **Option B (global)**: https://twilio.com → `TWILIO_ACCOUNT_SID` +
  `TWILIO_AUTH_TOKEN` + `TWILIO_FROM_NUMBER`.
- **Without it**: teacher OTP requests fail with an explicit
  "SMS service not configured" error (no fake codes, ever).

## 6. Webhook secret (we generate)

- `INTERNAL_WEBHOOK_SECRET`: any long random string; set once via
  `supabase secrets set`. Guards the moderation/dispatch webhooks.

## Summary table

| Key | Demo? | Production? | Falls back safely? |
|---|---|---|---|
| Supabase URL/anon/service_role | yes | yes | n/a (core) |
| Firebase app + FCM | optional | yes (push) | push disabled, truthful status |
| OpenAI | optional | yes (auto-mod) | held for review |
| Vision | optional | yes (auto image) | quarantined |
| MSG91/Twilio | optional | yes (teacher OTP) | explicit error |

Until keys arrive, the app and DMS run in degraded-but-honest modes and
`/dashboard/health` shows exactly what is configured.
