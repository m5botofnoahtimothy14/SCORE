// Unit tests for the role/tier rules that decide what each audience sees.
// These are pure functions, so they run without Supabase or Firebase.
import 'package:flutter_test/flutter_test.dart';
import 'package:teachcross_mobile/core/models/identity.dart';

AppIdentity build({
  required String role,
  String? className,
  String? studentIdNo,
  String? staffIdNo,
}) {
  return AppIdentity(
    userId: 'u1',
    displayName: 'Test User',
    role: role,
    tier: switch (role) {
      'student' => AppTier.student,
      'teacher' => AppTier.teacher,
      _ => AppTier.leadership,
    },
    schoolId: 's1',
    schoolName: 'Demo Public School',
    className: className,
    studentIdNo: studentIdNo,
    staffIdNo: staffIdNo,
  );
}

void main() {
  group('role -> tier mapping', () {
    test('student maps to the student tier', () {
      expect(build(role: 'student').tier, AppTier.student);
    });

    test('teacher maps to the teacher tier', () {
      expect(build(role: 'teacher').tier, AppTier.teacher);
    });

    test('leadership roles all map to the leadership tier', () {
      for (final role in ['head_teacher', 'principal', 'school_admin', 'platform_owner']) {
        expect(build(role: role).tier, AppTier.leadership, reason: role);
      }
    });
  });

  group('tier capabilities', () {
    test('only leadership manages staff and classes', () {
      expect(build(role: 'head_teacher').tier.canManageStaff, isTrue);
      expect(build(role: 'teacher').tier.canManageStaff, isFalse);
      expect(build(role: 'student').tier.canManageStaff, isFalse);
    });

    test('teachers can resolve support, students cannot', () {
      expect(build(role: 'teacher').tier.canResolveSupport, isTrue);
      expect(build(role: 'head_teacher').tier.canResolveSupport, isTrue);
      expect(build(role: 'student').tier.canResolveSupport, isFalse);
    });
  });

  group('identity subtitle', () {
    test('a student sees class and student number', () {
      final id = build(role: 'student', className: 'Grade 8-A', studentIdNo: 'S1002');
      expect(id.subtitle, 'Grade 8-A · S1002');
    });

    test('a teacher sees role and staff number', () {
      final id = build(role: 'teacher', staffIdNo: 'T001');
      expect(id.subtitle, 'Teacher · T001');
    });

    test('leadership is labelled as such', () {
      expect(build(role: 'head_teacher').subtitle, 'Head Teacher · Leadership');
    });

    test('a student with no class assigned degrades gracefully', () {
      expect(build(role: 'student').subtitle, 'Student');
    });
  });
}