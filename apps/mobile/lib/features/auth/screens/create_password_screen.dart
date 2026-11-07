import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/design_system.dart';
import '../../../core/widgets/premium_card.dart';
import '../../../core/widgets/premium_states.dart';
import '../services/auth_service.dart';

class CreatePasswordScreen extends ConsumerStatefulWidget {
  final String userId; // student_id or teacher_id
  final String userType; // 'student' or 'teacher'

  const CreatePasswordScreen({
    super.key,
    required this.userId,
    required this.userType,
  });

  @override
  ConsumerState<CreatePasswordScreen> createState() => _CreatePasswordScreenState();
}

class _CreatePasswordScreenState extends ConsumerState<CreatePasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  String? _error;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _createPassword() async {
    if (!_formKey.currentState!.validate()) return;
    if (_passwordController.text != _confirmController.text) {
      setState(() { _error = 'Passwords do not match.'; });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final auth = ref.read(authServiceProvider);
      if (widget.userType == 'student') {
        await auth.setStudentPassword(
          studentId: widget.userId,
          password: _passwordController.text,
        );
      } else {
        await auth.setTeacherPassword(
          teacherId: widget.userId,
          password: _passwordController.text,
        );
      }
      if (!mounted) return;
      context.go('/home');
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SColor.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Create Password', style: TextStyle(color: SColor.primaryText, fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const PremiumLoading()
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  shrinkWrap: true,
                  children: [
                    const Icon(Icons.lock_outline, size: 64, color: SColor.primary),
                    const SizedBox(height: SSpace.md),
                    Text(
                      'Create Your Password',
                      style: STextStyle.displayMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: SSpace.sm),
                    Text(
                      'Set a password for future logins. You will use your ID and this password to sign in.',
                      style: STextStyle.bodyMedium.copyWith(color: SColor.secondaryText),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: SSpace.lg),
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          PremiumInput(
                            controller: _passwordController,
                            label: 'Password',
                            hint: 'Enter a password (min 4 characters)',
                            obscureText: _obscurePassword,
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Password is required';
                              if (v.length < 4) return 'Password must be at least 4 characters';
                              return null;
                            },
                          ),
                          const SizedBox(height: SSpace.md),
                          PremiumInput(
                            controller: _confirmController,
                            label: 'Confirm Password',
                            hint: 'Re-enter your password',
                            obscureText: _obscureConfirm,
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Please confirm your password';
                              return null;
                            },
                          ),
                          const SizedBox(height: SSpace.lg),
                          if (_error != null) ...[
                            Text(_error!, style: TextStyle(color: SColor.error, fontSize: 13), textAlign: TextAlign.center),
                            const SizedBox(height: SSpace.md),
                          ],
                          PremiumPrimaryButton(
                            onPressed: _loading ? null : _createPassword,
                            child: _loading
                                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: SColor.textInverse))
                                : const Text('Create Password'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: SSpace.lg),
                    Text(
                      'Your password will be visible to your school admin for recovery purposes.',
                      style: STextStyle.captionMuted,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
