<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

[![pub package](https://img.shields.io/pub/v/at_client)](https://pub.dev/packages/at_client) [![pub points](https://img.shields.io/badge/dynamic/json?url=https://pub.dev/api/packages/at_client/score&label=pub%20score&query=grantedPoints)](https://pub.dev/packages/at_client/score) [![build status](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_client_sdk.yaml/badge.svg?branch=trunk)](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_client_sdk.yaml) [![gitHub license](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)

# at_client

The **non-platform-specific** client SDK for building apps on the
[Atsign Protocol](https://atsign.com). An atSign owns a personal server (the
**atServer**); `at_client` talks to that server on its owner's behalf,
transparently handling key management, end-to-end encryption, sync, and
notifications.

`at_client` runs on **both Dart (CLI / server)** and **Flutter
(mobile / desktop / web / IoT)**. It is intentionally platform-neutral:
the actual onboarding dialogs, secure key storage, and CLI scaffolding
live in sibling packages that depend on `at_client`.

## Which package do I actually want?

| If you're building…                        | Start with                                                                                                               |
|--------------------------------------------|--------------------------------------------------------------------------------------------------------------------------|
| A **Dart CLI or server app**               | [`at_cli_commons`](../at_cli_commons) for boilerplate + [`at_onboarding_cli`](../at_onboarding_cli) to provision atSigns |
| A **Flutter app** (mobile/desktop/web/IoT) | [`at_client_flutter`](../at_client_flutter) — ships pre-built onboarding / APKAM / keychain widgets                      |
| **Understanding** the atSign lifecycle     | [`at_auth`](../at_auth) — platform-neutral onboarding / authentication core with a detailed lifecycle writeup            |
| **Shared types** (`AtKey`, `Metadata`, …)  | [`at_commons`](../at_commons)                                                                                            |

## Core surface

The `AtClient` interface ([`lib/src/client/at_client_spec.dart`](lib/src/client/at_client_spec.dart))
is the main entry point once authentication is complete.

- `put(AtKey, value)` / `get(AtKey)` / `delete(AtKey)` — CRUD against
  the keystore
- `notificationService` — fire-and-forget and pub/sub messaging
  ([`lib/src/service/notification_service.dart`](lib/src/service/notification_service.dart))
- `syncService` — background sync between the local store and the
  atServer
- `collection<T>(namespace, defaultExpiration, {fromJson})` — returns a
  `Future<AtCollection<T>>` (see [Collections](#collections) below)

## Examples

The API in `at_client` has evolved substantially over several years.
The authoritative examples of current usage are the worked programs
under these two directories — start there rather than with older
tutorials or blog posts:

- **Dart / CLI examples:** [`example/`](example)
  - [`example/bin/notifications.dart`](example/bin/notifications.dart)
    — messaging via `NotificationService`
  - [`example/bin/rpcs.dart`](example/bin/rpcs.dart)
    — RPC-style method invocation between atSigns
  - [`example/bin/collections_primitives.dart`](example/bin/collections_primitives.dart)
    and the other `collections_*.dart` files — typed shareable records
    via the `AtCollection<T>` API

- **Flutter examples:**
  [`../at_client_flutter/example/`](../at_client_flutter/example)
  (onboarding + auth UI) and
  [`../at_client_flutter/examples/todos/`](../at_client_flutter/examples/todos)
  (a full shared-todos app using `AtCollection`).

## atSign lifecycle (short version)

Before an app can read or write, an atSign must be **registered**,
**onboarded**, and the app must **authenticate**. The detailed writeup
of all three phases — including why APKAM matters for "evil app"
protection — is in [`at_auth`'s README](../at_auth/README.md). The
summary is:

1. **Register** an atSign (free at
   [my.noports.com/no-ports-plans](https://my.noports.com/no-ports-plans)
   or paid/custom at [my.atsign.com](https://my.atsign.com)) to get a
   one-time **CRAM key** delivered to the user's email.
2. **Onboard** the atSign exactly once: CRAM-authenticate, generate the
   master keypairs, and write them to disk (`.atKeys` file for CLI) or
   the device **keychain** (Flutter). These **master AtKeys** are the
   root of trust — **end users must back them up**, losing them means
   losing the atSign.
3. **Authenticate** subsequent apps via **APKAM enrollment**: the app
   requests only the namespaces it needs (e.g. `{'todos': 'rw'}`), the
   master-keys holder approves, and the atServer issues a new scoped
   AtKeys set. Scoped keys can be **revoked** at any time; a
   compromised scoped key can only damage data in its granted
   namespaces.

## Collections

For the common "CRUD on typed, shareable records" use case,
`AtCollection<T>` ([`lib/src/collections/collections.dart`](lib/src/collections/collections.dart))
hides almost all of the AtKey / Metadata / notification-regex ceremony
behind a small set of verbs.

Sketch:

```dart
final todos = await atClient.collection<Todo>(
  'todos.my_app',            // fully-qualified namespace
  const Duration(days: 7),
  fromJson: Todo.fromJson,
  typeTag: 'Todo',           // wire-format identifier — required
);

final item = await todos.create(
  obj: Todo('write readme'),
  sharedWith: {'@bob'.toAtsign()},
);

item.obj.done = true;
await todos.update(item);

await for (final e in todos.updates) {
  print('updated: ${e.id} by ${e.owner}');
}
```

`AtCollection<T>` executes reads on-device by default, against a
local copy that the `at_client` SDK keeps current via real-time
sync with the atServer. Value-level filtering is always on-device
— records are end-to-end encrypted between atSigns, so the server
never sees plaintext to filter on.

A composable `Query<T>` builder covers the common filter / sort /
paginate / aggregate patterns:

```dart
final overdue = todos.query()
    .where((t) => !t.obj.done)
    .where((t) => t.obj.due.isBefore(DateTime.now()))
    .orderBy((t) => t.obj.due)
    .thenBy((t) => t.obj.title)   // tiebreak within same due date
    .limit(20);

final list = await overdue.fetch();   // one-shot List
final live = overdue.watch();         // Stream<List<CItem<Todo>>>

final openCount = await todos.query().where((t) => !t.obj.done).count();
final byOwner   = await todos.query().groupBy<Atsign>((t) => t.owner);
```

Queries are immutable values — build once, store, pass, fetch or
watch. `watch()` does incremental delta maintenance for
non-paginated queries (single-item read on each event, not a full
re-scan). For ad-hoc pipelines outside the builder's vocabulary,
`getItemsAsStream().where(...)` remains supported as an escape
hatch.

For typed, introspectable predicates that a future indexed
executor can push down to a secondary index, declare `PathField`s
on your domain type and use `wherePath`:

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
}

final overdue = await todos.query()
    .wherePath($Todo.done.eq(false))
    .wherePath($Todo.due.lt(DateTime.now()))
    .fetch();
```

Multi-level parent → children → grandchildren joins use
`watchWithTree`:

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
// → Stream<List<TreeNode<Post>>> — branches['comments'] holds
//   per-comment TreeNodes whose own branches['replies'] hold
//   per-reply TreeNodes.
```

Timer-driven events for items written with `availableAt`
(scheduled visibility) and `expiresAt` (TTL):

```dart
// Fires when each scheduled item becomes visible.
todos.availableEvents.listen((e) {
  print('Item ${e.id} just became available');
});

// Fires `leadTime` before each item expires — useful for
// reminder UIs that need to nudge the user before the atServer
// expires the record.
todos.expiringSoonEvents(leadTime: const Duration(minutes: 30))
    .listen((e) {
  print('Item ${e.id} expires at ${e.expiresAt}');
});
```

Read receipts ship built-in — one call on each side, no
app-level bookkeeping:

```dart
// Reader side: idempotent, no-op on self-owned items.
await incomingItem.markReadByMe();

// Owner side: who has read this? Maintained live via events.
final readers = await myItem.readBy;   // Future<Set<Atsign>>
todos.readReceipts.listen((e) => print('${e.from} read ${e.id}'));
```

Sub-collections are `AtCollection<U>` instances scoped to a parent
`CItem` — comments on a blog post, line-items on an invoice — with
opt-in cascade-delete:

```dart
final comments = posts.subCollection<Comment>(
  parent: post,
  subName: 'comments',
  defaultExpiration: const Duration(days: 30),
  fromJson: Comment.fromJson,
  typeTag: 'Comment',
);
await comments.create(obj: Comment('nice one'), sharedWith: {/* … */});

await posts.delete(post, cascade: true);   // removes comments too
```

Worked examples (Dart / CLI):

- [`example/bin/collections_primitives.dart`](example/bin/collections_primitives.dart)
- [`example/bin/collections_domain_objects.dart`](example/bin/collections_domain_objects.dart)
- [`example/bin/collections_generic.dart`](example/bin/collections_generic.dart)
  (polymorphic types)
- [`example/bin/collections_binary.dart`](example/bin/collections_binary.dart)
  (`Uint8List`)
- [`example/bin/collections_subcollections.dart`](example/bin/collections_subcollections.dart)
  (parent + sub with cascade)
- [`example/bin/collections_todos.dart`](example/bin/collections_todos.dart)
  (full interactive TUI)

For Flutter, the canonical reference app is
[`../at_client_flutter/examples/todos`](../at_client_flutter/examples/todos)
— same feature set as `collections_todos.dart` above, rendered
through the mobile / desktop widget stack the way a shipping app
would use it.

**Key-length note:** atServer keys are capped at 255 chars; atSigns at 55.
`subCollection(...)` enforces this at construction time with a hard
`ArgumentError` so oversized keys never reach the wire.

## Further reading

- [atPlatform overview](https://docs.atsign.com/)
- [Getting started guide](https://docs.atsign.com/start/)
- [pub.dev package page](https://pub.dev/packages/at_client)
