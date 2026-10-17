import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;

import '../services/auth_service.dart';
import '../../../core/config/router.dart';
import '../../../core/widgets/states.dart';

final _authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(Supabase.instance.client),
);

/// Student enrollment: school-issued Student ID + activation code.
/// Verified server-side against the approved roster; IDs are never trusted
/// from the client and errors never reveal whether an ID exists.
class StudentEnrollmentScreen extends ConsumerStatefulWidget {
  final String schoolId;
  const StudentEnrollmentScreen({super.key, required this.schoolId});

  @override
  ConsumerState<StudentEnrollmentScreen> createState() => _StudentEnrollmentScreenState();
}

class _StudentEnrollmentScreenState extends ConsumerState<StudentEnrollmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _codeController = TextEditingController();
  String? _schoolName;
  bool _loadingSchool = true;
  bool _submitting = false;
  String? _error;
  bool _obscureCode = true;

  @override
  void initState() {
    super.initState();
    _loadSchool();
  }

  Future<void> _loadSchool() async {
    try {
      final data = await Supabase.instance.client
          .from('public_schools')
          .select('name')
          .eq('id', widget.schoolId)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _schoolName = data?['name'] as String? ?? 'Your school';
        _loadingSchool = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingSchool = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(_authServiceProvider).activateStudent(
            schoolId: widget.schoolId,
            studentIdNo: _idController.text,
            activationCode: _codeController.text,
          );
      if (!mounted) return;
      invalidateOnboardingCache(Supabase.instance.client.auth.currentUser?.id);
      context.go('/home');
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _idController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Student Sign In')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _loadingSchool
              ? const SizedBox(height: 200, child: LoadingView())
              : Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _schoolName ?? '',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Enter the Student ID and activation code issued by your school office.',
                        style: TextStyle(color: Color(0xFF6B7280)),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _idController,
                        decoration: const InputDecoration(
                          labelText: 'Student ID',
                          hintText: 'e.g. S1001',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        textCapitalization: TextCapitalization.characters,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Enter your Student ID' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _codeController,
                        decoration: InputDecoration(
                          labelText: 'Activation code',
                          hintText: 'Issued by your school',
                          prefixIcon: const Icon(Icons.key_outlined),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureCode ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _obscureCode = !_obscureCode),
                          ),
                        ),
                        obscureText: _obscureCode,
                        validator: (v) =>
                            (v == null || v.trim().length < 6) ? 'Enter the activation code' : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
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
                              Expanded(
                                child: Text(_error!, style: const TextStyle(color: Color(0xFF991B1B))),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _submitting ? null : _submit,
                          child: _submitting
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Continue'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Your class and teachers are assigned automatically by your school. '
                        'Never share your activation code with other students.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
