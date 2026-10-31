import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/credential_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mentor_desk_design.dart';
import '../../../core/layout/responsive.dart';
import '../../../core/widgets/states.dart';
import '../services/auth_service.dart';

final _authServiceProvider = authServiceProvider;

class TeacherSignInScreen extends ConsumerStatefulWidget {
  const TeacherSignInScreen({super.key});

  @override
  ConsumerState<TeacherSignInScreen> createState() => _TeacherSignInScreenState();
}

class _TeacherSignInScreenState extends ConsumerState<TeacherSignInScreen> {
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
      final data = await auth.activateTeacher(
        staffIdNo: _idController.text.trim(),
        activationCode: _codeController.text.trim().isEmpty ? null : _codeController.text.trim(),
      );
      if (data.teacherId.isNotEmpty) {
        // Permanent account adoption is handled inside AuthService.activateTeacher.
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MDColors.ink50,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Teacher Sign In'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: _working
          ? const LoadingView()
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  shrinkWrap: true,
                  children: [
                    const Text(
                      'Teacher Sign In',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Enter your school-issued Staff ID and activation code. Your role is verified from the school roster.',
                      style: TextStyle(fontSize: 14, color: AppColors.ink500),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    MDGlossInput(
                      controller: _idController,
                      label: 'Staff ID',
                      hint: 'e.g., TF-67890',
                    ),
                    const SizedBox(height: 16),
                    MDGlossInput(
                      controller: _codeController,
                      label: 'Activation Code',
                      hint: 'e.g., A1B2C3D4',
                      obscureText: true,
                    ),
                    const SizedBox(height: 32),
                    if (_error != null) ...[
                      Text(
                        _error!,
                        style: TextStyle(color: AppColors.danger, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                    ],
                    MDButton(
                      onPressed: _working ? null : _submit,
                      child: _working
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Sign In'),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _working ? null : () => context.pop(),
                      child: const Text('Back to role selection'),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Contact your school office if your ID or activation code is not recognized.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}