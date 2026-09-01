import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_tokens.dart';
import '../../domain/entities/attachment.dart';
import '../../services/attachment_service.dart';
import '../pages/media_viewer_page.dart';
import 'app_card.dart';

/// Add / view / remove attachments on a subtopic.
///
/// Used unchanged in two places — the create form and the subtopic detail
/// page — so files can be attached while composing one *and* at any point
/// afterwards. It owns no state: the caller holds the list and persists it.
class AttachmentEditor extends StatefulWidget {
  final String subtopicId;
  final List<Attachment> attachments;
  final ValueChanged<List<Attachment>> onChanged;

  const AttachmentEditor({
    super.key,
    required this.subtopicId,
    required this.attachments,
    required this.onChanged,
  });

  @override
  State<AttachmentEditor> createState() => _AttachmentEditorState();
}

class _AttachmentEditorState extends State<AttachmentEditor> {
  bool _busy = false;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pick(FileType type) async {
    setState(() => _busy = true);
    final added = await AttachmentService.instance.pickAndImport(
      subtopicId: widget.subtopicId,
      type: type,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (added.isEmpty) return;
    HapticFeedback.lightImpact();
    widget.onChanged([...widget.attachments, ...added]);
  }

  Future<void> _addLink() async {
    final result = await showDialog<Attachment>(
      context: context,
      builder: (_) => const _LinkDialog(),
    );
    if (result == null || !mounted) return;
    HapticFeedback.lightImpact();
    widget.onChanged([...widget.attachments, result]);
  }

  Future<void> _open(Attachment a) async {
    final err = await openAttachment(context, a);
    if (err != null) _toast(err);
  }

  Future<void> _remove(Attachment a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove attachment?'),
        content: Text(
          a.isLocalFile
              ? '“${a.name}” will be deleted from this subtopic.'
              : '“${a.name}” will be removed from this subtopic.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AttachmentService.instance.delete(a);
    widget.onChanged(
      widget.attachments.where((x) => x.id != a.id).toList(),
    );
  }

  Future<void> _showAddMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Image'),
              subtitle: const Text('Opens in the app'),
              onTap: () => Navigator.pop(ctx, 'image'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Video'),
              subtitle: const Text('Plays in the app'),
              onTap: () => Navigator.pop(ctx, 'video'),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: const Text('File'),
              subtitle: const Text('PDF, slides, notes — opens in another app'),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('Link or YouTube'),
              subtitle: const Text('YouTube plays in the app; other links open '
                  'in your browser'),
              onTap: () => Navigator.pop(ctx, 'link'),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'image':
        await _pick(FileType.image);
      case 'video':
        await _pick(FileType.video);
      case 'file':
        await _pick(FileType.any);
      case 'link':
        await _addLink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final items = widget.attachments;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final a in items) ...[
          _AttachmentRow(
            attachment: a,
            onOpen: () => _open(a),
            onRemove: () => _remove(a),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              'Attach notes, slides, images, videos or links to study from.',
              style: tt.labelSmall,
            ),
          ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
          ),
          onPressed: _busy ? null : _showAddMenu,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_rounded, size: 20),
          label: Text(_busy ? 'Adding…' : 'Add attachment'),
        ),
      ],
    );
  }
}

class _AttachmentRow extends StatelessWidget {
  final Attachment attachment;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  const _AttachmentRow({
    required this.attachment,
    required this.onOpen,
    required this.onRemove,
  });

  static IconData _icon(AttachmentKind k) => switch (k) {
        AttachmentKind.image => Icons.image_rounded,
        AttachmentKind.video => Icons.play_circle_rounded,
        AttachmentKind.file => Icons.description_rounded,
        AttachmentKind.youtube => Icons.smart_display_rounded,
        AttachmentKind.link => Icons.link_rounded,
      };

  static String _label(AttachmentKind k) => switch (k) {
        AttachmentKind.image => 'Image',
        AttachmentKind.video => 'Video',
        AttachmentKind.file => 'File',
        AttachmentKind.youtube => 'YouTube',
        AttachmentKind.link => 'Link',
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return AppCard(
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(
              _icon(attachment.kind),
              size: 19,
              color: cs.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodyMedium,
                ),
                Text(_label(attachment.kind), style: tt.labelSmall),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// Prompt for a URL, classifying YouTube links as they're typed.
class _LinkDialog extends StatefulWidget {
  const _LinkDialog();

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  final _url = TextEditingController();
  final _label = TextEditingController();

  @override
  void initState() {
    super.initState();
    _url.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _url.dispose();
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final text = _url.text.trim();
    final isYouTube = text.isNotEmpty &&
        Attachment.youTubeId(
              text.startsWith(RegExp(r'https?://')) ? text : 'https://$text',
            ) !=
            null;

    return AlertDialog(
      title: const Text('Add a link'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _url,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: 'https://…',
              labelText: 'URL',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _label,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Optional',
              labelText: 'Name',
            ),
          ),
          if (text.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Icon(
                  isYouTube
                      ? Icons.smart_display_rounded
                      : Icons.open_in_browser_rounded,
                  size: 15,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isYouTube
                        ? 'Plays inside RecallDay'
                        : 'Opens in your browser',
                    style: tt.labelSmall,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: text.isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    AttachmentService.instance
                        .linkFrom(text, label: _label.text),
                  ),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
