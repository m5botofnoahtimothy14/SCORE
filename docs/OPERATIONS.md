# TeachCross Operations (runbook)

## Daily

- Glance at DMS → Overview: pending moderation, open incidents, failed
  notifications. Failed jobs carry `failure_reason`; re-queue from
  Notifications after fixing the cause (usually FCM config).

## Provider outages (fail-closed behavior)

| Outage | Effect | Action |
|---|---|---|
| OpenAI down / key missing | messages held for review | review queue; restore key |
| Vision down / key missing | uploads quarantined, invisible | review attachments; restore key |
| FCM misconfigured | jobs fail, status visible | fix secrets, re-queue |
| SMS provider down | OTP requests get explicit error | fix provider, users retry |

## Database

- Migrations: `supabase db push` (ordered 00001–00008). Never edit an
  applied migration; add a new one (`CREATE OR REPLACE` for functions).
- Rollback: each migration is additive; to revert a function, redeploy the
  previous definition as a new migration. Snapshot before releases.
- Retention: `data_retention_policies` per school; purge jobs should
  soft-delete then hard-delete after a grace window (implement per school
  policy; audit the purge).

## Incident response

1. Open/assign a safeguarding incident in the DMS (restricted area only).
2. Keep notes and evidence links in the incident, not in chat/email.
3. Investigation access requires a request + platform approval + expiry.
4. Legal/escalation steps go in `legal_reference`; closure records the
   decision. Never copy sensitive material outside the system.

## Support tickets

Triage in DMS → Support: reproduce, fix at the school level (rosters,
assignments, codes) or escalate infra issues with correlation IDs from
failed jobs.

## Release checklist

1. `npm test` green; both typechecks green.
2. `tests/rls_checks.sql` on staging; journeys + device matrix logged.
3. `supabase db push` to prod; deploy edge functions; set secrets.
4. DMS `npm run build` green; deploy; verify `/api/health`.
5. Mobile release build with prod `--dart-define` values; staged rollout.
