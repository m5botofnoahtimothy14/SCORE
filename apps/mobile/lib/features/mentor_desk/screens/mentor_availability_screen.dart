import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mentor_desk_design.dart';
import '../../../core/layout/responsive.dart';
import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/widgets/states.dart';
import '../../mentor_desk/services/mentor_desk_service.dart';

final _serviceProvider = Provider<MentorDeskService>(
  (ref) => MentorDeskService(Supabase.instance.client),
);

/// Mentor availability: set Available / Away.
class MentorAvailabilityScreen extends ConsumerStatefulWidget {
  const MentorAvailabilityScreen({super.key});

  @override
  ConsumerState<MentorAvailabilityScreen> createState() => _MentorAvailabilityScreenState();
}

class _MentorAvailabilityScreenState extends ConsumerState<MentorAvailabilityScreen> {
  String _status = 'away';
  bool _saving = false;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final identity = await ref.read(identityProvider.future);
    final service = ref.read(_serviceProvider);
    // Find own availability
    String own = 'away';
    try {
      final all = await service.listAvailability(identity.schoolId);
      for (final a in all) {
        if (a.teacherId == identity.teacherId) own = a.status;
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _status = own;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(_serviceProvider).setAvailability(_status);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Availability set to ${_status == 'available' ? 'Available' : 'Away'}.')));
      context.pop();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() { _saving = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = MDTier.teacher;
    return Scaffold(
      backgroundColor: MDColors.ink50,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, title: const Text('My availability')),
      body: _loading
          ? const LoadingView()
          : AdaptivePage(
              maxWidth: 600,
              child: ListView(
                padding: const EdgeInsets.all(kGutter * 1.5),
                children: [
                  const Text('Set whether students can see you as available.', style: TextStyle(fontSize: 15)),
                  const SizedBox(height: kGutter * 2),
                  _AvailabilityTile(
                    icon: Icons.check_circle,
                    label: 'Available',
                    subtitle: 'You appear online to students and can accept requests.',
                    value: 'available',
                    selected: _status == 'available',
                    accent: accent,
                    onChanged: (v) => setState(() => _status = v!),
                  ),
                  const SizedBox(height: kGutter),
                  _AvailabilityTile(
                    icon: Icons.do_not_disturb,
                    label: 'Away',
                    subtitle: 'You do not appear online; requests stay in the shared queue.',
                    value: 'away',
                    selected: _status == 'away',
                    accent: accent,
                    onChanged: (v) => setState(() => _status = v!),
                  ),
                  const SizedBox(height: kGutter * 2),
                  const Text('You appear online only when marked Available and the app is actively connected.', style: TextStyle(fontSize: 12, color: MDColors.ink600, fontStyle: FontStyle.italic)),
                  if (_error != null) ...[
                    const SizedBox(height: kGutter),
                    Text(_error!, style: const TextStyle(color: MDColors.danger, fontSize: 13)),
                  ],
                  const SizedBox(height: kGutter * 3),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: MDGlossButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Save availability'),
                    ),
                  ),
                ],
                ),
                ),
      );
  }
}

class _AvailabilityTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final String value;
  final bool selected;
  final MDTier accent;
  final void Function(String?) onChanged;
  const _AvailabilityTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.selected,
    required this.accent,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MDColors.ink50.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(kRadiusSm),
        border: Border.all(color: MDColors.ink200.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: kGutter / 2, vertical: kGutter / 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: selected ? accent.solid : MDColors.ink100,
            borderRadius: BorderRadius.circular(12),
            boxShadow: selected ? [BoxShadow(color: accent.solid.withValues(alpha: 0.5), blurRadius: 12, offset: const Offset(0, 4))] : null,
          ),
          child: Icon(icon, size: 18, color: selected ? Colors.white : MDColors.ink600),
        ),
        title: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: MDColors.ink900)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 13, color: MDColors.ink600)),
        trailing: Radio<String>(
          value: value,
          groupValue: selected ? value : '',
          onChanged: onChanged,
          activeColor: accent.solid,
        ),
      ),
    );
  }
}
