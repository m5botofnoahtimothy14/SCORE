// First-boot consent gate.
//
// Two pieces:
//   * [EulaStore] — versioned persistence of the acceptance. The stored
//     version must equal the current [EulaStore.version], otherwise the user
//     is asked again. That is the whole "we changed the terms" mechanism.
//   * [EulaGate] — the routing guard. Until the current version is accepted,
//     the only reachable locations are the splash, the consent screen itself
//     and the post-decline explanation.
//
// Storage failures are treated as "not accepted": for a consent gate, asking
// again is always the safe failure mode.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EulaStore {
  const EulaStore._();

  /// Bump this whenever the terms change materially — the gate then asks again.
  static const String version = '2026-10-18';

  static const String versionKey = 'eula_accepted_version';
  static const String acceptedAtKey = 'eula_accepted_at';

  static bool _loaded = false;
  static String? _acceptedVersion;
  static DateTime? _acceptedAt;
  static Future<void>? _pending;

  static bool get isLoaded => _loaded;
  static String? get acceptedVersion => _acceptedVersion;
  static DateTime? get acceptedAt => _acceptedAt;

  /// True only when the stored version is exactly the current one.
  static bool get isAccepted => _loaded && _acceptedVersion == version;

  /// Reads the stored acceptance once. Safe to call repeatedly and from
  /// concurrent callers; never throws.
  static Future<void> load() => _pending ??= _read();

  static Future<void> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _acceptedVersion = prefs.getString(versionKey);
      _acceptedAt = DateTime.tryParse(prefs.getString(acceptedAtKey) ?? '');
    } catch (error) {
      debugPrint('[CRIMSON] EULA read failed, asking again: $error');
      _acceptedVersion = null;
      _acceptedAt = null;
    }
    _loaded = true;
  }

  /// Records acceptance of [version] for this device.
  ///
  /// No database migration is added for consent: the acceptance is stored
  /// locally and logged with a timestamp so the record can be replayed once a
  /// server-side audit table exists.
  static Future<void> accept({String? userId}) async {
    final at = DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(versionKey, version);
      await prefs.setString(acceptedAtKey, at.toIso8601String());
    } catch (error) {
      debugPrint('[CRIMSON] EULA write failed: $error');
    }
    _acceptedVersion = version;
    _acceptedAt = at;
    _loaded = true;
    _pending = Future<void>.value();
    debugPrint(
      '[CRIMSON] EULA v$version accepted by ${userId ?? 'anonymous'} '
      'at ${at.toIso8601String()}',
    );
  }

  /// "18 October 2026" for the "you accepted these on ..." banner.
  static String acceptedOnLabel() {
    final at = _acceptedAt;
    if (at == null) return '';
    const months = <String>[
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${at.day} ${months[at.month - 1]} ${at.year}';
  }

  @visibleForTesting
  static void debugReset() {
    _loaded = false;
    _acceptedVersion = null;
    _acceptedAt = null;
    _pending = null;
  }
}

/// Routes that stay reachable before the terms are accepted.
class EulaGate {
  const EulaGate._();

  static const List<String> openPaths = <String>[
    '/', // splash
    '/legal/eula', // the consent screen itself
    '/legal/declined', // post-decline explanation
  ];

  static bool get isBlocking => !EulaStore.isAccepted;

  /// Returns '/legal/eula' while consent is outstanding, otherwise null so the
  /// app's own auth/onboarding guard runs. Call this first in the redirect.
  static String? guard(String location) {
    if (!isBlocking) return null;
    for (final path in openPaths) {
      if (location == path) return null;
    }
    return '/legal/eula';
  }
}
