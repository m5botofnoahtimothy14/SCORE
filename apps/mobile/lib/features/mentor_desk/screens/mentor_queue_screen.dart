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

final _serviceProvider = Provider((ref) => Supabase.instance.client);

class MentorQueueScreen extends ConsumerStatefulWidget {
  const MentorQueueScreen({super.key});

  @override
  ConsumerState<MentorQueueScreen> createState() => _MentorQueueScreenState();
}

class _MentorQueueScreenState extends ConsumerState<MentorQueueScreen> {
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
      final identity = await ref.read(identityProviderProvider.future);
      final supabase = Supabase.instance.client;
      final query = supabase.from('doubt_requests').select();
      if (identity != null) {
        // Use filter with 'in' operator since .in() is a Dart keyword
        await query.filter('status', 'in', '("pending_assignment","waiting","assigned")');
      }
      if (!mounted) return;
      setState(() { _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MDColors.ink50,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Mentor Queue'),
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : const Center(child: Text('Mentor Queue Screen')),
    );
  }
}