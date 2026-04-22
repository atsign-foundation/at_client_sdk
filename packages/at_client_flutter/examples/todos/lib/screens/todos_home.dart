import 'package:at_client/at_client.dart';
import 'package:flutter/material.dart';

import '../models/todo.dart';
import '../onboarding.dart';
import '../services/todos_service.dart';
import '../widgets/atsign_text.dart';
import '../widgets/todo_form.dart';
import 'todo_detail.dart';

class TodosHome extends StatefulWidget {
  const TodosHome({super.key});

  @override
  State<TodosHome> createState() => _TodosHomeState();
}

class _TodosHomeState extends State<TodosHome> {
  TodosService? _service;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final atClient = AtClientManager.getInstance().atClient;
      final s = TodosService(atClient);
      await s.init();
      if (!mounted) return;
      setState(() {
        _service = s;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _service?.dispose();
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

  Future<void> _createTodo() async {
    final r = await TodoFormDialog.show(context);
    if (r == null) return;
    await _withBusy(
      () => _service!.createTodo(
        title: r.title,
        description: r.description,
        dueDate: r.dueDate,
        sharedWith: r.sharedWith,
      ),
    );
  }

  Future<void> _logout() async {
    await logout();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Todos')),
        body: Center(child: Text('Init failed: $_error')),
      );
    }
    final service = _service;
    if (service == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Todos — ${service.self}',
          style: TextStyle(color: service.colors.colorFor(service.self)),
        ),
        actions: [
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: ValueListenableBuilder<List<CItem<Todo>>>(
        valueListenable: service.todos,
        builder: (_, todos, __) {
          if (todos.isEmpty) {
            return const Center(child: Text('No todos yet. Tap + to add one.'));
          }
          return RefreshIndicator(
            onRefresh: () =>
                Future.wait([service.refreshTodos(), service.refreshNotes()]),
            child: ValueListenableBuilder(
              valueListenable: service.notesByTodoId,
              builder: (_, notesByTodoId, __) {
                return ListView.separated(
                  itemCount: todos.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final todo = todos[i];
                    final noteCount = (notesByTodoId[todo.id]?.length ?? 0);
                    return _TodoRow(
                      todo: todo,
                      noteCount: noteCount,
                      service: service,
                      onToggleDone: () =>
                          _withBusy(() => service.toggleDone(todo)),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              TodoDetailScreen(todo: todo, service: service),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _busy ? null : _createTodo,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _TodoRow extends StatelessWidget {
  final CItem<Todo> todo;
  final int noteCount;
  final TodosService service;
  final VoidCallback onToggleDone;
  final VoidCallback onTap;

  const _TodoRow({
    required this.todo,
    required this.noteCount,
    required this.service,
    required this.onToggleDone,
    required this.onTap,
  });

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    return d.toIso8601String().substring(0, 19).replaceFirst('T', ' ');
  }

  @override
  Widget build(BuildContext context) {
    final canToggle = todo.owner == service.self;
    final subtitleParts = <Widget>[
      if (todo.obj.description.isNotEmpty) Text(todo.obj.description),
      Row(children: [const Text('Due: '), Text(_fmtDate(todo.obj.dueDate))]),
      Row(
        children: [
          const Text('By: '),
          AtsignText(atSign: todo.owner, colors: service.colors),
          if (todo.sharedWith.isNotEmpty) ...[
            const Text(' · shared: '),
            Expanded(
              child: AtsignList(
                atSigns: todo.sharedWith,
                colors: service.colors,
              ),
            ),
          ],
        ],
      ),
      if (noteCount > 0) Text('$noteCount note${noteCount == 1 ? "" : "s"}'),
    ];
    return ListTile(
      leading: Checkbox(
        value: todo.obj.done,
        onChanged: canToggle ? (_) => onToggleDone() : null,
      ),
      title: Text(
        todo.obj.title,
        style: TextStyle(
          decoration: todo.obj.done ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: subtitleParts,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
      isThreeLine: true,
    );
  }
}
