// Loads (and caches) the signed-in user's identity + role tier.
//
// Everything here is read from server-enforced tables under RLS, so a client
// cannot escalate by changing local state.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/identity.dart';

const _signedOut = '__signed_out__';

/// Emits the signed-in user's id, re-emitting only when it actually changes
/// (token refreshes are ignored). Identity is keyed off this stream, so signing
/// out and signing in as somebody else can never render the previous user's
/// dashboard from a stale cache.
final authUserIdProvider = StreamProvider<String?>((ref) async* {
  final client = Supabase.instance.client;

  final current = client.auth.currentUser?.id;
  yield current;
  var last = current ?? _signedOut;

  await for (final state in client.auth.onAuthStateChange) {
    final id = state.session?.user.id;
    final token = id ?? _signedOut;
    if (token != last) {
      last = token;
      yield id;
    }
  }
});

/// Resolve the active user's identity. Keyed on the signed-in user id so a
/// different user always rebuilds identity from scratch.
final identityProvider = FutureProvider<AppIdentity>((ref) async {
  final client = Supabase.instance.client;

  final userId = await ref.watch(authUserIdProvider.future);
  if (userId == null) {
    throw const IdentityException('not_authenticated', 'You are not signed in.');
  }

  final profile = await client
      .from('user_profiles')
      .select('display_name, is_active')
      .eq('id', userId)
      .maybeSingle();
  if (profile != null && (profile as Map)['is_active'] == false) {
    throw const IdentityException('suspended', 'This account has been suspended.');
  }

  final membership = await client
      .from('school_memberships')
      .select('role, school_id, schools(name)')
      .eq('user_id', userId)
      .eq('is_active', true)
      .order('joined_at', ascending: false)
      .limit(1)
      .maybeSingle();

  if (membership == null) {
    throw const IdentityException('no_membership', 'No active school membership.');
  }

  final m = Map<String, dynamic>.from(membership as Map);
  final role = (m['role'] as String?) ?? 'student';
  final schoolId = m['school_id'] as String;
  final school = m['schools'];
  final schoolName = school is Map ? school['name'] as String? ?? '' : '';

  final tier = switch (role) {
    'student' => AppTier.student,
    'teacher' => AppTier.teacher,
    _ => AppTier.leadership, // head_teacher, principal, school_admin, platform_owner
  };

  final displayName = (profile as Map?)?['display_name'] as String?;

  String? studentId, studentIdNo, classId, className;
  String? teacherId, staffIdNo;
  var isLeadershipFlag = false;
  final classIds = <String>[];

  if (tier == AppTier.student) {
    final s = await client
        .from('students')
        .select('id, student_id_no')
        .eq('user_id', userId)
        .eq('school_id', schoolId)
        .maybeSingle();
    if (s != null) {
      final sm = Map<String, dynamic>.from(s as Map);
      studentId = sm['id'] as String?;
      studentIdNo = sm['student_id_no'] as String?;
      final sid = studentId;
      if (sid != null) {
        final enr = await client
            .from('class_enrollments')
            .select('class_id, classes(id, name)')
            .eq('student_id', sid)
            .isFilter('unenrolled_at', null)
            .limit(1)
            .maybeSingle();
        if (enr != null) {
          final e = enr as Map;
          classId = e['class_id'] as String?;
          final c = e['classes'];
          className = c is Map ? c['name'] as String? : null;
        }
      }
    }
  } else {
    final t = await client
        .from('teachers')
        .select('id, staff_id_no, is_leadership')
        .eq('user_id', userId)
        .eq('school_id', schoolId)
        .maybeSingle();
    if (t != null) {
      final tm = Map<String, dynamic>.from(t as Map);
      teacherId = tm['id'] as String?;
      staffIdNo = tm['staff_id_no'] as String?;
      isLeadershipFlag = tm['is_leadership'] == true;

      final tid = teacherId;
      if (tid != null) {
        final assigns = await client
            .from('teaching_assignments')
            .select('class_id')
            .eq('teacher_id', tid)
            .eq('school_id', schoolId);
        for (final a in (assigns as List)) {
          final cid = (a as Map)['class_id'] as String?;
          if (cid != null && !classIds.contains(cid)) classIds.add(cid);
        }
      }
      if (classIds.isNotEmpty) classId = classIds.first;
    }
  }

  return AppIdentity(
    userId: userId,
    displayName: displayName ?? '',
    role: role,
    tier: tier,
    schoolId: schoolId,
    schoolName: schoolName,
    studentId: studentId,
    studentIdNo: studentIdNo,
    classId: classId,
    className: className,
    teacherId: teacherId,
    staffIdNo: staffIdNo,
    isLeadershipFlag: isLeadershipFlag,
    classIds: classIds,
  );
});

class IdentityException implements Exception {
  final String code;
  final String message;
  const IdentityException(this.code, this.message);
  @override
  String toString() => message;
}