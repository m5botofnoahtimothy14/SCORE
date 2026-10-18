// The CRIMSON X NOAH TIMOTHY KEBA signature block.
//
// Shown wherever the app needs to state who built it and how to reach support:
// the EULA footer and the profile screen. Every string comes from
// [AppConfig], so the lockup is written in exactly one place.
import 'package:flutter/material.dart';

import '../config/app_config.dart';

class DeveloperSignature extends StatelessWidget {
  /// Condensed form for tight spaces (EULA footer, profile bottom).
  final bool compact;

  const DeveloperSignature({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.textTheme.titleMedium?.color;
    final muted = theme.textTheme.bodySmall?.color;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 20,
        vertical: compact ? 14 : 18,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compact ? 14 : 18),
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment:
            compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            AppConfig.signatureLine,
            textAlign: compact ? TextAlign.center : TextAlign.start,
            style: TextStyle(
              color: onSurface,
              fontSize: compact ? 11.5 : 14,
              fontWeight: FontWeight.w700,
              letterSpacing: compact ? 1.5 : 1.1,
              height: 1.3,
            ),
          ),
          SizedBox(height: compact ? 6 : 8),
          Text(
            'Developed by ${AppConfig.developerName}',
            textAlign: compact ? TextAlign.center : TextAlign.start,
            style: TextStyle(
              color: muted,
              fontSize: compact ? 12 : 13.5,
              height: 1.35,
            ),
          ),
          SizedBox(height: compact ? 10 : 16),
          _ContactLine(
            icon: Icons.mail_outline,
            value: AppConfig.supportEmail,
            compact: compact,
            muted: muted,
          ),
          SizedBox(height: compact ? 5 : 8),
          _ContactLine(
            icon: Icons.phone_outlined,
            value: AppConfig.supportPhone,
            compact: compact,
            muted: muted,
          ),
        ],
      ),
    );
  }
}

class _ContactLine extends StatelessWidget {
  final IconData icon;
  final String value;
  final bool compact;
  final Color? muted;

  const _ContactLine({
    required this.icon,
    required this.value,
    required this.compact,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment:
          compact ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        Icon(icon, size: compact ? 13 : 15, color: muted),
        const SizedBox(width: 7),
        // Selectable so the contact details can be copied without a URL
        // launcher dependency (mailto:/tel: are not wired up on purpose).
        Flexible(
          child: SelectableText(
            value,
            textAlign: compact ? TextAlign.center : TextAlign.start,
            style: TextStyle(
              color: muted,
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}
