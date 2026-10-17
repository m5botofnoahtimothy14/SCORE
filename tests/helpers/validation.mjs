// ============================================================
// TeachCross — test helpers: validation (mirrors edge/mobile checks)
// These mirror the validation rules enforced in:
//  - supabase/functions/{activate-student,send-otp,verify-otp,publish-announcement}
//  - supabase/migrations/00006_functions_triggers.sql (send_message)
// ============================================================

export function validatePhone(phone) {
  if (typeof phone !== 'string') return { ok: false, error: 'invalid_phone' };
  return /^\+[1-9]\d{6,14}$/.test(phone)
    ? { ok: true }
    : { ok: false, error: 'invalid_phone' };
}

export function validateActivationCode(code) {
  if (typeof code !== 'string') return { ok: false, error: 'invalid_activation_code' };
  const t = code.trim();
  if (t.length < 6 || t.length > 32) return { ok: false, error: 'invalid_activation_code' };
  return { ok: true, value: t };
}

export function validateOtp(otp) {
  if (typeof otp !== 'string') return { ok: false, error: 'invalid_otp' };
  const t = otp.trim();
  if (!/^\d{4,8}$/.test(t)) return { ok: false, error: 'invalid_otp' };
  return { ok: true, value: t };
}

export function validateMessageBody(body) {
  if (typeof body !== 'string' || body.trim().length === 0) {
    return { ok: false, error: 'empty_message' };
  }
  if (body.length > 4000) return { ok: false, error: 'message_too_long' };
  return { ok: true, value: body };
}

const ALLOWED_MIME = new Set([
  'image/jpeg', 'image/png', 'image/webp', 'image/gif',
  'audio/mpeg', 'audio/mp4', 'audio/ogg', 'audio/wav', 'audio/webm',
  'application/pdf',
]);

export function validateFile({ sizeBytes, mimeType, maxMb }) {
  if (typeof sizeBytes !== 'number' || sizeBytes <= 0) return { ok: false, error: 'invalid_file' };
  if (!ALLOWED_MIME.has(mimeType)) return { ok: false, error: 'unsupported_type' };
  const maxBytes = (maxMb ?? 10) * 1024 * 1024;
  if (sizeBytes > maxBytes) return { ok: false, error: 'file_too_large' };
  return { ok: true };
}

export const ANNOUNCEMENT_AUDIENCES = ['school_wide', 'class', 'staff', 'leadership', 'custom'];
export const ANNOUNCEMENT_CATEGORIES = ['general', 'academic', 'event', 'safety', 'priority_alert'];

export function validateAnnouncement({ title, body, category, audience, classId }) {
  if (typeof title !== 'string' || title.trim().length === 0) return { ok: false, error: 'missing_title' };
  if (title.length > 200) return { ok: false, error: 'title_too_long' };
  if (typeof body !== 'string' || body.trim().length === 0) return { ok: false, error: 'missing_body' };
  if (body.length > 10000) return { ok: false, error: 'body_too_long' };
  if (!ANNOUNCEMENT_CATEGORIES.includes(category)) return { ok: false, error: 'invalid_category' };
  if (!ANNOUNCEMENT_AUDIENCES.includes(audience)) return { ok: false, error: 'invalid_audience' };
  if (audience === 'class' && !classId) return { ok: false, error: 'class_required' };
  return { ok: true };
}
