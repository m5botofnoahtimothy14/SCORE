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

class MentorDoubtConversationScreen extends ConsumerStatefulWidget {
  final String requestId;
  const MentorDoubtConversationScreen({super.key, required this.requestId});

  @override
  ConsumerState<MentorDoubtConversationScreen> createState() =>
      _MentorDoubtConversationScreenState();
}

class _MentorDoubtConversationScreenState
    extends ConsumerState<MentorDoubtConversationScreen> {
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
      final supabase = Supabase.instance.client;
      await supabase
          .from('doubt_requests')
          .select()
          .eq('id', widget.requestId)
          .maybeSingle();
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
        title: const Text('Doubt Conversation'),
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : const Center(child: Text('Doubt Conversation Screen')),
    );
  }
}