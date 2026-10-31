import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mentor_desk_design.dart';
import '../../../core/layout/responsive.dart';
import '../../../core/widgets/states.dart';
import '../../../core/models/identity.dart';
import '../services/auth_service.dart';

final _authServiceProvider = authServiceProvider;

class RoleSelectScreen extends ConsumerStatefulWidget {
  const RoleSelectScreen({super.key});

  @override
  ConsumerState<RoleSelectScreen> createState() => _RoleSelectScreenState();
}

class _RoleSelectScreenState extends ConsumerState<RoleSelectScreen> {
  AppTier? _selected;
  bool _loading = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final tierAccent = _selected != null ? TierAccent.of(_selected!) : TierAccent.of(AppTier.student);

    return Scaffold(
      backgroundColor: MDColors.ink50,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Sign in to SCORE+'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: tierAccent.gradient,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: tierAccent.solid.withValues(alpha: 0.5),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(Icons.school, size: 40, color: Colors.white),
              ),
              const SizedBox(height: 24),
              Text(
                'Welcome to SCORE+',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Select your role to continue.',
                style: TextStyle(fontSize: 14, color: MDColors.ink600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              _RoleCard(
                title: 'Student',
                subtitle: 'Student ID + activation code',
                icon: Icons.person,
                selected: _selected == AppTier.student,
                onTap: () => setState(() => _selected = AppTier.student),
              ),
              const SizedBox(height: 12),
              _RoleCard(
                title: 'Teacher / Staff',
                subtitle: 'Staff ID + phone verification',
                icon: Icons.person_outline,
                selected: _selected == AppTier.teacher,
                onTap: () => setState(() => _selected = AppTier.teacher),
              ),
              const SizedBox(height: 32),
              if (_error != null) ...[
                Text(
                  _error!,
                  style: TextStyle(color: MDColors.danger, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
              ],
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: _selected == null || _loading
                      ? null
                      : () {
                          if (_selected == AppTier.student) {
                            context.go('/auth/student-signin');
                          } else {
                            context.go('/auth/teacher-signin');
                          }
                        },
                  child: const Text('Continue'),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'New accounts are activated against the official roster. '
                'Contact your school office if your ID is not recognized.',
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

class _RoleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tier = MDTier.student;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? tier.solid : MDColors.ink200,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: tier.solid.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: selected ? tier.solid : MDColors.ink100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: selected ? Colors.white : MDColors.ink600,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: selected ? tier.solid : MDColors.ink900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 13, color: MDColors.ink600),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: selected ? tier.solid : MDColors.ink400,
            ),
          ],
        ),
      ),
    );
  }
}