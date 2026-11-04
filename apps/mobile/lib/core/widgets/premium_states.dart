import 'package:flutter/material.dart';
import '../design/design_system.dart';

/// Premium loading state.
class PremiumLoading extends StatelessWidget {
  const PremiumLoading({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator(color: SColor.electricBlue));
}

/// Premium error state with retry.
class PremiumError extends StatelessWidget {
  final String message; final VoidCallback onRetry;
  const PremiumError({super.key, required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.error_outline, size: 64, color: SColor.error),
    const SizedBox(height: SSpace.md),
    Text('Something went wrong', style: STextStyle.headingMedium.copyWith(fontWeight: FontWeight.w800)),
    const SizedBox(height: SSpace.sm),
    Text(message, style: STextStyle.bodyMedium.copyWith(color: SColor.secondaryText), textAlign: TextAlign.center),
    const SizedBox(height: SSpace.lg),
    ElevatedButton(onPressed: onRetry, child: const Text('Try Again')),
  ]));
}

/// Premium empty state.
class PremiumEmpty extends StatelessWidget {
  final IconData icon; final String title; final String subtitle; final String? actionLabel; final VoidCallback? onAction;
  const PremiumEmpty({super.key, required this.icon, required this.title, required this.subtitle, this.actionLabel, this.onAction});
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 64, color: SColor.textMuted),
    const SizedBox(height: SSpace.md),
    Text(title, style: STextStyle.headingMedium.copyWith(fontWeight: FontWeight.w800)),
    const SizedBox(height: SSpace.sm),
    Text(subtitle, style: STextStyle.bodyMedium.copyWith(color: SColor.secondaryText), textAlign: TextAlign.center),
    if (actionLabel != null && onAction != null) ...[
      const SizedBox(height: SSpace.lg),
      ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
    ],
  ]));
}

/// Premium success state.
class PremiumSuccess extends StatelessWidget {
  final IconData icon; final String title; final String subtitle; final String? actionLabel; final VoidCallback? onAction;
  const PremiumSuccess({super.key, required this.icon, required this.title, required this.subtitle, this.actionLabel, this.onAction});
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 64, color: SColor.success),
    const SizedBox(height: SSpace.md),
    Text(title, style: STextStyle.headingMedium.copyWith(fontWeight: FontWeight.w800)),
    const SizedBox(height: SSpace.sm),
    Text(subtitle, style: STextStyle.bodyMedium.copyWith(color: SColor.secondaryText), textAlign: TextAlign.center),
    if (actionLabel != null && onAction != null) ...[
      const SizedBox(height: SSpace.lg),
      ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
    ],
  ]));
}
