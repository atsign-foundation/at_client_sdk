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
    super.dispose();
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
    if (event.logicalKey == LogicalKey.keyQ) {
      shutdownApp();
      return true;
    }
    if (event.logicalKey == LogicalKey.arrowUp ||
        event.logicalKey == LogicalKey.keyK) {
      if (_selectedIdx > 0) {
        setState(() => _selectedIdx--);
      }
      return true;
    }
    if (event.logicalKey == LogicalKey.arrowDown ||
        event.logicalKey == LogicalKey.keyJ) {
      if (_selectedIdx < todos.length - 1) {
        setState(() => _selectedIdx++);
      }
      return true;
    }
    if (event.logicalKey == LogicalKey.keyG) {
      if (event.isShiftPressed) {
        if (todos.isNotEmpty) {
          setState(() => _selectedIdx = todos.length - 1);
        }
      } else {
        if (todos.isNotEmpty) {
          setState(() => _selectedIdx = 0);
        }
      }
      return true;
    }
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
    return Container(
      decoration: BoxDecoration(border: BoxBorder.all(color: Colors.gray)),
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: todos.isEmpty
          ? const Center(child: Text('(no todos)'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < todos.length; i++)
                  _buildTodoRow(i, todos[i]),
              ],
            ),
    );
  }

  Component _buildTodoRow(int i, CItem<Todo> todo) {
    final selected = i == _selectedIdx;
    final marker = selected ? '▶' : ' ';
    final check = todo.obj.done ? '[x]' : '[ ]';
    final due = todo.obj.dueDate?.toIso8601String().substring(0, 10) ?? '——';
    final noteCount = notesByTodoId[todo.id]?.length ?? 0;
    final noteTag = noteCount > 0 ? '  💬$noteCount' : '';
    return Container(
      color: selected ? Color.fromRGB(0, 0, 90) : null,
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Text(
        '$marker $check  $due  ${todo.obj.title}$noteTag',
        style: TextStyle(
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Component _buildDetailPane() {
    if (todos.isEmpty) {
      return Container(
        decoration: BoxDecoration(border: BoxBorder.all(color: Colors.gray)),
        child: const Center(child: Text('(no todo selected)')),
      );
    }
    final todo = todos[_selectedIdx];
    final notes = notesByTodoId[todo.id] ?? const <CItem<TodoNote>>[];
    final readers = todo.readBySnapshot;
    return Container(
      decoration: BoxDecoration(border: BoxBorder.all(color: Colors.gray)),
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
          Text('Owner    : ${todo.owner}'),
          Text(
            'Due      : ${todo.obj.dueDate?.toIso8601String().substring(0, 19).replaceFirst("T", " ") ?? "—"}',
          ),
          Text(
            'Created  : ${todo.createdAt.toIso8601String().substring(0, 19).replaceFirst("T", " ")}',
          ),
          Text(
            'Shared   : ${todo.sharedWith.isEmpty ? "—" : todo.sharedWith.join(", ")}',
          ),
          Text(
            'Read by  : ${readers.isEmpty ? (todo.sharedWith.isEmpty ? "—" : "(nobody yet)") : readers.join(", ")}',
          ),
          Text('Done     : ${todo.obj.done ? "yes" : "no"}'),
          const SizedBox(height: 1),
          Text(
            'Notes (${notes.length})',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.cyan),
          ),
          if (notes.isEmpty) const Text('  (none)'),
          for (final n in notes)
            Text(
              '  • [${n.owner}] ${n.obj.note}',
              style: TextStyle(color: Colors.gray),
            ),
        ],
      ),
    );
  }

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

  Component _buildFooterBar() => Container(
    height: 1,
    child: Text(
      '↑↓ / j k   nav   ·   g / G   top / bottom   ·   q   quit   '
      '·   commands & forms: coming in later milestones',
      style: TextStyle(color: Colors.gray),
    ),
  );
}
