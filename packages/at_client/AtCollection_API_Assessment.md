# Assessment: `AtCollection<T>` in `at_client`

A reference description of the `AtCollection<T>` API in
`packages/at_client/lib/src/collections/collections.dart`, as of
2026-05-06.

## TL;DR

`AtCollection<T>` is a typed Dart collection layered over the
Atsign Protocol's key/value-plus-notifications primitives. It
turns "store a typed record, share it with N atSigns, react to
remote changes, query the local store", five things the raw
`AtClient` makes you compose by hand, into a small idiomatic
CRUD surface (`create` / `update` / `delete` / `get` / `getItems`),
a composable immutable `Query<T>` builder, and a typed reactive
event stream. Reads run against a synced local store; writes
distribute across recipients invisibly. Three capabilities have
no genuine peer in other Dart CRUD libraries: per-record
ownership enforced at the type boundary, multi-destination
sharing as a field on the record, and built-in read receipts.

Server-side value-level filtering is not on the roadmap. It is
architecturally impossible under end-to-end encryption, see §2.
The atServer's regex-over-key filtering (which drives sync and
notifications) is unaffected; it is record *values* that the
server cannot decrypt.

## 1. What `AtCollection<T>` is

A Dart library on top of `AtClient` that turns the Atsign
Protocol's key/value-plus-notifications model into typed CRUD
against a collection. Principal types:

- `CItem<T>` is a single record. It carries `owner`, `id`,
  `type` tag, `obj` (the domain object), `sharedWith`,
  `createdAt`, `expiresAt`, `availableAt`. The read-receipt
  surface lives here too: `readBy` (a `Future<Set<Atsign>>` that
  lazy-loads and stays current via an event subscription),
  `readBySnapshot` (sync accessor), `wasMarkedReadByMe()`,
  `markReadByMe()`, and `receipts` (a queryable handle on the
  reserved `__rr` sub-collection that backs receipts).

- `AtCollection<T>` carries the verbs (`create`, `upsert`,
  `update`, `delete`, `get`, `getOrNull`, `getItems`,
  `getItemsAsStream`, `exists`); the composable `query()` entry
  point that mints a `Query<T>`; the reactive surface (`watch()`
  plus typed sub-streams); sub-collection construction
  (`subCollection<U>(...)`) plus `getDescendant<U>(...)` for a
  one-call walk down a sub-item ancestry; two sharing-mutation
  paths (`update` taking an optional `sharedWith:` set, plus
  `updateSharedWith` for delta-only recipient changes); and
  orphan recovery (`cleanupOrphans()`). `upsert` is the
  idempotent create-or-update verb (use it from any publisher
  that may restart within the collection's TTL); `getDescendant`
  takes a `CSubItemUpdated.ancestry` chain plus the leaf's
  `(id, owner)` and returns the typed leaf `CItem<U>` after
  walking parent CItems internally. In-process writes emit `CEvent`s
  synchronously on the writing collection's controller (and on
  every ancestor collection's controller for sub-collection
  writes), so UI bound to `Query.watch` redraws immediately
  rather than after the notification round-trip.

- `Query<T>` is an immutable, value-typed builder returned by
  `collection.query()`. Modifiers (`.where`, `.wherePath`,
  `.orderBy`, `.thenBy`, `.limit`, `.skip`, `.distinct`) compose;
  terminals (`.get`, `.watch`, `.count`, `.any`, `.first`,
  `.firstOrNull`, `.groupBy`, `.watchWithSub`, `.watchWithTree`)
  execute against the synced local store. Each modifier returns
  a new `Query<T>`, so two branches off the same base do not
  share state. `watch()` keeps a per-stream result-list cache
  and mutates it in place on each event (single-item read on
  update, zero-read on delete); paginated queries
  (`limit` / `skip`) fall back to full refetch because items can
  shift in and out of the visible window.

- The `CEvent` hierarchy is an `abstract class` (deliberately
  not `sealed`): `CItemUpdated`, `CItemDeleted`, `CReadReceipt`,
  `CSubItemUpdated`, `CSubItemDeleted`, `CItemAvailable`,
  `CItemExpiringSoon`. New event types can land in minor versions
  without breaking downstream `switch` statements that include a
  `default:` branch. Apps that want exhaustive dispatch use the
  typed sub-streams rather than a single `switch`.

- Sub-collections come from `parent.subCollection<U>(...)`,
  which returns another `AtCollection<U>` whose lifetime is tied
  to a specific parent item. Cascade delete is opt-in on
  `delete`; `cleanupOrphans()` recovers the offline-then-online
  case.

The full public API surface is tabulated in §4.

## 2. Platform context (why the library is shaped the way it is)

Five facts about the Atsign Protocol that shape every decision in
`AtCollection<T>`:

1. **Local-first with real-time sync (by default).** Every record
   a caller can see is held in local storage on the device (Hive
   today; planned move to SQLite for end-user apps, pluggable
   RDBMS for backend services). By default, reads hit that local
   store; the `at_client` SDK keeps the cache current via a
   bidirectional sync channel with the user's atServer. Typical
   sync latency today is ~50-200 ms end-to-end; the in-development
   "fsync" replacement drops that to ~10-30 ms excluding network
   transit. Offline writes queue locally and flush on reconnect.

2. **All inter-atSign data values are end-to-end encrypted.** A
   record shared from `@alice` to `@bob` is encrypted with
   `@bob`'s public key and stored on `@bob`'s atServer; `@bob`'s
   client decrypts it locally. No atServer ever holds a
   decryption key for data it is storing on behalf of another
   atSign, so it cannot reason over the **values** those records
   carry. This is why `AtCollection<T>` filters client-side: the
   server literally cannot inspect the data. (The atServer *can*
   and does filter by the plaintext-exposed **key** structure;
   regex over atKeys drives sync and notifications. It just
   can't filter on field values inside records.) What looks like
   a "server-side
   filter gap" in a naïve comparison is an architectural
   guarantee, not an oversight.

3. **Self-hosting is first-class.** An organisation can host its
   own atServers; it can host a split-horizon atDirectory so it
   is not dependent on `root.atsign.org:64`; for fully isolated
   enterprise deployments it can stand up an entirely
   hermetically sealed Atsign ecosystem (atDirectory + atSign
   registration & provisioning + a fleet-of-swarms of atServers,
   which scales indefinitely). `AtCollection<T>` is unaware of
   any of this, it talks to whichever atServer the underlying
   `AtClient` is bound to.

4. **Post-quantum crypto is in active development.** The current
   crypto stack (RSA-2048 + AES-256) is pluggable; an in-progress
   programme replaces it with Signal triple-ratchet plus
   post-quantum primitives as the default. See
   [#1889](https://github.com/atsign-foundation/at_client_sdk/issues/1889),
   [#1891](https://github.com/atsign-foundation/at_client_sdk/issues/1891),
   [#1893](https://github.com/atsign-foundation/at_client_sdk/issues/1893).
   `AtCollection<T>` adds no crypto of its own, it inherits
   whatever the SDK below it negotiates, so when the upgrade
   lands, every app built on AtCollection picks it up
   transparently.

5. **Metadata timestamps are first-class on the wire.**
   `Metadata.createdAt` / `updatedAt` / `expiresAt` /
   `availableAt` are emitted on the wire as `:cAt:` / `:uAt:` /
   `:eAt:` / `:aAt:` fields, formatted as ISO 8601 UTC with six
   fractional-second digits (e.g. `2026-05-05T11:59:44.123456Z`).
   The `delete` verb carries a `:dAt:` (deletedAt) field of the
   same shape. The fields ride through every `update` / `update:meta` /
   `notify` envelope, so the timestamps `CItem<T>` carries round-trip
   across the wire alongside the record value rather than being
   inferred client-side from `ttl` / `ttb`. App-visible `CItem`
   API does not change as a result; the plumbing is below the
   AtCollection surface.

Downstream consequences for the API shape:

- **Reads happen on-device against the synced local store.**
  `collection.query()` returns a composable `Query<T>` value;
  `getItemsAsStream()` remains as the untyped escape hatch for
  ad-hoc stream pipelines. Either way the filter evaluates
  locally over already-decrypted records, with a
  hundred-thousand-record budget comfortably in reach on typical
  hardware.

- **Read cost is dominated by local I/O**, not network
  round-trips, once the collection is synced. `getItems()`
  returning the whole collection doesn't incur a fan of RPCs per
  item; it's a scan over already-decrypted local records.

- **Schema drift recovery is inherent.** If a sender updates
  concurrently with a receiver going offline, the receiver's next
  sync pass catches everything up, no merge/conflict layer is
  needed at the AtCollection level because there is only one
  owner per record.

## 3. The cost of going without

Without `AtCollection<T>`, an app that wanted to do "save a typed
Todo shared with two atSigns" would write, roughly:

```dart
final id = DateTime.now().microsecondsSinceEpoch.toString();
final md = Metadata()
  ..ttr = -1 ..ccd = true ..namespaceAware = false
  ..expiresAt = expiresAt
  ..ttl = expiresAt.millisecondsSinceEpoch - DateTime.now().millisecondsSinceEpoch;

final selfKey = AtKey.fromString('$id.todos.my_app@alice')..metadata = md;
final payload = jsonEncode({'type': 'Todo', 'readBy': [], 'obj': todo.toJson()});
await atClient.put(selfKey, payload);

for (final r in recipients) {
  final k = AtKey.fromString('$r:$id.todos.my_app@alice')..metadata = md;
  await atClient.put(k, payload);
}
```

And to *read* those records back:

```dart
final regex = '(^|:)[^.]+\\.todos\\.my_app@';
final keys = await atClient.getAtKeys(regex: regex);
final seen = <String>{};
final todos = <Todo>[];
for (final k in keys) {
  final fullKeyAndOwner = '${k.key}${k.sharedBy ?? ''}';
  if (!seen.add(fullKeyAndOwner)) continue;
  final v = await atClient.get(k);
  final decoded = jsonDecode(v.value);
  final owner = k.sharedBy!.toAtsign();
  final id = k.key.split('.').first;
  // … walk the decoded map, handle the type tag, recombine into a domain Todo …
}
```

And to *react* to a remote update:

```dart
atClient.notificationService
    .subscribe(regex: '.*\\.todos\\.my_app@', shouldDecrypt: true)
    .listen((n) {
      String keyName = n.key.replaceAll('${n.to}:', '').replaceAll(n.from, '');
      final ix = keyName.lastIndexOf('.todos.my_app');
      if (ix >= 0) keyName = keyName.substring(0, ix);
      final id = keyName.split('.').reversed.first;
      switch (n.operation) {
        case 'update': /* ... */
        case 'delete': /* ... */
      }
    });
```

Read receipts? In practice almost no-one implements them at
this layer. Doing so requires inventing the `__rr` namespace
pattern, a send path, a receive handler, and a dedup scan. The
cost of a raw implementation is high enough that the feature is
*unavailable* to anyone who isn't an SDK author.

### 3a. Lines of application code, canonical operations

| Canonical operation                                           | Raw `AtClient` LOC  | `AtCollection<T>` LOC | Reduction |
|---------------------------------------------------------------|---------------------|-----------------------|-----------|
| Create + share typed object with N recipients                 | ~30-40              | 1                     | ~97 %     |
| Update an existing item's fields                              | ~15-20              | 2                     | ~88 %     |
| List all items (self + received), deduped + sharedWith merged | ~25-30              | 1                     | ~96 %     |
| Filter + list (e.g. `.where(done).toList()`)                  | ~30                 | 3                     | ~90 %     |
| Subscribe to updates with typed payload                       | ~15-20              | 1                     | ~94 %     |
| Send a read receipt (and receive one)                         | ~30 + invent scheme | 1 + 1 auto            | ~93 %     |
| Sub-collection scoped to a parent, cascade on delete          | N/A (invent it)     | 3                     |,         |

The current-API side of each row corresponds to genuine
single-line invocations:

```dart
final item = await todos.create(obj: Todo('write readme'), sharedWith: {bob});
await todos.update(item);
for (final t in await todos.getItems()) print(t.obj);
todos.updates.listen((e) => refresh(e.id));
await inboundItem.markReadByMe();
final unread = await todos.query().where((t) => !t.obj.done).count();
```

### 3b. Atsign Protocol concepts hidden vs exposed

The real win isn't LOC. It's the mental model the library
removes. Every raw-API concept on the left used to be a
potential source of bugs; every one that says "Hidden" on the
right is a concept the caller no longer has to remember.

| Atsign Protocol concept                     | Before (raw), caller writes code against it    | After, AtCollection status                                           |
|---------------------------------------------|-------------------------------------------------|-----------------------------------------------------------------------|
| AtKey format (self vs shared vs cached)     | Every put/get uses `AtKey.fromString("...")`    | Hidden, caller never writes an AtKey                                 |
| Metadata fields (ttr/ccd/ttl/ttb/expiresAt) | Caller composes Metadata by hand                | Hidden, caller sets `item.expiresAt` / `item.availableAt`            |
| Shared-with machinery (1 key per recipient) | Caller writes a for-loop across recipients      | Hidden, `sharedWith:` set on `CItem`                                 |
| Cached-prefix semantics on received keys    | Caller strips `cached:@self:` to parse          | Hidden, surfaces as `CItem.owner != self`                            |
| Namespace-aware vs namespace-free keys      | Caller sets `md.namespaceAware = false`         | Hidden, collection always uses namespace-free form                   |
| Notification key format                     | Caller parses `@to:<id>.<subspace>.<ns>@<from>` | Hidden, events arrive as typed `CEvent`s                             |
| Regex composition for key scans             | Caller writes regexes by hand                   | Hidden, `getItems` / `getItemsAsStream` compose internally           |
| JSON envelope (type tag, readBy, obj)       | Caller invents it                               | Hidden, `CItem.toJson` / rehydrate machinery                         |
| 255-char key length + 55-char atSign limit  | Caller may learn it the hard way                | Enforced at `subCollection` construction                              |
| Read-receipt key pattern (`__rr`)           | Feature unavailable to app authors in practice  | One-line: `item.markReadByMe()` (reader) / `item.readBy` (owner)      |
| Application namespace composition           | Caller must know it explicitly                  | Still exposed, caller provides fully-qualified namespace (by design) |

Net: ten of eleven concepts move from "app must maintain" to
"library handles". The one that stays exposed ,
fully-qualified namespace, is a deliberate design choice:
implicit namespace composition would make the call site less
greppable and the behaviour depend on `AtClientPreference`
context.

## 4. The current API surface, compact view

| Category                 | Methods / fields exposed                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
|--------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Drafting                 | `draft({obj, id?, sharedWith?, expiresAt?, availableAt?})` (no I/O)                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| Create / Update / Delete | `create({obj, id?, sharedWith?, expiresAt?, availableAt?})` (throws on collision); `upsert({id, obj, sharedWith?, expiresAt?, availableAt?})` (idempotent create-or-update); `update(item, {sharedWith?, unshareWithOthers})` (throws if missing); `updateSharedWith(item, newSharedWith, {unshareWithOthers})` (recipient-delta only); `delete(item, {cascade})`                                                                                                                                                       |
| Read one                 | `get(id, owner)` (throws if missing), `getOrNull(id, owner)` (null if missing or not yet available), `exists(id, owner)`                                                                                                                                                                                                                                                                                                                                                                                                |
| Read many                | `getItems({id?, owner?})` (List, throws on decode error), `getItemsAsStream({id?, owner?})` (Stream, errors yielded in-band; items past `expiresAt` or with `availableAt` in the future are skipped silently — same lifecycle bucket: logically non-existent)                                                                                                                                                                                                                                                          |
| Query builder            | `query()` → `Query<T>`; modifiers `.where(p)`, `.wherePath(predicate)`, `.orderBy(keyFn, {descending})`, `.thenBy(keyFn, {descending})`, `.limit(n)`, `.skip(n)`, `.distinct(keyFn)`; terminals `.get()` (with `.fetch()` retained as a `@Deprecated` alias for one minor), `.watch()`, `.count()`, `.any([p])`, `.first()`, `.firstOrNull()`, `.groupBy<K>(keyFn)`, `.watchWithSub<U>(subName, subDefaultExpiration, {subFromJson, subTypeTag})` (live parent+children join), `.watchWithTree(List<SubSpec>)` (recursive multi-level join) |
| Read receipts            | On `CItem`: `markReadByMe()`, `wasMarkedReadByMe()`, `readBy` (Future), `readBySnapshot` (sync), `receipts` (the `__rr` sub-collection). On `AtCollection`: `markReadByMe(item)` / `wasMarkedReadByMe(item)` shims, `readReceiptsFor(item)` → queryable receipts sub-collection.                                                                                                                                                                                                                                        |
| Sub-collections          | `subCollection<U>({parent, subName, defaultExpiration, fromJson?, typeTag?})`; `getDescendant<U>({ancestry, id, owner, leafExpiration, intermediateExpiration?, leafFromJson?, leafTypeTag?})` (one-call walk that's the receiver-side dual of `subCollection` for sub-item events); `cleanupOrphans()` (works on root and sub)                                                                                                                                                                                          |
| Events                   | `watch()` → `Stream<CEvent>`; typed getters `updates` / `deletes` / `readReceipts` / `subUpdates` / `subDeletes` / `availableEvents`; method `expiringSoonEvents({required leadTime})` for time-before-expiry alerts                                                                                                                                                                                                                                                                                                    |
| Exceptions               | `CollectionOpException` (write failures, with `.results` / `.failures` / `.firstFailure`); `CollectionGetException` (read/decode failures, with `.partialItems` / `.errors`); `StateError` (create-collides / update-missing / cascade-needed); `ArgumentError` (invalid input); `AtKeyNotFoundException` (get of absent)                                                                                                                                                                                               |

## 5. What's distinctive

Nine properties that distinguish `AtCollection<T>` from both the
distributed CRUD peers it competes with and the typical Dart
library shape. The first four are about the platform model the
peers can't match; the next five are about the Dart-surface
choices that make the library pleasant to use.

1. **Per-record ownership baked into the record.** Every `CItem`
   has a single `owner`. The library enforces that only the
   owner can `create` / `update` / `delete`. Firestore does this
   via centrally-configured security rules; AtCollection does it
   at the type boundary, enforced in Dart. App code can't write
   to another atSign's record by accident.

2. **Multi-destination distribution as a first-class concept.**
   Saving a `CItem` with `sharedWith: {@bob, @carol}` *is* the
   multi-destination write. The library handles the
   per-recipient key-key-key machinery invisibly. When the set
   is later changed and `update` (or the explicit
   `updateSharedWith` delta-only path) runs, the library diffs
   recipients and un-shares the ones removed. No comparable in
   the peer set.

3. **Read receipts without app-level bookkeeping.**
   `item.markReadByMe()` on the reader side is idempotent;
   `CReadReceipt` events fire automatically on the owner side;
   the owner's `item.readBy` future resolves to the live set of
   reader atSigns and is maintained in-place as receipts arrive.
   Receipts ride a reserved `__rr` sub-collection per item, kept
   as an append-only side-car so writing a parent item never
   round-trips to preserve receipts. None of the comparables
   implement receipts because none of them have the
   per-recipient-copy model to hang receipts on.

4. **Sub-collections with parent-scoped lifetime, including
   offline recovery.** Firestore has sub-collections; they are
   independent of the parent doc for lifecycle (well-known
   footgun). AtCollection binds the sub-collection's namespace
   to the parent's id, with both a live listener (cascade-fires
   on parent-delete notification) and a `cleanupOrphans()`
   offline-recovery hatch so descendants don't stay orphaned.
   The orphan sweep chain-walks every ancestor in the
   descendant's `parents` envelope; if any level between root
   and direct parent is locally absent, the descendant is
   reaped. This handles the hardest distributed-deletes case:
   app A is offline while the parent gets deleted by app B,
   then A comes online, and the sweep cleans up. No Dart
   competitor addresses this scenario, they assume a central
   store.

5. **Typed generics that actually carry weight.**
   `AtCollection<Todo>` means `getItems()` returns
   `List<CItem<Todo>>`, events carry typed payloads,
   `draft(obj: Todo(...))` fails at compile time for the wrong
   type.

6. **Typed event hierarchy with a forward-compat default.**
   `CEvent` is an `abstract class`, deliberately not `sealed`,
   so future minor versions can introduce new event types
   without breaking an existing app's `switch` statement. Apps
   that want exhaustive dispatch use the typed sub-streams
   (`collection.updates`, `.deletes`, `.readReceipts`,
   `.subUpdates`, `.subDeletes`, `.availableEvents`) rather than
   a single `switch`.

7. **Stream-based reactivity.** Stream operators (`.where`,
   `.map`, `.toList`) compose with `watch()` and
   `getItemsAsStream()`; the higher-level `Query<T>` builds on
   the same primitives to hand out
   `.watch()` → `Stream<List<CItem<T>>>` terminals. No ad-hoc
   callback API.

8. **API hygiene.** `AtCollection<T>` is an `interface class`
   (forbids `extends`, preserves `implements` for mocking).
   `OpSuccess`, `OpFailure`, every `CEvent` subclass, and
   `CollectionOpException` are `final` so user code can't
   subclass and lock the field set. `OpResult` is not `sealed`,
   because the variant set is open in practice and a sealed
   declaration would force a major-version bump on every new
   variant.
   `create(...)` uses named arguments so the call site reads
   intent; `get(id, owner)` uses positional because both are
   always required.

9. **Exception types with useful information.**
   `CollectionOpException` carries `.results` / `.failures` /
   `.firstFailure`; `CollectionGetException` carries
   `.partialItems` and `.errors` so the caller can choose how
   strict to be.

### 5a. From the LLM-coding-assistance angle

Three properties matter specifically for auto-written code:

- **CRUD verbs match the reader's prior.** An LLM reaches for
  `create`, `update`, `delete`, `get`, `getItems`, and gets
  what it expects. Raw-AtClient code forces the LLM to first
  learn the atKey idiom, then emit it.

- **No regex composition.** Generated code is notoriously bad
  at regex escaping; AtCollection removes that hazard
  entirely.

- **`typeTag` is required everywhere a `fromJson` factory is
  supplied.** No implicit `T.toString()` fallback exists, so
  Dart's minifier / tree-shaker (AOT obfuscated builds) can't
  silently rename the on-wire type tag underneath deployed
  callers. The registry rejects re-registering the same type
  under a different tag and rejects binding the same tag to two
  different types. An unknown envelope `type` tag at decode
  time logs a one-shot WARNING via the per-collection logger,
  pointing at `registerFactory<YourType>(... typeTag: '...')`,
  with per-tag dedup so the noise is bounded.

## 6. Comparison with CRUD libraries that write to a remote service

This section is restricted to libraries whose writes ultimately
reach a remote service, either directly (per-call client-server)
or indirectly (local-first store with eventual sync). Pure-local
stores (Hive, Isar, ObjectBox, Drift, IndexedDB) are out of scope:
they solve a different problem (single-user on-device persistence)
and the rows that matter for AtCollection, sharing, ownership,
sync semantics, don't apply to them. CRDT collaborative-editing
libraries (Yjs, Automerge) are also out of scope; the
conflict-free mergeable-state model is a different problem shape
from "owned records distributed to recipients."

### 6a. Vocabulary, side by side

| Operation                | **AtCollection<T>**                                            | Firestore (Dart)                                | Supabase (`postgrest_dart`)              | PouchDB / CouchDB                          | Realm (Atlas Device Sync)                              |
|--------------------------|----------------------------------------------------------------|-------------------------------------------------|------------------------------------------|--------------------------------------------|--------------------------------------------------------|
| Create (id known)        | **`create(obj, id: x)`**, throws on collision                 | `doc(id).set(data)` upsert                      | `from(t).insert(...)`                    | `db.put({_id, ...})`                       | `realm.add(obj)`                                       |
| Create (auto-id)         | **`create(obj)`**, retries on collision                       | `collection.add(data)`                          | `from(t).insert(...)`                    | `db.post({...})`                           | `realm.add(obj)` (auto PK)                             |
| Update existing          | **`update(item)`**, throws if missing                         | `doc(id).update()`, 404                        | `from(t).update()`                       | `db.put({_id,_rev,...})`                   | `realm.write(() => obj.x = y)`                         |
| Blind upsert             |, (no upsert; use create/update explicitly)                    | `doc(id).set(data)`                             | `from(t).upsert(...)`                    | `db.put` w/ `_rev`                         | `realm.add(obj, update: true)`                         |
| Delete                   | **`delete(item)`**, cascade-opt-in                            | `doc(id).delete()`                              | `from(t).delete()`                       | `db.remove(doc)`                           | `realm.delete(obj)`                                    |
| Read one                 | **`get(id, owner)`** / **`getOrNull`**                         | `doc(id).get()`                                 | `select().eq().single()`                 | `db.get(id)`                               | `realm.find<T>(pk)`                                    |
| Read many                | **`getItems()`** / **`getItemsAsStream()`**                    | `collection.get()`                              | `select()`                               | `db.allDocs()`                             | `realm.all<T>()`                                       |
| Query / filter           | `.query().where/orderBy/limit/skip` + terminals                | `.where()` chain                                | `.eq().gt()` chain                       | mango selectors                            | `realm.query<T>(rqlString)`                            |
| Where filter executes    | **on-device**, server cannot decrypt to filter                | server (indexed, plaintext)                     | server (Postgres)                        | on-device (indexed)                        | on-device (synced local copy)                          |
| Sync model               | **continuous bidirectional sync per atSign** (`at_client` SDK) | offline cache + background sync (Firestore SDK) | client-server, every op hits the network | manual or continuous replication push/pull | continuous bidirectional auto-sync (Atlas Device Sync) |
| Watch / subscribe        | **`watch()`** + typed sub-streams                              | `snapshots()`                                   | realtime channel                         | `changes().on('change')`                   | `Stream<RealmResultsChanges<T>>`                       |
| Typed generics           | **`fromJson` per-collection**                                  | `withConverter<T>`                              | code-gen types                           | none (plain JS objects)                    | annotated `RealmObject` classes                        |
| Sharing / multi-dest     | **`sharedWith` on record** (library hides distribution)        | none (ACLs only)                                | RLS (server)                             | replication between DBs                    | partitioned-realm scopes                               |
| Record ownership         | **built into `CItem.owner`** (Dart-enforced)                   | none (ACLs only)                                | RLS (server)                             | `_owner` field convention                  | partition / role-based                                 |
| Read receipts            | **`markReadByMe` + `readBy` + `CReadReceipt`**                 |,                                               |,                                        |,                                          |,                                                      |
| Nested / sub-collections | **`subCollection` with parent-scoped cascade**                 | documents-under-docs (no cascade)               | foreign keys                             |,                                          | embedded objects + linked                              |
| End-to-end encryption    | **yes, between every pair of atSigns, by default**            | no                                              | no                                       | no (replication is TLS)                    | no (TLS in transit; opt-in at-rest)                    |
| Local-first (full copy)  | **yes, sync keeps per-atSign local store current**            | no (offline cache, not full)                    | no                                       | yes (replicated DB)                        | yes (full or partitioned)                              |

### 6b. Sync model, in plain English

The "Sync model" row is the single most useful axis for choosing
between these libraries; the shapes differ in ways that matter
for what an app feels like.

- **AtCollection** keeps a synced local copy of every record this
  atSign can see. The `at_client` SDK runs a bidirectional
  notification-driven sync channel against the user's atServer;
  reads hit local storage, writes queue locally and propagate
  when online. Typical end-to-end latency today is ~50-200 ms;
  the in-development "fsync" replacement drops that further. Sync
  is per-atSign, each user has their own atServer, so there is
  no central database that all clients share.

- **Firestore** runs an offline cache as an SDK feature: writes
  apply to the cache and propagate to the server on reconnect,
  and `snapshots()` reads come from the cache plus a server
  stream. The cache is partial (driven by which queries you've
  executed) rather than a full local copy, and the canonical
  store is Google's central Firestore service.

- **Supabase (`postgrest_dart`)** is a direct client-server
  library. There is no built-in local cache; every read and
  write is a network round-trip. Realtime push (Supabase
  realtime channels) is available as a separate subscription
  primitive but does not populate a local store the SDK then
  queries against.

- **PouchDB / CouchDB** is the closest analogue in *spirit* to
  AtCollection: per-device databases that replicate against
  CouchDB endpoints. Replication is explicit (`db.sync(remote)`
  or `db.replicate.to/from`) and can be one-shot or continuous.
  Conflict resolution is rev-vector based.

- **Realm (Atlas Device Sync)** keeps a full or partitioned local
  Realm and ships changes back and forth with MongoDB Atlas
  continuously. Conflict resolution is operational-transform
  style. Strong typing via annotated `RealmObject` classes and
  code-gen.

The two structural axes that fall out of these descriptions:
**(i) is there a local store the SDK reads from?** AtCollection,
PouchDB, and Realm: yes. Firestore: partial. Supabase: no.
**(ii) is the canonical store centralised or per-user?**
Firestore, Supabase, and most CouchDB / Realm deployments:
centralised. AtCollection: per-user (each atSign owns their own
atServer). The combination "full local copy + per-user canonical
store" is what makes the AtCollection sync model unusual.

## 7. Open questions

Three additive items to the API surface as it stands.

1. **Batched writes** (`createBatch` / `deleteBatch`) ,
   best-effort batched per-atSign writes returning
   `List<OpResult>`. Most peer libraries expose some batching
   primitive; we don't. Atsign Protocol can't offer cross-atSign
   ACID, but per-atSign batching is achievable and is the
   highest-impact gap. Stub TODOs are present in
   `collections.dart`. The `PredicateOp` enum already
   pre-allocates `like`, `inSet`, `between`, `contains`,
   `startsWith` against the same future-extension posture
   (`CmpPredicate.evaluate` throws `UnimplementedError` until
   each is implemented, adding them is non-breaking).

2. **Cursor pagination** (`Query<T>.startAfter(CItem)`), for
   stable scrolling on a dynamic data set. Today only
   offset-based `skip` / `limit` is offered, which is fine for
   small windows but degrades when items shift in and out of
   the visible page during scroll.

3. **Transactional semantics** across multiple writes. There is
   no way to say "save item X and sub-item Y atomically".
   Cross-recipient atomicity would clash with the asynchronous
   distribution model anyway, so this is open by design rather
   than as a roadmap item; listed for completeness.

4. **Default `eventsFromLocalSecondary` to `true`.** The flag is
   currently a required named parameter on `AtClient.collection`
   and on the `AtCollection.new` factories; production callers
   typically want `true` (consume events from the local
   keystore's `DataUpdated` / `DataDeleted` stream, which is
   sync-completion-aware and avoids a redundant remote fetch on
   every notification). The `false` path (subscribe to
   `NotificationService` regex over the wire) is what the SDK
   used to do, and it produces measurably worse latency on
   streaming workloads because each leaf event triggers an
   `atClient.get` round-trip to fetch the envelope. Switching the
   default to `true` is a one-line change inside the constructors,
   plus a doc note. Open callers that want the old behaviour
   would pass `eventsFromLocalSecondary: false` explicitly.

All four are additive (or, in the case of #4, behaviour-preserving
for callers that pin the flag). They slot in without touching
existing call sites that already pass the flag, so deferring them
is non-breaking.

## Appendix: key-length budget and tree-depth ceiling

The Atsign Protocol caps any atKey at 255 chars[^limit] and any
atSign at 55 chars (including the leading `@`). The absolute
worst-case on-wire shape for an item under a sub-collection is
the cached-shared-with form:

```
cached:<other-atsign>:<itemId>.<composedNs>@<self-atsign>
   7  +    ≤55       +1+   ≤8 +1+    ?     +    ≤55
```

Wrapper overhead at the worst case (both atSigns at 55 chars):

| Segment      | Chars   | Note                                 |
|--------------|---------|--------------------------------------|
| `cached:`    | 7       | literal prefix                       |
| `<other>`    | 55      | recipient's atSign at protocol max   |
| `:`          | 1       | separator                            |
| `@<self>`    | 55      | this client's atSign at protocol max |
| **Subtotal** | **118** |                                      |

That leaves **137 chars** for the content portion
(`<itemId>.<composedNs>`). The SDK auto-generates 8-char item
ids; reserving those 8 plus 1 char for the separator caps the
composed namespace at **128 chars**, enforced at `subCollection`
construction time with a hard `ArgumentError`.

**Tree-depth implications.** A worst-case strategy of
single-character collection / sub-collection names with an
application namespace of 15 chars (e.g. `myapp.example`) leaves
122 chars for the collections section. Each level adds:

| Element                       | Cost                            |
|-------------------------------|---------------------------------|
| Item id                       | 8 chars                         |
| `.` between id and innermost  | 1 char                          |
| Each sub-collection level     | `.<sub>.<parent.id>` = 11 chars |
| Root collection name (1 char) | 1 char                          |

So an item at depth `D` (depth 0 = root collection) costs
`10 + 11·D` chars beyond the application namespace. Solving
`10 + 11·D ≤ 122` gives `D ≤ 10.18`, so the **theoretical
maximum is depth 10, 11 levels including the root**. Realistic
hierarchical models (blog → comments → replies; kanban board →
column → card → checklist; issue → comment → reaction) use 2-3
levels, well inside the budget.

The runtime check at `subCollection` is independent of the
actual self-atSign length, so the same SDK builds round-trip-safe
keys regardless of which atSign owns this AtClient. A custom
item id longer than 8 chars (passed via `create(id: '...')` or
`draft`) will still encounter a tighter limit at write time when
atServer rejects the over-long key.

[^limit]: The 255-char limit is a legacy consequence of the
initial choice for underlying persistence, and will likely be
increased, initially most likely to 1023 chars, once atClients
and atServers have migrated to newer persistent storage.

## Verification

- `dart analyze lib test example/bin`, clean.
- `dart test --concurrency=1` across the at_client suite,
  598 tests, all passing.
- `flutter analyze` on the Flutter todos and dockerstats
  examples (`packages/at_client_flutter/examples/todos`,
  `packages/at_client_flutter/examples/dockerstats`), clean.
  Todos is the idiomatic Flutter reference for AtCollection;
  dockerstats is a 3-level sub-collection demo that pairs with
  the `dockerstats_publish` / `dockerstats_subscribe` CLIs.
  CLI developers can also consult
  `packages/at_client/example/bin/collections_*.dart` and
  `packages/at_client/example/bin/dockerstats_*.dart`.

The implementation lives in
`packages/at_client/lib/src/collections/collections.dart`.
