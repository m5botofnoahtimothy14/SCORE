// TeachCross design language: calm, glossy, professional.
//
// One system for both light and dark. Each role tier carries its own accent so
// a student, teacher and leader can tell at a glance which surface they are in.
import 'package:flutter/material.dart';

import '../models/identity.dart';

class AppColors {
  // Brand
  static const brand = Color(0xFF2563EB);
  static const brandDark = Color(0xFF1D4ED8);
  static const brandDeep = Color(0xFF1E3A8A);

  // Neutral ink
  static const ink900 = Color(0xFF0F172A);
  static const ink700 = Color(0xFF334155);
  static const ink500 = Color(0xFF64748B);
  static const ink300 = Color(0xFFCBD5E1);
  static const ink100 = Color(0xFFF1F5F9);
  static const ink50 = Color(0xFFF8FAFC);

  // Semantic
  static const success = Color(0xFF059669);
  static const warning = Color(0xFFD97706);
  static const danger = Color(0xFFDC2626);
  static const info = Color(0xFF0284C7);
}

/// Per-tier accent. Drives headers, nav highlights and hero cards.
class TierAccent {
  final List<Color> gradient;
  final Color solid;
  final Color soft;
  final Color onSoft;

  const TierAccent({
    required this.gradient,
    required this.solid,
    required this.soft,
    required this.onSoft,
  });

  Color get start => gradient.first;
  Color get end => gradient.last;

  static TierAccent of(AppTier tier) => switch (tier) {
        AppTier.student => const TierAccent(
            gradient: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
            solid: Color(0xFF2563EB),
            soft: Color(0xFFEFF6FF),
            onSoft: Color(0xFF1D4ED8),
          ),
        AppTier.teacher => const TierAccent(
            gradient: [Color(0xFF14B8A6), Color(0xFF0F766E)],
            solid: Color(0xFF0D9488),
            soft: Color(0xFFF0FDFA),
            onSoft: Color(0xFF0F766E),
          ),
        AppTier.leadership => const TierAccent(
            gradient: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
            solid: Color(0xFF7C3AED),
            soft: Color(0xFFF5F3FF),
            onSoft: Color(0xFF6D28D9),
          ),
      };
}

class AppTheme {
  static ThemeData light() => _base(
        brightness: Brightness.light,
        scheme: ColorScheme.fromSeed(
          seedColor: AppColors.brand,
          brightness: Brightness.light,
        ),
      );

  static ThemeData dark() => _base(
        brightness: Brightness.dark,
        scheme: ColorScheme.fromSeed(
          seedColor: AppColors.brand,
          brightness: Brightness.dark,
        ),
      );

  static ThemeData _base({
    required Brightness brightness,
    required ColorScheme scheme,
  }) {
    final isLight = brightness == Brightness.light;
    final surface = isLight ? Colors.white : const Color(0xFF111827);
    final canvas = isLight ? AppColors.ink50 : const Color(0xFF0B1120);
    final onSurface = isLight ? AppColors.ink900 : const Color(0xFFF1F5F9);
    final muted = isLight ? AppColors.ink500 : const Color(0xFF94A3B8);
    final hairline = isLight ? const Color(0xFFE2E8F0) : const Color(0xFF1F2937);

    final radius = BorderRadius.circular(16);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(surface: surface),
      scaffoldBackgroundColor: canvas,
      canvasColor: canvas,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      textTheme: _textTheme(onSurface, muted),

      // Surfaces get a soft edge + shadow rather than a hard border.
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: hairline),
        ),
      ),

      dividerTheme: DividerThemeData(color: hairline, thickness: 1, space: 1),

      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        backgroundColor: surface,
        foregroundColor: onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
        iconTheme: IconThemeData(color: onSurface),
      ),

      navigationBarTheme: NavigationBarThemeData(
        height: 66,
        elevation: 0,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: 0.10),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11.5,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 23,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : muted,
          ),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onSurface,
          minimumSize: const Size.fromHeight(48),
          side: BorderSide(color: hairline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? AppColors.ink50 : const Color(0xFF16213A),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: const BorderSide(color: AppColors.danger, width: 1.6),
        ),
        labelStyle: TextStyle(color: muted),
        hintStyle: TextStyle(color: muted.withValues(alpha: 0.7)),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: isLight ? AppColors.ink100 : const Color(0xFF1B2537),
        side: BorderSide.none,
        labelStyle: TextStyle(color: onSurface, fontSize: 12.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isLight ? AppColors.ink900 : const Color(0xFF1E293B),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      listTileTheme: ListTileThemeData(
        iconColor: muted,
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 15.5,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: TextStyle(color: muted, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    );
  }

  static TextTheme _textTheme(Color onSurface, Color muted) => TextTheme(
        headlineSmall: TextStyle(
          color: onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleLarge: TextStyle(
          color: onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        titleMedium: TextStyle(
          color: onSurface,
          fontSize: 15.5,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(color: onSurface, fontSize: 15, height: 1.45),
        bodyMedium: TextStyle(color: onSurface, fontSize: 14, height: 1.45),
        bodySmall: TextStyle(color: muted, fontSize: 13, height: 1.4),
        labelSmall: TextStyle(
          color: muted,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      );
}

/// Shared decorative building blocks used across role dashboards.

/// A glossy gradient hero used at the top of each role dashboard.
class GlossHero extends StatelessWidget {
  final TierAccent accent;
  final String eyebrow;
  final String title;
  final String? subtitle;
  final List<Widget> trailing;
  final Widget? child;

  const GlossHero({
    super.key,
    required this.accent,
    required this.eyebrow,
    required this.title,
    this.subtitle,
    this.trailing = const [],
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: accent.gradient,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.solid.withValues(alpha: 0.28),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Soft light bloom + top gloss give the surface a physical sheen.
          Positioned(
            right: -50,
            top: -60,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.14),
              ),
            ),
          ),
          Positioned(
            left: -30,
            bottom: -70,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.06),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            eyebrow.toUpperCase(),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.82),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 23,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.4,
                              height: 1.15,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 5),
                            Text(
                              subtitle!,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.86),
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (trailing.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Row(mainAxisSize: MainAxisSize.min, children: trailing),
                    ],
                  ],
                ),
                if (child != null) ...[const SizedBox(height: 18), child!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact metric tile for role dashboards.
class MetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final TierAccent accent;

  const MetricTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  color: accent.soft,
                ),
                child: Icon(icon, size: 19, color: accent.onSoft),
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  color: scheme.onSurface,
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Section heading with an optional trailing action.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}