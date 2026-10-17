// Rate-limit + idempotency unit tests
import test from 'node:test';
import assert from 'node:assert/strict';
import { SlidingWindow, LIMITS, IdempotencyStore } from './helpers/policy.mjs';

test('otp: max 3 per phone per hour, then rate_limited', () => {
  const lim = new SlidingWindow();
  const t0 = Date.now();
  assert.equal(lim.allow('otp:+911', LIMITS.otpPerPhonePerHour, t0).ok, true);
  assert.equal(lim.allow('otp:+911', LIMITS.otpPerPhonePerHour, t0 + 1000).ok, true);
  assert.equal(lim.allow('otp:+911', LIMITS.otpPerPhonePerHour, t0 + 2000).ok, true);
  const blocked = lim.allow('otp:+911', LIMITS.otpPerPhonePerHour, t0 + 3000);
  assert.equal(blocked.ok, false);
  assert.equal(blocked.error, 'rate_limited');
});

test('rate limit: window expiry restores access; other keys unaffected', () => {
  const lim = new SlidingWindow();
  const t0 = 1_000_000;
  for (let i = 0; i < 5; i++) lim.allow('k', LIMITS.activatePerStudentPer15m, t0 + i);
  assert.equal(lim.allow('k', LIMITS.activatePerStudentPer15m, t0 + 10).error, 'rate_limited');
  // After the 15-min window, allowed again
  assert.equal(lim.allow('k', LIMITS.activatePerStudentPer15m, t0 + 15 * 60 * 1000 + 1).ok, true);
  // Different key never affected
  assert.equal(lim.allow('other', LIMITS.activatePerStudentPer15m, t0 + 10).ok, true);
});

test('rate limit: rapid retries cannot bypass (each retry counts)', () => {
  const lim = new SlidingWindow();
  const t0 = 5_000_000;
  for (let i = 0; i < 3; i++) lim.allow('otp:+912', LIMITS.otpPerPhonePerHour, t0);
  for (let i = 0; i < 10; i++) {
    assert.equal(lim.allow('otp:+912', LIMITS.otpPerPhonePerHour, t0 + i).error, 'rate_limited');
  }
});

test('idempotency: same key returns original, never duplicates', () => {
  const store = new IdempotencyStore();
  let created = 0;
  const first = store.submit('uuid-1', () => ({ id: ++created }));
  const second = store.submit('uuid-1', () => ({ id: ++created }));
  assert.equal(first.duplicate, false);
  assert.equal(second.duplicate, true);
  assert.equal(second.message.id, 1);
  assert.equal(created, 1);
});
