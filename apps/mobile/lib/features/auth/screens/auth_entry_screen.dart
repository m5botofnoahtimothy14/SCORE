import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;

import '../services/auth_service.dart';

final _authServiceProvider = authServiceProvider;

class AuthEntryScreen extends ConsumerStatefulWidget {
  const AuthEntryScreen({super.key});

  @override
  ConsumerState<AuthEntryScreen> createState() => _AuthEntryScreenState();
}

class _AuthEntryScreenState extends ConsumerState<AuthEntryScreen> {
  final _idController = TextEditingController();
  bool _teacher = false;
  bool _codeSent = false;
  String? _error;

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() { _error = null; });
    try {
      final auth = ref.read(_authServiceProvider);
      if (!_teacher) {
        // Student: direct sign-in with student ID, auto-enroll from roster
        final data = await auth.activateStudent(
          studentIdNo: _idController.text.trim(),
          activationCode: '',
        );
        if (data.studentId.isNotEmpty) {
          // Permanent account adoption is handled inside AuthService.activateStudent.
        }
      } else {
        // Teacher: direct OTP-based sign-in
        if (!_codeSent) {
          await auth.requestTeacherOtp(
            phone: _idController.text.trim(),
            staffIdNo: _idController.text.trim(),
          );
          if (!mounted) return;
          setState(() => _codeSent = true);
          return;
        } else {
          await auth.verifyTeacherOtp(
            phone: _idController.text.trim(),
            otp: _idController.text.trim(), // In real app, OTP comes from SMS
            staffIdNo: _idController.text.trim(),
          );
        }
      }
      if (!mounted) return;
      context.go('/home');
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not sign in. Check your connection and try again.');
    } finally {
      setState(() {});
    }
  }

  void _setRole(bool teacher) {
    setState(() {
      _teacher = teacher;
      _error = null;
      _codeSent = false;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sign in to SCORE+')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: [
              Text('Welcome to SCORE+', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text('Sign in directly with your ID. Role is verified from the school roster.'),
              const SizedBox(height: 24),
              TextField(
                controller: _idController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(labelText: _teacher ? 'Staff ID' : 'Student ID'),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _error == null && !_codeSent ? _submit : null,
                child: _error != null
                    ? Text('Error: $_error')
                    : _codeSent
                        ? const Text('Verify OTP & Sign In')
                        : _teacher
                            ? const Text('Teacher Sign In')
                            : const Text('Student Sign In'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              if (_codeSent && _teacher) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _idController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(labelText: 'SMS verification code'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _error == null ? () => setState(() => _codeSent = false) : null,
                  child: const Text('Use a different phone or Staff ID'),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'New accounts are activated against the official roster. '
                'Contact your school office if your ID is not recognized.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}