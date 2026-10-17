# TeachCross Architecture

## System map

```
apps/mobile  (Flutter, students + teachers)
    │  Supabase Auth (anonymous→activated, OTP) · PostgREST (RLS) ·
    │  Realtime (RLS-gated) · Storage signed URLs · FCM
    ▼
Supabase project
    ├─ PostgreSQL + RLS (00001–00008 migrations)
    ├─ Edge Functions: activate-student, send-otp, verify-otp,
    │   publish-announcement, moderate-message, moderate-image,
    │   dispatch-notifications
    └─ Realtime publication (supabase_realtime)

apps/admin   (Next.js DMS, platform_owner / school_admin / principal)
    ├─ Server-gated routes (middleware + layout + getAdminContext)
    ├─ API: /api/health, /api/activation-code (service-role, server only)
    └─ All mutations audited
```

## Trust boundaries

- The client (mobile or browser) is **untrusted**: role, school_id,
  class_id, sender_id from the client are never authoritative.
- Authorization lives in **RLS policies** (`00005`) and **SECURITY
  DEFINER functions** (`00006`–`00008`): `send_message`,
  `activate_student/teacher`, `issue_student_code`, `reassign_student_class`.
- Secrets (service-role key, FCM key, SMS keys, moderation keys) exist
  **only** in edge functions and DMS server routes.
- Push payloads carry **no message content** — generic text + deep-link
  data; content loads after authentication.

## Key flows

- **Student activation**: anonymous auth → `activate-student` edge fn →
  `activate_student()` verifies roster + code hash (crypt or SHA-256),
  links user, creates membership, resolves class, opens support room.
- **Teacher activation**: `send-otp` (hashed OTP, rate-limited) →
  `verify-otp` → `activate_teacher()` checks roster phone match.
- **Messaging**: `send_message()` RPC (membership + can_send +
  class-channel student block + idempotency) → row starts
  `pending_moderation` → `moderate-message` webhook approves/holds →
  notification jobs → `dispatch-notifications` → FCM.
- **Images**: private `attachments` bucket → `pending_scan` →
  `moderate-image` (Vision) → approved/quarantined/rejected. RLS keeps
  unscanned files invisible.
- **Announcements**: `publish-announcement` edge fn (role + audience
  checks) → recipient resolution → receipts + notification jobs.
- **Fail-closed moderation**: missing/failed provider ⇒ held/quarantined,
  never approved.

## Multi-tenancy

Every school-owned row carries `school_id`. RLS helpers
(`user_school_ids`, `is_school_admin`, `is_conversation_member`) scope
every read; cross-school access is denied at the database, not the UI.
