import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Central Supabase client provider
final supabaseProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

/// Current authenticated user session
final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

/// Current user profile (fetched from user_profiles table)
final currentUserProfileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final supabase = ref.watch(supabaseProvider);
  final user = supabase.auth.currentUser;
  if (user == null) return null;

  final data = await supabase
      .from('user_profiles')
      .select()
      .eq('id', user.id)
      .maybeSingle();

  return data;
});

/// Current user's school membership (first active one)
final currentMembershipProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final supabase = ref.watch(supabaseProvider);
  final user = supabase.auth.currentUser;
  if (user == null) return null;

  final data = await supabase
      .from('school_memberships')
      .select('*, schools(*)')
      .eq('user_id', user.id)
      .eq('is_active', true)
      .order('joined_at', ascending: false)
      .limit(1)
      .maybeSingle();

  return data;
});
