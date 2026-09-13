---
name: at_client_skills-sdk
description: >
  Use this skill when a developer is building a Dart or Flutter app that
  depends on at_client or at_client_flutter from pub.dev, stores or shares
  data via the Atsign Protocol, needs onboarding (CRAM new-atsign, atKeys
  file, keychain, APKAM) or APKAM enrollment, asks how to open, own, stop or
  switch an AtClient or read its connection state (online / offline /
  refused), how its sync and notification services start and stop, or asks
  about AtCollection<T>,
  CItem<T>, Query<T>, sub-collections, event streams, read receipts, wherePath
  typed predicates, or watchWithTree deep hierarchies. Also use when the
  developer asks how to send or receive notifications via NotificationService,
  how to do request/response RPC between atsigns (AtRpc), how to run headless
  agents or CLIs (CLIBase) or coordinate multiple agent instances, how to read
  or write directly against the remote atServer (useRemoteAtServer), which
  pub.dev packages to add, how to unit-test without a live atServer, or
  whether to use AtCollection vs notifications+SQLite. Warns
  against deprecated AtCollectionModel, at_common_flutter, at_backupkey_flutter,
  at_invitation_flutter, at_sync_ui_flutter, and at_theme_flutter.
license: BSD-3-Clause
compatibility: Claude Code and any agentskills.io-compatible agent.
user-invocable: true
metadata:
  version: "1.4.0"
  last_modified: "Sun, 13 Sep 2026 00:00:00 GMT"
---

# atsign-dart-sdk Skill

> **Audience:** developers adding `at_client` / `at_client_flutter` to their own
> Dart or Flutter app from pub.dev — not developers editing the SDK repo itself.

---

## 1. CRITICAL: Use the Modern Collection API

**Always use `AtCollection<T>`.** Never use `AtCollectionModel`.

```dart
// ✅ CORRECT — modern API
import 'package:at_client/at_client.dart';
final todos = await atClient.collection<Todo>(
  'todos.my_app',
  const Duration(days: 7),
  fromJson: Todo.fromJson,
  typeTag: 'Todo',
);

// ❌ WRONG — deprecated, do not use
class MyModel extends AtCollectionModel { ... }  // @Deprecated("Use AtClient.collection...")
```

The entire `AtCollectionModel` hierarchy is annotated
`@Deprecated("Use AtClient.collection for collection-style operations")`.

> **If asked how to use `AtCollectionModel`:** do NOT show any
> `AtCollectionModel` code, even in a "before/deprecated" comparison. Show ONLY
> the `AtCollection<T>` pattern above, state it is deprecated, and quote the
> `@Deprecated` message.

Read [references/01-deprecation-guide.md](references/01-deprecation-guide.md)
for the full migration table from old to new API.

---

## 2. Package Map

Install with `dart pub add` — it resolves the latest compatible version:

| Use case                       | packages to add                                                  |
| ------------------------------ | ---------------------------------------------------------------- |
| Dart CLI / server / IoT        | `at_client`                                                      |
| Flutter app                    | `at_client_flutter` (re-exports `at_client` — one dep)           |
| CLI / headless Dart            | `at_client`, `at_cli_commons`                                    |
| Onboarding, login, APKAM       | `at_client` (the `Atsign` verbs) or `at_client_flutter` (dialogs) |
| Raw cryptographic operations   | `at_client` or `at_client_flutter`, plus `at_chops`              |

An app never imports `at_auth`: `at_client` owns onboarding, login and
enrollment (see §11), and `at_client_flutter` re-exports the one at_auth type
an app may want, `RegistrarService`.

**Never add:** `at_common_flutter`, `at_onboarding_flutter` (discontinued — use
the `at_client_flutter` auth dialogs), `at_backupkey_flutter`,
`at_invitation_flutter`, `at_sync_ui_flutter`, `at_theme_flutter`

> **Never hardcode version constraints** for `at_client` / `at_client_flutter`
> (e.g. `at_client: ^3.11.0`) in `pubspec.yaml` or generated templates — run
> `dart pub add` and let pub choose. Pinned constraints go stale between SDK
> releases and cause resolution conflicts; stability comes from a fixed
> `typeTag` string literal (§3), not a fixed SDK version.

Read [references/06-package-map.md](references/06-package-map.md) for
per-use-case checklists and the full list of in-migration packages to avoid.

---

## 3. Getting an AtCollection\<T>

Obtain via `AtClient.collection(...)` — never construct `AtCollection` directly.

```dart
final todos = await atClient.collection<Todo>(
  'todos.my_app',                    // namespace: MUST contain '.' (fully qualified)
  const Duration(days: 7),           // defaultExpiration for new items
  fromJson: Todo.fromJson,           // auto-registers factory; typeTag required with this
  typeTag: 'Todo',                   // pin as a string literal — NOT T.toString()
  cleanupOrphansOnCreation: true,    // recommended when using sub-collections
  eventSource: EventSource.both,     // default (see below)
);
```

- **Cached per `(namespace, eventSource)` pair** — same namespace + different
  eventSource = separate instances
- **`namespace` must contain `.`** (e.g. `'todos.my_app'`) — throws
  `ArgumentError` otherwise
- **`typeTag` is mandatory when `fromJson` is supplied** — always a string
  literal, never derived from `T.toString()` (minifier renames types in
  release builds)

**EventSource:**

| Value                | Events seen                                                   |
| -------------------- | ------------------------------------------------------------- |
| `EventSource.data`   | All local keystore mutations (requires `SyncService` running) |
| `EventSource.notifs` | Cross-atsign writes via notification pipeline only            |
| `EventSource.both`   | Both sources; same change may fire twice (no dedup); default  |

Read [references/02-atcollection-api.md](references/02-atcollection-api.md) for
the complete API surface including `getDescendant`, `cleanupOrphans`, and
`registerFactory`.

---

## 4. CRUD Cheatsheet

```dart
// create — strict: throws StateError if id already exists
final item = await todos.create(
  obj: Todo('buy milk'),
  sharedWith: {'@bob'.toAtsign()},
);

// upsert — idempotent: use for re-runnable publishers
await todos.upsert(id: 'my-known-id', obj: Todo('buy milk'));

// update — mutate, then persist
item.obj.done = true;
await todos.update(item);

// updateSharedWith — change recipients without rewriting the item
await todos.updateSharedWith(item, {'@alice'.toAtsign(), '@carol'.toAtsign()});

// delete
await todos.delete(item);                    // throws StateError if has sub-items
await todos.delete(item, cascade: true);     // removes self-owned descendants first
```

> **Ownership model:** `AtCollection` is **owner-writes-only** — an atsign can
> only mutate items it owns. `update` / `updateSharedWith` / `delete` throw
> `ArgumentError` on an item whose `owner` isn't you. Collaboration is
> **additive**: sharing grants the recipient a *readable* copy, not write
> access. For a peer to contribute, they create their own item and share it
> back — you never edit theirs in place. (Reading a received item works;
> mutating it doesn't.)

---

## 5. Reading Data

```dart
final all = await todos.getItems();
final mine = await todos.getItems(owner: atClient.atSign);
final one  = await todos.getOrNull('abc', atClient.atSign);  // null if not found
final one2 = await todos.get('abc', atClient.atSign);         // throws if not found
final has  = await todos.exists('abc', atClient.atSign);

// Streaming — decode errors surface as stream errors (not silently swallowed)
todos.getItemsAsStream()
    .handleError((e) => _log.warning('decode error: $e'))
    .listen((item) => handle(item));
```

---

## 6. Query Builder

Queries are **immutable** — each modifier returns a new `Query<T>`. Execution
is always **on-device** (E2E encryption means the atServer cannot filter
plaintext).

```dart
final q = todos.query()
    .where((t) => !t.obj.done)
    .orderBy((t) => t.obj.due)
    .thenBy((t) => t.obj.title)
    .limit(20);

final list  = await q.get();          // Future<List<CItem<Todo>>>
final live  = q.watch();              // Stream<List<CItem<Todo>>>
final count = await q.count();
final any   = await q.any();
final first = await q.firstOrNull();
```

**Typed predicates (`wherePath`):** prefer over `.where()` when you want future
push-down optimisation on indexed fields.

```dart
abstract class $Todo {
  static final done = PathField<bool>(path: ['obj','done'], extract: (i) => (i.obj as Todo).done);
  static final due  = PathField<DateTime>(path: ['obj','due'], extract: (i) => (i.obj as Todo).due);
}

todos.query()
    .wherePath($Todo.done.eq(false).and($Todo.due.lt(DateTime.now())))
    .watch();
```

> **Flutter rule:** create a `watch()` stream **once** and hold it in `State`
> (a `late final` field or `initState`); never call `watch()` inside `build()`,
> or each rebuild mints a new stream and drops live updates. Memoise the `Query`
> and recreate the stream only when its inputs change.

Read [references/03-query-api.md](references/03-query-api.md) for all terminals
(`distinct`, `groupBy`, `watchWithSub`, `watchWithTree`) and the full
`PathField` operator list.

---

## 7. Sub-collections

```dart
// Create a sub-collection — NEVER call atClient.collection(composedNamespace)
final notes = todos.subCollection<TodoNote>(
  parent: todo,
  subName: 'notes',                           // must NOT contain '.'
  defaultExpiration: const Duration(days: 30),
  fromJson: TodoNote.fromJson,
  typeTag: 'TodoNote',
);

// Walk ancestry from a CSubItemUpdated event
final leaf = await todos.getDescendant<Reply>(
  ancestry: event.ancestry,  // root-to-direct-parent; ancestry.last is direct parent
  id: event.id,
  owner: event.owner,
  leafExpiration: const Duration(days: 7),
);  // returns null if any ancestor expired
// ⚠️ THROWS ArgumentError if any CAncestor.owner in ancestry is null.
//    CAncestor.owner IS null on CSubItemDeleted events — never call getDescendant from a delete handler.
//    Cache the ancestry from the preceding CSubItemUpdated if you need it on delete.
```

For 3+ levels use `watchWithTree` with `SubSpec<U>`. Each `TreeNode<T>` has a
`parent` (`CItem<T>`) and `branches` (`Map<String, List<TreeNode<dynamic>>>`).
When handling sub-collection events, `ancestry` is always **root-first**:
`ancestry[0]` is the root ancestor, `ancestry.last` is the direct parent.
Read [references/03-query-api.md](references/03-query-api.md) when working with
deep hierarchies.

---

## 8. Events & Streams

```dart
collection.updates           // Stream<CItemUpdated>
collection.deletes           // Stream<CItemDeleted>    (item.wasExpired flag)
collection.readReceipts      // Stream<CReadReceipt>    (r.from, r.readAt)
collection.subUpdates        // Stream<CSubItemUpdated> (ancestry chain; ancestry.last = direct parent)
collection.subDeletes        // Stream<CSubItemDeleted> (ancestry[n].owner is null — cache from subUpdates)
collection.availableEvents   // Stream<CItemAvailable>  (e.availableAt fired)
collection.expiringSoonEvents(leadTime: const Duration(hours: 1))
```

**Flutter subscribe/dispose:**

```dart
late StreamSubscription<CItemUpdated> _sub;
@override void initState() { super.initState(); _sub = collection.updates.listen((_) => setState(() {})); }
@override void dispose() { _sub.cancel(); super.dispose(); }
```

Read [references/04-events-api.md](references/04-events-api.md) for all event
class fields, the EventSource decision guide, and the ancestry ordering
(root-first: `ancestry[0]` = root, `ancestry.last` = direct parent of the leaf).

---

## 9. Read Receipts

```dart
await item.markReadByMe();                   // mark as read (idempotent)
final readers = await item.readBy;           // Future<Set<Atsign>>
item.readBySnapshot;                         // sync snapshot
final didRead = await item.wasMarkedReadByMe();
collection.readReceipts.listen((r) => print('${r.from} read ${r.id} at ${r.readAt}'));
```

---

## 10. Flutter Auth (`at_client_flutter`)

Four flows, four dialogs. Every dialog hands back the **`AtClient` it opened**
(`null` means the user cancelled or the dialog failed) and the app owns it: it
uses it, makes it current if its screens read the manager, and `stop()`s it
when done. Nothing here needs `at_auth`.

**Flow 2 (existing `.atKeys` file) — most common for returning developers:**

```dart
final atKeysIo = await AtKeysFileDialog.show(context);          // FileAtKeysIo?
if (atKeysIo == null) return;
final atSign = atKeysIo.getAtsign();                            // extensions.dart
final client = await PkamDialog.show(context,
  atSign: atSign,
  keys: atKeysIo,
  preference: AtClientPreference()..namespace = 'my_namespace',
  storage: await _storage(atSign),
  backupKeys: [KeychainAtKeysIo()],   // copies the keys into the keychain for next time
);
if (client == null) return;
_adopt(client);
```

**Flow 3 (device keychain — returning user on same device):**

```dart
final atSigns   = await KeychainStorage().getAllAtsigns();
final selection = await AtSignSelectionDialog.show(context, existingAtSigns: atSigns);
if (selection == null) return;                                 // AtsignSelection: atSign, rootDomain
final client = await PkamDialog.show(context,
  atSign: selection.atSign,
  rootDomain: selection.rootDomain,
  keys: KeychainAtKeysIo(),
  preference: AtClientPreference()..namespace = 'my_namespace',
  storage: await _storage(selection.atSign),
);
if (client == null) return;
_adopt(client);
```

**Storage and adoption (all flows):**

```dart
// Where this app keeps the atSign's local store. closedByClient: the client
// closes it when it stops, so there is nothing to tear down.
Future<HiveAtClientStorage> _storage(String atSign) async {
  final dir = await getApplicationSupportDirectory();
  return HiveAtClientStorage(atSign: atSign, storagePath: dir.path, closedByClient: true);
}

// An app whose screens read AtClientManager.getInstance().atClient makes the
// client current; an app that passes the client around needs no manager.
void _adopt(AtClient client) => AtClientManager.getInstance().use(client);

// Logout: stop the client. Opening the same atSign again while it is live is
// refused, so every sign-in stops the previous client first.
await client.stop();
```

Read [references/05-flutter-auth.md](references/05-flutter-auth.md) for all 4
flows (including Flow 1: CRAM new-atsign and Flow 4: APKAM enrollment) with
complete code, and what a `PkamDialog` that comes back **offline** means.

> **Sync setup:** set `AtClientPreference.syncRegex = '<your namespace>'` —
> without it, sync covers the atsign's whole keystore and can wedge, so shares
> and updates never propagate. Reads are local; writes sync in the background.
> See [references/11-sync.md](references/11-sync.md).

---

## 11. AtClient Lifecycle: Open, Own, Stop

`at_client` owns the atSign lifecycle. An app holds an `AtKeysIo` (a `.atKeys`
file, the keychain, or memory) and asks the atSign for a client; every verb
hands back an `AtClient` the app **owns and stops**. The Flutter dialogs (§10)
and `CLIBase` (§16) are these verbs behind UI and argument parsing.

```dart
final client = await Atsign('@alice').open(
  keys: FileAtKeysIo(filePath: (_) => '/keys/@alice_key.atKeys'),
  preference: AtClientPreference()..namespace = 'my_namespace'..syncRegex = 'my_namespace',
  storage: HiveAtClientStorage(atSign: '@alice', storagePath: dir, closedByClient: true),
);
// Also: Atsign(a).activate(cramSecret:, keys:, preference:)  — onboard a new atSign
//       Atsign(a).enroll(otp:, app:, device:, namespaces:, keys:, preference:) → PendingEnrollment
//       Atsign(a).resumeEnrollment(app:, device:, keys:, preference:)         — after a restart
```

**Connection state — the client comes back whatever the network did:**

```dart
client.connection.current;        // AtConnectionState: online | offline | refused, plus cause
client.connection.changes.listen((s) => ...);       // every change, in order
await client.connection.awaitOnline(budget: const Duration(seconds: 30));
await client.connection.attempt();                  // try again now
```

- **offline** (`unreachable`, `noAtServer`): the client serves its local store;
  writes queue and sync when the atServer is reached.
- **refused** (`revoked`, `unauthenticated`, `invalidEnrollment`,
  `enrollmentNotApproved`): the atServer rejected the keys — the app decides.
  The one refusal that **throws** (`AtOpenRefusedException`) is the first open
  of these keys on a device: nothing is held locally, so there is nothing to
  serve. Keys holding only a pending enrollment throw
  `AtEnrollmentPendingException` — call `resumeEnrollment`.
- **`stopped`**: what `current` reads after `stop()`; `changes` is done.

**Services — both belong to the client, start with it and stop with it:**

- `client.syncService` runs on its own: on every stats notification from the
  atServer and every `syncIntervalMins`. `sync()` expedites a round,
  `isInSync()` asks the atServer fresh, `addProgressListener` observes. The
  `AtClientManager` getters for these services are deprecated.
- `client.notificationService.subscribe(regex:, shouldDecrypt:)` — the monitor
  starts on the first `subscribe` (or 30 s after creation) when
  `monitorAutoStart` is true. **`subscribe()` returns before the monitor is
  connected**: wait for `listening` (or `currentListenerStateStream`) before a
  notify you expect to receive, or the send reports `delivered` and nothing
  arrives.

**Own it, then stop it:**

- **One live client per (atSign, enrollment) and per storage location** in a
  process: opening again while one is live throws `StateError` — `stop()` the
  previous client first. Another enrollment of the same atSign opens beside it
  on its own store.
- `await client.stop()` stops sync, notifications and the connection, and
  closes storage built with `closedByClient: true`. It does **not** drain: a
  sync round in flight is abandoned and its work stays queued for the next
  client on that store. Wait for `isInSync()` first if the writes must land.
- A stopped client is not restarted — open the atSign again.
- `AtClientManager.getInstance().use(client)` makes a client current for code
  that reads `AtClientManager.getInstance().atClient`; `use` does **not** stop
  the previous current client. `setCurrentAtSign` / `fromAuthSession` are
  deprecated. `reset()` is a test hook, not a logout.

Read [references/15-client-lifecycle.md](references/15-client-lifecycle.md)
for the full verb list, the storage object, every `AtConnectionCause`, the
service lifecycles and the shutdown checklist.

---

## 12. Domain-Object Checklist

```dart
class Todo {
  String title; bool done; DateTime due;
  Todo(this.title, {this.done = false, required this.due});

  Map<String, dynamic> toJson() => {'title': title, 'done': done, 'due': due.toIso8601String()};
  factory Todo.fromJson(Map<String, dynamic> j) => Todo(j['title'] as String,
      done: j['done'] as bool, due: DateTime.parse(j['due'] as String));
}

// Call once at startup — before any atClient.collection() call
AtCollection.registerFactory<Todo>(Todo.fromJson, typeTag: 'Todo');
```

- `typeTag` must be a string literal — never `T.toString()` (breaks in release
builds)
- Primitives (`String`, `Map<String,dynamic>`, `List`, `Uint8List`) need no
registration
- Use `typeTag: 'binary'` for `Uint8List`

<!-- pyml disable-next-line md013-->
Read [references/08-domain-object-patterns.md](references/08-domain-object-patterns.md)
for polymorphic types, schema evolution, and the full re-registration rules.

---

## 13. Architecture Decision: AtCollection vs Notifications+SQLite

|                 | `AtCollection<T>`               | Notifications + SQLite            |
| --------------- | ------------------------------- | --------------------------------- |
| **Data shape**  | Typed records, discrete items   | High-frequency events / telemetry |
| **Persistence** | Synced via atServer             | Local-only, from notifications    |
| **Volume**      | Low-medium (hundreds-thousands) | High (per-second metrics, logs)   |
| **Example**     | Todos, notes, contacts          | Live dashboard, analytics         |

These patterns are complementary and can coexist in the same app.

**Sending / receiving notifications** (the fire-and-forget side):

```dart
// Send — returns the notification id; body is usually JSON
await atClient.notificationService.send(
  to: '@bob'.toAtsign(),
  namespace: 'sample.my_app',
  body: jsonEncode(payload),
  expiration: const Duration(minutes: 5),   // short TTL for telemetry
);

// Receive — subscribe to a namespace regex; decrypt encrypted payloads
atClient.notificationService
    .subscribe(regex: r'sample\..*\.my_app', shouldDecrypt: true)
    .listen((n) => handle(n.value));
```

Read [references/10-architecture-guide.md](references/10-architecture-guide.md)
for the full decision guide and the dockerstats Notifications+SQLite example.
See `packages/at_client/example/bin/notifications.dart` for a minimal
send/subscribe walkthrough.

---

## 14. Testing Without a Live atServer

```dart
import 'package:at_client/at_client.dart'; // test hooks are re-exported here

final ctrl = StreamController<AtNotification>.broadcast();
final coll = collectionWithInjectedNotifications<Todo>(
  fakeAtClient, 'todos.my_app', const Duration(days: 7),
  notifications: ctrl.stream, fromJson: Todo.fromJson, typeTag: 'Todo',
);

clearFactoriesForTest();  // call in setUp() to prevent cross-test pollution
```

Available helpers: `collectionWithInjectedNotifications`,
`collectionWithInjectedDataEvents`,
`collectionWithInjectedBoth`, `handleNotificationForTest`,
`handleDataEventForTest`,`clearFactoriesForTest`,
`clearMissingFactoryWarningsForTest`

Read [references/09-testing-patterns.md](references/09-testing-patterns.md) for
the complete test template including the correct `AtNotification` constructor
and MockAtClient stubs.

---

## 15. RPC — Request/Response Between Atsigns

For "call another atsign and get an answer back" (actions and queries — not
data), use `AtRpc`/`AtRpcClient` from `at_client`:

```dart
// Requester — call() sends, awaits the success response, returns its payload
final client = AtRpcClient(serverAtsign: '@server', atClient: atClient,
    baseNameSpace: 'my_app', domainNameSpace: 'route_planning');
final answer = await client.call({'from': 'A', 'to': 'B'});

// Responder — handler's return value is sent back; thrown errors become nacks
final rpc = AtRpc.server(atClient: atClient, baseNameSpace: 'my_app',
    domainNameSpace: 'route_planning', requestHandler: handleRequest,
    allowList: {'@requester'.toAtsign()}, allowAll: false,
    enableRequestMutex: false);
rpc.start();
```

Requests from atsigns not on `allowList` are discarded before your handler
runs. Persist durable results via `AtCollection<T>`, not RPC payloads.

Read [references/13-rpc.md](references/13-rpc.md) when implementing
request/response between atsigns — response types, retries, expiry, and the
multi-instance mutex.

---

## 16. Headless Agents & Multi-Instance Coordination

Authenticate a UI-less process (agent, daemon, CLI) in one line with
`CLIBase` from `at_cli_commons`:

```dart
final AtClient atClient =
    (await CLIBase.fromCommandLineArgs(args, namespace: 'my_app')).atClient;
```

- **Every process needs its own storage** (`HiveAtClientStorage(atSign:,
  storagePath:)`, or the deprecated `hiveStoragePath`) — one store is held by
  one live client and a second open on it is refused. Use
  `Directory.systemTemp.createTempSync('agent_')` per instance, and
  `client.stop()` when the process is done.
- **Multiple instances of one agent** coordinate via an immutable-mutex race
  (`Metadata()..immutable = true` + remote put; the **losing `put()` throws** —
  there is no typed exception, inspect the message for `'immutable'`), or run
  stateless with `Atsign(a).open(..., serviceFactory:
  ServiceFactoryWithNoOpSyncService())` (from `at_cli_commons`, NOT
  `at_client`) + remote operations.

Read [references/14-multi-agent.md](references/14-multi-agent.md) when
building headless agents, daemons, or anything that runs more than one
instance.

---

## 17. Remote vs Local atServer Operations

By default (`AtClientPreference.remoteLocalPref = RemoteLocalPref.localOnly`)
`put`/`get`/`delete` hit the **local** secondary and sync in the background —
the right default for app data. (Reading another atsign's non-`cached:` key is
always a remote lookup.) For coordination keys and read-your-write
consistency, target the cloud secondary per operation:

```dart
await atClient.put(key, value,
    putRequestOptions: PutRequestOptions()..useRemoteAtServer = true);
await atClient.get(key,
    getRequestOptions: GetRequestOptions()..useRemoteAtServer = true);
await atClient.get(key,   // force-refresh another atsign's key past caches
    getRequestOptions: GetRequestOptions()..bypassCache = true);
```

`AtCollection<T>` takes no per-operation options — collection ops follow the
client-wide `remoteLocalPref` (set `RemoteLocalPref.remoteOnly` to route the
whole client, collections included, to the remote atServer). Remote ops cost a
round-trip and fail offline; scope per-operation overrides to infrastructure
keys (give those a distinct key-name prefix within your app's namespace, e.g.
`lock.`).

Read [references/12-remote-atserver.md](references/12-remote-atserver.md) when
an operation must see or produce server-side truth immediately.

---

## 18. Deprecated — Do Not Use

| Avoid                                                                                                                                                        | Use instead                                      |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------ |
| `AtCollectionModel` / `AtJsonCollectionModel`                                                                                                                | `AtCollection<T>` via `atClient.collection(...)` |
| `at_common_flutter`                                                                                                                                          | `at_client_flutter`                              |
| `at_backupkey_flutter`                                                                                                                                       | Copy `at_client_flutter` backup-key snippet      |
| `at_invitation_flutter`                                                                                                                                      | Copy `at_client_flutter` invitation snippet      |
| `at_sync_ui_flutter`, `at_theme_flutter`                                                                                                                     | Deprecated — do not use                          |
| `at_chat_flutter`, `at_contacts_flutter`, `at_contacts_group_flutter`, `at_events_flutter`, `at_follows_flutter`, `at_location_flutter`, `at_notify_flutter` | In migration — copy example code instead         |
| `AtClientManager.setCurrentAtSign(...)`, `fromAuthSession(...)`                                                                                              | `Atsign(a).open(...)` then `AtClientManager.getInstance().use(client)` |
| `AtAuthRequest`, `AuthResponse`, `AuthService`, `FlutterEnrollmentService` (at_client_flutter 1.x); importing `at_auth` in an app                              | The dialogs hand back the `AtClient` (§10); the `Atsign` verbs (§11) |
| `AtClientPreference.hiveStoragePath`, `.commitLogPath`                                                                                                       | `HiveAtClientStorage(atSign:, storagePath:)` passed as `storage` |

Read [references/01-deprecation-guide.md](references/01-deprecation-guide.md)
for the full migration table from old `AtCollectionModel` patterns to
`AtCollection<T>`.

---

## 19. Canonical Examples & Future Scope

- `packages/at_client/example/bin/collections_domain_objects.dart`
- `packages/at_client/example/bin/collections_subcollections.dart`
- `packages/at_client/example/bin/collections_todos.dart` — terminal-UI (TUI)
  todos app using `AtCollection` + `query().watch()` (Dart/CLI reference)
- `packages/at_client/example/bin/notifications.dart` — minimal
  `NotificationService` send/subscribe
- `packages/at_client_flutter/examples/todos/` — canonical Flutter reference app
- `packages/at_client_flutter/examples/dockerstats/` — notifications + SQLite

**If asked about migrating from `atClient.put()` / `atClient.get()` to
`AtCollection<T>`:** Both APIs share the same underlying atServer keystore but
use different key-naming conventions — `AtCollection` data will not appear in
raw `get()` queries and vice versa. Migration is non-trivial: read existing
data with the raw API and re-write it through `AtCollection<T>`. Always test
in a staging environment before touching production data. A formal migration
guide is **coming in skill v2.0**.
