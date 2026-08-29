import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Calm, dark-first Material 3 theme.
/// Palette:
///   • Surface       #0E1116  — near-black charcoal
///   • Surface alt   #161A21  — card background
///   • Primary       #7C9CFF  — soft blue accent
///   • Secondary     #93A1B5  — warm gray
///   • Error         #EF5A60
class AppTheme {
  static const _bg = Color(0xFF0E1116);
  static const _surface = Color(0xFF161A21);
  static const _surfaceVariant = Color(0xFF1E232C);
  static const _primary = Color(0xFF7C9CFF);
  static const _onPrimary = Color(0xFF0A0F1F);
  static const _secondary = Color(0xFF93A1B5);
  static const _outline = Color(0xFF2A313D);
  static const _onSurface = Color(0xFFE6E9EF);
  static const _onSurfaceMuted = Color(0xFF8E97A6);

  static ThemeData dark() {
    final scheme = const ColorScheme.dark(
      brightness: Brightness.dark,
      primary: _primary,
      onPrimary: _onPrimary,
      secondary: _secondary,
      onSecondary: Colors.black,
      surface: _bg,
      onSurface: _onSurface,
      surfaceContainerHighest: _surfaceVariant,
      surfaceContainer: _surface,
      outline: _outline,
      outlineVariant: Color(0xFF1F2530),
      error: Color(0xFFEF5A60),
      onError: Colors.white,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    return base.copyWith(
      scaffoldBackgroundColor: _bg,
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: _onSurface,
        displayColor: _onSurface,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: _bg,
        foregroundColor: _onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20, fontWeight: FontWeight.w600, color: _onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: _surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: _outline, width: 0.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          side: const BorderSide(color: _outline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _primary, width: 1.4),
        ),
        hintStyle: const TextStyle(color: _onSurfaceMuted),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: _bg,
        indicatorColor: Color(0x227C9CFF),
        labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
        iconTheme: WidgetStatePropertyAll(IconThemeData(size: 22)),
        elevation: 0,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _surfaceVariant,
        side: const BorderSide(color: _outline),
        labelStyle: const TextStyle(color: _onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dividerColor: _outline,
      iconTheme: const IconThemeData(color: _onSurface),
    );
  }

  static ThemeData light() {
    const scheme = ColorScheme.light(
      brightness: Brightness.light,
      primary: Color(0xFF3D5BDC),
      onPrimary: Colors.white,
      secondary: Color(0xFF6E7A8C),
      onSecondary: Colors.white,
      surface: Color(0xFFFAFAFB),
      onSurface: Color(0xFF111418),
      surfaceContainerHighest: Color(0xFFEEF0F4),
      surfaceContainer: Colors.white,
      outline: Color(0xFFE2E5EB),
      outlineVariant: Color(0xFFEDEFF3),
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: GoogleFonts.interTextTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20, fontWeight: FontWeight.w600, color: scheme.onSurface,
        ),
      ),
    );
  }

  static const Color textMuted = _onSurfaceMuted;
}
