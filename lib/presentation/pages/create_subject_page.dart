import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/subject_palette.dart';
import '../../domain/entities/subject.dart';
import '../providers/providers.dart';

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
      // Pre-fill from repository. Read once at init; the subjects watcher
      // would otherwise rebuild the form on every Hive change.
      final repo = ref.read(subjectRepositoryProvider);
      final s = repo.byId(widget.editId!);
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
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Name is required')));
      return;
    }
    setState(() => _busy = true);
    final s = Subject(
      id: _existing?.id ?? const Uuid().v4(),
      name: _name.text.trim(),
      colorValue: SubjectPalette.colors[_colorIdx].toARGB32(),
      iconKey: _iconKey,
      createdAt: _existing?.createdAt ?? DateTime.now(),
      archived: _existing?.archived ?? false,
    );
    await ref.read(topicCommandsProvider).saveSubject(s);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit subject' : 'New subject')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: 'Name', hintText: 'Algorithms, DBMS…'),
              maxLength: 40,
            ),
            const SizedBox(height: 12),
            const Text('Color', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (int i = 0; i < SubjectPalette.colors.length; i++)
                GestureDetector(
                  onTap: () => setState(() => _colorIdx = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: SubjectPalette.colors[i],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: i == _colorIdx
                            ? Colors.white
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 18),
            const Text('Icon', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final k in SubjectPalette.iconKeys)
                GestureDetector(
                  onTap: () => setState(() => _iconKey = k),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainer,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: k == _iconKey ? cs.primary : cs.outline,
                          width: k == _iconKey ? 1.6 : 0.6),
                    ),
                    child: Icon(SubjectPalette.iconFor(k),
                        color: k == _iconKey ? cs.primary : cs.onSurface),
                  ),
                ),
            ]),
            const SizedBox(height: 32),
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
