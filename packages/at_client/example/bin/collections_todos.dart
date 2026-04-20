import 'dart:async';
import 'dart:io';

import 'package:at_cli_commons/at_cli_commons.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client_examples/domain_objects.dart';
import 'package:nocterm/nocterm.dart';

void main(List<String> args) async {
  final AtClient atClient =
      (await CLIBase.fromCommandLineArgs(args, namespace: 'todos.demos'))
          .atClient;

  atClient.getPreferences()!.remoteLocalPref = RemoteLocalPref.remoteOnly;

  final app = TodosApp(atClient);
  await app.run();
  exit(0);
}

class TodosApp {
  final AtClient atClient;
  late final AtCollection<Todo> collection;
  late final AtCollection<TodoNote> notesCollection;
  late final Terminal terminal;
  late final StdioBackend backend;

  final List<String> logMessages = [];
  List<CItem<Todo>> todos = [];
  Map<String, List<CItem<TodoNote>>> notesByTodoId = {};
  String currentInput = '';
  bool _running = false;
  bool _handlerRunning = false;
  int logScrollOffset = 0;
  String? _promptLabel;
  Completer<String>? _promptCompleter;

  TodosApp(this.atClient) {
    AtCollection.registerFactory(type: 'Todo', factory: Todo.fromJson);
    AtCollection.registerFactory(type: 'TodoNote', factory: TodoNote.fromJson);
    collection = atClient.collection<Todo>(
      'todos.${atClient.getPreferences()!.namespace}',
      const Duration(days: 365),
    );
    notesCollection = atClient.collection<TodoNote>(
      'notes.${atClient.getPreferences()!.namespace}',
      const Duration(days: 365),
    );
  }

  void log(String message) {
    logMessages
        .add('${DateTime.now().toIso8601String().substring(11, 23)}: $message');
    if (logMessages.length > 100) logMessages.removeAt(0);
    logScrollOffset = 0;
    _draw();
  }

  Future<String> _prompt(String label) {
    _promptLabel = label;
    currentInput = '';
    _promptCompleter = Completer<String>();
    _draw();
    return _promptCompleter!.future;
  }

  Future<void> _runHandler(Future<void> Function() fn) async {
    if (_handlerRunning) {
      log('A command is already running');
      return;
    }
    _handlerRunning = true;
    try {
      await fn();
    } catch (e) {
      log('Error: $e');
    } finally {
      _handlerRunning = false;
      _promptLabel = null;
      final pending = _promptCompleter;
      _promptCompleter = null;
      if (pending != null && !pending.isCompleted) {
        pending.complete('');
      }
      _draw();
    }
  }

  Future<void> refreshTodos() async {
    try {
      todos = await collection.getItemsList();
      for (final item in todos) {
        if (!(await collection.sentReadReceipt(item))) {
          await collection.sendReadReceipt(item);
          log('Read receipt sent for: ${item.obj.title}');
        }
      }
      _draw();
    } catch (e) {
      log('Error refreshing todos: $e');
    }
  }

  Future<void> _refreshNotes() async {
    try {
      final items = await notesCollection.getItemsList();
      notesByTodoId = {};
      for (final n in items) {
        notesByTodoId.putIfAbsent(n.obj.todoId, () => []).add(n);
        if (!(await notesCollection.sentReadReceipt(n))) {
          await notesCollection.sendReadReceipt(n);
        }
      }
      _draw();
    } catch (e) {
      log('Error refreshing notes: $e');
    }
  }

  Future<void> run() async {
    backend = StdioBackend();
    terminal = Terminal(backend);

    terminal.enterAlternateScreen();
    terminal.hideCursor();
    terminal.clear();
    backend.enableRawMode();

    _running = true;

    collection.events
        .where((e) => e is CReadReceipt)
        .cast<CReadReceipt>()
        .listen((e) {
      log('message read by ${e.from}');
      unawaited(refreshTodos());
    });

    collection.events
        .where((e) => e is CItemUpdated)
        .cast<CItemUpdated>()
        .listen((e) {
      unawaited(() async {
        try {
          final item = await collection.get(e.id, e.owner);
          log('Item updated: "${item.obj.title}" (${e.owner})');
        } catch (_) {
          log('Item updated: id ${e.id} (${e.owner})');
        }
        await refreshTodos();
      }());
    });

    collection.events
        .where((e) => e is CItemDeleted)
        .cast<CItemDeleted>()
        .listen((e) {
      log('Item deleted: ${e.id} (${e.owner})');
      unawaited(refreshTodos());
    });

    notesCollection.events.listen((CEvent e) {
      switch (e) {
        case CItemUpdated():
          log('Note updated: id ${e.id} (${e.owner})');
          unawaited(_refreshNotes());
        case CItemDeleted():
          log('Note deleted: id ${e.id} (${e.owner})');
          unawaited(_refreshNotes());
        default:
          break;
      }
    });

    unawaited(refreshTodos());
    unawaited(_refreshNotes());

    final sigintSub = ProcessSignal.sigint.watch().listen((_) async {
      await stop();
      exit(0);
    });

    try {
      _draw();

      final inputStream = backend.inputStream;
      if (inputStream != null) {
        await for (final data in inputStream) {
          if (!_running) break;

          if (data.length == 1) {
            final charCode = data[0];
            if (charCode == 13 || charCode == 10) {
              final completer = _promptCompleter;
              if (completer != null && !completer.isCompleted) {
                final value = currentInput;
                currentInput = '';
                _promptLabel = null;
                _promptCompleter = null;
                completer.complete(value);
              } else if (!_handlerRunning) {
                final cmd = currentInput.trim();
                currentInput = '';
                if (cmd == 'quit') {
                  _running = false;
                  break;
                } else if (cmd == 'create') {
                  unawaited(_runHandler(_handleCreate));
                } else if (cmd == 'update') {
                  unawaited(_runHandler(_handleUpdate));
                } else if (cmd == 'delete') {
                  unawaited(_runHandler(_handleDelete));
                } else if (cmd == 'done') {
                  unawaited(_runHandler(_handleDone));
                } else if (cmd == 'due') {
                  unawaited(_runHandler(_handleDue));
                } else if (cmd == 'note') {
                  unawaited(_runHandler(_handleNote));
                } else if (cmd == 'updatenote') {
                  unawaited(_runHandler(_handleUpdateNote));
                } else if (cmd == 'deletenote') {
                  unawaited(_runHandler(_handleDeleteNote));
                } else if (cmd == 'share') {
                  unawaited(_runHandler(_handleShare));
                } else if (cmd == 'schedule') {
                  unawaited(_runHandler(_handleSchedule));
                } else if (cmd == 'keys') {
                  unawaited(_handleKeys());
                } else if (cmd.isNotEmpty) {
                  log('Unknown command: $cmd');
                }
              }
            } else if (charCode == 127 || charCode == 8) {
              if (currentInput.isNotEmpty) {
                currentInput =
                    currentInput.substring(0, currentInput.length - 1);
              }
            } else if (charCode >= 32 && charCode <= 126) {
              currentInput += String.fromCharCode(charCode);
            }
          } else if (data.length > 1) {
            final seq = String.fromCharCodes(data);
            if (seq == '\x1b[5~' || seq == '\x1b[A') {
              int step = (seq == '\x1b[5~') ? 14 : 1;
              logScrollOffset = (logScrollOffset + step)
                  .clamp(0, (logMessages.length - 14).clamp(0, 100));
            } else if (seq == '\x1b[6~' || seq == '\x1b[B') {
              int step = (seq == '\x1b[6~') ? 14 : 1;
              logScrollOffset = (logScrollOffset - step).clamp(0, 100);
            }
          }
          _draw();
        }
      }
    } finally {
      await sigintSub.cancel();
      await stop();
    }
  }

  Future<void> stop() async {
    _running = false;
    terminal.reset();
    backend.disableRawMode();
    backend.dispose();
  }

  static const _cmdList = [
    'create',
    'update',
    'delete',
    'done',
    'due',
    'note',
    'updatenote',
    'deletenote',
    'share',
    'schedule',
    'keys',
    'quit',
  ];

  void _draw() {
    if (!_running) return;
    terminal.clear();
    final width = terminal.size.width.toInt();
    final height = terminal.size.height.toInt();

    final mainHeight = height - 16;
    terminal.moveCursor(0, 0);
    terminal.write(
        '\x1b[1m--- Shared Todos (${atClient.getCurrentAtSign()}) ---\x1b[0m');

    int row = 1;
    for (var i = 0; i < todos.length; i++) {
      if (row >= mainHeight) break;
      final todo = todos[i];
      final doneStr = todo.obj.done ? '[x]' : '[ ]';
      final dueStr = todo.obj.dueDate != null
          ? '  due: ${todo.obj.dueDate!.toIso8601String().substring(0, 10)}'
          : '';
      _writeLine(terminal, row, width,
          '[$i] $doneStr ${todo.owner}: ${todo.obj.title} - ${todo.obj.description}$dueStr');
      row++;

      if (row >= mainHeight) break;
      final createdStr = todo.createdAt.toIso8601String().substring(11, 16);
      final expiresStr = todo.expiresAt.toIso8601String().substring(0, 10);
      _writeLine(terminal, row, width,
          '      shared: ${todo.sharedWith.join(",")}  read: ${todo.readBy.join(",")}  created: $createdStr  expires: $expiresStr');
      row++;

      final notes = notesByTodoId[todo.id] ?? [];
      for (int ni = 0; ni < notes.length; ni++) {
        if (row >= mainHeight) break;
        final note = notes[ni];
        _writeLine(terminal, row, width,
            '      [n$ni] "${note.obj.note}" (${note.owner})');
        row++;
      }
    }

    final separatorRow = mainHeight;
    final cmdWidth = width ~/ 2;
    terminal.moveCursor(0, separatorRow);
    terminal.write('${"-" * cmdWidth}|${"-" * (width - cmdWidth - 1)}');

    for (int i = 0; i < _cmdList.length; i++) {
      terminal.moveCursor(0, separatorRow + 1 + i);
      terminal.write(_cmdList[i]);
    }
    terminal.moveCursor(0, separatorRow + 13);
    terminal.write('Arrows/PgUp/PgDn: scroll logs');

    final promptPrefix = _promptLabel != null
        ? '$_promptLabel: '
        : (_handlerRunning ? '(busy) ' : '> ');
    terminal.moveCursor(0, separatorRow + 14);
    terminal.write('$promptPrefix$currentInput');

    for (int i = 0; i < 14; i++) {
      final msgIndex = (logMessages.length - 1 - logScrollOffset) - (13 - i);
      if (msgIndex >= 0 && msgIndex < logMessages.length) {
        final logLine = logMessages[msgIndex];
        final truncated = logLine.length > width - cmdWidth - 3
            ? logLine.substring(0, width - cmdWidth - 3)
            : logLine;
        terminal.moveCursor(cmdWidth + 2, separatorRow + 1 + i);
        terminal.write(truncated);
      }
      terminal.moveCursor(cmdWidth, separatorRow + 1 + i);
      terminal.write('|');
    }

    if (logMessages.length > 14 + logScrollOffset) {
      terminal.moveCursor(width - 1, separatorRow + 1);
      terminal.write('^');
    }
    if (logScrollOffset > 0) {
      terminal.moveCursor(width - 1, separatorRow + 14);
      terminal.write('v');
    }

    terminal.moveCursor(
        promptPrefix.length + currentInput.length, separatorRow + 14);
    terminal.showCursor();
    terminal.flush();
  }

  void _writeLine(Terminal t, int row, int width, String line) {
    t.moveCursor(0, row);
    t.write(line.length > width ? line.substring(0, width) : line);
  }

  Future<void> _handleCreate() async {
    final title = (await _prompt('Title')).trim();
    if (title.isEmpty) {
      log('Cancelled');
      return;
    }
    final desc = (await _prompt('Description')).trim();
    final atSignsStr =
        (await _prompt('Share with (comma-separated @signs, or empty)')).trim();
    final atSigns = atSignsStr.isNotEmpty
        ? atSignsStr.split(',').map((e) => e.trim().toAtsign()).toSet()
        : <Atsign>{};

    log('Creating todo: $title');
    final item = collection.create(
      type: 'Todo',
      obj: Todo(title: title, description: desc),
      sharedWith: atSigns,
    );
    try {
      final results = await collection.put(item);
      log('Created. Success: ${results.every((r) => r is OpSuccess)}');
      log(collection.prettyString(item));
      await refreshTodos();
    } catch (e) {
      log('Error creating todo: $e');
    }
  }

  Future<void> _handleUpdate() async {
    final idxStr = (await _prompt('Todo index')).trim();
    final idx = int.tryParse(idxStr);
    if (idx == null || idx < 0 || idx >= todos.length) {
      log('Invalid index');
      return;
    }
    final title = (await _prompt('New title')).trim();
    if (title.isEmpty) {
      log('Cancelled');
      return;
    }
    final desc = (await _prompt('New description')).trim();
    final atSignsStr =
        (await _prompt('Share with (comma-separated @signs, or empty)')).trim();
    final atSigns = atSignsStr.isNotEmpty
        ? atSignsStr.split(',').map((e) => e.trim().toAtsign()).toSet()
        : <Atsign>{};

    final old = todos[idx];
    log('Updating todo: ${old.obj.title} -> $title');
    final updated = collection.create(
      type: 'Todo',
      obj: Todo(
        title: title,
        description: desc,
        done: old.obj.done,
        dueDate: old.obj.dueDate,
      ),
      id: old.id,
      sharedWith: atSigns,
    );
    try {
      final results = await collection.put(updated);
      log('Updated. Success: ${results.every((r) => r is OpSuccess)}');
      log(collection.prettyString(updated));
      await refreshTodos();
    } catch (e) {
      log('Error updating todo: $e');
    }
  }

  Future<void> _handleDelete() async {
    final idxStr = (await _prompt('Todo index')).trim();
    final idx = int.tryParse(idxStr);
    if (idx == null || idx < 0 || idx >= todos.length) {
      log('Invalid index');
      return;
    }
    final item = todos[idx];
    log('Deleting todo: ${item.obj.title}');
    try {
      final results = await collection.delete(item);
      log('Deleted. Success: ${results.every((r) => r is OpSuccess)}');
      await refreshTodos();
    } catch (e) {
      log('Error deleting todo: $e');
    }
  }

  Future<void> _handleDone() async {
    final idxStr = (await _prompt('Todo index')).trim();
    final idx = int.tryParse(idxStr);
    if (idx == null || idx < 0 || idx >= todos.length) {
      log('Invalid index');
      return;
    }
    final old = todos[idx];
    if (old.owner != atClient.atSign) {
      log('Cannot update todos owned by other atSigns');
      return;
    }
    final updated = collection.create(
      type: 'Todo',
      obj: Todo(
        title: old.obj.title,
        description: old.obj.description,
        done: !old.obj.done,
        dueDate: old.obj.dueDate,
      ),
      id: old.id,
      sharedWith: Set.from(old.sharedWith),
    );
    try {
      await collection.put(updated);
      log('"${old.obj.title}" marked ${updated.obj.done ? "done [x]" : "not done [ ]"}');
      await refreshTodos();
    } catch (e) {
      log('Error toggling done: $e');
    }
  }

  Future<void> _handleDue() async {
    final idxStr = (await _prompt('Todo index')).trim();
    final idx = int.tryParse(idxStr);
    if (idx == null || idx < 0 || idx >= todos.length) {
      log('Invalid index');
      return;
    }
    final old = todos[idx];
    if (old.owner != atClient.atSign) {
      log('Cannot update todos owned by other atSigns');
      return;
    }
    final dateStr = (await _prompt('Due date (YYYY-MM-DD)')).trim();
    DateTime dueDate;
    try {
      dueDate = DateTime.parse(dateStr);
    } catch (_) {
      log('Invalid date format. Use YYYY-MM-DD');
      return;
    }
    final updated = collection.create(
      type: 'Todo',
      obj: Todo(
        title: old.obj.title,
        description: old.obj.description,
        done: old.obj.done,
        dueDate: dueDate,
      ),
      id: old.id,
      sharedWith: Set.from(old.sharedWith),
    );
    try {
      await collection.put(updated);
      log('Due date set to $dateStr for "${old.obj.title}"');
      await refreshTodos();
    } catch (e) {
      log('Error setting due date: $e');
    }
  }

  Future<void> _handleNote() async {
    final idxStr = (await _prompt('Todo index')).trim();
    final idx = int.tryParse(idxStr);
    if (idx == null || idx < 0 || idx >= todos.length) {
      log('Invalid index');
      return;
    }
    final text = (await _prompt('Note text')).trim();
    if (text.isEmpty) {
      log('Note text cannot be empty');
      return;
    }
    final todo = todos[idx];
    final note = notesCollection.create(
      type: 'TodoNote',
      obj: TodoNote(note: text, todoId: todo.id),
      sharedWith: Set.from(todo.sharedWith),
    );
    try {
      final results = await notesCollection.put(note);
      log('Note added. Success: ${results.every((r) => r is OpSuccess)}');
      await _refreshNotes();
    } catch (e) {
      log('Error adding note: $e');
    }
  }

  Future<void> _handleUpdateNote() async {
    final idxStr = (await _prompt('Todo index')).trim();
    final idx = int.tryParse(idxStr);
    if (idx == null || idx < 0 || idx >= todos.length) {
      log('Invalid todo index');
      return;
    }
    final todo = todos[idx];
    final notes = notesByTodoId[todo.id] ?? [];
    if (notes.isEmpty) {
      log('No notes for that todo');
      return;
    }
    final niStr = (await _prompt('Note index')).trim();
    final ni = int.tryParse(niStr);
    if (ni == null || ni < 0 || ni >= notes.length) {
      log('Invalid note index');
      return;
    }
    final existing = notes[ni];
    if (existing.owner != atClient.atSign) {
      log('Cannot update notes owned by other atSigns');
      return;
    }
    final text = (await _prompt('New note text')).trim();
    if (text.isEmpty) {
      log('Cancelled');
      return;
    }
    final updated = notesCollection.create(
      type: 'TodoNote',
      obj: TodoNote(note: text, todoId: todo.id),
      id: existing.id,
      sharedWith: Set.from(todo.sharedWith),
    );
    try {
      final results = await notesCollection.put(updated);
      log('Note updated. Success: ${results.every((r) => r is OpSuccess)}');
      await _refreshNotes();
    } catch (e) {
      log('Error updating note: $e');
    }
  }

  Future<void> _handleDeleteNote() async {
    final idxStr = (await _prompt('Todo index')).trim();
    final idx = int.tryParse(idxStr);
    if (idx == null || idx < 0 || idx >= todos.length) {
      log('Invalid todo index');
      return;
    }
    final todo = todos[idx];
    final notes = notesByTodoId[todo.id] ?? [];
    if (notes.isEmpty) {
      log('No notes for that todo');
      return;
    }
    final niStr = (await _prompt('Note index')).trim();
    final ni = int.tryParse(niStr);
    if (ni == null || ni < 0 || ni >= notes.length) {
      log('Invalid note index');
      return;
    }
    final note = notes[ni];
    if (note.owner != atClient.atSign) {
      log('Cannot delete notes owned by other atSigns');
      return;
    }
    try {
      final results = await notesCollection.delete(note);
      log('Note deleted. Success: ${results.every((r) => r is OpSuccess)}');
      await _refreshNotes();
    } catch (e) {
      log('Error deleting note: $e');
    }
  }

  Future<void> _handleShare() async {
    final idxStr = (await _prompt('Todo index')).trim();
    final idx = int.tryParse(idxStr);
    if (idx == null || idx < 0 || idx >= todos.length) {
      log('Invalid index');
      return;
    }
    final item = todos[idx];
    if (item.owner != atClient.atSign) {
      log('Cannot share todos owned by other atSigns');
      return;
    }
    final atSignsStr =
        (await _prompt('Add recipients (comma-separated @signs)')).trim();
    if (atSignsStr.isEmpty) {
      log('No recipients specified');
      return;
    }
    final newAtSigns =
        atSignsStr.split(',').map((s) => s.trim().toAtsign()).toSet();
    item.sharedWith.addAll(newAtSigns);
    try {
      final results = await collection.put(item, unshareWithOthers: false);
      log('Shared with $newAtSigns. Success: ${results.every((r) => r is OpSuccess)}');
      await refreshTodos();
    } catch (e) {
      log('Error sharing: $e');
    }
  }

  Future<void> _handleSchedule() async {
    final idxStr = (await _prompt('Todo index')).trim();
    final idx = int.tryParse(idxStr);
    if (idx == null || idx < 0 || idx >= todos.length) {
      log('Invalid index');
      return;
    }
    final item = todos[idx];
    if (item.owner != atClient.atSign) {
      log('Cannot schedule todos owned by other atSigns');
      return;
    }
    final secsStr = (await _prompt('Delay (seconds)')).trim();
    final seconds = int.tryParse(secsStr);
    if (seconds == null || seconds <= 0) {
      log('Seconds must be a positive integer');
      return;
    }
    final availableAt = DateTime.now().add(Duration(seconds: seconds));
    try {
      final results = await collection.put(item, availableAt: availableAt);
      log('Scheduled "${item.obj.title}" available at '
          '${availableAt.toIso8601String().substring(0, 19)}. '
          'Success: ${results.every((r) => r is OpSuccess)}');
      await refreshTodos();
    } catch (e) {
      log('Error scheduling: $e');
    }
  }

  Future<void> _handleKeys() async {
    try {
      final todoKeys = await collection.getKeys();
      final noteKeys = await notesCollection.getKeys();
      log('--- Todo keys (${todoKeys.length}) ---');
      for (final k in todoKeys) {
        log('  ${k.fullKeyAndOwner}');
      }
      log('--- Note keys (${noteKeys.length}) ---');
      for (final k in noteKeys) {
        log('  ${k.fullKeyAndOwner}');
      }
    } catch (e) {
      log('Error fetching keys: $e');
    }
  }
}
