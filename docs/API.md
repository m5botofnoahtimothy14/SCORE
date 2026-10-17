# TeachCross API Reference (edge functions + DMS API)

All edge functions require the Supabase anon key + user JWT unless noted.
Errors are `{ success: false, error: <code> }` (generic where enumeration
is a risk).

## POST /functions/v1/activate-student

Body: `{ school_id, student_id_no, activation_code }` (auth required).
200: `{ success: true, student_id, class_id }`.
Codes: `invalid_credentials` (generic), `rate_limited` (429).

## POST /functions/v1/send-otp

Body: `{ phone, school_id, staff_id_no }` (no auth; rate-limited 3/hr).
200: `{ success: true, expires_in_minutes: 10 }`.
Codes: `invalid_phone`, `invalid_credentials` (generic, timing-safe),
`rate_limited` (429), `sms_provider_unavailable` (503).

## POST /functions/v1/verify-otp

Body: `{ phone, otp, school_id, staff_id_no }` (auth required).
200: `{ success: true, teacher_id }`.
Codes: `invalid_otp`, `otp_expired`, `otp_already_used`,
`account_locked` (423), `activation_failed` (500).

## POST /functions/v1/publish-announcement

Body: `{ school_id, title, body, category, audience_type, class_id?,
requires_ack }` (auth required; role-gated server-side).
200: `{ success: true, announcement_id, recipient_count }`.
Teachers: class/staff/leadership only; `priority_alert` is admin-only.

## Internal webhooks (INTERNAL_WEBHOOK_SECRET required)

- `moderate-message { message_id, school_id }` → verdict + status update.
- `moderate-image { attachment_id, school_id }` → quarantine/approve.
- `dispatch-notifications { school_id? }` → FCM send, token hygiene.

## DMS API (admin session required)

- `GET /api/health` — DB/table status, provider presence booleans,
  queue counts, last-message timestamp, version. No secrets returned.
- `POST /api/activation-code { student_id }` — issues a one-time code,
  shown once; stores SHA-256 hash (verified by `activate_student()`).

## Database RPCs (authenticated, RLS + function checks)

- `send_message(p_conversation_id, p_sender_id, p_body, p_idempotency_key,
  p_reply_to_id?)` — full send gate incl. idempotent dedupe.
- `activate_student / activate_teacher` — enrollment (edge-called).
- `issue_student_code(p_student_id, p_plain_code, p_days_valid?)` —
  admin-issued crypt-hashed codes.
- `reassign_student_class(p_student_id, p_new_class_id, p_reason?)`.
- `publish_due_announcements()` — scheduled publishing helper.
