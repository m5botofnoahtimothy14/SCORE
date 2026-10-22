import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/layout/responsive.dart';
import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';
import '../../mentor_desk/models/mentor_desk_models.dart';
import '../../mentor_desk/services/mentor_desk_service.dart';

final _serviceProvider = Provider<MentorDeskService>(
  (ref) => MentorDeskService(Supabase.instance.client),
);

/// Mentor availability: set Available / Away. Appears online only when
/// Available and the app is connected (server-side heartbeat).
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
  List<MentorAvailability> _all = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final identity = await ref.read(identityProvider.future);
    final service = ref.read(_serviceProvider);
    final all = await service.listAvailability(identity.schoolId);
    // Find own
    String own = 'away';
    for (final a in all) {
      if (a.teacherId == identity.teacherId) own = a.status;
    }
    if (!mounted) return;
    setState(() {
      _status = own;
      _all = all;
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
    final accent = TierAccent.of(AppTier.teacher);
    return Scaffold(
      appBar: AppBar(title: const Text('My availability')),
      body: _loading
          ? const LoadingView()
          : AdaptivePage(
              maxWidth: 600,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const Text('Set whether students can see you as available.', style: TextStyle(fontSize: 15)),
                  const SizedBox(height: 20),
                  ListTile(
                    leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: accent.soft, borderRadius: BorderRadius.circular(12)), child: Icon(Icons.check_circle, color: accent.onSoft)),
                    title: const Text('Available'),
                    subtitle: const Text('You appear online to students and can accept requests.'),
                    trailing: Radio<String>(
                      value: 'available',
                      groupValue: _status,
                      onChanged: (v) => setState(() => _status = v!),
                      activeColor: accent.solid,
                    ),
                  ),
                  ListTile(
                    leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.do_not_disturb, color: Color(0xFF64748B))),
                    title: const Text('Away'),
                    subtitle: const Text('You do not appear online; requests stay in the shared queue.'),
                    trailing: Radio<String>(
                      value: 'away',
                      groupValue: _status,
                      onChanged: (v) => setState(() => _status = v!),
                      activeColor: accent.solid,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('You appear online only when marked Available and the app is actively connected.', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13)),
                  ],
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
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
