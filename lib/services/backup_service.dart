import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/models/review_model.dart';
import '../data/models/subject_model.dart';
import '../data/models/topic_model.dart';
import 'storage_service.dart';

/// Durable, uninstall-surviving backups.
///
/// Why this exists
/// ---------------
/// Hive stores its boxes under the app's *private* data directory. Android
/// deletes that directory wholesale when the app is uninstalled — there is no
/// flag that changes this. So "my data disappeared after reinstall" cannot be
/// fixed inside the Hive layer; the data has to be mirrored somewhere the
/// package manager doesn't own.
///
/// Two independent mechanisms now cover that:
///
///  1. **Android Auto Backup** (configured in AndroidManifest +
///     `res/xml/backup_rules.xml`). Google backs the Hive files up to the
///     user's account and restores them automatically on reinstall. Free and
///     invisible — but only when the device has backup enabled *and* the app
///     is installed through Play or `adb restore`.
///
///  2. **This service** — a plain JSON snapshot written to shared storage
///     (`Documents/RecallDay/`), which survives uninstall because it is not
///     inside the app sandbox. Rewritten automatically after every change and
///     restorable from Settings, or automatically on first launch into an
///     empty database.
///
/// Location fallback
/// -----------------
/// Shared storage is only writable by raw path when the OS grants broad file
/// access (MANAGE_EXTERNAL_STORAGE on Android 11+, WRITE_EXTERNAL_STORAGE
/// below it). Rather than reason about API levels we *probe*: try each
/// candidate directory in order and keep the first one we can actually write
/// to. [BackupLocation.survivesUninstall] tells the UI whether the location we
/// landed on genuinely outlives an uninstall, so Settings can be honest about
/// it instead of promising durability it doesn't have.
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const String _fileName = 'recallday-backup.json';
  /// Keeps a .json extension — see the note in [_writeTo].
  static const String _tempName = 'recallday-backup.writing.json';
  static const String _folderName = 'RecallDay';
  static const int _schemaVersion = 1;

  /// Public shared-storage roots, most preferred first. These live outside the
  /// app sandbox, so uninstalling RecallDay does not remove them.
  static const List<String> _sharedRoots = [
    '/storage/emulated/0/Documents',
    '/storage/emulated/0/Download',
    '/sdcard/Documents',
    '/sdcard/Download',
  ];

  BackupLocation? _cachedLocation;
  Timer? _debounce;

  // ---------------------------------------------------------------- snapshot

  /// Everything the app knows, as a plain JSON-serialisable map.
  Map<String, dynamic> buildSnapshot() {
    final store = StorageService.instance;
    return {
      'schemaVersion': _schemaVersion,
      'app': 'RecallDay',
      'exportedAt': DateTime.now().toIso8601String(),
      'subjects': store.subjects.values.map((m) => m.toJson()).toList(),
      'topics': store.topics.values.map((m) => m.toJson()).toList(),
      'reviews': store.reviews.values.map((m) => m.toJson()).toList(),
    };
  }

  String buildSnapshotJson() =>
      const JsonEncoder.withIndent('  ').convert(buildSnapshot());

  // ------------------------------------------------------------------ write

  /// Write the snapshot, trying each candidate location in turn.
  ///
  /// Never throws: returns a [BackupResult] describing what happened so the
  /// caller can show it. Auto-backup calls this on a debounce, so a failure
  /// here must not disturb the mutation that triggered it.
  ///
  /// This *actually writes* rather than probing first and trusting the result.
  /// A probe is a poor proxy for the real thing: creating a directory and
  /// touching a dot-file under `/storage/emulated/0/Documents` can succeed on
  /// Android while the real write still fails with EACCES, which is exactly
  /// the "Permission denied, errno = 13" users hit. Now a location that fails
  /// is simply skipped and the next one is tried, ending at app-private
  /// storage — which always works, so a backup effectively cannot fail.
  Future<BackupResult> writeBackup() async {
    final snapshot = buildSnapshot();
    final json = const JsonEncoder.withIndent('  ').convert(snapshot);
    final attempts = <String>[];

    for (final location in await _candidateLocations()) {
      final err = await _writeTo(location, json);
      if (err == null) {
        _cachedLocation = location;
        return BackupResult.success(
          path: '${location.path}/$_fileName',
          location: location,
          subjects: (snapshot['subjects'] as List).length,
          topics: (snapshot['topics'] as List).length,
          reviews: (snapshot['reviews'] as List).length,
        );
      }
      attempts.add('• ${location.path}\n    $err');
      debugPrint('[backup] ${location.path} failed: $err');
    }

    return BackupResult.failure(
      'Could not write to any storage location.\n\n${attempts.join('\n')}',
    );
  }

  /// Returns null on success, else a short reason.
  Future<String?> _writeTo(BackupLocation location, String json) async {
    try {
      final dir = Directory(location.path);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final target = File('${location.path}/$_fileName');

      // Write to a sibling temp file then rename, so an interrupted write
      // can't leave a truncated backup where a good one used to be.
      //
      // The temp name keeps the .json extension on purpose. Android's scoped
      // storage rejects files whose extension maps to no permitted MIME type
      // in a shared collection, so the previous `recallday-backup.json.tmp`
      // was refused outright on exactly the directory we most want to use.
      final temp = File('${location.path}/$_tempName');
      await temp.writeAsString(json, flush: true);
      if (await target.exists()) {
        await target.delete();
      }
      await temp.rename(target.path);
      return null;
    } on FileSystemException catch (e) {
      // The OS message ("Permission denied") is the useful part.
      return e.osError?.message ?? e.message;
    } catch (e) {
      return '$e';
    }
  }

  /// Debounced auto-backup. Mutations fire this; the file is rewritten a couple
  /// of seconds after the user stops making changes rather than on every keystroke.
  void scheduleAutoBackup() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () {
      unawaited(writeBackup());
    });
  }

  /// Flush any pending debounced backup immediately.
  Future<BackupResult> flush() {
    _debounce?.cancel();
    _debounce = null;
    return writeBackup();
  }

  // ---------------------------------------------------------------- restore

  /// The most recent backup file we can find, or null.
  Future<File?> findBackupFile() async {
    for (final candidate in await _candidateLocations()) {
      final f = File('${candidate.path}/$_fileName');
      try {
        if (await f.exists()) return f;
      } catch (_) {
        // Unreadable candidate (permission revoked) — keep looking.
      }
    }
    return null;
  }

  /// Restore from a JSON string.
  ///
  /// [merge] true keeps existing records and adds/overwrites by id; false wipes
  /// the boxes first. Ids are stable UUIDs, so merging a backup of the same
  /// database is idempotent.
  Future<RestoreSummary> restoreFromJson(String jsonText,
      {bool merge = true}) async {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Backup file is not a JSON object.');
    }
    if (decoded['subjects'] == null && decoded['topics'] == null) {
      throw const FormatException(
          'Backup file has no "subjects" or "topics" — is this a RecallDay backup?');
    }

    final store = StorageService.instance;
    if (!merge) {
      await store.subjects.clear();
      await store.topics.clear();
      await store.reviews.clear();
    }

    var subjects = 0, topics = 0, reviews = 0, skipped = 0;

    for (final raw in (decoded['subjects'] as List? ?? const [])) {
      try {
        final m = SubjectModel.fromJson(raw as Map<String, dynamic>);
        await store.subjects.put(m.id, m);
        subjects++;
      } catch (e) {
        debugPrint('[backup] skipped subject: $e');
        skipped++;
      }
    }

    for (final raw in (decoded['topics'] as List? ?? const [])) {
      try {
        final m = TopicModel.fromJson(raw as Map<String, dynamic>);
        await store.topics.put(m.id, m);
        topics++;
      } catch (e) {
        debugPrint('[backup] skipped topic: $e');
        skipped++;
      }
    }

    for (final raw in (decoded['reviews'] as List? ?? const [])) {
      try {
        final m = ReviewModel.fromJson(raw as Map<String, dynamic>);
        await store.reviews.put(m.id, m);
        reviews++;
      } catch (e) {
        debugPrint('[backup] skipped review: $e');
        skipped++;
      }
    }

    return RestoreSummary(
      subjects: subjects,
      topics: topics,
      reviews: reviews,
      skipped: skipped,
    );
  }

  /// Restore from the on-disk backup file, if one exists.
  Future<RestoreSummary?> restoreFromFile({bool merge = true}) async {
    final f = await findBackupFile();
    if (f == null) return null;
    return restoreFromJson(await f.readAsString(), merge: merge);
  }

  /// Called at startup. If the database is empty but a backup exists on shared
  /// storage, pull it back in — this is the "I reinstalled the app and my
  /// topics came back" path.
  Future<RestoreSummary?> autoRestoreIfEmpty() async {
    try {
      if (!StorageService.instance.isEmpty) return null;
      final summary = await restoreFromFile(merge: true);
      if (summary != null) {
        debugPrint('[backup] auto-restored $summary');
      }
      return summary;
    } catch (e, st) {
      debugPrint('[backup] auto-restore failed: $e\n$st');
      return null;
    }
  }

  // -------------------------------------------------------------- locations

  /// Ask for the broad storage access that shared-folder writes need.
  ///
  /// Returns true if we ended up with *some* usable access. Callers should
  /// re-run [resolveLocation] afterwards (pass `refresh: true`) because the
  /// answer may have changed.
  Future<bool> requestStoragePermission() async {
    var granted = false;

    // Android 11+ : broad file access is its own special permission.
    try {
      if (await Permission.manageExternalStorage.isGranted) {
        granted = true;
      } else {
        granted = (await Permission.manageExternalStorage.request()).isGranted;
      }
    } catch (e) {
      debugPrint('[backup] manageExternalStorage request failed: $e');
    }

    // Android 10 and below.
    if (!granted) {
      try {
        granted = (await Permission.storage.request()).isGranted;
      } catch (e) {
        debugPrint('[backup] storage request failed: $e');
      }
    }

    _cachedLocation = null;
    return granted;
  }

  /// Human-readable log of the last probe, surfaced when nothing was writable.
  final List<String> _lastProbeLog = [];

  /// Where backups are being written, for display in Settings.
  ///
  /// [writeBackup] no longer depends on this — it just tries each location for
  /// real. This still probes, so Settings can say up front whether the durable
  /// location is reachable, but a wrong answer here can no longer break a
  /// backup.
  Future<BackupLocation?> resolveLocation({bool refresh = false}) async {
    if (!refresh && _cachedLocation != null) return _cachedLocation;
    _lastProbeLog.clear();

    final candidates = await _candidateLocations();
    if (candidates.isEmpty) {
      _lastProbeLog.add('• no candidate directories could be resolved');
    }
    for (final candidate in candidates) {
      final err = await _probe(candidate.path);
      if (err == null) {
        _lastProbeLog.add('• ${candidate.path} — OK');
        _cachedLocation = candidate;
        return candidate;
      }
      _lastProbeLog.add('• ${candidate.path} — $err');
    }
    return null;
  }

  Future<List<BackupLocation>> _candidateLocations() async {
    final out = <BackupLocation>[];

    if (Platform.isAndroid) {
      for (final root in _sharedRoots) {
        out.add(BackupLocation(
          path: '$root/$_folderName',
          label: root.contains('Download')
              ? 'Downloads/$_folderName'
              : 'Documents/$_folderName',
          survivesUninstall: true,
        ));
      }
    }

    // App-scoped external storage: visible over USB, but the package manager
    // deletes it on uninstall like any other app data.
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        out.add(BackupLocation(
          path: '${ext.path}/$_folderName',
          label: 'App storage (visible over USB)',
          survivesUninstall: false,
        ));
      }
    } catch (e) {
      debugPrint('[backup] getExternalStorageDirectory failed: $e');
    }

    try {
      final docs = await getApplicationDocumentsDirectory();
      out.add(BackupLocation(
        path: '${docs.path}/$_folderName',
        label: 'Private app storage',
        survivesUninstall: false,
      ));
    } catch (e) {
      debugPrint('[backup] getApplicationDocumentsDirectory failed: $e');
    }

    return out;
  }

  /// Probe by actually creating the directory and writing a byte. Reasoning
  /// about API levels and permission combinations is far less reliable than
  /// just trying it.
  ///
  /// Returns null when writable, else a short reason.
  Future<String?> _probe(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final probe = File('$path/.write_probe');
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return null;
    } on FileSystemException catch (e) {
      // The OS message ("Permission denied", "Read-only file system") is the
      // useful part; the full exception toString is mostly noise.
      return e.osError?.message ?? e.message;
    } catch (e) {
      return '$e';
    }
  }
}

class BackupLocation {
  final String path;
  final String label;

  /// True only for directories outside the app sandbox. The UI uses this to
  /// tell the user whether their backup would actually survive an uninstall.
  final bool survivesUninstall;

  const BackupLocation({
    required this.path,
    required this.label,
    required this.survivesUninstall,
  });
}

class BackupResult {
  final bool ok;
  final String? path;
  final BackupLocation? location;
  final String? error;
  final int subjects, topics, reviews;

  const BackupResult.success({
    required this.path,
    required this.location,
    required this.subjects,
    required this.topics,
    required this.reviews,
  })  : ok = true,
        error = null;

  const BackupResult.failure(this.error)
      : ok = false,
        path = null,
        location = null,
        subjects = 0,
        topics = 0,
        reviews = 0;
}

class RestoreSummary {
  final int subjects, topics, reviews, skipped;
  const RestoreSummary({
    required this.subjects,
    required this.topics,
    required this.reviews,
    required this.skipped,
  });

  bool get isEmpty => subjects == 0 && topics == 0 && reviews == 0;

  @override
  String toString() =>
      '$subjects subjects, $topics topics, $reviews reviews'
      '${skipped > 0 ? ' ($skipped skipped)' : ''}';
}
