# TeachCross — School Communication Platform

Secure, school-managed communication for educational institutions:
Flutter app for students/teachers + Next.js DMS for administrators,
Supabase backend (Postgres + Auth + Realtime + Storage + Edge Functions),
FCM push, and a fail-closed safeguarding pipeline.

## Repository

- `apps/mobile/` — Flutter Android/iOS client (see its README for
  `--dart-define` build commands)
- `apps/admin/` — Next.js 14 DMS (`npm run dev|build|typecheck|lint`)
- `supabase/migrations/` — 00001–00008 (schema, RLS, helpers, storage,
  SHA-256 activation codes)
- `supabase/functions/` — 7 edge functions (auth, messaging, moderation,
  announcements, dispatch)
- `supabase/seed.dev.sql` — dev fixtures (**never run in production**)
- `packages/contracts/` — shared TypeScript contracts
- `tests/` — 49 unit + security-mirror tests (`npm test`) + live RLS
  checklist (`tests/rls_checks.sql`)
- `docs/` — SETUP, ARCHITECTURE, SECURITY, API, OPERATIONS, TESTING
- `scripts/bootstrap.mjs` — one-time platform-owner provisioning
  (refuses re-runs)

## Verify

```sh
npm test                    # 49 pass
npm run typecheck:admin     # clean
npm run typecheck:contracts # clean
```

Docs/TESTING.md records what was verified here vs what still requires a
live backend, real provider keys, and physical-device runs.
