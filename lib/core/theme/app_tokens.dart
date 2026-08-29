import 'package:flutter/animation.dart';

/// Design tokens — the single source of truth for spacing, shape and motion.
///
/// Before these existed the app used ad-hoc values everywhere: six different
/// corner radii, four different card paddings, and font sizes like 15.5 / 12.5
/// / 11.5 chosen per widget. Screens drifted apart because there was nothing to
/// drift *from*. Everything below is on a 4pt grid.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;
  static const double xxxl = 40;

  /// Horizontal page gutter. Every scrollable screen uses this, so content
  /// lines up vertically as you move between tabs.
  static const double gutter = 20;

  /// Bottom padding that clears the navigation bar and the FAB.
  static const double bottomInset = 104;
}

/// Corner radii. Three steps, not six.
class AppRadius {
  AppRadius._();

  /// Pills, chips, small badges.
  static const double sm = 10;

  /// Buttons, inputs, inner containers.
  static const double md = 14;

  /// Cards and sheets — the app's signature shape.
  static const double lg = 20;

  /// Hero surfaces (logo card, bottom sheets).
  static const double xl = 28;
}

/// Motion. Short and consistent; the point is for movement to go unnoticed.
class AppMotion {
  AppMotion._();

  /// Taps, toggles, colour changes.
  static const Duration fast = Duration(milliseconds: 150);

  /// The default for almost everything: entrances, expansions, page pushes.
  static const Duration base = Duration(milliseconds: 240);

  /// Larger surfaces travelling further.
  static const Duration slow = Duration(milliseconds: 340);

  /// Decelerating curve — fast out of the gate, gentle arrival. Reads as
  /// responsive rather than floaty.
  static const Curve curve = Curves.easeOutCubic;

  /// For things leaving the screen.
  static const Curve exit = Curves.easeInCubic;

  /// Per-item delay for staggered list entrances.
  static const Duration stagger = Duration(milliseconds: 28);

  /// Cap on how many items stagger. The old code used `40ms * index` with no
  /// ceiling, so the 20th row didn't appear for 800ms and long lists felt
  /// broken. Past this index every remaining row animates together.
  static const int staggerCap = 6;

  /// Delay for item [i], flattening out after [staggerCap].
  static Duration staggerFor(int i) =>
      stagger * (i > staggerCap ? staggerCap : i);
}
