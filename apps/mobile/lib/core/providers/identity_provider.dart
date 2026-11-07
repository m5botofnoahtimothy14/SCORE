import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/identity.dart';

/// Provider that resolves the signed-in user's identity (tier, school, etc.)
/// Reads from `school_memberships` and maps the role to an [AppTier].
final identityProviderProvider = FutureProvider<AppIdentity?>((ref) async {
  final session = Supabase.instance.client.auth.currentSession;
  if (session == null) return null;

  final userId = session.user.id;

  final result = await Supabase.instance.client
      .from('school_memberships')
      .select('role, school_id')
      .eq('user_id', userId)
      .eq('is_active', true)
      .order('joined_at', ascending: false)
      .limit(1)
      .maybeSingle();

  final membership = result;
  if (membership == null) return null;

  final role = membership['role'] as String;
  final schoolId = membership['school_id'] as String;

  final tier = switch (role) {
    'platform_owner' => AppTier.leadership,
    'school_admin' => AppTier.leadership,
    'principal' => AppTier.leadership,
    'head_teacher' => AppTier.teacher,
    'teacher' => AppTier.teacher,
    'student' => AppTier.student,
    _ => AppTier.student,
  };

  // Fetch display name from user_profiles
  String displayName = 'User';
  try {
    final profile = await Supabase.instance.client
        .from('user_profiles')
        .select('display_name')
        .eq('id', userId)
        .maybeSingle();
    if (profile != null && profile['display_name'] != null) {
      displayName = profile['display_name'] as String;
    }
  } catch (_) {}

  // Fetch student-specific info
  String? studentId;
  String? studentIdNo;
  String? classId;
  String? className;
  if (tier == AppTier.student) {
    try {
      final student = await Supabase.instance.client
          .from('students')
          .select('id, student_id_no')
          .eq('user_id', userId)
          .maybeSingle();
      if (student != null) {
        studentId = student['id'] as String?;
        studentIdNo = student['student_id_no'] as String?;
      }
      // Get class enrollment
      if (studentId != null) {
        final enroll = await Supabase.instance.client
            .from('class_enrollments')
            .select('class_id, classes(name)')
            .eq('student_id', studentId)
            .isFilter('unenrolled_at', null)
            .limit(1)
            .maybeSingle();
        if (enroll != null) {
          classId = enroll['class_id'] as String?;
          final cls = enroll['classes'] as Map<String, dynamic>?;
          className = cls?['name'] as String?;
        }
      }
    } catch (_) {}
  }

  // Fetch teacher-specific info
  String? teacherId;
  String? staffIdNo;
  List<String> classIds = [];
  if (tier == AppTier.teacher || tier == AppTier.leadership) {
    try {
      final teacher = await Supabase.instance.client
          .from('teachers')
          .select('id, staff_id_no')
          .eq('user_id', userId)
          .maybeSingle();
      if (teacher != null) {
        teacherId = teacher['id'] as String?;
        staffIdNo = teacher['staff_id_no'] as String?;
      }
      // Get assigned classes
      if (teacherId != null) {
        final assignments = await Supabase.instance.client
            .from('teaching_assignments')
            .select('class_id')
            .eq('teacher_id', teacherId);
        classIds = (assignments as List)
            .map((a) => a['class_id'] as String)
            .toSet()
            .toList();
      }
    } catch (_) {}
  }

  return AppIdentity(
    userId: userId,
    displayName: displayName,
    role: role,
    tier: tier,
    schoolId: schoolId,
    schoolName: '',
    studentId: studentId,
    studentIdNo: studentIdNo,
    classId: classId,
    className: className,
    teacherId: teacherId,
    staffIdNo: staffIdNo,
    classIds: classIds,
  );
});

/// Notifier-based provider for imperative refresh
class IdentityNotifier extends StateNotifier<AsyncValue<AppIdentity?>> {
  IdentityNotifier() : super(const AsyncValue.data(null)) {
    _load();
  }

  Future<void> _load() async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        state = const AsyncValue.data(null);
        return;
      }

      final userId = session.user.id;

      final result = await Supabase.instance.client
          .from('school_memberships')
          .select('role, school_id')
          .eq('user_id', userId)
          .eq('is_active', true)
          .order('joined_at', ascending: false)
          .limit(1)
          .maybeSingle();

      final membership = result;
      if (membership == null) {
        state = const AsyncValue.data(null);
        return;
      }

      final role = membership['role'] as String;
      final schoolId = membership['school_id'] as String;

      final tier = switch (role) {
        'platform_owner' => AppTier.leadership,
        'school_admin' => AppTier.leadership,
        'principal' => AppTier.leadership,
        'head_teacher' => AppTier.teacher,
        'teacher' => AppTier.teacher,
        'student' => AppTier.student,
        _ => AppTier.student,
      };

      // Fetch display name from user_profiles
      String displayName = 'User';
      try {
        final profile = await Supabase.instance.client
            .from('user_profiles')
            .select('display_name')
            .eq('id', userId)
            .maybeSingle();
        if (profile != null && profile['display_name'] != null) {
          displayName = profile['display_name'] as String;
        }
      } catch (_) {}

      // Fetch student-specific info
      String? studentId;
      String? studentIdNo;
      String? classId;
      String? className;
      if (tier == AppTier.student) {
        try {
          final student = await Supabase.instance.client
              .from('students')
              .select('id, student_id_no')
              .eq('user_id', userId)
              .maybeSingle();
          if (student != null) {
            studentId = student['id'] as String?;
            studentIdNo = student['student_id_no'] as String?;
          }
          if (studentId != null) {
            final enroll = await Supabase.instance.client
                .from('class_enrollments')
                .select('class_id, classes(name)')
                .eq('student_id', studentId)
                .isFilter('unenrolled_at', null)
                .limit(1)
                .maybeSingle();
            if (enroll != null) {
              classId = enroll['class_id'] as String?;
              final cls = enroll['classes'] as Map<String, dynamic>?;
              className = cls?['name'] as String?;
            }
          }
        } catch (_) {}
      }

      // Fetch teacher-specific info
      String? teacherId;
      String? staffIdNo;
      List<String> classIds = [];
      if (tier == AppTier.teacher || tier == AppTier.leadership) {
        try {
          final teacher = await Supabase.instance.client
              .from('teachers')
              .select('id, staff_id_no')
              .eq('user_id', userId)
              .maybeSingle();
          if (teacher != null) {
            teacherId = teacher['id'] as String?;
            staffIdNo = teacher['staff_id_no'] as String?;
          }
          if (teacherId != null) {
            final assignments = await Supabase.instance.client
                .from('teaching_assignments')
                .select('class_id')
                .eq('teacher_id', teacherId);
            classIds = (assignments as List)
                .map((a) => a['class_id'] as String)
                .toSet()
                .toList();
          }
        } catch (_) {}
      }

      state = AsyncValue.data(AppIdentity(
        userId: userId,
        displayName: displayName,
        role: role,
        tier: tier,
        schoolId: schoolId,
        schoolName: '',
        studentId: studentId,
        studentIdNo: studentIdNo,
        classId: classId,
        className: className,
        teacherId: teacherId,
        staffIdNo: staffIdNo,
        classIds: classIds,
      ));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() async {
    _load();
  }
}

final identityNotifierProvider =
    StateNotifierProvider<IdentityNotifier, AsyncValue<AppIdentity?>>(
  (ref) => IdentityNotifier(),
);

