// Moderation policy tests (fail-closed behaviour + threshold table).
//
// These delegate to the REAL edge module via tests/helpers/policy.mjs —
// there is no mirrored copy of the thresholds, so this file cannot drift
// out of sync with what ships. The full evaluation (precision/recall/F1
// over the labelled dataset) lives in tests/moderation_policy.test.mjs.
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  decideTextVerdict,
  decideImageVerdict,
  effectiveThresholds,
  DEFAULT_POLICY,
  MODERATION_POLICY_LOAD_ERROR,
} from './helpers/policy.mjs';

const SKIP = MODERATION_POLICY_LOAD_ERROR
  ? `requires native TypeScript type stripping (Node >= 22.6): ${MODERATION_POLICY_LOAD_ERROR.message}`
  : false;

test('the real moderation policy module is what these tests exercise', () => {
  assert.equal(MODERATION_POLICY_LOAD_ERROR, null, String(MODERATION_POLICY_LOAD_ERROR?.stack ?? ''));
});

test('text: hold thresholds map to verdicts (per-category, not max-of-all)', { skip: SKIP }, () => {
  // Below the hate hold bar (0.55) — nothing elevated.
  assert.equal(decideTextVerdict({ categories: { hate: 0.1 }, text: 'hello', provider: 'openai' }).verdict, 'approved');
  // Above it, but a single non-critical category can never block.
  assert.equal(decideTextVerdict({ categories: { hate: 0.6 }, text: 'hello', provider: 'openai' }).verdict, 'held');
  // Above hate's own block bar (0.88) and hate is critical -> blocks alone.
  assert.equal(decideTextVerdict({ categories: { hate: 0.9 }, text: 'hello', provider: 'openai' }).verdict, 'blocked');
});

test('text: held/blocked are not deliverable, approved/warned are', { skip: SKIP }, () => {
  assert.equal(decideTextVerdict({ categories: {}, text: 'hi', provider: 'openai' }).messageStatus, 'approved');
  assert.equal(
    decideTextVerdict({ categories: { violence: 0.75 }, text: 'hi', provider: 'openai' }).messageStatus,
    'held_for_review',
  );
  assert.equal(
    decideTextVerdict({ categories: { hate: 0.95 }, text: 'hi', provider: 'openai' }).messageStatus,
    'blocked',
  );
  // "warned" is an allowlist-suppressed approve: deliverable, but auditable.
  const warned = decideTextVerdict({
    categories: { violence: 0.5 },
    text: 'i killed time playing cricket with my friends',
    provider: 'openai',
    audience: 'class_channel',
  });
  assert.equal(warned.verdict, 'warned');
  assert.equal(warned.messageStatus, 'approved');
});

test('text: two independent signals are required to block', { skip: SKIP }, () => {
  const single = decideTextVerdict({ categories: { harassment: 0.85 }, text: 'hi', provider: 'openai' });
  assert.equal(single.policyAction, 'hold_for_review');
  assert.ok(single.matchedRules.includes('rule:hold_single_signal'));

  const multi = decideTextVerdict({
    categories: { harassment: 0.85, hate: 0.7 },
    text: 'hi',
    provider: 'openai',
  });
  assert.equal(multi.verdict, 'blocked');
  assert.ok(multi.matchedRules.includes('multisignal:block'));
});

test('text: sexual/minors and self-harm always escalate', { skip: SKIP }, () => {
  const csae = decideTextVerdict({
    categories: { 'sexual/minors': 0.11, hate: 0 },
    text: 'hi',
    provider: 'openai',
  });
  assert.equal(csae.verdict, 'escalated');
  assert.equal(csae.messageStatus, 'held_for_review');

  const selfHarm = decideTextVerdict({
    categories: { 'self-harm': 0.74, 'self-harm/intent': 0.63 },
    text: 'hi',
    provider: 'openai',
    audience: 'student_support',
  });
  assert.equal(selfHarm.verdict, 'escalated');
});

test('text: missing or failed provider NEVER approves (held for review)', { skip: SKIP }, () => {
  assert.equal(decideTextVerdict({ categories: {}, text: 'hi', provider: 'none' }).verdict, 'held');
  assert.equal(
    decideTextVerdict({ categories: { hate: 0 }, text: 'hi', provider: 'openai', providerError: 'timeout' }).verdict,
    'held',
  );
  assert.equal(decideTextVerdict({ categories: {}, text: 'hi', provider: 'none' }).messageStatus, 'held_for_review');
  // Catastrophic scores must not survive a provider failure either.
  assert.equal(
    decideTextVerdict({ categories: { 'sexual/minors': 0.99 }, text: 'hi', provider: 'openai', providerError: 'HTTP 503' })
      .verdict,
    'held',
  );
});

test('image: nudity score maps to attachment status', { skip: SKIP }, () => {
  assert.equal(decideImageVerdict({ score: 1 }).attachmentStatus, 'approved');
  assert.equal(decideImageVerdict({ score: 2 }).attachmentStatus, 'approved');
  assert.equal(decideImageVerdict({ score: 3 }).attachmentStatus, 'quarantined');
  assert.equal(decideImageVerdict({ score: 4 }).attachmentStatus, 'rejected');
  assert.equal(decideImageVerdict({ score: 5 }).attachmentStatus, 'rejected');
});

test('image: missing/failed provider NEVER approves (quarantined)', { skip: SKIP }, () => {
  assert.equal(decideImageVerdict({ score: 1, providerConfigured: false }).attachmentStatus, 'quarantined');
  assert.equal(
    decideImageVerdict({ score: 1, providerConfigured: true, providerError: 'APILayer error: 500' }).attachmentStatus,
    'quarantined',
  );
  // A failing provider returning "nudity 1" must still be quarantined.
  assert.equal(
    decideImageVerdict({ score: 1, providerConfigured: false, providerError: 'download failed' }).attachmentStatus,
    'quarantined',
  );
});

test('audience moves the hold bar but never the block bar', { skip: SKIP }, () => {
  const support = effectiveThresholds('student_support');
  const dm = effectiveThresholds('student_dm');
  assert.ok(support.bullying.hold > dm.bullying.hold);
  assert.equal(support.bullying.block, dm.bullying.block);
  assert.equal(support.self_harm.hold, DEFAULT_POLICY.categories.self_harm.hold);
  assert.equal(support.sexual_minors.hold, DEFAULT_POLICY.categories.sexual_minors.hold);
});
