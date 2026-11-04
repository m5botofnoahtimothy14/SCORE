import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/identity.dart';

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SCORE+ Premium Design System — Light theme
// Mandatory palette (visual reference benchmark):
//   Primary Navy   #14213D  — brand foundation
//   Secondary Navy #1B2F50  — elevated surfaces
//   Electric Blue  #3478F6  — primary actions
//   Accent Cyan    #28C7D9  — selected highlights
//   Background     #F5F7FB  — light neutral
//   Surface        #FFFFFF  — cards
//   Primary Text   #17243A
//   Secondary Text #718096
//   Border         #E5EAF2
//   Success #16A36A  Warning #F2A93B  Error #DC515B
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class SColor {
  static const Color primaryNavy = Color(0xFF14213D);
  static const Color secondaryNavy = Color(0xFF1B2F50);
  static const Color electricBlue = Color(0xFF3478F6);
  static const Color accentCyan = Color(0xFF28C7D9);
  static const Color accentCyanSoft = Color(0xFFE3F6F8);

  static const Color background = Color(0xFFF5F7FB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSoft = Color(0xFFEEF2F7);
  static const Color surfaceElevated = Color(0xFFF3F6FB);

  static const Color primaryText = Color(0xFF17243A);
  static const Color secondaryText = Color(0xFF718096);
  static const Color textMuted = Color(0xFF9AA7B8);
  static const Color textInverse = Color(0xFFFFFFFF);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  static const Color border = Color(0xFFE5EAF2);
  static const Color borderSoft = Color(0xFFF1F4F8);
  static const Color divider = Color(0xFFE9EDF3);

  static const Color success = Color(0xFF16A36A);
  static const Color successSoft = Color(0xFFE7F6EE);
  static const Color warning = Color(0xFFF2A93B);
  static const Color warningSoft = Color(0xFFFDF0DC);
  static const Color error = Color(0xFFDC515B);
  static const Color errorSoft = Color(0xFFFBECEC);
  static const Color info = Color(0xFF3478F6);
  static const Color infoSoft = Color(0xFFE8F1FF);

  static const Color studentTier = Color(0xFF3478F6);
  static const Color teacherTier = Color(0xFF16A36A);
  static const Color leadershipTier = Color(0xFF7C3AED);

  static const Color shadowColor = Color(0x0F000000);
}

class STextStyle {
  static TextStyle _base({double size = 14, FontWeight weight = FontWeight.normal, Color color = SColor.primaryText, double height = 1.5, double? letterSpacing}) {
    return GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color, height: height, letterSpacing: letterSpacing);
  }

  static const TextStyle displayLarge = TextStyle(fontFamily: 'Inter', fontSize: 30, fontWeight: FontWeight.w800, color: SColor.primaryText, height: 1.2, letterSpacing: -0.4);
  static const TextStyle displayMedium = TextStyle(fontFamily: 'Inter', fontSize: 24, fontWeight: FontWeight.w700, color: SColor.primaryText, height: 1.25, letterSpacing: -0.3);
  static const TextStyle headingLarge = TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w700, color: SColor.primaryText, height: 1.4);
  static const TextStyle headingMedium = TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600, color: SColor.primaryText, height: 1.4);
  static const TextStyle headingSmall = TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: SColor.primaryText, height: 1.4);
  static const TextStyle bodyLarge = TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w500, color: SColor.primaryText, height: 1.6);
  static const TextStyle bodyMedium = TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w500, color: SColor.primaryText, height: 1.6);
  static const TextStyle bodySmall = TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w500, color: SColor.primaryText, height: 1.5);
  static const TextStyle labelLarge = TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: SColor.primaryText);
  static const TextStyle labelMedium = TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: SColor.primaryText);
  static const TextStyle caption = TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w500, color: SColor.secondaryText, height: 1.4);
  static const TextStyle captionMuted = TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w500, color: SColor.textMuted, height: 1.4);
  static const TextStyle overline = TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, color: SColor.secondaryText, letterSpacing: 0.8);
  static const TextStyle button = TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w700, color: SColor.textInverse, letterSpacing: 0.2);
  static const TextStyle buttonSecondary = TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w700, color: SColor.primaryNavy, letterSpacing: 0.2);
}

class SSpace {
  static const double xs = 4, sm = 8, md = 16, lg = 24, xl = 32, xxl = 48;
}

class SRadii {
  static const Radius sm = Radius.circular(8), md = Radius.circular(12), lg = Radius.circular(16), xl = Radius.circular(20), full = Radius.circular(24);
  static const BorderRadius smAll = BorderRadius.all(Radius.circular(8));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(12));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(16));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(20));
}

class SShadow {
  static const List<BoxShadow> card = [BoxShadow(color: SColor.shadowColor, blurRadius: 10, offset: Offset(0, 2))];
  static const List<BoxShadow> elevated = [BoxShadow(color: SColor.shadowColor, blurRadius: 20, offset: Offset(0, 8))];
}

class STheme {
  static ThemeData light() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: SColor.background,
    cardColor: SColor.surface,
    dividerColor: SColor.divider,
    fontFamily: 'Inter',
    primaryColor: SColor.electricBlue,
    colorScheme: const ColorScheme.light(
      primary: SColor.electricBlue,
      onPrimary: SColor.textInverse,
      secondary: SColor.accentCyan,
      onSecondary: SColor.primaryNavy,
      surface: SColor.surface,
      onSurface: SColor.primaryText,
      background: SColor.background,
      onBackground: SColor.primaryText,
      error: SColor.error,
      onError: SColor.textInverse,
      outline: SColor.border,
    ),
    cardTheme: const CardThemeData(
      color: SColor.surface,
      elevation: 0,
      shadowColor: SColor.shadowColor,
      shape: RoundedRectangleBorder(borderRadius: SRadii.lgAll, side: BorderSide(color: SColor.border)),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SColor.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: SSpace.md, vertical: SSpace.md),
      isDense: true,
      border: OutlineInputBorder(borderRadius: SRadii.mdAll, borderSide: const BorderSide(color: SColor.border)),
      enabledBorder: OutlineInputBorder(borderRadius: SRadii.mdAll, borderSide: const BorderSide(color: SColor.border)),
      focusedBorder: OutlineInputBorder(borderRadius: SRadii.mdAll, borderSide: const BorderSide(color: SColor.electricBlue, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: SRadii.mdAll, borderSide: const BorderSide(color: SColor.error)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: SRadii.mdAll, borderSide: const BorderSide(color: SColor.error, width: 1.5)),
      disabledBorder: OutlineInputBorder(borderRadius: SRadii.mdAll, borderSide: const BorderSide(color: SColor.borderSoft)),
      labelStyle: STextStyle.labelMedium.copyWith(color: SColor.secondaryText),
      hintStyle: STextStyle.bodyMedium.copyWith(color: SColor.textMuted),
      errorStyle: STextStyle.caption.copyWith(color: SColor.error, fontSize: 12),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: SColor.electricBlue, foregroundColor: SColor.textInverse, elevation: 0,
        shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: SSpace.md),
        shape: RoundedRectangleBorder(borderRadius: SRadii.mdAll), textStyle: STextStyle.button,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: SColor.electricBlue, side: const BorderSide(color: SColor.electricBlue, width: 1.5),
        padding: const EdgeInsets.symmetric(vertical: SSpace.md),
        shape: RoundedRectangleBorder(borderRadius: SRadii.mdAll),
        textStyle: STextStyle.button.copyWith(color: SColor.electricBlue),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: SColor.secondaryText, padding: const EdgeInsets.symmetric(horizontal: SSpace.sm, vertical: SSpace.sm),
        shape: RoundedRectangleBorder(borderRadius: SRadii.mdAll), textStyle: STextStyle.labelMedium),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: SColor.surface, elevation: 4, type: BottomNavigationBarType.fixed,
      selectedItemColor: SColor.electricBlue, unselectedItemColor: SColor.secondaryText,
      selectedLabelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
      unselectedLabelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, fontFamily: 'Inter'),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: SColor.surface,
      selectedIconTheme: IconThemeData(color: SColor.electricBlue),
      unselectedIconTheme: IconThemeData(color: SColor.secondaryText),
      selectedLabelTextStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'Inter', color: SColor.electricBlue),
      unselectedLabelTextStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, fontFamily: 'Inter', color: SColor.secondaryText),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: SColor.surface,
      shape: RoundedRectangleBorder(borderRadius: SRadii.lgAll),
    ),
    textTheme: const TextTheme(
      displayLarge: STextStyle.displayLarge, displayMedium: STextStyle.displayMedium,
      titleLarge: STextStyle.headingLarge, titleMedium: STextStyle.headingMedium,
      bodyLarge: STextStyle.bodyLarge, bodyMedium: STextStyle.bodyMedium, bodySmall: STextStyle.bodySmall,
      labelLarge: STextStyle.labelLarge, labelMedium: STextStyle.labelMedium,
    ),
  );
}

class STierAccent {
  final Color solid, soft, onSoft;
  const STierAccent({required this.solid, required this.soft, required this.onSoft});
  static const student = STierAccent(solid: SColor.electricBlue, soft: SColor.infoSoft, onSoft: SColor.electricBlue);
  static const teacher = STierAccent(solid: SColor.success, soft: SColor.successSoft, onSoft: SColor.success);
  static const leadership = STierAccent(solid: SColor.leadershipTier, soft: Color(0xFFFAF5FF), onSoft: SColor.leadershipTier);
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

// Backwards-compatible aliases so existing imports keep working.
class AppColors {
  static const Color brand = SColor.primaryNavy;
  static const Color brandDark = SColor.primaryNavy;
  static const Color brandDeep = Color(0xFF0A1422);
  static const Color brandLight = SColor.secondaryNavy;
  static const Color brandSheen = SColor.textInverse;
  static const Color accent = SColor.electricBlue;
  static const Color accentLight = SColor.electricBlue;
  static const Color accentGlow = SColor.electricBlue;
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
  static const Color ink50 = SColor.primaryNavy;
  static const Color success = SColor.success;
  static const Color warning = SColor.warning;
  static const Color danger = SColor.error;
  static const Color info = SColor.info;
  static const Color surface = SColor.surface;
  static const Color surfaceCard = SColor.surface;
  static const Color surfaceElevated = SColor.surfaceElevated;
  static const Color surfaceGloss = SColor.surfaceElevated;
  static const Color glassDark = SColor.primaryNavy;
}

class MDColors {
  static const Color brand = SColor.primaryNavy;
  static const Color brandDark = SColor.primaryNavy;
  static const Color brandDeep = Color(0xFF0A1422);
  static const Color brandLight = SColor.secondaryNavy;
  static const Color brandSheen = SColor.textInverse;
  static const Color accent = SColor.electricBlue;
  static const Color accentLight = SColor.electricBlue;
  static const Color accentGlow = SColor.electricBlue;
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
  static const Color ink50 = SColor.primaryNavy;
  static const Color success = SColor.success;
  static const Color warning = SColor.warning;
  static const Color danger = SColor.error;
  static const Color info = SColor.info;
  static const Color surface = SColor.surface;
  static const Color surfaceCard = SColor.surface;
  static const Color surfaceElevated = SColor.surfaceElevated;
  static const Color surfaceGloss = SColor.surfaceElevated;
  static const Color glassDark = SColor.primaryNavy;
}

class MDTier {
  final Color gradient1, gradient2, solid, soft, onSoft;
  const MDTier({required this.gradient1, required this.gradient2, required this.solid, required this.soft, required this.onSoft});
  static const student = MDTier(gradient1: SColor.electricBlue, gradient2: SColor.electricBlue, solid: SColor.electricBlue, soft: SColor.infoSoft, onSoft: SColor.electricBlue);
  static const teacher = MDTier(gradient1: SColor.success, gradient2: SColor.success, solid: SColor.success, soft: SColor.successSoft, onSoft: SColor.success);
  static const leadership = MDTier(gradient1: SColor.leadershipTier, gradient2: SColor.leadershipTier, solid: SColor.leadershipTier, soft: Color(0xFFFAF5FF), onSoft: SColor.leadershipTier);
  List<Color> get gradient => [gradient1, gradient2];
}

class TierAccent {
  final List<Color> gradient;
  final Color solid, soft, onSoft;
  const TierAccent({required this.gradient, required this.solid, required this.soft, required this.onSoft});
  static TierAccent of(AppTier tier) => switch (tier) {
        AppTier.student => const TierAccent(gradient: [SColor.electricBlue, SColor.electricBlue], solid: SColor.electricBlue, soft: SColor.infoSoft, onSoft: SColor.electricBlue),
        AppTier.teacher => const TierAccent(gradient: [SColor.success, SColor.success], solid: SColor.success, soft: SColor.successSoft, onSoft: SColor.success),
        AppTier.leadership => const TierAccent(gradient: [SColor.leadershipTier, SColor.leadershipTier], solid: SColor.leadershipTier, soft: Color(0xFFFAF5FF), onSoft: SColor.leadershipTier),
      };
}

const double kGutter = 16;
const double kRadiusSm = 12;
const double kRadiusLg = 24;
const double kRadiusXl = 32;

class AppTheme {
  static ThemeData light() => STheme.light();
  static ThemeData dark() => STheme.light();
}
