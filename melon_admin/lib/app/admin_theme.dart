import 'package:shadcn_flutter/shadcn_flutter.dart';

class AdminShadcnTheme {
  static ThemeData get theme => const ThemeData(
        colorScheme: _burgundyDark,
        radius: 0.875,
      );

  static const ColorScheme _burgundyDark = ColorScheme(
    brightness: Brightness.dark,
    // Base
    background: Color(0xFF080609),
    foreground: Color(0xFFF7F3F6),
    // Card
    card: Color(0xFF1A1119),
    cardForeground: Color(0xFFF7F3F6),
    // Popover
    popover: Color(0xFF1A1119),
    popoverForeground: Color(0xFFF7F3F6),
    // Primary (Burgundy)
    primary: Color(0xFFC42A4D),
    primaryForeground: Color(0xFFFDF3F6),
    // Secondary
    secondary: Color(0xFF241722),
    secondaryForeground: Color(0xFFF7F3F6),
    // Muted
    muted: Color(0xFF120C12),
    mutedForeground: Color(0xFFB0A7B1),
    // Accent
    accent: Color(0xFF241722),
    accentForeground: Color(0xFFF7F3F6),
    // Destructive
    destructive: Color(0xFFFF5A5F),
    destructiveForeground: Color(0xFFFFFFFF),
    // Border / Input / Ring
    border: Color(0xFF3A2431),
    input: Color(0xFF3A2431),
    ring: Color(0xFFC42A4D),
    // Charts
    chart1: Color(0xFFC42A4D),
    chart2: Color(0xFFE76282),
    chart3: Color(0xFF30D158),
    chart4: Color(0xFFFFB347),
    chart5: Color(0xFF8A1632),
  );
}
