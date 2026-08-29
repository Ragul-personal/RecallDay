import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/storage_service.dart';

/// Light / dark / follow-system, persisted in the existing Hive `prefs` box.
///
/// `main.dart` previously hardcoded `themeMode: ThemeMode.dark`, so the light
/// theme was unreachable no matter what it contained.
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(_read());

  static const String _key = 'theme_mode';

  static ThemeMode _read() {
    try {
      final raw = StorageService.instance.prefs.get(_key) as String?;
      return switch (raw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        // Light-first: the palette is designed around the logo's light canvas,
        // so that's what a new user should meet.
        _ => ThemeMode.light,
      };
    } catch (_) {
      return ThemeMode.light;
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    try {
      await StorageService.instance.prefs.put(_key, mode.name);
    } catch (_) {
      // Persisting is a convenience; a failed write shouldn't undo the switch
      // the user just made and can see.
    }
  }

  /// Straight light↔dark flip for the app-bar toggle. A tri-state cycle through
  /// "system" is confusing from a single icon button — the full choice lives in
  /// Settings instead.
  Future<void> toggle(Brightness current) =>
      set(current == Brightness.dark ? ThemeMode.light : ThemeMode.dark);
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(),
);
