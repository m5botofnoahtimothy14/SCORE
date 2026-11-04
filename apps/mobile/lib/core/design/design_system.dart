/// SCORE+ Premium Design System
///
/// Single source of truth for colours, typography, spacing, radii and
/// reusable components. Every screen must use these tokens so the product
/// presents one unified, professional identity.
///
/// Mandatory palette (visual reference benchmark):
///   Primary Navy   #14213D  — brand foundation, deep surfaces, headers
///   Secondary Navy #1B2F50  — elevated surfaces, cards, side panels
///   Electric Blue  #3478F6  — primary actions
///   Accent Cyan    #28C7D9  — selected highlights, interactive details
///   Background     #F5F7FB  — light neutral page background
///   Surface        #FFFFFF  — card surfaces
///   Primary Text   #17243A  — near-black navy body/heading text
///   Secondary Text #718096  — muted supporting text
///   Border         #E5EAF2  — subtle hairline borders
///   Success        #16A36A
///   Warning        #F2A93B
///   Error          #DC515B

library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// COLOURS
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class SColor {
  // Brand — deep professional navy foundation
  static const Color primaryNavy = Color(0xFF14213D);
  static const Color secondaryNavy = Color(0xFF1B2F50);

  // Actions & accents
  static const Color electricBlue = Color(0xFF3478F6); // primary actions
  static const Color accentCyan = Color(0xFF28C7D9);   // selected highlights
  static const Color accentCyanSoft = Color(0xFFE3F6F8);

  // Surfaces
  static const Color background = Color(0xFFF5F7FB); // page background
  static const Color surface = Color(0xFFFFFFFF);    // card surface
  static const Color surfaceSoft = Color(0xFFEEF2F7); // subtle filled areas
  static const Color surfaceElevated = Color(0xFFF3F6FB);

  // Text
  static const Color primaryText = Color(0xFF17243A);
  static const Color secondaryText = Color(0xFF718096);
  static const Color textMuted = Color(0xFF9AA7B8);
  static const Color textInverse = Color(0xFFFFFFFF);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // Borders & dividers
  static const Color border = Color(0xFFE5EAF2);
  static const Color borderSoft = Color(0xFFF1F4F8);
  static const Color divider = Color(0xFFE9EDF3);

  // Semantic
  static const Color success = Color(0xFF16A36A);
  static const Color successSoft = Color(0xFFE7F6EE);
  static const Color warning = Color(0xFFF2A93B);
  static const Color warningSoft = Color(0xFFFDF0DC);
  static const Color error = Color(0xFFDC515B);
  static const Color errorSoft = Color(0xFFFBECEC);
  static const Color info = Color(0xFF3478F6);
  static const Color infoSoft = Color(0xFFE8F1FF);

  // Tier colours (subtle, used only as accents)
  static const Color studentTier = electricBlue;
  static const Color teacherTier = Color(0xFF16A36A);
  static const Color leadershipTier = Color(0xFF7C3AED);

  static const Color shadowColor = Color(0x0F000000); // minimal shadow
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// TYPOGRAPHY — Inter, clear hierarchy
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

const String kFontFamily = 'Inter';

class STextStyle {
  static TextStyle _base({double size = 14, FontWeight weight = FontWeight.normal, Color color = SColor.primaryText, double height = 1.5, double? letterSpacing}) {
    return GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  // Large dashboard headings
  static const TextStyle displayLarge = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 30,
    fontWeight: FontWeight.w800,
    color: SColor.primaryText,
    height: 1.2,
    letterSpacing: -0.4,
  );

  static const TextStyle displayMedium = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: SColor.primaryText,
    height: 1.25,
    letterSpacing: -0.3,
  );

  // Section headings
  static const TextStyle headingLarge = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: SColor.primaryText,
    height: 1.4,
  );

  static const TextStyle headingMedium = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: SColor.primaryText,
    height: 1.4,
  );

  static const TextStyle headingSmall = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: SColor.primaryText,
    height: 1.4,
  );

  // Body
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: SColor.primaryText,
    height: 1.6,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: SColor.primaryText,
    height: 1.6,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: SColor.primaryText,
    height: 1.5,
  );

  // Labels & supporting info
  static const TextStyle labelLarge = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: SColor.primaryText,
  );

  static const TextStyle labelMedium = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: SColor.primaryText,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: SColor.secondaryText,
    height: 1.4,
  );

  static const TextStyle captionMuted = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: SColor.textMuted,
    height: 1.4,
  );

  static const TextStyle overline = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 10,
    fontWeight: FontWeight.w700,
    color: SColor.secondaryText,
    letterSpacing: 0.8,
  );

  // Button text
  static const TextStyle button = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: SColor.textInverse,
    letterSpacing: 0.2,
  );

  static const TextStyle buttonSecondary = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: SColor.primaryNavy,
    letterSpacing: 0.2,
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SPACING (8-point grid)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class SSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// BORDER RADIUS
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class SRadii {
  static const Radius sm = Radius.circular(8);
  static const Radius md = Radius.circular(12);
  static const Radius lg = Radius.circular(16);
  static const Radius xl = Radius.circular(20);
  static const Radius full = Radius.circular(24);

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(8));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(12));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(16));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(20));
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SHADOWS (subtle, minimal)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class SShadow {
  static const List<BoxShadow> card = [
    BoxShadow(color: SColor.shadowColor, blurRadius: 10, offset: Offset(0, 2)),
  ];
  static const List<BoxShadow> cardHover = [
    BoxShadow(color: SColor.shadowColor, blurRadius: 16, offset: Offset(0, 4)),
  ];
  static const List<BoxShadow> elevated = [
    BoxShadow(color: SColor.shadowColor, blurRadius: 20, offset: Offset(0, 8)),
  ];
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// THEME DATA
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class STheme {
  static ThemeData light() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: SColor.background,
    cardColor: SColor.surface,
    dividerColor: SColor.divider,
    fontFamily: kFontFamily,
    textTheme: const TextTheme(
      displayLarge: STextStyle.displayLarge,
      displayMedium: STextStyle.displayMedium,
      titleLarge: STextStyle.headingLarge,
      titleMedium: STextStyle.headingMedium,
      bodyLarge: STextStyle.bodyLarge,
      bodyMedium: STextStyle.bodyMedium,
      bodySmall: STextStyle.bodySmall,
      labelLarge: STextStyle.labelLarge,
      labelMedium: STextStyle.labelMedium,
    ),
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
      border: OutlineInputBorder(
        borderRadius: SRadii.mdAll,
        borderSide: const BorderSide(color: SColor.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: SRadii.mdAll,
        borderSide: const BorderSide(color: SColor.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: SRadii.mdAll,
        borderSide: const BorderSide(color: SColor.electricBlue, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: SRadii.mdAll,
        borderSide: const BorderSide(color: SColor.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: SRadii.mdAll,
        borderSide: const BorderSide(color: SColor.error, width: 1.5),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: SRadii.mdAll,
        borderSide: const BorderSide(color: SColor.borderSoft),
      ),
      labelStyle: STextStyle.labelMedium.copyWith(color: SColor.secondaryText),
      hintStyle: STextStyle.bodyMedium.copyWith(color: SColor.textMuted),
      errorStyle: STextStyle.caption.copyWith(color: SColor.error, fontSize: 12),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: SColor.electricBlue,
        foregroundColor: SColor.textInverse,
        elevation: 0,
        shadowColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: SSpace.md),
        shape: RoundedRectangleBorder(borderRadius: SRadii.mdAll),
        textStyle: STextStyle.button,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: SColor.electricBlue,
        side: const BorderSide(color: SColor.electricBlue, width: 1.5),
        padding: const EdgeInsets.symmetric(vertical: SSpace.md),
        shape: RoundedRectangleBorder(borderRadius: SRadii.mdAll),
        textStyle: STextStyle.button.copyWith(color: SColor.electricBlue),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: SColor.secondaryText,
        padding: const EdgeInsets.symmetric(horizontal: SSpace.sm, vertical: SSpace.sm),
        shape: RoundedRectangleBorder(borderRadius: SRadii.mdAll),
        textStyle: STextStyle.labelMedium,
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: SColor.surface,
      elevation: 4,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: SColor.electricBlue,
      unselectedItemColor: SColor.secondaryText,
      selectedLabelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFamily: kFontFamily),
      unselectedLabelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, fontFamily: kFontFamily),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: SColor.surface,
      selectedIconTheme: IconThemeData(color: SColor.electricBlue),
      unselectedIconTheme: IconThemeData(color: SColor.secondaryText),
      selectedLabelTextStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFamily: kFontFamily, color: SColor.electricBlue),
      unselectedLabelTextStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, fontFamily: kFontFamily, color: SColor.secondaryText),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: SColor.surface,
      shape: RoundedRectangleBorder(borderRadius: SRadii.lgAll),
    ),
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(color: SColor.primaryNavy, borderRadius: SRadii.smAll),
      textStyle: TextStyle(color: SColor.textInverse, fontSize: 12, fontFamily: kFontFamily),
    ),
  );

  // TextTheme accessors (convenience)
  static TextTheme of(BuildContext context) => Theme.of(context).textTheme;
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// TIER ACCENTS (subtle, used sparingly)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class STierAccent {
  final Color solid;
  final Color soft;
  final Color onSoft;
  const STierAccent({required this.solid, required this.soft, required this.onSoft});

  static const student = STierAccent(
    solid: SColor.electricBlue,
    soft: SColor.infoSoft,
    onSoft: SColor.electricBlue,
  );
  static const teacher = STierAccent(
    solid: SColor.success,
    soft: SColor.successSoft,
    onSoft: SColor.success,
  );
  static const leadership = STierAccent(
    solid: SColor.leadershipTier,
    soft: Color(0xFFFAF5FF),
    onSoft: SColor.leadershipTier,
  );

  static STierAccent of(String? tier) => switch (tier) {
        'teacher' || 'head_teacher' => teacher,
        'platform_owner' || 'school_admin' || 'principal' => leadership,
        _ => student,
      };
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// RESPONSIVE BREAKPOINTS
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class SLayout {
  static const double phoneMaxWidth = 600;
  static const double tabletMinWidth = 600;
  static const double desktopMinWidth = 1024;
  static const double phoneGutter = 16;
  static const double tabletGutter = 24;
  static const double desktopGutter = 32;

  static bool isPhone(BuildContext context) => MediaQuery.sizeOf(context).width < phoneMaxWidth;
  static bool isTablet(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= tabletMinWidth && w < desktopMinWidth;
  }
  static bool isDesktop(BuildContext context) => MediaQuery.sizeOf(context).width >= desktopMinWidth;

  static double gutter(BuildContext context) {
    if (isDesktop(context)) return desktopGutter;
    if (isTablet(context)) return tabletGutter;
    return phoneGutter;
  }

  static int columns(BuildContext context, {int min = 1, int max = 3}) {
    if (isDesktop(context)) return max;
    if (isTablet(context)) return 2;
    return 1;
  }
}
