# TeachCross — Keys & Credentials Checklist

Everything below is needed for a production deployment. Demo (local
the full feature set. Nothing here is committed — the live values live in
`apps/admin/.env.local` (git-ignored).

## Environment variable reference (all vars, by location)

**Admin DMS — `apps/admin/.env.local`** (create this file; never commit):
```
NEXT_PUBLIC_SUPABASE_URL=...
NEXT_PUBLIC_SUPABASE_ANON_KEY=...
SUPABASE_SERVICE_ROLE_KEY=...        # server-only, used by API routes
```

**Edge-function secrets** (set with `supabase secrets set --project-ref <ref>`):
```
INTERNAL_WEBHOOK_SECRET=...          # long random string (see §6)
OPENAI_API_KEY=sk-...                # text AND image moderation (omni-moderation)
APILAYER_API_KEY=...                 # optional image-moderation fallback
TEXTBEE_API_KEY=...                  # SMS OTP (primary)
TEXTBEE_DEVICE_ID=...                # optional; defaults to the account's first device
FCM_PROJECT_ID=...                   # push dispatch (Firebase project id)
FCM_CLIENT_EMAIL=...                 # service-account email (FCM HTTP v1)
FCM_PRIVATE_KEY=...                  # service-account private key (PEM)
DEMO_OTP=123456                      # DEV ONLY — skips real SMS. UNSET for production.
```
> Moderation and dispatch are triggered by Postgres (`supabase/migrations/00015`)
> via `pg_net`; the shared secret must also be stored in Supabase Vault as
> `internal_webhook_secret` (see §6).

**Mobile build-time** (`flutter run/build --dart-define`):
```
SUPABASE_URL=...
SUPABASE_ANON_KEY=...                # anon key only — never service_role
```


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
  Add Android app (package `com.teachcross.app`).
- **You give us**:
  - `google-services.json` (goes to `apps/mobile/android/app/`, never committed)
  - `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_SENDER_ID`, `FIREBASE_PROJECT_ID`
    (for `--dart-define` mobile builds)
  - FCM HTTP v1 service-account fields → `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL`,
    `FCM_PRIVATE_KEY` secrets for the `dispatch-notifications` function.
- **Used for**: push delivery + Android channels (already coded).

## 3. OpenAI API key (REQUIRED for auto text moderation)

- **Where**: https://platform.openai.com/api-keys
- **You give us**: `OPENAI_API_KEY` → set as edge-function secret.
- **Without it**: messages are held for human review (fail-closed, by design).

## 4. Image moderation (OPTIONAL — OpenAI covers it)

- **Primary**: reuse `OPENAI_API_KEY` (`omni-moderation-latest` accepts image
  input). No extra key needed.
- **Fallback only**: APILayer Nudity Detection (`APILAYER_API_KEY`) — requires
  an active subscription on that product at https://apilayer.com. A key with no
  subscription returns `403 You cannot consume this service`.
- **Without either**: images are quarantined for manual review (never approved).

## 5. SMS provider (REQUIRED for real teacher OTP)

- **Where**: https://textbee.dev (cloud or self-hosted) → create an API key,
  then pair at least one Android device as an SMS gateway.
- **You give us**: `TEXTBEE_API_KEY` (+ optional `TEXTBEE_DEVICE_ID`).
- **Important**: the key alone is not enough — `GET /gateway/devices` must list
  a paired device, otherwise no SMS is sent. With `DEMO_OTP` set, OTP is fixed
  to the demo value and no SMS is sent (dev only).

## 6. Webhook secret (we generate)

- `INTERNAL_WEBHOOK_SECRET`: any long random string; set once via
  `supabase secrets set`. Guards the internal moderation/dispatch calls.
- Mirror the SAME value into Supabase Vault so the DB triggers can authenticate:
  ```sql
  select vault.create_secret('<same random string>', 'internal_webhook_secret',
    'Shared secret for internal edge-function calls');
  ```
  (or `select vault.update_secret(id, '<value>')` if it already exists).

## Summary table

| Key | Demo? | Production? | Falls back safely? |
|---|---|---|---|
| Supabase URL/anon/service_role | yes | yes | n/a (core) |
| Firebase app + FCM | optional | yes (push) | push disabled, truthful status |
| OpenAI | optional | yes (text + image mod) | held / quarantined |
| APILayer (image fallback) | optional | optional | quarantined |
| TextBee | optional | yes (teacher OTP) | explicit error (or DEMO_OTP) |

Until keys arrive, the app and DMS run in degraded-but-honest modes and
`/dashboard/health` shows exactly what is configured.
