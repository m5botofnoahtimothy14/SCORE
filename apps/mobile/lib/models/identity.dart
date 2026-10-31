enum AppTier { student, teacher, leadership }

class Identity {
  final String id;
  final AppTier tier;
  final String schoolId;
  final String? schoolName;
  final String? displayName;
  final String? email;

  const Identity({
    required this.id,
    required this.tier,
    required this.schoolId,
    this.schoolName,
    this.displayName,
    this.email,
  });

  Identity copyWith({
    String? id,
    AppTier? tier,
    String? schoolId,
    String? schoolName,
    String? displayName,
    String? email,
  }) {
    return Identity(
      id: id ?? this.id,
      tier: tier ?? this.tier,
      schoolId: schoolId ?? this.schoolId,
      schoolName: schoolName ?? this.schoolName,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
    );
  }

  @override
  String toString() => 'Identity(id: $id, tier: $tier, schoolId: $schoolId)';
}