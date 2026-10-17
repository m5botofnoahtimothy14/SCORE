# TeachCross Testing Plan & Evidence

## Automated (run in CI)

```sh
npm test                                   # 49 tests, must all pass
npm run typecheck:admin                    # next.js tsc
npm run typecheck:contracts                # shared contracts tsc
```

`tests/` covers: input validation, moderation thresholds + fail-closed
provider behavior, sliding-window rate limits + retry-resistance,
idempotency, announcement targeting/permissions, and all 18 §14.3 negative
security cases at the authorization-decision layer
(`tests/helpers/*.mjs` mirror the RLS/RPC/edge rules).

## Live-backend checks (staging, before release)

```sh
supabase db push && psql "$DATABASE_URL" -f supabase/seed.dev.sql
psql "$DATABASE_URL" -f tests/rls_checks.sql   # execute numbered checks
```

Record the outcome table below per release.

| # | Check | Expected | Result (date/initials) |
|---|---|---|---|
| 1 | Student selects students table | exactly 1 row (self) | |
| 2 | Student selects other school classes | 0 rows | |
| 3 | Insert message in foreign conversation | RLS error | |
| 4 | Insert with forged sender_id | RLS error | |
| 5 | UPDATE/DELETE audit_events as app role | 0 rows / error | |
| 6 | Teacher reads unassigned student | 0 rows | |
| 7 | Student selects announcements | only own recipient rows | |
| 8 | Anonymous GET on private attachment | 403/404 | |

## End-to-end journeys (staging, isolated test accounts)

- **Student**: activate → class auto-assigned → support room opens → send
  → teacher receives → peer cannot see → announcement ack recorded.
- **Teacher**: OTP → assigned classes visible → reply → authorized
  announcement publishes; school-wide attempt rejected.
- **Admin**: roster import (valid + error rows) → assignments → codes →
  publish → delivery/ack inspection → suspend → access revoked.
- **Security**: cross-school, impersonation, prohibited messaging, file
  retrieval, moderation bypass attempts — all rejected + audit entries.

## Real-device matrix (physical Android before production)

Sign-in/enrollment; realtime send/receive; image upload + review wait;
voice note record/playback; foreground + background push; deep-link
tap-through; airplane-mode recovery; session expiry; suspended account;
unauthorized-access attempts. Log results here per release.

## Evidence (2026-10-16, this workspace)

- `npm test`: **49 pass / 0 fail** (validation 6, moderation 6,
  ratelimit/idempotency 4, messaging 8, announcements 6, security 18).
- `tsc --noEmit` (apps/admin): **0 errors**. contracts: **0 errors**.
- `next build` (apps/admin): **success, 15 routes**.
- `flutter analyze` (apps/mobile): **No issues found**.
- `flutter test` (apps/mobile): **2 pass** (config fail-fast unit tests).
- `flutter build apk --debug`: **success** (`app-debug.apk`, ~159 MB).
- Emulator run (Pixel 7, API 35, headless, placeholder backend): app
  installs, launches, renders the real school-select screen and shows the
  truthful offline/error state with retry — no crash, no fake data.
  Screenshot: `D:\dev\downloads\teachcross_first_run.png`.
- Physical-device matrix and provider-backed push: **still require**
  a device + keys (see below).
- Emulator run (Galaxy_S24 Samsung frame, Play image, Private-DNS fix,
  **live Supabase backend**): **"Demo Public School — New Delhi, Delhi"
  renders from the real project** (verified via screenshot).
- Pre-prod backend: **9/9 migrations pushed**, **7/7 edge functions
  deployed** (activate-student, verify-otp, publish-announcement
  JWT-enforced), seed + platform-owner bootstrap + S1001 activation
  code issued. Fixes made along the way: `gen_random_uuid()` instead of
  `uuid-ossp`, RLS helpers moved from `auth.*` to `public.tc_*`
  (no permission to create in `auth` schema), `//` comments fixed in
  00008, public `public_schools` directory view added for
  pre-session school discovery.
- Still pending: provider keys (OpenAI/Vision/MSG91/FCM) — features
  fail closed without them; rotate service_role + revoke the setup
  PAT (both passed through chat).
