import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/design_system.dart';
import '../../../core/widgets/premium_card.dart';
import '../../../core/widgets/premium_states.dart';
import '../services/auth_service.dart';

final _authServiceProvider = authServiceProvider;

class RoleSelectScreen extends ConsumerStatefulWidget {
  const RoleSelectScreen({super.key});

  @override
  ConsumerState<RoleSelectScreen> createState() => _RoleSelectScreenState();
}

class _RoleSelectScreenState extends ConsumerState<RoleSelectScreen> {
  String? _selected; // 'student' | 'teacher'
  String? _error;

  @override
  Widget build(BuildContext context) {
    final accent = _selected == 'teacher' ? STierAccent.teacher : STierAccent.student;
    return Scaffold(
      backgroundColor: SColor.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 96, height: 96, decoration: BoxDecoration(
                  color: accent.solid,
                  borderRadius: SRadii.xlAll,
                  boxShadow: [BoxShadow(color: accent.solid.withValues(alpha: 0.5), blurRadius: 24, offset: const Offset(0, 10))],
                ), child: const Icon(Icons.school_outlined, size: 48, color: SColor.textInverse)),
                const SizedBox(height: SSpace.lg),
                Text('Welcome to SCORE+', style: STextStyle.displayMedium, textAlign: TextAlign.center),
                const SizedBox(height: SSpace.sm),
                Text('Choose your role to sign in.\nAll access is verified against your school roster.',
                    style: STextStyle.bodyMedium.copyWith(color: SColor.secondaryText, height: 1.5), textAlign: TextAlign.center),
                const SizedBox(height: SSpace.lg),
                _RoleCard(title: 'Student', subtitle: 'Student ID + activation code', icon: Icons.person_outline, selected: _selected == 'student',
                    accent: accent, onTap: () => setState(() => _selected = 'student')),
                const SizedBox(height: SSpace.sm),
                _RoleCard(title: 'Teacher / Staff', subtitle: 'Staff ID + activation code', icon: Icons.person_outline, selected: _selected == 'teacher',
                    accent: accent, onTap: () => setState(() => _selected = 'teacher')),
                const SizedBox(height: SSpace.lg),
                if (_error != null) ...[
                  Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: SColor.errorSoft, borderRadius: SRadii.mdAll, border: Border.all(color: SColor.error.withValues(alpha: 0.25))),
                    child: Text(_error!, style: TextStyle(color: SColor.error, fontSize: 13), textAlign: TextAlign.center)),
                  const SizedBox(height: SSpace.lg),
                ],
                SizedBox(width: double.infinity, height: 56, child: PremiumPrimaryButton(
                  onPressed: _selected == null ? null : () => context.go(_selected == 'student' ? '/auth/student-signin' : '/auth/teacher-signin'),
                  child: const Text('Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                )),
                const SizedBox(height: SSpace.lg),
                Text('New accounts are activated against the official school roster.\nContact your school office if your ID is not recognized.',
                    style: TextStyle(fontSize: 12.5, color: SColor.textMuted, height: 1.5), textAlign: TextAlign.center),
                const SizedBox(height: SSpace.sm),
                Text('SCORE+ · CRIMSON', style: TextStyle(fontSize: 11, color: SColor.textMuted, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String title, subtitle; final IconData icon; final bool selected; final STierAccent accent; final VoidCallback onTap;
  const _RoleCard({required this.title, required this.subtitle, required this.icon, required this.selected, required this.accent, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(color: Colors.transparent, child: InkWell(borderRadius: SRadii.mdAll, onTap: onTap, child: Container(
      padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: SColor.surface, borderRadius: SRadii.mdAll,
        border: Border.all(color: selected ? accent.solid : SColor.border, width: selected ? 2 : 1),
        boxShadow: selected ? [BoxShadow(color: accent.solid.withValues(alpha: 0.18), blurRadius: 16, offset: const Offset(0, 6))] : null),
      child: Row(children: [
        Container(width: 52, height: 52, decoration: BoxDecoration(color: selected ? accent.solid : SColor.surfaceSoft, borderRadius: SRadii.mdAll),
          child: Icon(icon, color: selected ? SColor.textInverse : SColor.secondaryText, size: 26)),
        const SizedBox(width: 18),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: selected ? accent.solid : SColor.primaryText)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: 13, color: SColor.secondaryText)),
        ])),
        Icon(Icons.chevron_right, color: selected ? accent.solid : SColor.textMuted),
      ]),
    )));
  }
}
