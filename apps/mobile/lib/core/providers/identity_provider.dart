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

  return AppIdentity(
    userId: userId,
    displayName: session.user.userMetadata?['display_name'] ?? 'User',
    role: role,
    tier: tier,
    schoolId: schoolId,
    schoolName: '',
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

      state = AsyncValue.data(AppIdentity(
        userId: userId,
        displayName: session.user.userMetadata?['display_name'] ?? 'User',
        role: role,
        tier: tier,
        schoolId: schoolId,
        schoolName: '',
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