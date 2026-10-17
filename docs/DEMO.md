# TeachCross Demo Mode (real backend, free tier)

Demo = the **real app** against a **real Supabase Cloud free project**
seeded with Demo Public School. No mocks, no fake data — the same code
paths as production, just with demo keys/data.

## What you (school owner) do — ~10 minutes

1. Create a free project at https://supabase.com → note:
   - Project URL, `anon` key, `service_role` key (Settings → API)
   - Project ref (URL subdomain, e.g. `xyzabc123`).
2. Hand those four values to your engineer (or paste them into
   `.env.example`-style notes — never commit them).

## What the engineer runs (Supabase CLI is at `D:\dev\npm-global\supabase.cmd`)

```powershell
cd "D:\Teachcross APP"
supabase link --project-ref <ref>            # first time: supabase login
supabase db push                             # applies 00001–00008
supabase functions deploy activate-student send-otp verify-otp `
  publish-announcement moderate-message moderate-image dispatch-notifications
supabase secrets set INTERNAL_WEBHOOK_SECRET=<random> `
  OPENAI_API_KEY=<k> GOOGLE_CLOUD_VISION_API_KEY=<k> `
  FCM_SERVER_KEY=<k> FCM_PROJECT_ID=<id> `
  MSG91_AUTH_KEY=<k> MSG91_OTP_TEMPLATE_ID=<id>
psql "$DATABASE_URL" -f supabase/seed.dev.sql   # or paste seed in SQL editor
# First admin (one time — refuses to run twice):
BOOTSTRAP_ENABLED=true BOOTSTRAP_ADMIN_EMAIL=you@school.edu `
BOOTSTRAP_ADMIN_PASSWORD='<16+ chars>' BOOTSTRAP_SCHOOL_NAME='Demo Public School' `
BOOTSTRAP_SCHOOL_CODE=DEMO node scripts/bootstrap.mjs
```

No-CLI fallback: paste `supabase/combined_schema.sql` into the Dashboard
SQL editor, then `supabase/seed.dev.sql`. (Edge functions still need the
CLI to deploy.)

## Point the clients at it

```powershell
# Android (Galaxy_S24 emulator booted, DNS already fixed via Private DNS)
flutter run --dart-define=SUPABASE_URL=<url> --dart-define=SUPABASE_ANON_KEY=<anon>
# Admin DMS
cd apps/admin
# .env.local: NEXT_PUBLIC_SUPABASE_URL=<url>, NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon>,
#            SUPABASE_SERVICE_ROLE_KEY=<service_role>
npm run dev   # http://localhost:3000/auth/login
```

## Demo script (works without SMS/FCM/moderation keys)

1. DMS → Students → pick `S1001` → **Issue code** (shown once).
2. App → select Demo Public School → Student → ID `S1001` + code →
   auto-assigned to Grade 8-A, Teacher Support room opens.
3. Send a message (held→approved needs OpenAI key; without it, it waits
   in `held_for_review` — approve it in DMS → Moderation to continue).
4. DMS → Announcements → publish class notice → app receives it →
   acknowledge → DMS shows the ack.
5. DMS → Students → deactivate S1001 → app loses access (session check).

Teacher OTP needs MSG91/Twilio keys even for demo; until then, link a
demo teacher directly in SQL (documented demo-only step, audited).
