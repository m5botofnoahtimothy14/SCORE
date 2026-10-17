// Messaging authorization unit tests (mirror of send_message + RLS intent)
import test from 'node:test';
import assert from 'node:assert/strict';
import { checkSendMessage, canReadConversation, canCreateConversation, sharesClass } from './helpers/authz.mjs';

const conv = (over = {}) => ({ id: 'conv1', schoolId: 's1', type: 'student_teacher', isActive: true, ...over });
const mem = (over = {}) => ({ conversationId: 'conv1', userId: 'u1', role: 'student', canSend: true, removedAt: null, ...over });

test('send: happy path for active member with permission', () => {
  const r = checkSendMessage({ authUserId: 'u1', claimedSenderId: 'u1', conversation: conv(), members: [mem()], body: 'hello' });
  assert.equal(r.ok, true);
});

test('send: forged sender id rejected', () => {
  const r = checkSendMessage({ authUserId: 'u1', claimedSenderId: 'victim', conversation: conv(), members: [mem()], body: 'hi' });
  assert.equal(r.error, 'forbidden');
});

test('send: non-member and revoked member rejected', () => {
  assert.equal(checkSendMessage({ authUserId: 'u9', claimedSenderId: 'u9', conversation: conv(), members: [mem()], body: 'hi' }).error, 'not_a_member');
  assert.equal(checkSendMessage({ authUserId: 'u1', claimedSenderId: 'u1', conversation: conv(), members: [mem({ removedAt: '2026-01-01' })], body: 'hi' }).error, 'not_a_member');
});

test('send: read-only member (can_send=false) rejected', () => {
  const r = checkSendMessage({ authUserId: 'u1', claimedSenderId: 'u1', conversation: conv(), members: [mem({ canSend: false })], body: 'hi' });
  assert.equal(r.error, 'send_not_permitted');
});

test('send: student cannot send in class_channel', () => {
  const r = checkSendMessage({ authUserId: 'u1', claimedSenderId: 'u1', conversation: conv({ type: 'class_channel' }), members: [mem({ role: 'student' })], body: 'hi' });
  assert.equal(r.error, 'students_cannot_send_in_class_channel');
});

test('send: teacher CAN broadcast in class_channel', () => {
  const r = checkSendMessage({ authUserId: 't1', claimedSenderId: 't1', conversation: conv({ type: 'class_channel' }), members: [mem({ userId: 't1', role: 'teacher' })], body: 'homework due' });
  assert.equal(r.ok, true);
});

test('read: only active members see conversation', () => {
  assert.equal(canReadConversation('u1', conv(), [mem()]), true);
  assert.equal(canReadConversation('u9', conv(), [mem()]), false);
  assert.equal(canReadConversation('u1', conv(), [mem({ removedAt: 'x' })]), false);
});

test('students can never create conversations/groups', () => {
  assert.equal(canCreateConversation('student').ok, false);
  assert.equal(canCreateConversation('teacher').ok, true);
});

test('student reaches only teachers sharing a class', () => {
  const students = [{ id: 's1', userId: 'stu', isActive: true }];
  const teachers = [{ id: 't1', userId: 'tea', isActive: true }, { id: 't2', userId: 'stranger', isActive: true }];
  const enrollments = [{ studentId: 's1', classId: 'c1', unenrolledAt: null }];
  const assignments = [{ teacherId: 't1', classId: 'c1' }, { teacherId: 't2', classId: 'c2' }];
  assert.equal(sharesClass('stu', 'tea', enrollments, assignments, students, teachers), true);
  assert.equal(sharesClass('stu', 'stranger', enrollments, assignments, students, teachers), false);
});
