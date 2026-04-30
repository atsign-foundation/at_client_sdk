import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:flutter/material.dart';

import '../models/todo.dart';

import '../services/todos_service.dart';
import '../widgets/atsign_text.dart';
import '../widgets/todo_form.dart';

class TodoDetailScreen extends StatefulWidget {
  final CItem<Todo> todo;
  final TodosService service;

  const TodoDetailScreen({
    super.key,
    required this.todo,
    required this.service,
  });

  @override
  State<TodoDetailScreen> createState() => _TodoDetailScreenState();
}

class _TodoDetailScreenState extends State<TodoDetailScreen> {
  final _noteCtrl = TextEditingController();
  bool _busy = false;
  // Live view of the currently-displayed todo. Seeded from the initial
  // widget.todo, then updated by [_liveSub] on each emission of
  // `service.watchSingle(id, owner)`. If the underlying item is
  // deleted remotely, we pop back to the home screen.
  late CItem<Todo> _currentTodo;
  StreamSubscription<CItem<Todo>?>? _liveSub;

  @override
  void initState() {
    super.initState();
    _currentTodo = widget.todo;
    _liveSub = widget.service
        .watchSingle(widget.todo.id, widget.todo.owner)
        .listen((t) {
          if (!mounted) return;
          if (t == null) {
            // Underlying todo was deleted — back out.
            Navigator.of(context).pop();
            return;
          }
          setState(() => _currentTodo = t);
        });
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _withBusy(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await fn();
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _edit() async {
    final r = await TodoFormDialog.show(context, existing: _currentTodo);
    if (r == null) return;
    await _withBusy(
      () => widget.service.updateTodo(
        _currentTodo,
        title: r.title,
        description: r.description,
        sharedWith: r.sharedWith,
      ),
    );
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete todo?'),
        content: Text('Delete "${_currentTodo.obj.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _withBusy(() async {
      await widget.service.deleteTodo(_currentTodo);
      if (!mounted) return;
      Navigator.of(context).pop();
    });
  }

  Future<void> _share() async {
    final set = await showShareDialog(context);
    if (set == null || set.isEmpty) return;
    await _withBusy(() => widget.service.shareTodo(_currentTodo, set));
  }

  Future<void> _schedule() async {
    final when = await showScheduleDialog(context);
    if (when == null) return;
    await _withBusy(() => widget.service.scheduleTodo(_currentTodo, when));
  }

  Future<void> _setDueDate() async {
    final now = _currentTodo.obj.dueDate ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (time == null) return;
    final newDue = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    await _withBusy(() => widget.service.setDueDate(_currentTodo, newDue));
  }

  Future<void> _addNote() async {
    final text = _noteCtrl.text.trim();
    if (text.isEmpty) return;
    await _withBusy(() async {
      await widget.service.addNote(_currentTodo, text);
      _noteCtrl.clear();
    });
  }

  Future<void> _editNote(CItem<TodoNote> note) async {
    final controller = TextEditingController(text: note.obj.note);
    final newText = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newText == null || newText.isEmpty) return;
    await _withBusy(
      () => widget.service.updateNote(note, _currentTodo, newText),
    );
  }

  String _fmtDate(DateTime? d) => d == null
      ? '—'
      : d.toIso8601String().substring(0, 19).replaceFirst('T', ' ');

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final isOwner = _currentTodo.owner == service.self;
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentTodo.obj.title),
        actions: [
          if (isOwner)
            IconButton(
              onPressed: _busy ? null : _edit,
              icon: const Icon(Icons.edit),
            ),
          if (isOwner)
            IconButton(
              onPressed: _busy ? null : _share,
              icon: const Icon(Icons.share),
            ),
          if (isOwner)
            IconButton(
              onPressed: _busy ? null : _schedule,
              icon: const Icon(Icons.schedule),
            ),
          if (isOwner)
            IconButton(
              onPressed: _busy ? null : _setDueDate,
              icon: const Icon(Icons.calendar_today),
            ),
          if (isOwner)
            IconButton(
              onPressed: _busy ? null : _delete,
              icon: const Icon(Icons.delete),
            ),
        ],
      ),
      body: StreamBuilder<List<CItem<TodoNote>>>(
        stream: service.watchNotes(_currentTodo),
        builder: (_, snap) {
          final todo = _currentTodo;
          final notes = snap.data ?? const <CItem<TodoNote>>[];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: todo.obj.done,
                          onChanged: isOwner
                              ? (_) => _withBusy(() => service.toggleDone(todo))
                              : null,
                        ),
                        Expanded(
                          child: Text(
                            todo.obj.title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                      ],
                    ),
                    if (todo.obj.description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(todo.obj.description),
                    ],
                    const SizedBox(height: 12),
                    _meta('Due', Text(_fmtDate(todo.obj.dueDate))),
                    _meta('Created', Text(_fmtDate(todo.createdAt))),
                    _meta(
                      'Author',
                      AtsignText(atSign: todo.owner, colors: service.colors),
                    ),
                    _meta(
                      'Shared with',
                      AtsignList(
                        atSigns: todo.sharedWith,
                        colors: service.colors,
                      ),
                    ),
                    _meta(
                      'Read by',
                      // Live timeline of receipts, sorted by when
                      // each reader marked the item. Direct use
                      // of the public `item.receipts` handle:
                      // `.query().orderBy(...).watch()`. Each
                      // receipt's `owner` is the reader and its
                      // `createdAt` is "when they marked it".
                      StreamBuilder<List<CItem<Map<String, dynamic>>>>(
                        stream: todo.receipts
                            .query()
                            .orderBy((r) => r.createdAt)
                            .watch(),
                        builder: (_, snap) {
                          final receipts = snap.data ?? const [];
                          if (receipts.isEmpty) {
                            return Text(
                              todo.sharedWith.isEmpty ? '—' : '(nobody yet)',
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final r in receipts)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Row(
                                    children: [
                                      AtsignText(
                                        atSign: r.owner,
                                        colors: service.colors,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _fmtDate(r.createdAt),
                                        style: TextStyle(
                                          color: Theme.of(context).hintColor,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  'Notes (${notes.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Expanded(
                child: notes.isEmpty
                    ? const Center(child: Text('No notes'))
                    : ListView.separated(
                        itemCount: notes.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final n = notes[i];
                          final noteIsMine = n.owner == service.self;
                          return Dismissible(
                            key: ValueKey('${n.owner}:${n.id}'),
                            direction: noteIsMine
                                ? DismissDirection.endToStart
                                : DismissDirection.none,
                            background: Container(
                              color: Colors.red,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: const Icon(
                                Icons.delete,
                                color: Colors.white,
                              ),
                            ),
                            confirmDismiss: (_) async => noteIsMine,
                            onDismissed: (_) =>
                                _withBusy(() => service.deleteNote(n, todo)),
                            child: ListTile(
                              title: Text(n.obj.note),
                              subtitle: Row(
                                children: [
                                  AtsignText(
                                    atSign: n.owner,
                                    colors: service.colors,
                                  ),
                                  const Text(' · '),
                                  Text(_fmtDate(n.createdAt)),
                                ],
                              ),
                              onTap: noteIsMine ? () => _editNote(n) : null,
                            ),
                          );
                        },
                      ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _noteCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Add a note…',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _addNote(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _busy ? null : _addNote,
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _meta(String label, Widget value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: value),
        ],
      ),
    );
  }
}
