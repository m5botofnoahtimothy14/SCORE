import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/identity.dart';

Future<AppIdentity?> _loadIdentity() async {
  final client = Supabase.instance.client;
  final session = client.auth.currentSession;
  if (session == null) return null;

  final userId = session.user.id;
  final membership = await client
      .from('school_memberships')
      .select('role, school_id, schools(name)')
      .eq('user_id', userId)
      .eq('is_active', true)
      .order('joined_at', ascending: false)
      .limit(1)
      .maybeSingle();

  if (membership == null) return null;

  final role = membership['role'] as String;
  final schoolId = membership['school_id'] as String;
  final rawSchool = membership['schools'];
  final schoolName = rawSchool is Map
      ? rawSchool['name']?.toString() ?? ''
      : rawSchool is List && rawSchool.isNotEmpty && rawSchool.first is Map
          ? (rawSchool.first as Map)['name']?.toString() ?? ''
          : '';

  String profileName = '';
  try {
    final profile = await client
        .from('user_profiles')
        .select('display_name')
        .eq('id', userId)
        .maybeSingle();
    profileName = profile?['display_name']?.toString() ?? '';
  } catch (_) {}

  String? studentId;
  String? studentIdNo;
  String? classId;
  String? className;
  String? teacherId;
  String? staffIdNo;
  bool isLeadershipFlag = false;

  if (role == 'student') {
    try {
      final student = await client
          .from('students')
          .select('id, student_id_no, first_name, last_name')
          .eq('user_id', userId)
          .eq('school_id', schoolId)
          .eq('is_active', true)
          .maybeSingle();

      if (student != null) {
        studentId = student['id']?.toString();
        studentIdNo = student['student_id_no']?.toString();
        final first = student['first_name']?.toString() ?? '';
        final last = student['last_name']?.toString() ?? '';
        if (profileName.isEmpty) profileName = '${first} ${last}'.trim();

        try {
          final enrollment = await client
              .from('class_enrollments')
              .select('class_id, classes(name)')
              .eq('student_id', studentId!)
              .isFilter('unenrolled_at', null)
              .order('enrolled_at', ascending: false)
              .limit(1)
              .maybeSingle();
          if (enrollment != null) {
            classId = enrollment['class_id']?.toString();
            final rawClass = enrollment['classes'];
            if (rawClass is Map) className = rawClass['name']?.toString();
            if (rawClass is List && rawClass.isNotEmpty && rawClass.first is Map) {
              className = (rawClass.first as Map)['name']?.toString();
            }
          }
        } catch (_) {}
      }
    } catch (_) {}
  } else if (role == 'teacher' || role == 'head_teacher') {
    try {
      final teacher = await client
          .from('teachers')
          .select('id, staff_id_no, first_name, last_name, is_leadership')
          .eq('user_id', userId)
          .eq('school_id', schoolId)
          .eq('is_active', true)
          .maybeSingle();

      if (teacher != null) {
        teacherId = teacher['id']?.toString();
        staffIdNo = teacher['staff_id_no']?.toString();
        isLeadershipFlag = teacher['is_leadership'] == true;
        final first = teacher['first_name']?.toString() ?? '';
        final last = teacher['last_name']?.toString() ?? '';
        if (profileName.isEmpty) profileName = '${first} ${last}'.trim();
      }
    } catch (_) {}
  }

  final tier = switch (role) {
    'platform_owner' || 'school_admin' || 'principal' => AppTier.leadership,
    'head_teacher' || 'teacher' => AppTier.teacher,
    'student' => AppTier.student,
    _ => AppTier.student,
  };

  final displayName = profileName.isNotEmpty
      ? profileName
      : session.user.userMetadata?['display_name']?.toString() ?? 'User';

  return AppIdentity(
    userId: userId,
    displayName: displayName,
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
  );
}

/// Resolves the authenticated user's school membership and roster context.
final identityProviderProvider = FutureProvider<AppIdentity?>((ref) async {
  return _loadIdentity();
});

/// Notifier-based provider for imperative refresh.
class IdentityNotifier extends StateNotifier<AsyncValue<AppIdentity?>> {
  IdentityNotifier() : super(const AsyncValue.data(null)) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    try {
      state = AsyncValue.data(await _loadIdentity());
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> refresh() async {
    await _load();
  }
}

final identityNotifierProvider =
    StateNotifierProvider<IdentityNotifier, AsyncValue<AppIdentity?>>(
  (ref) => IdentityNotifier(),
);
