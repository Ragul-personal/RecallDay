import 'package:flutter/material.dart';

/// The RecallDay logo, presented on the light card the artwork was drawn for.
///
/// `assets/logo.png` has an opaque near-white background (#FDFFFE) baked in —
/// it isn't a transparent silhouette. Dropping it straight onto the app's dark
/// scaffold would read as a white rectangle, so it sits on a rounded card of
/// exactly that same colour instead: the card reads as deliberate framing and
/// the image edge disappears into it.
class AppLogo extends StatelessWidget {
  /// Side length of the card, in logical pixels.
  final double size;

  /// Drop shadow. Worth it on the splash, noise in a dense list row.
  final bool elevated;

  const AppLogo({super.key, this.size = 160, this.elevated = true});

  /// The logo artwork's own background colour.
  static const Color canvas = Color(0xFFFDFFFE);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: canvas,
        borderRadius: BorderRadius.circular(size * 0.22),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: size * 0.12,
                  offset: Offset(0, size * 0.04),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(size * 0.06),
        child: Image.asset(
          'assets/logo.png',
          fit: BoxFit.contain,
          // If the asset is ever missing from the bundle, degrade to a plain
          // glyph rather than throwing an exception into the widget tree.
          errorBuilder: (_, __, ___) => Icon(
            Icons.replay_circle_filled_rounded,
            size: size * 0.5,
            color: const Color(0xFF6C4BF6),
          ),
        ),
      ),
    );
  }
}
