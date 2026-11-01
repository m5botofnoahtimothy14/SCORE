import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/identity_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../models/mentor_desk_models.dart';
import '../services/mentor_desk_service.dart';

final _mentorServiceProvider = Provider((ref) => MentorDeskService(Supabase.instance.client));

class MentorAvailabilityScreen extends ConsumerStatefulWidget {
  const MentorAvailabilityScreen({super.key});

  @override
  ConsumerState<MentorAvailabilityScreen> createState() => _MentorAvailabilityScreenState();
}

class _MentorAvailabilityScreenState extends ConsumerState<MentorAvailabilityScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _myStatus = 'away';
  List<MentorAvailability> _availability = [];
  String? _myTeacherId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final identity = await ref.read(identityProviderProvider.future);
      if (identity == null) throw Exception('Account not found');
      final service = ref.read(_mentorServiceProvider);
      final teacher = await service.client
          .from('teachers')
          .select('id')
          .eq('user_id', identity.userId)
          .eq('is_active', true)
          .maybeSingle();
      final availability = await service.listAvailability(identity.schoolId);
      final teacherId = teacher?['id'] as String?;
      final mine = availability.where((item) => item.teacherId == teacherId).toList();
      if (!mounted) return;
      setState(() {
        _myTeacherId = teacherId;
        _availability = availability;
        _myStatus = mine.isEmpty ? 'away' : mine.first.status;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = 'Could not load teacher availability.'; _loading = false; });
    }
  }

  Future<void> _setStatus(String status) async {
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(_mentorServiceProvider).setAvailability(status);
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not update your availability.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Mentor availability'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _availability.isEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : ListView(
                  padding: const EdgeInsets.all(18),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.ink200)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Your status', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink900)),
                        const SizedBox(height: 6),
                        Text(_myTeacherId == null ? 'No active teacher profile is linked to this account.' : _myStatus == 'available' ? 'Students can request support from you.' : 'You are not currently accepting new requests.', style: const TextStyle(fontSize: 12, color: AppColors.ink500)),
                        const SizedBox(height: 16),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'available', label: Text('Available'), icon: Icon(Icons.check_circle_outline)),
                            ButtonSegment(value: 'away', label: Text('Away'), icon: Icon(Icons.pause_circle_outline)),
                          ],
                          selected: {_myStatus},
                          onSelectionChanged: _saving || _myTeacherId == null ? null : (value) => _setStatus(value.first),
                        ),
                        if (_saving) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
                        if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12))),
                      ]),
                    ),
                    const SizedBox(height: 22),
                    const Text('School mentor availability', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink900)),
                    const SizedBox(height: 10),
                    if (_availability.isEmpty)
                      const Text('No mentor availability records are available.')
                    else
                      ..._availability.map((item) => ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        tileColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13), side: const BorderSide(color: AppColors.ink200)),
                        leading: Icon(item.isAvailable ? Icons.check_circle : Icons.pause_circle_filled, color: item.isAvailable ? AppColors.success : AppColors.ink400),
                        title: Text(item.teacherId == _myTeacherId ? 'You' : 'Teacher'),
                        subtitle: Text(item.isAvailable ? 'Available' : 'Away'),
                      )),
                  ],
                ),
    );
  }
}
