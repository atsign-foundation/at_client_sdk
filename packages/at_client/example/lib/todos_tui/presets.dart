import 'package:at_client/at_client.dart';

import '../domain_objects.dart';

/// A named filter+sort view over the todos collection. Each preset is
/// a function from `(collection, self, reverse)` to an immutable
/// `Query<Todo>` value, so the rest of the TUI can treat them as
/// first-class references and compose further `.where(...)`s on top.
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

/// Sort by due date ascending, with `null` due-dates sorted last (far-
/// future sentinel). `reverse` flips direction; nulls then sort first,
/// matching the pre-builder `_compareByDue` behaviour.
Query<Todo> sortedByDue(Query<Todo> q, bool reverse) =>
    q.orderBy((t) => t.obj.dueDate ?? DateTime.utc(9999), descending: reverse);

final List<TodoPreset> todoPresets = [
  TodoPreset('all', 'All', (c, _, rev) => sortedByDue(c.query(), rev)),
  TodoPreset(
    'mine',
    'Mine',
    (c, self, rev) => sortedByDue(c.query().where((t) => t.owner == self), rev),
  ),
  TodoPreset(
    'shared',
    'Shared with me',
    (c, self, rev) => sortedByDue(c.query().where((t) => t.owner != self), rev),
  ),
  TodoPreset(
    'open',
    'Open',
    (c, _, rev) => sortedByDue(c.query().where((t) => !t.obj.done), rev),
  ),
  TodoPreset(
    'done',
    'Done',
    (c, _, rev) => sortedByDue(c.query().where((t) => t.obj.done), rev),
  ),
  TodoPreset('overdue', 'Overdue', (c, _, rev) {
    final now = DateTime.now();
    return sortedByDue(
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
