import 'dart:async';
import 'dart:io';

import 'package:at_cli_commons/at_cli_commons.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client_examples/domain_objects.dart';
import 'package:nocterm/nocterm.dart';

void main(List<String> args) async {
  final AtClient atClient = (await CLIBase.fromCommandLineArgs(
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

// -----------------------------------------------------------------------------
// Preset definitions — filter+sort views over the todos collection. Each
// preset is a named function from `(collection, self, reverse)` to an
// immutable `Query<Todo>` value, so the rest of the app can treat them
// as first-class references and compose further .where(...)'s on top.

class _TodoPreset {
  final String name;
  final String label;
  final Query<Todo> Function(
    AtCollection<Todo> collection,
    Atsign self,
    bool reverse,
  )
  build;

  const _TodoPreset(this.name, this.label, this.build);
}

/// Sort by due date ascending, with `null` due-dates sorted last (far-
/// future sentinel). `reverse` flips direction; nulls then sort first,
/// matching the pre-builder `_compareByDue` behaviour.
Query<Todo> _sortedByDue(Query<Todo> q, bool reverse) =>
    q.orderBy((t) => t.obj.dueDate ?? DateTime.utc(9999), descending: reverse);

final List<_TodoPreset> _todoPresets = [
  _TodoPreset('all', 'All', (c, _, rev) => _sortedByDue(c.query(), rev)),
  _TodoPreset(
    'mine',
    'Mine',
    (c, self, rev) =>
        _sortedByDue(c.query().where((t) => t.owner == self), rev),
  ),
  _TodoPreset(
    'shared',
    'Shared with me',
    (c, self, rev) =>
        _sortedByDue(c.query().where((t) => t.owner != self), rev),
  ),
  _TodoPreset(
    'open',
    'Open',
    (c, _, rev) => _sortedByDue(c.query().where((t) => !t.obj.done), rev),
  ),
  _TodoPreset(
    'done',
    'Done',
    (c, _, rev) => _sortedByDue(c.query().where((t) => t.obj.done), rev),
  ),
  _TodoPreset('overdue', 'Overdue', (c, _, rev) {
    final now = DateTime.now();
    return _sortedByDue(
      c.query().where(
        (t) => !t.obj.done && (t.obj.dueDate?.isBefore(now) ?? false),
      ),
      rev,
    );
  }),
];

final Map<String, _TodoPreset> _todoPresetsByName = {
  for (final p in _todoPresets) p.name: p,
};

/// Parent+children snapshot emitted by [Query.watchWithSub] — one todo
/// paired with its current notes.
typedef _TodoWithNotes =
    ({CItem<Todo> parent, List<CItem<TodoNote>> children});

/// Which pane currently owns keyboard focus. `list` is the default;
/// `detail` is entered via Enter or Right-arrow so the user can read
/// or (later) scroll through the detail pane; Esc / Left-arrow return.
enum _Pane { list, detail }

/// Per-TUI colour helpers. One instance lives on the State class,
/// seeded with the current atSign at init time.
///
/// - [colorForAtSign] assigns a stable colour to each seen atSign by
///   walking a pastel palette in order; the current atSign always
///   gets the accent orange.
/// - [colorForDue] encodes due-date urgency (overdue=red, ≤24h=amber,
///   otherwise green; done items are greyed regardless).
class _TodoTheme {
  static const List<int> _palette = [
    27, 33, 39, 63, 69, 75, 76, 82, 99, 105, 129, 135, 141, 148,
    160, 161, 162, 166, 172, 178, 196, 200, 201, 202, 208, 214,
  ];
  final Atsign self;
  final Map<String, int> _assigned = {};
  int _nextIdx = 0;

  _TodoTheme(this.self);

  /// Converts an ANSI-256 colour-cube index (16..231) to an RGB Color
  /// using the canonical 6x6x6 cube steps.
  static Color _ansi256ToColor(int idx) {
    if (idx < 16 || idx > 231) return Colors.white;
    final n = idx - 16;
    final r = (n ~/ 36) % 6;
    final g = (n ~/ 6) % 6;
    final b = n % 6;
    const steps = [0, 95, 135, 175, 215, 255];
    return Color.fromRGB(steps[r], steps[g], steps[b]);
  }

  Color colorForAtSign(Atsign a) {
    if (a == self) return const Color.fromRGB(255, 135, 0); // self = orange
    final key = a.toString();
    final idx = _assigned.putIfAbsent(key, () {
      final i = _nextIdx;
      _nextIdx = (_nextIdx + 1) % _palette.length;
      return i;
    });
    return _ansi256ToColor(_palette[idx]);
  }

  TextStyle styleForAtSign(Atsign a, {bool bold = false}) => TextStyle(
    color: colorForAtSign(a),
    fontWeight: bold ? FontWeight.bold : FontWeight.normal,
  );

  Color colorForDue(DateTime? due, {required bool done}) {
    if (done) return Colors.gray;
    if (due == null) return Colors.white;
    final diff = due.difference(DateTime.now());
    if (diff.isNegative) return Colors.red;
    if (diff.inHours < 24) return const Color.fromRGB(255, 175, 0);
    return Colors.green;
  }
}

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
  late final _TodoTheme _theme = _TodoTheme(atClient.atSign);

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
  _Pane _activePane = _Pane.list;

  // Init state — the app renders a "Loading…" placeholder until
  // `_setup()` completes, or an error screen if init failed.
  bool _ready = false;
  String? _initError;

  // ---- Subscriptions ----
  StreamSubscription<List<_TodoWithNotes>>? _todosSub;
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
    if (todos.isEmpty ||
        _selectedIdx < 0 ||
        _selectedIdx >= todos.length) {
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
        .listen(
          (list) {
            if (!mounted) return;
            setState(() => _detailReceipts = list);
          },
          onError: (Object e) =>
              log('receipts stream: $e', error: true),
        );
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
      ),
    );
  }

  /// Builds the current `Query<Todo>` from active preset + reverse flag.
  Query<Todo> _buildQuery() {
    final preset = _todoPresetsByName[_activePresetName]!;
    return preset.build(collection, atClient.atSign, _reverseSort);
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
        )
        .listen(
          _onCombinedSnapshot,
          onError: (Object e) => log('Error on todos stream: $e', error: true),
        );
  }

  /// Applies an incoming snapshot to state: updates todos +
  /// notesByTodoId, sends pending read-receipts, primes readBy,
  /// clamps the selection index, schedules a redraw via [setState].
  Future<void> _onCombinedSnapshot(List<_TodoWithNotes> snapshot) async {
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
      final parents = await _buildQuery().fetch();
      final combined = <_TodoWithNotes>[];
      for (final p in parents) {
        final notes = await _notesSubFor(p).query().fetch();
        combined.add((parent: p, children: notes));
      }
      await _onCombinedSnapshot(combined);
    } catch (e) {
      log('Error refreshing todos: $e', error: true);
    }
  }

  void _setupCountStreams() {
    _openCountSub = _todoPresetsByName['open']!
        .build(collection, atClient.atSign, false)
        .watch()
        .map((l) => l.length)
        .listen((n) {
          if (!mounted) return;
          setState(() => _countOpen = n);
        });
    _overdueCountSub = _todoPresetsByName['overdue']!
        .build(collection, atClient.atSign, false)
        .watch()
        .map((l) => l.length)
        .listen((n) {
          if (!mounted) return;
          setState(() => _countOverdue = n);
        });
    _sharedCountSub = _todoPresetsByName['shared']!
        .build(collection, atClient.atSign, false)
        .watch()
        .map((l) => l.length)
        .listen((n) {
          if (!mounted) return;
          setState(() => _countSharedWithMe = n);
        });
  }

  void _setupNextDueStream() {
    _nextDueSub = _todoPresetsByName['open']!
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
              final dueStr = due == null
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

  @override
  Component build(BuildContext context) {
    if (_initError != null) {
      return _errorView(_initError!);
    }
    if (!_ready) {
      return _loadingView();
    }
    return _mainView();
  }

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
    onKeyEvent: _onGlobalKey,
    child: Column(
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
  );

  bool _onGlobalKey(KeyboardEvent event) {
    // Global keys — active regardless of pane focus.
    if (event.logicalKey == LogicalKey.keyQ) {
      shutdownApp();
      return true;
    }
    if (_activePane == _Pane.list) {
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
        setState(() => _activePane = _Pane.detail);
      }
      return true;
    }
    return false;
  }

  bool _onDetailKey(KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.escape ||
        event.logicalKey == LogicalKey.arrowLeft ||
        event.logicalKey == LogicalKey.keyH) {
      setState(() => _activePane = _Pane.list);
      return true;
    }
    // Scrolling / note navigation inside the detail pane comes in a
    // later milestone. For now the pane is read-only once focused.
    return false;
  }

  // ---- Widget builders ----

  Component _buildHeader() {
    final preset = _todoPresetsByName[_activePresetName]!;
    final arrow = _reverseSort ? '↓' : '↑';
    final nextDueFragment = _nextDueLabel.isEmpty
        ? ''
        : ' · next due $_nextDueLabel';
    return Container(
      height: 3,
      padding: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(border: BoxBorder.all(color: Colors.cyan)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Shared Todos  —  ${atClient.atSign}',
            style: TextStyle(
              color: Colors.cyan,
              fontWeight: FontWeight.bold,
            ),
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
    final focused = _activePane == _Pane.list;
    return Container(
      decoration: BoxDecoration(
        border: BoxBorder.all(
          color: focused ? Colors.cyan : Colors.gray,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: todos.isEmpty
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
    // Highlight the selected row brighter when the list pane owns
    // focus; dimmer when focus has moved to the detail pane but the
    // user should still see which item they're reading.
    final rowBg = selected
        ? (listFocused ? Color.fromRGB(0, 0, 110) : Color.fromRGB(0, 0, 40))
        : null;
    final weight = selected ? FontWeight.bold : FontWeight.normal;
    final done = todo.obj.done;
    final titleStyle = TextStyle(
      fontWeight: weight,
      color: done ? Colors.gray : null,
    );
    return Container(
      color: rowBg,
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontWeight: weight),
          children: [
            TextSpan(text: '$marker $check  '),
            TextSpan(
              text: due,
              style: TextStyle(
                color: _theme.colorForDue(todo.obj.dueDate, done: done),
                fontWeight: weight,
              ),
            ),
            TextSpan(text: '  '),
            TextSpan(text: todo.obj.title, style: titleStyle),
            TextSpan(text: '  ('),
            TextSpan(
              text: '${todo.owner}',
              style: _theme.styleForAtSign(todo.owner, bold: selected),
            ),
            TextSpan(text: ')'),
            if (noteCount > 0)
              TextSpan(
                text: '  notes:$noteCount',
                style: TextStyle(color: Colors.gray, fontWeight: weight),
              ),
          ],
        ),
      ),
    );
  }

  Component _buildDetailPane() {
    final focused = _activePane == _Pane.detail;
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
          Text(
            todo.obj.title,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
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

  static String _fmtDateTime(DateTime? d) => d == null
      ? '—'
      : d.toIso8601String().substring(0, 19).replaceFirst('T', ' ');

  Component _buildLogPane() {
    const logHeight = 8;
    final tail = logMessages.length > logHeight
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
    final hint = _activePane == _Pane.list
        ? '↑↓/jk nav  ·  g/G top/bottom  ·  ⏎/→ open detail  ·  q quit'
        : 'Esc/← back to list  ·  q quit';
    return Container(
      height: 1,
      child: Text(hint, style: TextStyle(color: Colors.gray)),
    );
  }
}
