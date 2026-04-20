import 'dart:async';
import 'dart:io';

import 'package:at_cli_commons/at_cli_commons.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client_examples/domain_objects.dart';
import 'package:nocterm/nocterm.dart';

void main(List<String> args) async {
  final AtClient atClient =
      (await CLIBase.fromCommandLineArgs(
        args,
        namespace: 'todos.demos',
      )).atClient;

  atClient.getPreferences()!.remoteLocalPref = RemoteLocalPref.remoteOnly;

  final app = TodosApp(atClient);
  await app.run();
  exit(0);
}

class _TodoRef {
  final int todoIdx;
  final int? noteIdx;

  const _TodoRef(this.todoIdx, [this.noteIdx]);
}

class _AtsignColors {
  // dart format off
  // 20 pastel ANSI-256 foreground codes.
  static const List<int> _palette = [
    27, 33, 39, 63, 69, 75, 76, 82, 99, 105, 129, 135, 141, 148,
    160, 161, 162, 166, 172, 178, 196, 200, 201, 202, 208, 214
  ];

  // dart format on

  final Atsign myAtsign;
  final Map<String, int> _assigned = {};
  int _nextIdx = 0;

  _AtsignColors(this.myAtsign);

  String fmt(Atsign a, {String? displayText}) {
    final text = displayText ?? a.toString();
    if (a == myAtsign) {
      return '\x1b[1;38;5;208m$text\x1b[0m';
    }
    final key = a.toString();
    final idx = _assigned.putIfAbsent(key, () {
      final i = _nextIdx;
      _nextIdx = (_nextIdx + 1) % _palette.length;
      return i;
    });
    return '\x1b[38;5;${_palette[idx]}m$text\x1b[0m';
  }

  String fmtAll(Iterable<Atsign> xs) => xs.map(fmt).join(', ');
}

class _Cols {
  final int due;
  final int idx;
  final int st;
  final int title;
  final int desc;
  final int author;
  final int shared;
  final int readBy;

  const _Cols(
    this.due,
    this.idx,
    this.st,
    this.title,
    this.desc,
    this.author,
    this.shared,
    this.readBy,
  );

  // Overhead for an 8-column row: 9 '│' chars + 16 padding spaces = 25.
  static const int _overhead = 25;

  static _Cols compute(int totalWidth) {
    const due = 10;
    const idx = 3;
    const st = 3;
    const author = 20;
    final flex = (totalWidth - _overhead - due - idx - st - author).clamp(
      30,
      500,
    );
    final title = (flex * 0.15).round().clamp(5, 200);
    final desc = (flex * 0.30).round().clamp(5, 200);
    final shared = (flex * 0.275).round().clamp(5, 200);
    final readBy = (flex - title - desc - shared).clamp(5, 200);
    return _Cols(due, idx, st, title, desc, author, shared, readBy);
  }

  int get totalWidth =>
      _overhead + due + idx + st + title + desc + author + shared + readBy;

  List<int> get widths => [due, idx, st, title, desc, author, shared, readBy];

  // Column at which the Title cell's content begins (0-based).
  // Layout per cell: '│ <content> '. Three fixed cells precede Title.
  int get titleStartCol => due + idx + st + 11;
}

class TodosApp {
  final AtClient atClient;
  late final AtCollection<Todo> collection;
  late final AtCollection<TodoNote> notesCollection;
  late final Terminal terminal;
  late final StdioBackend backend;
  late final _AtsignColors _color;

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
    _color = _AtsignColors(atClient.atSign);
  }

  // Orange ANSI-256 colour for exception messages resulting directly from a
  // user command.
  static const String _errorAnsi = '\x1b[38;5;208m';

  void log(String message, {Atsign? by, bool error = false}) {
    final who = by ?? atClient.atSign;
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    final body = error ? '$_errorAnsi$message\x1b[0m' : message;
    logMessages.add('$ts ${_color.fmt(who)}: $body');
    if (logMessages.length > 100) logMessages.removeAt(0);
    // Preserve user's scroll position: if they've scrolled back, advance the
    // offset so they keep looking at the same messages as new ones arrive.
    if (logScrollOffset > 0) {
      final maxOffset = (logMessages.length - _logHeight).clamp(0, 100);
      logScrollOffset = (logScrollOffset + 1).clamp(0, maxOffset);
    }
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
      log('Error: $e', error: true);
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
      final fetched = await collection.getItemsList();
      fetched.sort(_compareByDue);
      todos = fetched;
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

  int _compareByDue(CItem<Todo> a, CItem<Todo> b) {
    final ad = a.obj.dueDate;
    final bd = b.obj.dueDate;
    if (ad == null && bd == null) return 0;
    if (ad == null) return 1;
    if (bd == null) return -1;
    return ad.compareTo(bd);
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
          log('sent us a read receipt', by: e.from);
          unawaited(refreshTodos());
        });

    collection.events
        .where((e) => e is CItemUpdated)
        .cast<CItemUpdated>()
        .listen((e) {
          unawaited(refreshTodos());
        });

    collection.events
        .where((e) => e is CItemDeleted)
        .cast<CItemDeleted>()
        .listen((e) {
          unawaited(refreshTodos());
        });

    notesCollection.events.listen((CEvent e) {
      switch (e) {
        case CItemUpdated():
          log('updated a note ', by: e.owner);
          unawaited(_refreshNotes());
        case CItemDeleted():
          log('deleted a note', by: e.owner);
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
                _handleCommand(cmd);
                if (!_running) break;
              }
            } else if (charCode == 127 || charCode == 8) {
              if (currentInput.isNotEmpty) {
                currentInput = currentInput.substring(
                  0,
                  currentInput.length - 1,
                );
              }
            } else if (charCode >= 32 && charCode <= 126) {
              currentInput += String.fromCharCode(charCode);
            }
          } else if (data.length > 1) {
            final seq = String.fromCharCodes(data);
            if (seq == '\x1b[5~' || seq == '\x1b[A') {
              int step = (seq == '\x1b[5~') ? _logHeight : 1;
              logScrollOffset = (logScrollOffset + step).clamp(
                0,
                (logMessages.length - _logHeight).clamp(0, 100),
              );
            } else if (seq == '\x1b[6~' || seq == '\x1b[B') {
              int step = (seq == '\x1b[6~') ? _logHeight : 1;
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

  static const Map<String, String> _cmdHelp = {
    'create':
        'Create a new todo. Prompts for title, description, atSigns, and due date (default 7 days).',
    'update':
        'Update a todo. Usage: update N. Prompts for new title, description, and share list.',
    'delete':
        'Delete a todo or note. Usage: delete N (todo) or delete N.M (note M of todo N).',
    'done': "Toggle a todo's done status. Usage: done N.",
    'due':
        'Set a due date. Usage: due N [YYYY-MM-DD]. Prompts for the date if not given.',
    'note':
        'Add a note to a todo. Usage: note N [text...]. Prompts for the text if not given.',
    'updatenote':
        "Update a note's text. Usage: updatenote N.M [text...]. Prompts for text if not given.",
    'share':
        'Add recipients to a todo (keeps existing shares). Usage: share N [@signs,...].',
    'schedule':
        'Delay recipient visibility (availableAt). Usage: schedule N [seconds].',
    'keys': 'Log all AtKeys in both collections (debug).',
    'help': 'Show help. Usage: "help <cmd>", "<cmd> help", or "<cmd> --help".',
    'quit': 'Exit the app.',
  };

  static const int _logHeight = 8;

  // Fixed row count for the wrapped command list. Enough for 2 lines at 80-col
  // terminals; wider terminals will wrap to 1 line and leave the second row
  // blank. This is deliberately fixed so mainHeight never shifts between draws.
  static const int _cmdRows = 2;

  void _draw() {
    if (!_running) return;
    terminal.clear();
    final width = terminal.size.width.toInt();
    final height = terminal.size.height.toInt();

    final cmdLines = _wrapCommands(width - 1);
    // Bottom pane: separator + commands + logs + hint + prompt. Fixed height.
    final bottomRows = 1 + _cmdRows + _logHeight + 2;
    final mainHeight = (height - bottomRows).clamp(3, height);
    terminal.moveCursor(0, 0);
    terminal.write(
      '\x1b[1m--- Shared Todos (${_color.fmt(atClient.atSign)}) ---\x1b[0m',
    );

    int row = 1;
    if (todos.isEmpty) {
      if (row < mainHeight) _trow(row++, width, '  (no todos)');
    } else {
      final cols = _Cols.compute(width);
      final tableWidth = cols.totalWidth.clamp(0, width);

      if (row < mainHeight) {
        row = _drawTableBorder(row, tableWidth, cols, '┌', '┬', '┐');
      }
      if (row < mainHeight) {
        row = _drawTableRowSingle(row, tableWidth, cols, [
          'Due',
          '#',
          '✓',
          'Title',
          'Description',
          'Author',
          'Shared with',
          'Read by',
        ]);
      }
      if (row < mainHeight) {
        row = _drawTableBorder(row, tableWidth, cols, '├', '┼', '┤');
      }

      for (int i = 0; i < todos.length && row < mainHeight; i++) {
        final todo = todos[i];
        final dueStr =
            todo.obj.dueDate != null
                ? todo.obj.dueDate!.toIso8601String().substring(0, 10)
                : '-';
        final idxStr = '${i + 1}';
        final stStr = todo.obj.done ? '[x]' : '[ ]';
        final authorStr = _color.fmt(todo.owner);
        final sharedStr =
            todo.sharedWith.isEmpty ? '-' : _color.fmtAll(todo.sharedWith);
        final readByStr =
            todo.readBy.isEmpty
                ? (todo.sharedWith.isEmpty ? '-' : '(nobody)')
                : _color.fmtAll(todo.readBy);
        row = _drawTableRowSingle(row, tableWidth, cols, [
          dueStr,
          idxStr,
          stStr,
          todo.obj.title,
          todo.obj.description,
          authorStr,
          sharedStr,
          readByStr,
        ]);

        if (row >= mainHeight) break;
        final notes = notesByTodoId[todo.id] ?? [];
        for (int ni = 0; ni < notes.length && row < mainHeight; ni++) {
          final n = notes[ni];
          final text = '[n${ni + 1}] (${_color.fmt(n.owner)}) "${n.obj.note}"';
          row = _drawNote(row, width, cols.titleStartCol, text, mainHeight);
        }

        if (row >= mainHeight) break;
        if (i < todos.length - 1) {
          row = _drawTableBorder(row, tableWidth, cols, '├', '┼', '┤');
        } else {
          row = _drawTableBorder(row, tableWidth, cols, '└', '┴', '┘');
        }
      }
    }

    final separatorRow = mainHeight;
    final cmdStartRow = separatorRow + 1;
    final logStartRow = cmdStartRow + _cmdRows;
    final hintRow = logStartRow + _logHeight;
    final promptRow = hintRow + 1;

    terminal.moveCursor(0, separatorRow);
    terminal.write('─' * width);

    for (int i = 0; i < _cmdRows; i++) {
      terminal.moveCursor(0, cmdStartRow + i);
      if (i < cmdLines.length) {
        terminal.write(_clipVisual(cmdLines[i], width));
      }
    }

    for (int i = 0; i < _logHeight; i++) {
      final msgIndex =
          (logMessages.length - 1 - logScrollOffset) - (_logHeight - 1 - i);
      if (msgIndex >= 0 && msgIndex < logMessages.length) {
        final logLine = logMessages[msgIndex];
        final clipped = _clipVisual(logLine, width - 1);
        terminal.moveCursor(0, logStartRow + i);
        terminal.write(clipped);
      }
    }

    if (logMessages.length > _logHeight + logScrollOffset) {
      terminal.moveCursor(width - 1, logStartRow);
      terminal.write('^');
    }
    if (logScrollOffset > 0) {
      terminal.moveCursor(width - 1, logStartRow + _logHeight - 1);
      terminal.write('v');
    }

    terminal.moveCursor(0, hintRow);
    terminal.write('Arrows/PgUp/PgDn: scroll logs');

    final promptPrefix =
        _promptLabel != null
            ? '$_promptLabel: '
            : (_handlerRunning ? '(busy) ' : '> ');
    terminal.moveCursor(0, promptRow);
    terminal.write('$promptPrefix$currentInput');

    terminal.moveCursor(promptPrefix.length + currentInput.length, promptRow);
    terminal.showCursor();
    terminal.flush();
  }

  int _drawTableBorder(
    int row,
    int width,
    _Cols cols,
    String left,
    String mid,
    String right,
  ) {
    final widths = cols.widths;
    final parts = <String>[left];
    for (int i = 0; i < widths.length; i++) {
      parts.add('─' * (widths[i] + 2));
      parts.add(i < widths.length - 1 ? mid : right);
    }
    final s = parts.join();
    terminal.moveCursor(0, row);
    terminal.write(s.length > width ? s.substring(0, width) : s);
    return row + 1;
  }

  int _drawTableRowSingle(int row, int width, _Cols cols, List<String> values) {
    final widths = cols.widths;
    final parts = <String>['│'];
    for (int c = 0; c < widths.length; c++) {
      final clipped = _clipVisual(values[c], widths[c]);
      parts.add(' ${_padRightVisual(clipped, widths[c])} │');
    }
    terminal.moveCursor(0, row);
    terminal.write(_clipVisual(parts.join(), width));
    return row + 1;
  }

  int _drawNote(int row, int width, int indent, String text, int maxRow) {
    final noteWidth = (width - indent).clamp(10, 500);
    final wrapped = _wrapCell(text, noteWidth);
    int r = row;
    for (int i = 0; i < wrapped.length && r < maxRow; i++) {
      terminal.moveCursor(indent, r);
      terminal.write(_clipVisual(wrapped[i], noteWidth));
      r++;
    }
    return r;
  }

  void _trow(int row, int width, String content) {
    final inner = (width - 2).clamp(0, width);
    final s =
        content.length > inner
            ? content.substring(0, inner)
            : content.padRight(inner);
    terminal.moveCursor(0, row);
    terminal.write('│$s│');
  }

  static final RegExp _ansiRe = RegExp(r'\x1b\[[0-9;]*m');

  int _visualLen(String s) => s.replaceAll(_ansiRe, '').length;

  String _padRightVisual(String s, int width) {
    final vl = _visualLen(s);
    if (vl >= width) return s;
    return '$s${' ' * (width - vl)}';
  }

  // Truncate to visual width, preserving complete ANSI escape sequences and
  // closing any open color with a reset.
  String _clipVisual(String s, int width) {
    if (width <= 0) return '';
    if (_visualLen(s) <= width) return s;
    int visible = 0;
    final parts = <String>[];
    int i = 0;
    bool sawEscape = false;
    while (i < s.length && visible < width) {
      if (s.codeUnitAt(i) == 0x1b) {
        final m = _ansiRe.matchAsPrefix(s, i);
        if (m != null) {
          parts.add(m.group(0)!);
          i = m.end;
          sawEscape = true;
          continue;
        }
      }
      parts.add(s[i]);
      visible++;
      i++;
    }
    if (sawEscape) parts.add('\x1b[0m');
    return parts.join();
  }

  // Simple word-wrap that respects ANSI escape-sequence groups (treats a
  // complete \x1b[...m as zero-width) and hard-breaks overlong words.
  List<String> _wrapCell(String text, int width) {
    if (width <= 0) return [''];
    if (text.isEmpty) return [''];
    final words = text.split(RegExp(r'\s+'));
    final lines = <String>[];
    String current = '';
    int currentVl = 0;
    for (final word in words) {
      if (word.isEmpty) continue;
      final wl = _visualLen(word);
      if (wl > width) {
        if (current.isNotEmpty) {
          lines.add(current);
          current = '';
          currentVl = 0;
        }
        // hard-break (on plain text; escape-wrapped long single tokens are rare)
        final plain = word.replaceAll(_ansiRe, '');
        for (int j = 0; j < plain.length; j += width) {
          final chunk = plain.substring(j, (j + width).clamp(0, plain.length));
          if (chunk.length == width) {
            lines.add(chunk);
          } else {
            current = chunk;
            currentVl = chunk.length;
          }
        }
      } else if (currentVl == 0) {
        current = word;
        currentVl = wl;
      } else if (currentVl + 1 + wl <= width) {
        current = '$current $word';
        currentVl = currentVl + 1 + wl;
      } else {
        lines.add(current);
        current = word;
        currentVl = wl;
      }
    }
    if (current.isNotEmpty) lines.add(current);
    if (lines.isEmpty) lines.add('');
    return lines;
  }

  Set<Atsign> _noteAudience(CItem<Todo> todo) {
    final audience = <Atsign>{todo.owner, ...todo.sharedWith};
    audience.remove(atClient.atSign);
    return audience;
  }

  List<String> _wrapCommands(int maxWidth) {
    final names = _cmdHelp.keys.toList();
    final lines = <String>[];
    String current = '';
    for (int i = 0; i < names.length; i++) {
      final name = names[i];
      if (current.isEmpty) {
        current = name;
      } else {
        final trial = '$current, $name';
        if (trial.length <= maxWidth) {
          current = trial;
        } else {
          lines.add('$current,');
          current = name;
        }
      }
    }
    if (current.isNotEmpty) lines.add(current);
    return lines;
  }

  _TodoRef? _parseRef(String s) {
    if (s.isEmpty) return null;
    final parts = s.split('.');
    if (parts.isEmpty || parts.length > 2) return null;
    final t = int.tryParse(parts[0]);
    if (t == null || t < 1) return null;
    if (parts.length == 1) return _TodoRef(t - 1);
    final n = int.tryParse(parts[1]);
    if (n == null || n < 1) return null;
    return _TodoRef(t - 1, n - 1);
  }

  void _handleCommand(String cmd) {
    if (cmd.isEmpty) return;
    final parts = cmd.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return;
    final first = parts.first;
    final args = parts.sublist(1);

    if (first == 'help' || first == '--help') {
      _showHelp(args.isNotEmpty ? args.first : null);
      return;
    }
    if (args.isNotEmpty && (args.last == 'help' || args.last == '--help')) {
      _showHelp(first);
      return;
    }

    switch (first) {
      case 'quit':
        if (args.isNotEmpty) {
          log('Unknown command: $cmd');
          return;
        }
        _running = false;
      case 'create':
        if (args.isNotEmpty) {
          log('Unknown command: $cmd');
          return;
        }
        unawaited(_runHandler(_handleCreate));
      case 'update':
        unawaited(_runHandler(() => _handleUpdate(args)));
      case 'delete':
        unawaited(_runHandler(() => _handleDelete(args)));
      case 'done':
        unawaited(_runHandler(() => _handleDone(args)));
      case 'due':
        unawaited(_runHandler(() => _handleDue(args)));
      case 'note':
        unawaited(_runHandler(() => _handleNote(args)));
      case 'updatenote':
        unawaited(_runHandler(() => _handleUpdateNote(args)));
      case 'share':
        unawaited(_runHandler(() => _handleShare(args)));
      case 'schedule':
        unawaited(_runHandler(() => _handleSchedule(args)));
      case 'keys':
        if (args.isNotEmpty) {
          log('Unknown command: $cmd');
          return;
        }
        unawaited(_handleKeys());
      default:
        log('Unknown command: $cmd');
    }
  }

  void _showHelp(String? target) {
    if (target == null || target.isEmpty) {
      log('Commands: ${_cmdHelp.keys.join(", ")}');
      log('Type "help <cmd>", "<cmd> help", or "<cmd> --help" for details.');
      return;
    }
    final desc = _cmdHelp[target];
    if (desc != null) {
      log('$target: $desc');
    } else {
      log('No help for "$target". Known: ${_cmdHelp.keys.join(", ")}');
    }
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
    final atSigns =
        atSignsStr.isNotEmpty
            ? atSignsStr.split(',').map((e) => e.trim().toAtsign()).toSet()
            : <Atsign>{};

    final dueStr =
        (await _prompt(
          'Due date (YYYY-MM-DD, empty for 7 days from now)',
        )).trim();
    DateTime dueDate;
    if (dueStr.isEmpty) {
      dueDate = DateTime.now().add(const Duration(days: 7));
    } else {
      try {
        dueDate = DateTime.parse(dueStr);
      } catch (_) {
        log('Invalid date, using default (7 days from now)');
        dueDate = DateTime.now().add(const Duration(days: 7));
      }
    }

    log('Creating todo: $title');
    final item = collection.create(
      type: 'Todo',
      obj: Todo(title: title, description: desc, dueDate: dueDate),
      sharedWith: atSigns,
    );
    try {
      final results = await collection.put(item);
      log(
        'Created item ${item.id}. Success: ${results.every((r) => r is OpSuccess)}',
      );
      await refreshTodos();
    } catch (e) {
      log('Error creating todo: $e', error: true);
      await refreshTodos();
    }
  }

  Future<void> _handleUpdate(List<String> args) async {
    if (args.isEmpty) {
      log('Usage: update N');
      return;
    }
    final ref = _parseRef(args.first);
    if (ref == null || ref.noteIdx != null) {
      log('Invalid todo index');
      return;
    }
    if (ref.todoIdx < 0 || ref.todoIdx >= todos.length) {
      log('Invalid todo index');
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
    final atSigns =
        atSignsStr.isNotEmpty
            ? atSignsStr.split(',').map((e) => e.trim().toAtsign()).toSet()
            : <Atsign>{};

    final old = todos[ref.todoIdx];
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
    } catch (e) {
      log('Error updating todo: $e', error: true);
    } finally {
      await refreshTodos();
    }
  }

  Future<void> _handleDelete(List<String> args) async {
    if (args.isEmpty) {
      log('Usage: delete N (todo) or delete N.M (note M in todo N)');
      return;
    }
    final ref = _parseRef(args.first);
    if (ref == null) {
      log('Invalid reference "${args.first}"');
      return;
    }
    if (ref.todoIdx < 0 || ref.todoIdx >= todos.length) {
      log('Invalid todo index');
      return;
    }
    final todo = todos[ref.todoIdx];
    if (ref.noteIdx != null) {
      final notes = notesByTodoId[todo.id] ?? [];
      if (ref.noteIdx! < 0 || ref.noteIdx! >= notes.length) {
        log('Invalid note index');
        return;
      }
      final note = notes[ref.noteIdx!];
      if (note.owner != atClient.atSign) {
        log('Cannot delete notes owned by other atSigns');
        return;
      }
      try {
        final results = await notesCollection.delete(note);
        log('Note deleted. Success: ${results.every((r) => r is OpSuccess)}');
        await _refreshNotes();
      } catch (e) {
        log('Error deleting note: $e', error: true);
      }
    } else {
      log('Deleting todo: ${todo.obj.title}');
      try {
        final results = await collection.delete(todo);
        log('Deleted. Success: ${results.every((r) => r is OpSuccess)}');
        await refreshTodos();
      } catch (e) {
        log('Error deleting todo: $e', error: true);
      }
    }
  }

  Future<void> _handleDone(List<String> args) async {
    if (args.isEmpty) {
      log('Usage: done N');
      return;
    }
    final ref = _parseRef(args.first);
    if (ref == null || ref.noteIdx != null) {
      log('Invalid todo index');
      return;
    }
    if (ref.todoIdx < 0 || ref.todoIdx >= todos.length) {
      log('Invalid todo index');
      return;
    }
    final old = todos[ref.todoIdx];
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
      log(
        '"${old.obj.title}" marked ${updated.obj.done ? "done [x]" : "not done [ ]"}',
      );
      await refreshTodos();
    } catch (e) {
      log('Error toggling done: $e', error: true);
    }
  }

  Future<void> _handleDue(List<String> args) async {
    if (args.isEmpty) {
      log('Usage: due N [YYYY-MM-DD]');
      return;
    }
    final ref = _parseRef(args.first);
    if (ref == null || ref.noteIdx != null) {
      log('Invalid todo index');
      return;
    }
    if (ref.todoIdx < 0 || ref.todoIdx >= todos.length) {
      log('Invalid todo index');
      return;
    }
    final old = todos[ref.todoIdx];
    if (old.owner != atClient.atSign) {
      log('Cannot update todos owned by other atSigns');
      return;
    }
    final dateStr =
        args.length > 1
            ? args[1]
            : (await _prompt('Due date (YYYY-MM-DD)')).trim();
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
      log('Error setting due date: $e', error: true);
    }
  }

  Future<void> _handleNote(List<String> args) async {
    if (args.isEmpty) {
      log('Usage: note N [text...]');
      return;
    }
    final ref = _parseRef(args.first);
    if (ref == null || ref.noteIdx != null) {
      log('Invalid todo index');
      return;
    }
    if (ref.todoIdx < 0 || ref.todoIdx >= todos.length) {
      log('Invalid todo index');
      return;
    }
    final text =
        args.length > 1
            ? args.sublist(1).join(' ')
            : (await _prompt('Note text')).trim();
    if (text.isEmpty) {
      log('Note text cannot be empty');
      return;
    }
    final todo = todos[ref.todoIdx];
    final note = notesCollection.create(
      type: 'TodoNote',
      obj: TodoNote(note: text, todoId: todo.id),
      sharedWith: _noteAudience(todo),
    );
    try {
      final results = await notesCollection.put(note);
      log('Note added. Success: ${results.every((r) => r is OpSuccess)}');
      await _refreshNotes();
    } catch (e) {
      log('Error adding note: $e', error: true);
    }
  }

  Future<void> _handleUpdateNote(List<String> args) async {
    if (args.isEmpty) {
      log('Usage: updatenote N.M [text...]');
      return;
    }
    final ref = _parseRef(args.first);
    if (ref == null || ref.noteIdx == null) {
      log('Invalid note reference (expected N.M)');
      return;
    }
    if (ref.todoIdx < 0 || ref.todoIdx >= todos.length) {
      log('Invalid todo index');
      return;
    }
    final todo = todos[ref.todoIdx];
    final notes = notesByTodoId[todo.id] ?? [];
    if (ref.noteIdx! < 0 || ref.noteIdx! >= notes.length) {
      log('Invalid note index');
      return;
    }
    final existing = notes[ref.noteIdx!];
    if (existing.owner != atClient.atSign) {
      log('Cannot update notes owned by other atSigns');
      return;
    }
    final text =
        args.length > 1
            ? args.sublist(1).join(' ')
            : (await _prompt('New note text')).trim();
    if (text.isEmpty) {
      log('Cancelled');
      return;
    }
    final updated = notesCollection.create(
      type: 'TodoNote',
      obj: TodoNote(note: text, todoId: todo.id),
      id: existing.id,
      sharedWith: _noteAudience(todo),
    );
    try {
      final results = await notesCollection.put(updated);
      log('Note updated. Success: ${results.every((r) => r is OpSuccess)}');
      await _refreshNotes();
    } catch (e) {
      log('Error updating note: $e', error: true);
    }
  }

  Future<void> _handleShare(List<String> args) async {
    if (args.isEmpty) {
      log('Usage: share N [@sign1,@sign2]');
      return;
    }
    final ref = _parseRef(args.first);
    if (ref == null || ref.noteIdx != null) {
      log('Invalid todo index');
      return;
    }
    if (ref.todoIdx < 0 || ref.todoIdx >= todos.length) {
      log('Invalid todo index');
      return;
    }
    final item = todos[ref.todoIdx];
    if (item.owner != atClient.atSign) {
      log('Cannot share todos owned by other atSigns');
      return;
    }
    final atSignsStr =
        args.length > 1
            ? args.sublist(1).join(' ')
            : (await _prompt('Add recipients (comma-separated @signs)')).trim();
    if (atSignsStr.isEmpty) {
      log('No recipients specified');
      return;
    }
    final newAtSigns =
        atSignsStr.split(',').map((s) => s.trim().toAtsign()).toSet();
    item.sharedWith.addAll(newAtSigns);
    try {
      final results = await collection.put(item, unshareWithOthers: false);
      log(
        'Shared with ${_color.fmtAll(newAtSigns)}. Success: ${results.every((r) => r is OpSuccess)}',
      );
      await refreshTodos();
    } catch (e) {
      log('Error sharing: $e', error: true);
    }
  }

  Future<void> _handleSchedule(List<String> args) async {
    if (args.isEmpty) {
      log('Usage: schedule N [seconds]');
      return;
    }
    final ref = _parseRef(args.first);
    if (ref == null || ref.noteIdx != null) {
      log('Invalid todo index');
      return;
    }
    if (ref.todoIdx < 0 || ref.todoIdx >= todos.length) {
      log('Invalid todo index');
      return;
    }
    final item = todos[ref.todoIdx];
    if (item.owner != atClient.atSign) {
      log('Cannot schedule todos owned by other atSigns');
      return;
    }
    final secsStr =
        args.length > 1 ? args[1] : (await _prompt('Delay (seconds)')).trim();
    final seconds = int.tryParse(secsStr);
    if (seconds == null || seconds <= 0) {
      log('Seconds must be a positive integer');
      return;
    }
    final availableAt = DateTime.now().add(Duration(seconds: seconds));
    try {
      final results = await collection.put(item, availableAt: availableAt);
      log(
        'Scheduled "${item.obj.title}" available at '
        '${availableAt.toIso8601String().substring(0, 19)}. '
        'Success: ${results.every((r) => r is OpSuccess)}',
      );
      await refreshTodos();
    } catch (e) {
      log('Error scheduling: $e', error: true);
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
      log('Error fetching keys: $e', error: true);
    }
  }
}
