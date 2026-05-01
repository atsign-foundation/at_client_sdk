import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:flutter/foundation.dart';

import '../models/todo.dart';
import 'atsign_colors.dart';

/// Type alias for the combined parent-plus-notes stream emitted by
/// [TodosService.watchTodosWithNotes]. Each row carries one todo and
/// its current list of notes.
typedef TodoWithNotes = WithChildren<Todo, TodoNote>;

/// Wraps the two `AtCollection`s (todos and notes) and exposes reactive
/// state for Flutter widgets. Mirrors the TUI's in-file logic verbatim for
/// anything that affects interoperability (key names, note audience rule,
/// read-receipt behaviour, etc.).
///
/// Bundle A shape: todos are consumed as a `Stream<List<CItem<Todo>>>`
/// via [watchTodos]; count badges via [watchCount]; the detail screen
/// via [watchSingle]. The old `ValueNotifier<List<CItem<Todo>>>` and
/// manual `refreshTodos()` pattern are gone — `Query.watch()` picks
/// up remote changes, and write methods call [_pumpRefresh] for
/// immediate local-feedback.
class TodosService {
  static const String namespaceSuffix = 'todos.demos';
  static const Duration defaultExpiration = Duration(days: 365);

  final AtClient atClient;
  late final AtCollection<Todo> collection;
  late final AtsignColors colors;

  final ValueNotifier<List<String>> logMessages = ValueNotifier([]);

  // Memoised per-todo notes sub-collection, keyed by (owner, id) of
  // the parent todo. Used by write-path methods (addNote /
  // updateNote / deleteNote) — reads flow through `watchWithSub` and
  // `watchNotes` instead.
  final Map<String, AtCollection<TodoNote>> _notesSubs = {};

  // Active-query stream machinery for the combined parents-plus-notes
  // stream consumed by the home screen. Cached by [Query] object
  // identity — the home screen should memoise its `Query<Todo>` so
  // re-renders don't tear down the pipeline.
  StreamController<List<TodoWithNotes>>? _todosCtrl;
  StreamSubscription<List<TodoWithNotes>>? _todosWatchSub;
  Query<Todo>? _currentQuery;

  TodosService(this.atClient) {
    colors = AtsignColors(atClient.atSign);
  }

  /// Must be called before [init]. Creates the todos collection with
  /// orphan sweep. Notes live as per-todo sub-collections, built
  /// lazily by [_notesSubFor].
  Future<void> setUpCollections() async {
    final ns = atClient.getPreferences()!.namespace!;
    collection = await atClient.collection<Todo>(
      'todos.$ns',
      defaultExpiration,
      fromJson: Todo.fromJson,
      typeTag: 'Todo',
      cleanupOrphansOnCreation: true,
    );
    // Legacy notes probe — pre-subcollection versions of this app
    // stored notes under a sibling `notes.$ns` namespace. Report any
    // remaining legacy keys without migrating them.
    try {
      final legacyRegex = '(^|:)[^.]+\\.notes\\.${ns.replaceAll('.', '\\.')}@';
      final legacyKeys = await atClient.getAtKeys(regex: legacyRegex);
      if (legacyKeys.isNotEmpty) {
        _log(
          '${legacyKeys.length} legacy notes in "notes.$ns" '
          'present; not displayed by this version.',
        );
      }
    } catch (_) {
      /* best-effort */
    }
  }

  /// Returns the memoised notes sub-collection for [todo], constructing
  /// it on first access.
  AtCollection<TodoNote> _notesSubFor(CItem<Todo> todo) {
    final key = '${todo.owner}:${todo.id}';
    return _notesSubs.putIfAbsent(
      key,
      () => collection.subCollection<TodoNote>(
        parent: todo,
        subName: 'notes',
        defaultExpiration: defaultExpiration,
        fromJson: TodoNote.fromJson,
        typeTag: 'TodoNote',
      ),
    );
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
    await setUpCollections();
    // Both parent todos and their notes flow through a single
    // `Query.watchWithSub` stream (see [watchTodosWithNotes]).
    // Query.watch() already subscribes to the underlying collection
    // events internally — no manual event listeners here.
  }

  /// Live stream of `(todo, notes)` pairs matching [q]. Re-emits on
  /// any parent-level update/delete AND on any change to any listed
  /// parent's `notes` sub-collection. Replaces both the Bundle-A
  /// parents-only stream AND the manual refreshNotes loop with one
  /// subscription.
  ///
  /// Caches the pipeline on [Query] object identity — callers should
  /// memoise their `Query<Todo>` value across widget rebuilds
  /// (see `screens/todos_home.dart`).
  Stream<List<TodoWithNotes>> watchTodosWithNotes(Query<Todo> q) {
    if (!identical(q, _currentQuery)) {
      _todosWatchSub?.cancel();
      _todosCtrl?.close();
      _currentQuery = q;
      _todosCtrl = StreamController<List<TodoWithNotes>>.broadcast();
      _todosWatchSub = q
          .watchWithSub<TodoNote>(
            subName: 'notes',
            subDefaultExpiration: defaultExpiration,
            subFromJson: TodoNote.fromJson,
            subTypeTag: 'TodoNote',
          )
          .listen(_todosCtrl!.add, onError: _todosCtrl!.addError);
    }
    return _todosCtrl!.stream.asyncMap(_primeReadReceipts);
  }

  /// Live count of items matching [q] — thin convenience over
  /// `q.watch().map((l) => l.length)`. Useful for AppBar badges.
  Stream<int> watchCount(Query<Todo> q) => q.watch().map((l) => l.length);

  /// Live single-item stream for the detail screen. Re-emits whenever
  /// the underlying todo changes (e.g. an owner on another atSign
  /// renames it); yields `null` if the item is deleted while we're
  /// looking at it.
  Stream<CItem<Todo>?> watchSingle(String id, Atsign owner) => collection
      .query()
      .where((t) => t.id == id && t.owner == owner)
      .watch()
      .map((l) => l.isEmpty ? null : l.first);

  /// Live stream of notes for a single parent [todo] — used by the
  /// detail screen. Kept separate from [watchTodosWithNotes] so the
  /// detail screen doesn't pay for the full-list watch just to render
  /// one todo.
  Stream<List<CItem<TodoNote>>> watchNotes(CItem<Todo> todo) =>
      _notesSubFor(todo).query().watch().asyncMap((notes) async {
        for (final n in notes) {
          if (!(await n.wasMarkedReadByMe())) {
            await n.markReadByMe();
          }
        }
        return notes;
      });

  /// Mark-as-read / prime-readBy side effect applied to every snapshot
  /// flowing through [watchTodosWithNotes]. Kept on the pipeline so
  /// both remote and local-refresh emissions go through the same
  /// treatment — parents and children both get their receipts.
  Future<List<TodoWithNotes>> _primeReadReceipts(
    List<TodoWithNotes> rows,
  ) async {
    for (final r in rows) {
      if (!(await r.parent.wasMarkedReadByMe())) {
        await r.parent.markReadByMe();
        _log(
          'sent read receipt to ${r.parent.owner} for "${r.parent.obj.title}"',
        );
      }
      await r.parent.readBy;
      for (final note in r.children) {
        if (!(await note.wasMarkedReadByMe())) {
          await note.markReadByMe();
        }
      }
    }
    return rows;
  }

  /// One-shot fetch of the currently-watched query, pumped into the
  /// same controller the `watchWithSub` stream feeds. Called from
  /// write methods so the UI reflects a local change immediately
  /// rather than waiting for the atServer to echo the self-
  /// notification back through the live stream.
  Future<void> _pumpRefresh() async {
    final q = _currentQuery;
    final ctrl = _todosCtrl;
    if (q == null || ctrl == null || ctrl.isClosed) return;
    try {
      final parents = await q.fetch();
      final combined = <TodoWithNotes>[];
      for (final p in parents) {
        final notes = await _notesSubFor(p).query().fetch();
        combined.add(WithChildren(parent: p, children: notes));
      }
      ctrl.add(combined);
    } catch (e, st) {
      ctrl.addError(e, st);
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
    await _pumpRefresh();
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
    await _pumpRefresh();
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
    await _pumpRefresh();
  }

  Future<void> setDueDate(CItem<Todo> existing, DateTime dueDate) async {
    if (existing.owner != self) {
      throw StateError(
        'Cannot change due date on a todo owned by another atSign',
      );
    }
    await collection.update(
      collection.draft(
        obj: Todo(
          title: existing.obj.title,
          description: existing.obj.description,
          done: existing.obj.done,
          dueDate: dueDate,
        ),
        id: existing.id,
        sharedWith: Set.from(existing.sharedWith),
      ),
    );
    _log('due date set for "${existing.obj.title}"');
    await _pumpRefresh();
  }

  Future<void> deleteTodo(CItem<Todo> todo) async {
    // cascade: true so notes (and any deeper descendants) go with the
    // todo rather than stranding on the atServer.
    await collection.delete(todo, cascade: true);
    _log('deleted "${todo.obj.title}"');
    await _pumpRefresh();
    await _pumpRefresh();
  }

  Future<void> shareTodo(CItem<Todo> todo, Set<Atsign> addAtSigns) async {
    if (todo.owner != self) {
      throw StateError('Cannot share a todo owned by another atSign');
    }
    todo.sharedWith.addAll(addAtSigns);
    await collection.update(todo, unshareWithOthers: false);
    _log('shared "${todo.obj.title}" with ${addAtSigns.join(", ")}');
    await _pumpRefresh();
  }

  Future<void> scheduleTodo(CItem<Todo> todo, DateTime availableAt) async {
    if (todo.owner != self) {
      throw StateError('Cannot schedule a todo owned by another atSign');
    }
    todo.availableAt = availableAt;
    await collection.update(todo);
    _log('scheduled "${todo.obj.title}" for ${availableAt.toIso8601String()}');
    await _pumpRefresh();
  }

  Future<void> addNote(CItem<Todo> todo, String text) async {
    await _notesSubFor(todo).create(
      obj: TodoNote(note: text),
      sharedWith: noteAudience(todo),
    );
    _log('note added to "${todo.obj.title}"');
    await _pumpRefresh();
  }

  Future<void> updateNote(
    CItem<TodoNote> existing,
    CItem<Todo> todo,
    String text,
  ) async {
    if (existing.owner != self) {
      throw StateError('Cannot update a note owned by another atSign');
    }
    final sub = _notesSubFor(todo);
    await sub.update(
      sub.draft(
        obj: TodoNote(note: text),
        id: existing.id,
        sharedWith: noteAudience(todo),
      ),
    );
    _log('note updated on "${todo.obj.title}"');
    await _pumpRefresh();
  }

  Future<void> deleteNote(CItem<TodoNote> note, CItem<Todo> todo) async {
    if (note.owner != self) {
      throw StateError('Cannot delete a note owned by another atSign');
    }
    await _notesSubFor(todo).delete(note);
    _log('note deleted');
    await _pumpRefresh();
  }

  void dispose() {
    _todosWatchSub?.cancel();
    _todosCtrl?.close();
    logMessages.dispose();
  }
}
