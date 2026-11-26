---
name: at-client-skills-core
description: >
  Use this skill whenever a Dart or Flutter app on the Atsign Platform reads,
  writes, shares or syncs data, or is upgraded to at_client 4.0. Covers
  AtCollection<T> — CItem, Query, sub-collections, events, read receipts — and
  when notifications+SQLite fits better; the post-quantum posture; opening,
  stopping and switching an AtClient and its connection state; a keyfile
  that stopped working after a restore; sending,
  receiving and confirming delivery of notifications; waiting for sync to
  settle; RPC between atsigns; remote-versus-local atServer operations;
  publishing public data; which exceptions to catch; NoPorts tunnels;
  unit-testing without a live atServer; which pub.dev packages to add; and
  what to do when the SDK lacks something or has a bug.
  Warns against AtCollectionModel and the other APIs at_client 4.0 removed.
  Use alongside at-client-skills-cli (CLI, daemon, server, headless agents) or
  at-client-skills-flutter (Flutter apps, onboarding dialogs).
license: BSD-3-Clause
compatibility: Claude Code and any agentskills.io-compatible agent.
user-invocable: true
metadata:
  version: "2.0.0"
  last_modified: "Mon, 09 Nov 2026 00:00:00 GMT"
---

# Atsign Platform: core

> **Audience:** developers adding the Atsign Dart SDK to their own Dart or
> Flutter app from pub.dev — not developers editing the SDK repo itself.

This skill covers what every app does, whatever it runs on. Use it with the
skill for the app's platform:

- **at-client-skills-cli** — Dart CLI, daemon, server, IoT, headless agents:
  `CLIBase`, `CliKeys`, `at_activate`, one store per process.
- **at-client-skills-flutter** — Flutter apps: the onboarding dialogs,
  `AtsignFlows`, the keychain, widget lifecycles.

If a platform skill the app needs is not among your skills, ask the developer
to install it: `dart run skills get --skill <name>`.

---

## 1. Rules every app follows

**Always use `AtCollection<T>`.** Never use `AtCollectionModel`.

```dart
// ✅ CORRECT — modern API, through the app's one platform package
import 'package:at_client_flutter/at_client_flutter.dart'; // CLI: at_client_cli
final todos = await atClient.collection<Todo>(
  'todos.my_app',
  const Duration(days: 7),
  fromJson: Todo.fromJson,
  typeTag: 'Todo',
);

// ❌ WRONG — removed in at_client 4.0; does not compile
class MyModel extends AtCollectionModel { ... }
```

at_client 4.0 removed the entire `AtCollectionModel` hierarchy
(`AtCollectionModel`, `AtJsonCollectionModel`, their factories and
operations), which at_client 3.x had deprecated in favour of
`AtClient.collection`.

> **If asked how to use `AtCollectionModel`:** do NOT show any
> `AtCollectionModel` code, even in a "before/removed" comparison. Show ONLY
> the `AtCollection<T>` pattern above, and state that at_client 4.0 removed
> `AtCollectionModel`, so code using it no longer compiles.

**A new app runs post-quantum.** Build every preference with
`AtClientPreference(posture: PqPosture.pqActive)` and set its `namespace`.
The SDK's default is `legacy`, so a preference that names no posture encrypts
the old way, and nothing tells you. See §9.

**One platform package.** An app depends on `at_client_cli` or
`at_client_flutter` and imports only from that package (§2).

**Upgrading an app from at_client 3.x?** When the code, its `pubspec.yaml`
or the errors point to at_client 3.x, follow the upgrade guide — it is
organised by the error `dart analyze` / `flutter analyze` reports, and is kept
current with the SDK: [Upgrading to at_client 4.0][upgrade-guide]. Upgrade to
the latest packages; never pin back to at_client 3.x to make errors go away.
What at_client 4.0 removed is in §16.

---

## 2. Package Map

An app depends on **one platform package** and imports only from it: its
barrel, and any helper library its platform skill names. The platform package
re-exports at_client's API and supplies a working default for
everything that differs by platform (storage, transport, keys, logging).
Install with `dart pub add` — it resolves the latest compatible version:

| App                              | Add and import                                                  |
| -------------------------------- | --------------------------------------------------------------- |
| Dart CLI / daemon / server / IoT | `at_client_cli` — `package:at_client_cli/at_client_cli.dart`         |
| Flutter app                      | `at_client_flutter` — `package:at_client_flutter/at_client_flutter.dart` |

A project with both Flutter apps and headless agents is two packages: the apps
on `at_client_flutter`, the agents in a pure-Dart package on `at_client_cli`.
Inside a Flutter package, `dart compile exe` refuses to build an agent, even
one that imports no Flutter code: the package's dependencies have build hooks.

Nothing else from the SDK, beyond any feature package the app adds
(`at_contact`, `at_policy`, `at_telemetry`, `noports_core`; these are released
separately, so check one resolves before building on it — see
[references/06-package-map.md](references/06-package-map.md)). An app never
adds or imports the packages underneath — `at_client`, `at_auth`,
`at_commons`, `at_chops`, `at_lookup`, `at_utils` — except as a marked
workaround for an SDK gap (§18). `at_client` itself is the
platform-neutral core, for building a platform package.

**Never add:** `at_common_flutter`, `at_onboarding_flutter` (discontinued — use
the `at_client_flutter` auth dialogs), `at_backupkey_flutter`,
`at_invitation_flutter`, `at_sync_ui_flutter`, `at_theme_flutter`, and the
deprecated `at_cli_commons` and `at_onboarding_cli`, whose last majors only
re-export `at_client_cli`.

> **Never hardcode version constraints** for `at_client_cli` /
> `at_client_flutter` in `pubspec.yaml` or generated templates — run `dart pub
> add` and let pub choose. Pinned constraints go stale between SDK releases
> and cause resolution conflicts; stability comes from a fixed `typeTag`
> string literal (§3), not a fixed SDK version.

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
  eventSource: EventSource.both,     // default: data + notifs; may fire twice
);
```

- **Cached per `(namespace, eventSource)` pair** — same namespace + different
  eventSource = separate instances
- **`namespace` must contain `.`** (e.g. `'todos.my_app'`) — throws
  `ArgumentError` otherwise
- **At `pqActive`, `namespace` ends with `.` and the client's
  `preference.namespace`** (or a namespace its enrollment is granted);
  elsewhere the first write throws `NamespaceKeyUnavailableException`
- **`typeTag` is mandatory when `fromJson` is supplied** — always a string
  literal, never derived from `T.toString()` (minifier renames types in
  release builds)

Read [references/02-atcollection-api.md](references/02-atcollection-api.md) for
the complete API surface, and
[references/04-events-api.md](references/04-events-api.md) for choosing an
`EventSource`.

---

## 4. CRUD and Reading

```dart
// create — strict: throws StateError if id already exists
final item = await todos.create(obj: Todo('buy milk'), sharedWith: {'@bob'.toAtsign()});
await todos.upsert(id: 'my-known-id', obj: Todo('buy milk'));   // idempotent
item.obj.done = true;
await todos.update(item);                                       // mutate, then persist
await todos.updateSharedWith(item, {'@alice'.toAtsign()});      // change recipients
await todos.delete(item);                    // throws StateError if has sub-items
await todos.delete(item, cascade: true);     // removes self-owned descendants first

final all = await todos.getItems();
final mine = await todos.getItems(owner: atClient.atSign);
final one  = await todos.getOrNull('abc', atClient.atSign);  // null if not found
final one2 = await todos.get('abc', atClient.atSign);         // throws if not found
todos.getItemsAsStream()                     // decode errors arrive as stream errors
    .handleError((e) => _log.warning('decode error: $e'))
    .listen(handle);
```

> **Ownership model:** `AtCollection` is **owner-writes-only** — an atsign can
> only mutate items it owns. `update` / `updateSharedWith` / `delete` throw
> `ArgumentError` on an item whose `owner` isn't you. Collaboration is
> **additive**: sharing grants the recipient a *readable* copy, not write
> access. For a peer to contribute, they create their own item and share it
> back — you never edit theirs in place.

At `pqActive`, a share needs each recipient to have published a namespace key;
otherwise the write throws `CollectionOpException` naming them. See
[references/18-post-quantum.md](references/18-post-quantum.md).

---

## 5. Query Builder

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
final first = await q.firstOrNull();
```

Prefer typed predicates (`wherePath` with `PathField`) over `.where()` when
you want future push-down optimisation on indexed fields. Create a `watch()`
stream once and hold it; never recreate it per rebuild or per call.

Read [references/03-query-api.md](references/03-query-api.md) for all terminals
(`distinct`, `groupBy`, `watchWithSub`, `watchWithTree`) and the full
`PathField` operator list.

---

## 6. Sub-collections

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

For 3+ levels use `watchWithTree` with `SubSpec<U>`. `ancestry` is always
**root-first**: `ancestry[0]` is the root ancestor, `ancestry.last` is the
direct parent. Read [references/03-query-api.md](references/03-query-api.md)
when working with deep hierarchies.

---

## 7. Events and Read Receipts

```dart
collection.updates           // Stream<CItemUpdated>
collection.deletes           // Stream<CItemDeleted>    (item.wasExpired flag)
collection.readReceipts      // Stream<CReadReceipt>    (r.from, r.readAt)
collection.subUpdates        // Stream<CSubItemUpdated> (ancestry chain; ancestry.last = direct parent)
collection.subDeletes        // Stream<CSubItemDeleted> (ancestry[n].owner is null — cache from subUpdates)
collection.availableEvents   // Stream<CItemAvailable>  (e.availableAt fired)
collection.expiringSoonEvents(leadTime: const Duration(hours: 1))

await item.markReadByMe();                   // mark as read (idempotent)
final readers = await item.readBy;           // Future<Set<Atsign>>
final didRead = await item.wasMarkedReadByMe();
```

Cancel every subscription when its owner goes away. Read
[references/04-events-api.md](references/04-events-api.md) for all event class
fields and the EventSource decision guide.

---

## 8. Domain Objects

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
  registration; use `typeTag: 'binary'` for `Uint8List`

<!-- pyml disable-next-line md013-->
Read [references/08-domain-object-patterns.md](references/08-domain-object-patterns.md)
for polymorphic types, schema evolution, and the full re-registration rules.

---

## 9. AtClient Lifecycle: Open, Own, Stop

`at_client` owns the atsign lifecycle. An app holds an `AtKeysIo` (a `.atKeys`
file or the keychain, never one that dies with the process) and asks the
atsign for a client; every verb hands back an `AtClient` the app **owns and
stops**. The platform skills show the verbs as each platform wraps them:
`CLIBase` and `CliKeys` (at-client-skills-cli), the dialogs and `AtsignFlows`
(at-client-skills-flutter).

```dart
final preference = AtClientPreference(posture: PqPosture.pqActive)
  ..namespace = 'my_app'
  ..syncRegex = 'my_app';
final client = await Atsign('@alice').open(
  keys: FileAtKeysIo(filePath: (_) => '/keys/@alice_key.atKeys'),
  preference: preference,
  storage: HiveAtClientStorage(atSign: '@alice', storagePath: dir.path, closedByClient: true),
  lookUps: secureSocketLookUps(),   // how every connection is built
  secondaryAddressFinder: CacheableSecondaryAddressFinder(
      preference.rootDomain, preference.rootPort),   // where the atServer is
);
// Also: Atsign(a).activate(...) — onboard a new atsign
//       Atsign(a).enroll(...) → PendingEnrollment; pending.client(preference, storage:)
//       Atsign(a).resumeEnrollment(...) — after a restart
```

Every verb that builds a client **requires** the platform bundle: `keys:`,
`storage:`, `lookUps:` (an `AtLookUpFactory` that builds every connection the
client opens) and `secondaryAddressFinder:`. The platform packages supply it.

**Posture** is fixed when the preference is built: `legacy` (the default),
`pqReady` (reads post-quantum, writes legacy) or `pqActive` (writes
post-quantum). A new app goes straight to `pqActive`. The default comes back
wherever a preference is left out: `CLIBase` with no `preference:`,
`at_activate` with no `--posture`, a Flutter dialog or `AtsignFlows` call
handed a preference with no posture. The platform skills say more. An app
already deployed on
legacy moves in two steps, through `pqReady`. Read
[references/18-post-quantum.md](references/18-post-quantum.md) for the floor,
the keyfile, writes right after open, offline writes, mixed fleets and
approvers.

**The keyfile changes after first use.** Start-up writes each namespace key's
private into the atsign's keys, so never put an earlier copy of a keyfile back,
and back one up only after the app has started once.

**Connection state — the client comes back whatever the network did:**

```dart
client.connection.current;        // AtConnectionState: online | offline | refused, plus cause
client.connection.changes.listen((s) => ...);       // every change, in order
await client.connection.awaitOnline(budget: const Duration(seconds: 30));
```

- **offline**: the client serves its local store; writes queue and sync when
  the atServer is reached.
- **refused**: the atServer rejected the keys — the app decides. The first
  open of these keys on a device throws instead (`AtOpenRefusedException`);
  keys holding only a pending enrollment throw `AtEnrollmentPendingException`
  — call `resumeEnrollment`.
- **stopped**: what `current` reads after `stop()`.

**Services belong to the client, start with it and stop with it.**
`client.syncService` runs on its own; `client.notificationService` starts its
monitor on the first `subscribe`. **`subscribe()` returns before the monitor is
connected**: wait for `listening` before a notify you expect to receive.

> **Sync setup** (every app): set `AtClientPreference.syncRegex = '<your
> namespace>'` — without it, sync covers the atsign's whole keystore and can
> wedge, so shares and updates never propagate. To hold an operation until
> sync has settled, `await client.syncService.waitUntilCaughtUp(timeout: ...)`
> — always with a timeout. See [references/11-sync.md](references/11-sync.md).

**Own it, then stop it:**

- **One live client per (atsign, enrollment) and per storage location** in a
  process: opening again while one is live throws `StateError` — `stop()` the
  previous client first.
- `await client.stop()` stops sync, notifications and the connection. It does
  **not** drain: if the writes must land, first
  `await client.syncService.waitUntilCaughtUp(timeout: ...)`.
- Work the stop cuts short fails with `StoppedException` — not an
  `AtException`; catch it by type. A stopped client is not restarted — open
  the atsign again.
- `AtClientManager.getInstance().use(client)` makes a client current for code
  that reads the manager; it does **not** stop the previous one.

Read [references/15-client-lifecycle.md](references/15-client-lifecycle.md)
for the full verb list, the storage object, every `AtConnectionCause`, the
service lifecycles, enrollment approval and the shutdown checklist.

---

## 10. Architecture: AtCollection vs Notifications+SQLite

|                 | `AtCollection<T>`               | Notifications + SQLite            |
| --------------- | ------------------------------- | --------------------------------- |
| **Data shape**  | Typed records, discrete items   | High-frequency events / telemetry |
| **Persistence** | Synced via atServer             | Local-only, from notifications    |
| **Volume**      | Low-medium (hundreds-thousands) | High (per-second metrics, logs)   |
| **Example**     | Todos, notes, contacts          | Live dashboard, analytics         |

```dart
// Send — returns the notification id; body is usually JSON
final id = await atClient.notificationService.send(
  to: '@bob'.toAtsign(),
  idAndNamespace: 'sample.my_app',          // an id, a dot, then the namespace
  body: jsonEncode(payload),
  expiration: const Duration(minutes: 5),
);

// Receive, on @bob's client — only from the senders it accepts
atClient.notificationService
    .subscribeFiltered(acceptedSenders: {'@alice'.toAtsign()}, namespace: 'sample.my_app')
    .listen((n) => handle(n.value));
```

- Awaiting `send()` proves only that the notification was accepted, never
  that it arrived. When it must not be lost, poll `getStatus(id)` within the
  notification's `expiration`; one `undelivered` reading is not a failure.
- Receiving is **at-least-once**: write handlers that can run twice on the same
  notification — key the effect off `n.id`.

Read [references/10-architecture-guide.md](references/10-architecture-guide.md)
for the decision guide, and
[references/16-notifications.md](references/16-notifications.md) for delivery
confirmation and filtered receiving.

---

## 11. RPC — Request/Response Between Atsigns

For "call another atsign and get an answer back" (actions and queries — not
data), use `AtRpc` / `AtRpcClient`:

```dart
final client = AtRpcClient(serverAtsign: '@server', atClient: atClient,
    baseNameSpace: 'my_app', domainNameSpace: 'route_planning');
// call() has NO timeout of its own — an unanswered request waits forever
final answer = await client.call({'from': 'A', 'to': 'B'})
    .timeout(const Duration(seconds: 20));

final rpc = AtRpc.server(atClient: atClient, baseNameSpace: 'my_app',
    domainNameSpace: 'route_planning', requestHandler: handleRequest,
    allowList: {'@requester'.toAtsign()}, allowAll: false,
    enableRequestMutex: false);
rpc.start();
```

Requests from atsigns not on `allowList` are discarded before your handler
runs. Both helpers are one-way; for a peer that both answers and asks,
construct `AtRpc` with your own `AtRpcCallbacks`. Read
[references/13-rpc.md](references/13-rpc.md) for response types, retries,
expiry and the multi-instance mutex.

---

## 12. Remote vs Local atServer Operations

By default `put`/`get`/`delete` hit the **local** store and sync in the
background — the right default for app data. For coordination keys and
read-your-write consistency, target the atServer per operation:

```dart
await atClient.put(key, value,
    putRequestOptions: PutRequestOptions()..useRemoteAtServer = true);
await atClient.get(key,   // force-refresh another atsign's key past caches
    getRequestOptions: GetRequestOptions()..bypassCache = true);
```

`AtCollection<T>` takes no per-operation options; it follows the client-wide
`remoteLocalPref`. **Public data** is the other reason to leave
`AtCollection`: build public keys with `AtKey.public(key, namespace:,
sharedBy:).build()` and raw `put`. Public values are **signed, not
encrypted** — never put anything private in one.

Read [references/12-remote-atserver.md](references/12-remote-atserver.md) when
an operation must see server-side truth immediately, or to publish data.

---

## 13. Error Handling

- **`ArgumentError` / `StateError`** — your bug. Fix the call; do not catch.
- **`AtException` and its subtypes** — everything the protocol layer throws.
  This is the one catch-all worth writing.
- **`CollectionOpException`, `StoppedException`, `TimeoutException`** —
  outside the `AtException` tree. `CollectionOpException` means a write was
  *partially* applied and carries a per-key breakdown. `StoppedException`
  means the client was stopped — end the work quietly.

```dart
try {
  await atClient.get(key);
} on AtException catch (e) {
  _log.warning(e.getTraceMessage());   // NOT '$e' — that shows only the innermost message
}
```

Branch on `e.exceptionScenario` rather than message text; it is nullable. Read
[references/17-error-handling.md](references/17-error-handling.md) for what
each operation throws.

---

## 14. Testing Without a Live atServer

```dart
final ctrl = StreamController<AtNotification>.broadcast();
final coll = collectionWithInjectedNotifications<Todo>(
  fakeAtClient, 'todos.my_app', const Duration(days: 7),
  notifications: ctrl.stream, fromJson: Todo.fromJson, typeTag: 'Todo',
);

clearFactoriesForTest();  // call in setUp() to prevent cross-test pollution
```

The test hooks come through the platform package's barrel. Also available:
`collectionWithInjectedDataEvents`, `collectionWithInjectedBoth`,
`handleNotificationForTest`, `handleDataEventForTest`,
`clearMissingFactoryWarningsForTest`. Read
[references/09-testing-patterns.md](references/09-testing-patterns.md) for the
complete test template and the `AtNotification` constructor.

---

## 15. Common Pitfalls

Read [references/07-common-pitfalls.md](references/07-common-pitfalls.md)
before debugging data that does not appear, does not sync, or decodes wrong.

---

## 16. Removed or Deprecated — Do Not Use

Removed in at_client 4.0 — code using these no longer compiles. To move a
whole app off at_client 3.x, follow the [upgrade guide][upgrade-guide].

| Avoid                                                              | Use instead                                                 |
| ------------------------------------------------------------------ | ----------------------------------------------------------- |
| `AtCollectionModel` / `AtJsonCollectionModel`                      | `AtCollection<T>` via `atClient.collection(...)`            |
| `AtClientManager.setCurrentAtSign(...)`, `fromAuthSession(...)`    | `Atsign(a).open(...)` (§9)                                  |
| `atClient.notify(...)`, `notifyChange(...)`, `notifyAll(...)`      | `notificationService.notify(...)`, once per recipient       |
| `atClient.startMonitor(...)`                                       | `notificationService.subscribe(...)`                        |
| `AtClientManager.getInstance().syncService`, `.notificationService` | `client.syncService`, `client.notificationService`         |
| `notificationService.send(namespace: ...)`                         | `send(idAndNamespace: ...)`                                 |
| `uploadFile`, `downloadFile`, `shareFiles`, `atClient.stream(...)` | `put` or `notify` the value; file transfer belongs in the app |
| `AtClient.atChops`; the `atChops:` and `isDedicated:` parameters   | Delete them                                                 |
| Importing `at_auth`, `at_onboarding_cli`, `at_cli_commons` in an app | The platform package                                      |

Read [references/01-deprecation-guide.md](references/01-deprecation-guide.md)
for every removed API and its replacement, and
[references/06-package-map.md](references/06-package-map.md) for the
deprecated packages and the packages in migration.

---

## 17. Canonical Examples

- [collections_todos.dart][ex-todos] — terminal todos app using `AtCollection`
  and `query().watch()`, at `PqPosture.pqActive`
- [collections_domain_objects.dart][ex-domain],
  [collections_subcollections.dart][ex-sub]
- [notifications.dart][ex-notif] — minimal `NotificationService`
  send/subscribe
- [Upgrading to at_client 4.0][upgrade-guide] — moving an app from at_client
  3.x, by the error `dart analyze` or `flutter analyze` reports

**If asked about migrating from `atClient.put()` / `atClient.get()` to
`AtCollection<T>`:** both share the atServer keystore but use different
key-naming conventions, so `AtCollection` data will not appear in raw `get()`
queries and vice versa. Read existing data with the raw API and re-write it
through `AtCollection<T>`; test in a staging environment first.

---

## 18. When the SDK Falls Short

When the app needs something the SDK does not provide, or the SDK does not do
what its docs say, read [references/19-sdk-gaps.md](references/19-sdk-gaps.md).
In order: confirm there is no supported way; search the issues, open and
closed, and check whether a fix is published; apply the smallest workaround;
draft the issue and file it only if the developer agrees; and tell the
developer it is a workaround.

[upgrade-guide]: https://github.com/atsign-foundation/at_client_sdk/blob/trunk/docs/upgrade-to-4.md
[ex-todos]: https://github.com/atsign-foundation/at_client_sdk/blob/trunk/packages/at_client/example/bin/collections_todos.dart
[ex-domain]: https://github.com/atsign-foundation/at_client_sdk/blob/trunk/packages/at_client/example/bin/collections_domain_objects.dart
[ex-sub]: https://github.com/atsign-foundation/at_client_sdk/blob/trunk/packages/at_client/example/bin/collections_subcollections.dart
[ex-notif]: https://github.com/atsign-foundation/at_client_sdk/blob/trunk/packages/at_client/example/bin/notifications.dart
