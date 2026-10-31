import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;

import '../../../core/auth/credential_store.dart';
import '../../../core/notifications/notification_service.dart';
import '../services/auth_service.dart';

final _authServiceProvider = authServiceProvider;

class StudentEnrollmentScreen extends ConsumerStatefulWidget {
  final String? schoolId;
  const StudentEnrollmentScreen({super.key, this.schoolId});

  @override
  ConsumerState<StudentEnrollmentScreen> createState() =>
      _StudentEnrollmentScreenState();
}

class _StudentEnrollmentScreenState extends ConsumerState<StudentEnrollmentScreen> {
  final _idController = TextEditingController();
  final _codeController = TextEditingController();
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _idController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() { _working = true; _error = null; });
    try {
      final auth = ref.read(_authServiceProvider);
      // Direct student login - auto-enroll from roster using student ID
      final data = await auth.activateStudent(
        studentIdNo: _idController.text.trim(),
        activationCode: _codeController.text.trim(),
      );
      if (data.studentId.isNotEmpty) {
        // Permanent account adoption is handled inside AuthService.activateStudent.
      }
      if (!mounted) return;
      context.go('/home');
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not sign in. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Student Enrollment')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Enroll as a Student',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Enter your school-issued Student ID to sign in directly. '
                  'Your role and class are verified from the school roster.',
                  style: TextStyle(fontSize: 14, color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _idController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Student ID',
                    hintText: 'e.g., STU-12345',
                  ),
                ),
                if (_codeController.text.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _codeController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Activation Code (optional)',
                    ),
                  ),
                ],
                const Spacer(),
                FilledButton(
                  onPressed: _working ? null : _submit,
                  child: _working
                      ? const SizedBox(
                          height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Sign In'),
                ),
                const SizedBox(height: 16),
                const TextButton(
                  onPressed: null,
                  child: Text(
                    'If you don\'t have a Student ID, contact your school office.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}