import 'package:flutter/material.dart';

/// Subject accent colours, rebuilt around the logo's violet.
///
/// The old set opened on a soft blue (#7C9CFF) with mint/sand/sage tones that
/// pulled against the brand. These are all mid-saturation and share a similar
/// perceived lightness, so a grid of subject cards reads as one family and no
/// single tile shouts louder than its neighbours. Violet leads, since it's the
/// brand colour and therefore the sensible default for a first subject.
class SubjectPalette {
  SubjectPalette._();

  static const List<Color> colors = [
    Color(0xFF6038D8), // brand violet
    Color(0xFF2E7BE0), // azure
    Color(0xFF128C86), // teal
    Color(0xFF2E9457), // green
    Color(0xFFB07A12), // amber
    Color(0xFFD1622E), // burnt orange
    Color(0xFFC7386B), // raspberry
    Color(0xFF8348C9), // orchid
  ];

  static const List<String> iconKeys = [
    'book', 'function', 'cpu', 'network', 'database',
    'flask', 'compass', 'leaf', 'graph', 'pencil',
  ];

  static IconData iconFor(String key) {
    switch (key) {
      case 'book':
        return Icons.menu_book_rounded;
      case 'function':
        return Icons.functions_rounded;
      case 'cpu':
        return Icons.memory_rounded;
      case 'network':
        return Icons.hub_rounded;
      case 'database':
        return Icons.storage_rounded;
      case 'flask':
        return Icons.science_rounded;
      case 'compass':
        return Icons.explore_rounded;
      case 'leaf':
        return Icons.eco_rounded;
      case 'graph':
        return Icons.show_chart_rounded;
      case 'pencil':
        return Icons.edit_rounded;
      default:
        return Icons.bookmark_rounded;
    }
  }

  /// A subject colour readable as *text* on the current background.
  ///
  /// The stored colours are chosen for light surfaces; several are too dark to
  /// read on the dark theme, so they're lifted there.
  static Color readable(Color c, Brightness brightness) {
    if (brightness == Brightness.light) return c;
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness + 0.26).clamp(0.0, 0.82))
        .withSaturation((hsl.saturation * 0.9).clamp(0.0, 1.0))
        .toColor();
  }
}
