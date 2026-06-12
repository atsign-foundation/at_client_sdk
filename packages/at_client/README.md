<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

[![pub package](https://img.shields.io/pub/v/at_client)](https://pub.dev/packages/at_client) [![pub points](https://img.shields.io/badge/dynamic/json?url=https://pub.dev/api/packages/at_client/score&label=pub%20score&query=grantedPoints)](https://pub.dev/packages/at_client/score) [![build status](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_client_sdk.yaml/badge.svg?branch=trunk)](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_client_sdk.yaml) [![gitHub license](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)

# at_client

The **non-platform-specific** client SDK for building apps on the
[Atsign Protocol](https://atsign.com). An atSign owns a personal server (the
**atServer**); `at_client` talks to that server on its owner's behalf,
transparently handling key management, end-to-end encryption, sync, and
notifications.

`at_client` runs on **both Dart (CLI / server)** and **Flutter
(mobile / desktop / IoT)**. It is intentionally platform-neutral:
the actual onboarding dialogs, secure key storage, and CLI scaffolding
live in sibling packages that depend on `at_client`. **Flutter web
is not supported** — atSign onboarding and key storage rely on
platform plugins that don't have web implementations today.

## Which package do I actually want?

| If you're building…                        | Start with                                                                                                               |
|--------------------------------------------|--------------------------------------------------------------------------------------------------------------------------|
| A **Dart CLI or server app**               | [`at_cli_commons`](../at_cli_commons) for boilerplate + [`at_onboarding_cli`](../at_onboarding_cli) to provision atSigns |
| A **Flutter app** (mobile/desktop/IoT)     | [`at_client_flutter`](../at_client_flutter) — ships pre-built onboarding / APKAM / keychain widgets (web not supported)  |
| **Understanding** the atSign lifecycle     | [`at_auth`](../at_auth) — platform-neutral onboarding / authentication core with a detailed lifecycle writeup            |

## Core surface

The `AtClient` interface ([`lib/src/client/at_client_spec.dart`](lib/src/client/at_client_spec.dart))
is the main entry point once authentication is complete.

- `collection<T>(namespace, defaultExpiration, {fromJson, typeTag, eventSource, cleanupOrphansOnCreation})` —
  returns a `Future<AtCollection<T>>`. `fromJson` and `typeTag` travel
  together; pass either both or neither. AtCollections hide the
  low-level keystore plumbing and let you work directly with your own
  domain objects and types (see [Collections](#collections) below).
- `notificationService` — fire-and-forget and pub/sub messaging
  ([`lib/src/service/notification_service.dart`](lib/src/service/notification_service.dart))
- `syncService` — background sync between the local store and the
  atServer
- `put(AtKey, value)` / `get(AtKey)` / `delete(AtKey)` — low level CRUD against
  the keystore. You should almost never need to do this if you are using 
  AtCollections.
- `AtClientSecretSharing` (via `package:at_client/at_client_mixins.dart`,
  **experimental**) — pairwise secret sharing between clients of the
  **same** atSign: each client publishes a signed, post-quantum key package
  (X-Wing hybrid KEM), and secrets are end-to-end encrypted to one specific
  receiving client, scoped by application namespace. This is the substrate
  for the group-based encryption direction in
  [`docs/crypto-roadmap.md`](../../docs/crypto-roadmap.md); the durable
  app-facing surface will be `SecureGroup`. See
  [`example/bin/secret_sharing.dart`](example/bin/secret_sharing.dart).



## Examples

The API in `at_client` has evolved substantially over several years.
The authoritative examples of current usage are the worked programs
under these two directories — start there rather than with older
tutorials or blog posts:

- **Dart / CLI examples:** [`example/README.md`](example/README.md)
  walks through every program in [`example/bin/`](example/bin/) —
  primitives, domain objects, polymorphic / binary collections, a
  full interactive TUI todos app, raw notifications, RPCs, same-atSign
  secret sharing, and the
  [dockerstats CLI publisher / subscriber](example/README.md#dockerstats--notification-based-live-telemetry).

- **Flutter examples:**
  - [`../at_client_flutter/example/`](../at_client_flutter/example) —
    onboarding + auth UI walkthroughs (CRAM, .atKeys-file, keychain,
    APKAM).
  - [`../at_client_flutter/examples/todos/README.md`](../at_client_flutter/examples/todos/README.md)
    — full shared-todos Flutter app. The **idiomatic** Flutter
    consumer of `AtCollection<T>` — every common collection pattern
    (typed `AtCollection`, sub-collections, queries, watches, read
    receipts, sharing, schedule-via-`availableAt`) wired up the way
    a real app would. Wire-compatible with the CLI sibling so the
    two apps can share data live.
  - [`../at_client_flutter/examples/dockerstats/README.md`](../at_client_flutter/examples/dockerstats/README.md)
    — live telemetry dashboard. The deliberate counterpart to
    `todos`, `dockerstats` is the canonical worked example of a pattern the
    SDK supports but doesn't impose: **deliver via short-lived notifications,
    store in a relational database**. It demonstrates the trade-off
    explicitly because mis-applying `AtCollection<T>` to
    this shape of workload — a high-frequency stream of observations
    whose query / aggregation / windowing is the dominant design
    concern — would be wrong.

## atSign lifecycle (short version)

Before an app can read or write, an atSign must be **registered**,
**onboarded**, and the app must **authenticate**. The detailed writeup
of all three phases — including why APKAM matters for "evil app"
protection — is in [`at_auth`'s README](../at_auth/README.md). The
summary is:

1. **Register** an atSign (free at
   [my.noports.com/no-ports-plans](https://my.noports.com/no-ports-plans)
   or paid/custom at [my.atsign.com](https://my.atsign.com)). Once you have
   a registered atSign, the application code needs to get the CRAM key for
   step 2 below. Typically this is done by the app, once it knows the atSign
   to be onboarded, requesting that an OTP for the atSign be sent to the
   registered owner's email address. (There are other processes possible for
   all of this, but this is typical.)
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

// Add @carol without rewriting the self copy:
await todos.updateSharedWith(item, {'@bob'.toAtsign(), '@carol'.toAtsign()});

await for (final e in todos.updates) {
  print('updated: ${e.id} by ${e.owner}');
}
```

`update` / `delete` / `create` fire `CItemUpdated` / `CItemDeleted`
on the writing collection's event streams as soon as the local write
lands — no waiting for the network round-trip — so a UI using
`Query.watch()` redraws immediately. The same event re-fires on the
round-trip ~50–200 ms later (and ~10–30 ms excluding network transit
once fsync ships); `Query.watch`'s delta path is idempotent so the
second occurrence is invisible.

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

final list = await overdue.get();     // one-shot List
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
    .get();
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

**Key-length note.** atServer keys are capped at 255 chars and
atSigns at 55. The absolute worst-case wire shape is the
cached-copy form
`cached:<other>:<itemId>.<composedNs>@<self>`, which fixes the
wrapper overhead at 118 chars (`cached:` + 55 + `:` + 55) and
leaves **137 chars** for everything inside (item id + every
level of namespace). With 8-char auto-generated ids and 1 char
for the separator, **`composedNs` is capped at 128 chars** — a
budget enforced by `subCollection(...)` at construction time
with a hard `ArgumentError`, so oversized keys never reach the
wire. Plenty of room: with 1-char collection / sub-collection
names and a 15-char application namespace, the theoretical
ceiling is **11 levels (root + 10 nested sub-collections)**.

## Crypto providers

By default, encrypted writes use the legacy Atsign encryption provider. Apps
that need their own encryption behavior can configure
`AtClientPreference.crypto` with a `CryptoConfig` and one or more
`CryptoProvider`s. For the common one-provider setup, use
`CryptoConfig.singleProvider`. The SDK initializes those providers during
`AtClientImpl` startup, before sync and notification services are wired, and
uses the provider id in existing `appMetadata` to route future decrypts.
`appMetadata` remains the wire field for this metadata: the SDK owns only the
provider id used for routing, while any additional fields are provider-owned,
opaque to the SDK, and visible to the atServer as plaintext metadata.
Providers receive a `CryptoStorage` gateway in their
`CryptoContext` for local / remote provider state keyed by owner,
recipient, namespace, and name. They can also use `CryptoPolicy` to
handle missing providers; the default policy still throws, while custom
policies may register or lazy-load a provider and retry once.

A compact way to read the model split is:

```dart
final preference = AtClientPreference()
  ..crypto = CryptoConfig.singleProvider(
    defaultProviderId: DemoCryptoProvider.providerId,
    provider: (context) => DemoCryptoProvider(context.storage),
  );

class DemoCryptoProvider extends CryptoProvider {
  static const providerId = 'demo-v1';

  final CryptoStorage storage;

  DemoCryptoProvider(this.storage);

  @override
  String get id => providerId;

  @override
  Future<void> initialize(CryptoContext context) async {
    await storage.writeLocal(
      CryptoStorageKey(
        owner: context.currentAtSign,
        recipient: context.currentAtSign,
        namespace: 'demo_crypto',
        name: 'ready',
      ),
      'true',
    );
  }

  @override
  Future<CryptoEncryptResult> encrypt(CryptoEncryptRequest request) async {
    final ciphertext = 'demo:${request.plaintext}';
    return CryptoEncryptResult(
      ciphertext: ciphertext,
      metadata: AppMetadata(providerId: id, additional: {'format': 'demo'}),
    );
  }

  @override
  Future<CryptoDecryptResult> decrypt(CryptoDecryptRequest request) async {
    final ciphertext = request.ciphertext.toString();
    return CryptoDecryptResult(
      plaintext: ciphertext.replaceFirst('demo:', ''),
    );
  }
}
```

`CryptoConfig` is app configuration, the provider factory receives
`CryptoContext`, `CryptoStorage` is for provider-owned state, and
`AppMetadata.providerId` is the stored routing value used by future decrypts.
Per-write provider overrides use `PutRequestOptions.cryptoProviderId`;
notification overrides use `NotificationService.send(..., cryptoProviderId:)`
or `NotificationParams.cryptoProviderId`.
For the full model map, see [`CRYPTO_MODELS.md`](CRYPTO_MODELS.md).

For compact examples of provider registration and per-write overrides, see
[`example/bin/custom_crypto_provider.dart`](example/bin/custom_crypto_provider.dart),
[`test/at_client_impl_test.dart`](test/at_client_impl_test.dart) and
[`test/put_request_test.dart`](test/put_request_test.dart). For notification
provider selection, see
[`test/notification_service_test.dart`](test/notification_service_test.dart).
For storage and lazy-provider recovery behavior, see
[`test/crypto_storage_test.dart`](test/crypto_storage_test.dart)
and [`test/crypto_runtime_test.dart`](test/crypto_runtime_test.dart).

## Further reading

- [atPlatform overview](https://docs.atsign.com/)
- [Getting started guide](https://docs.atsign.com/start/)
- [pub.dev package page](https://pub.dev/packages/at_client)
