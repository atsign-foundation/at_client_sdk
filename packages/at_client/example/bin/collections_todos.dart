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
  late final Terminal terminal;
  late final StdioBackend backend;

  final List<String> logMessages = [];
  List<CItem<Todo>> todos = [];
  String currentInput = "";
  bool _running = false;
  int logScrollOffset = 0; // 0 means bottom (most recent)

  TodosApp(this.atClient) {
    CItem.registerFactory(type: 'Todo', factory: Todo.fromJson);
    CItem.registerFactory(type: 'TodoNote', factory: TodoNote.fromJson);
    collection = atClient.collection<Todo>(
      'todos.${atClient.getPreferences()!.namespace}',
      const Duration(days: 365),
    );
  }

  void log(String message) {
    logMessages
        .add('${DateTime.now().toIso8601String().substring(11, 23)}: $message');
    if (logMessages.length > 100) logMessages.removeAt(0);
    logScrollOffset = 0; // Reset to bottom on new message
    _draw();
  }

  Future<void> refreshTodos() async {
    try {
      final response = await collection.get();
      todos = response.items;

      for (final item in todos) {
        if (!(await collection.sentReadReceipt(item))) {
          await collection.sendReadReceipt(item);
          log('Read receipt sent for todo: ${item.obj.title}');
        }
      }

      for (final ex in response.exceptions) {
        log('Error loading some items: $ex');
      }
      _draw();
    } catch (e) {
      log('Error refreshing todos: $e');
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

    collection.events.listen((event) {
      if (event is CReadReceipt) {
        log('message read by ${event.from}');
        unawaited(refreshTodos());
      } else if (event is CItemUpdated) {
        unawaited(() async {
          final res = await collection.get(id: event.id, owner: event.owner);
          if (res.items.isNotEmpty) {
            final fetchedItem = res.items.first;
            log('Item updated: id: ${event.id} Owner ${event.owner}, title ${fetchedItem.obj.title}');
          } else {
            log('Item updated: id: ${event.id} Owner ${event.owner}');
          }
          await refreshTodos();
        }());
      } else if (event is CItemDeleted) {
        log('Item deleted: ${event.id}');
        unawaited(refreshTodos());
      }
    });

    unawaited(refreshTodos());

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
              // Enter
              final cmd = currentInput.trim();
              currentInput = "";
              if (cmd == 'quit') {
                _running = false;
                break;
              } else if (cmd.startsWith('create ')) {
                unawaited(_handleCreate(cmd));
              } else if (cmd.startsWith('update ')) {
                unawaited(_handleUpdate(cmd));
              } else if (cmd.startsWith('delete ')) {
                unawaited(_handleDelete(cmd));
              } else if (cmd.isNotEmpty) {
                log('Unknown command: $cmd');
              }
            } else if (charCode == 127 || charCode == 8) {
              // Backspace
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
              // Page Up or Up Arrow
              int step = (seq == '\x1b[5~') ? 14 : 1;
              logScrollOffset = (logScrollOffset + step)
                  .clamp(0, (logMessages.length - 14).clamp(0, 100));
            } else if (seq == '\x1b[6~' || seq == '\x1b[B') {
              // Page Down or Down Arrow
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

  void _draw() {
    if (!_running) return;
    terminal.clear();
    final width = terminal.size.width.toInt();
    final height = terminal.size.height.toInt();

    final mainHeight = height - 16;
    terminal.moveCursor(0, 0);
    terminal.write(
        "\x1b[1m--- Shared Todos (${atClient.getCurrentAtSign()}) ---\x1b[0m");

    for (var i = 0; i < todos.length && i < mainHeight - 2; i++) {
      final todo = todos[i];
      terminal.moveCursor(0, i + 1);
      terminal.write(
          "[$i] ${todo.owner}: ${todo.obj.title} - ${todo.obj.description} (shared: ${todo.sharedWith.join(', ')}) (read: ${todo.readBy.join(', ')})");
    }

    final separatorRow = mainHeight;
    final cmdWidth = width ~/ 2;
    terminal.moveCursor(0, separatorRow);
    terminal.write("${"-" * cmdWidth}|${"-" * (width - cmdWidth - 1)}");

    terminal.moveCursor(0, separatorRow + 1);
    terminal.write("Commands: create <title>,<desc>,<atSigns>");
    terminal.moveCursor(0, separatorRow + 2);
    terminal.write("          update <idx>,<title>,<desc>,<atSigns>");
    terminal.moveCursor(0, separatorRow + 3);
    terminal.write(
        "          delete <idx> | quit | Arrows/PgUp/PgDn to scroll logs");
    terminal.moveCursor(0, separatorRow + 4);
    terminal.write("> $currentInput");

    // Display logs: oldest at top of area, newest at bottom, respecting scroll offset
    // The bottom-most log line shown is (logMessages.length - 1 - logScrollOffset)
    for (int i = 0; i < 14; i++) {
      // i=0 is the top line of the log area (index separatorRow + 1)
      // i=13 is the bottom line (index separatorRow + 14)
      // We want the bottom line (i=13) to show the latest message (adjusted by scroll)
      final msgIndex = (logMessages.length - 1 - logScrollOffset) - (13 - i);

      if (msgIndex >= 0 && msgIndex < logMessages.length) {
        final logLine = logMessages[msgIndex];
        final truncatedLog = logLine.length > width - cmdWidth - 3
            ? logLine.substring(0, width - cmdWidth - 3)
            : logLine;
        terminal.moveCursor(cmdWidth + 2, separatorRow + 1 + i);
        terminal.write(truncatedLog);
      }
      terminal.moveCursor(cmdWidth, separatorRow + 1 + i);
      terminal.write("|");
    }

    // Scroll indicators
    if (logMessages.length > 14 + logScrollOffset) {
      terminal.moveCursor(width - 1, separatorRow + 1);
      terminal.write("^");
    }
    if (logScrollOffset > 0) {
      terminal.moveCursor(width - 1, separatorRow + 14);
      terminal.write("v");
    }

    terminal.moveCursor("> ".length + currentInput.length, separatorRow + 4);
    terminal.showCursor();
    terminal.flush();
  }

  Future<void> _handleCreate(String cmd) async {
    final parts = cmd.substring(7).split(',');
    if (parts.length >= 2) {
      final title = parts[0].trim();
      final desc = parts[1].trim();
      final atSigns = parts.length > 2
          ? parts.sublist(2).map((e) => e.trim().toAtsign()).toSet()
          : <Atsign>{};

      log('Creating todo: $title');
      final item = CItem.domain(
        owner: atClient.atSign,
        type: 'Todo',
        obj: Todo(title: title, description: desc),
        sharedWith: atSigns,
      );

      try {
        final results = await collection.put(item);
        log('Created $title. Success: ${results.every((r) => r is OpSuccess)}');
        await refreshTodos();
      } catch (e) {
        log('Error creating todo: $e');
      }
    } else {
      log('Invalid create cmd. Format: create title,desc,atSign1,atSign2');
    }
  }

  Future<void> _handleUpdate(String cmd) async {
    final parts = cmd.substring(7).split(',');
    if (parts.length >= 3) {
      final idx = int.tryParse(parts[0].trim());
      if (idx != null && idx >= 0 && idx < todos.length) {
        final title = parts[1].trim();
        final desc = parts[2].trim();
        final atSigns = parts.length > 3
            ? parts.sublist(3).map((e) => e.trim().toAtsign()).toSet()
            : <Atsign>{};

        final oldTodo = todos[idx];
        log('Updating todo: ${oldTodo.obj.title} -> $title');
        final newItem = CItem.domain(
          owner: atClient.atSign,
          type: 'Todo',
          obj: Todo(title: title, description: desc),
          id: oldTodo.id,
          sharedWith: atSigns,
        );

        try {
          final results = await collection.put(newItem);
          log('Updated $title. Success: ${results.every((r) => r is OpSuccess)}');
          await refreshTodos();
        } catch (e) {
          log('Error updating todo: $e');
        }
      } else {
        log('Invalid index');
      }
    } else {
      log('Invalid update cmd. Format: update idx,title,desc,atSign1,atSign2');
    }
  }

  Future<void> _handleDelete(String cmd) async {
    final idxStr = cmd.substring(7).trim();
    final idx = int.tryParse(idxStr);
    if (idx != null && idx >= 0 && idx < todos.length) {
      final item = todos[idx];
      log('Deleting todo: ${item.obj.title}');
      try {
        final results = await collection.delete(item);
        log('Deleted ${item.obj.title}. Success: ${results.every((r) => r is OpSuccess)}');
        await refreshTodos();
      } catch (e) {
        log('Error deleting todo: $e');
      }
    } else {
      log('Invalid index for delete');
    }
  }
}
