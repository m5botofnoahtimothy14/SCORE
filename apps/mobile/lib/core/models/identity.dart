// Identity context: who is signed in, and which experience they get.
//
// The app is deliberately split into three tiers so each audience only ever
// sees controls that belong to them:
//   • Student    — their class, teachers, messages, notices. Read-mostly.
//   • Teacher    — their classes and students, support queue, moderate control.
//   • Leadership — whole-school view: staff, insights, announcements.
//
// The tier is derived from `school_memberships.role` (server-enforced) and is
// never trusted from anything the client can edit.

enum AppTier { student, teacher, leadership }

extension AppTierX on AppTier {
  String get label => switch (this) {
        AppTier.student => 'Student',
        AppTier.teacher => 'Teacher',
        AppTier.leadership => 'Leadership',
      };

  bool get canManageStaff => this == AppTier.leadership;
  bool get canManageClasses => this == AppTier.leadership;
  bool get canResolveSupport => this != AppTier.student;
}

class AppIdentity {
  final String userId;
  final String displayName;
  final String role;
  final AppTier tier;
  final String schoolId;
  final String schoolName;

  // Student context
  final String? studentId;
  final String? studentIdNo;
  final String? classId;
  final String? className;

  // Staff context
  final String? teacherId;
  final String? staffIdNo;
  final bool isLeadershipFlag;
  final List<String> classIds;

  const AppIdentity({
    required this.userId,
    required this.displayName,
    required this.role,
    required this.tier,
    required this.schoolId,
    required this.schoolName,
    this.studentId,
    this.studentIdNo,
    this.classId,
    this.className,
    this.teacherId,
    this.staffIdNo,
    this.isLeadershipFlag = false,
    this.classIds = const [],
  });

  bool get isStudent => tier == AppTier.student;
  bool get isTeacher => tier == AppTier.teacher;
  bool get isLeadership => tier == AppTier.leadership;

  /// e.g. "Class 10-A · S1001" for a student.
  String get subtitle {
    if (isStudent) {
      final bits = <String>[
        if (className != null) className!,
        if (studentIdNo != null) studentIdNo!,
      ];
      return bits.isEmpty ? AppTier.student.label : bits.join(' · ');
    }
    if (isLeadership) return '${_titleCase(role)} · Leadership';
    final bits = <String>[
      _titleCase(role),
      if (staffIdNo != null) staffIdNo!,
    ];
    return bits.join(' · ');
  }

  static String _titleCase(String s) => s
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}