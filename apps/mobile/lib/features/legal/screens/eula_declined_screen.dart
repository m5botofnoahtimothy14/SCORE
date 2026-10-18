// Where a user lands after declining the terms.
//
// Declining is a legitimate outcome, not an error: the session is closed and
// the app is unavailable until the terms are accepted. This screen says so
// plainly and offers the only way forward — no dead ends, no loop back into a
// gated screen.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/developer_signature.dart';

class EulaDeclinedScreen extends StatelessWidget {
  const EulaDeclinedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.gpp_maybe_outlined,
                  size: 60,
                  color: AppColors.danger,
                ),
                const SizedBox(height: 20),
                Text(
                  'You need to accept the terms',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  'TeachCross is only available to people who accept the End '
                  'User Licence Agreement and Acceptable Use Policy. You '
                  'declined, so your session has been closed and no school '
                  'data is available on this device.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  'If you think this was a mistake, or you would like to read '
                  'the terms with your school office before deciding, review '
                  'them below. You can also contact your school office.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => context.go('/legal/eula'),
                  child: const Text('Review and accept the terms'),
                ),
                const SizedBox(height: 24),
                const DeveloperSignature(compact: true),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
