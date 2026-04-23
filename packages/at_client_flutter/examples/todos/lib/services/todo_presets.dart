import 'package:at_client/at_client.dart';

import '../models/todo.dart';

/// A named filter+sort view over the todos collection. Each preset is
/// just a function from `(collection, self, reverse)` to a `Query<Todo>`
/// — queries are immutable values, so presets stay cheap to build and
/// safe to pass around between screens, badges, and streams.
class TodoPreset {
  final String name;
  final String label;
  final Query<Todo> Function(
    AtCollection<Todo> collection,
    Atsign self,
    bool reverse,
  )
  build;

  const TodoPreset(this.name, this.label, this.build);
}

/// Sort by due date ascending, with `null` due-dates sorted last (we
/// use a far-future sentinel of year 9999). `reverse` flips to
/// descending; the sentinel then sorts first, matching the app's
/// pre-builder `_compareByDue` behaviour for interop.
Query<Todo> _sortedByDue(Query<Todo> q, bool reverse) => q.orderBy(
  (t) => t.obj.dueDate ?? DateTime.utc(9999),
  descending: reverse,
);

/// The full preset registry. Order here drives the filter-chip order on
/// the home screen.
final List<TodoPreset> todoPresets = [
  TodoPreset('all', 'All', (c, _, rev) => _sortedByDue(c.query(), rev)),
  TodoPreset(
    'mine',
    'Mine',
    (c, self, rev) =>
        _sortedByDue(c.query().where((t) => t.owner == self), rev),
  ),
  TodoPreset(
    'shared',
    'Shared',
    (c, self, rev) =>
        _sortedByDue(c.query().where((t) => t.owner != self), rev),
  ),
  TodoPreset(
    'open',
    'Open',
    (c, _, rev) => _sortedByDue(c.query().where((t) => !t.obj.done), rev),
  ),
  TodoPreset(
    'done',
    'Done',
    (c, _, rev) => _sortedByDue(c.query().where((t) => t.obj.done), rev),
  ),
  TodoPreset('overdue', 'Overdue', (c, _, rev) {
    final now = DateTime.now();
    return _sortedByDue(
      c.query().where(
        (t) => !t.obj.done && (t.obj.dueDate?.isBefore(now) ?? false),
      ),
      rev,
    );
  }),
];

final Map<String, TodoPreset> todoPresetsByName = {
  for (final p in todoPresets) p.name: p,
};
