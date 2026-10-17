// ============================================================
// Mandatory negative security tests (§14.3).
// These assert the pure authorization-decision layer that mirrors the
// enforced RLS policies + SECURITY DEFINER functions + edge checks.
// Each maps to a live-backend check in tests/rls_checks.sql, which must
// be run against staging before release (see docs/TESTING.md).
// ============================================================
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  checkSendMessage, canReadConversation, canCreateConversation, sharesClass,
  canPublishAnnouncement, canReadAttachment, canModifyAudit, canAccessInvestigation,
  activeRolesFor, userSchools, isPlatformOwner,
} from './helpers/authz.mjs';
import { decideTextVerdict, decideImageVerdict, SlidingWindow, LIMITS } from './helpers/policy.mjs';

const S1 = 'school-A', S2 = 'school-B';
const memberships = [
  { userId: 'stuA', schoolId: S1, role: 'student', isActive: true },
  { userId: 'stuB', schoolId: S1, role: 'student', isActive: true },
  { userId: 'teaA', schoolId: S1, role: 'teacher', isActive: true },
  { userId: 'teaOther', schoolId: S1, role: 'teacher', isActive: true },
  { userId: 'adminA', schoolId: S1, role: 'school_admin', isActive: true },
  { userId: 'adminB', schoolId: S2, role: 'school_admin', isActive: true },
  { userId: 'owner', schoolId: S1, role: 'platform_owner', isActive: true },
];
const students = [
  { id: 'sA', userId: 'stuA', isActive: true },
  { id: 'sB', userId: 'stuB', isActive: true },
];
const teachers = [
  { id: 'tA', userId: 'teaA', isActive: true },
  { id: 'tO', userId: 'teaOther', isActive: true },
];
const enrollments = [
  { studentId: 'sA', classId: 'cA', unenrolledAt: null },
  { studentId: 'sB', classId: 'cB', unenrolledAt: null },
];
const assignments = [
  { teacherId: 'tA', classId: 'cA' }, // teaA teaches stuA's class only
  { teacherId: 'tO', classId: 'cB' },
];

test('1. student cannot message another student (no shared student conversation exists by construction; direct send without membership fails)', () => {
  const r = checkSendMessage({
    authUserId: 'stuA', claimedSenderId: 'stuA',
    conversation: { id: 'nope', schoolId: S1, type: 'student_teacher', isActive: true },
    members: [], body: 'hi',
  });
  assert.equal(r.error, 'not_a_member');
});

test('2. student cannot create a group/conversation', () => {
  assert.equal(canCreateConversation('student').ok, false);
});

test('3. student cannot access another student support room', () => {
  const supportRoomB = { id: 'supB', schoolId: S1, type: 'student_support', isActive: true };
  const membersB = [{ conversationId: 'supB', userId: 'stuB', role: 'student', canSend: true, removedAt: null }];
  assert.equal(canReadConversation('stuA', supportRoomB, membersB), false);
});

test('4. student cannot message an unassigned teacher', () => {
  assert.equal(sharesClass('stuA', 'teaOther', enrollments, assignments, students, teachers), false);
});

test('5. teacher cannot access unassigned student (no shared class)', () => {
  assert.equal(sharesClass('stuB', 'teaA', enrollments, assignments, students, teachers), false);
});

test('6. teacher cannot grant themselves a privileged role', () => {
  // Role changes are admin-only server-side; the decision helper has no
  // self-elevation path: active roles for teaA contain only teacher.
  assert.deepEqual(activeRolesFor(memberships, 'teaA', S1), ['teacher']);
  assert.equal(isPlatformOwner('teacher'), false);
});

test('7. forged school/class change in a request grants nothing (server resolves from records)', () => {
  // userSchools() is derived from verified memberships, never client input.
  assert.deepEqual(userSchools(memberships, 'stuA'), [S1]);
  assert.ok(!userSchools(memberships, 'stuA').includes(S2));
});

test('8. cross-school isolation: School A admin has no role in School B', () => {
  assert.deepEqual(activeRolesFor(memberships, 'adminA', S2), []);
  assert.deepEqual(activeRolesFor(memberships, 'adminB', S1), []);
});

test('9. unauthorized user cannot retrieve a private attachment', () => {
  const attachment = { uploaderId: 'stuB', messageId: 'm1', status: 'approved' };
  const message = { id: 'm1', conversationId: 'supB' };
  const membersB = [{ conversationId: 'supB', userId: 'stuB', role: 'student', canSend: true, removedAt: null }];
  assert.equal(canReadAttachment({ userId: 'stuA', attachment, message, members: membersB, isAdmin: false }), false);
  // ...and unapproved attachments are invisible even to members
  const pending = { uploaderId: 'teaA', messageId: 'm2', status: 'pending_scan' };
  const msg2 = { id: 'm2', conversationId: 'supA' };
  const membersA = [{ conversationId: 'supA', userId: 'stuA', role: 'student', canSend: true, removedAt: null }];
  assert.equal(canReadAttachment({ userId: 'stuA', attachment: pending, message: msg2, members: membersA, isAdmin: false }), false);
});

test('10. revoked member loses access (read + send)', () => {
  const conv = { id: 'c1', schoolId: S1, type: 'student_teacher', isActive: true };
  const revoked = [{ conversationId: 'c1', userId: 'stuA', role: 'student', canSend: true, removedAt: '2026-02-01' }];
  assert.equal(canReadConversation('stuA', conv, revoked), false);
  assert.equal(checkSendMessage({ authUserId: 'stuA', claimedSenderId: 'stuA', conversation: conv, members: revoked, body: 'hi' }).error, 'not_a_member');
});

test('11. forged sender id rejected', () => {
  const conv = { id: 'c1', schoolId: S1, type: 'student_teacher', isActive: true };
  const members = [{ conversationId: 'c1', userId: 'stuA', role: 'student', canSend: true, removedAt: null }];
  const r = checkSendMessage({ authUserId: 'stuA', claimedSenderId: 'stuB', conversation: conv, members, body: 'impersonation' });
  assert.equal(r.error, 'forbidden');
});

test('12. student cannot publish a school-wide announcement', () => {
  assert.equal(canPublishAnnouncement({ role: 'student', audience: 'school_wide', category: 'general' }).ok, false);
});

test('13. ordinary school admin cannot perform platform-owner-only actions', () => {
  //.Platform-only: background_jobs management + investigation approvals.
  // school_admin role is not platform_owner.
  assert.equal(isPlatformOwner('school_admin'), false);
  assert.equal(isPlatformOwner('platform_owner'), true);
});

test('14. unapproved investigation requests grant no access', () => {
  const now = new Date('2026-10-16T00:00:00Z');
  assert.equal(canAccessInvestigation({ now, request: { status: 'requested' } }).ok, false);
  assert.equal(canAccessInvestigation({ now, request: { status: 'active', revokedAt: '2026-10-01' } }).error, 'revoked');
  assert.equal(canAccessInvestigation({ now, request: { status: 'active', accessExpiresAt: '2026-10-01' } }).error, 'expired');
  assert.equal(canAccessInvestigation({ now, request: { status: 'active', accessExpiresAt: '2026-12-01' } }).ok, true);
});

test('15. audit records cannot be modified through application permissions', () => {
  assert.equal(canModifyAudit(), false);
});

test('16. missing moderation credentials never mark content safe', () => {
  assert.notEqual(decideTextVerdict({ categories: {}, provider: 'none' }).messageStatus, 'approved');
  assert.notEqual(decideImageVerdict({ adult: 0, violence: 0, racy: 0, providerConfigured: false }).attachmentStatus, 'approved');
});

test('17. rate limits cannot be bypassed by retrying', () => {
  const lim = new SlidingWindow();
  const t0 = 9_000_000;
  for (let i = 0; i < 3; i++) assert.equal(lim.allow('otp:+913', LIMITS.otpPerPhonePerHour, t0 + i).ok, true);
  for (let i = 0; i < 20; i++) {
    assert.equal(lim.allow('otp:+913', LIMITS.otpPerPhonePerHour, t0 + 100 + i).error, 'rate_limited');
  }
});

test('18. realtime subscriptions reveal nothing without membership (read gate)', () => {
  const conv = { id: 'priv', schoolId: S1, type: 'student_support', isActive: true };
  assert.equal(canReadConversation('eavesdropper', conv, []), false);
});
