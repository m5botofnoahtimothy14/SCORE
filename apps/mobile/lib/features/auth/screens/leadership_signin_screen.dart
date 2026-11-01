import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mentor_desk_design.dart';
import '../services/auth_service.dart';

class LeadershipSignInScreen extends ConsumerStatefulWidget {
  const LeadershipSignInScreen({super.key});

  @override
  ConsumerState<LeadershipSignInScreen> createState() => _LeadershipSignInScreenState();
}

class _LeadershipSignInScreenState extends ConsumerState<LeadershipSignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _working = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your administrator email and password.');
      return;
    }

    setState(() {
      _working = true;
      _error = null;
    });

    try {
      await ref.read(authServiceProvider).signInLeadership(
        email: email,
        password: password,
      );
      if (!mounted) return;
      context.go('/home');
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Sign-in failed. Check your connection and try again.');
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
        title: const Text('Leadership Sign In'),
        leading: IconButton(
          onPressed: () => context.go('/auth/role-select'),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                Container(
                  width: 68,
                  height: 68,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.leadershipTier.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.admin_panel_settings_outlined, size: 34, color: AppColors.leadershipTier),
                ),
                const SizedBox(height: 22),
                Text('School leadership', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  'Sign in with your existing administrator account. SCORE+ will verify your school leadership role.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.ink500),
                ),
                const SizedBox(height: 26),
                MDGlossInput(
                  controller: _emailController,
                  label: 'Administrator email',
                  hint: 'name@school.edu',
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                Text('Password', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passwordController,
                  obscureText: !_showPassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _working ? null : _submit(),
                  decoration: InputDecoration(
                    hintText: 'Enter your password',
                    filled: true,
                    fillColor: Colors.white,
                    suffixIcon: IconButton(
                      tooltip: _showPassword ? 'Hide password' : 'Show password',
                      onPressed: () => setState(() => _showPassword = !_showPassword),
                      icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                ],
                const SizedBox(height: 24),
                MDButton(
                  onPressed: _working ? null : _submit,
                  loading: _working,
                  child: const Text('Sign In'),
                ),
                const SizedBox(height: 18),
                const Text(
                  'This sign-in is for authorised school administrators and leadership only.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, height: 1.45, color: AppColors.ink500),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
