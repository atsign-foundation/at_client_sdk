import 'package:at_client/at_client.dart';
import 'package:flutter/material.dart';

import '../models/todo.dart';

class TodoFormResult {
  final String title;
  final String description;
  final DateTime dueDate;
  final Set<Atsign> sharedWith;

  TodoFormResult({
    required this.title,
    required this.description,
    required this.dueDate,
    required this.sharedWith,
  });
}

/// Dialog form used for both creating and editing a todo. Returns null on
/// cancel or a [TodoFormResult] on submit.
class TodoFormDialog extends StatefulWidget {
  final CItem<Todo>? existing;

  const TodoFormDialog({super.key, this.existing});

  static Future<TodoFormResult?> show(
    BuildContext context, {
    CItem<Todo>? existing,
  }) {
    return showDialog<TodoFormResult>(
      context: context,
      builder: (_) => TodoFormDialog(existing: existing),
    );
  }

  @override
  State<TodoFormDialog> createState() => _TodoFormDialogState();
}

class _TodoFormDialogState extends State<TodoFormDialog> {
  late final TextEditingController _title;
  late final TextEditingController _desc;
  late final TextEditingController _shared;
  late DateTime _dueDate;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.obj.title ?? '');
    _desc = TextEditingController(text: e?.obj.description ?? '');
    _shared = TextEditingController(
      text: (e?.sharedWith ?? <Atsign>{}).join(', '),
    );
    _dueDate = e?.obj.dueDate ?? DateTime.now().add(const Duration(days: 7));
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _shared.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueDate),
    );
    setState(() {
      _dueDate = DateTime(
        picked.year,
        picked.month,
        picked.day,
        time?.hour ?? 9,
        time?.minute ?? 0,
      );
    });
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Title is required')));
      return;
    }
    final sharedText = _shared.text.trim();
    final sharedWith = sharedText.isEmpty
        ? <Atsign>{}
        : sharedText
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .map((s) => s.toAtsign())
              .toSet();
    Navigator.of(context).pop(
      TodoFormResult(
        title: title,
        description: _desc.text.trim(),
        dueDate: _dueDate,
        sharedWith: sharedWith,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formatted = _dueDate
        .toIso8601String()
        .substring(0, 16)
        .replaceFirst('T', ' ');
    return AlertDialog(
      title: Text(widget.existing == null ? 'New todo' : 'Edit todo'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Title'),
                autofocus: true,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _desc,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 3,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _shared,
                decoration: const InputDecoration(
                  labelText: 'Share with (comma-separated @signs)',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Due: '),
                  Expanded(child: Text(formatted)),
                  TextButton(onPressed: _pickDate, child: const Text('Pick…')),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

/// Simple single-field dialog for "add recipients". Returns null on cancel
/// or a set of atSigns to add.
Future<Set<Atsign>?> showShareDialog(BuildContext context) async {
  final controller = TextEditingController();
  return showDialog<Set<Atsign>>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Add recipients'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Comma-separated @signs'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final parts = controller.text
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .map((s) => s.toAtsign())
                .toSet();
            Navigator.of(ctx).pop(parts);
          },
          child: const Text('Share'),
        ),
      ],
    ),
  );
}

/// Picks a future [DateTime] for scheduling.
Future<DateTime?> showScheduleDialog(BuildContext context) async {
  final now = DateTime.now();
  final date = await showDatePicker(
    context: context,
    initialDate: now,
    firstDate: now,
    lastDate: DateTime(now.year + 2),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 5))),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}
