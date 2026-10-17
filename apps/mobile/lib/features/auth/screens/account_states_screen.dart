import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shown when the account is suspended. Read-only; offers sign-out + support note.
class AccountSuspendedScreen extends StatelessWidget {
  const AccountSuspendedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.block, size: 72, color: Color(0xFFDC2626)),
              const SizedBox(height: 24),
              Text('Account suspended',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text(
                'Your access has been suspended by your school administrator. '
                'Contact your school office to resolve this.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () async {
                  await Supabase.instance.client.auth.signOut();
                  if (context.mounted) context.go('/auth/school-select');
                },
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when a user lands somewhere their role may not access.
class AccessDeniedScreen extends StatelessWidget {
  const AccessDeniedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Not available')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 64, color: Color(0xFF9CA3AF)),
              const SizedBox(height: 16),
              const Text('You do not have access to this area.',
                  textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF6B7280))),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: () => context.go('/home'), child: const Text('Back to Home')),
            ],
          ),
        ),
      ),
    );
  }
}
