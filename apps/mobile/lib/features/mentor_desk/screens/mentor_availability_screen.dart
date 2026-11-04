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
import '../services/mentor_desk_service.dart';

final mentorDeskServiceProvider = Provider<MentorDeskService>((ref) {
  return MentorDeskService(Supabase.instance.client);
});

class MentorAvailabilityScreen extends ConsumerStatefulWidget {
  const MentorAvailabilityScreen({super.key});

  @override
  ConsumerState<MentorAvailabilityScreen> createState() => _MentorAvailabilityScreenState();
}

class _MentorAvailabilityScreenState extends ConsumerState<MentorAvailabilityScreen> {
  String _status = 'available';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final service = ref.read(mentorDeskServiceProvider);
      // Try to read current availability from Supabase
      final identity = await ref.read(identityProviderProvider.future);
      if (identity != null) {
        final rows = await Supabase.instance.client
            .from('mentor_availability')
            .select('status, updated_at')
            .eq('teacher_id', identity.teacherId ?? identity.userId)
            .maybeSingle();
        if (rows != null) {
          _status = rows['status'] ?? 'available';
        }
      }
      if (!mounted) return;
      setState(() { _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _set(String status) async {
    setState(() { _loading = true; });
    try {
      final service = ref.read(mentorDeskServiceProvider);
      await service.setAvailability(status);
      if (!mounted) return;
      setState(() { _status = status; _loading = false; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Availability set to $status.'),
        backgroundColor: status == 'available' ? MDColors.success : MDColors.warning,
        duration: const Duration(seconds: 3),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MDColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MDColors.ink900),
          onPressed: () => context.pop(),
        ),
        title: const Text('Availability', style: TextStyle(color: MDColors.ink900, fontWeight: FontWeight.w800)),
        centerTitle: false,
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    horizontalGutter(context),
                    24,
                    horizontalGutter(context),
                    MediaQuery.of(context).padding.bottom + 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mentor Availability',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Set whether you are available to pick up student requests.',
                        style: TextStyle(fontSize: 14, color: MDColors.ink600),
                      ),
                      const SizedBox(height: 32),
                      _StatusTile(
                        title: 'Available',
                        subtitle: 'You can pick up requests from the shared queue.',
                        icon: Icons.check_circle,
                        color: MDColors.success,
                        selected: _status == 'available',
                        onTap: () => _set('available'),
                      ),
                      const SizedBox(height: 14),
                      _StatusTile(
                        title: 'Away',
                        subtitle: 'You will not appear in the shared queue.',
                        icon: Icons.access_alarm,
                        color: MDColors.warning,
                        selected: _status == 'away',
                        onTap: () => _set('away'),
                      ),
                      const SizedBox(height: 40),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: MDColors.ink100,
                          borderRadius: BorderRadius.circular(kRadiusLg),
                          border: Border.all(color: MDColors.ink200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('How it works', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MDColors.ink700)),
                            const SizedBox(height: 10),
                            Text('• When you are Available, students can see you and assign named requests to you.',
                                style: TextStyle(fontSize: 13, color: MDColors.ink600, height: 1.5)),
                            const SizedBox(height: 6),
                            Text('• When Away, you will not receive new request assignments.',
                                style: TextStyle(fontSize: 13, color: MDColors.ink600, height: 1.5)),
                            const SizedBox(height: 6),
                            Text('• Your status is shared with students so they know when to expect a response.',
                                style: TextStyle(fontSize: 13, color: MDColors.ink600, height: 1.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _StatusTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadiusSm),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: MDColors.surfaceCard,
            borderRadius: BorderRadius.circular(kRadiusSm),
            border: Border.all(color: selected ? color : MDColors.ink200, width: selected ? 2 : 1),
            boxShadow: selected
                ? [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 12, offset: const Offset(0, 4))]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: selected ? color.withValues(alpha: 0.15) : MDColors.ink100,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: selected ? color : MDColors.ink500, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: MDColors.ink900)),
                        const SizedBox(width: 8),
                        if (selected)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text('ACTIVE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(fontSize: 13, color: MDColors.ink500)),
                  ],
                ),
              ),
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: selected ? color : MDColors.ink400),
            ],
          ),
        ),
      ),
    );
  }
}


