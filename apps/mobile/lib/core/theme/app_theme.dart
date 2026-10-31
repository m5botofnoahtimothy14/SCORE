import 'package:flutter/material.dart';
import '../models/identity.dart';

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// TeachCross Professional Design System
// Glossy, modern, readable — deep navy + electric blue with soft accents
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class AppColors {
  // ━ Brand — deep professional navy
  static const brand = Color(0xFF0F1E33);        // Deep navy base
  static const brandDark = Color(0xFF0A1422);     // Even deeper
  static const brandDeep = Color(0xFF060E18);     // Near-black navy
  static const brandLight = Color(0xFF1E3A5F);    // Lighter navy
  static const brandSheen = Color(0xFFFFFFFF);    // Pure white highlight

  // ━ Accent — vibrant electric blue for glossy highlights
  static const accent = Color(0xFF2563EB);        // Electric blue
  static const accentLight = Color(0xFF3B82F6);
  static const accentGlow = Color(0xFF60A5FA);

  // ━ Tier colors
  static const studentTier = Color(0xFF2563EB);   // Blue
  static const teacherTier = Color(0xFF059669);   // Emerald green
  static const leadershipTier = Color(0xFF7C3AED); // Purple

  // ━ Ink — text hierarchy (never pure black)
  static const ink900 = Color(0xFF1E293B);        // Near-black slate
  static const ink700 = Color(0xFF334155);        // Slate gray
  static const ink600 = Color(0xFF475569);        // Muted slate
  static const ink500 = Color(0xFF64748B);        // Medium slate
  static const ink400 = Color(0xFF94A3B8);        // Light slate
  static const ink300 = Color(0xFFCBD5E1);        // Lighter slate
  static const ink200 = Color(0xFFE2E8F0);        // Very light slate
  static const ink100 = Color(0xFFF1F5F9);        // Almost white slate
  static const ink50 = Color(0xFFF8FAFC);         // Background tint

  // ━ Semantic colors
  static const success = Color(0xFF10B981);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
  static const info = Color(0xFF3B82F6);

  // ━ Surfaces — glossy layered look
  static const surface = Color(0xFFF8FAFC);
  static const surfaceCard = Color(0xFFFFFFFF);
  static const surfaceElevated = Color(0xFFF1F5F9);
  static const surfaceGloss = Color(0xFFE2E8F0);
  static const glassDark = Color(0xFF0A0E22);

  // ━ Gradients
  static const brandGradient = LinearGradient(
    colors: [Color(0xFF0F1E33), Color(0xFF1E3A5F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const glossyGradient = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFF1F5F9)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

// ━ Spacing & radius
const double kGutter = 16;
const double kRadiusSm = 12;
const double kRadiusLg = 24;
const double kRadiusXl = 32;

// ━ Tier accent configuration
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

  static TierAccent of(AppTier tier) => switch (tier) {
    AppTier.student => const TierAccent(
          gradient: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
          solid: Color(0xFF2563EB),
          soft: Color(0xFFEFF6FF),
          onSoft: Color(0xFF1D4ED8),
        ),
    AppTier.teacher => const TierAccent(
          gradient: [Color(0xFF059669), Color(0xFF047857)],
          solid: Color(0xFF059669),
          soft: Color(0xFFECFDF5),
          onSoft: Color(0xFF047857),
        ),
    AppTier.leadership => const TierAccent(
          gradient: [Color(0xFF7C3AED), Color(0xFF6B21A8)],
          solid: Color(0xFF7C3AED),
          soft: Color(0xFFFAF5FF),
          onSoft: Color(0xFF6B21A8),
        ),
  };
}

// ━ Public MDTier (replaces private _MDTier)
class MDTier {
  final List<Color> gradient;
  final Color solid;
  final Color soft;
  final Color onSoft;

  const MDTier({
    required this.gradient,
    required this.solid,
    required this.soft,
    required this.onSoft,
  });

  static const MDTier student = MDTier(
    gradient: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
    solid: Color(0xFF2563EB),
    soft: Color(0xFFEFF6FF),
    onSoft: Color(0xFF1D4ED8),
  );

  static const MDTier teacher = MDTier(
    gradient: [Color(0xFF059669), Color(0xFF047857)],
    solid: Color(0xFF059669),
    soft: Color(0xFFECFDF5),
    onSoft: Color(0xFF047857),
  );

  static const MDTier leadership = MDTier(
    gradient: [Color(0xFF7C3AED), Color(0xFF6B21A8)],
    solid: Color(0xFF7C3AED),
    soft: Color(0xFFFAF5FF),
    onSoft: Color(0xFF6B21A8),
  );
}

// ━ MDColors alias for backward compat
class MDColors {
  static const brand = AppColors.brand;
  static const brandDark = AppColors.brandDark;
  static const brandDeep = AppColors.brandDeep;
  static const brandLight = AppColors.brandLight;
  static const brandSheen = AppColors.brandSheen;
  static const accent = AppColors.accent;
  static const accentLight = AppColors.accentLight;
  static const accentGlow = AppColors.accentGlow;
  static const studentTier = AppColors.studentTier;
  static const teacherTier = AppColors.teacherTier;
  static const leadershipTier = AppColors.leadershipTier;

  static const ink900 = AppColors.ink900;
  static const ink700 = AppColors.ink700;
  static const ink600 = AppColors.ink600;
  static const ink500 = AppColors.ink500;
  static const ink400 = AppColors.ink400;
  static const ink300 = AppColors.ink300;
  static const ink200 = AppColors.ink200;
  static const ink100 = AppColors.ink100;
  static const ink50 = AppColors.ink50;

  static const success = AppColors.success;
  static const warning = AppColors.warning;
  static const danger = AppColors.danger;
  static const info = AppColors.info;

  static const surface = AppColors.surface;
  static const surfaceCard = AppColors.surfaceCard;
  static const surfaceElevated = AppColors.surfaceElevated;
  static const surfaceGloss = AppColors.surfaceGloss;
  static const glassDark = AppColors.glassDark;
}

// ━ ThemeData — light & dark
class AppTheme {
  static ThemeData light() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      brightness: Brightness.light,
      surface: AppColors.surface,
    ),
    fontFamily: 'Inter',
    fontFamilyFallback: const ['Times New Roman', 'Times', 'serif'],
    scaffoldBackgroundColor: AppColors.surface,
    cardTheme: CardThemeData(
      elevation: 0,
      color: AppColors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(24)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.ink50,
      border: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: AppColors.ink300.withValues(alpha: 0.5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: AppColors.accent, width: 2),
      ),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.ink500,
      ),
      hintStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.ink300,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: const BorderRadius.all(Radius.circular(12))),
        elevation: 8,
        shadowColor: AppColors.brand.withValues(alpha: 0.4),
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accent,
        shape: RoundedRectangleBorder(borderRadius: const BorderRadius.all(Radius.circular(12))),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.accent,
        side: BorderSide(color: AppColors.accent, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: const BorderRadius.all(Radius.circular(12))),
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: const BorderRadius.all(Radius.circular(24))),
      elevation: 12,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: AppColors.ink900,
        letterSpacing: -0.5,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: AppColors.ink900,
        letterSpacing: -0.4,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.ink900,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.ink900,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: AppColors.ink700,
        height: 1.6,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.ink700,
        height: 1.6,
      ),
      bodySmall: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.ink500,
        height: 1.6,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.ink700,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.ink500,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.ink300,
      ),
    ),
  );

  static ThemeData dark() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      brightness: Brightness.dark,
      surface: const Color(0xFF0A0E22),
    ),
    fontFamily: 'Inter',
    fontFamilyFallback: const ['Times New Roman', 'Times', 'serif'],
    scaffoldBackgroundColor: const Color(0xFF0A0E22),
    cardTheme: CardThemeData(
      elevation: 0,
      color: const Color(0xFF141E3A),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(24)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF141E3A),
      border: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Colors.white24),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: AppColors.accent, width: 2),
      ),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.white70,
      ),
      hintStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: Colors.white38,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: const BorderRadius.all(Radius.circular(12))),
        elevation: 8,
        shadowColor: AppColors.accent.withValues(alpha: 0.4),
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accentLight,
        shape: RoundedRectangleBorder(borderRadius: const BorderRadius.all(Radius.circular(12))),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.accentLight,
        side: BorderSide(color: AppColors.accentLight, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: const BorderRadius.all(Radius.circular(12))),
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: const BorderRadius.all(Radius.circular(24))),
      elevation: 12,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: Colors.white,
        letterSpacing: -0.5,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        letterSpacing: -0.4,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: Colors.white70,
        height: 1.6,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Colors.white70,
        height: 1.6,
      ),
      bodySmall: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: Colors.white54,
        height: 1.6,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Colors.white54,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Colors.white38,
      ),
    ),
  );
}
