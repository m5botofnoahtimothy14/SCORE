// ============================================================
// TeachCross — test helpers: moderation policy + rate limiting.
// Mirrors supabase/functions/moderate-{message,image} thresholds and
// the sliding-window rate limits in send-otp / activate-student.
// Safe-failure rule: missing/failed provider MUST NOT approve.
// ============================================================

export const BLOCK_THRESHOLD = 0.8;
export const HOLD_THRESHOLD = 0.5;
export const WARN_THRESHOLD = 0.3;

export function decideTextVerdict({ categories, provider, providerError }) {
  if (providerError || provider === 'none') {
    return { verdict: 'held', messageStatus: 'held_for_review', providerError };
  }
  const scores = Object.values(categories ?? {});
  const maxScore = scores.length ? Math.max(...scores) : 0;
  if ((categories?.['sexual/minors'] ?? 0) > 0.1) return { verdict: 'escalated', messageStatus: 'held_for_review', maxScore };
  if (maxScore >= BLOCK_THRESHOLD) return { verdict: 'blocked', messageStatus: 'blocked', maxScore };
  if (maxScore >= HOLD_THRESHOLD) return { verdict: 'held', messageStatus: 'held_for_review', maxScore };
  if (maxScore >= WARN_THRESHOLD) return { verdict: 'warned', messageStatus: 'approved', maxScore };
  return { verdict: 'approved', messageStatus: 'approved', maxScore };
}

// APILayer Nudity Detection returns a 1–5 score (5 = most likely nude).
export const IMAGE_REJECT_AT = 4;
export const IMAGE_HOLD_AT = 3;

export function decideImageVerdict({ score, providerConfigured, providerError }) {
  if (!providerConfigured || providerError) {
    return { verdict: 'quarantined', attachmentStatus: 'quarantined' }; // fail closed
  }
  if (score >= IMAGE_REJECT_AT) return { verdict: 'rejected', attachmentStatus: 'rejected' };
  if (score >= IMAGE_HOLD_AT) return { verdict: 'quarantined', attachmentStatus: 'quarantined' };
  return { verdict: 'approved', attachmentStatus: 'approved' };
}

// Sliding-window limiter (mirrors rate_limit_events checks)
export class SlidingWindow {
  constructor() {
    this.events = new Map(); // key -> number[] (epoch ms)
  }
  attempts(key, nowMs, windowMs) {
    const list = (this.events.get(key) ?? []).filter((t) => t > nowMs - windowMs);
    this.events.set(key, list);
    return list.length;
  }
  allow(key, { max, windowMs }, nowMs) {
    const count = this.attempts(key, nowMs, windowMs);
    if (count >= max) return { ok: false, error: 'rate_limited' };
    this.events.get(key).push(nowMs);
    return { ok: true };
  }
}

export const LIMITS = {
  otpPerPhonePerHour: { max: 3, windowMs: 60 * 60 * 1000 },
  activatePerStudentPer15m: { max: 5, windowMs: 15 * 60 * 1000 },
};

// Idempotency store (mirrors messages.idempotency_key UNIQUE + retry)
export class IdempotencyStore {
  constructor() { this.seen = new Map(); }
  submit(key, makeMessage) {
    if (this.seen.has(key)) return { duplicate: true, message: this.seen.get(key) };
    const msg = makeMessage();
    this.seen.set(key, msg);
    return { duplicate: false, message: msg };
  }
}
