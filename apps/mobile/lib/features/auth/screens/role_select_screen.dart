import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/identity.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mentor_desk_design.dart';

class RoleSelectScreen extends StatefulWidget {
  const RoleSelectScreen({super.key});

  @override
  State<RoleSelectScreen> createState() => _RoleSelectScreenState();
}

class _RoleSelectScreenState extends State<RoleSelectScreen> {
  AppTier? _selected;

  @override
  Widget build(BuildContext context) {
    final tierAccent = TierAccent.of(_selected ?? AppTier.student);

    return Scaffold(
      backgroundColor: MDColors.ink50,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Sign in to SCORE+'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
              shrinkWrap: true,
              children: [
                Center(
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: tierAccent.gradient),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: tierAccent.solid.withValues(alpha: 0.20),
                          blurRadius: 22,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.school_rounded, size: 38, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Welcome to SCORE+',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose the account type issued by your school.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: MDColors.ink600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                _RoleCard(
                  title: 'Student',
                  subtitle: 'Student ID and activation code',
                  icon: Icons.school_outlined,
                  tier: MDTier.student,
                  selected: _selected == AppTier.student,
                  onTap: () => setState(() => _selected = AppTier.student),
                ),
                const SizedBox(height: 12),
                _RoleCard(
                  title: 'Teacher / Staff',
                  subtitle: 'Staff ID and activation code',
                  icon: Icons.co_present_outlined,
                  tier: MDTier.teacher,
                  selected: _selected == AppTier.teacher,
                  onTap: () => setState(() => _selected = AppTier.teacher),
                ),
                const SizedBox(height: 12),
                _RoleCard(
                  title: 'School Leadership',
                  subtitle: 'Administrator email and password',
                  icon: Icons.admin_panel_settings_outlined,
                  tier: MDTier.leadership,
                  selected: _selected == AppTier.leadership,
                  onTap: () => setState(() => _selected = AppTier.leadership),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 54,
                  child: FilledButton(
                    onPressed: _selected == null
                        ? null
                        : () {
                            switch (_selected!) {
                              case AppTier.student:
                                context.go('/auth/student-signin');
                                break;
                              case AppTier.teacher:
                                context.go('/auth/teacher-signin');
                                break;
                              case AppTier.leadership:
                                context.go('/auth/leadership-signin');
                                break;
                            }
                          },
                    child: const Text('Continue'),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Your access is checked against your school account. Contact your school office if your details are not recognised.',
                  style: TextStyle(fontSize: 12, height: 1.5, color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tier,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final MDTier tier;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? tier.solid : MDColors.ink200,
              width: selected ? 1.8 : 1,
            ),
            boxShadow: selected
                ? [BoxShadow(color: tier.solid.withValues(alpha: 0.10), blurRadius: 16, offset: const Offset(0, 4))]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: selected ? tier.solid : MDColors.ink100,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: selected ? Colors.white : MDColors.ink600, size: 23),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: selected ? tier.solid : MDColors.ink900)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: MDColors.ink600)),
                  ],
                ),
              ),
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: selected ? tier.solid : MDColors.ink300),
            ],
          ),
        ),
      ),
    );
  }
}
