import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'saf_service.dart';

import '../data/models/review_model.dart';
import '../data/models/subject_model.dart';
import '../data/models/topic_model.dart';
import '../domain/entities/attachment.dart';
import 'storage_service.dart';

/// Backup and restore.
///
/// Why this shape
/// --------------
/// Hive lives in the app's private directory, which Android deletes on
/// uninstall, so durable copies have to leave the sandbox. The previous design
/// did that by writing to `/storage/emulated/0/Documents/RecallDay` through
/// raw `dart:io` paths. That is not a reliable contract on modern Android, and
/// it failed three separate ways in practice:
///
///   • A write could appear to succeed while the matching read failed with
///     `PathAccessException … errno = 13`: without a real
///     MANAGE_EXTERNAL_STORAGE grant, some operations pass through a media
///     shim and others are refused outright.
///   • `File.exists()` returns *false* rather than throwing when access is
///     denied, so a present-but-forbidden backup looked like no backup at all
///     and the first-launch prompt reported "none found".
///   • The write-to-temp-then-rename dance left `.writing` files behind, and
///     the OS silently rewrote their extension (`.writing.json` arrived as
///     `.writing.js`) — plain evidence that the platform, not the filesystem,
///     was deciding what happened.
///
/// So raw shared-storage paths are gone, along with the storage permissions
/// they needed. Instead:
///
///   1. **Automatic** — after every change a JSON snapshot is written to
///      app-private storage. This always succeeds, needs no permission, and is
///      covered by Android Auto Backup, so a Play or `adb` reinstall restores
///      it invisibly. It's also what the first-launch prompt reads.
///   2. **Export** — one `.zip` holding the database *and every attachment*,
///      handed to the system share sheet. The user saves it to Drive, Files,
///      or sends it to themselves. The OS owns the destination, so there is no
///      permission to be denied.
///   3. **Import** — chosen through the system file picker, which grants read
///      access to that one file. This is why importing works where reading a
///      raw path did not.
///
/// Attachments were previously absent from backups entirely, so a restore
/// produced topics pointing at files that no longer existed. The export
/// carries them and the import rewrites every path for the new install.
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  /// The automatic snapshot, in app-private storage.
  static const String _autoFileName = 'recallday-backup.json';

  /// Name of the full archive inside the user's chosen folder.
  static const String _archiveFileName = 'recallday-backup.zip';

  /// Entry names inside an exported archive.
  static const String _archiveData = 'data.json';
  static const String _archiveAttachments = 'attachments';

  static const int _schemaVersion = 2;

  // ---------------------------------------------------------------- snapshot

  /// Everything in the database, as a plain JSON-serialisable map.
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

  // ------------------------------------------------------- automatic backup

  Future<File> _autoFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_autoFileName');
  }

  bool _writing = false;
  bool _queued = false;

  /// Save now.
  ///
  /// Called after every mutation, so a subject, topic or recorded revision is
  /// on disk before the user moves on. Writes are serialised with a single
  /// queued follow-up: a burst of edits ends in exactly one write of the final
  /// state, and the file is never written concurrently.
  void scheduleAutoBackup() => unawaited(_runSerialised());

  Future<void> _runSerialised() async {
    if (_writing) {
      _queued = true;
      return;
    }
    _writing = true;
    try {
      do {
        _queued = false;
        await writeAutoBackup();
      } while (_queued);
    } finally {
      _writing = false;
    }
  }

  /// Write the automatic snapshot.
  ///
  /// Always to app-private storage, which cannot fail for permission reasons.
  /// Then, if the user has nominated a folder, the same JSON is mirrored there
  /// — that copy is what survives an uninstall, and it is why the export step
  /// is optional rather than the only durable route.
  Future<BackupResult> writeAutoBackup() async {
    try {
      final json = buildSnapshotJson();
      final f = await _autoFile();
      await f.writeAsString(json, flush: true);

      final mirrored = await SafService.instance.writeFile(
        _autoFileName,
        Uint8List.fromList(utf8.encode(json)),
        mime: 'application/json',
      );

      final store = StorageService.instance;
      return BackupResult.success(
        path: f.path,
        mirroredToFolder: mirrored,
        subjects: store.subjects.length,
        topics: store.topics.length,
        reviews: store.reviews.length,
      );
    } catch (e, st) {
      debugPrint('[backup] auto write failed: $e\n$st');
      return BackupResult.failure('$e');
    }
  }

  /// Write the full archive (data + attachments) into the chosen folder.
  ///
  /// Heavier than the JSON mirror, so this runs when the app goes to the
  /// background and on an explicit request, not on every keystroke-free edit.
  Future<bool> mirrorArchiveToFolder() async {
    if (!await SafService.instance.hasAccess()) return false;
    try {
      final file = await buildArchiveFile();
      final ok = await SafService.instance.writeFile(
        _archiveFileName,
        await file.readAsBytes(),
        mime: 'application/zip',
      );
      return ok;
    } catch (e) {
      debugPrint('[backup] archive mirror failed: $e');
      return false;
    }
  }

  /// Restore from the chosen folder: the archive if present (it carries
  /// attachments), else the JSON snapshot.
  Future<RestoreSummary?> restoreFromFolder({bool merge = true}) async {
    final saf = SafService.instance;
    if (!await saf.hasAccess()) return null;

    final zip = await saf.readFile(_archiveFileName);
    if (zip != null) return restoreFromArchiveBytes(zip, merge: merge);

    final json = await saf.readFile(_autoFileName);
    if (json != null) {
      return restoreFromJson(utf8.decode(json), merge: merge);
    }
    return null;
  }

  /// Move any backup already in the chosen folder aside before the app starts
  /// writing its own.
  ///
  /// Adopting a folder must never cost the user the file they already had
  /// there. Renaming keeps it — under a dated name — instead of letting the
  /// first automatic save overwrite it.
  Future<void> preserveExistingBackups() async {
    final saf = SafService.instance;
    if (!await saf.hasAccess()) return;

    final now = DateTime.now();
    final stamp = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}';

    for (final name in const [_archiveFileName, _autoFileName]) {
      if (!await saf.hasFile(name)) continue;
      final dot = name.lastIndexOf('.');
      final base = name.substring(0, dot);
      final ext = name.substring(dot);
      await saf.renameFile(name, '$base-previous-$stamp$ext');
    }
  }

  /// Whether the chosen folder holds anything restorable.
  Future<bool> folderHasBackup() async {
    final saf = SafService.instance;
    if (!await saf.hasAccess()) return false;
    return await saf.readFile(_archiveFileName) != null ||
        await saf.readFile(_autoFileName) != null;
  }

  /// Write now and report. Used on app background and by Settings.
  Future<BackupResult> flush() async {
    while (_writing) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    _writing = true;
    try {
      return await writeAutoBackup();
    } finally {
      _writing = false;
    }
  }

  /// When the automatic snapshot was last written, or null if there isn't one.
  Future<DateTime?> lastAutoBackupAt() async {
    try {
      final f = await _autoFile();
      return await f.exists() ? (await f.stat()).modified : null;
    } catch (_) {
      return null;
    }
  }

  /// Whether there is an automatic snapshot worth offering to restore.
  Future<bool> hasAutoBackup() async {
    try {
      return await (await _autoFile()).exists();
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------------ export

  /// Build the portable archive: database plus every attachment file.
  Future<File> buildArchiveFile() async {
    final archive = Archive();

    final json = utf8.encode(buildSnapshotJson());
    archive.addFile(ArchiveFile(_archiveData, json.length, json));

    // Attachments go in under attachments/<topicId>/<filename>, mirroring
    // their on-disk layout so import can put them straight back.
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory('${docs.path}/$_archiveAttachments');
    if (await root.exists()) {
      await for (final entity in root.list(recursive: true)) {
        if (entity is! File) continue;
        try {
          final bytes = await entity.readAsBytes();
          final rel = entity.path.substring(root.path.length + 1);
          archive.addFile(
            ArchiveFile('$_archiveAttachments/$rel', bytes.length, bytes),
          );
        } catch (e) {
          debugPrint('[backup] skipped attachment ${entity.path}: $e');
        }
      }
    }

    // encode() is nullable in archive 3.x — it returns null if the archive
    // can't be written out at all.
    final bytes = ZipEncoder().encode(archive);
    if (bytes == null) {
      throw const FormatException('The backup archive could not be built.');
    }

    // Written to the cache directory: the share sheet copies it wherever the
    // user chooses, so this copy is disposable.
    final tmp = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final out = File('${tmp.path}/recallday-backup-$stamp.zip');
    await out.writeAsBytes(bytes, flush: true);
    return out;
  }

  /// Hand the archive to the system share sheet.
  ///
  /// Returns null on success, else a message. The OS owns the destination, so
  /// no storage permission is involved and the user can put it anywhere.
  Future<String?> exportArchive() async {
    try {
      final file = await buildArchiveFile();
      final result = await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'RecallDay backup',
      );
      return result.status == ShareResultStatus.unavailable
          ? 'No app was available to receive the backup.'
          : null;
    } catch (e, st) {
      debugPrint('[backup] export failed: $e\n$st');
      return '$e';
    }
  }

  // ------------------------------------------------------------------ import

  /// Let the user pick a backup and restore it.
  ///
  /// Accepts both the `.zip` export and a bare `.json` snapshot. The picker
  /// grants read access to the chosen file, which is why this works where
  /// reading a raw `/storage/emulated/0/...` path did not.
  Future<RestoreSummary> importArchive({bool merge = true}) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) {
      throw const BackupCancelled();
    }

    final f = picked.files.first;
    final bytes =
        f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
    if (bytes == null) {
      throw const FormatException('That file could not be read.');
    }

    if (f.name.toLowerCase().endsWith('.zip')) {
      return restoreFromArchiveBytes(bytes, merge: merge);
    }
    return restoreFromJson(utf8.decode(bytes), merge: merge);
  }

  /// Restore a `.zip` export: database first, then the attachment files.
  Future<RestoreSummary> restoreFromArchiveBytes(
    List<int> bytes, {
    bool merge = true,
  }) async {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('That file is not a readable backup.');
    }

    ArchiveFile? data;
    for (final f in archive.files) {
      if (f.name == _archiveData) data = f;
    }
    if (data == null) {
      throw const FormatException(
        'That archive has no data.json — is it a RecallDay backup?',
      );
    }

    // Attachment files land in this install's own directory. The absolute
    // paths recorded in the backup belong to the *old* install and don't exist
    // here, so they're rewritten in [_rehomeAttachments].
    final docs = await getApplicationDocumentsDirectory();
    final newPaths = <String, String>{}; // '<topicId>/<file>' -> absolute
    var files = 0;
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      if (!entry.name.startsWith('$_archiveAttachments/')) continue;
      try {
        final rel = entry.name.substring(_archiveAttachments.length + 1);
        final dest = File('${docs.path}/$_archiveAttachments/$rel');
        await dest.parent.create(recursive: true);
        await dest.writeAsBytes(entry.content as List<int>, flush: true);
        newPaths[rel] = dest.path;
        files++;
      } catch (e) {
        debugPrint('[backup] could not restore ${entry.name}: $e');
      }
    }

    final summary = await restoreFromJson(
      utf8.decode(data.content as List<int>),
      merge: merge,
      attachmentPaths: newPaths,
    );
    return summary.withFiles(files);
  }

  /// Restore from a JSON snapshot.
  ///
  /// [merge] true keeps existing records and adds/overwrites by id; false
  /// wipes the boxes first. Ids are stable UUIDs, so merging a backup of the
  /// same database is idempotent.
  ///
  /// [attachmentPaths] maps `<topicId>/<filename>` to the absolute path the
  /// file was just written to, so restored topics point at files that exist.
  Future<RestoreSummary> restoreFromJson(
    String jsonText, {
    bool merge = true,
    Map<String, String> attachmentPaths = const {},
  }) async {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('That file is not a RecallDay backup.');
    }
    if (decoded['subjects'] == null && decoded['topics'] == null) {
      throw const FormatException(
        'That backup has no subjects or topics in it.',
      );
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
        var m = TopicModel.fromJson(raw as Map<String, dynamic>);
        m = _rehomeAttachments(m, attachmentPaths);
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

  /// Point a restored topic's file attachments at this install's paths.
  ///
  /// An app's private directory changes between installs, so absolute paths
  /// inside a backup mean nothing here. Web links are left alone.
  TopicModel _rehomeAttachments(TopicModel m, Map<String, String> paths) {
    if (m.attachments.isEmpty || paths.isEmpty) return m;
    final rebuilt = Attachment.decodeAll(m.attachments).map((a) {
      if (!a.isLocalFile) return a;
      final now = paths['${m.id}/${a.target.split('/').last}'];
      if (now == null) return a;
      return Attachment(
        id: a.id,
        kind: a.kind,
        target: now,
        name: a.name,
        addedAt: a.addedAt,
      );
    }).toList();
    m.attachments = Attachment.encodeAll(rebuilt);
    return m;
  }

  // ------------------------------------------------------------ auto restore

  /// Restore the automatic snapshot if the database is empty.
  ///
  /// Covers "I cleared app data" and an Auto-Backup-restored reinstall. It
  /// cannot cover a plain uninstall — that erases app-private storage,
  /// including this file, which is exactly what the .zip export is for.
  Future<RestoreSummary?> autoRestoreIfEmpty() async {
    try {
      if (!StorageService.instance.isEmpty) return null;
      final f = await _autoFile();
      if (!await f.exists()) return null;
      return await restoreFromJson(await f.readAsString());
    } catch (e, st) {
      debugPrint('[backup] auto-restore failed: $e\n$st');
      return null;
    }
  }
}

/// Thrown when the user dismisses the file picker.
class BackupCancelled implements Exception {
  const BackupCancelled();
  @override
  String toString() => 'Cancelled';
}

class BackupResult {
  final bool ok;
  final String? path;
  final String? error;

  /// True when the snapshot also reached the user's chosen folder — the copy
  /// that outlives an uninstall.
  final bool mirroredToFolder;

  final int subjects, topics, reviews;

  const BackupResult.success({
    required this.path,
    required this.subjects,
    required this.topics,
    required this.reviews,
    this.mirroredToFolder = false,
  })  : ok = true,
        error = null;

  const BackupResult.failure(this.error)
      : ok = false,
        path = null,
        mirroredToFolder = false,
        subjects = 0,
        topics = 0,
        reviews = 0;
}

class RestoreSummary {
  final int subjects, topics, reviews, skipped, files;

  const RestoreSummary({
    required this.subjects,
    required this.topics,
    required this.reviews,
    required this.skipped,
    this.files = 0,
  });

  RestoreSummary withFiles(int n) => RestoreSummary(
        subjects: subjects,
        topics: topics,
        reviews: reviews,
        skipped: skipped,
        files: n,
      );

  bool get isEmpty => subjects == 0 && topics == 0 && reviews == 0;

  @override
  String toString() => '$subjects subjects, $topics topics, $reviews reviews'
      '${files > 0 ? ', $files files' : ''}'
      '${skipped > 0 ? ' ($skipped skipped)' : ''}';
}
