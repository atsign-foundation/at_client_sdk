# Reactive Todo Query in Flutter with StreamBuilder

This guide shows you how to query your todos reactively — filtering for `done=false` and sorting by due date — using `StreamBuilder` in Flutter with the `at_client` / `at_client_flutter` collection API.

---

## Prerequisites

Your `pubspec.yaml` needs:

```yaml
dependencies:
  at_client: ^3.12.0
  at_client_flutter: ^1.1.2
```

---

## Step 1: Define Your Todo Domain Object

Your `Todo` class needs `toJson()` and `fromJson` to work with `AtCollection<T>`. Make sure `done` and `due` are both present and round-trip correctly:

```dart
class Todo {
  final String title;
  bool done;
  DateTime due;

  Todo(this.title, {this.done = false, required this.due});

  Map<String, dynamic> toJson() => {
    'title': title,
    'done': done,
    'due': due.toIso8601String(),
  };

  factory Todo.fromJson(Map<String, dynamic> json) => Todo(
    json['title'] as String,
    done: json['done'] as bool? ?? false,
    due: DateTime.parse(json['due'] as String),
  );
}
```

Key points:
- `done` uses `?? false` to safely handle any stored items that predate the field
- `due` is serialized as an ISO 8601 string so it survives JSON round-trips
- `typeTag` must always be the string literal `'Todo'` — never derive it from `runtimeType` or `$T`, which breaks in release (minified) builds

---

## Step 2: Obtain the AtCollection

Call `atClient.collection(...)` once — typically after auth completes — and cache the result. Never construct `AtCollection` directly.

```dart
late AtCollection<Todo> todos;

Future<void> _initCollection() async {
  todos = await atClient.collection<Todo>(
    'todos.my_app',               // namespace: must contain '.'
    const Duration(days: 7),      // default TTL for new items
    fromJson: Todo.fromJson,       // registers the factory automatically
    typeTag: 'Todo',               // must be a string literal
  );
}
```

Alternatively, register the factory once at app startup and omit `fromJson`/`typeTag` on each `collection()` call:

```dart
// In main() or before any collection() call:
AtCollection.registerFactory<Todo>(Todo.fromJson, typeTag: 'Todo');
```

---

## Step 3: Build the Reactive Query Stream

`Query<T>` is immutable — each modifier returns a new query. Call `.watch()` to get a live `Stream<List<CItem<Todo>>>` that emits an initial snapshot and re-emits on every change that affects the result set.

```dart
Stream<List<CItem<Todo>>> _activeTodosSortedByDue() {
  return todos
      .query()
      .where((item) => !item.obj.done)      // filter: done == false
      .orderBy((item) => item.obj.due)      // sort ascending by due date
      .watch();
}
```

Alternatively, use the typed `wherePath` predicate (preferred for future push-down optimisation on indexed fields):

```dart
// Declare a companion class for typed predicates — do this once, outside your widget
abstract class $Todo {
  static final done = PathField<bool>(
    path: ['obj', 'done'],
    extract: (item) => (item.obj as Todo).done,
  );
  static final due = PathField<DateTime>(
    path: ['obj', 'due'],
    extract: (item) => (item.obj as Todo).due,
  );
}

// Then build the query:
Stream<List<CItem<Todo>>> _activeTodosSortedByDue() {
  return todos
      .query()
      .wherePath($Todo.done.eq(false))
      .orderBy((item) => item.obj.due)
      .watch();
}
```

Both approaches produce identical results at runtime. `wherePath` is more verbose upfront but allows the SDK to introspect your predicates for future index-based acceleration; closure-based `.where()` is opaque to the executor.

---

## Step 4: Use the Stream in a StreamBuilder

`watch()` returns a **single-subscription** stream. For a `StreamBuilder` that is built once and persists, assign the stream to a field (not inline in `build`) so it is not recreated on every rebuild:

```dart
class TodoListScreen extends StatefulWidget {
  const TodoListScreen({super.key});

  @override
  State<TodoListScreen> createState() => _TodoListScreenState();
}

class _TodoListScreenState extends State<TodoListScreen> {
  // Assign the stream once — do NOT call .watch() inside build()
  late final Stream<List<CItem<Todo>>> _stream;

  @override
  void initState() {
    super.initState();
    // todos is your cached AtCollection<Todo> instance
    _stream = todos
        .query()
        .where((item) => !item.obj.done)
        .orderBy((item) => item.obj.due)
        .watch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Active Todos')),
      body: StreamBuilder<List<CItem<Todo>>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No active todos.'));
          }

          final items = snapshot.data!;
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final todo = items[index].obj;
              return ListTile(
                title: Text(todo.title),
                subtitle: Text('Due: ${todo.due.toLocal()}'),
                trailing: IconButton(
                  icon: const Icon(Icons.check_circle_outline),
                  onPressed: () async {
                    // Mark done — the stream will re-emit and the item will disappear
                    items[index].obj.done = true;
                    await todos.update(items[index]);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
```

Why assign in `initState` rather than inline in `build`:
- `watch()` returns a single-subscription stream. Calling it inside `build()` would create a new stream on every rebuild, leaking the previous subscription.
- `StreamBuilder` re-uses the stream reference and does not re-subscribe unless the `stream` argument changes.

---

## Step 5: Multi-listener Scenario (Optional)

If more than one widget or listener needs to subscribe to the same stream, convert it to a broadcast stream:

```dart
_stream = todos
    .query()
    .where((item) => !item.obj.done)
    .orderBy((item) => item.obj.due)
    .watch()
    .asBroadcastStream();
```

---

## How it All Works Together

| Concern | Handled by |
|---------|-----------|
| Filter `done=false` | `.where((item) => !item.obj.done)` or `.wherePath($Todo.done.eq(false))` |
| Sort by due date (ascending) | `.orderBy((item) => item.obj.due)` |
| Live reactivity | `.watch()` — emits initial snapshot + re-emits on every change |
| No server-side filtering | Queries run on-device against the local synced keystore (E2E encryption means the atServer cannot filter plaintext) |
| Stream lifecycle | Single-subscription stream assigned in `initState`, passed to `StreamBuilder` |

`.watch()` uses a delta path when no `limit`/`skip` is applied (as in this example): it maintains a cached list and performs a per-event single-item delta — efficient even for large collections.

---

## Complete Minimal Example

```dart
import 'package:flutter/material.dart';
import 'package:at_client/at_client.dart';

// Assumes AtCollection.registerFactory<Todo>(...) was called at startup
// and `todos` is the cached AtCollection<Todo> from atClient.collection(...)

class ActiveTodosScreen extends StatefulWidget {
  final AtCollection<Todo> todos;
  const ActiveTodosScreen({super.key, required this.todos});

  @override
  State<ActiveTodosScreen> createState() => _ActiveTodosScreenState();
}

class _ActiveTodosScreenState extends State<ActiveTodosScreen> {
  late final Stream<List<CItem<Todo>>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = widget.todos
        .query()
        .where((item) => !item.obj.done)
        .orderBy((item) => item.obj.due)
        .watch();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CItem<Todo>>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const CircularProgressIndicator();
        }
        final items = snapshot.data!;
        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (_, i) => ListTile(
            title: Text(items[i].obj.title),
            subtitle: Text('Due ${items[i].obj.due.toLocal()}'),
          ),
        );
      },
    );
  }
}
```

---

## Common Pitfalls

**Do not call `.watch()` inside `build()`.**
Each call creates a new single-subscription stream. Assign it once in `initState` or via a field initializer.

**Do not use `AtCollectionModel`.**
The entire `AtCollectionModel` hierarchy is deprecated. Always use `AtCollection<T>` via `atClient.collection(...)`.

**`typeTag` must be a string literal.**
Never use `T.toString()`, `runtimeType.toString()`, or string interpolation with a type variable. Release builds minify type names, which will break deserialization for all stored items.

**`namespace` must be fully qualified (contain `.`).**
`'todos'` throws `ArgumentError`. Use `'todos.my_app'` or similar.

**`like`, `inSet`, `between`, `contains`, `startsWith` are not yet implemented.**
These `PathField` operators exist in the API but throw `UnimplementedError` at runtime. Use `.where()` closures for those filter shapes until they are implemented.
