import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

/// Where a backup being imported lives.
enum ImportSource {
  /// A single exported backup file.
  file,

  /// A folder holding an extracted backup — data plus its attachment files.
  folder,
}

/// Ask which one the user has.
///
/// The distinction is unavoidable rather than fussy: picking a file grants
/// access to that file alone, so an extracted backup's attachments can only be
/// reached by pointing at the folder that contains them.
Future<ImportSource?> chooseImportSource(BuildContext context) {
  return showModalBottomSheet<ImportSource>(
    context: context,
    builder: (ctx) {
      final tt = Theme.of(ctx).textTheme;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                AppSpacing.sm,
                AppSpacing.gutter,
                AppSpacing.md,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Where is your backup?', style: tt.titleMedium),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: const Text('A backup file'),
              subtitle: const Text(
                'The file you exported, still packed up',
              ),
              onTap: () => Navigator.pop(ctx, ImportSource.file),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('A folder'),
              subtitle: const Text(
                'A backup you unpacked, or another RecallDay folder — brings '
                'its attachments across too',
              ),
              onTap: () => Navigator.pop(ctx, ImportSource.folder),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      );
    },
  );
}
