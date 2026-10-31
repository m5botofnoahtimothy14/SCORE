import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/auth_service.dart';

final _authServiceProvider = authServiceProvider;

class TeacherEnrollmentScreen extends ConsumerStatefulWidget {
  final String? schoolId;
  const TeacherEnrollmentScreen({super.key, this.schoolId});

  @override
  ConsumerState<TeacherEnrollmentScreen> createState() =>
      _TeacherEnrollmentScreenState();
}

class _TeacherEnrollmentScreenState extends ConsumerState<TeacherEnrollmentScreen> {
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
      await auth.activateTeacher(
        staffIdNo: _idController.text.trim(),
        activationCode: _codeController.text.trim().isEmpty ? null : _codeController.text.trim(),
      );
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
    appBar: AppBar(title: const Text('Teacher Enrollment')),
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
                  'Teacher / Staff Sign In',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Enter your Staff ID and activation code issued by your school office.',
                  style: TextStyle(fontSize: 14, color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _idController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Staff ID',
                    hintText: 'e.g., TF-67890',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _codeController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Activation Code',
                    hintText: 'e.g., A1B2C3D4',
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _working ? null : _submit,
                  child: _working
                      ? const SizedBox(
                          height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Sign In'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                ],
                const Spacer(),
                const Text(
                  'Accounts are activated against the official roster. '
                  'Contact your school office if your ID or activation code is not recognized.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}