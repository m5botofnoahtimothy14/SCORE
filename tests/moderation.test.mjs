// Moderation policy unit tests (fail-closed behavior)
import test from 'node:test';
import assert from 'node:assert/strict';
import { decideTextVerdict, decideImageVerdict } from './helpers/policy.mjs';

test('text: thresholds map to verdicts', () => {
  assert.equal(decideTextVerdict({ categories: { hate: 0.1 }, provider: 'openai' }).verdict, 'approved');
  assert.equal(decideTextVerdict({ categories: { hate: 0.35 }, provider: 'openai' }).verdict, 'warned');
  assert.equal(decideTextVerdict({ categories: { hate: 0.6 }, provider: 'openai' }).verdict, 'held');
  assert.equal(decideTextVerdict({ categories: { hate: 0.9 }, provider: 'openai' }).verdict, 'blocked');
});

test('text: warned still deliverable, held/blocked are not approved', () => {
  assert.equal(decideTextVerdict({ categories: { spam: 0.35 }, provider: 'openai' }).messageStatus, 'approved');
  assert.equal(decideTextVerdict({ categories: { threat: 0.7 }, provider: 'openai' }).messageStatus, 'held_for_review');
  assert.equal(decideTextVerdict({ categories: { hate: 0.95 }, provider: 'openai' }).messageStatus, 'blocked');
});

test('text: sexual/minors signal always escalates', () => {
  const r = decideTextVerdict({ categories: { 'sexual/minors': 0.11, hate: 0 }, provider: 'openai' });
  assert.equal(r.verdict, 'escalated');
});

test('text: missing or failed provider NEVER approves (held for review)', () => {
  assert.equal(decideTextVerdict({ categories: {}, provider: 'none' }).verdict, 'held');
  assert.equal(decideTextVerdict({ categories: { hate: 0 }, provider: 'openai', providerError: 'timeout' }).verdict, 'held');
  assert.equal(decideTextVerdict({ categories: {}, provider: 'none' }).messageStatus, 'held_for_review');
});

test('image: APILayer score maps to attachment status', () => {
  const cfg = { providerConfigured: true };
  assert.equal(decideImageVerdict({ ...cfg, score: 1 }).attachmentStatus, 'approved');
  assert.equal(decideImageVerdict({ ...cfg, score: 2 }).attachmentStatus, 'approved');
  assert.equal(decideImageVerdict({ ...cfg, score: 3 }).attachmentStatus, 'quarantined');
  assert.equal(decideImageVerdict({ ...cfg, score: 4 }).attachmentStatus, 'rejected');
  assert.equal(decideImageVerdict({ ...cfg, score: 5 }).attachmentStatus, 'rejected');
});

test('image: missing/failed provider NEVER approves (quarantined)', () => {
  assert.equal(decideImageVerdict({ score: 1, providerConfigured: false }).attachmentStatus, 'quarantined');
  assert.equal(decideImageVerdict({ score: 1, providerConfigured: true, providerError: 'APILayer error: 500' }).attachmentStatus, 'quarantined');
});
