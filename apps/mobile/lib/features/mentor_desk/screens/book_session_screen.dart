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

class BookSessionScreen extends ConsumerStatefulWidget {
  const BookSessionScreen({super.key});

  @override
  ConsumerState<BookSessionScreen> createState() => _BookSessionScreenState();
}

class _BookSessionScreenState extends ConsumerState<BookSessionScreen> {
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
      if (identity != null) {
        await supabase
            .from('session_bookings')
            .select()
            .eq('student_id', identity.userId);
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
        title: const Text('Book a Session'),
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : const Center(child: Text('Book Session Screen')),
    );
  }
}