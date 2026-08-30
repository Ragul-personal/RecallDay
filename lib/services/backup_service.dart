import 'dart:async';
import 'dart:isolate';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
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

  /// The one file to pick when restoring: a small JSON snapshot of the
  /// database, living in the root of the chosen folder.
  static const String _folderData = 'recallday-backup.json';

  /// Attachments sit beside it in their own subfolder, one file each.
  ///
  /// They are deliberately NOT bundled into a zip for the automatic backup.
  /// Doing that re-read and re-compressed every attachment on every change:
  /// with 64 MB of video, renaming a topic rebuilt 64 MB of archive in memory
  /// and pushed it through a method channel, which blocked the UI thread for
  /// seconds and pushed the process past its heap limit until Android killed
  /// it. Attachments are immutable once added, so each one is copied across
  /// exactly once, streamed, and never touched again.
  static const String _folderFiles = 'RecallDay-files';

  /// Name used only by the explicit share/export action.
  static const String _archiveFileName = 'recallday-backup.zip';

  /// Written by versions that mirrored a zip automatically. Read on restore so
  /// an older folder isn't orphaned; never written again.
  static const String _legacyFolderZip = 'recallday-backup.zip';

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

  /// Save the database snapshot: app-private, and mirrored into the chosen
  /// folder.
  ///
  /// Only the database — measured in kilobytes even with hundreds of topics —
  /// so this stays cheap enough to run on every change. Attachments travel
  /// separately via [syncAttachment], once each.
  Future<BackupResult> writeAutoBackup() async {
    try {
      final json = buildSnapshotJson();
      final f = await _autoFile();
      await f.writeAsString(json, flush: true);

      final mirrored = await SafService.instance.writeFile(
        _folderData,
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

  /// Copy one attachment into the chosen folder, streamed.
  ///
  /// Called when an attachment is added. Constant memory regardless of size,
  /// and each file is written exactly once for its lifetime.
  Future<bool> syncAttachment(String topicId, String localPath) async {
    if (!await SafService.instance.hasAccess()) return false;
    final name = localPath.split('/').last;
    return SafService.instance.copyIn(
      '$_folderFiles/$topicId/$name',
      localPath,
      mime: _mimeFor(name),
    );
  }

  Future<void> removeAttachmentFromFolder(String topicId, String localPath) async {
    if (!await SafService.instance.hasAccess()) return;
    final name = localPath.split('/').last;
    await SafService.instance.deleteAt('$_folderFiles/$topicId/$name');
  }

  Future<void> removeTopicFilesFromFolder(String topicId) async {
    if (!await SafService.instance.hasAccess()) return;
    for (final rel in await SafService.instance.listAt('$_folderFiles/$topicId')) {
      await SafService.instance.deleteAt('$_folderFiles/$topicId/$rel');
    }
  }

  /// Push across any attachment the folder doesn't have yet.
  ///
  /// Covers files added before a folder was chosen, and anything that failed
  /// mid-copy. Runs on adoption and when the app goes to the background, never
  /// on the hot path.
  Future<int> syncMissingAttachments() async {
    final saf = SafService.instance;
    if (!await saf.hasAccess()) return 0;

    final docs = await getApplicationDocumentsDirectory();
    final root = Directory('${docs.path}/attachments');
    if (!await root.exists()) return 0;

    final present = (await saf.listAt(_folderFiles)).toSet();
    var copied = 0;
    await for (final entity in root.list(recursive: true)) {
      if (entity is! File) continue;
      final rel = entity.path.substring(root.path.length + 1);
      if (present.contains(rel)) continue;
      if (await saf.copyIn(
        '$_folderFiles/$rel',
        entity.path,
        mime: _mimeFor(rel),
      )) {
        copied++;
      }
    }
    return copied;
  }

  static String _mimeFor(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'mp4' || 'm4v' => 'video/mp4',
      'mov' => 'video/quicktime',
      'mkv' => 'video/x-matroska',
      'webm' => 'video/webm',
      'pdf' => 'application/pdf',
      'json' => 'application/json',
      'txt' => 'text/plain',
      _ => 'application/octet-stream',
    };
  }

  /// Write the full archive (data + attachments) into the chosen folder.
  ///
  /// Heavier than the JSON mirror, so this runs when the app goes to the
  /// background and on an explicit request, not on every keystroke-free edit.
  /// Bring the folder fully up to date: database snapshot plus any attachment
  /// it is missing.
  ///
  /// Runs on app background and on explicit request — never on the hot path.
  /// It replaced a full zip rebuild that ran two seconds after *every* change.
  Future<bool> mirrorArchiveToFolder() async {
    if (!await SafService.instance.hasAccess()) return false;
    try {
      await writeAutoBackup();
      await syncMissingAttachments();
      return true;
    } catch (e) {
      debugPrint('[backup] folder sync failed: $e');
      return false;
    }
  }

  /// Take ownership of the chosen folder, folding in whatever is already there.
  ///
  /// Anything the folder already holds is merged into the current database by
  /// id, so previous and current data end up as one set rather than rival
  /// copies, and then the folder is brought up to date. Older folders written
  /// as a single zip are read once and unpacked into the current layout.
  Future<RestoreSummary?> adoptFolder() async {
    final saf = SafService.instance;
    if (!await saf.hasAccess()) return null;

    RestoreSummary? merged;
    try {
      merged = await restoreFromFolder(merge: true);
    } catch (e) {
      // A folder holding something unreadable must not block setup — the
      // canonical files are written below regardless.
      debugPrint('[backup] could not merge existing folder backup: $e');
    }

    // An older folder kept everything in one zip. Once its contents are in the
    // current layout the zip is stale, and leaving it would mean two things
    // claiming to be the backup.
    if (await saf.hasFile(_legacyFolderZip)) {
      await saf.deleteFile(_legacyFolderZip);
    }

    await writeAutoBackup();
    await syncMissingAttachments();
    return merged;
  }

  /// Restore everything the chosen folder holds.
  ///
  /// Current layout first (a small JSON plus loose attachment files), then the
  /// single-zip layout written by older versions.
  Future<RestoreSummary?> restoreFromFolder({bool merge = true}) async {
    final saf = SafService.instance;
    if (!await saf.hasAccess()) return null;

    final json = await saf.readFile(_folderData);
    if (json != null) {
      final summary =
          await restoreFromJson(utf8.decode(json), merge: merge);
      final files = await _pullAttachmentsFromFolder();
      return summary.withFiles(files);
    }

    // Legacy: one zip holding both. Streamed through a temp file rather than
    // decoded from a byte array, so a large one can't exhaust the heap.
    if (await saf.hasFile(_legacyFolderZip)) {
      final tmp = await getTemporaryDirectory();
      final staged = '${tmp.path}/restore-staged.zip';
      if (await saf.copyOut(_legacyFolderZip, staged)) {
        try {
          return await restoreFromArchivePath(staged, merge: merge);
        } finally {
          try {
            await File(staged).delete();
          } catch (_) {}
        }
      }
    }
    return null;
  }

  /// Copy attachment files out of the folder into app storage, skipping any
  /// already present. Streamed one at a time.
  Future<int> _pullAttachmentsFromFolder() async {
    final saf = SafService.instance;
    final docs = await getApplicationDocumentsDirectory();
    var copied = 0;

    for (final rel in await saf.listAt(_folderFiles)) {
      final dest = File('${docs.path}/attachments/$rel');
      if (await dest.exists()) continue;
      await dest.parent.create(recursive: true);
      if (await saf.copyOut('$_folderFiles/$rel', dest.path)) copied++;
    }

    if (copied > 0) await _rehomeAllAttachments();
    return copied;
  }

  /// Point every topic's file attachments at this install's paths.
  ///
  /// Absolute paths inside a backup belong to the install that wrote them, so
  /// after pulling files across they have to be rewritten or nothing opens.
  Future<void> _rehomeAllAttachments() async {
    final docs = await getApplicationDocumentsDirectory();
    final box = StorageService.instance.topics;

    for (final key in box.keys.toList()) {
      final m = box.get(key);
      if (m == null || m.attachments.isEmpty) continue;

      var changed = false;
      final rebuilt = Attachment.decodeAll(m.attachments).map((a) {
        if (!a.isLocalFile) return a;
        final expected =
            '${docs.path}/attachments/${m.id}/${a.target.split('/').last}';
        if (a.target == expected) return a;
        changed = true;
        return Attachment(
          id: a.id,
          kind: a.kind,
          target: expected,
          name: a.name,
          addedAt: a.addedAt,
        );
      }).toList();

      if (!changed) continue;
      m.attachments = Attachment.encodeAll(rebuilt);
      await box.put(key, m);
    }
  }

  /// Whether the chosen folder holds anything restorable.
  Future<bool> folderHasBackup() async {
    final saf = SafService.instance;
    if (!await saf.hasAccess()) return false;
    return await saf.hasFile(_folderData) ||
        await saf.hasFile(_legacyFolderZip);
  }

  /// Write now and report. Used on app background and by Settings.
  Future<BackupResult> flush() async {
    while (_writing) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    _writing = true;
    try {
      final r = await writeAutoBackup();
      await mirrorArchiveToFolder();
      return r;
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
  ///
  /// Written incrementally to disk with [ZipFileEncoder], which streams each
  /// file in as it goes. The previous version read every attachment into an
  /// in-memory `Archive` and then had `ZipEncoder` produce the whole zip as a
  /// second byte array — for 64 MB of video that was well over 128 MB live at
  /// once, on top of the engine, which is what got the process killed.
  Future<File> buildArchiveFile() async {
    final docs = await getApplicationDocumentsDirectory();
    final tmp = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final outPath = '${tmp.path}/recallday-backup-$stamp.zip';
    final json = buildSnapshotJson();
    final attachmentsRoot = '${docs.path}/attachments';

    // Off the main isolate: zipping tens of megabytes is CPU-bound work that
    // would otherwise freeze the UI long enough for Android to raise an ANR.
    await Isolate.run(() => _writeArchive(outPath, json, attachmentsRoot));
    return File(outPath);
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
    // withData:false is essential — asking the picker to load the bytes puts
    // the entire file in memory before we have even looked at it.
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: false,
    );
    if (picked == null || picked.files.isEmpty) {
      throw const BackupCancelled();
    }

    final f = picked.files.first;
    final path = f.path;
    if (path == null) {
      throw const FormatException('That file could not be read.');
    }

    if (f.name.toLowerCase().endsWith('.zip')) {
      return restoreFromArchivePath(path, merge: merge);
    }
    // A bare .json snapshot is small enough to read whole.
    return restoreFromJson(await File(path).readAsString(), merge: merge);
  }

  /// Restore a `.zip` export, streamed from disk.
  ///
  /// Entries are written out one at a time with `writeContent`, so a 50 MB
  /// video costs a buffer rather than 50 MB of heap. Decoding the same archive
  /// from a byte array meant holding the compressed file *and* every extracted
  /// entry in memory simultaneously.
  Future<RestoreSummary> restoreFromArchivePath(
    String zipPath, {
    bool merge = true,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    final input = InputFileStream(zipPath);
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBuffer(input);
    } catch (_) {
      await input.close();
      throw const FormatException('That file is not a readable backup.');
    }

    String? dataJson;
    var files = 0;

    try {
      for (final entry in archive.files) {
        if (!entry.isFile) continue;

        if (entry.name == _archiveData) {
          dataJson = utf8.decode(entry.content as List<int>);
          continue;
        }
        if (!entry.name.startsWith('$_archiveAttachments/')) continue;

        try {
          final rel = entry.name.substring(_archiveAttachments.length + 1);
          final dest = File('${docs.path}/$_archiveAttachments/$rel');
          await dest.parent.create(recursive: true);
          final out = OutputFileStream(dest.path);
          entry.writeContent(out);
          await out.close();
          files++;
        } catch (e) {
          debugPrint('[backup] could not restore ${entry.name}: $e');
        }
      }
    } finally {
      await input.close();
    }

    if (dataJson == null) {
      throw const FormatException(
        'That archive has no data.json — is it a RecallDay backup?',
      );
    }

    final summary = await restoreFromJson(dataJson, merge: merge);
    // Paths inside the backup belong to the install that wrote it.
    await _rehomeAllAttachments();
    return summary.withFiles(files);
  }

  /// Restore from a JSON snapshot.
  ///
  /// [merge] true keeps existing records and adds/overwrites by id; false
  /// wipes the boxes first. Ids are stable UUIDs, so merging a backup of the
  /// same database is idempotent.
  ///
  /// Attachment paths are corrected afterwards by [_rehomeAllAttachments]:
  /// the absolute paths inside a backup belong to the install that wrote it.
  Future<RestoreSummary> restoreFromJson(
    String jsonText, {
    bool merge = true,
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

/// Build the zip on a background isolate.
///
/// Top-level because an isolate entry point cannot close over `this`. Uses
/// [ZipFileEncoder], which appends each file to the archive on disk as it
/// reads it, so peak memory is one buffer rather than the whole archive.
Future<void> _writeArchive(
  String outPath,
  String dataJson,
  String attachmentsRoot,
) async {
  final encoder = ZipFileEncoder();
  encoder.create(outPath);
  try {
    final bytes = utf8.encode(dataJson);
    encoder.addArchiveFile(ArchiveFile('data.json', bytes.length, bytes));

    final root = Directory(attachmentsRoot);
    if (root.existsSync()) {
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File) continue;
        final rel = entity.path.substring(root.path.length + 1);
        encoder.addFile(entity, 'attachments/$rel');
      }
    }
  } finally {
    encoder.close();
  }
}
