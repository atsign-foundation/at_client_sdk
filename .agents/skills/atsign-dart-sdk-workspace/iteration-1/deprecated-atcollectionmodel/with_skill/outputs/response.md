# How to Store Data in Your Dart App with the atSDK

## Important: AtCollectionModel is Deprecated

`AtCollectionModel` is **deprecated** and must not be used in new code. The entire `AtCollectionModel` hierarchy carries this annotation in the SDK source:

```dart
@Deprecated("Use AtClient.collection for collection-style operations")
abstract class AtCollectionModel<T> implements AtCollectionModelOperations { ... }
```

This includes:
- `AtCollectionModel<T>`
- `AtJsonCollectionModel`
- `AtCollectionModelFactory`
- `AtCollectionQueryOperations`
- `AtCollectionModelStreamOperations`
- `AtCollectionModelOperations`

These classes still compile today (Dart emits a warning, not an error), but they will become uncompilable in a future major release. **Start all new code with `AtCollection<T>`.**

---

## The Modern API: AtCollection\<T>

Use `AtCollection<T>` obtained via `atClient.collection(...)`. Never construct `AtCollection` directly and never extend `AtCollectionModel`.

### 1. Add the Correct Package

```yaml
# pubspec.yaml
dependencies:
  at_client: ^3.12.0            # Dart CLI / server / IoT
  # Add at_client_flutter: ^1.1.2 if building a Flutter app
```

Do **not** add `at_common_flutter` or `at_backupkey_flutter` — both are deprecated.

---

### 2. Define Your Domain Object

Your model class does not extend anything special. It just needs `toJson` and `fromJson`:

```dart
class Todo {
  String title;
  bool done;
  DateTime due;

  Todo(this.title, {this.done = false, required this.due});

  Map<String, dynamic> toJson() => {
    'title': title,
    'done': done,
    'due': due.toIso8601String(),
  };

  factory Todo.fromJson(Map<String, dynamic> j) => Todo(
    j['title'] as String,
    done: j['done'] as bool? ?? false,
    due: DateTime.parse(j['due'] as String),
  );
}
```

Key rules:
- `typeTag` must be a **string literal** — never `T.toString()`. Dart minifiers rename types in release builds, which would break deserialization.
- Primitives (`String`, `Map<String,dynamic>`, `List`, `Uint8List`) need no factory registration.
- Use `typeTag: 'binary'` for `Uint8List`.

---

### 3. Register the Factory at Startup

Call this **once at startup**, before any `atClient.collection()` call:

```dart
AtCollection.registerFactory<Todo>(Todo.fromJson, typeTag: 'Todo');
```

---

### 4. Get a Collection

```dart
final todos = await atClient.collection<Todo>(
  'todos.my_app',                    // namespace — MUST contain '.' (fully qualified)
  const Duration(days: 7),           // defaultExpiration for new items
  fromJson: Todo.fromJson,           // auto-registers factory; typeTag is required with this
  typeTag: 'Todo',                   // string literal — NOT T.toString()
  cleanupOrphansOnCreation: true,    // recommended when using sub-collections
  eventSource: EventSource.both,     // default
);
```

The namespace **must contain a `.`** (e.g. `'todos.my_app'`) — the call throws `ArgumentError` if it does not.

Collections are cached per `(namespace, eventSource)` pair. The same namespace with a different `eventSource` gives a separate instance.

---

### 5. CRUD Operations

```dart
// Create — throws StateError if the id already exists
final item = await todos.create(
  obj: Todo('buy milk', due: DateTime.now().add(const Duration(days: 1))),
  sharedWith: {'@bob'.toAtsign()},
);

// Upsert — idempotent, safe to call multiple times with the same id
await todos.upsert(
  id: 'my-known-id',
  obj: Todo('buy milk', due: DateTime.now().add(const Duration(days: 1))),
);

// Update — mutate the object, then persist the item
item.obj.done = true;
await todos.update(item);

// Change recipients without rewriting the item data
await todos.updateSharedWith(item, {'@alice'.toAtsign(), '@carol'.toAtsign()});

// Delete
await todos.delete(item);                // throws StateError if item has sub-items
await todos.delete(item, cascade: true); // removes self-owned descendants first
```

---

### 6. Reading Data

```dart
final all   = await todos.getItems();
final mine  = await todos.getItems(owner: atClient.atSign);
final one   = await todos.getOrNull('abc', atClient.atSign); // null if not found
final one2  = await todos.get('abc', atClient.atSign);        // throws if not found
final found = await todos.exists('abc', atClient.atSign);

// Streaming — decode errors surface as stream errors, not silently swallowed
todos.getItemsAsStream()
    .handleError((e) => print('decode error: $e'))
    .listen((item) => print(item.obj.title));
```

---

### 7. Querying Data

Queries are **immutable** — each modifier returns a new `Query<T>`. Filtering is always **on-device** (E2E encryption means the atServer cannot filter plaintext).

```dart
final q = todos.query()
    .where((t) => !t.obj.done)
    .orderBy((t) => t.obj.due)
    .thenBy((t) => t.obj.title)
    .limit(20);

final list  = await q.get();         // Future<List<CItem<Todo>>>
final live  = q.watch();             // Stream<List<CItem<Todo>>>
final count = await q.count();
final any   = await q.any();
final first = await q.firstOrNull();
```

For future push-down optimisation on indexed fields, use typed predicates with `wherePath`:

```dart
abstract class $Todo {
  static final done = PathField<bool>(
    path: ['obj', 'done'],
    extract: (i) => (i.obj as Todo).done,
  );
  static final due = PathField<DateTime>(
    path: ['obj', 'due'],
    extract: (i) => (i.obj as Todo).due,
  );
}

todos.query()
    .wherePath($Todo.done.eq(false).and($Todo.due.lt(DateTime.now())))
    .watch();
```

---

### 8. Listening to Changes

```dart
collection.updates           // Stream<CItemUpdated>
collection.deletes           // Stream<CItemDeleted>   (item.wasExpired flag)
collection.readReceipts      // Stream<CReadReceipt>   (r.from, r.readAt)
collection.subUpdates        // Stream<CSubItemUpdated>
collection.subDeletes        // Stream<CSubItemDeleted>
collection.availableEvents   // Stream<CItemAvailable>
collection.expiringSoonEvents(leadTime: const Duration(hours: 1))
```

In Flutter, always cancel subscriptions in `dispose()`:

```dart
late StreamSubscription<CItemUpdated> _sub;

@override
void initState() {
  super.initState();
  _sub = collection.updates.listen((_) => setState(() {}));
}

@override
void dispose() {
  _sub.cancel();
  super.dispose();
}
```

---

## Migration Cheatsheet: Old AtCollectionModel vs New AtCollection\<T>

| Old API (deprecated) | New API |
|---|---|
| `class MyModel extends AtCollectionModel<MyModel>` | Plain Dart class with `toJson`/`fromJson` |
| `AtCollection.registerFactories([...])` | `AtCollection.registerFactory<T>(T.fromJson, typeTag: 'T')` |
| `await model.save()` | `await collection.create(obj: model)` or `collection.upsert(id: id, obj: model)` |
| `await model.share(sharedWith: ['@bob'])` | `sharedWith` param on `create`/`upsert`, or `updateSharedWith` |
| `await model.unshare(sharedWith: ['@bob'])` | `updateSharedWith(item, item.sharedWith..remove('@bob'.toAtsign()))` |
| `await model.delete()` | `await collection.delete(item)` |
| `await MyModel.getModel(id, namespace, sharedBy)` | `await collection.get(id, owner)` |
| `await MyModel.getModelsByCollectionName(ns)` | `await collection.getItems()` |
| `model.streams.save()` | `collection.create(...)` then listen to `collection.updates` |

---

## What the Old Code Looked Like (do not copy this)

```dart
// OLD — DO NOT USE
@Deprecated("...")
class Todo extends AtCollectionModel<Todo> {
  String? title;
  bool done = false;

  @override
  String collectionName = 'todos';
  @override
  String namespace = 'my.app';

  @override
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'done': done};

  @override
  Todo fromJson(Map<String, dynamic> json) {
    id = json['id'];
    title = json['title'];
    done = json['done'] ?? false;
    return this;
  }
}

// Old usage
await todo.save();
await todo.share(sharedWith: ['@bob']);
final todos = await Todo.getModelsByCollectionName('todos', namespace: 'my.app');
```

---

## Complete Working Example

```dart
import 'package:at_client/at_client.dart';

// 1. Domain object
class Todo {
  String title;
  bool done;
  DateTime due;

  Todo(this.title, {this.done = false, required this.due});

  Map<String, dynamic> toJson() => {
    'title': title,
    'done': done,
    'due': due.toIso8601String(),
  };

  factory Todo.fromJson(Map<String, dynamic> j) => Todo(
    j['title'] as String,
    done: j['done'] as bool? ?? false,
    due: DateTime.parse(j['due'] as String),
  );
}

// 2. At app startup (before any collection calls)
AtCollection.registerFactory<Todo>(Todo.fromJson, typeTag: 'Todo');

// 3. Get a collection (atClient is your authenticated AtClient instance)
final todos = await atClient.collection<Todo>(
  'todos.my_app',
  const Duration(days: 7),
  fromJson: Todo.fromJson,
  typeTag: 'Todo',
);

// 4. Create
final item = await todos.create(
  obj: Todo('buy milk', due: DateTime.now().add(const Duration(days: 1))),
  sharedWith: {'@bob'.toAtsign()},
);

// 5. Read all
final all = await todos.getItems();
for (final t in all) {
  print('${t.id}: ${t.obj.title} — done: ${t.obj.done}');
}

// 6. Update
item.obj.done = true;
await todos.update(item);

// 7. Delete
await todos.delete(item);

// 8. Live query
todos.query()
    .where((t) => !t.obj.done)
    .orderBy((t) => t.obj.due)
    .watch()
    .listen((items) => print('Active todos: ${items.length}'));
```

---

## Canonical Reference Apps

- `packages/at_client/example/bin/collections_domain_objects.dart` — polymorphic types
- `packages/at_client/example/bin/collections_subcollections.dart` — sub-collections + cascade
- `packages/at_client_flutter/examples/todos/` — canonical Flutter reference app
