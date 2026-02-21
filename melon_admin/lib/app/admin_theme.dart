import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shad;

// ─────────────────────────────────────────────
// Admin Dark Theme — #1E1E24 + #FFCF99
// ─────────────────────────────────────────────

class AdminTheme {
  // ─── Brand Colors: Warm Gold on Dark ───
  static const Color gold = Color(0xFFFFCF99);
  static const Color goldLight = Color(0xFFFFDEB8);
  static const Color goldDark = Color(0xFFD4A86E);
  static const Color goldSubtle = Color(0x26FFCF99);
  static const Color onAccent = Color(0xFF1E1E24);

  // ─── Background & Surface ───
  static const Color background = Color(0xFF1E1E24);
  static const Color surface = Color(0xFF26262E);
  static const Color card = Color(0xFF2A2A32);
  static const Color cardElevated = Color(0xFF32323C);
  static const Color border = Color(0x33888894);
  static const Color borderLight = Color(0x1A888894);

  // ─── Text ───
  static const Color textPrimary = Color(0xFFF2F0EA);
  static const Color textSecondary = Color(0xFF9A9AA6);
  static const Color textTertiary = Color(0x999A9AA6);

  // ─── Semantic ───
  static const Color success = Color(0xFF4ADE80);
  static const Color error = Color(0xFFFF6B6B);
  static const Color warning = Color(0xFFFFCF99);
  static const Color info = Color(0xFF60A5FA);

  // ─── Aliases ───
  static const Color primaryColor = gold;
  static const Color primaryDark = goldDark;
  static const Color primaryLight = goldLight;
  static const Color surfaceColor = surface;
  static const Color darkSurface = cardElevated;
  static const Color backgroundColor = background;
  static const Color dividerColor = border;
  static const Color cardColor = card;
  static const Color accentColor = gold;
  static const Color errorColor = error;
  static const Color warningColor = warning;
  static const Color successColor = success;

  // ─── Sage (neutral secondary) ───
  static const Color sage = Color(0xFF888894);

  // ─── Gradients ───
  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFFFCF99), Color(0xFFD4A86E)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient goldGradientVertical = LinearGradient(
    colors: [Color(0xFFD4A86E), Color(0xFFFFCF99)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    colors: [Color(0xFF1E1E24), Color(0xFF26262E)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient posterOverlay = LinearGradient(
    colors: [
      Colors.transparent,
      Color(0x001E1E24),
      Color(0x661E1E24),
      Color(0xFF1E1E24),
    ],
    stops: [0.0, 0.4, 0.7, 1.0],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient topOverlay = LinearGradient(
    colors: [Color(0x881E1E24), Colors.transparent],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // ─── Premium Text Shadows ───
  /// 약한 그림자 — 다크 배경 위 기본 텍스트
  static const List<Shadow> textShadow = [
    Shadow(color: Color(0x30000000), offset: Offset(0, 1), blurRadius: 3),
  ];

  /// 강한 그림자 — 제목, 가격, 큰 숫자
  static const List<Shadow> textShadowStrong = [
    Shadow(color: Color(0x40000000), offset: Offset(0, 1), blurRadius: 4),
    Shadow(color: Color(0x15000000), offset: Offset(0, 2), blurRadius: 8),
  ];

  // ─── Font Helpers ───
  static TextStyle serif({
    double fontSize = 16,
    FontWeight fontWeight = FontWeight.w700,
    Color? color,
    double? letterSpacing,
    double? height,
    FontStyle? fontStyle,
    List<Shadow>? shadows,
    bool noShadow = false,
  }) =>
      GoogleFonts.notoSerif(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color ?? textPrimary,
        letterSpacing: letterSpacing,
        height: height,
        fontStyle: fontStyle,
        shadows: noShadow ? null : (shadows ?? textShadow),
      );

  static TextStyle sans({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
    double? letterSpacing,
    double? height,
    List<Shadow>? shadows,
    bool noShadow = false,
  }) =>
      GoogleFonts.inter(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color ?? textPrimary,
        letterSpacing: letterSpacing,
        height: height,
        shadows: noShadow ? null : (shadows ?? textShadow),
      );

  static TextStyle label({
    double fontSize = 10,
    Color? color,
    List<Shadow>? shadows,
    bool noShadow = false,
  }) =>
      GoogleFonts.inter(
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        color: color ?? sage,
        letterSpacing: 2.0,
        height: 1.4,
        shadows: noShadow ? null : (shadows ?? textShadow),
      );

  // ─── Material ThemeData ───
  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: gold,
        onPrimary: onAccent,
        primaryContainer: goldDark,
        onPrimaryContainer: onAccent,
        secondary: sage,
        onSecondary: textPrimary,
        surface: surface,
        onSurface: textPrimary,
        error: error,
        onError: Colors.white,
      ),
      textTheme: _textTheme(),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: GoogleFonts.notoSerif(
          fontSize: 18,
          fontWeight: FontWeight.w500,
          color: textPrimary,
          fontStyle: FontStyle.italic,
        ),
        iconTheme: const IconThemeData(color: textPrimary, size: 22),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: onAccent,
          disabledBackgroundColor: border,
          disabledForegroundColor: textTertiary,
          minimumSize: const Size(double.infinity, 56),
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 2.0,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: gold,
          minimumSize: const Size(double.infinity, 56),
          side: BorderSide(color: gold.withValues(alpha: 0.3), width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.0,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: gold,
          textStyle: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        border: const UnderlineInputBorder(
          borderSide: BorderSide(color: border, width: 0.5),
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: sage.withValues(alpha: 0.4), width: 0.5),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: gold, width: 1),
        ),
        errorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: error, width: 1),
        ),
        focusedErrorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: error, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
        hintStyle: GoogleFonts.inter(fontSize: 14, color: textTertiary),
        labelStyle: GoogleFonts.inter(fontSize: 14, color: textSecondary),
        errorStyle: GoogleFonts.inter(fontSize: 12, color: error),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(2),
          side: BorderSide(color: sage.withValues(alpha: 0.1), width: 0.5),
        ),
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 8,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        titleTextStyle: GoogleFonts.notoSerif(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        contentTextStyle: GoogleFonts.inter(
          fontSize: 14,
          color: textSecondary,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        elevation: 8,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: gold,
        contentTextStyle: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: onAccent,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 0.5,
        space: 0.5,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: gold,
        linearTrackColor: border,
        circularTrackColor: border,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: gold,
        side: BorderSide(color: sage.withValues(alpha: 0.3), width: 0.5),
        labelStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? onAccent : sage),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? gold
                : sage.withValues(alpha: 0.3)),
        trackOutlineColor:
            WidgetStateProperty.all(Colors.transparent),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  // ─── Shadcn ThemeData ───
  static shad.ThemeData get shadcnTheme => const shad.ThemeData(
        colorScheme: _shadcnColorScheme,
        radius: 0.875,
      );

  static const shad.ColorScheme _shadcnColorScheme = shad.ColorScheme(
    brightness: shad.Brightness.dark,
    background: background,
    foreground: textPrimary,
    card: card,
    cardForeground: textPrimary,
    popover: card,
    popoverForeground: textPrimary,
    primary: gold,
    primaryForeground: onAccent,
    secondary: surface,
    secondaryForeground: textPrimary,
    muted: cardElevated,
    mutedForeground: textSecondary,
    accent: surface,
    accentForeground: textPrimary,
    destructive: error,
    destructiveForeground: Color(0xFFFFFFFF),
    border: border,
    input: border,
    ring: gold,
    chart1: gold,
    chart2: goldLight,
    chart3: success,
    chart4: warning,
    chart5: goldDark,
  );

  static TextTheme _textTheme() {
    final base = GoogleFonts.interTextTheme(ThemeData.dark().textTheme);
    return base.copyWith(
      displayLarge: GoogleFonts.notoSerif(
        fontSize: 42, fontWeight: FontWeight.w700, color: textPrimary,
        letterSpacing: -0.5, height: 1.1,
      ),
      displayMedium: GoogleFonts.notoSerif(
        fontSize: 32, fontWeight: FontWeight.w700, color: textPrimary,
        letterSpacing: -0.5, height: 1.15,
      ),
      displaySmall: GoogleFonts.notoSerif(
        fontSize: 24, fontWeight: FontWeight.w600, color: textPrimary,
        letterSpacing: -0.25, height: 1.2,
      ),
      headlineLarge: GoogleFonts.notoSerif(
        fontSize: 22, fontWeight: FontWeight.w700, color: textPrimary, height: 1.25,
      ),
      headlineMedium: GoogleFonts.notoSerif(
        fontSize: 20, fontWeight: FontWeight.w500, color: textPrimary,
        fontStyle: FontStyle.italic, height: 1.3,
      ),
      headlineSmall: GoogleFonts.notoSerif(
        fontSize: 18, fontWeight: FontWeight.w500, color: textPrimary, height: 1.35,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 16, fontWeight: FontWeight.w600, color: textPrimary, height: 1.4,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 14, fontWeight: FontWeight.w600, color: textPrimary, height: 1.4,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontSize: 13, fontWeight: FontWeight.w500, color: textPrimary, height: 1.4,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        fontSize: 16, fontWeight: FontWeight.w300, color: textPrimary, height: 1.6,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: 14, fontWeight: FontWeight.w400, color: textPrimary, height: 1.5,
      ),
      bodySmall: base.bodySmall?.copyWith(
        fontSize: 13, fontWeight: FontWeight.w400, color: textSecondary, height: 1.5,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 11, fontWeight: FontWeight.w600, color: textPrimary,
        letterSpacing: 2.0, height: 1.4,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontSize: 10, fontWeight: FontWeight.w600, color: textSecondary,
        letterSpacing: 2.0, height: 1.4,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontSize: 9, fontWeight: FontWeight.w600, color: textTertiary,
        letterSpacing: 2.0, height: 1.4,
      ),
    );
  }
}

/// Shadow presets (dark theme — subtle warm glow)
class AdminShadows {
  static List<BoxShadow> get small => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.3),
          blurRadius: 12,
          offset: const Offset(0, 2),
        ),
      ];
  static List<BoxShadow> get card => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.4),
          blurRadius: 20,
          offset: const Offset(0, 4),
        ),
      ];
  static List<BoxShadow> get elevated => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.5),
          blurRadius: 30,
          offset: const Offset(0, 8),
        ),
      ];
}
