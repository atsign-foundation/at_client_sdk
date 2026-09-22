# Deprecation Guide: What NOT to Use

## The Deprecated `AtCollectionModel` API

### Exact deprecation annotation (quoted from source)

```dart
@Deprecated("Use AtClient.collection for collection-style operations")
abstract class AtCollectionModel<T> implements AtCollectionModelOperations { ... }
```

All classes in `packages/at_client/lib/src/at_collection/` carry this
annotation:

- `AtCollectionModel<T>`
- `AtJsonCollectionModel`
- `AtCollectionModelFactory`
- `AtCollectionQueryOperations`
- `AtCollectionModelStreamOperations`
- `AtCollectionModelOperations`

These classes still compile — Dart only warns, not errors. But any code using
them will become uncompilable in a future major release. Start all new code with
`AtCollection<T>`.

---

## Migration Table: Old → New

| Old API                                                  | New API                                                                          |
| -------------------------------------------------------- | -------------------------------------------------------------------------------- |
| `class MyModel extends AtCollectionModel<MyModel>`       | Implement `toJson`/`fromJson` + register factory                                 |
| `AtCollection.registerFactories([...])`                  | `AtCollection.registerFactory<T>(T.fromJson, typeTag: 'T')`                      |
| `await model.save()`                                     | `await collection.create(obj: model)` or `collection.upsert(id: id, obj: model)` |
| `await model.share(sharedWith: ['@bob'])`                | `sharedWith` param on `create`/`upsert`, or `updateSharedWith`                   |
| `await model.unshare(sharedWith: ['@bob'])`              | `updateSharedWith(item, item.sharedWith..remove('@bob'.toAtsign()))`             |
| `await model.delete()`                                   | `await collection.delete(item)`                                                  |
| `await MyModel.getModel(id, namespace, sharedBy)`        | `await collection.get(id, owner)`                                                |
| `await MyModel.getModelsByCollectionName(ns)`            | `await collection.getItems()`                                                    |
| `await MyModel.getModelsSharedWith(atSign)`              | `await collection.getItems().then(l => l.where(...).toList())`                   |
| `model.streams.save()` → `Stream<AtOperationItemStatus>` | `collection.create(...)` then listen to `collection.updates`                     |

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

## Deprecated `AtClient` methods

These are still on `AtClient`, so they compile and autocomplete — but each is
annotated `@Deprecated` and several are slated for removal at the next major.
Reaching for one is the usual sign an agent is working from older examples.

| Was | Now |
| --- | --- |
| `atClient.notify(...)`, `notifyAll(...)`, `notifyChange(...)` | `atClient.notificationService.send(...)` |
| `atClient.startMonitor(...)` | `atClient.notificationService.subscribe(...)` |
| `atClient.uploadFile/downloadFile/reuploadFiles/shareFiles` | Nothing in the SDK — moved to the app layer |
| `atClient.stream(...)`, `sendStreamAck(...)` | Nothing in the SDK — same as above |
| `atClient.startCompactionJob()`, `stopCompactionJob()` | Nothing — just stop calling them |
| `atClient.atChops` (getter and setter) | Build the client from its keyfile; nothing outside `at_client` needs it |

**The notification family.** `startMonitor` is annotated *"Obsolete. Use the
NotificationService"*, and the three `notify*` methods likewise. The whole
group predates `NotificationService`; send with `send(...)` and receive with
`subscribe(...)` — see [16-notifications.md](16-notifications.md). On
`NotificationParams`, `forText` is *"No longer supported"* and `messageType`
is superseded by `MessageType.key`.

**`send(namespace:)` is now `send(idAndNamespace:)`.** Same value, same wire
format — only the parameter name changed. Supply exactly one of the two;
both or neither throws `ArgumentError`.

**File transfer has no SDK replacement.** All four methods are annotated
*"Method will be removed from SDK since method is moved to app layer"*, and
the stream pair carries its own removal notice. There is no drop-in: encrypt
the file client-side, upload the ciphertext wherever you like, and share the
URL and decryption key as a normal encrypted item. That pattern is in
[10-architecture-guide.md](10-architecture-guide.md).

**Compaction is already gone.** `startCompactionJob` / `stopCompactionJob`
are annotated as removed along with commit-log compaction itself, which the
commit-log-free keystore did away with. Nothing replaces them — code calling
them is doing nothing and can drop the calls.

### Deprecated `AtClientPreference` fields

| Was | Now |
| --- | --- |
| `hiveStoragePath`, `commitLogPath` | `HiveAtClientStorage(atSign:, storagePath:)` passed as `storage` |
| `decryptPackets`, `tlsKeysSavePath`, `pathToCerts` | `lookUps: secureSocketLookUps(config: SecureSocketConfig(...))` |
| `syncStrategy` | `SyncService` |
| `useAtChops` | Nothing — at_chops is used by default |

The transport fields moved because configuring the socket is the
`AtLookUpFactory`'s job, not the preference's — see
[15-client-lifecycle.md](15-client-lifecycle.md).

## Deprecated Packages

| Package                 | Status          | Use instead                                               |
| ----------------------- | --------------- | --------------------------------------------------------- |
| `at_common_flutter`     | ⛔ DEPRECATED   | `at_client_flutter`                                       |
| `at_onboarding_flutter` | ⛔ DISCONTINUED | `at_client_flutter`                                       |
| `at_backupkey_flutter`  | ⛔ DEPRECATED   | Copy `at_client_flutter` backup-key snippet into your app |
| `at_invitation_flutter` | ⛔ DEPRECATED   | Copy `at_client_flutter` invitation snippet into your app |
| `at_sync_ui_flutter`    | ⛔ DEPRECATED   | Avoid; being removed                                      |
| `at_theme_flutter`      | ⛔ DEPRECATED   | Avoid; being removed                                      |

## Retired auth API (at_client_flutter 2.0, at_auth 4.0)

| Was                                                                     | Now                                                                                           |
| ----------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `AuthService().authenticate(AtAuthRequest(...))` → `AuthResponse`       | `PkamDialog.show(context, atSign:, keys:, preference:)` → `AtClient`, or `Atsign(a).open(...)` |
| `AuthService().onboard(AtOnboardingRequest(...), cramKey)`              | `CramDialog.show(...)` → `AtClient`, or `Atsign(a).activate(...)`                             |
| `FlutterEnrollmentService().enroll(...)` then a `PkamDialog`            | `ApkamActivationDialog.show(...)` → `AtClient`, or `Atsign(a).enroll(...)` then `pending.client(...)` |
| `AtClientManager.getInstance().setCurrentAtSign(...)` after auth        | `AtClientManager.getInstance().use(client)`                                                   |
| `AtClientPreference.hiveStoragePath` / `.commitLogPath`                 | `HiveAtClientStorage(atSign:, storagePath:)` passed as `storage`                              |
| `import 'package:at_auth/at_auth.dart'` in an app                       | Nothing; `RegistrarService` comes through `at_client_flutter`                                 |

See [05-flutter-auth.md](05-flutter-auth.md) and
[15-client-lifecycle.md](15-client-lifecycle.md).

### at_common_flutter

The `at_common_flutter` package's own README states: _"Deprecated in favour of
`at_client_flutter`."_ Do not add `at_common_flutter` to `pubspec.yaml`.
Existing code
using it should migrate to `at_client_flutter` equivalents.

### at_onboarding_flutter

**Discontinued.** pub.dev marks this package discontinued and names
`at_client_flutter` as its replacement. Do not add `at_onboarding_flutter` to
`pubspec.yaml`. Onboarding and authentication belong to the `at_client_flutter`
dialogs — see [05-flutter-auth.md](05-flutter-auth.md) for all four flows (CRAM
activation, `.atKeys` file, device keychain, APKAM enrolment).

### at_backupkey_flutter

This package has been deleted from the repository. Implement backup-key
functionality
by copying the snippet from
`packages/at_client_flutter/example/lib/snippets/at_backup_key.dart`
directly into your own app. Do not take a dependency on `at_backupkey_flutter`.

### at_invitation_flutter

This package is deprecated. Implement invitation functionality by copying the
snippet
from `packages/at_client_flutter/example/lib/snippets/at_invitation.dart`
directly into your own app. Do not take a dependency on `at_invitation_flutter`.

### at_sync_ui_flutter / at_theme_flutter

Both packages are being deprecated and removed. Do not use them in new projects.

---

## Packages In Migration (avoid for new projects)

These packages are still published but are in the process of being deprecated.
Their functionality will be replaced by example application code (copy the
pattern, don't depend on the package).

| Package                     | Status       |
| --------------------------- | ------------ |
| `at_chat_flutter`           | In migration |
| `at_contacts_flutter`       | In migration |
| `at_contacts_group_flutter` | In migration |
| `at_events_flutter`         | In migration |
| `at_follows_flutter`        | In migration |
| `at_location_flutter`       | In migration |
| `at_notify_flutter`         | In migration |

For new projects: look at the source of these packages for inspiration, then
implement the pattern directly in your app rather than adding them as
dependencies.

---

## Canonical examples using the modern API

- `packages/at_client/example/bin/collections_primitives.dart`
- `packages/at_client/example/bin/collections_domain_objects.dart`
- `packages/at_client_flutter/examples/todos/lib/services/todos_service.dart`
