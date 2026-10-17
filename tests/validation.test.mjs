// Validation unit tests
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  validatePhone, validateActivationCode, validateOtp, validateMessageBody,
  validateFile, validateAnnouncement,
} from './helpers/validation.mjs';

test('phone: accepts E.164, rejects malformed', () => {
  assert.equal(validatePhone('+911234567890').ok, true);
  assert.equal(validatePhone('1234567890').ok, false);
  assert.equal(validatePhone('+91').ok, false);
  assert.equal(validatePhone(123).ok, false);
  assert.equal(validatePhone('+911234567890123456').ok, false); // >15 digits
});

test('activation code: length bounds + trim', () => {
  assert.equal(validateActivationCode('ABC123').ok, true);
  assert.equal(validateActivationCode('  ABC123  ').value, 'ABC123');
  assert.equal(validateActivationCode('ab').ok, false);
  assert.equal(validateActivationCode('x'.repeat(33)).ok, false);
  assert.equal(validateActivationCode(123456).ok, false);
});

test('otp: digits only, 4-8 chars', () => {
  assert.equal(validateOtp('123456').ok, true);
  assert.equal(validateOtp('12a456').ok, false);
  assert.equal(validateOtp('123').ok, false);
  assert.equal(validateOtp('123456789').ok, false);
});

test('message body: empty and oversize rejected', () => {
  assert.equal(validateMessageBody('   ').ok, false);
  assert.equal(validateMessageBody('').ok, false);
  assert.equal(validateMessageBody('hi').ok, true);
  assert.equal(validateMessageBody('x'.repeat(4000)).ok, true);
  assert.equal(validateMessageBody('x'.repeat(4001)).error, 'message_too_long');
});

test('file: mime allowlist + size cap enforced', () => {
  assert.equal(validateFile({ sizeBytes: 1024, mimeType: 'image/jpeg', maxMb: 10 }).ok, true);
  assert.equal(validateFile({ sizeBytes: 11 * 1024 * 1024, mimeType: 'image/jpeg', maxMb: 10 }).error, 'file_too_large');
  assert.equal(validateFile({ sizeBytes: 100, mimeType: 'video/mp4', maxMb: 10 }).error, 'unsupported_type');
  assert.equal(validateFile({ sizeBytes: 100, mimeType: 'application/x-sh', maxMb: 10 }).error, 'unsupported_type');
  assert.equal(validateFile({ sizeBytes: 0, mimeType: 'image/png', maxMb: 10 }).ok, false);
});

test('announcement: required fields + class audience needs class', () => {
  const base = { title: 'Exam', body: 'On Monday', category: 'academic', audience: 'class', classId: 'c1' };
  assert.equal(validateAnnouncement(base).ok, true);
  assert.equal(validateAnnouncement({ ...base, classId: undefined }).error, 'class_required');
  assert.equal(validateAnnouncement({ ...base, category: 'party' }).error, 'invalid_category');
  assert.equal(validateAnnouncement({ ...base, audience: 'everyone' }).error, 'invalid_audience');
  assert.equal(validateAnnouncement({ ...base, title: '' }).error, 'missing_title');
});
