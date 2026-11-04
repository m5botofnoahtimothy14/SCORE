import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/app_config.dart';
import '../theme/app_theme.dart';

const Duration _kSplashDuration = Duration(seconds: 10);

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
            const Icon(Icons.school, size: 48, color: Colors.white),
            const SizedBox(height: 28),
            Text(
              AppConfig.signatureTop,
              semanticsLabel: AppConfig.signatureLine,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              AppConfig.signatureCross,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              AppConfig.signatureName,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Developed by ${AppConfig.developerName}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'SCORE+',
              style: TextStyle(
                color: Colors.white,
                fontSize: 40,
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(color: Colors.white),
          ],
        ),
      ),
    );
  }
}



