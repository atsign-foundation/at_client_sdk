import 'dart:async';
import 'dart:io';

import 'package:at_cli_commons/at_cli_commons.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client_examples/domain_objects.dart';
import 'package:at_client_examples/todos_tui/presets.dart';
import 'package:at_client_examples/todos_tui/theme.dart';
import 'package:at_client_examples/todos_tui/types.dart';
import 'package:nocterm/nocterm.dart';

void main(List<String> args) async {
  final AtClient atClient =
      (await CLIBase.fromCommandLineArgs(
        args,
        namespace: 'todos.demos',
      )).atClient;

  // Default read preference is local — the at_client SDK keeps a
  // real-time-synced local cache per atSign, so `query().watch()`
  // emissions resolve against on-device storage rather than the
  // remote atServer. No override needed here.

  await runApp(TodosApp(atClient: atClient));
  exit(0);
}

// Shared TUI types / presets / theme live under
// `example/lib/todos_tui/` and are re-exported above via the package
// imports. See `presets.dart`, `theme.dart`, and `types.dart`.

// -----------------------------------------------------------------------------
// TodosApp — root `StatefulComponent`. Milestone 1 scaffold: basic
// header / list / detail / log / footer layout, arrow-key list
// navigation, `q` to quit. No commands wired yet; later milestones add
// command menu (M4), modal forms (M5), find bar + shortcuts (M6).

class TodosApp extends StatefulComponent {
  final AtClient atClient;

  const TodosApp({required this.atClient, super.key});

  @override
  State<TodosApp> createState() => _TodosAppState();
}

class _TodosAppState extends State<TodosApp> {
  AtClient get atClient => component.atClient;
  late final AtCollection<Todo> collection;
  late final TodoTheme _theme = TodoTheme(atClient.atSign);

  // ---- State ----
  final List<String> logMessages = [];
  List<CItem<Todo>> todos = [];
  Map<String, List<CItem<TodoNote>>> notesByTodoId = {};
  // Memoised per-todo notes sub-collection — keyed by (owner, id) of
  // the parent so same-id todos across atSigns get independent subs.
  final Map<String, AtCollection<TodoNote>> _notesSubs = {};

  // Active preset + sort direction for the list view. Reassigned by
  // the filter / reverse commands in a later milestone.
  // ignore: prefer_final_fields
  String _activePresetName = 'all';
  // ignore: prefer_final_fields
  bool _reverseSort = false;

  // Which todo row is currently selected (index into [todos]).
  int _selectedIdx = 0;
  // Which pane is currently keyboard-focused. `list` is the default;
  // `Enter` or Right-arrow moves focus to the detail pane so the user
  // can scroll through its contents; `Esc` or Left-arrow comes back.
  Pane _activePane = Pane.list;
  // Which modal (if any) is overlaying the main view. While non-
  // [Modal.none], keyboard events are routed to the modal instead
  // of the list/detail handlers.
  Modal _modal = Modal.none;
  // Command-menu state — live filter text and selected row index in
  // the filtered list.
  String _cmdMenuQuery = '';
  int _cmdMenuIdx = 0;
  // Modal-form state. Each form is described by a list of field
  // labels and a parallel list of current text values; the user
  // types into `_formFieldIdx`-th field and presses Tab / Enter to
  // advance. The target todo (when editing / adding a note to an
  // existing one) is held in [_formTarget]. Simpler than wiring
  // nocterm's TextField focus system for every field, and identical
  // to the "type into a slot" mental model of the previous inline-
  // prompt TUI.
  List<String> _formLabels = const [];
  List<String> _formValues = const [];
  int _formFieldIdx = 0;
  CItem<Todo>? _formTarget;
  // Live-narrow search overlay. When [_modal] is [Modal.find], the
  // user types into [_findQuery] and the list pane renders a
  // `.where(title contains)` composition of the active preset's
  // query. Empty string → full unfiltered list. Esc closes and
  // clears.
  String _findQuery = '';

  // Init state — the app renders a "Loading…" placeholder until
  // `_setup()` completes, or an error screen if init failed.
  bool _ready = false;
  String? _initError;

  // ---- Subscriptions ----
  StreamSubscription<List<TodoWithNotes>>? _todosSub;
  StreamSubscription<int>? _openCountSub;
  StreamSubscription<int>? _overdueCountSub;
  StreamSubscription<int>? _sharedCountSub;
  StreamSubscription<CReadReceipt>? _receiptsTickerSub;
  StreamSubscription<List<CItem<Todo>>>? _nextDueSub;
  // Detail-pane read-by timeline — subscribes to the selected
  // todo's `__rr` sub-collection via the public `item.receipts`
  // handle, re-subscribes when the selection changes.
  StreamSubscription<List<CItem<Map<String, dynamic>>>>? _detailReceiptsSub;
  List<CItem<Map<String, dynamic>>> _detailReceipts = [];
  String _detailItemKey = ''; // "<owner>:<id>" of the subscribed item

  // ---- Derived counts rendered in the header ----
  int _countOpen = 0;
  int _countOverdue = 0;
  int _countSharedWithMe = 0;
  String _nextDueLabel = '';

  @override
  void initState() {
    super.initState();
    unawaited(_setup());
  }

  @override
  void dispose() {
    _todosSub?.cancel();
    _openCountSub?.cancel();
    _overdueCountSub?.cancel();
    _sharedCountSub?.cancel();
    _receiptsTickerSub?.cancel();
    _nextDueSub?.cancel();
    _detailReceiptsSub?.cancel();
    super.dispose();
  }

  /// Ensures [_detailReceiptsSub] is subscribed to the currently-
  /// selected todo's receipts sub-collection. Idempotent — a second
  /// call with the same selection is a no-op.
  void _subscribeSelectedReceipts() {
    if (todos.isEmpty || _selectedIdx < 0 || _selectedIdx >= todos.length) {
      _detailReceiptsSub?.cancel();
      _detailReceiptsSub = null;
      _detailItemKey = '';
      if (mounted && _detailReceipts.isNotEmpty) {
        setState(() => _detailReceipts = const []);
      }
      return;
    }
    final item = todos[_selectedIdx];
    final key = '${item.owner}:${item.id}';
    if (key == _detailItemKey) return;
    _detailReceiptsSub?.cancel();
    _detailItemKey = key;
    // Reset the cached list synchronously so the UI doesn't flash the
    // previous item's readers while we wait for the first emission.
    if (mounted) setState(() => _detailReceipts = const []);
    _detailReceiptsSub = item.receipts
        .query()
        .orderBy((r) => r.createdAt)
        .watch()
        .listen((list) {
          if (!mounted) return;
          setState(() => _detailReceipts = list);
        }, onError: (Object e) => log('receipts stream: $e', error: true));
  }

  /// Full startup chain: open the collection, install the live stream
  /// subscriptions, flip to `_ready`. Runs once from [initState] via
  /// `unawaited(...)`; while it's in flight the app shows a loading
  /// placeholder.
  Future<void> _setup() async {
    try {
      await _initCollections();
      await _applyActiveQuery();
      _setupCountStreams();
      _setupNextDueStream();
      _setupReceiptsTicker();
      if (mounted) setState(() => _ready = true);
    } catch (e, st) {
      if (mounted) setState(() => _initError = '$e\n$st');
    }
  }

  // ---------------------------------------------------------------------------
  // Domain wiring — collection setup + stream subscriptions

  Future<void> _initCollections() async {
    final ns = atClient.getPreferences()!.namespace!;
    collection = await atClient.collection<Todo>(
      'todos.$ns',
      const Duration(days: 365),
      fromJson: Todo.fromJson,
      typeTag: 'Todo',
      cleanupOrphansOnCreation: true,
    );
    // Legacy-notes probe: prior versions stored notes in a sibling
    // top-level collection; report any surviving keys without
    // migrating them.
    try {
      final legacyRegex = '(^|:)[^.]+\\.notes\\.${ns.replaceAll('.', '\\.')}@';
      final legacyKeys = await atClient.getAtKeys(regex: legacyRegex);
      if (legacyKeys.isNotEmpty) {
        log(
          '${legacyKeys.length} legacy notes in "notes.$ns" '
          '(pre-subcollection shape) present; not displayed. Data is '
          'preserved on the atServer.',
        );
      }
    } catch (_) {
      /* best-effort probe */
    }
  }

  /// Memoised notes sub-collection for [todo]. Cache key includes
  /// owner so same-id todos across atSigns get independent subs.
  AtCollection<TodoNote> _notesSubFor(CItem<Todo> todo) {
    final key = '${todo.owner}:${todo.id}';
    return _notesSubs.putIfAbsent(
      key,
      () => collection.subCollection<TodoNote>(
        parent: todo,
        subName: 'notes',
        defaultExpiration: const Duration(days: 365),
        fromJson: TodoNote.fromJson,
        typeTag: 'TodoNote',
      ),
    );
  }

  /// Builds the current `Query<Todo>` from active preset + reverse
  /// flag, with the find-bar substring composed in as a further
  /// `.where(title contains)` predicate when non-empty. Stream-
  /// composing this into `watchWithSub` means typing in the find
  /// bar narrows the visible list live.
  Query<Todo> _buildQuery() {
    final preset = todoPresetsByName[_activePresetName]!;
    var q = preset.build(collection, atClient.atSign, _reverseSort);
    final needle = _findQuery.trim().toLowerCase();
    if (needle.isNotEmpty) {
      q = q.where((t) => t.obj.title.toLowerCase().contains(needle));
    }
    return q;
  }

  /// (Re-)subscribes [_todosSub] to a single `watchWithSub` stream
  /// carrying parents + notes together. Re-created on filter/reverse
  /// changes.
  Future<void> _applyActiveQuery() async {
    await _todosSub?.cancel();
    _todosSub = _buildQuery()
        .watchWithSub<TodoNote>(
          subName: 'notes',
          subDefaultExpiration: const Duration(days: 365),
          subFromJson: TodoNote.fromJson,
          subTypeTag: 'TodoNote',
        )
        .listen(
          _onCombinedSnapshot,
          onError: (Object e) => log('Error on todos stream: $e', error: true),
        );
  }

  /// Applies an incoming snapshot to state: updates todos +
  /// notesByTodoId, sends pending read-receipts, primes readBy,
  /// clamps the selection index, schedules a redraw via [setState].
  Future<void> _onCombinedSnapshot(List<TodoWithNotes> snapshot) async {
    final nextTodos = [for (final r in snapshot) r.parent];
    final nextNotes = <String, List<CItem<TodoNote>>>{};
    for (final r in snapshot) {
      if (r.children.isNotEmpty) nextNotes[r.parent.id] = r.children;
    }
    // Mark unseen parents + children as read and prime readBy so
    // detail-pane snapshots render the latest reader list.
    for (final r in snapshot) {
      if (!(await r.parent.wasMarkedReadByMe())) {
        await r.parent.markReadByMe();
      }
      await r.parent.readBy;
      for (final note in r.children) {
        if (!(await note.wasMarkedReadByMe())) {
          await note.markReadByMe();
        }
      }
    }
    if (!mounted) return;
    setState(() {
      todos = nextTodos;
      notesByTodoId = nextNotes;
      if (_selectedIdx >= todos.length) {
        _selectedIdx = todos.isEmpty ? 0 : todos.length - 1;
      }
    });
    _subscribeSelectedReceipts();
  }

  /// One-shot fetch of the active query (parents + notes), pumped
  /// through the same snapshot handler the live stream uses. Called
  /// by write-path command handlers for immediate UI feedback.
  Future<void> refreshTodos() async {
    try {
      final parents = await _buildQuery().get();
      final combined = <TodoWithNotes>[];
      for (final p in parents) {
        final notes = await _notesSubFor(p).query().get();
        combined.add(WithChildren(parent: p, children: notes));
      }
      await _onCombinedSnapshot(combined);
    } catch (e) {
      log('Error refreshing todos: $e', error: true);
    }
  }

  void _setupCountStreams() {
    _openCountSub = todoPresetsByName['open']!
        .build(collection, atClient.atSign, false)
        .watch()
        .map((l) => l.length)
        .listen((n) {
          if (!mounted) return;
          setState(() => _countOpen = n);
        });
    _overdueCountSub = todoPresetsByName['overdue']!
        .build(collection, atClient.atSign, false)
        .watch()
        .map((l) => l.length)
        .listen((n) {
          if (!mounted) return;
          setState(() => _countOverdue = n);
        });
    _sharedCountSub = todoPresetsByName['shared']!
        .build(collection, atClient.atSign, false)
        .watch()
        .map((l) => l.length)
        .listen((n) {
          if (!mounted) return;
          setState(() => _countSharedWithMe = n);
        });
  }

  void _setupNextDueStream() {
    _nextDueSub = todoPresetsByName['open']!
        .build(collection, atClient.atSign, false)
        .watch()
        .listen((open) {
          if (!mounted) return;
          setState(() {
            if (open.isEmpty) {
              _nextDueLabel = '';
            } else {
              final next = open.first;
              final due = next.obj.dueDate;
              final dueStr =
                  due == null
                      ? 'no date'
                      : due.toIso8601String().substring(0, 10);
              _nextDueLabel = '"${next.obj.title}" ($dueStr)';
            }
          });
        });
  }

  void _setupReceiptsTicker() {
    _receiptsTickerSub = collection.readReceipts.listen((e) {
      if (e.from == atClient.atSign) return;
      String title = '(id ${e.id})';
      for (final t in todos) {
        if (t.id == e.id && t.owner == e.owner) {
          title = t.obj.title;
          break;
        }
      }
      log('${e.from} just read "$title"');
    });
  }

  /// Appends a timestamped message to the in-memory log. Called from
  /// many places (setup, streams, handlers); safe to invoke before the
  /// widget tree is attached.
  void log(String message, {Atsign? by, bool error = false}) {
    final who = by ?? atClient.atSign;
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    final prefix = error ? 'ERR ' : '';
    if (mounted) {
      setState(() {
        logMessages.add('$ts $prefix$who: $message');
        if (logMessages.length > 200) logMessages.removeAt(0);
      });
    } else {
      logMessages.add('$ts $prefix$who: $message');
      if (logMessages.length > 200) logMessages.removeAt(0);
    }
  }

  // ---------------------------------------------------------------------------
  // Build — widget tree

  // Minimum terminal size below which the layout clips badly:
  // - Footer hint line is ~93 chars long.
  // - Header (3) + log pane (10) + footer (1) = 14 rows of fixed
  //   chrome, leaving room for a usable list/detail pane and a
  //   centred form-modal stack.
  static const int _minCols = 95;
  static const int _minRows = 28;

  @override
  Component build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth.toInt();
        final rows = constraints.maxHeight.toInt();
        if (cols < _minCols || rows < _minRows) {
          return _tooSmallView(cols, rows);
        }
        if (_initError != null) {
          return _errorView(_initError!);
        }
        if (!_ready) {
          return _loadingView();
        }
        return _mainView();
      },
    );
  }

  Component _tooSmallView(int cols, int rows) => Focusable(
    focused: true,
    onKeyEvent: _onGlobalKey,
    child: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Terminal too small',
            style: TextStyle(
              color: Colors.yellow,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            'Current: ${cols}x$rows',
            style: TextStyle(color: Colors.gray),
          ),
          Text(
            'Minimum: ${_minCols}x$_minRows',
            style: TextStyle(color: Colors.gray),
          ),
          const SizedBox(height: 1),
          Text(
            'Resize the window and the UI will recover automatically.',
            style: TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 1),
          Text('Press q to quit', style: TextStyle(color: Colors.gray)),
        ],
      ),
    ),
  );

  Component _errorView(String msg) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Init failed',
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 1),
        Text(msg, style: TextStyle(color: Colors.red)),
        const SizedBox(height: 2),
        Text('Press q to quit', style: TextStyle(color: Colors.gray)),
      ],
    ),
  );

  Component _loadingView() => Focusable(
    focused: true,
    onKeyEvent: _onGlobalKey,
    child: Center(
      child: Text(
        'Loading…',
        style: TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold),
      ),
    ),
  );

  Component _mainView() => Focusable(
    focused: true,
    onKeyEvent: _onTopKey,
    child: Stack(
      children: [
        // Main layout — always rendered underneath any modal.
        Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Row(
                children: [
                  Expanded(flex: 2, child: _buildListPane()),
                  Expanded(flex: 3, child: _buildDetailPane()),
                ],
              ),
            ),
            _buildLogPane(),
            _buildFooterBar(),
          ],
        ),
        // Modal overlay (if any). Rendered above the main content
        // with a dimmed barrier that obscures text beneath.
        if (_modal != Modal.none) _buildModal(),
      ],
    ),
  );

  /// Top-level key dispatcher. Routes to the active modal handler if
  /// one is open; otherwise to the pane-level handler [_onGlobalKey].
  /// `q` and `?` are handled globally so they work in any mode.
  bool _onTopKey(KeyboardEvent event) {
    if (_modal == Modal.commandMenu) return _onCommandMenuKey(event);
    if (_modal == Modal.help) return _onHelpKey(event);
    if (_modal == Modal.confirmDeleteTodo) return _onConfirmKey(event);
    if (_modal == Modal.find) return _onFindKey(event);
    if (_modal == Modal.createTodo ||
        _modal == Modal.editTodo ||
        _modal == Modal.addNote ||
        _modal == Modal.share ||
        _modal == Modal.schedule ||
        _modal == Modal.setDue) {
      return _onFormKey(event);
    }
    // Global shortcuts available from any pane:
    if (event.character == '?') {
      setState(() => _modal = Modal.help);
      return true;
    }
    if (event.character == '/') {
      _openFindBar();
      return true;
    }
    if (event.logicalKey == LogicalKey.keyM && event.isAltPressed) {
      _openCommandMenu();
      return true;
    }
    // List-pane single-key shortcuts. These fire in the list context
    // only, so they don't interfere with the detail pane's reserved
    // keys. Each dispatches into the same action path as the
    // corresponding command-menu entry.
    if (_activePane == Pane.list) {
      if (event.logicalKey == LogicalKey.keyM &&
          !event.isShiftPressed &&
          !event.isControlPressed) {
        _openCommandMenu();
        return true;
      }
      if (event.logicalKey == LogicalKey.keyC &&
          !event.isShiftPressed &&
          !event.isControlPressed) {
        _openCreateForm();
        return true;
      }
      if (event.logicalKey == LogicalKey.keyE &&
          !event.isShiftPressed &&
          !event.isControlPressed) {
        _openEditForm();
        return true;
      }
      if (event.logicalKey == LogicalKey.keyD &&
          !event.isShiftPressed &&
          !event.isControlPressed) {
        _openConfirmDeleteForm();
        return true;
      }
      if (event.logicalKey == LogicalKey.keyN &&
          !event.isShiftPressed &&
          !event.isControlPressed) {
        _openAddNoteForm();
        return true;
      }
      if (event.logicalKey == LogicalKey.keyS && event.isShiftPressed) {
        _openScheduleForm();
        return true;
      }
      if (event.logicalKey == LogicalKey.keyS &&
          !event.isShiftPressed &&
          !event.isControlPressed) {
        _openShareForm();
        return true;
      }
      if (event.logicalKey == LogicalKey.keyU &&
          !event.isShiftPressed &&
          !event.isControlPressed) {
        _openSetDueForm();
        return true;
      }
      if (event.logicalKey == LogicalKey.keyR &&
          !event.isShiftPressed &&
          !event.isControlPressed) {
        _cmdToggleReverse();
        return true;
      }
      if (event.logicalKey == LogicalKey.space) {
        unawaited(_cmdToggleDone());
        return true;
      }
    }
    return _onGlobalKey(event);
  }

  bool _onGlobalKey(KeyboardEvent event) {
    // Global keys — active regardless of pane focus.
    if (event.logicalKey == LogicalKey.keyQ) {
      shutdownApp();
      return true;
    }
    if (_activePane == Pane.list) {
      return _onListKey(event);
    } else {
      return _onDetailKey(event);
    }
  }

  bool _onListKey(KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.arrowUp ||
        event.logicalKey == LogicalKey.keyK) {
      if (_selectedIdx > 0) {
        setState(() => _selectedIdx--);
        _subscribeSelectedReceipts();
      }
      return true;
    }
    if (event.logicalKey == LogicalKey.arrowDown ||
        event.logicalKey == LogicalKey.keyJ) {
      if (_selectedIdx < todos.length - 1) {
        setState(() => _selectedIdx++);
        _subscribeSelectedReceipts();
      }
      return true;
    }
    if (event.logicalKey == LogicalKey.keyG) {
      if (todos.isEmpty) return true;
      setState(
        () => _selectedIdx = event.isShiftPressed ? todos.length - 1 : 0,
      );
      _subscribeSelectedReceipts();
      return true;
    }
    if (event.logicalKey == LogicalKey.enter ||
        event.logicalKey == LogicalKey.arrowRight ||
        event.logicalKey == LogicalKey.keyL) {
      if (todos.isNotEmpty) {
        setState(() => _activePane = Pane.detail);
      }
      return true;
    }
    return false;
  }

  bool _onDetailKey(KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.escape ||
        event.logicalKey == LogicalKey.arrowLeft ||
        event.logicalKey == LogicalKey.keyH) {
      setState(() => _activePane = Pane.list);
      return true;
    }
    // Scrolling / note navigation inside the detail pane comes in a
    // later milestone. For now the pane is read-only once focused.
    return false;
  }

  // ---------------------------------------------------------------------------
  // Command menu / help overlay

  /// The full command list. Order here drives the menu's display
  /// order; typing in the menu filters by substring over [label].
  /// Later milestones add form-backed entries like "Create todo"
  /// that open a modal form instead of running directly.
  List<Command> _commands() => [
    (label: 'Create todo', hint: 'c', invoke: _openCreateForm),
    (label: 'Edit selected todo', hint: 'e', invoke: _openEditForm),
    (label: 'Delete selected todo', hint: 'd', invoke: _openConfirmDeleteForm),
    (label: 'Toggle done on selected', hint: 'space', invoke: _cmdToggleDone),
    (label: 'Add note to selected', hint: 'n', invoke: _openAddNoteForm),
    (label: 'Share selected (add atSigns)', hint: 's', invoke: _openShareForm),
    (label: 'Set due date on selected', hint: 'u', invoke: _openSetDueForm),
    (
      label: 'Schedule selected (availableAt)',
      hint: 'S',
      invoke: _openScheduleForm,
    ),
    (label: 'Filter: All', hint: '', invoke: () => _cmdSetPreset('all')),
    (label: 'Filter: Mine', hint: '', invoke: () => _cmdSetPreset('mine')),
    (
      label: 'Filter: Shared with me',
      hint: '',
      invoke: () => _cmdSetPreset('shared'),
    ),
    (label: 'Filter: Open', hint: '', invoke: () => _cmdSetPreset('open')),
    (label: 'Filter: Done', hint: '', invoke: () => _cmdSetPreset('done')),
    (
      label: 'Filter: Overdue',
      hint: '',
      invoke: () => _cmdSetPreset('overdue'),
    ),
    (label: 'Reverse sort direction', hint: 'r', invoke: _cmdToggleReverse),
    (label: 'Cleanup orphans', hint: '', invoke: _cmdCleanup),
    (label: 'Stats', hint: '', invoke: _cmdStats),
    (
      label: 'Find (live-narrow list by title)',
      hint: '/',
      invoke: _openFindBar,
    ),
    (
      label: 'Help',
      hint: '?',
      invoke: () => setState(() => _modal = Modal.help),
    ),
    (label: 'Quit', hint: 'q', invoke: shutdownApp),
  ];

  List<Command> _filteredCommands() {
    final q = _cmdMenuQuery.trim().toLowerCase();
    if (q.isEmpty) return _commands();
    return _commands().where((c) => c.label.toLowerCase().contains(q)).toList();
  }

  void _openCommandMenu() {
    setState(() {
      _modal = Modal.commandMenu;
      _cmdMenuQuery = '';
      _cmdMenuIdx = 0;
    });
  }

  /// Opens the live-narrow find bar. The bar is a thin overlay
  /// anchored at the bottom of the main area; every keystroke
  /// rebuilds the active query with a `.where(title contains)`
  /// predicate so the list filters in real time.
  void _openFindBar() {
    setState(() {
      _modal = Modal.find;
      _findQuery = '';
    });
    unawaited(_applyActiveQuery());
  }

  bool _onFindKey(KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.escape) {
      setState(() {
        _modal = Modal.none;
        _findQuery = '';
      });
      unawaited(_applyActiveQuery());
      return true;
    }
    if (event.logicalKey == LogicalKey.enter) {
      // Leave the narrow in place; just close the bar so the list
      // behaves normally until the user hits `/` again.
      setState(() => _modal = Modal.none);
      return true;
    }
    if (event.logicalKey == LogicalKey.backspace) {
      if (_findQuery.isNotEmpty) {
        setState(
          () => _findQuery = _findQuery.substring(0, _findQuery.length - 1),
        );
        unawaited(_applyActiveQuery());
      }
      return true;
    }
    final ch = event.character;
    if (ch != null && ch.length == 1 && ch.codeUnitAt(0) >= 32) {
      setState(() => _findQuery = _findQuery + ch);
      unawaited(_applyActiveQuery());
      return true;
    }
    return false;
  }

  bool _onCommandMenuKey(KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.escape) {
      setState(() => _modal = Modal.none);
      return true;
    }
    final items = _filteredCommands();
    if (event.logicalKey == LogicalKey.arrowUp) {
      if (_cmdMenuIdx > 0) setState(() => _cmdMenuIdx--);
      return true;
    }
    if (event.logicalKey == LogicalKey.arrowDown) {
      if (_cmdMenuIdx < items.length - 1) {
        setState(() => _cmdMenuIdx++);
      }
      return true;
    }
    if (event.logicalKey == LogicalKey.enter) {
      if (items.isNotEmpty && _cmdMenuIdx >= 0 && _cmdMenuIdx < items.length) {
        final chosen = items[_cmdMenuIdx];
        setState(() => _modal = Modal.none);
        unawaited(Future.sync(chosen.invoke));
      }
      return true;
    }
    if (event.logicalKey == LogicalKey.backspace) {
      if (_cmdMenuQuery.isNotEmpty) {
        setState(() {
          _cmdMenuQuery = _cmdMenuQuery.substring(0, _cmdMenuQuery.length - 1);
          _cmdMenuIdx = 0;
        });
      }
      return true;
    }
    // Any printable character extends the filter.
    final ch = event.character;
    if (ch != null && ch.length == 1 && ch.codeUnitAt(0) >= 32) {
      setState(() {
        _cmdMenuQuery = _cmdMenuQuery + ch;
        _cmdMenuIdx = 0;
      });
      return true;
    }
    return false;
  }

  bool _onHelpKey(KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.escape ||
        event.character == '?' ||
        event.logicalKey == LogicalKey.enter) {
      setState(() => _modal = Modal.none);
      return true;
    }
    return false;
  }

  // ---- Command action methods ----

  void _cmdSetPreset(String name) {
    if (_activePresetName == name) return;
    setState(() => _activePresetName = name);
    unawaited(_applyActiveQuery());
    log('Active preset: ${todoPresetsByName[name]!.label}');
  }

  void _cmdToggleReverse() {
    setState(() => _reverseSort = !_reverseSort);
    unawaited(_applyActiveQuery());
    log('Sort direction: ${_reverseSort ? "descending" : "ascending"}');
  }

  Future<void> _cmdToggleDone() async {
    if (todos.isEmpty || _selectedIdx < 0 || _selectedIdx >= todos.length) {
      log('No todo selected.', error: true);
      return;
    }
    final t = todos[_selectedIdx];
    if (t.owner != atClient.atSign) {
      log("Can't toggle done on ${t.owner}'s todo.", error: true);
      return;
    }
    try {
      final updated = collection.draft(
        obj: Todo(
          title: t.obj.title,
          description: t.obj.description,
          done: !t.obj.done,
          dueDate: t.obj.dueDate,
        ),
        id: t.id,
        sharedWith: Set.from(t.sharedWith),
      );
      await collection.update(updated);
      log('"${t.obj.title}" marked ${updated.obj.done ? "done" : "not done"}');
      await refreshTodos();
    } catch (e) {
      log('toggle done: $e', error: true);
    }
  }

  Future<void> _cmdCleanup() async {
    try {
      final results = await collection.cleanupOrphans();
      if (results.isEmpty) {
        log('cleanupOrphans: nothing to sweep.');
        return;
      }
      final ok = results.whereType<OpSuccess>().length;
      final fail = results.whereType<OpFailure>().length;
      log('cleanupOrphans: $ok reclaimed, $fail failed.');
    } catch (e) {
      log('cleanup: $e', error: true);
    }
  }

  Future<void> _cmdStats() async {
    try {
      final base = collection.query();
      final all = await base.count();
      final open = await base.where((t) => !t.obj.done).count();
      final done = await base.where((t) => t.obj.done).count();
      final hasOverdue = await base.any(
        (t) =>
            !t.obj.done && (t.obj.dueDate?.isBefore(DateTime.now()) ?? false),
      );
      final oldest = await base.orderBy((t) => t.createdAt).firstOrNull();
      final byOwner = await base.groupBy<Atsign>((t) => t.owner);
      log('── stats ──');
      log('Total: $all  ·  Open: $open  ·  Done: $done');
      log('Any overdue open? ${hasOverdue ? "yes" : "no"}');
      if (oldest != null) {
        log(
          'Oldest: "${oldest.obj.title}" (${_fmtDateTime(oldest.createdAt)})',
        );
      }
      for (final entry in byOwner.entries) {
        log('  ${entry.key}: ${entry.value.length}');
      }
    } catch (e) {
      log('stats: $e', error: true);
    }
  }

  // ---- Modal widget builders ----

  Component _buildModal() {
    switch (_modal) {
      case Modal.commandMenu:
        return _buildCommandMenu();
      case Modal.help:
        return _buildHelpOverlay();
      case Modal.createTodo:
        return _buildFormModal('New todo');
      case Modal.editTodo:
        return _buildFormModal('Edit todo');
      case Modal.addNote:
        return _buildFormModal(
          'Add note to "${_formTarget?.obj.title ?? "…"}"',
        );
      case Modal.share:
        return _buildFormModal(
          'Share "${_formTarget?.obj.title ?? "…"}"',
          hint: 'Enter comma-separated atSigns  ·  ⏎ submit  ·  Esc cancel',
        );
      case Modal.schedule:
        return _buildFormModal(
          'Schedule "${_formTarget?.obj.title ?? "…"}"',
          hint: 'Delay in seconds  ·  ⏎ submit  ·  Esc cancel',
        );
      case Modal.setDue:
        return _buildFormModal(
          'Set due for "${_formTarget?.obj.title ?? "…"}"',
          hint: 'YYYY-MM-DD  ·  ⏎ submit  ·  Esc cancel',
        );
      case Modal.confirmDeleteTodo:
        return _buildConfirmDeleteModal();
      case Modal.find:
        return _buildFindBar();
      case Modal.none:
        return const SizedBox.shrink();
    }
  }

  Component _buildFindBar() {
    // Thin bottom-anchored bar overlaid on top of the log pane.
    // Doesn't use a ModalBarrier because the user wants to see the
    // live-narrowed list underneath while typing.
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          border: BoxBorder.all(color: Colors.yellow),
          color: Colors.black,
        ),
        child: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: 'find ',
                style: TextStyle(
                  color: Colors.yellow,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextSpan(text: '> '),
              TextSpan(
                text: '$_findQuery█',
                style: TextStyle(color: Colors.white),
              ),
              TextSpan(
                text: '   (Esc clear · ⏎ keep filter)',
                style: TextStyle(color: Colors.gray),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Component _buildCommandMenu() {
    final items = _filteredCommands();
    const double menuWidth = 48;
    const double menuHeight = 20;
    return Stack(
      children: [
        const ModalBarrier(color: Color.fromRGB(0, 0, 0), obscure: true),
        Positioned(
          left: 4,
          top: 3,
          child: Container(
            width: menuWidth,
            height: menuHeight,
            padding: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              border: BoxBorder.all(color: Colors.cyan),
              color: Colors.black,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Commands',
                  style: TextStyle(
                    color: Colors.cyan,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'type to filter  ·  ↑↓ nav  ·  ⏎ run  ·  Esc close',
                  style: TextStyle(color: Colors.gray),
                ),
                const SizedBox(height: 1),
                Text(
                  '> ${_cmdMenuQuery.isEmpty ? "(no filter)" : _cmdMenuQuery}',
                  style: TextStyle(color: Colors.yellow),
                ),
                const SizedBox(height: 1),
                if (items.isEmpty)
                  Text('(no match)', style: TextStyle(color: Colors.gray))
                else
                  for (int i = 0; i < items.length; i++)
                    _buildCommandRow(items[i], i == _cmdMenuIdx),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Component _buildCommandRow(Command c, bool selected) {
    final label = c.label;
    final hint = c.hint;
    final styleLabel = TextStyle(
      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      color: selected ? Colors.white : Colors.gray,
    );
    return Container(
      color: selected ? Color.fromRGB(0, 0, 110) : null,
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(text: selected ? '▶ ' : '  ', style: styleLabel),
            TextSpan(text: label, style: styleLabel),
            if (hint.isNotEmpty)
              TextSpan(text: '  ($hint)', style: TextStyle(color: Colors.gray)),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Form modals (M5) — every input command pops a modal form here.
  //
  // Fields are stored as plain strings in [_formValues], indexed by
  // [_formFieldIdx]. Tab / Enter move between fields (Enter on the
  // last field submits); Esc cancels. Rendering shows an underscore
  // at the end of the focused field's value to hint at cursor
  // position. This is deliberately thinner than wiring nocterm's
  // TextField focus system — the UX is consistent across every form
  // and stays close to the inline-prompt shape of the previous TUI.

  void _closeModal() {
    if (!mounted) return;
    setState(() {
      _modal = Modal.none;
      _formTarget = null;
      _formLabels = const [];
      _formValues = const [];
      _formFieldIdx = 0;
    });
  }

  void _openForm(
    Modal modal,
    List<String> labels,
    List<String> initialValues, {
    CItem<Todo>? target,
  }) {
    assert(labels.length == initialValues.length);
    setState(() {
      _modal = modal;
      _formLabels = labels;
      _formValues = [...initialValues];
      _formFieldIdx = 0;
      _formTarget = target;
    });
  }

  // ---- Form openers ----

  void _openCreateForm() {
    final defaultDue = DateTime.now().add(const Duration(days: 7));
    _openForm(
      Modal.createTodo,
      ['Title', 'Description', 'Share with (comma @signs)', 'Due (YYYY-MM-DD)'],
      ['', '', '', defaultDue.toIso8601String().substring(0, 10)],
    );
  }

  void _openEditForm() {
    final t = _requireSelectedOwnTodo('Edit');
    if (t == null) return;
    _openForm(
      Modal.editTodo,
      ['Title', 'Description', 'Share with (comma @signs)'],
      [
        t.obj.title,
        t.obj.description,
        t.sharedWith.map((a) => '$a').join(', '),
      ],
      target: t,
    );
  }

  void _openAddNoteForm() {
    if (todos.isEmpty || _selectedIdx < 0 || _selectedIdx >= todos.length) {
      log('No todo selected.', error: true);
      return;
    }
    final t = todos[_selectedIdx];
    _openForm(Modal.addNote, ['Note'], [''], target: t);
  }

  void _openShareForm() {
    final t = _requireSelectedOwnTodo('Share');
    if (t == null) return;
    _openForm(Modal.share, ['Add atSigns (comma-separated)'], [''], target: t);
  }

  void _openScheduleForm() {
    final t = _requireSelectedOwnTodo('Schedule');
    if (t == null) return;
    _openForm(
      Modal.schedule,
      ['Delay visibility by (seconds)'],
      ['30'],
      target: t,
    );
  }

  void _openSetDueForm() {
    final t = _requireSelectedOwnTodo('Set due date');
    if (t == null) return;
    final current =
        t.obj.dueDate?.toIso8601String().substring(0, 10) ??
        DateTime.now()
            .add(const Duration(days: 7))
            .toIso8601String()
            .substring(0, 10);
    _openForm(Modal.setDue, ['Due (YYYY-MM-DD)'], [current], target: t);
  }

  void _openConfirmDeleteForm() {
    if (todos.isEmpty || _selectedIdx < 0 || _selectedIdx >= todos.length) {
      log('No todo selected.', error: true);
      return;
    }
    final t = todos[_selectedIdx];
    if (t.owner != atClient.atSign) {
      log("Can't delete ${t.owner}'s todo.", error: true);
      return;
    }
    setState(() {
      _modal = Modal.confirmDeleteTodo;
      _formTarget = t;
    });
  }

  CItem<Todo>? _requireSelectedOwnTodo(String action) {
    if (todos.isEmpty || _selectedIdx < 0 || _selectedIdx >= todos.length) {
      log('$action: no todo selected.', error: true);
      return null;
    }
    final t = todos[_selectedIdx];
    if (t.owner != atClient.atSign) {
      log("$action: can't modify ${t.owner}'s todo.", error: true);
      return null;
    }
    return t;
  }

  // ---- Form key handler ----

  bool _onFormKey(KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.escape) {
      _closeModal();
      return true;
    }
    if (event.logicalKey == LogicalKey.tab) {
      if (_formValues.isEmpty) return true;
      final n = _formValues.length;
      setState(
        () =>
            _formFieldIdx =
                event.isShiftPressed
                    ? (_formFieldIdx - 1 + n) % n
                    : (_formFieldIdx + 1) % n,
      );
      return true;
    }
    if (event.logicalKey == LogicalKey.enter) {
      if (_formFieldIdx < _formValues.length - 1) {
        setState(() => _formFieldIdx++);
      } else {
        unawaited(_submitForm());
      }
      return true;
    }
    if (event.logicalKey == LogicalKey.backspace) {
      if (_formValues.isEmpty) return true;
      final v = _formValues[_formFieldIdx];
      if (v.isNotEmpty) {
        setState(() {
          _formValues = [..._formValues];
          _formValues[_formFieldIdx] = v.substring(0, v.length - 1);
        });
      }
      return true;
    }
    final ch = event.character;
    if (ch != null && ch.length == 1 && ch.codeUnitAt(0) >= 32) {
      setState(() {
        _formValues = [..._formValues];
        _formValues[_formFieldIdx] = _formValues[_formFieldIdx] + ch;
      });
      return true;
    }
    return false;
  }

  bool _onConfirmKey(KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.escape ||
        event.character == 'n' ||
        event.character == 'N') {
      _closeModal();
      return true;
    }
    if (event.character == 'y' ||
        event.character == 'Y' ||
        event.logicalKey == LogicalKey.enter) {
      unawaited(_submitForm());
      return true;
    }
    return false;
  }

  // ---- Submit (per-modal) ----

  Future<void> _submitForm() async {
    switch (_modal) {
      case Modal.createTodo:
        await _submitCreate();
      case Modal.editTodo:
        await _submitEdit();
      case Modal.addNote:
        await _submitAddNote();
      case Modal.share:
        await _submitShare();
      case Modal.schedule:
        await _submitSchedule();
      case Modal.setDue:
        await _submitSetDue();
      case Modal.confirmDeleteTodo:
        await _submitDeleteTodo();
      // ignore: no_default_cases
      default:
        _closeModal();
    }
  }

  Set<Atsign> _parseAtSigns(String s) =>
      s
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .map((e) => e.toAtsign())
          .toSet();

  DateTime _parseDueOrDefault(String s) {
    try {
      return DateTime.parse(s.trim());
    } catch (_) {
      return DateTime.now().add(const Duration(days: 7));
    }
  }

  Future<void> _submitCreate() async {
    final title = _formValues[0].trim();
    if (title.isEmpty) {
      log('Title is required.', error: true);
      return;
    }
    final desc = _formValues[1].trim();
    final shared = _parseAtSigns(_formValues[2]);
    final due = _parseDueOrDefault(_formValues[3]);
    try {
      final item = await collection.create(
        obj: Todo(title: title, description: desc, dueDate: due),
        sharedWith: shared,
      );
      log('Created: ${item.obj.title}');
      _closeModal();
      await refreshTodos();
    } catch (e) {
      log('Create failed: $e', error: true);
    }
  }

  Future<void> _submitEdit() async {
    final t = _formTarget;
    if (t == null) {
      _closeModal();
      return;
    }
    final title = _formValues[0].trim();
    if (title.isEmpty) {
      log('Title is required.', error: true);
      return;
    }
    final desc = _formValues[1].trim();
    final shared = _parseAtSigns(_formValues[2]);
    try {
      final updated = collection.draft(
        obj: Todo(
          title: title,
          description: desc,
          done: t.obj.done,
          dueDate: t.obj.dueDate,
        ),
        id: t.id,
        sharedWith: shared,
      );
      await collection.update(updated);
      log('Updated: $title');
      _closeModal();
      await refreshTodos();
    } catch (e) {
      log('Edit failed: $e', error: true);
    }
  }

  Future<void> _submitAddNote() async {
    final t = _formTarget;
    if (t == null) {
      _closeModal();
      return;
    }
    final text = _formValues[0].trim();
    if (text.isEmpty) {
      log('Note is empty.', error: true);
      return;
    }
    // Audience: parent's owner + sharedWith, minus self.
    final audience = <Atsign>{t.owner, ...t.sharedWith}
      ..remove(atClient.atSign);
    try {
      await _notesSubFor(
        t,
      ).create(obj: TodoNote(note: text), sharedWith: audience);
      log('Note added to "${t.obj.title}"');
      _closeModal();
      await refreshTodos();
    } catch (e) {
      log('Add note failed: $e', error: true);
    }
  }

  Future<void> _submitShare() async {
    final t = _formTarget;
    if (t == null) {
      _closeModal();
      return;
    }
    final toAdd = _parseAtSigns(_formValues[0]);
    if (toAdd.isEmpty) {
      log('No atSigns given.', error: true);
      return;
    }
    try {
      t.sharedWith.addAll(toAdd);
      await collection.update(t, unshareWithOthers: false);
      log('Shared "${t.obj.title}" with ${toAdd.join(", ")}');
      _closeModal();
      await refreshTodos();
    } catch (e) {
      log('Share failed: $e', error: true);
    }
  }

  Future<void> _submitSchedule() async {
    final t = _formTarget;
    if (t == null) {
      _closeModal();
      return;
    }
    final seconds = int.tryParse(_formValues[0].trim());
    if (seconds == null || seconds < 0) {
      log('Enter a non-negative integer (seconds).', error: true);
      return;
    }
    try {
      final updated = collection.draft(
        obj: Todo(
          title: t.obj.title,
          description: t.obj.description,
          done: t.obj.done,
          dueDate: t.obj.dueDate,
        ),
        id: t.id,
        sharedWith: Set.from(t.sharedWith),
        availableAt: DateTime.now().add(Duration(seconds: seconds)),
      );
      await collection.update(updated);
      log(
        'Scheduled "${t.obj.title}" to be visible '
        'in ${seconds}s.',
      );
      _closeModal();
      await refreshTodos();
    } catch (e) {
      log('Schedule failed: $e', error: true);
    }
  }

  Future<void> _submitSetDue() async {
    final t = _formTarget;
    if (t == null) {
      _closeModal();
      return;
    }
    final due = _parseDueOrDefault(_formValues[0]);
    try {
      final updated = collection.draft(
        obj: Todo(
          title: t.obj.title,
          description: t.obj.description,
          done: t.obj.done,
          dueDate: due,
        ),
        id: t.id,
        sharedWith: Set.from(t.sharedWith),
      );
      await collection.update(updated);
      log(
        'Due date for "${t.obj.title}" set to '
        '${due.toIso8601String().substring(0, 10)}',
      );
      _closeModal();
      await refreshTodos();
    } catch (e) {
      log('Set due failed: $e', error: true);
    }
  }

  Future<void> _submitDeleteTodo() async {
    final t = _formTarget;
    if (t == null) {
      _closeModal();
      return;
    }
    try {
      await collection.delete(t, cascade: true);
      log('Deleted: ${t.obj.title}');
      _closeModal();
      await refreshTodos();
    } catch (e) {
      log('Delete failed: $e', error: true);
    }
  }

  // ---- Form widget builder (shared) ----

  Component _buildFormModal(String title, {String? hint}) {
    return Stack(
      children: [
        const ModalBarrier(color: Color.fromRGB(0, 0, 0), obscure: true),
        Positioned(
          left: 4,
          top: 3,
          child: Container(
            width: 64,
            padding: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              border: BoxBorder.all(color: Colors.cyan),
              color: Colors.black,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.cyan,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  hint ?? 'Tab next field  ·  ⏎ next/submit  ·  Esc cancel',
                  style: TextStyle(color: Colors.gray),
                ),
                const SizedBox(height: 1),
                for (int i = 0; i < _formLabels.length; i++) _buildFormField(i),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Component _buildFormField(int idx) {
    final focused = idx == _formFieldIdx;
    final label = _formLabels[idx];
    final value = _formValues[idx];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: focused ? Colors.yellow : Colors.gray,
            fontWeight: focused ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            border: BoxBorder.all(color: focused ? Colors.yellow : Colors.gray),
          ),
          // The enclosing modal paints a black background; without an
          // explicit foreground colour here, the input text falls
          // through to the terminal's default fg — which on a black
          // bg is invisible (or near-invisible) on most terminals.
          child: Text(
            focused ? '$value█' : value,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }

  Component _buildConfirmDeleteModal() {
    final t = _formTarget;
    final title = t?.obj.title ?? '(unknown)';
    return Stack(
      children: [
        const ModalBarrier(color: Color.fromRGB(0, 0, 0), obscure: true),
        Positioned(
          left: 8,
          top: 5,
          child: Container(
            width: 52,
            padding: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              border: BoxBorder.all(color: Colors.red),
              color: Colors.black,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Delete todo?',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 1),
                Text('"$title"'),
                Text(
                  '(all notes will be cascade-deleted)',
                  style: TextStyle(color: Colors.gray),
                ),
                const SizedBox(height: 1),
                Text(
                  'y / ⏎ confirm  ·  n / Esc cancel',
                  style: TextStyle(color: Colors.yellow),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Component _buildHelpOverlay() {
    const rows = <({String chord, String desc})>[
      (chord: '↑ ↓ / k j', desc: 'Move selection'),
      (chord: 'g / G', desc: 'First / last todo'),
      (chord: '⏎ or →', desc: 'Focus detail pane'),
      (chord: 'Esc or ←', desc: 'Back to list pane'),
      (chord: 'c', desc: 'Create todo'),
      (chord: 'e', desc: 'Edit selected'),
      (chord: 'd', desc: 'Delete selected (confirm)'),
      (chord: 'space', desc: 'Toggle done on selected'),
      (chord: 'n', desc: 'Add note to selected'),
      (chord: 's', desc: 'Share selected (add atSigns)'),
      (chord: 'u', desc: 'Set due date'),
      (chord: 'S', desc: 'Schedule availableAt'),
      (chord: 'r', desc: 'Reverse sort'),
      (chord: '/', desc: 'Find (live-narrow list)'),
      (chord: 'm / Alt+m', desc: 'Open command menu'),
      (chord: '?', desc: 'Toggle this help'),
      (chord: 'q', desc: 'Quit'),
    ];
    return Stack(
      children: [
        const ModalBarrier(color: Color.fromRGB(0, 0, 0), obscure: true),
        Positioned(
          left: 6,
          top: 2,
          child: Container(
            width: 60,
            padding: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              border: BoxBorder.all(color: Colors.cyan),
              color: Colors.black,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Shared Todos — keyboard reference',
                  style: TextStyle(
                    color: Colors.cyan,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text('Esc or ? to close', style: TextStyle(color: Colors.gray)),
                const SizedBox(height: 1),
                for (final r in rows)
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '  ${r.chord.padRight(14)}',
                          style: TextStyle(color: Colors.yellow),
                        ),
                        TextSpan(text: r.desc),
                      ],
                    ),
                  ),
                const SizedBox(height: 1),
                Text(
                  'Every command is also reachable via the command menu (m).',
                  style: TextStyle(color: Colors.gray),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---- Widget builders ----

  Component _buildHeader() {
    final preset = todoPresetsByName[_activePresetName]!;
    final arrow = _reverseSort ? '↓' : '↑';
    final nextDueFragment =
        _nextDueLabel.isEmpty ? '' : ' · next due $_nextDueLabel';
    return Container(
      height: 3,
      padding: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(border: BoxBorder.all(color: Colors.cyan)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Shared Todos  —  ${atClient.atSign}',
            style: TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold),
          ),
          Text(
            '${preset.label} · due $arrow · '
            '${todos.length} in view · '
            '$_countOpen open · $_countOverdue overdue · '
            '$_countSharedWithMe shared$nextDueFragment',
            style: TextStyle(color: Colors.gray),
          ),
        ],
      ),
    );
  }

  Component _buildListPane() {
    final focused = _activePane == Pane.list;
    return Container(
      decoration: BoxDecoration(
        border: BoxBorder.all(color: focused ? Colors.cyan : Colors.gray),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child:
          todos.isEmpty
              ? const Center(child: Text('(no todos)'))
              : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0; i < todos.length; i++)
                    _buildTodoRow(i, todos[i], listFocused: focused),
                ],
              ),
    );
  }

  Component _buildTodoRow(
    int i,
    CItem<Todo> todo, {
    required bool listFocused,
  }) {
    final selected = i == _selectedIdx;
    final marker = selected ? '▶' : ' ';
    final check = todo.obj.done ? '[x]' : '[ ]';
    final due = todo.obj.dueDate?.toIso8601String().substring(0, 10) ?? '——';
    final noteCount = notesByTodoId[todo.id]?.length ?? 0;
    // Selection background. Brighter when the list pane owns focus
    // so the active row pops; muted-but-still-distinct when focus
    // has moved to the detail pane so the user can still see which
    // item they're reading.
    //
    // The earlier (0,0,110)/(0,0,40) palette was too dark — text
    // without an explicit foreground rendered illegibly on it on
    // common terminal themes. The current values are mid-luminance
    // blues that read against both light and dark default fg.
    final rowBg = selected
        ? (listFocused
            ? const Color.fromRGB(20, 60, 130)
            : const Color.fromRGB(60, 60, 70))
        : null;
    final weight = selected ? FontWeight.bold : FontWeight.normal;
    final done = todo.obj.done;
    // Every TextSpan below carries an explicit color — without one,
    // nocterm renders with the terminal's default foreground, which
    // can be invisible against the row's selection background or
    // even against the pane's transparent backdrop on themes whose
    // default fg approaches the body color.
    final markerColor = selected ? Colors.cyan : Colors.gray;
    final checkColor = done ? Colors.green : Colors.white;
    final titleColor = done ? Colors.gray : Colors.white;
    final dimColor = Colors.gray;
    final titleStyle = TextStyle(
      fontWeight: weight,
      color: titleColor,
    );
    return Container(
      color: rowBg,
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontWeight: weight, color: Colors.white),
          children: [
            TextSpan(
              text: '$marker ',
              style: TextStyle(color: markerColor, fontWeight: weight),
            ),
            TextSpan(
              text: '$check  ',
              style: TextStyle(color: checkColor, fontWeight: weight),
            ),
            TextSpan(
              text: due,
              style: TextStyle(
                color: _theme.colorForDue(todo.obj.dueDate, done: done),
                fontWeight: weight,
              ),
            ),
            TextSpan(text: '  ', style: TextStyle(color: titleColor)),
            TextSpan(text: todo.obj.title, style: titleStyle),
            TextSpan(text: '  (', style: TextStyle(color: dimColor)),
            TextSpan(
              text: '${todo.owner}',
              style: _theme.styleForAtSign(todo.owner, bold: selected),
            ),
            TextSpan(text: ')', style: TextStyle(color: dimColor)),
            if (noteCount > 0)
              TextSpan(
                text: '  notes:$noteCount',
                style: TextStyle(color: dimColor, fontWeight: weight),
              ),
          ],
        ),
      ),
    );
  }

  Component _buildDetailPane() {
    final focused = _activePane == Pane.detail;
    final borderColor = focused ? Colors.cyan : Colors.gray;
    if (todos.isEmpty) {
      return Container(
        decoration: BoxDecoration(border: BoxBorder.all(color: borderColor)),
        child: const Center(child: Text('(no todo selected)')),
      );
    }
    final todo = todos[_selectedIdx];
    final notes = notesByTodoId[todo.id] ?? const <CItem<TodoNote>>[];
    return Container(
      decoration: BoxDecoration(border: BoxBorder.all(color: borderColor)),
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(todo.obj.title, style: TextStyle(fontWeight: FontWeight.bold)),
          if (todo.obj.description.isNotEmpty) ...[
            const SizedBox(height: 1),
            Text(todo.obj.description),
          ],
          const SizedBox(height: 1),
          RichText(
            text: TextSpan(
              children: [
                const TextSpan(text: 'Owner    : '),
                TextSpan(
                  text: '${todo.owner}',
                  style: _theme.styleForAtSign(todo.owner, bold: true),
                ),
              ],
            ),
          ),
          RichText(
            text: TextSpan(
              children: [
                const TextSpan(text: 'Due      : '),
                TextSpan(
                  text: _fmtDateTime(todo.obj.dueDate),
                  style: TextStyle(
                    color: _theme.colorForDue(
                      todo.obj.dueDate,
                      done: todo.obj.done,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Text('Created  : ${_fmtDateTime(todo.createdAt)}'),
          _buildAtSignListRow('Shared   : ', todo.sharedWith),
          Text('Done     : ${todo.obj.done ? "yes" : "no"}'),
          const SizedBox(height: 1),
          // Live read-by timeline. Each row is one receipt CItem from
          // `item.receipts.query().orderBy((r) => r.createdAt).watch()`
          // (the public `__rr` sub-collection handle exposed in
          // Bundle S1). Updates live as new atSigns mark the item as
          // read without any app-level polling.
          Text(
            'Read by  (${_detailReceipts.length})',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.cyan),
          ),
          if (_detailReceipts.isEmpty)
            Text(
              todo.sharedWith.isEmpty ? '  (—)' : '  (nobody yet)',
              style: TextStyle(color: Colors.gray),
            ),
          for (final r in _detailReceipts)
            RichText(
              text: TextSpan(
                children: [
                  const TextSpan(text: '  • '),
                  TextSpan(
                    text: '${r.owner}',
                    style: _theme.styleForAtSign(r.owner),
                  ),
                  TextSpan(
                    text: '  ${_fmtDateTime(r.createdAt)}',
                    style: TextStyle(color: Colors.gray),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 1),
          Text(
            'Notes (${notes.length})',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.cyan),
          ),
          if (notes.isEmpty)
            Text('  (none)', style: TextStyle(color: Colors.gray)),
          for (final n in notes)
            RichText(
              text: TextSpan(
                children: [
                  const TextSpan(text: '  • ['),
                  TextSpan(
                    text: '${n.owner}',
                    style: _theme.styleForAtSign(n.owner),
                  ),
                  TextSpan(
                    text: '] ${n.obj.note}',
                    style: TextStyle(color: Colors.gray),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Helper that renders a label followed by a comma-separated
  /// coloured list of atSigns. Used for "Shared :" and similar.
  Component _buildAtSignListRow(String label, Iterable<Atsign> atSigns) {
    if (atSigns.isEmpty) {
      return Text('$label—');
    }
    final children = <InlineSpan>[TextSpan(text: label)];
    var first = true;
    for (final a in atSigns) {
      if (!first) children.add(const TextSpan(text: ', '));
      children.add(TextSpan(text: '$a', style: _theme.styleForAtSign(a)));
      first = false;
    }
    return RichText(text: TextSpan(children: children));
  }

  static String _fmtDateTime(DateTime? d) =>
      d == null
          ? '—'
          : d.toIso8601String().substring(0, 19).replaceFirst('T', ' ');

  Component _buildLogPane() {
    const logHeight = 8;
    final tail =
        logMessages.length > logHeight
            ? logMessages.sublist(logMessages.length - logHeight)
            : logMessages;
    return Container(
      height: logHeight + 2,
      decoration: BoxDecoration(border: BoxBorder.all(color: Colors.gray)),
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Log', style: TextStyle(fontWeight: FontWeight.bold)),
          for (final line in tail)
            Text(line, style: TextStyle(color: Colors.gray)),
        ],
      ),
    );
  }

  Component _buildFooterBar() {
    final String hint;
    if (_modal == Modal.commandMenu) {
      hint = 'type to filter  ·  ↑↓ nav  ·  ⏎ run  ·  Esc close';
    } else if (_modal == Modal.help) {
      hint = 'Esc or ? to close help';
    } else if (_modal == Modal.find) {
      hint = 'type to narrow  ·  ⏎ keep filter  ·  Esc clear & close';
    } else if (_modal != Modal.none) {
      hint = 'Tab next  ·  ⏎ submit  ·  Esc cancel';
    } else if (_activePane == Pane.list) {
      hint =
          '⏎/→ detail  ·  c new  ·  e edit  ·  d del  ·  '
          'space done  ·  n note  ·  / find  ·  m menu  ·  ? help  ·  q quit';
    } else {
      hint = 'Esc/← back to list  ·  m menu  ·  ? help  ·  q quit';
    }
    return Container(
      height: 1,
      child: Text(hint, style: TextStyle(color: Colors.gray)),
    );
  }
}
