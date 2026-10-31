import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class EulaDeclinedScreen extends StatelessWidget {
  const EulaDeclinedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.block, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Terms Declined',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'You must accept the terms to use SCORE+.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/legal/eula'),
              child: const Text('Accept Terms'),
            ),
          ],
        ),
      ),
    );
  }
}