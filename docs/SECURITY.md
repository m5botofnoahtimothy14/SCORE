# TeachCross Security Model

## Principles

- **Never trust the client.** Role, school, class and sender identity are
  resolved server-side from `auth.uid()` on every privileged path.
- **RLS is the primary enforcement layer** (`00005_rls_policies.sql`);
  edge functions and DMS server code are the secondary gate.
- **Fail closed.** Missing/failed moderation, SMS or push providers disable
  the dependent capability with an explicit error — never silent approval.
- **Least privilege + audit.** Admin mutations write `audit_events`
  (append-only; no UPDATE/DELETE policy exists for app roles). Sensitive
  exports and investigation access are separately gated and logged.

## Authentication

- Students: anonymous Supabase session + server-verified roster/activation
  code (codes are single-use, expiring, hashed; errors are generic to block
  ID enumeration; attempts are rate-limited).
- Teachers: Staff-ID + registered-phone match + SMS OTP (hashed, expiring,
  attempt-counted, lockout). No provider ⇒ explicit
  `sms_provider_unavailable`, never a fake "sent".
- Admins: email + password in the DMS only, MFA recommended at the
  Supabase project level; no public registration; no admin entry in the app.
- Bootstrap (`scripts/bootstrap.mjs`) refuses re-runs once an owner exists.

## Permissions (enforced in Postgres, mirrored in `tests/helpers/authz.mjs`)

- Students: message only assigned teachers via existing conversations;
  cannot create groups, cannot message peers, cannot post in class
  channels, cannot publish announcements.
- Teachers: assigned classes only; class-scoped (not school-wide)
  announcements; priority alerts are admin-only.
- Attachments: uploader or approved+member (or admin); unapproved files
  are invisible to recipients.
- Tenancy: `school_id` on every row; cross-school reads/writes denied.
- Investigations: requested → platform-approved → time-limited → expired/
  revoked/closed; each access event recorded.

## Data protection

- Private Storage buckets; 5-minute signed URLs for reviewer previews.
- Push payloads contain no message content.
- No passwords, OTPs or tokens are logged; message bodies are not used for
  ads/profiling and never sent to AI providers except the configured
  moderation classifiers.
- Backups: Supabase PITR per project plan; test restores before depending
  on them. Credential rotation: rotate in provider dashboards, then
  `supabase secrets set` / DMS env, then verify via `/dashboard/health`.

## Review cadence

Run `npm test`, `tests/rls_checks.sql` (staging), and the TESTING.md
device matrix before every release. Review `audit_events` weekly.
