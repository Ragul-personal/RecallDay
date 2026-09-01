import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/subject_palette.dart';
import '../../core/theme/app_tokens.dart';
import '../../domain/entities/topic.dart';
import '../providers/providers.dart';
import '../widgets/app_card.dart';
import '../widgets/form_section.dart';

/// Combined Create + Edit page for a topic.
///
/// Deliberately short. A topic is a heading — a name and the subject it lives
/// in — so there is nothing to schedule and nothing to attach here; all of
/// that belongs to the subtopics underneath, which is what keeps this form
/// from turning into a second copy of the subtopic one.
///
/// Moving a topic to another subject moves its subtopics with it; see
/// `TopicCommands.updateTopic`.
class CreateTopicPage extends ConsumerStatefulWidget {
  final String? initialSubjectId;
  final String? editId;

  const CreateTopicPage({super.key, this.initialSubjectId, this.editId});

  @override
  ConsumerState<CreateTopicPage> createState() => _CreateTopicPageState();
}

class _CreateTopicPageState extends ConsumerState<CreateTopicPage> {
  final _title = TextEditingController();

  String? _subjectId;
  bool _busy = false;
  Topic? _existing;

  bool get _isEdit => widget.editId != null;

  @override
  void initState() {
    super.initState();
    _subjectId = widget.initialSubjectId;
    if (_isEdit) {
      final t = ref.read(topicRepositoryProvider).byId(widget.editId!);
      if (t != null) {
        _existing = t;
        _title.text = t.title;
        _subjectId = t.subjectId;
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      _toast('Give the topic a title');
      return;
    }
    if (_subjectId == null) {
      _toast('Pick a subject first');
      return;
    }
    setState(() => _busy = true);
    HapticFeedback.lightImpact();

    final cmd = ref.read(topicCommandsProvider);
    String id;
    if (_isEdit) {
      id = _existing!.id;
      await cmd.updateTopic(
        topicId: id,
        subjectId: _subjectId!,
        title: _title.text.trim(),
      );
    } else {
      final created = await cmd.createTopic(
        subjectId: _subjectId!,
        title: _title.text.trim(),
      );
      id = created.id;
    }
    // Popped with the id so a caller that sent the user here mid-form — the
    // subtopic page, when the subject had no topics yet — can select the topic
    // that was just made instead of asking for it a second time.
    if (mounted) context.pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tt = theme.textTheme;
    final subjects = ref.watch(subjectsStreamProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit topic' : 'New topic')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.lg,
            AppSpacing.gutter,
            AppSpacing.xxxl,
          ),
          children: [
            FormSection(
              label: 'Topic',
              hint: 'A chapter, module or theme',
              child: TextField(
                controller: _title,
                autofocus: !_isEdit,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Deadlocks, Cell biology, Verb tenses…',
                ),
              ),
            ),

            FormSection(
              label: 'Subject',
              child: subjects.isEmpty
                  ? _NoSubjectsNotice(
                      onCreate: () => context.push('/create/subject'),
                    )
                  : DropdownButtonFormField<String>(
                      initialValue: _subjectId,
                      isExpanded: true,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      decoration: const InputDecoration(
                        hintText: 'Choose a subject',
                      ),
                      icon: const Icon(Icons.expand_more_rounded),
                      items: [
                        for (final s in subjects)
                          DropdownMenuItem(
                            value: s.id,
                            child: Row(
                              children: [
                                Icon(
                                  SubjectPalette.iconFor(s.iconKey),
                                  size: 18,
                                  color: SubjectPalette.readable(
                                    s.color,
                                    theme.brightness,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Flexible(
                                  child: Text(
                                    s.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: tt.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        HapticFeedback.selectionClick();
                        setState(() => _subjectId = v);
                      },
                    ),
            ),

            if (_isEdit) ...[
              AppCard(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        'Changing the subject moves every subtopic in this '
                        'topic with it.',
                        style: tt.labelSmall,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],

            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_isEdit ? 'Save changes' : 'Create topic'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoSubjectsNotice extends StatelessWidget {
  final VoidCallback onCreate;
  const _NoSubjectsNotice({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'You need a subject before adding a topic.',
              style: tt.bodySmall,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            ),
            onPressed: onCreate,
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
