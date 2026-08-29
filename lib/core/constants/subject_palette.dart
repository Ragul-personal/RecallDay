import 'package:flutter/material.dart';

/// Curated palette of muted accent colors used when creating subjects.
class SubjectPalette {
  static const List<Color> colors = [
    Color(0xFF7C9CFF), // soft blue
    Color(0xFF8FD9C0), // mint
    Color(0xFFE0A878), // warm sand
    Color(0xFFC586C0), // mauve
    Color(0xFFEF8C8C), // coral
    Color(0xFF9AB7B0), // sage
    Color(0xFFC9C28A), // dusty olive
    Color(0xFF8FB8FF), // sky
  ];

  static const List<String> iconKeys = [
    'book', 'function', 'cpu', 'network', 'database',
    'flask', 'compass', 'leaf', 'graph', 'pencil',
  ];

  static IconData iconFor(String key) {
    switch (key) {
      case 'book': return Icons.menu_book_outlined;
      case 'function': return Icons.functions;
      case 'cpu': return Icons.memory_outlined;
      case 'network': return Icons.hub_outlined;
      case 'database': return Icons.storage_outlined;
      case 'flask': return Icons.science_outlined;
      case 'compass': return Icons.explore_outlined;
      case 'leaf': return Icons.eco_outlined;
      case 'graph': return Icons.show_chart_outlined;
      case 'pencil': return Icons.edit_outlined;
      default: return Icons.bookmark_outline;
    }
  }
}
