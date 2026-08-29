import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'storage_service.dart';

/// A folder the user nominated for backups, via Android's Storage Access
/// Framework.
///
/// The point of this is to remove the manual export step. Once a folder is
/// chosen the app writes to it after every change, with no permission and no
/// prompt, and the file lives outside the app sandbox so an uninstall doesn't
/// take it. After reinstalling, the user re-picks the same folder once —
/// Android drops persisted grants along with the app's identity — and the app
/// carries on writing to the same file and can restore from it.
///
/// This replaces raw `/storage/emulated/0/...` paths, which were never a real
/// filesystem contract: writes could succeed while reads failed with EACCES,
/// and the OS rewrote extensions behind our back.
class SafService {
  SafService._();
  static final SafService instance = SafService._();

  static const MethodChannel _channel = MethodChannel('recallday/saf');
  static const String _prefKey = 'saf_backup_tree';

  /// The saved folder URI, or null if none has been chosen.
  String? get savedUri {
    try {
      return StorageService.instance.prefs.get(_prefKey) as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _remember(String? uri) async {
    try {
      final prefs = StorageService.instance.prefs;
      if (uri == null) {
        await prefs.delete(_prefKey);
      } else {
        await prefs.put(_prefKey, uri);
      }
    } catch (e) {
      debugPrint('[saf] could not persist folder choice: $e');
    }
  }

  /// Ask the user to choose a folder. Returns its URI, or null if cancelled.
  Future<String?> pickFolder() async {
    try {
      final uri = await _channel.invokeMethod<String>('pickFolder');
      if (uri != null) await _remember(uri);
      return uri;
    } on PlatformException catch (e) {
      debugPrint('[saf] pickFolder failed: ${e.message}');
      return null;
    } on MissingPluginException {
      // Non-Android, or an engine without the channel attached.
      return null;
    }
  }

  /// Whether a folder is chosen AND still readable/writable.
  ///
  /// Checked rather than assumed: the grant is revoked by an uninstall, and a
  /// user can withdraw it from Android's settings at any time.
  Future<bool> hasAccess() async {
    final uri = savedUri;
    if (uri == null) return false;
    try {
      return await _channel.invokeMethod<bool>('hasAccess', {'uri': uri}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Display name of the chosen folder, for the UI.
  Future<String?> folderName() async {
    final uri = savedUri;
    if (uri == null) return null;
    try {
      return await _channel.invokeMethod<String>('folderName', {'uri': uri});
    } catch (_) {
      return null;
    }
  }

  /// Write (or overwrite) a file in the chosen folder. Returns false when the
  /// folder is gone or access was withdrawn.
  Future<bool> writeFile(
    String name,
    Uint8List bytes, {
    String mime = 'application/octet-stream',
  }) async {
    final uri = savedUri;
    if (uri == null) return false;
    try {
      final result = await _channel.invokeMethod<String>('writeFile', {
        'uri': uri,
        'name': name,
        'bytes': bytes,
        'mime': mime,
      });
      return result != null;
    } catch (e) {
      debugPrint('[saf] write "$name" failed: $e');
      return false;
    }
  }

  /// Read a file from the chosen folder, or null if it isn't there.
  Future<Uint8List?> readFile(String name) async {
    final uri = savedUri;
    if (uri == null) return null;
    try {
      return await _channel.invokeMethod<Uint8List>('readFile', {
        'uri': uri,
        'name': name,
      });
    } catch (e) {
      debugPrint('[saf] read "$name" failed: $e');
      return null;
    }
  }

  /// Forget the folder and hand the grant back to Android.
  Future<void> forget() async {
    final uri = savedUri;
    if (uri != null) {
      try {
        await _channel.invokeMethod<bool>('release', {'uri': uri});
      } catch (_) {
        // Already gone; dropping our own reference is what matters.
      }
    }
    await _remember(null);
  }
}
