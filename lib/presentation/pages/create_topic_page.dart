import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/subject_palette.dart';
import '../../core/theme/app_tokens.dart';
import '../../domain/entities/attachment.dart';
import '../../domain/entities/topic.dart';
import '../providers/providers.dart';
import '../widgets/app_card.dart';
import '../widgets/attachment_editor.dart';
import '../widgets/form_section.dart';

/// Combined Create + Edit page. If [editId] is non-null, loads the topic and
/// updates only the user-facing fields. SR state (ease, repetitions,
/// ladderIndex, nextDueAt) is preserved on edit, except that a reminder-time
/// change rolls nextDueAt forward to the new hour/minute on the same day.
class CreateTopicPage extends ConsumerStatefulWidget {
  final String? initialSubjectId;
  final String? editId;

  const CreateTopicPage({super.key, this.initialSubjectId, this.editId});

  @override
  ConsumerState<CreateTopicPage> createState() => _CreateTopicPageState();
}

class _CreateTopicPageState extends ConsumerState<CreateTopicPage> {
  final _title = TextEditingController();
  final _notes = TextEditingController();

  String? _subjectId;
  // No longer editable in the form, but still round-tripped so editing a
  // topic created by an older build doesn't silently reset these fields.
  Difficulty _difficulty = Difficulty.medium;
  Priority _priority = Priority.medium;
  int _minutes = 15;
  TimeOfDay _reminder = const TimeOfDay(hour: 19, minute: 0);
  bool _persistent = true;
  bool _busy = false;
  Topic? _existing;
  List<Attachment> _attachments = const [];

  /// Fixed up front so attachments can be copied into this topic's folder
  /// while the form is still being filled in.
  late final String _topicId =
      widget.editId ?? const Uuid().v4();

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
        _notes.text = t.notes ?? '';
        _subjectId = t.subjectId;
        _difficulty = t.difficulty;
        _priority = t.priority;
        _minutes = t.estimatedMinutes;
        _reminder = TimeOfDay(hour: t.reminderHour, minute: t.reminderMinute);
        _persistent = t.persistentReminders;
        _attachments = t.attachments;
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
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
    final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();

    if (_isEdit) {
      await cmd.updateTopic(
        topicId: _existing!.id,
        subjectId: _subjectId!,
        title: _title.text.trim(),
        notes: notes,
        priority: _priority,
        difficulty: _difficulty,
        estimatedMinutes: _minutes,
        reminderHour: _reminder.hour,
        reminderMinute: _reminder.minute,
        persistentReminders: _persistent,
        attachments: _attachments,
      );
    } else {
      await cmd.createTopic(
        subjectId: _subjectId!,
        title: _title.text.trim(),
        notes: notes,
        difficulty: _difficulty,
        priority: _priority,
        estimatedMinutes: _minutes,
        reminderHour: _reminder.hour,
        reminderMinute: _reminder.minute,
        persistentReminders: _persistent,
        attachments: _attachments,
        presetId: _topicId,
      );
    }
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
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
              child: TextField(
                controller: _title,
                autofocus: !_isEdit,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Deadlocks, Krebs cycle, past tense…',
                ),
              ),
            ),

            FormSection(
              label: 'Subject',
              child: subjects.isEmpty
                  ? _NoSubjectsNotice(
                      onCreate: () => context.push('/create/subject'),
                    )
                  // A dropdown rather than chips: it stays one row tall however
                  // many subjects exist, and `_subjectId` is pre-filled when
                  // you arrive from inside a subject, so it opens already set.
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

            FormSection(
              label: 'Notes',
              hint: 'Optional · Markdown supported',
              child: TextField(
                controller: _notes,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'What do you need to remember?',
                  alignLabelWithHint: true,
                ),
              ),
            ),

            // Reminder time and the persistent-reminder switch are the two
            // settings that actually change behaviour, so they sit inline
            // rather than behind a disclosure. Difficulty, priority and
            // estimated-time were removed entirely: the scheduling engine
            // never read difficulty or priority, and the minutes figure was
            // only ever echoed back on the card.
            FormSection(
              label: 'Reminder time',
              child: AppCard(
                onTap: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: _reminder,
                  );
                  if (t != null) setState(() => _reminder = t);
                },
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.lg,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 20,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        _reminder.format(context),
                        style: tt.bodyLarge,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ),
            ),

            FormSection(
              label: 'Reminders',
              child: AppCard(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.sm,
                  AppSpacing.sm,
                ),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _persistent,
                  onChanged: (v) => setState(() => _persistent = v),
                  title: Text('Keep reminding me', style: tt.bodyMedium),
                  subtitle: Text(
                    'Re-send daily until the topic is reviewed.',
                    style: tt.labelSmall,
                  ),
                ),
              ),
            ),

            FormSection(
              label: 'Attachments',
              hint: 'Optional · files, images, videos or links',
              child: AttachmentEditor(
                topicId: _topicId,
                attachments: _attachments,
                onChanged: (v) => setState(() => _attachments = v),
              ),
            ),

            const SizedBox(height: AppSpacing.sm),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_isEdit ? 'Save changes' : 'Create topic'),
            ),
            if (!_isEdit) ...[
              const SizedBox(height: AppSpacing.md),
              Center(
                child: Text(
                  'First reminder today at ${_reminder.format(context)}',
                  style: tt.labelSmall,
                ),
              ),
            ],
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
