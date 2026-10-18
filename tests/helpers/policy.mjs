// ============================================================
// TeachCross — test helpers: moderation policy + rate limiting.
//
// The moderation verdict functions below are THIN DELEGATES to the real
// edge module, supabase/functions/_shared/moderation_policy.ts. There is
// deliberately NO mirrored copy of the thresholds here: a hand-copied
// threshold table is exactly how a tuned policy silently stops being the
// thing that is tested. Node >= 22.6 strips the module's types natively.
//
// Also mirrors the sliding-window rate limits in send-otp /
// activate-student. Safe-failure rule: a missing/failed provider MUST NOT
// approve.
// ============================================================

let policyMod = null;
let policyLoadError = null;
try {
  policyMod = await import('../../supabase/functions/_shared/moderation_policy.ts');
} catch (err) {
  policyLoadError = err;
}

export const MODERATION_POLICY_LOAD_ERROR = policyLoadError;

const {
  DEFAULT_POLICY,
  applyPolicy,
  effectiveThresholds,
  toTextVerdict,
  toImageVerdict,
} = policyMod ?? {};

export { DEFAULT_POLICY, effectiveThresholds, applyPolicy };

function requirePolicy() {
  if (!policyMod) {
    throw new Error(
      'moderation_policy.ts could not be loaded (needs Node >= 22.6 for native type stripping): ' +
        String(policyLoadError?.message ?? policyLoadError),
    );
  }
}

/**
 * Mirrors the edge function's text path: vendor scores in, verdict +
 * message status out. Fail-closed when the provider is missing or errored.
 */
export function decideTextVerdict({ categories, text = '', provider, providerError, audience, senderRole }) {
  requirePolicy();
  const decision = applyPolicy({
    categories: categories ?? {},
    text,
    context: { media: 'text', provider, providerError: providerError ?? null, audience, senderRole },
  });
  const verdict = toTextVerdict(decision);
  const messageStatus =
    verdict === 'blocked'
      ? 'blocked'
      : verdict === 'approved' || verdict === 'warned'
        ? 'approved'
        : 'held_for_review';
  return {
    verdict,
    messageStatus,
    policyAction: decision.action,
    reasons: [...decision.reasons],
    matchedRules: [...decision.matchedRules],
  };
}

/**
 * Mirrors the edge function's image path. `score` is the 1..5 nudity
 * observation (APILayer scale). Fail-closed when the provider is missing
 * or errored — an image is never approved without a completed scan.
 */
export function decideImageVerdict({ score, providerConfigured = true, providerError, audience }) {
  requirePolicy();
  const decision = applyPolicy({
    categories: {},
    text: '',
    context: {
      media: 'image',
      provider: providerConfigured ? 'apilayer_nudity' : 'none',
      providerError: providerError ?? null,
      nudityScore: typeof score === 'number' ? score : null,
      audience,
    },
  });
  return {
    verdict: toImageVerdict(decision),
    attachmentStatus: toImageVerdict(decision),
    policyAction: decision.action,
    reasons: [...decision.reasons],
    matchedRules: [...decision.matchedRules],
  };
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
