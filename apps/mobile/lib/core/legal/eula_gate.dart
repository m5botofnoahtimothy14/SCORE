import 'package:shared_preferences/shared_preferences.dart';

class EulaStore {
  const EulaStore._();

  // Bump this on every material legal/privacy or AI-processing change so that
  // existing users must review the revised agreement.
  static const String version = '2026-10-31';
  static const String versionKey = 'eula_accepted_version';
  static const String acceptedAtKey = 'eula_accepted_at';

  static bool _loaded = false;
  static String? _acceptedVersion;
  static DateTime? _acceptedAt;

  static bool get isLoaded => _loaded;
  static String? get acceptedVersion => _acceptedVersion;
  static DateTime? get acceptedAt => _acceptedAt;
  static bool get isAccepted => _loaded && _acceptedVersion == version;

  static Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _acceptedVersion = prefs.getString(versionKey);
      _acceptedAt =
          prefs.getString(acceptedAtKey) != null
              ? DateTime.tryParse(prefs.getString(acceptedAtKey)!)
              : null;
    } catch (_) {
      _acceptedVersion = null;
      _acceptedAt = null;
    }
    _loaded = true;
  }

  static Future<void> accept({String? userId}) async {
    final at = DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(versionKey, version);
      await prefs.setString(acceptedAtKey, at.toIso8601String());
    } catch (_) {}
    _acceptedVersion = version;
    _acceptedAt = at;
    _loaded = true;
  }

  static String acceptedOnLabel() {
    final at = _acceptedAt;
    if (at == null) return '';
    const months = <String>[
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${at.day} ${months[at.month - 1]} ${at.year}';
  }
}

class EulaGate {
  const EulaGate._();

  static const List<String> openPaths = <String>[
    '/',
    '/legal/eula',
    '/legal/declined',
  ];

  static bool get isBlocking => !EulaStore.isAccepted;

  static String? guard(String location) {
    if (!isBlocking) return null;
    for (final path in openPaths) {
      if (location == path) return null;
    }
    return '/legal/eula';
  }
}
