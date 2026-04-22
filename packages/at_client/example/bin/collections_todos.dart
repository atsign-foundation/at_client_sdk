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
  final int created;
  final int idx;
  final int st;
  final int title;
  final int desc;
  final int author;
  final int shared;
  final int readBy;

  const _Cols(
    this.due,
    this.created,
    this.idx,
    this.st,
    this.title,
    this.desc,
    this.author,
    this.shared,
    this.readBy,
  );

  // Overhead for a 9-column row: 10 '│' chars + 18 padding spaces = 28.
  static const int _overhead = 28;

  static _Cols compute(int totalWidth) {
    const due = 20;
    const created = 20;
    const idx = 3;
    const st = 3;
    const author = 20;
    final flex = (totalWidth - _overhead - due - created - idx - st - author)
        .clamp(30, 500);
    final title = (flex * 0.15).round().clamp(5, 200);
    // shared and readBy reduced by 60% from their previous 0.275 share.
    final shared = (flex * 0.11).round().clamp(5, 200);
    final readBy = (flex * 0.11).round().clamp(5, 200);
    final desc = (flex - title - shared - readBy).clamp(5, 200);
    return _Cols(due, created, idx, st, title, desc, author, shared, readBy);
  }

  int get totalWidth =>
      _overhead +
      due +
      created +
      idx +
      st +
      title +
      desc +
      author +
      shared +
      readBy;

  List<int> get widths => [
    due,
    created,
    idx,
    st,
    title,
    desc,
    author,
    shared,
    readBy,
  ];

  // Column at which the Title cell's content begins (0-based).
  // Layout per cell: '│ <content> '. Four fixed cells precede Title.
  int get titleStartCol => due + created + idx + st + 14;
}

class TodosApp {
  final AtClient atClient;
  late final AtCollection<Todo> collection;
  late final Terminal terminal;
  late final StdioBackend backend;
  late final _AtsignColors _color;

  final List<String> logMessages = [];
  List<CItem<Todo>> todos = [];
  Map<String, List<CItem<TodoNote>>> notesByTodoId = {};
  // Memoised per-todo notes sub-collection. Keyed by (owner, id) of
  // the parent todo to avoid clashing when two atSigns happen to pick
  // the same todo id.
  final Map<String, AtCollection<TodoNote>> _notesSubs = {};
  String currentInput = '';
  bool _running = false;
  bool _handlerRunning = false;
  int logScrollOffset = 0;
  String? _promptLabel;
  Completer<String>? _promptCompleter;

  TodosApp(this.atClient) {
    _color = _AtsignColors(atClient.atSign);
  }

  /// Builds the todos collection and sweeps orphans at startup.
  /// Called from [run] before entering the event loop. Notes are now
  /// per-todo sub-collections, constructed lazily by [_notesSubFor].
  Future<void> _initCollections() async {
    final ns = atClient.getPreferences()!.namespace!;
    collection = await atClient.collection<Todo>(
      'todos.$ns',
      const Duration(days: 365),
      fromJson: Todo.fromJson,
      cleanupOrphansOnCreation: true,
    );
    // Legacy-notes probe: prior versions of this TUI stored notes in
    // a sibling top-level collection `notes.$ns`. Notes now live as
    // sub-collections of each todo. Report any legacy keys without
    // migrating them (per the post-implementation tidy-up plan).
    try {
      final legacyRegex = '(^|:)[^.]+\\.notes\\.${ns.replaceAll('.', '\\.')}@';
      final legacyKeys = await atClient.getAtKeys(regex: legacyRegex);
      if (legacyKeys.isNotEmpty) {
        log(
          '${legacyKeys.length} legacy notes in "notes.$ns" '
          '(pre-subcollection shape) present; not displayed by this '
          'version. Data is preserved on the atServer.',
        );
      }
    } catch (_) {
      /* swallow — legacy probe is best-effort */
    }
  }

  /// Returns the memoised notes sub-collection for [todo], constructing
  /// it on first access. The cache key includes the todo's owner so
  /// same-id todos belonging to different atSigns get independent
  /// sub-collections.
  AtCollection<TodoNote> _notesSubFor(CItem<Todo> todo) {
    final key = '${todo.owner}:${todo.id}';
    return _notesSubs.putIfAbsent(
      key,
      () => collection.subCollection<TodoNote>(
        parent: todo,
        subName: 'notes',
        defaultExpiration: const Duration(days: 365),
        fromJson: TodoNote.fromJson,
      ),
    );
  }

  // Orange ANSI-256 colour for exception messages resulting directly from a
  // user command.
  static const String _errorAnsi = '\x1b[38;5;208m';

  void log(String message, {Atsign? by, bool error = false}) {
    if (message.contains('\n')) {
      message.split('\n').forEach((s) => log(s, by: by, error: error));
      return;
    }
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

  Future<void> refreshTodos({CEvent? event}) async {
    if (event != null) {
      log('refreshTodos due to event: $event');
    }
    try {
      final fetched = await collection.getItems();
      fetched.sort(_compareByDue);
      todos = fetched;
      for (final item in todos) {
        if (!(await item.wasMarkedReadByMe())) {
          await item.markReadByMe();
          log(
            'Read receipt sent to ${_color.fmt(item.owner)} for: ${item.obj.title}',
          );
        }
        // Prime the readBy cache so _draw()'s sync snapshot is populated.
        await item.readBy;
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

  Future<void> _refreshNotes({CEvent? event}) async {
    if (event != null) {
      log('_refreshNotes due to event: $event');
    }
    try {
      final next = <String, List<CItem<TodoNote>>>{};
      for (final todo in todos) {
        final sub = _notesSubFor(todo);
        final items = await sub.getItems();
        if (items.isNotEmpty) {
          next[todo.id] = items;
          for (final n in items) {
            if (!(await n.wasMarkedReadByMe())) {
              await n.markReadByMe();
            }
          }
        }
      }
      notesByTodoId = next;
      _draw();
    } catch (e, st) {
      log('Error refreshing notes: $e\n$st');
    }
  }

  Future<void> run() async {
    await _initCollections();

    backend = StdioBackend();
    terminal = Terminal(backend);

    terminal.enterAlternateScreen();
    terminal.hideCursor();
    terminal.clear();
    backend.enableRawMode();

    _running = true;

    collection.readReceipts.listen((e) {
      log('sent us a read receipt', by: e.from);
      unawaited(refreshTodos());
    });
    collection.updates.listen((e) => unawaited(refreshTodos(event: e)));
    collection.deletes.listen((e) => unawaited(refreshTodos(event: e)));
    // Notes are sub-items of the todos collection. Filter by
    // ancestry.last.subName == 'notes' so we don't also react to
    // __rr read-receipt sub-updates.
    collection.subUpdates
        .where((e) => e.subName == 'notes')
        .listen((e) => unawaited(_refreshNotes(event: e)));
    collection.subDeletes
        .where((e) => e.subName == 'notes')
        .listen((e) => unawaited(_refreshNotes(event: e)));

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

  static const int _logHeight = 10;

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
          'Created',
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
                ? todo.obj.dueDate!
                    .toIso8601String()
                    .substring(0, 19)
                    .replaceFirst('T', ' ')
                : '-';
        final createdStr = todo.createdAt
            .toIso8601String()
            .substring(0, 19)
            .replaceFirst('T', ' ');
        final idxStr = '${i + 1}';
        final stStr = todo.obj.done ? '[x]' : '[ ]';
        final authorStr = _color.fmt(todo.owner);
        final sharedStr =
            todo.sharedWith.isEmpty ? '-' : _color.fmtAll(todo.sharedWith);
        final readers = todo.readBySnapshot;
        final readByStr =
            readers.isEmpty
                ? (todo.sharedWith.isEmpty ? '-' : '(nobody)')
                : _color.fmtAll(readers);
        row = _drawTableRowSingle(row, tableWidth, cols, [
          dueStr,
          createdStr,
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
          final createdStr = n.createdAt
              .toIso8601String()
              .substring(0, 19)
              .replaceFirst('T', ' ');
          final text =
              '[n${ni + 1}] (${_color.fmt(n.owner)}, $createdStr) "${n.obj.note}"';
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
    try {
      final item = await collection.create(
        obj: Todo(title: title, description: desc, dueDate: dueDate),
        sharedWith: atSigns,
      );
      log('Created item ${item.id}.');
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
    try {
      await collection.update(
        collection.draft(
          obj: Todo(
            title: title,
            description: desc,
            done: old.obj.done,
            dueDate: old.obj.dueDate,
          ),
          id: old.id,
          sharedWith: atSigns,
        ),
      );
      log('Updated.');
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
        await _notesSubFor(todo).delete(note);
        log('Note deleted.');
        await _refreshNotes();
      } catch (e) {
        log('Error deleting note: $e', error: true);
      }
    } else {
      log('Deleting todo: ${todo.obj.title}');
      try {
        await collection.delete(todo, cascade: true);
        log('Deleted.');
        await refreshTodos();
        await _refreshNotes();
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
    try {
      final updated = collection.draft(
        obj: Todo(
          title: old.obj.title,
          description: old.obj.description,
          done: !old.obj.done,
          dueDate: old.obj.dueDate,
        ),
        id: old.id,
        sharedWith: Set.from(old.sharedWith),
      );
      await collection.update(updated);
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
    try {
      await collection.update(
        collection.draft(
          obj: Todo(
            title: old.obj.title,
            description: old.obj.description,
            done: old.obj.done,
            dueDate: dueDate,
          ),
          id: old.id,
          sharedWith: Set.from(old.sharedWith),
        ),
      );
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
    try {
      await _notesSubFor(
        todo,
      ).create(obj: TodoNote(note: text), sharedWith: _noteAudience(todo));
      log('Note added.');
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
    try {
      final sub = _notesSubFor(todo);
      await sub.update(
        sub.draft(
          obj: TodoNote(note: text),
          id: existing.id,
          sharedWith: _noteAudience(todo),
        ),
      );
      log('Note updated.');
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
      await collection.update(item, unshareWithOthers: false);
      log('Shared with ${_color.fmtAll(newAtSigns)}.');
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
    item.availableAt = availableAt;
    try {
      await collection.update(item);
      log(
        'Scheduled "${item.obj.title}" available at '
        '${availableAt.toIso8601String().substring(0, 19)}.',
      );
      await refreshTodos();
    } catch (e) {
      log('Error scheduling: $e', error: true);
    }
  }

  Future<void> _handleKeys() async {
    try {
      final todoKeys = await collection.getKeys();
      log('--- Todo keys (${todoKeys.length}) ---');
      for (final k in todoKeys) {
        log('  ${k.fullKeyAndOwner}');
      }
      // Notes now live as per-todo sub-collection items — scan each.
      var totalNoteKeys = 0;
      for (final todo in todos) {
        final noteKeys = await _notesSubFor(todo).getKeys();
        totalNoteKeys += noteKeys.length;
      }
      log('--- Note keys (across todos: $totalNoteKeys) ---');
      for (final todo in todos) {
        final noteKeys = await _notesSubFor(todo).getKeys();
        for (final k in noteKeys) {
          log('  ${k.fullKeyAndOwner}');
        }
      }
    } catch (e) {
      log('Error fetching keys: $e', error: true);
    }
  }
}
