import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:flutter/foundation.dart';

import '../models/todo.dart';
import 'atsign_colors.dart';

/// Wraps the two `AtCollection`s (todos and notes) and exposes reactive
/// state for Flutter widgets. Mirrors the TUI's in-file logic verbatim for
/// anything that affects interoperability (key names, note audience rule,
/// read-receipt behaviour, etc.).
class TodosService {
  static const String namespaceSuffix = 'todos.demos';
  static const Duration defaultExpiration = Duration(days: 365);

  final AtClient atClient;
  late final AtCollection<Todo> collection;
  late final AtCollection<TodoNote> notesCollection;
  late final AtsignColors colors;

  final ValueNotifier<List<CItem<Todo>>> todos = ValueNotifier([]);
  final ValueNotifier<Map<String, List<CItem<TodoNote>>>> notesByTodoId =
      ValueNotifier({});
  final ValueNotifier<List<String>> logMessages = ValueNotifier([]);

  final List<StreamSubscription> _subs = [];

  TodosService(this.atClient) {
    final ns = atClient.getPreferences()!.namespace!;
    collection = atClient.collection<Todo>(
      'todos.$ns',
      defaultExpiration,
      fromJson: Todo.fromJson,
    );
    notesCollection = atClient.collection<TodoNote>(
      'notes.$ns',
      defaultExpiration,
      fromJson: TodoNote.fromJson,
    );
    colors = AtsignColors(atClient.atSign);
  }

  Atsign get self => atClient.atSign;

  void _log(String message) {
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    logMessages.value = [...logMessages.value, '$ts $message'];
    if (logMessages.value.length > 200) {
      logMessages.value = logMessages.value.sublist(
        logMessages.value.length - 200,
      );
    }
  }

  Future<void> init() async {
    _subs.add(collection.readReceipts.listen((r) {
      _log('read receipt from ${r.from}');
      unawaited(refreshTodos());
    }));
    _subs.add(collection.updates.listen((_) => unawaited(refreshTodos())));
    _subs.add(collection.deletes.listen((_) => unawaited(refreshTodos())));
    _subs.add(notesCollection.updates.listen((_) => unawaited(refreshNotes())));
    _subs.add(notesCollection.deletes.listen((_) => unawaited(refreshNotes())));

    await Future.wait([refreshTodos(), refreshNotes()]);
  }

  int _compareByDue(CItem<Todo> a, CItem<Todo> b) {
    final ad = a.obj.dueDate;
    final bd = b.obj.dueDate;
    if (ad == null && bd == null) return 0;
    if (ad == null) return 1;
    if (bd == null) return -1;
    return ad.compareTo(bd);
  }

  Future<void> refreshTodos() async {
    try {
      final fetched = await collection.getItems();
      fetched.sort(_compareByDue);
      todos.value = fetched;
      for (final item in fetched) {
        if (!(await collection.wasMarkedReadByMe(item))) {
          await collection.markReadByMe(item);
          _log('sent read receipt to ${item.owner} for "${item.obj.title}"');
        }
      }
    } catch (e) {
      _log('Error refreshing todos: $e');
    }
  }

  Future<void> refreshNotes() async {
    try {
      final items = await notesCollection.getItems();
      final map = <String, List<CItem<TodoNote>>>{};
      for (final n in items) {
        map.putIfAbsent(n.obj.todoId, () => []).add(n);
        if (!(await notesCollection.wasMarkedReadByMe(n))) {
          await notesCollection.markReadByMe(n);
        }
      }
      for (final list in map.values) {
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      }
      notesByTodoId.value = map;
    } catch (e) {
      _log('Error refreshing notes: $e');
    }
  }

  /// Audience for a note attached to [todo] — matches the TUI's _noteAudience.
  Set<Atsign> noteAudience(CItem<Todo> todo) {
    final audience = <Atsign>{todo.owner, ...todo.sharedWith};
    audience.remove(self);
    return audience;
  }

  Future<void> createTodo({
    required String title,
    required String description,
    required DateTime dueDate,
    required Set<Atsign> sharedWith,
  }) async {
    final item = await collection.create(
      obj: Todo(title: title, description: description, dueDate: dueDate),
      sharedWith: sharedWith,
    );
    _log('created "${item.obj.title}"');
    await refreshTodos();
  }

  Future<void> updateTodo(
    CItem<Todo> existing, {
    required String title,
    required String description,
    required Set<Atsign> sharedWith,
  }) async {
    final updated = collection.draft(
      obj: Todo(
        title: title,
        description: description,
        done: existing.obj.done,
        dueDate: existing.obj.dueDate,
      ),
      id: existing.id,
      sharedWith: sharedWith,
    );
    await collection.update(updated);
    _log('updated "${updated.obj.title}"');
    await refreshTodos();
  }

  Future<void> toggleDone(CItem<Todo> existing) async {
    if (existing.owner != self) {
      throw StateError('Cannot toggle done on a todo owned by another atSign');
    }
    final updated = collection.draft(
      obj: Todo(
        title: existing.obj.title,
        description: existing.obj.description,
        done: !existing.obj.done,
        dueDate: existing.obj.dueDate,
      ),
      id: existing.id,
      sharedWith: Set.from(existing.sharedWith),
    );
    await collection.update(updated);
    _log(
      '"${existing.obj.title}" marked '
      '${updated.obj.done ? "done" : "not done"}',
    );
    await refreshTodos();
  }

  Future<void> setDueDate(CItem<Todo> existing, DateTime dueDate) async {
    if (existing.owner != self) {
      throw StateError('Cannot change due date on a todo owned by another atSign');
    }
    await collection.update(collection.draft(
      obj: Todo(
        title: existing.obj.title,
        description: existing.obj.description,
        done: existing.obj.done,
        dueDate: dueDate,
      ),
      id: existing.id,
      sharedWith: Set.from(existing.sharedWith),
    ));
    _log('due date set for "${existing.obj.title}"');
    await refreshTodos();
  }

  Future<void> deleteTodo(CItem<Todo> todo) async {
    await collection.delete(todo);
    _log('deleted "${todo.obj.title}"');
    await refreshTodos();
  }

  Future<void> shareTodo(CItem<Todo> todo, Set<Atsign> addAtSigns) async {
    if (todo.owner != self) {
      throw StateError('Cannot share a todo owned by another atSign');
    }
    todo.sharedWith.addAll(addAtSigns);
    await collection.update(todo, unshareWithOthers: false);
    _log('shared "${todo.obj.title}" with ${addAtSigns.join(", ")}');
    await refreshTodos();
  }

  Future<void> scheduleTodo(CItem<Todo> todo, DateTime availableAt) async {
    if (todo.owner != self) {
      throw StateError('Cannot schedule a todo owned by another atSign');
    }
    todo.availableAt = availableAt;
    await collection.update(todo);
    _log('scheduled "${todo.obj.title}" for ${availableAt.toIso8601String()}');
    await refreshTodos();
  }

  Future<void> addNote(CItem<Todo> todo, String text) async {
    await notesCollection.create(
      obj: TodoNote(note: text, todoId: todo.id),
      sharedWith: noteAudience(todo),
    );
    _log('note added to "${todo.obj.title}"');
    await refreshNotes();
  }

  Future<void> updateNote(
    CItem<TodoNote> existing,
    CItem<Todo> todo,
    String text,
  ) async {
    if (existing.owner != self) {
      throw StateError('Cannot update a note owned by another atSign');
    }
    await notesCollection.update(notesCollection.draft(
      obj: TodoNote(note: text, todoId: todo.id),
      id: existing.id,
      sharedWith: noteAudience(todo),
    ));
    _log('note updated on "${todo.obj.title}"');
    await refreshNotes();
  }

  Future<void> deleteNote(CItem<TodoNote> note) async {
    if (note.owner != self) {
      throw StateError('Cannot delete a note owned by another atSign');
    }
    await notesCollection.delete(note);
    _log('note deleted');
    await refreshNotes();
  }

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    todos.dispose();
    notesByTodoId.dispose();
    logMessages.dispose();
  }
}
