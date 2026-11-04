import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mentor_desk_design.dart';
import '../../../core/layout/responsive.dart';
import '../../../core/widgets/states.dart';
import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../models/mentor_desk_models.dart';
import '../services/mentor_desk_service.dart';

final mentorDeskServiceProvider = Provider<MentorDeskService>((ref) {
  return MentorDeskService(Supabase.instance.client);
});

class BookSessionScreen extends ConsumerStatefulWidget {
  const BookSessionScreen({super.key});

  @override
  ConsumerState<BookSessionScreen> createState() => _BookSessionScreenState();
}

class _BookSessionScreenState extends ConsumerState<BookSessionScreen> {
  final _topicController = TextEditingController();
  final _preparationController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  String? _error;
  List<SubjectWithName> _subjects = [];
  List<TeacherMentor> _mentors = [];
  String? _subjectId;
  String? _mentorId; // null = any available
  int _durationMinutes = 30;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String? _schoolId;
  String? _studentId;
  int _sessionAllowanceMinutes = 120;
  int _sessionUsedMinutes = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final identity = await ref.read(identityProviderProvider.future);
      if (identity == null) throw Exception('No identity found');
      _schoolId = identity.schoolId;
      _studentId = identity.studentId ?? identity.userId;

      final service = ref.read(mentorDeskServiceProvider);
      final subjects = await service.listSubjects(_schoolId!);

      // Get settings for allowance
      final settings = await service.getSettings(_schoolId!);
      _sessionAllowanceMinutes = settings?.sessionAllowanceMinutes ?? 120;
      _sessionUsedMinutes = settings?.sessionUsedMinutes ?? 0;

      // Load available mentors (teachers with subject approvals)
      final teachers = await Supabase.instance.client
          .from('teachers')
          .select('id, staff_id_no, first_name, last_name, is_active')
          .eq('school_id', _schoolId!)
          .eq('is_active', true);
      _mentors = (teachers as List)
          .map((r) => TeacherMentor.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();

      if (!mounted) return;
      setState(() {
        _subjects = subjects;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  int get _remainingMinutes => _sessionAllowanceMinutes - _sessionUsedMinutes;

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 14)),
    );
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? const TimeOfDay(hour: 10, minute: 0),
    );
    if (time == null) return;
    setState(() {
      _selectedDate = date;
      _selectedTime = time;
    });
  }

  Future<void> _book() async {
    if (!_formKey.currentState!.validate()) return;
    if (_subjectId == null) {
      setState(() { _error = 'Please select a subject.'; });
      return;
    }
    if (_selectedDate == null || _selectedTime == null) {
      setState(() { _error = 'Please select date and time.'; });
      return;
    }
    final duration = _durationMinutes;
    if (duration > _remainingMinutes) {
      setState(() { _error = 'This session exceeds your remaining weekly allowance ($_remainingMinutes min).'; });
      return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      final service = ref.read(mentorDeskServiceProvider);
      final scheduledAt = DateTime(
        _selectedDate!.year, _selectedDate!.month, _selectedDate!.day,
        _selectedTime!.hour, _selectedTime!.minute,
      );

      await service.bookSession(
        subjectId: _subjectId!,
        mentorId: _mentorId,
        durationMinutes: duration,
        scheduledAt: scheduledAt,
        topic: _topicController.text.trim(),
        preparation: _preparationController.text.trim().isEmpty ? null : _preparationController.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Session booked — awaiting mentor confirmation.'),
        backgroundColor: MDColors.success,
        duration: Duration(seconds: 4),
      ));
      context.go('/mentor-desk');
    } on MentorDeskException catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.message; });
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
        title: const Text('Book a Session', style: TextStyle(color: MDColors.ink900, fontWeight: FontWeight.w800)),
        centerTitle: false,
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    horizontalGutter(context),
                    16,
                    horizontalGutter(context),
                    MediaQuery.of(context).padding.bottom + 24,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Book a Session',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Choose subject, mentor, time and length. Confirmation is set once the mentor accepts.',
                          style: TextStyle(fontSize: 14, color: MDColors.ink600),
                        ),
                        const SizedBox(height: 20),

                        // Allowance banner
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: MDColors.ink100,
                            borderRadius: BorderRadius.circular(kRadiusLg),
                            border: Border.all(color: MDColors.ink200),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.access_time, color: MDColors.brand, size: 24),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Weekly session allowance', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MDColors.ink500)),
                                    Text('$_remainingMinutes min left of $_sessionAllowanceMinutes min',
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: MDColors.ink900)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Subject
                        _SelectField(
                          label: 'Subject *',
                          value: _subjects.firstWhere((s) => s.id == _subjectId,
                              orElse: () => SubjectWithName(id: '', name: 'Select subject')).name,
                          onTap: _pickSubject,
                        ),
                        const SizedBox(height: 16),

                        // Mentor
                        Text(
                          'Mentor (optional — leave blank for any available)',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MDColors.ink700),
                        ),
                        const SizedBox(height: 8),
                        _SelectField(
                          label: 'Mentor',
                          value: _mentorId == null ? 'Any available' : (_mentors.firstWhere((m) => m.id == _mentorId,
                              orElse: () => TeacherMentor(id: '', staffIdNo: '', firstName: '', lastName: '', isActive: false)).fullName),
                          onTap: _pickMentor,
                        ),
                        const SizedBox(height: 16),

                        // Duration
                        const Text('Session length *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MDColors.ink700)),
                        const SizedBox(height: 8),
                        Row(
                          children: [15, 30, 45].map((d) {
                            final selected = _durationMinutes == d;
                            final canSelect = d <= _remainingMinutes;
                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text('$d min'),
                                  selected: selected,
                                  onSelected: canSelect ? (v) => setState(() { _durationMinutes = d; }) : null,
                                  selectedColor: MDColors.brand.withValues(alpha: 0.15),
                                  checkmarkColor: MDColors.brand,
                                  backgroundColor: MDColors.ink50,
                                  labelStyle: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: canSelect ? (selected ? MDColors.brand : MDColors.ink900) : MDColors.ink400,
                                  ),
                                  side: BorderSide(
                                    color: canSelect ? (selected ? MDColors.brand : MDColors.ink300) : MDColors.ink200,
                                    width: selected ? 2 : 1,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        if (_durationMinutes > _remainingMinutes)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text('$_durationMinutes min exceeds remaining allowance ($_remainingMinutes min)',
                                style: const TextStyle(fontSize: 11, color: MDColors.danger, fontWeight: FontWeight.w600)),
                          ),
                        const SizedBox(height: 20),

                        // Date & time
                        InkWell(
                          onTap: _pickDateTime,
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: MDColors.surfaceCard,
                              borderRadius: BorderRadius.circular(kRadiusSm),
                              border: Border.all(color: MDColors.ink300.withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today, color: MDColors.brand, size: 22),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Date & Time', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MDColors.ink700)),
                                      const SizedBox(height: 4),
                                      Text(
                                        _selectedDate == null
                                            ? 'Select date and time'
                                            : '${DateFormat('EEE, MMM d').format(_selectedDate!)} · ${_selectedTime!.format(context)}',
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: MDColors.ink900),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right, color: MDColors.ink400),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Topic
                        MDGlossInput(
                          controller: _topicController,
                          label: 'Topic *',
                          hint: 'What is this session about?',
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Topic is required' : null,
                        ),
                        const SizedBox(height: 16),

                        // Preparation
                        MDGlossInput(
                          controller: _preparationController,
                          label: 'Preparation details (optional)',
                          hint: 'What should the mentor prepare?',
                          maxLines: 3,
                        ),
                        const SizedBox(height: 24),

                        MDButton(
                          onPressed: _book,
                          loading: _loading,
                          child: const Text('Book Session', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
    );
  }

  Future<void> _pickSubject() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
          decoration: const BoxDecoration(
            color: MDColors.surfaceCard,
            borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: MDColors.ink200, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    const Text('Select Subject', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => context.pop()),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _subjects.length,
                  itemBuilder: (context, index) {
                    final s = _subjects[index];
                    final selected = _subjectId == s.id;
                    return ListTile(
                      leading: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: selected ? MDColors.brand.withValues(alpha: 0.12) : MDColors.ink100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: selected ? MDColors.brand : MDColors.ink200),
                        ),
                        child: Icon(Icons.book_outlined, color: selected ? MDColors.brand : MDColors.ink600, size: 20),
                      ),
                      title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(s.code ?? '', style: const TextStyle(fontSize: 11, color: MDColors.ink500)),
                      trailing: selected ? const Icon(Icons.check, color: MDColors.brand) : null,
                      onTap: () {
                        setState(() { _subjectId = s.id; _mentorId = null; });
                        context.pop();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickMentor() async {
    final available = _mentors.where((m) => m.isActive).toList();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
          decoration: const BoxDecoration(
            color: MDColors.surfaceCard,
            borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: MDColors.ink200, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    const Text('Select Mentor', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => context.pop()),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: available.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      final selected = _mentorId == null;
                      return ListTile(
                        leading: const Icon(Icons.people_outline, color: MDColors.ink600),
                        title: const Text('Any available mentor', style: TextStyle(fontWeight: FontWeight.w700)),
                        trailing: selected ? const Icon(Icons.check, color: MDColors.brand) : null,
                        onTap: () {
                          setState(() { _mentorId = null; });
                          context.pop();
                        },
                      );
                    }
                    final m = available[index - 1];
                    final selected = _mentorId == m.id;
                    return ListTile(
                      leading: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: selected ? MDColors.teacherTier.withValues(alpha: 0.12) : MDColors.ink100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: selected ? MDColors.teacherTier : MDColors.ink200),
                        ),
                        child: const Icon(Icons.person_outlined, color: MDColors.teacherTier, size: 20),
                      ),
                      title: Text('${m.firstName} ${m.lastName}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(m.staffIdNo ?? '', style: const TextStyle(fontSize: 11, color: MDColors.ink500)),
                      trailing: selected ? const Icon(Icons.check, color: MDColors.brand) : null,
                      onTap: () {
                        setState(() { _mentorId = m.id; });
                        context.pop();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}


class _SelectField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _SelectField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.ink700,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(kRadiusSm),
              border: Border.all(color: AppColors.ink300.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.subject, size: 20, color: AppColors.ink500),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.ink900,
                    ),
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down,
                    color: AppColors.ink400),
              ],
            ),
          ),
        ),
      ],
    );
  }
}



