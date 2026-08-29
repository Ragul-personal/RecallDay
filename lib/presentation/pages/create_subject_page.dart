import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/subject_palette.dart';
import '../../core/theme/app_tokens.dart';
import '../../domain/entities/subject.dart';
import '../providers/providers.dart';
import '../widgets/app_card.dart';
import '../widgets/form_section.dart';

/// Combined Create + Edit page. If [editId] is non-null, loads the existing
/// subject and overwrites it on save (preserving createdAt).
class CreateSubjectPage extends ConsumerStatefulWidget {
  final String? editId;
  const CreateSubjectPage({super.key, this.editId});

  @override
  ConsumerState<CreateSubjectPage> createState() => _CreateSubjectPageState();
}

class _CreateSubjectPageState extends ConsumerState<CreateSubjectPage> {
  final _name = TextEditingController();
  int _colorIdx = 0;
  String _iconKey = SubjectPalette.iconKeys.first;
  bool _busy = false;
  Subject? _existing;

  bool get _isEdit => widget.editId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final s = ref.read(subjectRepositoryProvider).byId(widget.editId!);
      if (s != null) {
        _existing = s;
        _name.text = s.name;
        final i = SubjectPalette.colors
            .indexWhere((c) => c.toARGB32() == s.colorValue);
        _colorIdx = i >= 0 ? i : 0;
        _iconKey = SubjectPalette.iconKeys.contains(s.iconKey)
            ? s.iconKey
            : SubjectPalette.iconKeys.first;
      }
    }
    // Live preview needs to rebuild as the name is typed.
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Give the subject a name')));
      return;
    }
    setState(() => _busy = true);
    HapticFeedback.lightImpact();
    await ref.read(topicCommandsProvider).saveSubject(
          Subject(
            id: _existing?.id ?? const Uuid().v4(),
            name: _name.text.trim(),
            colorValue: SubjectPalette.colors[_colorIdx].toARGB32(),
            iconKey: _iconKey,
            createdAt: _existing?.createdAt ?? DateTime.now(),
            archived: _existing?.archived ?? false,
          ),
        );
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tt = theme.textTheme;
    final color = SubjectPalette.colors[_colorIdx];
    final accent = SubjectPalette.readable(color, theme.brightness);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit subject' : 'New subject'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.sm,
            AppSpacing.gutter,
            AppSpacing.xxxl,
          ),
          children: [
            // Live preview of the row the user is building — colour and icon
            // choices are abstract until you can see the result.
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: AppMotion.base,
                    curve: Curves.easeOutCubic,
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(
                      SubjectPalette.iconFor(_iconKey),
                      color: accent,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md + 2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _name.text.trim().isEmpty
                              ? 'Subject name'
                              : _name.text.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.titleSmall?.copyWith(
                            color: _name.text.trim().isEmpty
                                ? theme.colorScheme.onSurfaceVariant
                                : null,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text('No topics yet', style: tt.labelSmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),

            FormSection(
              label: 'Name',
              child: TextField(
                controller: _name,
                autofocus: !_isEdit,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                maxLength: 40,
                decoration: const InputDecoration(
                  hintText: 'Algorithms, Anatomy, Spanish…',
                  counterText: '',
                ),
              ),
            ),

            FormSection(
              label: 'Colour',
              child: Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  for (var i = 0; i < SubjectPalette.colors.length; i++)
                    _Swatch(
                      color: SubjectPalette.readable(
                        SubjectPalette.colors[i],
                        theme.brightness,
                      ),
                      selected: i == _colorIdx,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _colorIdx = i);
                      },
                    ),
                ],
              ),
            ),

            FormSection(
              label: 'Icon',
              child: Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  for (final k in SubjectPalette.iconKeys)
                    _IconChoice(
                      icon: SubjectPalette.iconFor(k),
                      selected: k == _iconKey,
                      accent: accent,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _iconKey = k);
                      },
                    ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_isEdit ? 'Save changes' : 'Create subject'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: Curves.easeOutCubic,
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: selected
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 19)
            : null,
      ),
    );
  }
}

class _IconChoice extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _IconChoice({
    required this.icon,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: Curves.easeOutCubic,
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.14)
              : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? accent : Colors.transparent,
            width: 1.6,
          ),
        ),
        child: Icon(
          icon,
          color: selected ? accent : cs.onSurfaceVariant,
          size: 22,
        ),
      ),
    );
  }
}
