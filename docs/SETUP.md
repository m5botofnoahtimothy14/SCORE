# TeachCross Setup (development → staging → production)

## 1. Prerequisites

- Node 20+, Flutter 3.24+ (mobile), Supabase CLI, Postgres client
- Firebase project (Android push), OpenAI key (text moderation),
  Google Cloud Vision key (image safety), MSG91 or Twilio (teacher OTP)

## 2. Supabase backend

```sh
supabase link --project-ref <ref>
supabase db push            # applies 00001–00008
psql "$DATABASE_URL" -f supabase/seed.dev.sql   # DEV ONLY
supabase functions deploy activate-student send-otp verify-otp \
  publish-announcement moderate-message moderate-image dispatch-notifications
supabase secrets set \
  INTERNAL_WEBHOOK_SECRET=<random> OPENAI_API_KEY=<k> \
  GOOGLE_CLOUD_VISION_API_KEY=<k> FCM_SERVER_KEY=<k> FCM_PROJECT_ID=<id> \
  MSG91_AUTH_KEY=<k> MSG91_OTP_TEMPLATE_ID=<id>
# Enable in Dashboard: Auth → Anonymous sign-ins; Storage buckets exist via migration.
```

## 3. Bootstrap the first admin (one time)

```sh
BOOTSTRAP_ENABLED=true BOOTSTRAP_ADMIN_EMAIL=you@school.edu \
BOOTSTRAP_ADMIN_PASSWORD='<16+ chars>' BOOTSTRAP_SCHOOL_NAME='Demo School' \
BOOTSTRAP_SCHOOL_CODE=DEMO node scripts/bootstrap.mjs
# Script refuses to run twice. Unset BOOTSTRAP_ENABLED afterwards.
```

## 4. Admin DMS

```sh
cd apps/admin
cp ../../.env.example .env.local   # fill NEXT_PUBLIC_* + SUPABASE_SERVICE_ROLE_KEY
npm install
npm run typecheck
npm run dev     # http://localhost:3000 → /auth/login
npm run build && npm start          # production
```

## 5. Mobile app

```sh
cd apps/mobile
flutter pub get
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
# + FIREBASE_* defines for push; without them push stays disabled (truthful).
flutter build apk --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

## 6. Tests

```sh
npm test                                   # 49 unit + security-mirror tests
psql "$DATABASE_URL" -f tests/rls_checks.sql   # live RLS checks (staging)
```

## 7. Environment matrix

| Variable | Where | Secret? |
|---|---|---|
| SUPABASE_URL / ANON_KEY | everywhere | no (anon is public) |
| SUPABASE_SERVICE_ROLE_KEY | edge fns, DMS server | **yes** |
| INTERNAL_WEBHOOK_SECRET | edge fns | **yes** |
| OPENAI_API_KEY / VISION key | edge fns | **yes** |
| FCM_* | edge fns | **yes** |
| MSG91_* / TWILIO_* | edge fns | **yes** |
| FIREBASE_* dart-define | mobile build | no (public config) |

Separate Supabase projects + Firebase projects for dev/staging/prod.
