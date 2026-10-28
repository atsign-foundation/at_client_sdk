# Deprecation Guide: What NOT to Use

What at_client 4.0 removed, what it still carries deprecated, and the packages
to avoid. An app upgrading from 3.x follows the upgrade guide, which goes by
the error `dart analyze` reports:

<!-- pyml disable-next-line md013-->
<https://github.com/atsign-foundation/at_client_sdk/blob/trunk/docs/upgrade-to-4.md>

## The Removed `AtCollectionModel` API

at_client 4.0 removed the legacy collection models, which 3.x had marked
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
final collection = await atClient.collection<Todo>('todos.my_app', const Duration(days: 7));
final item = await collection.create(obj: Todo('buy milk'), sharedWith: {'@bob'.toAtsign()});
final all  = await collection.getItems();
await collection.delete(item);
```

---

## Deprecated Packages

| Package                 | Status          | Use instead                                               |
| ----------------------- | --------------- | --------------------------------------------------------- |
| `at_common_flutter`     | ⛔ DEPRECATED   | `at_client_flutter`                                       |
| `at_onboarding_flutter` | ⛔ DISCONTINUED | `at_client_flutter`                                       |
| `at_backupkey_flutter`  | ⛔ DEPRECATED   | Copy `at_client_flutter` backup-key snippet into your app |
| `at_invitation_flutter` | ⛔ DEPRECATED   | `AtClientInvitations` in `at_client`                      |
| `at_sync_ui_flutter`    | ⛔ DEPRECATED   | Avoid; being removed                                      |
| `at_theme_flutter`      | ⛔ DEPRECATED   | Avoid; being removed                                      |
| `at_cli_commons`        | ⛔ DEPRECATED   | `at_client_cli`; its 4.0.0 only re-exports it             |
| `at_onboarding_cli`     | ⛔ DEPRECATED   | `at_client_cli`; its 2.0.0 only re-exports it             |

## Retired auth API (at_client_flutter 2.0, at_auth 4.0)

| Was                                                                     | Now                                                                                           |
| ----------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `AuthService().authenticate(AtAuthRequest(...))` → `AuthResponse`       | `PkamDialog.show(context, atSign:, keys:, preference:)` → `AtClient`, or `Atsign(a).open(...)` |
| `AuthService().onboard(AtOnboardingRequest(...), cramKey)`              | `CramDialog.show(...)` → `AtClient`, or `Atsign(a).activate(...)`                             |
| `FlutterEnrollmentService().enroll(...)` then a `PkamDialog`            | `ApkamActivationDialog.show(...)` → `AtClient`, or `Atsign(a).enroll(...)` then `pending.client(...)` |
| `AtClientManager.getInstance().setCurrentAtSign(...)` after auth        | `AtClientManager.getInstance().use(client)`                                                   |
| `import 'package:at_auth/at_auth.dart'` in an app                       | Nothing; `RegistrarService` comes through the platform package                                |

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

This package is deprecated. Use `AtClientInvitations` from
`package:at_client/at_client_mixins.dart`; the Flutter app in
`packages/at_client_flutter/example/invitations` shows it end to end. Do not
take a dependency on `at_invitation_flutter`.

### at_sync_ui_flutter / at_theme_flutter

Both packages are being deprecated and removed. Do not use them in new projects.

### at_cli_commons / at_onboarding_cli

Deprecated. Their last majors, at_cli_commons 4.0.0 and at_onboarding_cli
2.0.0, only re-export `at_client_cli`, which carries their code. Depend on
`at_client_cli` and import `package:at_client_cli/at_client_cli.dart`; the
command-line table under *Removed in at_client 4.0* below maps what changed.

---

## Removed in at_client 4.0

Code using these no longer compiles. Every one has a replacement, or nothing
replaces it because nothing read it.

| Was                                                                                          | Now                                                                                     |
| -------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `AtClientManager.getInstance().setCurrentAtSign(...)`, `AtClientManager.fromAuthSession(...)` | `Atsign(a).open(...)` (see [15-client-lifecycle.md](15-client-lifecycle.md)), then `use(client)` for code that reads the manager |
| The `AtCollectionModel` family (above)                                                       | `AtClient.collection<T>(...)`                                                           |
| `AtClient.atChops`, `RemoteSecondary.atChops`, the `atChops:` parameters                     | Nothing: a client signs and encrypts with the `AtKeysIo` it was given                   |
| `isDedicated:` on `put`, `get`, `delete`, `notify`, `getMeta`, `notifyList`, `notifyAll`     | Delete the argument                                                                     |
| `sync:` on `executeVerb`, `executeAndParse`                                                  | Delete the argument                                                                     |
| `AtClientPreference.commitLogPath`, `keyStoreSecret`, `downloadPath`, `atProtocolEmitted`, `outboundConnectionTimeout` | Delete the assignment; nothing read them                     |
| `AtClientPreference.enforceNamespace`                                                        | Delete the assignment; every key except a `local:` one names a namespace                |
| `AtClientPreference.decryptPackets`, `pathToCerts`, `tlsKeysSavePath`                        | `secureSocketLookUps(config: SecureSocketConfig()..pathToCerts = ...)` as `lookUps:`    |
| `atClient.stream(...)`, `sendStreamAck(...)`                                                 | `put` the value, or `notify` it                                                         |
| `uploadFile`, `downloadFile`, `reuploadFiles`, `shareFiles`                                  | None; file transfer belongs in the app                                                  |
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

| Was (at_onboarding_cli 1.x, at_cli_commons 3.x)                    | Now (at_client_cli 1.0)                                                                  |
| ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------- |
| `AtOnboardingServiceImpl(atSign, pref).authenticate()`, `.atClient` | `CLIBase.fromCommandLineArgs(...)`, or `Atsign(atSign).open(...)` with `CliKeys`        |
| `AtOnboardingPreference`                                           | `AtClientPreference`; the keyfile is `CliKeys.fileFor(atSign, path:, passPhrase:)` and the store `CliKeys.storageFor(atSign, program:, path:)` |
| `createAtClient(...)`                                              | `CLIBase`                                                                                |
| `OnboardingUtil`                                                   | `at_activate onboard` fetches a CRAM secret, and `at_register` a free atSign             |
| `AuthKeyType`                                                      | None: read a keyfile with `CliKeys.fileFor(atSign).read(atSign)`                         |
| `MySyncProgressListener`                                           | A `SyncProgressListener` of the program's own                                            |
| `CLIBase` throwing `AtOpenRefusedException`                        | `AtCredentialRefusedException` for every refusal, `SecondaryNotFoundException` for an atSign the atDirectory has no atServer for, `SecondaryServerConnectivityException` only for an outage |

## Deprecated, still present in at_client 4.0

These still compile, with a deprecation warning. Avoid them in new code. The
three `AtClientPreference` fields go in 5.0.

| Deprecated                                                   | Instead                                                                           |
| ------------------------------------------------------------ | --------------------------------------------------------------------------------- |
| `AtClientPreference.hiveStoragePath`                         | `HiveAtClientStorage(atSign:, storagePath:, closedByClient: true)` as `storage:`; at_client ignores the field, and at_client_flutter's dialogs read it only when given no storage |
| `AtClientPreference.isLocalStoreRequired`, `hashingAlgoType` | Nothing; at_client reads neither                                                  |
| `AtClientManager.getInstance().syncService`, `.notificationService` | `client.syncService`, `client.notificationService`                         |

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
- `packages/at_client_flutter/example/todos/lib/services/todos_service.dart`
