import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/design/design_system.dart';
import '../../../core/models/identity.dart';
import '../../../core/providers/identity_provider.dart';
import '../../../core/widgets/premium_states.dart';
import '../../../core/widgets/premium_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _loading = true;
  String? _error;
  String _displayName = 'User';
  String? _tier;
  String? _schoolId;
  String? _role;
  int _openDoubts = 0;
  int _sessionMinutesLeft = 0;
  bool _urgentPassAvailable = false;

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
      final supabase = Supabase.instance.client;

      _schoolId = identity.schoolId;
      _role = identity.role;
      _tier = identity.tier.toString();

      final name = identity.displayName.isNotEmpty ? identity.displayName : 'User';
      if (!mounted) return;
      setState(() { _displayName = name; _loading = false; });

      // Load student allowances if student
      if (identity.tier.toString() == 'student') {
        final doubts = await supabase
            .from('doubt_requests')
            .select('id, status')
            .eq('student_id', identity.userId)
            .filter('status', 'in', '("pending_assignment","waiting","assigned","in_progress")');
        final sessions = await supabase
            .from('session_bookings')
            .select('allowance_minutes_used, status')
            .eq('student_id', identity.userId)
            .filter('status', 'in', '("confirmed","completed")');
        final settings = await supabase
            .from('mentor_desk_settings')
            .select('session_allowance_minutes')
            .eq('school_id', identity.schoolId)
            .maybeSingle();
        final allowance = settings?['session_allowance_minutes'] ?? 60;
        final used = sessions.fold<int>(0, (sum, s) => sum + ((s['allowance_minutes_used'] as num?)?.toInt() ?? 0));
        if (!mounted) return;
        setState(() {
          _openDoubts = doubts.length;
          _sessionMinutesLeft = allowance - used;
          _urgentPassAvailable = true;
          _loading = false;
        });
      } else {
        if (!mounted) return;
        setState(() { _loading = false; });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = STierAccent.of(_tier);
    return Scaffold(
      backgroundColor: SColor.background,
      body: _loading
          ? const PremiumLoading()
          : _error != null
              ? PremiumError(message: _error!, onRetry: _load)
              : SafeArea(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(SLayout.gutter(context), 16, SLayout.gutter(context), 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Welcome back, $_displayName',
                                    style: STextStyle.displayLarge.copyWith(fontSize: 26),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _role != null ? _role!.replaceAll('_', ' ').toUpperCase() : '',
                                    style: STextStyle.overline.copyWith(color: SColor.accentCyan),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(color: SColor.surface, borderRadius: SRadii.mdAll, border: Border.all(color: SColor.border)),
                              child: IconButton(icon: const Icon(Icons.refresh, color: SColor.electricBlue, size: 20), onPressed: _load, tooltip: 'Refresh'),
                            ),
                          ],
                        ),
                        const SizedBox(height: SSpace.lg),
                        _SectionHeader(title: 'Quick Actions'),
                        const SizedBox(height: SSpace.sm),
                        _QuickActionGrid(tier: _tier ?? 'student', context: context),
                        const SizedBox(height: SSpace.lg),
                        _SectionHeader(title: 'Your weekly allowance'),
                        const SizedBox(height: SSpace.sm),
                        Row(
                          children: [
                            Expanded(child: _MetricTile(icon: Icons.question_answer_outlined, label: 'Open doubts', value: '$_openDoubts', tier: accent, onTap: () => context.go('/mentor-desk/doubts'))),
                            const SizedBox(width: SSpace.md),
                            Expanded(child: _MetricTile(icon: Icons.access_time_outlined, label: 'Session minutes left', value: '$_sessionMinutesLeft min', tier: accent, onTap: () => context.go('/mentor-desk/session/book'))),
                          ],
                        ),
                        const SizedBox(height: SSpace.sm),
                        _MetricTile(icon: Icons.flash_on_outlined, label: 'Urgent pass', value: _urgentPassAvailable ? 'Available' : 'Used', tier: accent, onTap: null),
                        const SizedBox(height: SSpace.lg),
                        _SectionHeader(title: 'Mentor Desk'),
                        const SizedBox(height: SSpace.sm),
                        PremiumCard(
                          onTap: () => context.go(_tier == 'student' ? '/mentor-desk' : _tier == 'teacher' ? '/mentor-desk/queue' : '/mentor-desk/slt'),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_tier == 'student' ? 'Need help with a doubt?' : _tier == 'teacher' ? 'Check your queue' : 'View oversight dashboard',
                                        style: STextStyle.headingMedium.copyWith(color: SColor.primaryText)),
                                    const SizedBox(height: SSpace.xs),
                                    Text(_tier == 'student' ? 'Ask a doubt or book a session with a mentor.' : _tier == 'teacher' ? 'Review and resolve pending student requests.' : 'Monitor program metrics and escalations.',
                                        style: STextStyle.bodySmall.copyWith(color: SColor.secondaryText)),
                                    const SizedBox(height: SSpace.md),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        onPressed: () => context.go(_tier == 'student' ? '/mentor-desk' : _tier == 'teacher' ? '/mentor-desk/queue' : '/mentor-desk/slt'),
                                        child: const Text('Open Mentor Desk', style: TextStyle(fontWeight: FontWeight.w800)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: SSpace.md),
                              Container(
                                width: 64, height: 64,
                                decoration: BoxDecoration(color: accent.soft, borderRadius: SRadii.lgAll),
                                child: Icon(_tier == 'student' ? Icons.support_agent : _tier == 'teacher' ? Icons.list : Icons.insights, color: accent.solid, size: 32),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: SSpace.lg),
                        _SectionHeader(title: 'Notices'),
                        const SizedBox(height: SSpace.sm),
                        PremiumCard(
                          child: Row(
                            children: [
                              Container(width: 44, height: 44, decoration: BoxDecoration(color: SColor.infoSoft, borderRadius: SRadii.mdAll), child: const Icon(Icons.campaign, color: SColor.info, size: 22)),
                              const SizedBox(width: SSpace.md),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('No new notices', style: STextStyle.headingSmall.copyWith(fontWeight: FontWeight.w800)),
                                SizedBox(height: 2),
                                Text('Check back later for school announcements.', style: STextStyle.captionMuted),
                              ])),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(title, style: STextStyle.headingSmall.copyWith(fontWeight: FontWeight.w800, color: SColor.primaryText)),
      const Spacer(),
    ]);
  }
}

class _QuickActionGrid extends StatelessWidget {
  final String tier;
  final BuildContext context;
  const _QuickActionGrid({required this.tier, required this.context});

  List<_QuickAction> _actions() {
    switch (tier) {
      case 'teacher':
        return [
          _QuickAction(icon: Icons.list, label: 'Queue', route: '/mentor-desk/queue', color: SColor.success),
          _QuickAction(icon: Icons.accessibility, label: 'Availability', route: '/mentor-desk/availability', color: SColor.teacherTier),
          _QuickAction(icon: Icons.campaign, label: 'Notices', route: '/announcements', color: SColor.info),
          _QuickAction(icon: Icons.person, label: 'Profile', route: '/profile', color: SColor.teacherTier),
        ];
      case 'platform_owner':
      case 'school_admin':
      case 'principal':
        return [
          _QuickAction(icon: Icons.insights, label: 'Oversight', route: '/mentor-desk/slt', color: SColor.leadershipTier),
          _QuickAction(icon: Icons.campaign, label: 'Notices', route: '/announcements', color: SColor.info),
          _QuickAction(icon: Icons.person, label: 'Profile', route: '/profile', color: SColor.leadershipTier),
        ];
      default:
        return [
          _QuickAction(icon: Icons.support_agent, label: 'Mentor Desk', route: '/mentor-desk', color: SColor.electricBlue),
          _QuickAction(icon: Icons.auto_awesome, label: 'AI Ask', route: '/ai-ask', color: SColor.accentCyan),
          _QuickAction(icon: Icons.campaign, label: 'Notices', route: '/announcements', color: SColor.info),
          _QuickAction(icon: Icons.person, label: 'Profile', route: '/profile', color: SColor.teacherTier),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = _actions();
    final cols = SLayout.columns(context, max: 3);
    return GridView.count(
      crossAxisCount: cols,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: SSpace.md,
      crossAxisSpacing: SSpace.md,
      childAspectRatio: 1.5,
      children: actions.map((a) => _ActionTile(action: a)).toList(),
    );
  }
}

class _QuickAction {
  final IconData icon; final String label; final String route; final Color color;
  const _QuickAction({required this.icon, required this.label, required this.route, required this.color});
}

class _ActionTile extends StatelessWidget {
  final _QuickAction action;
  const _ActionTile({required this.action});
  @override
  Widget build(BuildContext context) {
    return Material(color: Colors.transparent, child: InkWell(
      borderRadius: SRadii.lgAll, onTap: () => context.go(action.route),
      child: Container(
        decoration: BoxDecoration(color: SColor.surface, borderRadius: SRadii.lgAll, border: Border.all(color: SColor.border), boxShadow: SShadow.card),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(color: action.color.withValues(alpha: 0.12), borderRadius: SRadii.mdAll),
            child: Icon(action.icon, color: action.color, size: 24)),
          const SizedBox(height: SSpace.sm),
          Text(action.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: SColor.primaryText)),
        ]),
      ),
    ));
  }
}

class _MetricTile extends StatelessWidget {
  final IconData icon; final String label; final String value; final STierAccent tier; final VoidCallback? onTap;
  const _MetricTile({required this.icon, required this.label, required this.value, required this.tier, this.onTap});
  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      onTap: onTap,
      padding: const EdgeInsets.all(SSpace.md),
      child: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: tier.soft, borderRadius: SRadii.mdAll), child: Icon(icon, color: tier.solid, size: 20)),
        const SizedBox(width: SSpace.md),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: STextStyle.caption.copyWith(color: SColor.secondaryText, fontSize: 11)),
          const SizedBox(height: 2),
          Text(value, style: STextStyle.headingMedium.copyWith(fontWeight: FontWeight.w800, color: SColor.primaryText)),
        ])),
        Icon(Icons.chevron_right, color: SColor.textMuted, size: 20),
      ]),
    );
  }
}
