# Deprecation Guide: What NOT to Use

What at_client 4.0 removed, what it still carries deprecated, and the packages
to avoid. An app upgrading from at_client 3.x follows the upgrade guide, which
goes by the error `dart analyze` reports:

<!-- pyml disable-next-line md013-->
<https://github.com/atsign-foundation/at_client_sdk/blob/trunk/docs/upgrade-to-4.md>

## The Removed `AtCollectionModel` API

at_client 4.0 removed the legacy collection models, which at_client 3.x had marked
`@Deprecated("Use AtClient.collection for collection-style operations")`:

- `AtCollectionModel<T>`
- `AtJsonCollectionModel`
- `AtCollectionModelFactory`, `AtJsonCollectionModelFactory`
- `AtCollectionQueryOperations`
- `AtCollectionModelStreamOperations`
- `AtCollectionModelOperations`
- `KeyMaker`, `ObjectLifeCycleOptions`

Code using them no longer compiles against at_client 4.0. Start all new code
with `AtCollection<T>`, and move old code with the table below.

---

## Migration Table: Old → New

<!-- pyml disable-num-lines 12 md013-->
| Old API                                                  | New API                                                                          |
| -------------------------------------------------------- | -------------------------------------------------------------------------------- |
| `class MyModel extends AtCollectionModel<MyModel>`       | Implement `toJson`/`fromJson` + register factory                                 |
| `AtCollectionModel.registerFactories([...])`             | `AtCollection.registerFactory<T>(T.fromJson, typeTag: 'T')`                      |
| `await model.save()`                                     | `await collection.create(obj: model)` or `collection.upsert(id: id, obj: model)` |
| `await model.share(sharedWith: ['@bob'])`                | `sharedWith` param on `create`/`upsert`, or `updateSharedWith`                   |
| `await model.unshare(sharedWith: ['@bob'])`              | `updateSharedWith(item, item.sharedWith..remove('@bob'.toAtsign()))`             |
| `await model.delete()`                                   | `await collection.delete(item)`                                                  |
| `await MyModel.getModel(id, namespace, sharedBy)`        | `await collection.get(id, owner)`                                                |
| `await MyModel.getModelsByCollectionName(ns)`            | `await collection.getItems()`                                                    |
| `await MyModel.getModelsSharedWith(atSign)`              | `await collection.getItems().then(l => l.where(...).toList())`                   |
| `model.streams.save()` → `Stream<AtOperationItemStatus>` | `collection.create(...)` then listen to `collection.updates`                     |

### Before (removed in at_client 4.0)

For recognising old code only; never show it in an answer.

```dart
// Old way — removed in at_client 4.0; does not compile
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
final collection = await atClient.collection<Todo>(
    'todos.my_app', const Duration(days: 7));
final item = await collection.create(obj: Todo('buy milk'), sharedWith: {'@bob'.toAtsign()});
final all  = await collection.getItems();
await collection.delete(item);
```

---

## Deprecated and discontinued packages

Which packages an app never adds, which are in migration, and what replaces
each, is in [06-package-map.md](06-package-map.md).

## Retired auth API (at_client_flutter 2.0, at_auth 4.0)

<!-- pyml disable-num-lines 7 md013-->
| Was                                                                     | Now                                                                                           |
| ----------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `AuthService().authenticate(AtAuthRequest(...))` → `AuthResponse`       | `PkamDialog.show(context, atSign:, keys:, preference:)` → `AtClient`, or `const AtsignFlows().open(a, ...)` |
| `AuthService().onboard(AtOnboardingRequest(...), cramKey)`              | `CramDialog.show(...)` → `AtClient`, or `const AtsignFlows().activate(a, ...)`                           |
| `FlutterEnrollmentService().enroll(...)` then a `PkamDialog`            | `ApkamActivationDialog.show(...)` → `AtClient`, or `const AtsignFlows().enroll(a, ...)` then `pending.client(...)` |
| `AtClientManager.getInstance().setCurrentAtSign(...)` after auth        | `AtClientManager.getInstance().use(client)`                                                   |
| `import 'package:at_auth/at_auth.dart'` in an app                       | Nothing; `RegistrarService` comes through the platform package                                |

See the at-client-skills-flutter skill and
[15-client-lifecycle.md](15-client-lifecycle.md).

---

## Removed in at_client 4.0

Code using these no longer compiles. Every one has a replacement, or nothing
replaces it because nothing read it.

<!-- pyml disable-num-lines 28 md013-->
| Was                                                                                          | Now                                                                                     |
| -------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `AtClientManager.getInstance().setCurrentAtSign(...)`, `AtClientManager.fromAuthSession(...)` | `Atsign(a).open(...)` (see [15-client-lifecycle.md](15-client-lifecycle.md)), then `use(client)` for code that reads the manager |
| The `AtCollectionModel` family (above)                                                       | `AtClient.collection<T>(...)`                                                           |
| `AtClient.atChops`, `RemoteSecondary.atChops`, the `atChops:` parameters                     | Nothing: a client signs and encrypts with the `AtKeysIo` it was given                   |
| `isDedicated:` on `put`, `get`, `delete`, `notify`, `getMeta`, `notifyList`                  | Delete the argument                                                                     |
| `atClient.notify(...)`, `notifyChange(...)`, `notifyAll(...)`                                | `notificationService.notify(...)`, once per recipient                                   |
| `atClient.startMonitor(...)`                                                                 | `notificationService.subscribe(...)`                                                    |
| `startCompactionJob`, `stopCompactionJob`                                                    | none; they did nothing                                                                  |
| `NotificationParams.forText(...)`                                                            | `NotificationParams.forUpdate(...)`; atServers refuse text notifications                |
| `notificationService.send(namespace: ...)`                                                   | `send(idAndNamespace: ...)`, the same value                                             |
| `AtClientManager.getInstance().syncService`, `.notificationService`                          | `client.syncService`, `client.notificationService`                                      |
| `syncService.sync(onDone: ...)`, `setOnDone(...)`                                            | a `SyncProgressListener` added with `addProgressListener`                               |
| `syncService.sync(onError: ...)`                                                             | a `SyncProgressListener`, which hears each sync that fails                              |
| `AtServiceFactory.atClient(...)`                                                             | `Atsign(a).open(...)` or `buildAtClient(...)`                                           |
| `AtClientPreference.syncStrategy`, `SyncStrategy`                                            | nothing; they did nothing                                                               |
| `AtClientPreference.isLocalStoreRequired`, `useAtChops`, `hashingAlgoType`                   | nothing; they did nothing                                                               |
| `AtClientPreference.privateKey`, `signingAlgoType`                                           | keys in the client's `AtKeysIo`                                                         |
| `PutRequestOptions.storeSharedKeyEncryptedMetadata`, `RemoteSecondary(signingAlgoType:)`     | nothing; they did nothing                                                               |
| `sync:` on `executeVerb`, `executeAndParse`                                                  | Delete the argument                                                                     |
| `AtClientPreference.commitLogPath`, `keyStoreSecret`, `downloadPath`, `atProtocolEmitted`, `outboundConnectionTimeout` | Delete the assignment; nothing read them                     |
| `AtClientPreference.enforceNamespace`                                                        | Delete the assignment; every key except a `local:` one names a namespace                |
| `AtClientPreference.decryptPackets`, `pathToCerts`, `tlsKeysSavePath`                        | `secureSocketLookUps(config: SecureSocketConfig()..pathToCerts = ...)` as `lookUps:`    |
| `atClient.stream(...)`, `sendStreamAck(...)`                                                 | `put` the value, or `notify` it                                                         |
| `uploadFile`, `downloadFile`, `reuploadFiles`, `shareFiles`                                  | None; file transfer belongs in the app — see [10-architecture-guide.md](10-architecture-guide.md) |
| `ConnectivityListener`                                                                       | A connectivity package of the app's choosing                                            |
| `RemoteSecondary.isAvailable()`                                                              | `checkAtSignServer(lookUp, atSign)`                                                     |
| `atClient.persistenceBundle`                                                                 | The `AtClientStorage` the client was given                                              |

Every verb that builds a client now requires its storage, transport and
atDirectory finder: `storage:` (`open`, `activate`, `pending.client`),
`lookUps:` and `secondaryAddressFinder:` (`open`, `activate`, `enroll`,
`resumeEnrollment`). A compile error naming one of them is fixed by passing
it, as [15-client-lifecycle.md](15-client-lifecycle.md) shows.

### Command-line programs: at_onboarding_cli and at_cli_commons

Both packages' code lives in `at_client_cli`. A program depends on
`at_client_cli` alone and imports `package:at_client_cli/at_client_cli.dart`.

<!-- pyml disable-num-lines 9 md013-->
| Was (at_onboarding_cli 1.x, at_cli_commons 3.x)                    | Now (at_client_cli)                                                                      |
| ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------- |
| `AtOnboardingServiceImpl(atSign, pref).authenticate()`, `.atClient` | `CLIBase.fromCommandLineArgs(...)`, or `Atsign(atSign).open(...)` with `CliKeys`        |
| `AtOnboardingPreference`                                           | `AtClientPreference`; the keyfile is `CliKeys.fileFor(atSign, path:, passPhrase:)` and the store `CliKeys.storageFor(atSign, program:, path:)` |
| `createAtClient(...)`                                              | Unchanged, from `at_client_cli`: the client at_activate's commands open                  |
| `OnboardingUtil`                                                   | `at_activate onboard` fetches a CRAM secret, and `at_register` a free atSign             |
| `AuthKeyType`                                                      | None: read a keyfile with `CliKeys.fileFor(atSign).read(atSign)`                         |
| `MySyncProgressListener`                                           | A `SyncProgressListener` of the program's own                                            |
| `CLIBase` throwing `AtOpenRefusedException`                        | `AtCredentialRefusedException` for every refusal, `SecondaryNotFoundException` for an atSign the atDirectory has no atServer for, `SecondaryServerConnectivityException` only for an outage |

## Deprecated, still present in at_client 4.0

These still compile, with a deprecation warning. Avoid them in new code.

<!-- pyml disable-num-lines 3 md013-->
| Deprecated                                                   | Instead                                                                           |
| ------------------------------------------------------------ | --------------------------------------------------------------------------------- |
| `AtClientPreference.hiveStoragePath`                         | `HiveAtClientStorage(atSign:, storagePath:, closedByClient: true)` as `storage:`; at_client ignores the field, and at_client_flutter's dialogs read it only when given no storage |

---

## Canonical examples using the modern API

- `packages/at_client/example/bin/collections_primitives.dart`
- `packages/at_client/example/bin/collections_domain_objects.dart`
- `packages/at_client_flutter/example/todos/lib/services/todos_service.dart`
