import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/topic.dart';
import '../providers/providers.dart';

/// Combined Create + Edit page. If [editId] is non-null, loads the topic and
/// updates only the user-facing fields (title/notes/difficulty/priority/
/// minutes/reminder time/persistent flag). SR state (ease, repetitions,
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
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Title is required')));
      return;
    }
    if (_subjectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Pick a subject (or create one first)')));
      return;
    }
    setState(() => _busy = true);
    final cmd = ref.read(topicCommandsProvider);
    if (_isEdit) {
      await cmd.updateTopic(
        topicId: _existing!.id,
        title: _title.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        priority: _priority,
        difficulty: _difficulty,
        estimatedMinutes: _minutes,
        reminderHour: _reminder.hour,
        reminderMinute: _reminder.minute,
        persistentReminders: _persistent,
        subjectId: _subjectId!,
      );
    } else {
      await cmd.createTopic(
        subjectId: _subjectId!,
        title: _title.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
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
    final subjects = ref.watch(subjectsStreamProvider).valueOrNull ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit topic' : 'New topic')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                  labelText: 'Title', hintText: 'Deadlocks'),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _subjectId,
              decoration: const InputDecoration(labelText: 'Subject'),
              items: [
                for (final s in subjects)
                  DropdownMenuItem(value: s.id, child: Text(s.name)),
              ],
              onChanged: (v) => setState(() => _subjectId = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Notes (markdown supported)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 18),
            const Text('Difficulty',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SegmentedButton<Difficulty>(
              segments: const [
                ButtonSegment(value: Difficulty.easy, label: Text('Easy')),
                ButtonSegment(value: Difficulty.medium, label: Text('Medium')),
                ButtonSegment(value: Difficulty.hard, label: Text('Hard')),
              ],
              selected: {_difficulty},
              onSelectionChanged: (s) => setState(() => _difficulty = s.first),
            ),
            const SizedBox(height: 14),
            const Text('Priority',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SegmentedButton<Priority>(
              segments: const [
                ButtonSegment(value: Priority.low, label: Text('Low')),
                ButtonSegment(value: Priority.medium, label: Text('Medium')),
                ButtonSegment(value: Priority.high, label: Text('High')),
              ],
              selected: {_priority},
              onSelectionChanged: (s) => setState(() => _priority = s.first),
            ),
            const SizedBox(height: 14),
            Row(children: [
              const Text('Estimated time',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('$_minutes min',
                  style: const TextStyle(color: AppTheme.textMuted)),
            ]),
            Slider(
              value: _minutes.toDouble(),
              min: 5, max: 120, divisions: 23,
              label: '$_minutes min',
              onChanged: (v) => setState(() => _minutes = v.round()),
            ),
            const SizedBox(height: 6),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Reminder time'),
              subtitle: Text(_reminder.format(context),
                  style: const TextStyle(color: AppTheme.textMuted)),
              trailing: const Icon(Icons.access_time),
              onTap: () async {
                final t = await showTimePicker(
                    context: context, initialTime: _reminder);
                if (t != null) setState(() => _reminder = t);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Persistent reminders'),
              subtitle: const Text(
                'Re-send the reminder daily until you mark it reviewed.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
              ),
              value: _persistent,
              onChanged: (v) => setState(() => _persistent = v),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_isEdit ? 'Save changes' : 'Create topic'),
            ),
            const SizedBox(height: 8),
            if (!_isEdit)
              Center(
                child: Text(
                  'First reminder: today at ${_reminder.format(context)}',
                  style: const TextStyle(
                      color: AppTheme.textMuted, fontSize: 12.5),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
