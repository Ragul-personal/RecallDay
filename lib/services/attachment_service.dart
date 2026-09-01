import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../domain/entities/attachment.dart';

/// Picks files and copies them into app-owned storage.
///
/// The copy matters: a path returned by the system picker is a temporary or
/// borrowed URI that can be revoked, moved or cleaned up at any time, so
/// storing it directly would leave attachments that silently stop opening.
/// Everything lands under `<app documents>/attachments/<subtopicId>/`, which the
/// app owns outright and which Android Auto Backup already covers.
class AttachmentService {
  AttachmentService._();
  static final AttachmentService instance = AttachmentService._();

  static const _uuid = Uuid();

  Future<Directory> _dirFor(String subtopicId) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/attachments/$subtopicId');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Open the system picker and copy whatever is chosen into app storage.
  ///
  /// [subtopicId] may be a not-yet-saved id — the directory is created eagerly
  /// so attachments can be added *while* composing a new subtopic, before it
  /// exists in Hive.
  Future<List<Attachment>> pickAndImport({
    required String subtopicId,
    FileType type = FileType.any,
  }) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: type,
        // We copy the bytes ourselves, so ask the plugin not to also cache
        // them — on large videos that doubles the work and the disk use.
        withData: false,
      );
      if (result == null) return const [];

      final out = <Attachment>[];
      for (final f in result.files) {
        final src = f.path;
        if (src == null) continue;
        final imported = await importPath(
          subtopicId: subtopicId,
          sourcePath: src,
          displayName: f.name,
        );
        if (imported != null) out.add(imported);
      }
      return out;
    } catch (e, st) {
      debugPrint('[attachments] pick failed: $e\n$st');
      return const [];
    }
  }

  /// Copy one file into the subtopic's folder.
  Future<Attachment?> importPath({
    required String subtopicId,
    required String sourcePath,
    required String displayName,
  }) async {
    try {
      final dir = await _dirFor(subtopicId);
      final ext =
          displayName.contains('.') ? '.${displayName.split('.').last}' : '';
      final id = _uuid.v4();
      final dest = File('${dir.path}/$id$ext');
      await File(sourcePath).copy(dest.path);

      return Attachment(
        id: id,
        kind: Attachment.kindForPath(displayName),
        target: dest.path,
        name: displayName,
        addedAt: DateTime.now(),
      );
    } catch (e, st) {
      debugPrint('[attachments] import failed: $e\n$st');
      return null;
    }
  }

  /// Build a link attachment from a URL the user typed.
  Attachment linkFrom(String rawUrl, {String? label}) {
    var url = rawUrl.trim();
    // People paste "youtube.com/..." without a scheme; Uri.parse then treats
    // the host as a path and nothing resolves.
    if (!url.startsWith(RegExp(r'https?://'))) {
      url = 'https://$url';
    }
    final kind = Attachment.kindForUrl(url);
    return Attachment(
      id: _uuid.v4(),
      kind: kind,
      target: url,
      name: label?.trim().isNotEmpty == true
          ? label!.trim()
          : kind == AttachmentKind.youtube
              ? 'YouTube video'
              : Uri.tryParse(url)?.host ?? url,
      addedAt: DateTime.now(),
    );
  }

  /// Delete the backing file, if this attachment has one.
  Future<void> delete(Attachment a) async {
    if (!a.isLocalFile) return;
    try {
      final f = File(a.target);
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('[attachments] delete failed: $e');
    }
  }

  /// Remove every file for a subtopic. Called when the record itself is
  /// deleted so videos don't linger on disk forever.
  Future<void> deleteAllFor(String subtopicId) async {
    try {
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory('${base.path}/attachments/$subtopicId');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('[attachments] deleteAllFor failed: $e');
    }
  }

  /// Move files staged under a temporary id into the real subtopic's folder.
  ///
  /// A new subtopic gets its id up front, so in practice this is a no-op — it
  /// exists so that the create flow can't strand files if that ever changes.
  Future<List<Attachment>> reparent({
    required String fromSubtopicId,
    required String toSubtopicId,
    required List<Attachment> attachments,
  }) async {
    if (fromSubtopicId == toSubtopicId) return attachments;
    final out = <Attachment>[];
    for (final a in attachments) {
      if (!a.isLocalFile) {
        out.add(a);
        continue;
      }
      try {
        final dir = await _dirFor(toSubtopicId);
        final name = a.target.split('/').last;
        final dest = await File(a.target).rename('${dir.path}/$name');
        out.add(Attachment(
          id: a.id,
          kind: a.kind,
          target: dest.path,
          name: a.name,
          addedAt: a.addedAt,
        ));
      } catch (e) {
        debugPrint('[attachments] reparent failed: $e');
        out.add(a);
      }
    }
    await deleteAllFor(fromSubtopicId);
    return out;
  }
}
