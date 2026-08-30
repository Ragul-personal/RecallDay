import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_tokens.dart';

/// Brand palette, sampled directly from `Logo.png`.
///
/// The mark is a violet gradient (#5830D0 → #9858E8) against a deep navy ink
/// (#081840), with pale lavender (#C8C0F0) accents in the calendar dots. The
/// old theme was built on a soft blue (#7C9CFF) that shared nothing with the
/// logo, so the app and its icon looked like different products.
class BrandColors {
  BrandColors._();

  /// Core violet — the logo gradient's midpoint.
  static const Color violet = Color(0xFF6038D8);
  static const Color violetBright = Color(0xFF7757E3);
  static const Color violetLight = Color(0xFF9858E8);

  /// Deep navy from the mark and the "Recall" wordmark.
  static const Color ink = Color(0xFF081840);

  /// Pale lavender from the calendar dots.
  static const Color lavender = Color(0xFFC8C0F0);

  /// The logo artwork's own background.
  static const Color canvas = Color(0xFFFDFFFE);

  /// Lifted violet for dark surfaces — the core violet doesn't carry enough
  /// luminance against a dark background to pass contrast.
  static const Color violetOnDark = Color(0xFF9E85FF);
}

/// Semantic status colours, tuned per brightness so both themes hit similar
/// contrast rather than reusing one set that only works on dark.
///
/// Always reached through [success] / [warning] rather than the raw constants:
/// the `light ? xLight : xDark` ternary was written out at eighteen call sites
/// across nine files, which is eighteen chances to pick the wrong one.
///
/// There is no danger/error entry here on purpose — that comes from
/// `Theme.of(context).colorScheme.error`, which the theme already defines per
/// brightness.
class StatusColors {
  StatusColors._();

  static const Color _successLight = Color(0xFF12805C);
  static const Color _successDark = Color(0xFF5FD3AB);

  static const Color _warningLight = Color(0xFFB25A16);
  static const Color _warningDark = Color(0xFFE8A366);

  /// Done, mastered, on track.
  static Color success(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
          ? _successLight
          : _successDark;

  /// Late, missed, needs attention — short of an outright error.
  static Color warning(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
          ? _warningLight
          : _warningDark;
}

/// Light-first Material 3 theme, with a matching dark variant.
///
/// Every component is themed in *both* modes. The previous `light()` was a
/// 15-line stub that themed only the app bar, so switching to it produced
/// default-blue Material buttons, unstyled inputs and an unreadable navigation
/// bar. It also exposed a `textMuted` constant hardcoded to a dark-theme grey,
/// which ~40 call sites used inside `const TextStyle(...)` — invisible on a
/// light background. Muted text now comes from `colorScheme.onSurfaceVariant`.
class AppTheme {
  AppTheme._();

  // ---------------------------------------------------------------- light
  static const Color _lightBg = Color(0xFFF6F6FB); // faint lavender-grey
  static const Color _lightSurface = Color(0xFFFFFFFF);
  static const Color _lightSurfaceAlt = Color(0xFFF0F0F7);
  static const Color _lightOutline = Color(0xFFE4E4EF);
  static const Color _lightInk = Color(0xFF10142B);
  static const Color _lightMuted = Color(0xFF6A7191);

  // ----------------------------------------------------------------- dark
  // Navy-tinted rather than neutral charcoal, echoing the logo's ink.
  static const Color _darkBg = Color(0xFF0A0E1C);
  static const Color _darkSurface = Color(0xFF141A2E);
  static const Color _darkSurfaceAlt = Color(0xFF1D2440);
  static const Color _darkOutline = Color(0xFF262E4C);
  static const Color _darkInk = Color(0xFFE9EBF5);
  static const Color _darkMuted = Color(0xFF8891B2);

  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: BrandColors.violet,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFEDE8FD),
      onPrimaryContainer: Color(0xFF2A1470),
      secondary: BrandColors.violetLight,
      onSecondary: Colors.white,
      surface: _lightSurface,
      onSurface: _lightInk,
      // Muted body text and icons. This is what replaced `AppTheme.textMuted`.
      onSurfaceVariant: _lightMuted,
      surfaceContainerLowest: Colors.white,
      surfaceContainer: _lightSurface,
      surfaceContainerHigh: _lightSurfaceAlt,
      surfaceContainerHighest: _lightSurfaceAlt,
      outline: _lightOutline,
      outlineVariant: Color(0xFFEFEFF6),
      error: Color(0xFFC42B3E),
      onError: Colors.white,
      errorContainer: Color(0xFFFCE8EA),
      onErrorContainer: Color(0xFF7A1523),
    );
    return _build(scheme, _lightBg, Brightness.light);
  }

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: BrandColors.violetOnDark,
      onPrimary: Color(0xFF130A33),
      primaryContainer: Color(0xFF2B1F5C),
      onPrimaryContainer: Color(0xFFDDD2FF),
      secondary: BrandColors.lavender,
      onSecondary: Color(0xFF130A33),
      surface: _darkSurface,
      onSurface: _darkInk,
      onSurfaceVariant: _darkMuted,
      surfaceContainerLowest: Color(0xFF0D1222),
      surfaceContainer: _darkSurface,
      surfaceContainerHigh: _darkSurfaceAlt,
      surfaceContainerHighest: _darkSurfaceAlt,
      outline: _darkOutline,
      outlineVariant: Color(0xFF1C2338),
      error: Color(0xFFFF8A93),
      onError: Color(0xFF3D0710),
      errorContainer: Color(0xFF4A1620),
      onErrorContainer: Color(0xFFFFD6D9),
    );
    return _build(scheme, _darkBg, Brightness.dark);
  }

  // ------------------------------------------------------------ shared build

  static ThemeData _build(
    ColorScheme scheme,
    Color background,
    Brightness brightness,
  ) {
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final text = _textTheme(scheme);

    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,

      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: AppSpacing.gutter,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: scheme.onSurface, size: 22),
        systemOverlayStyle: brightness == Brightness.light
            ? SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: background,
                systemNavigationBarIconBrightness: Brightness.dark,
              )
            : SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: background,
                systemNavigationBarIconBrightness: Brightness.light,
              ),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: scheme.outline),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: text.labelLarge,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          textStyle: text.labelLarge,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          side: BorderSide(color: scheme.outline),
          textStyle: text.labelLarge,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        border: _inputBorder(Colors.transparent),
        enabledBorder: _inputBorder(Colors.transparent),
        focusedBorder: _inputBorder(scheme.primary, width: 1.6),
        errorBorder: _inputBorder(scheme.error),
        focusedErrorBorder: _inputBorder(scheme.error, width: 1.6),
        hintStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        labelStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        floatingLabelStyle: text.labelMedium?.copyWith(color: scheme.primary),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: 0.14),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return text.labelSmall?.copyWith(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 23,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 3,
        highlightElevation: 3,
        extendedTextStyle: text.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        side: BorderSide.none,
        labelStyle: text.labelMedium,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll(text.labelMedium),
          side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        titleTextStyle: text.titleMedium,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          height: 1.5,
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: scheme.outline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: brightness == Brightness.light
            ? _lightInk
            : _darkSurfaceAlt,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: brightness == Brightness.light ? Colors.white : _darkInk,
        ),
        elevation: 0,
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),

      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.gutter,
          vertical: AppSpacing.xs,
        ),
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
          height: 1.4,
        ),
        minVerticalPadding: AppSpacing.md,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? scheme.primary : null,
        ),
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.primary.withValues(alpha: 0.16),
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
        trackHeight: 4,
        valueIndicatorColor: scheme.primary,
        valueIndicatorTextStyle: text.labelSmall?.copyWith(
          color: scheme.onPrimary,
        ),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.primary.withValues(alpha: 0.14),
        circularTrackColor: Colors.transparent,
      ),

      iconTheme: IconThemeData(color: scheme.onSurface, size: 22),
      dividerColor: scheme.outlineVariant,

      // Shared, restrained page transition on every route push. Android is the
      // only shipping target, so one builder covers it.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _FadeThroughTransitionBuilder(),
        },
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: color, width: width),
      );

  /// One typographic scale for the whole app.
  ///
  /// Screens used to hand-roll `TextStyle(fontSize: 15.5)` and friends, so no
  /// two lists agreed on a title size. Widgets now read from
  /// `Theme.of(context).textTheme`, which means a change here lands everywhere.
  static TextTheme _textTheme(ColorScheme scheme) {
    final ink = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;

    return GoogleFonts.interTextTheme().copyWith(
      // Big numeric readouts (streak counts, stat values).
      displaySmall: GoogleFonts.inter(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        height: 1.1,
        color: ink,
      ),
      // Screen-level greeting/heading.
      headlineSmall: GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        height: 1.2,
        color: ink,
      ),
      // App bar titles.
      titleLarge: GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: ink,
      ),
      // Section headers, card headings.
      titleMedium: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: ink,
      ),
      // List-row titles.
      titleSmall: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: ink,
      ),
      bodyLarge: GoogleFonts.inter(fontSize: 15, height: 1.45, color: ink),
      bodyMedium: GoogleFonts.inter(fontSize: 14, height: 1.45, color: ink),
      // Metadata lines under a title.
      bodySmall: GoogleFonts.inter(fontSize: 13, height: 1.4, color: muted),
      labelLarge: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: ink,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: ink,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: muted,
      ),
    );
  }
}

/// Cross-fade + subtle lift, applied to every pushed route.
///
/// Flutter's stock Android builder slides the whole page up from the bottom,
/// which at this app's navigation depth feels heavier than the content
/// warrants. This travels 12px instead of a full screen height.
class _FadeThroughTransitionBuilder extends PageTransitionsBuilder {
  const _FadeThroughTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: AppMotion.curve,
      reverseCurve: AppMotion.exit,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.018),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
