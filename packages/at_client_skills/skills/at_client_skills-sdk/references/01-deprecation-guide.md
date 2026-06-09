<!-- verified: at_client ^3.12.0, at_client_flutter ^1.1.2 — update on next minor release -->

# Deprecation Guide: What NOT to Use

## The Deprecated `AtCollectionModel` API

### Exact deprecation annotation (quoted from source)

```dart
@Deprecated("Use AtClient.collection for collection-style operations")
abstract class AtCollectionModel<T> implements AtCollectionModelOperations { ... }
```

All classes in `packages/at_client/lib/src/at_collection/` carry this annotation:
- `AtCollectionModel<T>`
- `AtJsonCollectionModel`
- `AtCollectionModelFactory`
- `AtCollectionQueryOperations`
- `AtCollectionModelStreamOperations`
- `AtCollectionModelOperations`

These classes still compile — Dart only warns, not errors. But any code using them will
become uncompilable in a future major release. Start all new code with `AtCollection<T>`.

---

## Migration Table: Old → New

| Old API | New API |
|---------|---------|
| `class MyModel extends AtCollectionModel<MyModel>` | Implement `toJson`/`fromJson` + register factory |
| `AtCollection.registerFactories([...])` | `AtCollection.registerFactory<T>(T.fromJson, typeTag: 'T')` |
| `await model.save()` | `await collection.create(obj: model)` or `collection.upsert(id: id, obj: model)` |
| `await model.share(sharedWith: ['@bob'])` | `sharedWith` param on `create`/`upsert`, or `updateSharedWith` |
| `await model.unshare(sharedWith: ['@bob'])` | `updateSharedWith(item, item.sharedWith..remove('@bob'.toAtsign()))` |
| `await model.delete()` | `await collection.delete(item)` |
| `await MyModel.getModel(id, namespace, sharedBy)` | `await collection.get(id, owner)` |
| `await MyModel.getModelsByCollectionName(ns)` | `await collection.getItems()` |
| `await MyModel.getModelsSharedWith(atSign)` | `await collection.getItems().then(l => l.where(...).toList())` |
| `model.streams.save()` → `Stream<AtOperationItemStatus>` | `collection.create(...)` then listen to `collection.updates` |

### Before (deprecated)

```dart
// Old way — DO NOT USE
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

// Usage
await todo.save();
await todo.share(sharedWith: ['@bob']);
final todos = await Todo.getModelsByCollectionName('todos', namespace: 'my.app');
```

### After (modern)

```dart
// New way — use this
class Todo {
  String title;
  bool done;

  Todo(this.title, {this.done = false});

  Map<String, dynamic> toJson() => {'title': title, 'done': done};
  factory Todo.fromJson(Map<String, dynamic> j) =>
      Todo(j['title'] as String, done: j['done'] as bool? ?? false);
}

// Register at startup
AtCollection.registerFactory<Todo>(Todo.fromJson, typeTag: 'Todo');

// Usage
final collection = await atClient.collection<Todo>('todos.my_app', const Duration(days: 7));
final item = await collection.create(obj: Todo('buy milk'), sharedWith: {'@bob'.toAtsign()});
final all  = await collection.getItems();
await collection.delete(item);
```

---

## Deprecated Packages

| Package | Status | Use instead |
|---------|--------|-------------|
| `at_common_flutter` | ⛔ DEPRECATED | `at_client_flutter` |
| `at_backupkey_flutter` | ⛔ DEPRECATED | Copy `at_client_flutter` backup-key snippet into your app |
| `at_invitation_flutter` | ⛔ DEPRECATED | Copy `at_client_flutter` invitation snippet into your app |
| `at_sync_ui_flutter` | ⛔ DEPRECATED | Avoid; being removed |
| `at_theme_flutter` | ⛔ DEPRECATED | Avoid; being removed |

### at_common_flutter
The `at_common_flutter` package's own README states: *"Deprecated in favour of
`at_client_flutter`."* Do not add `at_common_flutter` to `pubspec.yaml`. Existing code
using it should migrate to `at_client_flutter` equivalents.

### at_backupkey_flutter
This package has been deleted from the repository. Implement backup-key functionality
by copying the snippet from
`packages/at_client_flutter/example/lib/snippets/at_backup_key.dart`
directly into your own app. Do not take a dependency on `at_backupkey_flutter`.

### at_invitation_flutter
This package is deprecated. Implement invitation functionality by copying the snippet
from `packages/at_client_flutter/example/lib/snippets/at_invitation.dart`
directly into your own app. Do not take a dependency on `at_invitation_flutter`.

### at_sync_ui_flutter / at_theme_flutter
Both packages are being deprecated and removed. Do not use them in new projects.

---

## Packages In Migration (avoid for new projects)

These packages are still published but are in the process of being deprecated.
Their functionality will be replaced by example application code (copy the pattern,
don't depend on the package).

| Package | Status |
|---------|--------|
| `at_chat_flutter` | In migration |
| `at_contacts_flutter` | In migration |
| `at_contacts_group_flutter` | In migration |
| `at_events_flutter` | In migration |
| `at_follows_flutter` | In migration |
| `at_location_flutter` | In migration |
| `at_notify_flutter` | In migration |

For new projects: look at the source of these packages for inspiration, then implement
the pattern directly in your app rather than adding them as dependencies.

---

## Canonical examples using the modern API

- `packages/at_client/example/bin/collections_primitives.dart`
- `packages/at_client/example/bin/collections_domain_objects.dart`
- `packages/at_client_flutter/examples/todos/lib/services/todos_service.dart`
