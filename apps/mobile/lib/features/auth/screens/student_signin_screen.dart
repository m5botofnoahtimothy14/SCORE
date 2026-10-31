import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mentor_desk_design.dart';
import '../../../core/layout/responsive.dart';
import '../../../core/widgets/states.dart';
import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';

final _serviceProvider = Provider((ref) => Supabase.instance.client);

class StudentSignInScreen extends ConsumerStatefulWidget {
  const StudentSignInScreen({super.key});

  @override
  ConsumerState<StudentSignInScreen> createState() => _StudentSignInScreenState();
}

class _StudentSignInScreenState extends ConsumerState<StudentSignInScreen> {
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
      final supabase = Supabase.instance.client;
      final data = await supabase.rpc('activate_student', params: {
        'p_student_id_no': _idController.text.trim(),
        'p_activation_code': _codeController.text.trim().isEmpty ? null : _codeController.text.trim(),
        'p_device_secret': '',
      });
      if (data == null || data['success'] != true) {
        setState(() => _error = data?['error'] ?? 'activation_failed');
        return;
      }
      if (!mounted) return;
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not sign in. Check your connection and try again.');
    } finally {
      if (!mounted) return;
      setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MDColors.ink50,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Student Sign In'),
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
                      'Student Sign In',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Enter your school-issued Student ID to sign in directly. Your role and class are verified from the school roster.',
                      style: TextStyle(fontSize: 14, color: AppColors.ink500),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    MDGlossInput(
                      controller: _idController,
                      label: 'Student ID',
                      hint: 'e.g., STU-12345',
                    ),
                    const SizedBox(height: 16),
                    MDGlossInput(
                      controller: _codeController,
                      label: 'Activation Code',
                      hint: 'e.g., ABC-123-XYZ',
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