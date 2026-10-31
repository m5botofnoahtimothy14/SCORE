import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/app_config.dart';
import '../theme/app_theme.dart';

const Duration _kSplashDuration = Duration(seconds: 3);

class SplashSequence extends StatefulWidget {
  const SplashSequence({super.key});

  @override
  State<SplashSequence> createState() => _SplashSequenceState();
}

class _SplashSequenceState extends State<SplashSequence> {
  @override
  void initState() {
    super.initState();
    Future.delayed(_kSplashDuration, () {
      if (mounted) {
        GoRouter.of(context).go('/auth/role-select');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.brand,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.school, size: 40, color: AppColors.brand),
            ),
            const SizedBox(height: 24),
            const Text(
              'SCORE+',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            const CircularProgressIndicator(
              color: Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}