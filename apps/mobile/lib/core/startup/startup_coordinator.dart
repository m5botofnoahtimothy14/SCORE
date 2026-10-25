// Boot sequence for the app.
//
// The splash screen is not decoration: it is the window in which the app
// finishes everything it needs before the first screen can be useful. This
// coordinator owns that work so the handoff is always into a READY app:
//
//   1. restore the persisted session (the local-storage read is async, so
//      `currentSession` can still be null right after `Supabase.initialize`)
//   2. resolve the signed-in identity (profile + membership + class)
//   3. register/refresh the push token for this device
//   4. start the presence heartbeat
//
// Every step is individually best-effort: a failure in one must never
// strand the user on the splash. The whole thing is bounded by a hard
// timeout so a slow or unreachable backend can never hold the app hostage.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/credential_store.dart';
import '../models/identity.dart';
import '../notifications/notification_service.dart';
import '../services/presence_service.dart';
import '../../features/auth/services/auth_service.dart';

/// Hard ceiling on how long the boot sequence may run.
const Duration startupTimeout = Duration(seconds: 8);

/// Outcome of the boot sequence — used by the splash to decide where to
/// hand off and to report honest progress.
class StartupResult {
  /// A session was restored (or created) by the time boot finished.
  final bool signedIn;

  /// The resolved identity, when it could be loaded.
  final AppIdentity? identity;

  /// True when the user has an active school membership (i.e. onboarded).
  final bool onboarded;

  /// Steps that failed — never fatal, but surfaced for diagnostics.
  final List<String> failures;

  const StartupResult({
    required this.signedIn,
    required this.identity,
    required this.onboarded,
    required this.failures,
  });

  static const empty = StartupResult(
    signedIn: false,
    identity: null,
    onboarded: false,
    failures: [],
  );
}

/// Runs the boot sequence. Safe to call more than once.
class StartupCoordinator {
  static Future<StartupResult>? _inFlight;

  /// Run (or join) the boot sequence.
  static Future<StartupResult> run() {
    return _inFlight ??= _run().whenComplete(() => _inFlight = null);
  }

  /// Re-run the boot sequence when the app comes back to the foreground.
  ///
  /// A device that was retired by a failed push delivery, or a session that
  /// was refreshed while the app was backgrounded, is picked up here. The
  /// work is cheap and the coordinator is idempotent, so this is safe to
  /// call on every resume.
  static void ensureStarted() {
    if (!_resumedHookInstalled) {
      _resumedHookInstalled = true;
      WidgetsBinding.instance.addObserver(_ResumeHook());
    }
    unawaited(run());
  }

  static bool _resumedHookInstalled = false;

  static Future<StartupResult> _run() async {
    final failures = <String>[];

    // Supabase may not be initialised yet (or at all, in tests). The boot
    // sequence must degrade to "not signed in" rather than throw.
    SupabaseClient client;
    try {
      client = Supabase.instance.client;
    } catch (e) {
      debugPrint('[CRIMSON] startup: Supabase not initialised: $e');
      return StartupResult.empty;
    }

    // 1. Restore the persisted session.
    //
    // `currentSession` is populated asynchronously after initialisation, so
    // reading it directly can report "signed out" for a user who is in fact
    // signed in. `getSession()` forces the local-storage read to complete.
    var session = client.auth.currentSession;
    try {
      session = await client.auth.getSession();
    } catch (e) {
      failures.add('session_restore');
      debugPrint('[CRIMSON] session restore failed: $e');
    }

    // No usable session: fall back to the credential stored on this device.
    // That is how a user who closed the app for longer than the session
    // lifetime gets back in without re-entering their activation code.
    if (session == null) {
      try {
        final auth = AuthService(client);
        if (await auth.signInWithStoredCredential()) {
          session = client.auth.currentSession;
        }
      } catch (e) {
        failures.add('credential_sign_in');
        debugPrint('[CRIMSON] stored credential sign-in failed: $e');
      }
    }

    debugPrint(
      '[CRIMSON] startup: session=${session == null ? 'none' : 'restored'} '
      'user=${session?.user.id ?? '-'} '
      'anonymous=${session?.user.isAnonymous ?? false}',
    );

    if (session == null) {
      return StartupResult(
        signedIn: false,
        identity: null,
        onboarded: false,
        failures: failures,
      );
    }

    // 2. Resolve identity + onboarding state.
    AppIdentity? identity;
    var onboarded = false;
    try {
      identity = await _loadIdentity(client, session.user.id);
      onboarded = identity != null;
    } catch (e) {
      failures.add('identity');
      debugPrint('[CRIMSON] identity load failed: $e');
    }

    // A session whose account has gone (deleted by an administrator, or
    // replaced by a re-enrolment) is stale: the server will reject it, so it
    // is closed here rather than left to fail every later request.
    if (!onboarded && session.user.isAnonymous) {
      debugPrint('[CRIMSON] startup: anonymous session with no membership — signing out');
      try {
        await client.auth.signOut();
        await CredentialStore.clear();
      } catch (e) {
        debugPrint('[CRIMSON] startup: sign-out failed: $e');
      }
    }

    // 3. Register the push token for this device.
    try {
      await NotificationService.registerToken();
    } catch (e) {
      failures.add('push_registration');
      debugPrint('[CRIMSON] push registration failed: $e');
    }

    // 4. Start the presence heartbeat.
    try {
      PresenceService.start();
    } catch (e) {
      failures.add('presence');
      debugPrint('[CRIMSON] presence start failed: $e');
    }

    return StartupResult(
      signedIn: true,
      identity: identity,
      onboarded: onboarded,
      failures: failures,
    );
  }

  /// Loads the same fields the identity provider does, without the Riverpod
  /// container — the splash runs before the app shell is built.
  static Future<AppIdentity?> _loadIdentity(
    SupabaseClient client,
    String userId,
  ) async {
    final profile = await client
        .from('user_profiles')
        .select('display_name, is_active')
        .eq('id', userId)
        .maybeSingle();
    if (profile != null && (profile as Map)['is_active'] == false) {
      return null;
    }

    final membership = await client
        .from('school_memberships')
        .select('role, school_id, schools(name)')
        .eq('user_id', userId)
        .eq('is_active', true)
        .order('joined_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (membership == null) return null;

    final m = Map<String, dynamic>.from(membership as Map);
    final role = (m['role'] as String?) ?? 'student';
    final schoolId = m['school_id'] as String;
    final school = m['schools'];
    final schoolName = school is Map ? school['name'] as String? ?? '' : '';

    final tier = switch (role) {
      'student' => AppTier.student,
      'teacher' => AppTier.teacher,
      _ => AppTier.leadership,
    };

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
      displayName: (profile as Map?)?['display_name'] as String? ?? '',
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
  }
}

/// Re-runs the boot sequence whenever the app returns to the foreground.
class _ResumeHook extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(StartupCoordinator.run());
    }
  }
}
