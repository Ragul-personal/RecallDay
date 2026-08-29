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
  Difficulty _difficulty = Difficulty.medium;
  Priority _priority = Priority.medium;
  int _minutes = 15;
  TimeOfDay _reminder = const TimeOfDay(hour: 19, minute: 0);
  bool _persistent = true;
  bool _busy = false;
  bool _showMore = false;
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
        _notes.text = t.notes ?? '';
        _subjectId = t.subjectId;
        _difficulty = t.difficulty;
        _priority = t.priority;
        _minutes = t.estimatedMinutes;
        _reminder = TimeOfDay(hour: t.reminderHour, minute: t.reminderMinute);
        _persistent = t.persistentReminders;
        // An editing user has already made these choices; show them rather
        // than hiding them behind a disclosure.
        _showMore = true;
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
                  : Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final s in subjects)
                          _SubjectChip(
                            name: s.name,
                            icon: SubjectPalette.iconFor(s.iconKey),
                            color: SubjectPalette.readable(
                              s.color,
                              theme.brightness,
                            ),
                            selected: s.id == _subjectId,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _subjectId = s.id);
                            },
                          ),
                      ],
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

            // Everything below has a sensible default, so it's collapsed by
            // default — creating a topic should be title, subject, done.
            if (!_showMore)
              Center(
                child: TextButton.icon(
                  onPressed: () => setState(() => _showMore = true),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('More options'),
                ),
              )
            else ...[
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
                label: 'Difficulty',
                child: SegmentedButton<Difficulty>(
                  segments: const [
                    ButtonSegment(value: Difficulty.easy, label: Text('Easy')),
                    ButtonSegment(
                      value: Difficulty.medium,
                      label: Text('Medium'),
                    ),
                    ButtonSegment(value: Difficulty.hard, label: Text('Hard')),
                  ],
                  selected: {_difficulty},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) {
                    HapticFeedback.selectionClick();
                    setState(() => _difficulty = s.first);
                  },
                ),
              ),

              FormSection(
                label: 'Priority',
                child: SegmentedButton<Priority>(
                  segments: const [
                    ButtonSegment(value: Priority.low, label: Text('Low')),
                    ButtonSegment(value: Priority.medium, label: Text('Normal')),
                    ButtonSegment(value: Priority.high, label: Text('High')),
                  ],
                  selected: {_priority},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) {
                    HapticFeedback.selectionClick();
                    setState(() => _priority = s.first);
                  },
                ),
              ),

              FormSection(
                label: 'Estimated time',
                child: Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: _minutes.toDouble(),
                        min: 5,
                        max: 120,
                        divisions: 23,
                        label: '$_minutes min',
                        onChanged: (v) => setState(() => _minutes = v.round()),
                      ),
                    ),
                    SizedBox(
                      width: 62,
                      child: Text(
                        '$_minutes min',
                        textAlign: TextAlign.end,
                        style: tt.labelMedium,
                      ),
                    ),
                  ],
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
            ],

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

/// Subject picker as chips rather than a dropdown — with a handful of subjects
/// they're all visible at once, and each carries its own colour and icon so the
/// choice is recognisable rather than textual.
class _SubjectChip extends StatelessWidget {
  final String name;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _SubjectChip({
    required this.name,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.curve,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md + 2,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.14)
              : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? color : cs.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              name,
              style: tt.labelMedium?.copyWith(
                color: selected ? color : cs.onSurface,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
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
