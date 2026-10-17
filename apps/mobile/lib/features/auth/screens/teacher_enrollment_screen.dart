import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;

import '../services/auth_service.dart';

final _authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(Supabase.instance.client),
);

/// Teacher enrollment: Staff ID + phone, then 6-digit SMS OTP.
/// Uses the real configured SMS provider; shows a truthful error when the
/// school has not configured one instead of pretending a code was sent.
class TeacherEnrollmentScreen extends ConsumerStatefulWidget {
  final String schoolId;
  const TeacherEnrollmentScreen({super.key, required this.schoolId});

  @override
  ConsumerState<TeacherEnrollmentScreen> createState() => _TeacherEnrollmentScreenState();
}

class _TeacherEnrollmentScreenState extends ConsumerState<TeacherEnrollmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _staffController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  bool _codeSent = false;
  bool _working = false;
  String? _error;
  int _resendIn = 0;
  Timer? _timer;

  void _startResendTimer() {
    _timer?.cancel();
    setState(() => _resendIn = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (_resendIn <= 1) return t.cancel();
      setState(() => _resendIn--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _staffController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await ref.read(_authServiceProvider).requestTeacherOtp(
            phone: _phoneController.text,
            schoolId: widget.schoolId,
            staffIdNo: _staffController.text,
          );
      setState(() => _codeSent = true);
      _startResendTimer();
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _verify() async {
    if (_otpController.text.trim().length < 4) {
      setState(() => _error = 'Enter the verification code sent to your phone.');
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await ref.read(_authServiceProvider).verifyTeacherOtp(
            phone: _phoneController.text,
            otp: _otpController.text,
            schoolId: widget.schoolId,
            staffIdNo: _staffController.text,
          );
      if (!mounted) return;
      context.go('/home');
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Teacher Sign In')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _codeSent ? 'Enter verification code' : 'Verify your staff identity',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _codeSent
                      ? 'We sent a code to ${_phoneController.text.trim()}. It expires in 10 minutes.'
                      : 'Enter your Staff ID and registered phone number. Your school office must add you to the staff roster first.',
                  style: const TextStyle(color: Color(0xFF6B7280)),
                ),
                const SizedBox(height: 24),
                if (!_codeSent) ...[
                  TextFormField(
                    controller: _staffController,
                    decoration: const InputDecoration(
                      labelText: 'Staff ID',
                      hintText: 'e.g. T001',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your Staff ID' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                      hintText: '+911234567890',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Enter your phone number';
                      if (!RegExp(r'^\+[1-9]\d{6,14}$').hasMatch(v.trim())) {
                        return 'Use international format, e.g. +911234567890';
                      }
                      return null;
                    },
                  ),
                ] else ...[
                  TextFormField(
                    controller: _otpController,
                    decoration: const InputDecoration(
                      labelText: 'Verification code',
                      hintText: '6-digit code',
                      prefixIcon: Icon(Icons.sms_outlined),
                    ),
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _resendIn > 0 || _working ? null : _requestCode,
                    child: Text(_resendIn > 0 ? 'Resend code in $_resendIn s' : 'Resend code'),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Color(0xFFDC2626)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFF991B1B)))),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _working ? null : (_codeSent ? _verify : _requestCode),
                    child: _working
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_codeSent ? 'Verify & Continue' : 'Send verification code'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
