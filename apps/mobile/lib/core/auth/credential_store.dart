// Device-bound credential store.
//
// A student or teacher activates with a one-time code and, from then on,
// holds a permanent Supabase account. The credential that unlocks it is
// generated on the device, kept in the platform keystore, and never leaves
// the handset except over TLS to the activation edge function.
//
// The credential is deliberately device-bound: if the phone is lost the
// student re-enrols with the activation code the school issues, exactly as
// the backend already supports for returning students.
import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A stored sign-in credential.
class StoredCredential {
  final String email;
  final String secret;

  const StoredCredential({required this.email, required this.secret});

  Map<String, dynamic> toJson() => {'email': email, 'secret': secret};

  static StoredCredential? fromJson(Map<String, dynamic> json) {
    final email = json['email'];
    final secret = json['secret'];
    if (email is! String || secret is! String) return null;
    if (email.isEmpty || secret.isEmpty) return null;
    return StoredCredential(email: email, secret: secret);
  }
}

class CredentialStore {
  static const _key = 'teachcross.device.credential';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// Generates a fresh device secret. 32 characters of URL-safe base64.
  static String generateSecret() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static Future<void> save(StoredCredential credential) async {
    try {
      await _storage.write(key: _key, value: jsonEncode(credential.toJson()));
    } catch (_) {
      // A keystore failure must never block the user from signing in.
    }
  }

  static Future<StoredCredential?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return null;
      return StoredCredential.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }
}
