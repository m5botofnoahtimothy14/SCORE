// Announcement targeting + permission unit tests
import test from 'node:test';
import assert from 'node:assert/strict';
import { canPublishAnnouncement, resolveAudience } from './helpers/authz.mjs';

test('students can never publish announcements', () => {
  for (const audience of ['school_wide', 'class', 'staff', 'leadership']) {
    const r = canPublishAnnouncement({ role: 'student', audience, category: 'general' });
    assert.equal(r.ok, false, audience);
  }
});

test('teachers cannot broadcast school-wide; admins can', () => {
  assert.equal(canPublishAnnouncement({ role: 'teacher', audience: 'school_wide', category: 'general' }).error, 'insufficient_permissions_for_audience');
  assert.equal(canPublishAnnouncement({ role: 'school_admin', audience: 'school_wide', category: 'general' }).ok, true);
  assert.equal(canPublishAnnouncement({ role: 'principal', audience: 'school_wide', category: 'general' }).ok, true);
  assert.equal(canPublishAnnouncement({ role: 'teacher', audience: 'class', category: 'general' }).ok, true);
});

test('priority alerts require admin role', () => {
  assert.equal(canPublishAnnouncement({ role: 'teacher', audience: 'class', category: 'priority_alert' }).error, 'priority_alerts_require_admin');
  assert.equal(canPublishAnnouncement({ role: 'head_teacher', audience: 'staff', category: 'priority_alert' }).error, 'priority_alerts_require_admin');
  assert.equal(canPublishAnnouncement({ role: 'school_admin', audience: 'school_wide', category: 'priority_alert' }).ok, true);
});

test('audience resolution: school_wide reaches active members only', () => {
  const memberships = [
    { userId: 'a', schoolId: 's1', role: 'student', isActive: true },
    { userId: 'b', schoolId: 's1', role: 'teacher', isActive: true },
    { userId: 'c', schoolId: 's1', role: 'student', isActive: false },
    { userId: 'd', schoolId: 's2', role: 'student', isActive: true },
  ];
  const got = resolveAudience({ audience: 'school_wide', memberships, enrollments: [], assignments: [], students: [], teachers: [] });
  // caller filters by school in real query; resolution here returns active users passed in scope
  assert.ok(got.includes('a') && got.includes('b'));
  assert.ok(!got.includes('c'));
});

test('audience resolution: class reaches only enrolled students + assigned teachers', () => {
  const students = [
    { id: 's1', userId: 'stu1' }, { id: 's2', userId: 'stu2' },
  ];
  const teachers = [{ id: 't1', userId: 'tea1' }, { id: 't2', userId: 'tea2' }];
  const enrollments = [
    { studentId: 's1', classId: 'c1', unenrolledAt: null },
    { studentId: 's2', classId: 'c1', unenrolledAt: '2026-01-01' }, // unenrolled: excluded
  ];
  const assignments = [{ teacherId: 't1', classId: 'c1' }, { teacherId: 't2', classId: 'c9' }];
  const got = resolveAudience({ audience: 'class', classId: 'c1', memberships: [], enrollments, assignments, students, teachers });
  assert.deepEqual(new Set(got), new Set(['stu1', 'tea1']));
});

test('audience resolution: unknown audience and missing class resolve to nobody', () => {
  assert.deepEqual(resolveAudience({ audience: 'custom', memberships: [], enrollments: [], assignments: [], students: [], teachers: [] }), []);
  assert.deepEqual(resolveAudience({ audience: 'class', memberships: [], enrollments: [], assignments: [], students: [], teachers: [] }), []);
});
