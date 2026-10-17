// ============================================================
// TeachCross — test helpers: authorization decisions.
// Pure-logic mirror of:
//  - supabase/migrations/00005_rls_policies.sql (RLS intent)
//  - supabase/migrations/00006_functions_triggers.sql (send_message,
//    activate_student/teacher, issue_student_code, reassign_student_class)
//  - supabase/functions/publish-announcement (audience permissions)
// DB-level RLS tests require a live backend; see tests/rls_checks.sql.
// ============================================================

export const ADMIN_ROLES = ['platform_owner', 'school_admin', 'principal'];
export const TEACHER_ROLES = ['teacher', 'head_teacher'];

export function isSchoolAdmin(role) {
  return ADMIN_ROLES.includes(role);
}

export function isPlatformOwner(role) {
  return role === 'platform_owner';
}

// Active membership lookup: { userId, schoolId, role, isActive }[]
export function activeRolesFor(memberships, userId, schoolId) {
  return memberships
    .filter((m) => m.userId === userId && m.schoolId === schoolId && m.isActive)
    .map((m) => m.role);
}

export function userSchools(memberships, userId) {
  return [...new Set(
    memberships.filter((m) => m.userId === userId && m.isActive).map((m) => m.schoolId),
  )];
}

// --- Messaging (mirrors send_message) ---
// member: { conversationId, userId, role, canSend, removedAt }
export function checkSendMessage({ authUserId, claimedSenderId, conversation, members, body }) {
  if (claimedSenderId !== authUserId) return { ok: false, error: 'forbidden' }; // forged sender
  if (!conversation || !conversation.isActive) return { ok: false, error: 'conversation_not_found' };
  const member = members.find(
    (m) => m.conversationId === conversation.id && m.userId === authUserId && !m.removedAt,
  );
  if (!member) return { ok: false, error: 'not_a_member' }; // incl. revoked
  if (!member.canSend) return { ok: false, error: 'send_not_permitted' };
  if (conversation.type === 'class_channel' && member.role === 'student') {
    return { ok: false, error: 'students_cannot_send_in_class_channel' };
  }
  if (typeof body !== 'string' || body.trim().length === 0) return { ok: false, error: 'empty_message' };
  if (body.length > 4000) return { ok: false, error: 'message_too_long' };
  return { ok: true };
}

export function canReadConversation(userId, conversation, members) {
  return members.some(
    (m) => m.conversationId === conversation.id && m.userId === userId && !m.removedAt,
  );
}

// Students can NEVER create conversations (only system/admins create).
export function canCreateConversation(role) {
  if (role === 'student') return { ok: false, error: 'students_cannot_create' };
  return { ok: true };
}

// A student may only reach teachers sharing a class enrollment/assignment.
export function sharesClass(studentUserId, teacherUserId, enrollments, assignments, students, teachers) {
  const sIds = students.filter((s) => s.userId === studentUserId && s.isActive).map((s) => s.id);
  const tIds = teachers.filter((t) => t.userId === teacherUserId && t.isActive).map((t) => t.id);
  const studentClasses = new Set(
    enrollments.filter((e) => sIds.includes(e.studentId) && !e.unenrolledAt).map((e) => e.classId),
  );
  return assignments.some((a) => tIds.includes(a.teacherId) && studentClasses.has(a.classId));
}

// --- Announcements (mirrors publish-announcement edge function) ---
export function canPublishAnnouncement({ role, audience, category }) {
  if (role === 'student') return { ok: false, error: 'forbidden' };
  const privileged = [...ADMIN_ROLES, ...TEACHER_ROLES].includes(role);
  if (!privileged) return { ok: false, error: 'forbidden' };
  if (audience === 'school_wide' && !ADMIN_ROLES.includes(role)) {
    return { ok: false, error: 'insufficient_permissions_for_audience' };
  }
  if (category === 'priority_alert' && !ADMIN_ROLES.includes(role)) {
    return { ok: false, error: 'priority_alerts_require_admin' };
  }
  return { ok: true };
}

export function resolveAudience({ audience, classId, memberships, enrollments, assignments, students, teachers }) {
  const active = memberships.filter((m) => m.isActive);
  switch (audience) {
    case 'school_wide':
      return active.map((m) => m.userId);
    case 'staff':
      return active.filter((m) => ['teacher', 'head_teacher', 'principal', 'school_admin'].includes(m.role)).map((m) => m.userId);
    case 'leadership':
      return active.filter((m) => ['principal', 'head_teacher'].includes(m.role)).map((m) => m.userId);
    case 'class': {
      if (!classId) return [];
      const sIds = new Set(
        enrollments.filter((e) => e.classId === classId && !e.unenrolledAt).map((e) => e.studentId),
      );
      const tIds = new Set(assignments.filter((a) => a.classId === classId).map((a) => a.teacherId));
      const out = new Set();
      for (const s of students) if (sIds.has(s.id) && s.userId) out.add(s.userId);
      for (const t of teachers) if (tIds.has(t.id) && t.userId) out.add(t.userId);
      return [...out];
    }
    default:
      return [];
  }
}

// --- Attachments (mirrors attachments_member_read) ---
export function canReadAttachment({ userId, attachment, message, members, isAdmin }) {
  if (isAdmin) return true;
  if (attachment.uploaderId === userId) return true;
  if (attachment.status !== 'approved') return false;
  if (!message || message.id !== attachment.messageId) return false;
  return members.some(
    (m) => m.conversationId === message.conversationId && m.userId === userId && !m.removedAt,
  );
}

// --- Audit is append-only: no role may UPDATE/DELETE via app permissions ---
export function canModifyAudit() {
  return false;
}

// --- Investigations: active approval window only ---
export function canAccessInvestigation({ now, request }) {
  if (!request) return { ok: false, error: 'not_found' };
  if (request.status !== 'active' && request.status !== 'approved') return { ok: false, error: 'not_approved' };
  if (request.revokedAt) return { ok: false, error: 'revoked' };
  if (request.accessExpiresAt && new Date(request.accessExpiresAt) < now) return { ok: false, error: 'expired' };
  return { ok: true };
}
