import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/design_system.dart';
import '../../../core/widgets/premium_card.dart';
import '../../../core/widgets/premium_states.dart';
import '../services/auth_service.dart';

final _authServiceProvider = authServiceProvider;

class TeacherSignInScreen extends ConsumerStatefulWidget {
  const TeacherSignInScreen({super.key});

  @override
  ConsumerState<TeacherSignInScreen> createState() => _TeacherSignInScreenState();
}

class _TeacherSignInScreenState extends ConsumerState<TeacherSignInScreen> {
  final _idController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();
  bool _useActivationCode = false;
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() { _working = true; _error = null; });
    try {
      final auth = ref.read(_authServiceProvider);
      if (_useActivationCode) {
        final result = await auth.activateTeacher(
          staffIdNo: _idController.text.trim(),
          activationCode: _codeController.text.trim().isEmpty ? null : _codeController.text.trim(),
        );
        if (!mounted) return;
        final hasPassword = await auth.hasTeacherPassword(result.teacherId);
        if (!mounted) return;
        if (hasPassword) {
          context.go('/home');
        } else {
          context.go('/auth/create-password?userId=${result.teacherId}&type=teacher');
        }
      } else {
        final success = await auth.signInWithIdAndPassword(
          idNo: _idController.text.trim(),
          password: _passwordController.text,
          userType: 'teacher',
        );
        if (!mounted) return;
        if (success) {
          context.go('/home');
        } else {
          setState(() { _error = 'Invalid ID or password. If this is your first time, use activation code.'; });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SColor.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Teacher Sign In', style: TextStyle(color: SColor.primaryText, fontWeight: FontWeight.w800)),
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: SColor.primaryText), onPressed: () => context.canPop() ? context.pop() : context.go('/auth/role-select')),
      ),
      body: _working ? const PremiumLoading() : Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: [
              const Text('Teacher Sign In', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: SColor.primaryText), textAlign: TextAlign.center),
              const SizedBox(height: SSpace.sm),
              Text(
                _useActivationCode
                    ? 'Enter your school-issued Staff ID and activation code.'
                    : 'Enter your Staff ID and password.',
                style: TextStyle(fontSize: 14, color: SColor.secondaryText),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: SSpace.lg),
              PremiumInput(controller: _idController, label: 'Staff ID', hint: 'e.g., TF-67890'),
              const SizedBox(height: SSpace.md),
              if (_useActivationCode) ...[
                PremiumInput(controller: _codeController, label: 'Activation Code', hint: 'e.g., A1B2C3D4', obscureText: true),
              ] else ...[
                PremiumInput(controller: _passwordController, label: 'Password', hint: 'Enter your password', obscureText: true),
              ],
              const SizedBox(height: SSpace.lg),
              if (_error != null) ...[
                Text(_error!, style: TextStyle(color: SColor.error, fontSize: 13), textAlign: TextAlign.center),
                const SizedBox(height: SSpace.md),
              ],
              PremiumPrimaryButton(
                onPressed: _working ? null : _submit,
                child: _working
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: SColor.textInverse))
                    : Text(_useActivationCode ? 'Activate' : 'Sign In'),
              ),
              const SizedBox(height: SSpace.md),
              PremiumTextButton(
                onPressed: () => setState(() { _useActivationCode = !_useActivationCode; _error = null; }),
                child: Text(_useActivationCode ? 'Already have a password? Sign in' : 'First time? Use activation code'),
              ),
              const SizedBox(height: SSpace.lg),
              Text('Contact your school office if your ID or activation code is not recognized.', style: TextStyle(fontSize: 12, color: SColor.textMuted), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}