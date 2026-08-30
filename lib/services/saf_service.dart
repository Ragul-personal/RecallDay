import 'dart:convert';
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

  /// Ask the user to choose the app's storage folder. Remembered for good.
  Future<String?> pickFolder() async {
    try {
      final uri = await _channel
          .invokeMethod<String>('pickFolder', {'persist': true});
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

  /// Ask the user to point at a folder to read once — importing a backup that
  /// was extracted somewhere else.
  ///
  /// Deliberately does NOT become the storage location and is not remembered.
  /// Reusing [pickFolder] here would silently move the app's data folder to
  /// wherever the user happened to browse to.
  Future<String?> pickFolderForImport() async {
    try {
      return await _channel
          .invokeMethod<String>('pickFolder', {'persist': false});
    } on PlatformException catch (e) {
      debugPrint('[saf] pickFolderForImport failed: ${e.message}');
      return null;
    } on MissingPluginException {
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
  Future<Uint8List?> readFile(String name, {String? fromUri}) async {
    final uri = fromUri ?? savedUri;
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

  /// Whether [name] exists in the chosen folder.
  Future<bool> hasFile(String name, {String? fromUri}) async {
    final uri = fromUri ?? savedUri;
    if (uri == null) return false;
    try {
      return await _channel
              .invokeMethod<bool>('hasFile', {'uri': uri, 'name': name}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteFile(String name) async {
    final uri = savedUri;
    if (uri == null) return false;
    try {
      return await _channel
              .invokeMethod<bool>('deleteFile', {'uri': uri, 'name': name}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Confirm the folder really accepts writes, without touching any real file.
  ///
  /// Setup used to prove this by writing the actual backup, which on a fresh
  /// install meant writing an EMPTY database over whatever was already there —
  /// destroying the user's backup before they had a chance to import it. A
  /// throwaway probe answers the same question and harms nothing.
  Future<bool> verifyWritable() async {
    const probe = 'recallday-write-test.txt';
    final ok = await writeFile(
      probe,
      Uint8List.fromList(utf8.encode('ok')),
      mime: 'text/plain',
    );
    if (ok) await deleteFile(probe);
    return ok;
  }

}
