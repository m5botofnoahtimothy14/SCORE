// Real authentication + enrollment against Supabase.
// Students: anonymous sign-in, then server-verified activation via the
// `activate-student` edge function (roster + activation code checked
// server-side; nothing trusted from the client).
// Teachers: OTP request + verification via `send-otp` / `verify-otp`
// edge functions (real SMS provider required).
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/notifications/notification_service.dart';

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
  /// Supabase throws [FunctionException] for non-2xx replies; the real error
  /// code lives in its `details` body, so surface that instead of labelling
  /// every business error (e.g. invalid_credentials) as a network failure.
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

  /// Student enrollment: verifies school-issued ID + activation code.
  /// Returns (studentId, classId). Never reveals whether an ID exists.
  Future<({String studentId, String? classId})> activateStudent({
    required String schoolId,
    required String studentIdNo,
    required String activationCode,
  }) async {
    await ensureSession();
    final data = await _invoke('activate-student', {
      'school_id': schoolId,
      'student_id_no': studentIdNo.trim(),
      'activation_code': activationCode.trim(),
    });
    if (data == null || data['success'] != true) {
      final err = data?['error']?.toString();
      throw AuthException(err ?? 'invalid_credentials', _activationErrorMessage(err));
    }
    NotificationService.registerToken();
    return (
      studentId: data['student_id'] as String,
      classId: data['class_id'] as String?,
    );
  }

  String _activationErrorMessage(String? code) {
    switch (code) {
      case 'rate_limited':
        return 'Too many attempts. Please wait 15 minutes and try again.';
      case 'code_expired':
        return 'This activation code has expired. Ask your school office for a new one.';
      case 'code_already_used':
        return 'This activation code was already used. Ask your school office for help.';
      case 'no_activation_code':
        return 'No activation code found for this ID. Ask your school office to issue one.';
      default:
        // Generic: do not reveal whether the ID exists.
        return 'Check your Student ID and activation code, then try again.';
    }
  }

  /// Teacher step 1: request an OTP via the configured SMS provider.
  Future<void> requestTeacherOtp({
    required String phone,
    required String schoolId,
    required String staffIdNo,
  }) async {
    final data = await _invoke('send-otp', {
      'phone': phone.trim(),
      'school_id': schoolId,
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
      throw const AuthException('invalid_credentials', 'Check your Staff ID and phone number, then try again.');
    }
  }

  /// Teacher step 2: verify OTP and activate the account.
  Future<void> verifyTeacherOtp({
    required String phone,
    required String otp,
    required String schoolId,
    required String staffIdNo,
  }) async {
    await ensureSession();
    final data = await _invoke('verify-otp', {
      'phone': phone.trim(),
      'otp': otp.trim(),
      'school_id': schoolId,
      'staff_id_no': staffIdNo.trim(),
    });
    if (data == null || data['success'] != true) {
      final err = data?['error']?.toString();
      switch (err) {
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
    NotificationService.registerToken();
  }

  /// Signs out and deactivates this device's push token server-side.
  /// Only this device's token is deactivated (never the user's other devices).
  Future<void> signOut() async {
    try {
      await NotificationService.deactivateToken();
    } catch (_) {
      // Best effort — still sign out locally.
    }
    await _client.auth.signOut();
  }
}
