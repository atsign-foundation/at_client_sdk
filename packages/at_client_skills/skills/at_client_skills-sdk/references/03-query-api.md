# Query\<T> API Reference

`Query<T>` is a composable, immutable, value-typed query builder over an
`AtCollection<T>`.

**Key properties:**

- **Immutable** — every modifier returns a new `Query<T>`. Store, pass around,
  and reuse safely
- **On-device execution** — queries run against the local synced keystore.
  Under E2E encryption the atServer cannot filter plaintext on your behalf;
  on-device is the only correct model
- Obtain via `collection.query()`

---

## Builder Methods (modifiers — return new `Query<T>`)

### `where(bool Function(CItem<T> item) predicate)`

Adds a closure predicate. Multiple `.where()` calls are AND'd together.

```dart
todos.query()
    .where((t) => !t.obj.done)
    .where((t) => t.obj.due.isBefore(DateTime.now()));
```

### `wherePath(Predicate predicate)`

Adds a typed `PathField`-based predicate. AND'd with any `.where()` clauses.
A future indexed executor can inspect and push these down to secondary indexes
(closure-based `.where()` predicates are opaque to introspection).

```dart
todos.query()
    .wherePath($Todo.done.eq(false))
    .wherePath($Todo.due.lt(DateTime.now()));
```

See the **PathField section** below for declaring `$YourType` companion classes.

### `orderBy(Comparable<dynamic> Function(CItem<T>) keyFn, {bool descending = false})`

Sets the primary sort. A subsequent `orderBy` **replaces** the previous sort —
call `thenBy` to add tiebreakers without resetting.

### `thenBy(Comparable<dynamic> Function(CItem<T>) keyFn, {bool descending = false})`

Adds a tiebreaker sort key. Requires a prior `orderBy` — throws `StateError`
otherwise.

```dart
todos.query()
    .orderBy((t) => t.obj.due)
    .thenBy((t) => t.obj.title, descending: true)
    .thenBy((t) => t.createdAt);
```

### `limit(int n)`

Keeps at most `n` items after filter + sort + skip. Throws `ArgumentError` if
`n < 0`.

### `skip(int n)`

Skips the first `n` items after filter + sort, before limit. Throws
`ArgumentError` if `n < 0`.

---

## Terminal Methods (execute the query)

### `Future<List<CItem<T>>> get()`

One-shot fetch. Reads local store once, applies full spec, returns list.

### ~~`fetch()`~~ → `get()`

Deprecated alias for `get()`. Migrating: replace `.fetch()` with `.get()`.

### `Stream<List<CItem<T>>> watch()`

Live reactive terminal. Emits an initial snapshot on subscribe, then re-emits a
fresh snapshot on every update or delete that could affect the result set.

**Delta path (no `limit`/`skip`):** maintains a cached list; per-event
single-item delta — fast even for large collections.  
**Paginated path (with `limit`/`skip`):** falls back to full `get()` on
each event.

Returns a **single-subscription** stream. Use `.asBroadcastStream()` for
multi-listener UIs.

```dart
// Flutter pattern
@override
Widget build(BuildContext context) {
  return StreamBuilder<List<CItem<Todo>>>(
    stream: todos.query().where((t) => !t.obj.done).watch(),
    builder: (ctx, snap) {
      if (!snap.hasData) return const CircularProgressIndicator();
      return ListView(children: snap.data!.map((t) => TodoTile(t)).toList());
    },
  );
}
```

### `Future<int> count()`

Number of items matching the full spec. Equivalent to `(await get()).length`.

### `Future<bool> any([bool Function(CItem<T>)? predicate])`

True if at least one item matches. Short-circuits on first match.
Does **not** apply `orderBy`, `skip`, or `limit`.

An optional predicate is AND'd with accumulated `.where()` clauses:

```dart
final hasDone = await todos.query().any((t) => t.obj.done);
```

### `Future<CItem<T>?> firstOrNull()`

First item matching the spec. Without `orderBy`: stream short-circuits on
first match. With `orderBy`: fetches and sorts full result set, returns first.

### `Future<CItem<T>> first()`

Same as `firstOrNull()` but throws `StateError` if nothing matches.

### `Future<List<CItem<T>>> distinct<K>(K Function(CItem<T>) keyFn)`

One-shot fetch with duplicates removed by key. First item per key wins (apply
`orderBy` first to control which item wins).

### `Future<Map<K, List<CItem<T>>>> groupBy<K>(K Function(CItem<T>) keyFn)`

Groups matching items by a derived key. Runs the full spec first.

```dart
final byOwner = await todos.query().groupBy((t) => t.owner);
// Map<Atsign, List<CItem<Todo>>>
```

---

## Reactive Multi-level Terminals

### `Stream<List<WithChildren<T, U>>> watchWithSub<U>({required String subName, required Duration subDefaultExpiration, U Function(Map<String,dynamic>)? subFromJson, String? subTypeTag})`

Joins each parent matching this query with its children from a named
sub-collection. Re-emits on any parent update/delete AND any child
update/delete within any current parent.

```dart
final stream = todos.query()
    .where((t) => !t.obj.done)
    .watchWithSub<TodoNote>(
      subName: 'notes',
      subDefaultExpiration: const Duration(days: 30),
      subFromJson: TodoNote.fromJson,
      subTypeTag: 'TodoNote',
    );
// Stream<List<WithChildren<Todo, TodoNote>>>

stream.listen((rows) {
  for (final row in rows) {
    final todo  = row.parent;    // CItem<Todo>
    final notes = row.children;  // List<CItem<TodoNote>>
  }
});
```

Child subscriptions are cancelled when a parent leaves the result set or the
outer stream is cancelled.

### `Stream<List<TreeNode<T>>> watchWithTree(List<SubSpec<dynamic>> subSpecs)`

Multi-level generalisation of `watchWithSub`. Declare the tree shape with
`SubSpec<U>`.

```dart
final stream = posts.query().watchWithTree([
  SubSpec<Comment>(
    subName: 'comments',
    subDefaultExpiration: const Duration(days: 30),
    subFromJson: Comment.fromJson,
    subTypeTag: 'Comment',
    children: [
      SubSpec<Reply>(
        subName: 'replies',
        subDefaultExpiration: const Duration(days: 30),
        subFromJson: Reply.fromJson,
        subTypeTag: 'Reply',
      ),
    ],
  ),
]);
// Stream<List<TreeNode<Post>>>

stream.listen((tree) {
  for (final node in tree) {
    final post = node.parent;                            // CItem<Post>
    final comments = node.branches['comments'] ?? [];   // List<TreeNode<dynamic>>
    for (final c in comments) {
      final replies = c.branches['replies'] ?? [];       // List<TreeNode<dynamic>>
    }
  }
});
```

**When to use `watchWithSub` vs `watchWithTree`:**

- 2 levels (parent + one child type) → `watchWithSub<U>` —
  strongly typed, simpler
- 3+ levels or mixed child types → `watchWithTree` — arbitrary depth,
  `TreeNode<dynamic>` branches

---

## PathField\<V> and the Typed Predicate AST

`PathField<V>` creates typed, introspectable predicates for `wherePath`.

### Declaring a companion class

```dart
abstract class $Todo {
  static final done = PathField<bool>(
    path: ['obj', 'done'],
    extract: (item) => (item.obj as Todo).done,
  );
  static final due = PathField<DateTime>(
    path: ['obj', 'due'],
    extract: (item) => (item.obj as Todo).due,
  );
  static final priority = PathField<int>(
    path: ['obj', 'priority'],
    extract: (item) => (item.obj as Todo).priority,
  );
  // Nullable field example:
  static final note = PathField<String?>(
    path: ['obj', 'note'],
    extract: (item) => (item.obj as Todo).note,
  );
}
```

### PathField operators

| Operator | Available on | Returns |
| ---------- | ------------- | --------- |
| `.eq(value)` | All `PathField<V>` | `Predicate` |
| `.neq(value)` | All `PathField<V>` | `Predicate` |
| `.lt(value)` | `PathField<V extends Comparable>` | `Predicate` |
| `.lte(value)` | `PathField<V extends Comparable>` | `Predicate` |
| `.gt(value)` | `PathField<V extends Comparable>` | `Predicate` |
| `.gte(value)` | `PathField<V extends Comparable>` | `Predicate` |
| `.isNull` | `PathField<V?>` (nullable) | `Predicate` |
| `.isNotNull` | `PathField<V?>` (nullable) | `Predicate` |

> **Note:** `like`, `inSet`, `between`, `contains`, `startsWith` are declared in
> `PredicateOp` but throw `UnimplementedError` at runtime. Use `.where()`
> closures for those cases until they are implemented.

### Predicate combinators

```dart
// AND
final andPred = $Todo.done.eq(false).and($Todo.priority.gte(2));

// OR
final orPred = $Todo.due.lt(now).or($Todo.priority.eq(1));

// NOT
final notPred = $Todo.done.eq(true).not;

// Nested
final complex = $Todo.done.eq(false)
    .and($Todo.due.lt(soon).or($Todo.priority.eq(1)));
```

### Use with `wherePath`

```dart
final urgent = todos.query()
    .wherePath($Todo.done.eq(false).and($Todo.due.lt(soon)))
    .orderBy((t) => t.obj.due)
    .watch();
```

### SubSpec and TreeNode classes

```dart
final class SubSpec<U> {
  final String subName;
  final Duration subDefaultExpiration;
  final U Function(Map<String, dynamic>)? subFromJson;
  final String? subTypeTag;
  final List<SubSpec<dynamic>> children;   // nested specs
}

final class TreeNode<T> {
  final CItem<T> parent;
  final Map<String, List<TreeNode<dynamic>>> branches;  // keyed by subName
}

final class WithChildren<P, C> {
  final CItem<P> parent;
  final List<CItem<C>> children;
}
```
