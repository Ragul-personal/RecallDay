import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_tokens.dart';

/// The app's single entrance animation: a short fade with a small upward
/// settle. Used for list rows and cards so every screen enters the same way.
///
/// Screens previously called `.animate(delay: (40 * i).ms).fadeIn(...)` inline
/// with an uncapped delay, so a 20-row list took 800ms to finish appearing and
/// the movement read as lag rather than polish. [AppMotion.staggerFor] flattens
/// the delay after a handful of rows.
class FadeSlideIn extends StatelessWidget {
  final Widget child;

  /// Position in a list; drives the stagger delay.
  final int index;

  /// Extra delay before the stagger begins.
  final Duration delay;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.delay = Duration.zero,
  });

  @override
  Widget build(BuildContext context) {
    return child
        .animate(delay: delay + AppMotion.staggerFor(index))
        .fadeIn(duration: AppMotion.base, curve: AppMotion.curve)
        .slideY(
          begin: 0.05,
          end: 0,
          duration: AppMotion.base,
          curve: AppMotion.curve,
        );
  }
}

/// Animates a numeric readout when it changes, instead of snapping.
class AnimatedCount extends StatelessWidget {
  final int value;
  final TextStyle? style;

  const AnimatedCount(this.value, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: AppMotion.slow,
      curve: AppMotion.curve,
      builder: (_, v, __) => Text(v.round().toString(), style: style),
    );
  }
}
