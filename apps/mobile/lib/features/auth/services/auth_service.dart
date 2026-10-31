// Real authentication + enrollment against Supabase.
// Students: anonymous sign-in, then server-verified activation via the
// `activate-student` edge function (roster + activation code checked
// server-side; nothing trusted from the client).
// Teachers: OTP request + verification via `send-otp` / `verify-otp`
// edge functions (real SMS provider required).

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/credential_store.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(Supabase.instance.client);
});

class AuthException implements Exception {
  final String code;
  final String message;
  const AuthException(this.code, this.message);
  @override
  String toString() => message;
}

class AuthService {
  AuthService(this._client);
  final SupabaseClient _client;

  /// Ensures an authenticated session exists (anonymous for students first).
  Future<User> ensureSession() async {
    final current = _client.auth.currentUser;
    if (current != null) return current;
    try {
      final res = await _client.auth.signInAnonymously();
      final user = res.user;
      if (user == null) {
        throw const AuthException('auth_failed', 'Could not start a secure session. Please try again.');
      }
      return user;
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException('auth_failed', 'Could not start a secure session. Check your connection.');
    }
  }

  /// Invokes an edge function and normalizes the response.
  Future<Map<String, dynamic>?> _invoke(String function, Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke(function, body: body);
      final data = res.data;
      return data is Map ? Map<String, dynamic>.from(data) : null;
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map) return Map<String, dynamic>.from(details);
      throw const AuthException('server_error', 'Something went wrong. Please try again.');
    } catch (_) {
      throw const AuthException('network_error', 'Network error. Check your connection and try again.');
    }
  }

  /// Direct student sign-in: auto-enrolls from roster using student ID.
  Future<({String studentId, String? classId})> activateStudent({
    required String studentIdNo,
    String? activationCode,
  }) async {
    await ensureSession();
    final secret = CredentialStore.generateSecret();
    final data = await _invoke('activate-student', {
      'student_id_no': studentIdNo.trim(),
      if (activationCode != null) 'activation_code': activationCode.trim(),
      'device_secret': secret,
    });
    if (data == null || data['success'] != true) {
      final err = data?['error']?.toString();
      if (err == 'invalid_credentials') {
        throw AuthException(err ?? 'invalid_credentials', _activationErrorMessage(err));
      }
      if (err == 'student_not_found') {
        throw AuthException('student_not_found', 'Student ID not found in school roster. Verify with school office.');
      }
      throw AuthException(err ?? 'server_error', _activationErrorMessage(err));
    }
    await _adoptPermanentAccount(data, secret);
    return (
      studentId: data['student_id'] as String,
      classId: data['class_id'] as String?,
    );
  }

  /// Teacher activation: staff ID + one-time activation code issued by the school.
  Future<({String teacherId, String? schoolId})> activateTeacher({
    required String staffIdNo,
    String? activationCode,
  }) async {
    await ensureSession();
    final secret = CredentialStore.generateSecret();
    final data = await _invoke('activate-teacher', {
      'staff_id_no': staffIdNo.trim(),
      if (activationCode != null) 'activation_code': activationCode.trim(),
      'device_secret': secret,
    });
    if (data == null || data['success'] != true) {
      final err = data?['error']?.toString();
      throw AuthException(err ?? 'server_error', _teacherActivationErrorMessage(err));
    }
    await _adoptPermanentAccount(data, secret);
    return (
      teacherId: data['teacher_id'] as String,
      schoolId: data['school_id'] as String?,
    );
  }

  String _teacherActivationErrorMessage(String? code) {
    switch (code) {
      case 'rate_limited':
        return 'Too many attempts. Please wait 15 minutes and try again.';
      case 'code_expired':
        return 'This activation code has expired. Ask your school office for a new one.';
      case 'code_already_used':
        return 'This activation code was already used. Ask your school office for help.';
      case 'teacher_not_found':
        return 'Staff ID not found in school roster. Verify with school office.';
      case 'no_activation_code':
        return 'No activation code found for this ID. Ask your school office to issue one.';
      case 'invalid_code':
        return 'Invalid activation code. Check and try again.';
      default:
        return 'Check your Staff ID and activation code, then try again.';
    }
  }

  /// Signs the device in with the account the activation created and keeps
  /// the credential for the next launch.
  Future<void> _adoptPermanentAccount(
    Map<String, dynamic> data,
    String secret,
  ) async {
    final email = data['email'] as String?;
    if (email == null || email.isEmpty) return;
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: secret,
      );
      await CredentialStore.save(StoredCredential(email: email, secret: secret));
      debugPrint('[CRIMSON] auth: permanent session established for $email');
    } catch (e) {
      debugPrint('[CRIMSON] auth: permanent sign-in failed: $e');
    }
  }

  /// Signs in with the credential stored on this device, if there is one.
  Future<bool> signInWithStoredCredential() async {
    final stored = await CredentialStore.read();
    if (stored == null) return false;
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: stored.email,
        password: stored.secret,
      );
      debugPrint('[CRIMSON] auth: signed in with the stored credential');
      return true;
    } catch (e) {
      debugPrint('[CRIMSON] auth: stored credential rejected: $e');
      await CredentialStore.clear();
      return false;
    }
  }

  String _activationErrorMessage(String? code) {
    switch (code) {
      case 'rate_limited':
        return 'Too many attempts. Please wait 15 minutes and try again.';
      case 'code_expired':
        return 'This activation code has expired. Ask your school office for a new one.';
      case 'code_already_used':
        return 'This activation code was already used. Ask your school office for help.';
      case 'student_not_found':
        return 'Student ID not found in school roster. Verify with school office.';
      case 'no_activation_code':
        return 'No activation code found for this ID. Ask your school office to issue one.';
      default:
        return 'Check your Student ID and activation code, then try again.';
    }
  }

  /// Teacher step 1: request an OTP via the configured SMS provider.
  Future<void> requestTeacherOtp({
    required String phone,
    required String staffIdNo,
  }) async {
    final data = await _invoke('send-otp', {
      'phone': phone.trim(),
      'staff_id_no': staffIdNo.trim(),
    });
    if (data == null || data['success'] != true) {
      final err = data?['error']?.toString();
      if (err == 'sms_provider_unavailable') {
        throw const AuthException('sms_provider_unavailable',
            'SMS service is not configured for this school yet. Please contact your administrator.');
      }
      if (err == 'rate_limited') {
        throw const AuthException('rate_limited', 'Too many code requests. Please wait an hour and try again.');
      }
      if (err == 'school_resolution_required') {
        throw const AuthException('school_resolution_required', 'Your Staff ID matches more than one school. Ask your school office for a school-specific identifier.');
      }
      throw const AuthException('invalid_credentials', 'Check your Staff ID and phone number, then try again.');
    }
  }

  /// Teacher step 2: verify OTP and activate the account.
  Future<void> verifyTeacherOtp({
    required String phone,
    required String otp,
    required String staffIdNo,
  }) async {
    await ensureSession();
    final secret = CredentialStore.generateSecret();
    final data = await _invoke('verify-otp', {
      'phone': phone.trim(),
      'otp': otp.trim(),
      'staff_id_no': staffIdNo.trim(),
      'device_secret': secret,
    });
    if (data == null || data['success'] != true) {
      final err = data?['error']?.toString();
      switch (err) {
        case 'school_resolution_required':
          throw const AuthException('school_resolution_required', 'Your Staff ID matches more than one school. Ask your school office for a school-specific identifier.');
        case 'invalid_otp':
          throw const AuthException('invalid_otp', 'Incorrect code. Please check and try again.');
        case 'otp_expired':
          throw const AuthException('otp_expired', 'This code has expired. Request a new one.');
        case 'account_locked':
          throw const AuthException('account_locked', 'Too many wrong attempts. Try again in 30 minutes.');
        case 'otp_already_used':
          throw const AuthException('otp_already_used', 'This code was already used. Request a new one.');
        default:
          throw const AuthException('invalid_credentials', 'Verification failed. Request a new code and try again.');
      }
    }
    await _adoptPermanentAccount(data, secret);
  }

  /// Signs out and clears this device's credentials.
  Future<void> signOut() async {
    await _client.auth.signOut();
    await CredentialStore.clear();
  }
}