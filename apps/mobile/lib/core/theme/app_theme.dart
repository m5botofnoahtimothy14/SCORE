import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/identity.dart';

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SCORE+ Design System v4 — Fresh Professional (completely new identity)
// Deep teal + warm orange on clean surfaces
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class SColor {
  static const Color primary = Color(0xFF0D9488);
  static const Color primaryLight = Color(0xFF14B8A6);
  static const Color primaryDark = Color(0xFF0F766E);
  static const Color accent = Color(0xFFF97316);
  static const Color accentSoft = Color(0xFFFFF7ED);
  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSoft = Color(0xFFF1F5F9);
  static const Color surfaceElevated = Color(0xFFF8FAFC);
  static const Color primaryText = Color(0xFF0F172A);
  static const Color secondaryText = Color(0xFF64748B);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color textInverse = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE2E8F0);
  static const Color borderSoft = Color(0xFFF1F5F9);
  static const Color divider = Color(0xFFE2E8F0);
  static const Color success = Color(0xFF22C55E);
  static const Color successSoft = Color(0xFFDCFCE7);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningSoft = Color(0xFFFEF3C7);
  static const Color error = Color(0xFFEF4444);
  static const Color errorSoft = Color(0xFFFEE2E2);
  static const Color info = Color(0xFF3B82F6);
  static const Color infoSoft = Color(0xFFDBEAFE);
  static const Color studentTier = Color(0xFF0D9488);
  static const Color teacherTier = Color(0xFF22C55E);
  static const Color leadershipTier = Color(0xFF8B5CF6);
  static const Color shadowColor = Color(0x0F000000);
}

class STextStyle {
  static const TextStyle displayLarge = TextStyle(fontFamily: 'Inter', fontSize: 28, fontWeight: FontWeight.w700, color: SColor.primaryText, height: 1.2, letterSpacing: -0.3);
  static const TextStyle displayMedium = TextStyle(fontFamily: 'Inter', fontSize: 22, fontWeight: FontWeight.w700, color: SColor.primaryText, height: 1.25, letterSpacing: -0.2);
  static const TextStyle headingLarge = TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w600, color: SColor.primaryText, height: 1.3);
  static const TextStyle headingMedium = TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600, color: SColor.primaryText, height: 1.3);
  static const TextStyle headingSmall = TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: SColor.primaryText, height: 1.3);
  static const TextStyle bodyLarge = TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w400, color: SColor.primaryText, height: 1.6);
  static const TextStyle bodyMedium = TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w400, color: SColor.primaryText, height: 1.6);
  static const TextStyle bodySmall = TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w400, color: SColor.primaryText, height: 1.5);
  static const TextStyle labelLarge = TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w500, color: SColor.primaryText);
  static const TextStyle labelMedium = TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w500, color: SColor.primaryText);
  static const TextStyle caption = TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w400, color: SColor.secondaryText, height: 1.4);
  static const TextStyle captionMuted = TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w400, color: SColor.textMuted, height: 1.4);
  static const TextStyle overline = TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w600, color: SColor.secondaryText, letterSpacing: 0.6);
  static const TextStyle button = TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: SColor.textInverse, letterSpacing: 0.1);
  static const TextStyle buttonSecondary = TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: SColor.primary, letterSpacing: 0.1);
}

class SSpace {
  static const double xs = 4, sm = 8, md = 16, lg = 20, xl = 28, xxl = 40;
}

class SRadii {
  static const Radius sm = Radius.circular(8), md = Radius.circular(12), lg = Radius.circular(16), xl = Radius.circular(20), full = Radius.circular(24);
  static const BorderRadius smAll = BorderRadius.all(Radius.circular(8));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(12));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(16));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(20));
}

class SShadow {
  static const List<BoxShadow> card = [BoxShadow(color: SColor.shadowColor, blurRadius: 12, offset: Offset(0, 2))];
  static const List<BoxShadow> elevated = [BoxShadow(color: SColor.shadowColor, blurRadius: 24, offset: Offset(0, 8))];
}

class STheme {
  static ThemeData light() => _buildTheme(Brightness.light);
  static ThemeData dark() => _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A) : SColor.background;
    final surfaceColor = isDark ? const Color(0xFF1E293B) : SColor.surface;
    final textColor = isDark ? const Color(0xFFF8FAFC) : SColor.primaryText;
    final secondaryTextColor = isDark ? const Color(0xFF94A3B8) : SColor.secondaryText;
    final mutedColor = isDark ? const Color(0xFF64748B) : SColor.textMuted;
    final borderColor = isDark ? const Color(0xFF334155) : SColor.border;
    final borderSoftColor = isDark ? const Color(0xFF1E293B) : SColor.borderSoft;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: bgColor,
      cardColor: surfaceColor,
      dividerColor: isDark ? const Color(0xFF334155) : SColor.divider,
      fontFamily: 'Inter',
      primaryColor: SColor.primary,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: SColor.primary,
        onPrimary: SColor.textInverse,
        secondary: SColor.accent,
        onSecondary: isDark ? SColor.textInverse : SColor.primaryText,
        surface: surfaceColor,
        onSurface: textColor,
        background: bgColor,
        onBackground: textColor,
        error: SColor.error,
        onError: SColor.textInverse,
        outline: borderColor,
      ),
      cardTheme: CardThemeData(
        color: surfaceColor,
        elevation: 0,
        shadowColor: isDark ? Colors.black26 : SColor.shadowColor,
        shape: RoundedRectangleBorder(borderRadius: SRadii.lgAll, side: BorderSide(color: borderColor)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1E293B) : SColor.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: SSpace.md, vertical: SSpace.md),
        isDense: true,
        border: OutlineInputBorder(borderRadius: SRadii.mdAll, borderSide: BorderSide(color: borderColor)),
        enabledBorder: OutlineInputBorder(borderRadius: SRadii.mdAll, borderSide: BorderSide(color: borderColor)),
        focusedBorder: OutlineInputBorder(borderRadius: SRadii.mdAll, borderSide: const BorderSide(color: SColor.primary, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: SRadii.mdAll, borderSide: const BorderSide(color: SColor.error)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: SRadii.mdAll, borderSide: const BorderSide(color: SColor.error, width: 1.5)),
        disabledBorder: OutlineInputBorder(borderRadius: SRadii.mdAll, borderSide: BorderSide(color: borderSoftColor)),
        labelStyle: STextStyle.labelMedium.copyWith(color: secondaryTextColor),
        hintStyle: STextStyle.bodyMedium.copyWith(color: mutedColor),
        errorStyle: STextStyle.caption.copyWith(color: SColor.error, fontSize: 12),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: SColor.primary, foregroundColor: SColor.textInverse, elevation: 0,
          shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: SSpace.md),
          shape: RoundedRectangleBorder(borderRadius: SRadii.mdAll), textStyle: STextStyle.button,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: SColor.primary, side: const BorderSide(color: SColor.primary, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: SSpace.md),
          shape: RoundedRectangleBorder(borderRadius: SRadii.mdAll),
          textStyle: STextStyle.button.copyWith(color: SColor.primary),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: secondaryTextColor, padding: const EdgeInsets.symmetric(horizontal: SSpace.sm, vertical: SSpace.sm),
          shape: RoundedRectangleBorder(borderRadius: SRadii.mdAll), textStyle: STextStyle.labelMedium),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surfaceColor, elevation: 1, type: BottomNavigationBarType.fixed,
        selectedItemColor: SColor.primary, unselectedItemColor: secondaryTextColor,
        selectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
        unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, fontFamily: 'Inter'),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surfaceColor,
        selectedIconTheme: const IconThemeData(color: SColor.primary),
        unselectedIconTheme: IconThemeData(color: secondaryTextColor),
        selectedLabelTextStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'Inter', color: SColor.primary),
        unselectedLabelTextStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, fontFamily: 'Inter', color: secondaryTextColor),
      ),
      dialogTheme: DialogThemeData(backgroundColor: surfaceColor, shape: RoundedRectangleBorder(borderRadius: SRadii.lgAll)),
      textTheme: TextTheme(
        displayLarge: STextStyle.displayLarge.copyWith(color: textColor),
        displayMedium: STextStyle.displayMedium.copyWith(color: textColor),
        titleLarge: STextStyle.headingLarge.copyWith(color: textColor),
        titleMedium: STextStyle.headingMedium.copyWith(color: textColor),
        bodyLarge: STextStyle.bodyLarge.copyWith(color: textColor),
        bodyMedium: STextStyle.bodyMedium.copyWith(color: textColor),
        bodySmall: STextStyle.bodySmall.copyWith(color: textColor),
        labelLarge: STextStyle.labelLarge.copyWith(color: textColor),
        labelMedium: STextStyle.labelMedium.copyWith(color: textColor),
      ),
    );
  }
}

class STierAccent {
  final Color solid, soft, onSoft;
  const STierAccent({required this.solid, required this.soft, required this.onSoft});
  static const student = STierAccent(solid: SColor.primary, soft: SColor.infoSoft, onSoft: SColor.primary);
  static const teacher = STierAccent(solid: SColor.success, soft: SColor.successSoft, onSoft: SColor.success);
  static const leadership = STierAccent(solid: SColor.leadershipTier, soft: Color(0xFFF3E8FF), onSoft: SColor.leadershipTier);
  static STierAccent of(String? tier) => switch (tier) {
        'teacher' || 'head_teacher' => teacher,
        'platform_owner' || 'school_admin' || 'principal' => leadership,
        _ => student,
      };
}

class SLayout {
  static const double phoneMaxWidth = 600, tabletMinWidth = 600, desktopMinWidth = 1024;
  static const double phoneGutter = 16, tabletGutter = 24, desktopGutter = 32;
  static bool isPhone(BuildContext c) => MediaQuery.sizeOf(c).width < phoneMaxWidth;
  static bool isTablet(BuildContext c) { final w = MediaQuery.sizeOf(c).width; return w >= tabletMinWidth && w < desktopMinWidth; }
  static bool isDesktop(BuildContext c) => MediaQuery.sizeOf(c).width >= desktopMinWidth;
  static double gutter(BuildContext c) { if (isDesktop(c)) return desktopGutter; if (isTablet(c)) return tabletGutter; return phoneGutter; }
  static int columns(BuildContext c, {int min = 1, int max = 3}) { if (isDesktop(c)) return max; if (isTablet(c)) return 2; return 1; }
}

class AppColors {
  static const Color brand = SColor.primary;
  static const Color brandDark = SColor.primaryDark;
  static const Color brandDeep = Color(0xFF0F172A);
  static const Color brandLight = SColor.primaryLight;
  static const Color brandSheen = SColor.textInverse;
  static const Color accent = SColor.accent;
  static const Color accentLight = SColor.accent;
  static const Color accentGlow = SColor.accent;
  static const Color studentTier = SColor.studentTier;
  static const Color teacherTier = SColor.teacherTier;
  static const Color leadershipTier = SColor.leadershipTier;
  static const Color ink900 = SColor.primaryText;
  static const Color ink700 = SColor.secondaryText;
  static const Color ink600 = SColor.textMuted;
  static const Color ink500 = SColor.textMuted;
  static const Color ink400 = SColor.textMuted;
  static const Color ink300 = SColor.border;
  static const Color ink200 = SColor.borderSoft;
  static const Color ink100 = SColor.surfaceSoft;
  static const Color ink50 = SColor.primary;
  static const Color success = SColor.success;
  static const Color warning = SColor.warning;
  static const Color danger = SColor.error;
  static const Color info = SColor.info;
  static const Color surface = SColor.surface;
  static const Color surfaceCard = SColor.surface;
  static const Color surfaceElevated = SColor.surfaceElevated;
  static const Color surfaceGloss = SColor.surfaceElevated;
  static const Color glassDark = SColor.primary;
}

class MDColors {
  static const Color brand = SColor.primary;
  static const Color brandDark = SColor.primaryDark;
  static const Color brandDeep = Color(0xFF0F172A);
  static const Color brandLight = SColor.primaryLight;
  static const Color brandSheen = SColor.textInverse;
  static const Color accent = SColor.accent;
  static const Color accentLight = SColor.accent;
  static const Color accentGlow = SColor.accent;
  static const Color studentTier = SColor.studentTier;
  static const Color teacherTier = SColor.teacherTier;
  static const Color leadershipTier = SColor.leadershipTier;
  static const Color ink900 = SColor.primaryText;
  static const Color ink700 = SColor.secondaryText;
  static const Color ink600 = SColor.textMuted;
  static const Color ink500 = SColor.textMuted;
  static const Color ink400 = SColor.textMuted;
  static const Color ink300 = SColor.border;
  static const Color ink200 = SColor.borderSoft;
  static const Color ink100 = SColor.surfaceSoft;
  static const Color ink50 = SColor.primary;
  static const Color success = SColor.success;
  static const Color warning = SColor.warning;
  static const Color danger = SColor.error;
  static const Color info = SColor.info;
  static const Color surface = SColor.surface;
  static const Color surfaceCard = SColor.surface;
  static const Color surfaceElevated = SColor.surfaceElevated;
  static const Color surfaceGloss = SColor.surfaceElevated;
  static const Color glassDark = SColor.primary;
}

class MDTier {
  final Color gradient1, gradient2, solid, soft, onSoft;
  const MDTier({required this.gradient1, required this.gradient2, required this.solid, required this.soft, required this.onSoft});
  static const student = MDTier(gradient1: SColor.primary, gradient2: SColor.primaryLight, solid: SColor.primary, soft: SColor.infoSoft, onSoft: SColor.primary);
  static const teacher = MDTier(gradient1: SColor.success, gradient2: SColor.success, solid: SColor.success, soft: SColor.successSoft, onSoft: SColor.success);
  static const leadership = MDTier(gradient1: SColor.leadershipTier, gradient2: SColor.leadershipTier, solid: SColor.leadershipTier, soft: Color(0xFFF3E8FF), onSoft: SColor.leadershipTier);
  List<Color> get gradient => [gradient1, gradient2];
}

class TierAccent {
  final List<Color> gradient;
  final Color solid, soft, onSoft;
  const TierAccent({required this.gradient, required this.solid, required this.soft, required this.onSoft});
  static TierAccent of(AppTier tier) => switch (tier) {
        AppTier.student => const TierAccent(gradient: [SColor.primary, SColor.primaryLight], solid: SColor.primary, soft: SColor.infoSoft, onSoft: SColor.primary),
        AppTier.teacher => const TierAccent(gradient: [SColor.success, SColor.success], solid: SColor.success, soft: SColor.successSoft, onSoft: SColor.success),
        AppTier.leadership => const TierAccent(gradient: [SColor.leadershipTier, SColor.leadershipTier], solid: SColor.leadershipTier, soft: Color(0xFFF3E8FF), onSoft: SColor.leadershipTier),
      };
}

const double kGutter = 16;
const double kRadiusSm = 10;
const double kRadiusLg = 14;
const double kRadiusXl = 18;

class AppTheme {
  static ThemeData light() => STheme.light();
  static ThemeData dark() => STheme.dark();
}