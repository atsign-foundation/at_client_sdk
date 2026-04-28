import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:flutter/material.dart';

import '../models/todo.dart';
import '../onboarding.dart';
import '../services/todo_presets.dart';
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
  // Active filter preset (name is the key into [todoPresetsByName]).
  // Default 'all' = every todo the current atSign can see.
  String _presetName = 'all';
  // When true, sort direction is reversed (descending by due date).
  bool _reverseSort = false;
  // When true, the list renders as sections keyed by todo owner, via
  // an inline projection of the `watchTodosWithNotes` stream. The
  // one-shot equivalent is `query().groupBy<Atsign>((t) => t.owner)`.
  bool _groupByOwner = false;
  // Debounced search needle composed into the active query as an
  // additional `.where(title contains)` predicate. Empty string
  // means "no search filter".
  String _search = '';
  Timer? _searchDebounce;
  final TextEditingController _searchController = TextEditingController();

  // Cached `Query<Todo>` for the list view. Rebuilt only when
  // preset / reverse / search changes — passing a stable object to
  // [TodosService.watchTodos] keeps its pipeline cached and avoids
  // tearing down the stream on every widget rebuild.
  Query<Todo>? _currentQuery;
  // Long-lived count queries for the AppBar badges. Built once after
  // service init; not re-created as the user navigates the presets.
  Query<Todo>? _openCountQuery;
  Query<Todo>? _overdueCountQuery;
  // Transient "just read by X" ticker, driven by
  // [AtCollection.readReceipts] on the service's collection.
  StreamSubscription<CReadReceipt>? _receiptsTickerSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _receiptsTickerSub?.cancel();
    _service?.dispose();
    super.dispose();
  }

  void _onSearchChanged(String text) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _search = text.trim());
      _rebuildCurrentQuery();
    });
  }

  /// Rebuilds [_currentQuery] from the current preset / reverse /
  /// search state. Called whenever the user changes any of those
  /// knobs. A stable query reference between user actions lets
  /// [TodosService.watchTodos] keep its stream subscription alive.
  void _rebuildCurrentQuery() {
    final service = _service;
    if (service == null) return;
    var q = todoPresetsByName[_presetName]!.build(
      service.collection,
      service.self,
      _reverseSort,
    );
    if (_search.isNotEmpty) {
      final needle = _search.toLowerCase();
      q = q.where((t) => t.obj.title.toLowerCase().contains(needle));
    }
    setState(() => _currentQuery = q);
  }

  void _applyPreset(String name) {
    if (_presetName == name) return;
    setState(() => _presetName = name);
    _rebuildCurrentQuery();
  }

  void _toggleReverse() {
    setState(() => _reverseSort = !_reverseSort);
    _rebuildCurrentQuery();
  }

  Future<void> _init() async {
    try {
      final atClient = AtClientManager.getInstance().atClient;
      final s = TodosService(atClient);
      await s.init();
      if (!mounted) return;
      setState(() {
        _service = s;
        // Build the initial list query + the long-lived count queries
        // now that `s.collection` is populated.
        _openCountQuery = todoPresetsByName['open']!.build(
          s.collection,
          s.self,
          false,
        );
        _overdueCountQuery = todoPresetsByName['overdue']!.build(
          s.collection,
          s.self,
          false,
        );
      });
      _rebuildCurrentQuery();
      // Transient "just read by X" toast. Showcases direct use of
      // the `AtCollection.readReceipts` event stream — a compelling
      // live-reactive moment when two atSigns are using the app
      // side by side.
      _receiptsTickerSub = s.collection.readReceipts.listen((e) async {
        if (!mounted || e.from == s.self) return;
        final item = await s.collection.getOrNull(e.id, e.owner);
        if (!mounted) return;
        final title = item?.obj.title ?? '(id ${e.id})';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text('${e.from} just read "$title"'),
          ),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    }
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
    final currentQuery = _currentQuery;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Todos — ${service.self}',
          style: TextStyle(color: service.colors.colorFor(service.self)),
        ),
        actions: [
          _CountBadge(
            label: 'Open',
            stream: service.watchCount(_openCountQuery!),
          ),
          _CountBadge(
            label: 'Overdue',
            stream: service.watchCount(_overdueCountQuery!),
          ),
          IconButton(
            tooltip: _reverseSort
                ? 'Sort ascending by due date'
                : 'Sort descending by due date',
            onPressed: _toggleReverse,
            icon: Icon(
              _reverseSort ? Icons.arrow_downward : Icons.arrow_upward,
            ),
          ),
          IconButton(
            tooltip: _groupByOwner ? 'Show flat list' : 'Group by owner',
            onPressed: () => setState(() => _groupByOwner = !_groupByOwner),
            icon: Icon(_groupByOwner ? Icons.view_list : Icons.group_work),
          ),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: Column(
        children: [
          // Live "next due open todo" banner. Driven by a `.watch()`
          // over the open preset → take the first item on each
          // snapshot, so the label updates the instant anyone
          // completes the current next-due todo (or one earlier is
          // shared in). Empty-list snapshots collapse the banner
          // to nothing.
          _NextDueBanner(
            stream: _openCountQuery!.watch().map(
              (l) => l.isEmpty ? null : l.first,
            ),
            service: service,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search titles…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          _FilterChipRow(activeName: _presetName, onSelected: _applyPreset),
          Expanded(
            child: currentQuery == null
                ? const Center(child: CircularProgressIndicator())
                : StreamBuilder<List<TodoWithNotes>>(
                    stream: service.watchTodosWithNotes(currentQuery),
                    builder: (_, snap) {
                      if (snap.hasError) {
                        return Center(child: Text('Error: ${snap.error}'));
                      }
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final rows = snap.data!;
                      if (rows.isEmpty) {
                        return const Center(
                          child: Text('No todos match this filter.'),
                        );
                      }
                      Widget buildRow(TodoWithNotes row) => _TodoRow(
                        todo: row.parent,
                        noteCount: row.children.length,
                        service: service,
                        onToggleDone: () =>
                            _withBusy(() => service.toggleDone(row.parent)),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => TodoDetailScreen(
                              todo: row.parent,
                              service: service,
                            ),
                          ),
                        ),
                      );
                      if (!_groupByOwner) {
                        return ListView.separated(
                          itemCount: rows.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) => buildRow(rows[i]),
                        );
                      }
                      // Group-by-owner inline projection — same effect
                      // as `query().groupBy<Atsign>((t) => t.owner)` but
                      // kept live off the existing stream rather than
                      // invoking the one-shot terminal.
                      final groups = <Atsign, List<TodoWithNotes>>{};
                      for (final r in rows) {
                        groups.putIfAbsent(r.parent.owner, () => []).add(r);
                      }
                      final owners = groups.keys.toList()
                        ..sort((a, b) => a.toString().compareTo(b.toString()));
                      return ListView.builder(
                        itemCount: owners.fold<int>(
                          owners.length,
                          (acc, o) => acc + groups[o]!.length,
                        ),
                        itemBuilder: (_, i) {
                          var idx = i;
                          for (final owner in owners) {
                            if (idx == 0) {
                              return Container(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                child: AtsignText(
                                  atSign: owner,
                                  colors: service.colors,
                                ),
                              );
                            }
                            idx--;
                            final bucket = groups[owner]!;
                            if (idx < bucket.length) {
                              return buildRow(bucket[idx]);
                            }
                            idx -= bucket.length;
                          }
                          return const SizedBox.shrink();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _busy ? null : _createTodo,
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// Thin banner above the search field showing "Next due: <title>
/// in N days" for the earliest-due open todo. Backed by a live
/// stream that projects `.first` (as `firstOrNull`) off the open
/// preset's `.watch()` output — so the banner updates the moment
/// someone completes the current leader or a new earlier one lands.
class _NextDueBanner extends StatelessWidget {
  final Stream<CItem<Todo>?> stream;
  final TodosService service;

  const _NextDueBanner({required this.stream, required this.service});

  String _relDue(DateTime? due) {
    if (due == null) return '(no date)';
    final diff = due.difference(DateTime.now());
    if (diff.isNegative) {
      final past = -diff;
      if (past.inDays >= 1) return 'overdue by ${past.inDays}d';
      return 'overdue';
    }
    if (diff.inDays >= 1) return 'in ${diff.inDays}d';
    if (diff.inHours >= 1) return 'in ${diff.inHours}h';
    return 'soon';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CItem<Todo>?>(
      stream: stream,
      builder: (_, snap) {
        final item = snap.data;
        if (item == null) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          color: Theme.of(context).colorScheme.secondaryContainer,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.schedule, size: 16),
              const SizedBox(width: 6),
              const Text('Next due: '),
              Expanded(
                child: Text(
                  '"${item.obj.title}" ${_relDue(item.obj.dueDate)}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 6),
              AtsignText(atSign: item.owner, colors: service.colors),
            ],
          ),
        );
      },
    );
  }
}

/// AppBar badge showing a live count — e.g. "Open 5" — driven by
/// `TodosService.watchCount(query)`. The stream re-emits on any
/// update/delete that could affect the count.
class _CountBadge extends StatelessWidget {
  final String label;
  final Stream<int> stream;

  const _CountBadge({required this.label, required this.stream});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      child: StreamBuilder<int>(
        stream: stream,
        builder: (_, snap) {
          final n = snap.data ?? 0;
          return Chip(
            label: Text('$label $n'),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          );
        },
      ),
    );
  }
}

/// Horizontally-scrolling row of filter chips, one per entry in
/// [todoPresets]. Each chip holds a preset name; tapping swaps the
/// active preset. The underlying `Query<Todo>` is built lazily in
/// [_TodosHomeState._rebuildCurrentQuery] so we don't pay for every
/// query on every build.
class _FilterChipRow extends StatelessWidget {
  final String activeName;
  final ValueChanged<String> onSelected;

  const _FilterChipRow({required this.activeName, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        itemCount: todoPresets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (_, i) {
          final p = todoPresets[i];
          return FilterChip(
            label: Text(p.label),
            selected: p.name == activeName,
            onSelected: (_) => onSelected(p.name),
          );
        },
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Live read-receipt count via the public `item.receipts`
          // sub-collection — Bundle S1 made this accessible from app
          // code, Bundle C puts it to work here. Shows N eyes icons
          // with the current reader count; 0 when nobody has read yet.
          StreamBuilder<List<CItem<Map<String, dynamic>>>>(
            stream: todo.receipts.query().watch(),
            builder: (_, snap) {
              final n = snap.data?.length ?? 0;
              return Tooltip(
                message: n == 0
                    ? 'No read receipts yet'
                    : '$n read receipt${n == 1 ? '' : 's'}',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.visibility,
                      size: 16,
                      color: n > 0
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).disabledColor,
                    ),
                    const SizedBox(width: 4),
                    Text('$n'),
                  ],
                ),
              );
            },
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: onTap,
      isThreeLine: true,
    );
  }
}
