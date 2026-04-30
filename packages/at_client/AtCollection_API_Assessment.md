# Assessment v3: `AtCollection<T>` in `at_client`

A from-scratch assessment of the `AtCollection<T>` API in
`packages/at_client/lib/src/collections/collections.dart` as of
2026-04-29 (UTC); originally written end-of-day Thu Apr 23. A
2026-04-29 snagging pass closed W2 (required `typeTag`),
W9 (test hook off the public `subCollection` surface), W8
(warning on unknown envelope type tags), W3-residual (existence-
probe elision cache), W6-residual (chain-walk for legacy
descendants), W5 (`getKeys` removed from public surface),
W7 (timer-driven `CItemAvailable` / `CItemExpiringSoon` events
via `availableEvents` / `expiringSoonEvents`), and the entire
**W1 phase-2** bundle: W1(a) typed field accessors + predicate
AST + `Query.wherePath`, W1(b) `Query.thenBy` multi-key sort,
W1(c) per-stream delta maintenance in `Query.watch` (with
limit/skip queries falling back to refetch), and W1(d)
`Query.watchWithTree` recursive multi-level joins. All folded
into 3.13.0.

## TL;DR

Before `AtCollection<T>`, an app that wanted to store typed records,
share them with other atSigns, and react to live changes had to
hand-roll every canonical operation against `AtClient.put` / `get` /
`delete` / `notificationService`. That hand-rolling required the app
author to understand — and correctly maintain — about fifteen
Atsign Protocol-specific concepts (AtKey formats, metadata fields, cached-
prefix semantics, notification key parsing, namespace-aware flags, the
255/55 length limits, the `__rr` read-receipt pattern, and so on).

`AtCollection<T>` reduces the surface of these canonical operations by
~90 % of their line-count, hides ~80 % of the Atsign Protocol concepts, and
adds three capabilities that have no genuine peer in other Dart CRUD
libraries: per-record ownership, multi-destination distribution via
`sharedWith`, and first-class read receipts. Its sub-collections solve a
known footgun in Firestore and related systems (parent delete leaves
children stranded) via a scoped-namespace design and an explicit
`cleanupOrphans()` for offline-then-online recovery.

The composable query-builder (`collection.query()` → `Query<T>`)
landed on 2026-04-23 with phase-1 modifiers (`.where`, `.orderBy`,
`.limit`, `.skip`) and terminals (`.fetch`, `.watch`, `.count`,
`.any`, `.first`, `.firstOrNull`, `.groupBy`, `.watchWithSub`).
Phase-2 followed on 2026-04-29 and is now complete: `.thenBy`
multi-key sort, `.wherePath` accepting a `Predicate` AST built
from `PathField<V>` accessors (introspectable, ready for SQLite
JSON-index push-down once the local store migrates that way),
`.watchWithTree` for arbitrary-depth parent-children joins via
`SubSpec<U>` and `TreeNode<T>`, and incremental delta maintenance
in `.watch()` (single-item read on update, zero-read delete; limit
/ skip queries fall back to refetch). The
`getItemsAsStream().where(...)` stream-transformer path remains
supported as an escape hatch for ad-hoc pipelines outside the
builder's vocabulary.

Note: "no value-level server-side filter" is NOT a gap — it is
architecturally impossible under end-to-end encryption (see §1a)
and is a property of the platform. The atServer's own regex-over-key
filtering (what drives sync and notifications) is unaffected, but
record values are never decryptable at the server.

## 1. Context — what AtCollection<T> is

A `Dart` library layered on top of `AtClient` that turns the
Atsign Protocol's key/value plus notifications model into typed CRUD against
a collection. The principal types:

- **`CItem<T>`** — a single record. Carries `owner`, `id`, `type` tag,
  `obj` (the domain object), `sharedWith`, `createdAt`, `expiresAt`,
  `availableAt`. Read-receipt surface lives here too: the `readBy`
  Future-getter, the `readBySnapshot` sync accessor,
  `wasMarkedReadByMe()` and `markReadByMe()`.
- **`AtCollection<T>`** — the verbs (`create`, `update`, `delete`,
  `get`, `getOrNull`, `getItems`, `getItemsAsStream`); the
  composable `query()` entry point that mints a `Query<T>`; and the
  reactive surface (`watch()` + typed sub-streams).
- **`Query<T>`** — an immutable, value-typed builder returned by
  `collection.query()`. Modifiers (`.where`, `.wherePath`,
  `.orderBy`, `.thenBy`, `.limit`, `.skip`) compose; terminals
  (`.fetch`, `.watch`, `.count`, `.any`, `.first`, `.firstOrNull`,
  `.groupBy`, `.watchWithSub`, `.watchWithTree`) execute against
  the synced local store.
- **`CEvent`** hierarchy — deliberately **not** `sealed`:
  `CItemUpdated`, `CItemDeleted`, `CReadReceipt`, `CSubItemUpdated`,
  `CSubItemDeleted`. Kept as an `abstract class` so new event types
  can be added in future minor versions without breaking downstream
  `switch` statements that include a `default:` branch. Emitted from
  a per-collection notification subscription.
- **Sub-collections** — `parent.subCollection<U>(...)` returns another
  `AtCollection<U>` whose lifetime is tied to a specific parent item.

The full public API surface is tabulated below in §4.

## 1a. Platform context (why the library is shaped the way it is)

Four facts about the Atsign Protocol that shape every decision in
`AtCollection<T>`:

1. **Local-first with real-time sync (by default).** Every record a
   caller can see is held in local storage on the device (Hive today;
   planned move to SQLite for end-user apps, pluggable RDBMS for
   backend services). By default, reads hit that local store; the
   `at_client` SDK keeps the cache current via a bidirectional sync
   channel with the user's atServer. Current sync latency is ~1–3 s
   end-to-end; the in-development "fsync" replacement drops that to
   ~100 ms including network transit. Offline writes queue locally
   and flush on reconnect. (An `AtClientPreference.remoteLocalPref`
   setting can route individual fetches at the remote atServer
   instead — an escape hatch for edge cases. Once fsync is generally
   available, local will simply always be current enough that the
   remote-only path is no longer interesting. `AtCollection<T>`
   inherits whatever the underlying `AtClient` is configured for.)

2. **All inter-atSign data values are end-to-end encrypted.** A
   record shared from `@alice` to `@bob` is encrypted with `@bob`'s
   public key and stored on `@bob`'s atServer; `@bob`'s client
   decrypts it locally. No atServer ever holds a decryption key for
   data it is storing on behalf of another atSign, so it cannot
   reason over the **values** those records carry. This is why
   `AtCollection<T>` filters client-side: the server literally cannot
   inspect the data. What looks like a "server-side filter gap" in a
   naïve comparison is an architectural guarantee, not an oversight.
   (The atServer *can* and does filter by the plaintext-exposed
   **key** structure — regex over atKeys drives sync and
   notifications — but not by field values inside records.)

3. **Self-hosting is first-class.** An organisation can host its
   own atServers; it can host a split-horizon atDirectory so it is
   not dependent on `root.atsign.org:64`; for fully isolated
   enterprise deployments it can stand up an entirely hermetically
   sealed Atsign ecosystem (atDirectory + atSign registration &
   provisioning + a fleet-of-swarms of atServers, which scales
   indefinitely). `AtCollection<T>` is unaware of any of this — it
   talks to whichever atServer the underlying `AtClient` is bound
   to.

4. **Post-quantum crypto is in active development.** The current
   crypto stack (RSA-2048 + AES-256) is pluggable; the in-progress
   "Manhattan project" replaces it with Signal triple-ratchet +
   post-quantum primitives as the default. See
   [#1889](https://github.com/atsign-foundation/at_client_sdk/issues/1889),
   [#1891](https://github.com/atsign-foundation/at_client_sdk/issues/1891),
   [#1893](https://github.com/atsign-foundation/at_client_sdk/issues/1893).
   `AtCollection<T>` inherits whatever the crypto layer provides —
   the library adds no crypto of its own and so benefits from the
   upgrade transparently.

The downstream consequences for the API shape:

- **Reads happen on-device against the synced local store.**
  `collection.query()` returns a composable `Query<T>` value
  (`.where` / `.wherePath` / `.orderBy` / `.thenBy` / `.limit` /
  `.skip` / terminals `.fetch` / `.watch` / `.count` / `.any` /
  `.first` / `.firstOrNull` / `.groupBy` / `.watchWithSub` /
  `.watchWithTree`). `getItemsAsStream()` remains as
  the untyped escape hatch for ad-hoc stream pipelines. Either way the filter evaluates
  locally over already-decrypted records, with a
  hundred-thousand-record budget comfortably in reach on typical
  hardware.
- **Read cost is dominated by local I/O**, not network round-trips,
  once the collection is synced. `getItems()` returning the whole
  collection doesn't incur a fan of RPCs per item; it's a scan over
  already-decrypted local records.
- **Schema drift recovery is inherent.** If a sender updates
  concurrently with a receiver going offline, the receiver's next
  sync pass catches everything up — no merge/conflict layer is
  needed at the AtCollection level because there is only one owner
  per record.

## 2. Pre-AtCollection: what a developer had to write

Without `AtCollection<T>`, an app that wanted to do "save a typed Todo
shared with two atSigns" had to write, roughly, the following:

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

And read receipts? In practice, almost no-one implemented them — doing
so required inventing the `__rr` namespace pattern, a send path, a
receive handler, and a dedup scan. That last point is important: the
cost of a raw implementation was effectively so high that the feature
was *unavailable* to anyone who wasn't an atSign SDK author.

## 3. Quantified improvement

### 3a. Lines of application code to accomplish canonical operations

| Canonical operation                                           | Raw `AtClient` LOC  | `AtCollection<T>` LOC | Reduction |
|---------------------------------------------------------------|---------------------|-----------------------|-----------|
| Create + share typed object with N recipients                 | ~30–40              | 1                     | ~97 %     |
| Update an existing item's fields                              | ~15–20              | 2                     | ~88 %     |
| List all items (self + received), deduped + sharedWith merged | ~25–30              | 1                     | ~96 %     |
| Filter + list (e.g. `.where(done).toList()`)                  | ~30                 | 3                     | ~90 %     |
| Subscribe to updates with typed payload                       | ~15–20              | 1                     | ~94 %     |
| Send a read receipt (and receive one)                         | ~30 + invent scheme | 1 + 1 auto            | ~93 %     |
| Sub-collection scoped to a parent, cascade on delete          | N/A (invent it)     | 3                     | —         |

The current-API side of each row corresponds to genuine single-line
invocations. Example:

```dart
final item = await todos.create(obj: Todo('write readme'), sharedWith: {bob});
await todos.update(item);
for (final t in await todos.getItems()) print(t.obj);
todos.updates.listen((e) => refresh(e.id));
await inboundItem.markReadByMe();
final unread = await todos.query().where((t) => !t.obj.done).count();
```

### 3b. Atsign Protocol concepts hidden vs exposed

The real leverage isn't LOC — it's the **mental model** the library
removes. Every raw-API concept on the left used to be a potential
source of bugs; every one that says "Hidden" on the right is a concept
the caller no longer has to remember.

| Atsign Protocol concept                     | Before (raw) — caller writes code against it    | After — AtCollection status                                           |
|---------------------------------------------|-------------------------------------------------|-----------------------------------------------------------------------|
| AtKey format (self vs shared vs cached)     | Every put/get uses `AtKey.fromString("...")`    | Hidden — caller never writes an AtKey                                 |
| Metadata fields (ttr/ccd/ttl/ttb/expiresAt) | Caller composes Metadata by hand                | Hidden — caller sets `item.expiresAt` / `item.availableAt`            |
| Shared-with machinery (1 key per recipient) | Caller writes a for-loop across recipients      | Hidden — `sharedWith:` set on `CItem`                                 |
| Cached-prefix semantics on received keys    | Caller strips `cached:@self:` to parse          | Hidden — surfaces as `CItem.owner != self`                            |
| Namespace-aware vs namespace-free keys      | Caller sets `md.namespaceAware = false`         | Hidden — collection always uses namespace-free form                   |
| Notification key format                     | Caller parses `@to:<id>.<subspace>.<ns>@<from>` | Hidden — events arrive as typed `CEvent`s                             |
| Regex composition for key scans             | Caller writes regexes by hand                   | Hidden — `getItems` / `getItemsAsStream` compose internally           |
| JSON envelope (type tag, readBy, obj)       | Caller invents it                               | Hidden — `CItem.toJson` / rehydrate machinery                         |
| 255-char key length + 55-char atSign limit  | Caller may learn it the hard way                | Enforced at `subCollection` construction                              |
| Read-receipt key pattern (`__rr`)           | Feature effectively unavailable to app authors  | One-line: `item.markReadByMe()` (reader) / `item.readBy` (owner)      |
| Application namespace composition           | Caller must know it explicitly                  | Still exposed — caller provides fully-qualified namespace (by design) |

Net: 10 of 11 concepts moved from "app must maintain" to "library
handles". The one that stays exposed — fully-qualified namespace — is a
deliberate design choice: implicit namespace composition would have
made the call site less greppable and the behaviour depend on
`AtClientPreference` context.

## 4. The current API surface, compact view

| Category                 | Methods / fields exposed                                                                                                                                                                                                                                                                                                                                                                                                                                |
|--------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Construction             | `AtCollection(atClient, namespace, defaultExpiration, {fromJson, typeTag})`, `AtCollection.withInjectedNotifications(...)` (testing)                                                                                                                                                                                                                                                                                                                    |
| Identity                 | `atSign`, `namespace`, `defaultExpiration`, `isSubCollection`                                                                                                                                                                                                                                                                                                                                                                                           |
| Factory                  | `registerFactory<U>(fromJson, {required typeTag})`                                                                                                                                                                                                                                                                                                                                                                                                      |
| Drafting                 | `draft({obj, id?, sharedWith?, expiresAt?, availableAt?})` (no I/O)                                                                                                                                                                                                                                                                                                                                                                                     |
| Create / Update / Delete | `create({obj, id?, sharedWith?, expiresAt?, availableAt?})` (throws on collision), `update(item, {unshareWithOthers})` (throws if missing), `delete(item, {cascade})`                                                                                                                                                                                                                                                                                   |
| Read one                 | `get(id, owner)` (throws if missing), `getOrNull(id, owner)` (null if missing)                                                                                                                                                                                                                                                                                                                                                                          |
| Read many                | `getItems({id?, owner?})` (List, throws on decode error), `getItemsAsStream({id?, owner?})` (Stream, errors yielded in-band)                                                                                                                                                                                                                                                                                                                            |
| Query builder            | `query()` → `Query<T>`; modifiers `.where(p)`, `.wherePath(predicate)`, `.orderBy(keyFn, {descending})`, `.thenBy(keyFn, {descending})`, `.limit(n)`, `.skip(n)`; terminals `.fetch()`, `.watch()`, `.count()`, `.any([p])`, `.first()`, `.firstOrNull()`, `.groupBy<K>(keyFn)`, `.watchWithSub<U>(subName, subDefaultExpiration, {subFromJson, subTypeTag})` (live parent+children join), `.watchWithTree(List<SubSpec>)` (recursive multi-level join) |
| Read receipts            | On `CItem`: `markReadByMe()`, `wasMarkedReadByMe()`, `readBy` (Future), `readBySnapshot` (sync), `receipts` (the `__rr` sub-collection). On `AtCollection`: `markReadByMe(item)` / `wasMarkedReadByMe(item)` shims, `readReceiptsFor(item)` → queryable receipts sub-collection.                                                                                                                                                                        |
| Sub-collections          | `subCollection<U>({parent, subName, defaultExpiration, fromJson?, typeTag?})` (plus `notifications:` test hook — see §W9), `cleanupOrphans()` (works on root and sub)                                                                                                                                                                                                                                                                                   |
| Events                   | `watch()` → Stream<CEvent>; typed getters `updates` / `deletes` / `readReceipts` / `subUpdates` / `subDeletes` / `availableEvents`; method `expiringSoonEvents({required leadTime})` for time-before-expiry alerts                                                                                                                                                                                                                                      |
| Exceptions               | `CollectionOpException` (write failures), `CollectionGetException` (read/decode failures), `StateError` (create-collides / update-missing / cascade-needed), `ArgumentError` (invalid input), `AtKeyNotFoundException` (get of absent)                                                                                                                                                                                                                  |

## 5. Comparison with CRUD libraries in the Dart ecosystem and beyond

### 5a. Vocabulary, side by side

| Operation                | Firestore (Dart)                  | MongoDB (mongo_dart) | Isar / ObjectBox        | Hive                 | Drift (SQL)           | Supabase (postgrest)     | PouchDB                  | **AtCollection<T>**                                     |
|--------------------------|-----------------------------------|----------------------|-------------------------|----------------------|-----------------------|--------------------------|--------------------------|---------------------------------------------------------|
| Create (id known)        | `doc(id).set(data)` upsert        | `insertOne`          | `put(obj)` upsert       | `put(key, v)` upsert | `insert`              | `from(t).insert(...)`    | `db.put({_id, ...})`     | **`create(obj, id: x)`** — throws on collision          |
| Create (auto-id)         | `collection.add(data)`            | `insertOne`          | `put(obj)` auto-id      | `add(v)`             | `insert`              | `from(t).insert(...)`    | `db.post({...})`         | **`create(obj)`** — retries on collision                |
| Update existing          | `doc(id).update()` — 404          | `updateOne`          | `put(obj)`              | `put(key, v)`        | `update`              | `from(t).update()`       | `db.put({_id,_rev,...})` | **`update(item)`** — throws if missing                  |
| Blind upsert             | `doc(id).set(data)`               | `replaceOne` upsert  | `put(obj)`              | `put(key, v)`        | `upsert`              | `from(t).upsert(...)`    | `db.put` w/ _rev         | — (removed; use create/update explicitly)               |
| Delete                   | `doc(id).delete()`                | `deleteOne`          | `delete(id)` / `remove` | `delete(key)`        | `delete`              | `from(t).delete()`       | `db.remove(doc)`         | **`delete(item)`** — cascade-opt-in                     |
| Read one                 | `doc(id).get()`                   | `findOne`            | `get(id)`               | `get(key)`           | single-value query    | `select().eq().single()` | `db.get(id)`             | **`get(id, owner)`** / **`getOrNull`**                  |
| Read many                | `collection.get()`                | `find.toList()`      | `where().findAll()`     | `values`             | `select().get()`      | `select()`               | `db.allDocs()`           | **`getItems()`** / **`getItemsAsStream()`**             |
| Query / filter           | `.where()` chain                  | `find({...})`        | `.filter()` chain       | in-memory            | SQL                   | `.eq().gt()` chain       | mango selectors          | `.query().where/orderBy/limit/skip` + terminals         |
| Where filter executes    | server (indexed, plaintext)       | server (indexed)     | on-device (indexed)     | on-device (memory)   | server (SQL)          | server (Postgres)        | on-device (indexed)      | **on-device** — server cannot decrypt to filter         |
| Watch / subscribe        | `snapshots()`                     | `watch()`            | `.watchLazy()`          | `watch()`            | `.watch()`            | realtime channel         | `changes().on('change')` | **`watch()`** + typed sub-streams                       |
| Typed generics           | `withConverter<T>`                | none (Map)           | annotated entities      | TypeAdapter          | companions (code-gen) | code-gen types           | none (plain JS objects)  | **`fromJson` per-collection**                           |
| Sharing / multi-dest     | none (ACLs only)                  | none                 | none                    | none                 | none                  | RLS (server)             | replication between DBs  | **`sharedWith` on record** (library hides distribution) |
| Record ownership         | none (ACLs only)                  | none                 | none                    | none                 | none                  | RLS (server)             | _owner field convention  | **built into `CItem.owner`** (enforced)                 |
| Read receipts            | —                                 | —                    | —                       | —                    | —                     | —                        | —                        | **`markReadByMe` + `readBy` + `CReadReceipt`**          |
| Nested / sub-collections | documents-under-docs (no cascade) | —                    | —                       | —                    | relations             | foreign keys             | —                        | **`subCollection` with parent-scoped cascade**          |
| End-to-end encryption    | no                                | no                   | no                      | no (local-only)      | no                    | no                       | no (replication is TLS)  | **yes — between every pair of atSigns, by default**     |
| Local-first (full copy)  | no                                | no                   | yes (DB is local)       | yes                  | no (unless embedded)  | no                       | yes (replicated DB)      | **yes — sync keeps per-atSign local store current**     |

### 5b. Dart-ecosystem positioning

- **Firestore (Dart SDK)** — closest in shape. `doc(id).set / update /
  delete` maps cleanly to AtCollection's `create / update / delete`.
  `.snapshots()` maps to `watch()` plus typed sub-streams. Typed
  generics land the same way via a factory callback
  (`withConverter<T>` vs `fromJson:`). Firestore's indexed server-side
  `.where()` is a real convenience — but it's a convenience that
  Firestore can offer because the data is not end-to-end encrypted.
  AtCollection's on-device `.where()` is what end-to-end
  encryption looks like at the API layer. Firestore sub-collections
  are the one other place AtCollection is arguably *ahead*: Firestore
  sub-collections are independent documents that do NOT delete on
  parent delete (well-known footgun). AtCollection binds
  sub-collection lifetime to the parent item, and
  `cleanupOrphans()` handles the offline-recovery case.

- **Isar / ObjectBox** — local, single-user, typed entities via
  code-gen. `put` is upsert. No sharing, no ownership, no receipts.
  They handle on-device queries beautifully — secondary indexes,
  typed `.filter()` chains, everything. AtCollection's on-device
  scan over synced data is in the same family of execution
  (local-first, no server round-trip). Phase 1 of the `Query<T>`
  builder gives you a composable chain in the same shape as Isar's
  (`.where` / `.orderBy` / `.limit` / terminals); phase 2 —
  field-accessor value nodes and secondary-index push-down — is
  what's still in Isar/Drift territory. See §W1.

- **Hive** — lowest-overhead KV. Great for single-user prefs. Not a
  peer comparison — AtCollection is a networked, multi-user
  distributed model.

- **Drift** — SQL over SQLite. Typed companions via code-gen. Very
  different shape (relational schema, joins, transactions). Borrows
  nothing from AtCollection directly; interesting counterpoint on
  typing (Drift's generated types are tighter than AtCollection's
  `fromJson`-based rehydrate).

- **Supabase (`postgrest_dart`)** — REST-wrapped Postgres with RLS.
  Closest competitor on the "typed records, multi-user, realtime"
  axis. RLS gives row-level auth but centralised to one server;
  AtCollection gives per-record ownership across decentralised
  atServers. Supabase's Postgres indexes are operationally beautiful
  and something AtCollection never competes with — but, as with
  Firestore, they depend on Supabase seeing data in the clear. For
  the end-to-end-encrypted peer-to-peer model AtCollection occupies,
  the server-side index isn't an option.

- **mongo_dart** — loose typing (Map<String, dynamic>). Offers
  ChangeStreams but no typed generics. Not a competitive experience
  for app authors who want compile-time safety.

- **PouchDB/CouchDB (via flutter_pouchdb wrappers)** — the closest
  analogue in *spirit* to Atsign Protocol. Per-device databases, multi-
  master replication, mango queries, `.changes().on('change')` watch.
  No typed generics by default; no record-level sharing (replication
  moves whole DBs / filtered subsets).

### 5c. Cross-ecosystem (for perspective)

- **Realm** (MongoDB Atlas sync) — typed objects + cloud sync. No
  per-record ownership; partition-based.
- **IndexedDB** (via `idb_shim`) — browser-local KV with cursors.
  Not typed; AtCollection abstracts at a higher level.
- **Yjs / Automerge (CRDTs)** — collaborative document editing. A
  completely different model (mergeable state, no conflicts), applies
  where AtCollection does not (real-time co-editing) and vice versa
  (ownership semantics, receipts).

## 6. What's uniquely atSign-ish (no genuine peer)

1. **Per-record ownership baked into the record.** Every `CItem` has
   a single `owner`. The library enforces that only the owner can
   `create`/`update`/`delete`. Firestore does this via centrally-
   configured security rules; AtCollection does it at the type
   boundary, enforced in Dart. It's effectively impossible for app
   code to write to another atSign's record by accident.

2. **Multi-destination distribution as a first-class concept.**
   Saving a `CItem` with `sharedWith: {@bob, @carol}` *is* the
   multi-destination write. The library handles the per-recipient
   key-key-key machinery invisibly. No comparable in the peer set.

3. **Read receipts without app-level bookkeeping.**
   `item.markReadByMe()` on the reader side is idempotent;
   `CReadReceipt` events fire automatically on the owner side; the
   owner's `item.readBy` future resolves to the live set of reader
   atSigns and is maintained in-place as receipts arrive. None of
   the comparables implement receipts because none of them have the
   per-recipient-copy model to hang receipts on.

4. **Sub-collections with parent-scoped lifetime.** Firestore has
   sub-collections; they are independent of the parent doc for
   lifecycle. AtCollection binds the sub-collection's namespace to
   the parent's id — and both a live listener (fires on parent-delete
   notification) and a `cleanupOrphans()` offline-recovery hatch
   ensure descendants don't stay orphaned.

5. **Offline-recovery for distributed deletes.** This is the hardest
   case: app A is offline while the parent gets deleted by app B,
   then A comes online. `cleanupOrphans()` on the root (or
   sub-collection) identifies descendants whose root ancestor is now
   absent locally and deletes them. No Dart competitor addresses this
   scenario — they assume a central store.

## 7. What's uniquely Dart-idiomatic

- **Typed generics that actually carry weight.** `AtCollection<Todo>`
  means `getItems()` returns `List<CItem<Todo>>`, events carry typed
  payloads, `draft(obj: Todo(...))` fails at compile time for the
  wrong type.
- **Typed event hierarchy with a forward-compat default.** `CEvent`
  is an `abstract class` — deliberately not `sealed`, so future
  minor versions can introduce new event types (`CItemAvailable`,
  `CItemExpiringSoon`, …) without breaking an existing app's
  `switch` statement. Apps that want exhaustive dispatch use the
  typed sub-streams (`collection.updates`, `collection.deletes`,
  `collection.readReceipts`, `collection.subUpdates`,
  `collection.subDeletes`) rather than a single `switch`.
- **Stream-based reactivity.** Stream operators (`.where`, `.map`,
  `.toList`) compose with `watch()` and `getItemsAsStream()`; the
  higher-level `Query<T>` builds on the same primitives to hand out
  `.watch()` → `Stream<List<CItem<T>>>` terminals. No ad-hoc
  callback API.
- **Named & positional arguments used deliberately.** `create(...)`
  uses named args so the call site reads intent; `get(id, owner)`
  uses positional because they're always both required.
- **Exception types with useful information.** `CollectionOpException`
  carries `.results` / `.failures` / `.firstFailure`;
  `CollectionGetException` carries `.partialItems` and `.errors` so
  the caller can choose how strict to be.

## 8. Remaining weaknesses / areas for improvement

Ordered by bang-per-buck.

### W1. Query/filter DSL ergonomics — phase 1 landed

The composable `Query<T>` builder landed on 2026-04-23, complementing
`getItemsAsStream().where(...)` with a value-typed immutable builder:

```dart
final overdue = todos.query()
    .where((t) => !t.obj.done)
    .where((t) => t.obj.due.isBefore(DateTime.now()))
    .orderBy((t) => t.obj.due)
    .limit(20);

final list = await overdue.fetch();
final live = overdue.watch();
final open = await todos.query().count();
final any  = await todos.query().any((t) => t.obj.flagged);
final byOwner = await todos.query().groupBy<Atsign>((t) => t.owner);
```

Surface shipped:

- **Modifiers** — `.where(predicate)` composes (AND; multiple calls
  supported); `.orderBy(keyFn, {descending})` with last-call-wins
  semantics; `.limit(n)` and `.skip(n)` as pagination primitives.
- **Terminals** — `.fetch()` → one-shot `Future<List<CItem<T>>>`;
  `.watch()` → live reactive `Stream<List<CItem<T>>>` (re-emits on
  any `CItemUpdated` or `CItemDeleted`); `.count()` → `Future<int>`
  respecting the full spec; `.any([predicate])` → short-circuiting
  `Future<bool>`; `.first()` / `.firstOrNull()` with orderBy-aware
  short-circuit; `.groupBy<K>(keyFn)` →
  `Future<Map<K, List<CItem<T>>>>`;
  `.watchWithSub<U>(subName, subDefaultExpiration, {subFromJson, subTypeTag})`
  → live `Stream<List<({CItem<T> parent, List<CItem<U>> children})>>`
  joining each matching parent with the current children from a
  named sub-collection (replaces the manual per-parent refetch
  pattern both example apps previously hand-rolled).
- **Immutable** — each modifier returns a new `Query<T>`, so two
  branches off the same base don't share state.

Companion on `AtCollection<T>` / `CItem<T>`: `readReceiptsFor(item)`
and `item.receipts` expose the reserved `__rr` sub-collection for
direct query — e.g. a live "how many readers?" badge is
`item.receipts.query().watch().map((l) => l.length)`.

The spec is kept as an immutable data object (`_QuerySpec<T>`) so a
future indexed executor (e.g. once the local store migrates from
Hive to SQLite and JSON-field indexes become available) can
introspect the non-predicate modifiers (`.orderBy` / `.limit` /
`.skip`) directly. Pushing **predicates** down to a secondary index
additionally requires replacing `.where`'s opaque closure with an
inspectable AST — see §W1(a). Both shifts can land without changing
any caller's code. The raw `getItemsAsStream().where(...)` path
remains supported as an escape hatch for ad-hoc stream pipelines
outside the builder's vocabulary.

What's **not yet** in phase 1 (phase 2 material):

### (a) ~~Typed field-accessor values in predicates~~ (closed)

Landed 2026-04-29 in 3.13.0. App code declares typed accessors per
domain type (no codegen — one line per field):

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
```

Then on `Query<T>`:

```dart
final overdue = await todos.query()
    .wherePath($Todo.done.eq(false))
    .wherePath($Todo.due.lt(DateTime.now()))
    .fetch();

// Or composed with .and / .or / .not:
final urgent = await todos.query()
    .wherePath($Todo.done.eq(false).and($Todo.due.lt(soon)))
    .fetch();
```

Surface shipped:

- `PathField<V>` — typed accessor with `path` (introspection) and
  `extract` (evaluation). `eq` / `neq` work on any `V`; `lt` /
  `lte` / `gt` / `gte` are extension methods restricted to
  `V extends Comparable`; `isNull` / `isNotNull` extension getters
  on `PathField<V?>` for nullable fields.
- `Predicate` — abstract AST root. Three concrete combinators
  (`AndPredicate`, `OrPredicate`, `NotPredicate`) plus the
  `CmpPredicate` leaf. `.and`, `.or` flatten on construction;
  `.not.not` collapses double negation. All public so a future
  indexed executor can pattern-match.
- `PredicateOp` enum (`eq`, `neq`, `lt`, `lte`, `gt`, `gte`,
  `isNull`, `isNotNull`) carried by `CmpPredicate` for switchable
  push-down.
- `Query<T>.wherePath(Predicate)` — new modifier; coexists with
  closure-based `where`. Both lists AND together at evaluation
  time. The typed-AST list is preserved on `_QuerySpec` so a
  future SQLite-indexed executor can walk it.

Today the library evaluates AST predicates in memory, behaviourally
identical to the closure path. The forward-looking benefit is the
introspection surface: when the local store migrates to SQLite +
JSON-path indexes, `_apply` can split eligible AST clauses into
`WHERE` push-downs and evaluate the rest in memory — no caller-code
change.

### (b) ~~Multi-key `orderBy`~~ (closed)

Landed 2026-04-29. `Query<T>.orderBy(...)` keeps replace semantics
(matches LINQ / Drift / Isar idiom), and a new `Query<T>.thenBy(...)`
appends tiebreakers:

```dart
q.orderBy((t) => t.obj.dueDate)
 .thenBy((t) => t.obj.title, descending: true)
 .thenBy((t) => t.createdAt);
```

`_QuerySpec` now holds `List<_OrderBy<T>>` (primary first) and
`_apply` runs a stable multi-key compare in registration order.
Each level carries its own `descending:` independently.
`thenBy` without a prior `orderBy` throws `StateError`. The single-
composite-key workaround still works for callers that prefer it.

### (c) ~~Incremental delta maintenance in `watch()`~~ (closed)

Landed 2026-04-29 in 3.13.0 for the no-pagination case. `Query.watch()`
now keeps a per-stream result-list cache, mutated in place by each
event:

- **Initial fetch** populates the cache.
- **Update event** (`CItemUpdated(owner, id)`): single-item read
  via `getOrNull(id, owner)`, then evaluate against predicates
  (closure + AST). Insert / replace / remove from cache; re-sort
  if `orderBy` is set; emit. Cost is **O(1) per event** vs. the
  old O(N) refetch.
- **Delete event** (`CItemDeleted(owner, id)`): remove from cache
  if present, emit. **Zero reads** — purely cache-local.

A per-stream serialiser (mutex) chains tasks so two
near-simultaneous events can't interleave on the cached list.
On per-item read errors the stream surfaces the error and falls
back to a full refetch to realign with the store.

**Pagination caveat.** `limit` / `skip` queries can't take the
delta path: when an item falls out of the visible window, the
next-out-of-window item isn't cached. So `_spec.limitN != null`
or `_spec.skipN != null` opts back into the original full-refetch
behaviour on each event — same correctness as before, same cost.
A future variant that keeps `limit + lookahead` items cached could
extend the delta path to pagination, but until a real workload
measures the cost, the simpler fall-back is the right posture.

**Pairing with (a).** The AST predicates added in (a) flow through
the same `matchesPredicates` evaluator. A future indexed-executor
landing can walk the AST, see that a `CItemUpdated` event for
`(owner, id)` doesn't touch the indexed field's value, and skip
predicate re-evaluation entirely — pushing the per-event cost
below O(1) for index-eligible queries.

### (d) ~~Deeper sub-collection queries~~ (closed)

Landed 2026-04-29 in 3.13.0. `Query<T>.watchWithTree` takes a list
of `SubSpec<U>` nodes describing the tree shape and live-orchestrates
nested watchWithSub-style streams to arbitrary depth:

```dart
posts.query().watchWithTree([
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
// → Stream<List<TreeNode<Post>>>
//   tree[i].parent              → CItem<Post>
//   tree[i].branches['comments'] → List<TreeNode<dynamic>> (per comment)
//   tree[i].branches['comments'][j].branches['replies']
//                              → List<TreeNode<dynamic>> (per reply)
```

Surface shipped:

- `SubSpec<U>` — value-typed level descriptor (`subName`,
  `subDefaultExpiration`, optional `subFromJson` + `subTypeTag`,
  recursive `children: List<SubSpec<dynamic>>`).
- `TreeNode<T>` — snapshot node carrying `CItem<T> parent` and
  `Map<String, List<TreeNode<dynamic>>> branches` keyed by
  `subName`. App code that knows the topology can
  `branches['comments']!.cast<TreeNode<Comment>>()`.
- `Query<T>.watchWithTree(List<SubSpec<dynamic>>)` →
  `Stream<List<TreeNode<T>>>`. Implemented recursively: each level
  opens a sub-collection and calls `watchWithTree` on its query
  with that level's `children`. Empty `children` is the leaf case.
- `SubSpec<U>.openOn<T>(parentColl, parent)` — `@visibleForTesting`
  helper that preserves `U` through a heterogeneous
  `List<SubSpec<dynamic>>` iteration (Dart erases per-element
  generics; the per-spec method captures `U` lexically and avoids
  a registry collision when the constructor's auto-register fires).

Cascade behaviour: when a parent leaves the result set, every
descendant subscription rooted at that parent is cancelled
transitively. Outer-stream cancellation does the same. The
`TreeNode` lower levels lose generic typing because Dart can't
thread per-level type parameters through a heterogeneous recursive
structure without codegen — same trade `Map<String, dynamic>` makes.
Apps that need tighter typing at every level can wrap with their
own typed view.

### Summary (one sentence each)

1. **(a) ~~Typed field accessors~~** — landed 2026-04-29.
   `PathField<V>` + `Predicate` AST + `Query.wherePath`; closures
   still supported alongside.
2. **(b) ~~Multi-key `orderBy`~~** — landed 2026-04-29. `Query.thenBy`
   appends tiebreakers; `orderBy` still resets.
3. **(c) ~~Delta maintenance in `.watch()`~~** — landed 2026-04-29.
   Per-stream cache, single-item re-evaluate on event; pagination
   queries fall back to refetch.
4. **(d) ~~`watchWithTree`~~** — landed 2026-04-29. Recursive
   terminal with `SubSpec<U>` nodes and `TreeNode<T>` snapshots.

All four phase-2 items closed; the original "wait for X" gating
notes are preserved in the W1 prose above for the historical
record.

Server-side value-level filtering is **not** on this list. It is
architecturally impossible under end-to-end encryption: the atServer
never holds the decryption keys for another atSign's data it is
storing, so it cannot reason over plaintext values. See §1a —
"Platform context". Pushing value predicates to the server would
require weakening E2EE, which is not a trade any AtCollection user
would sensibly make. (The atServer *can* filter by key structure —
that's what drives sync and notifications — just not by values.)

### W2. ~~Factory registry still keyed on `T.toString()`~~ (closed)

Landed 2026-04-29 in 3.13.0. `typeTag` is now a required parameter of
`AtCollection.registerFactory` and a required companion of every
`fromJson:` shortcut (`AtCollection.new`,
`AtCollection.withInjectedNotifications`, `AtClient.collection<T>`,
`AtCollection.subCollection<U>`, `Query<T>.watchWithSub<U>`). The
implicit `T.toString()` fallback is gone, so Dart's minifier /
tree-shaker (release-mode Flutter web, AOT obfuscated builds) can
no longer silently rename the on-wire type tag underneath
deployed callers. The registry also now rejects re-registering the
same type under a different tag, and rejects binding the same tag
to two different types — same-(type, tag) re-registration remains
idempotent (last-fromJson-body-wins) so test harnesses still work
unchanged. Primitives and `Uint8List` continue to use their
synthetic `'n/a'` / `'binary'` tags.

### W3. ~~`put`-on-update is still reads-before-writes~~ (closed)

The readBy-merge read was removed when read receipts moved to the
reserved `__rr` sub-collection (see W4). The remaining existence
probe is now elided too (closed 2026-04-29): each collection
maintains a per-process `_seenSelfIds` set populated on successful
`_put`, drained on successful self-key delete. `_selfKeyExists`
short-circuits when the id is in the set, so a `create → update`
sequence in the same process pays no probe round-trip on the
update. Cross-process visibility is unaffected — self-keys are
owner-scoped and only this client writes them, so a local
"I just wrote it" entry is authoritative. The first `update` after
process restart still probes (cache is in-memory only).

### W4. ~~`CItem.readBy` merge couples write cost to read semantics~~ (closed)

Read receipts now live in a reserved `__rr` sub-collection per item.
The old eager `readBy` array baked into the parent record's envelope
is gone. The current surface on `CItem` is: `readBy` (a
`Future<Set<Atsign>>` that lazy-loads + stays current via an event
subscription), `readBySnapshot` (sync accessor for the same cache),
`wasMarkedReadByMe()`, and `markReadByMe()` (the single-entry write
path, shared by the reader). Writing a parent item no longer
round-trips to preserve receipts — the sub-collection is an
independent, append-only side-car.

### W5. ~~`getKeys(...)` leaks `AtKey` into the public API~~ (closed)

Closed 2026-04-29 by **removing the public method entirely**, not
merely marking it `@visibleForTesting`. There were no example or
production callers, and the two unit tests that exercised it
(`'composes regex with id and owner filters'` and `'defaults id
and owner to wildcards'`) were testing an implementation detail
in isolation — every other read/write/cleanup test in the suite
uses the same regex composition through higher-level methods, so
nothing test-side is lost.

The implementation lives entirely behind a private
`_getKeysInternal`; the four SDK-internal callers (the
`getItemsAsStream` decode loop, the cleanup-orphans root scan,
`_put`'s recipient diff, `_delete`'s self-and-recipients sweep)
all route through it. With the public method gone, **`AtKey` no
longer appears anywhere in the AtCollection public surface** —
the design intent ("typed collection over an opaque protocol") now
holds without an asterisk.

### W6. ~~`cleanupOrphans` only catches root-ancestor orphans~~ (closed)

`_cleanupOrphansFromRoot` chain-walks every ancestor in the
descendant's `parents` envelope — if any level between root and
direct parent is locally absent, the descendant is orphaned and
swept. Middleman-orphan case is handled for envelope-bearing items
since the 2026-04-21 tidy-up. The legacy fallback (items predating
the `parents` field) was extended on 2026-04-29 to also chain-walk
by id-presence at each composed-namespace level via a per-sweep
`_aliveIdsAt` cache — depth-2+ legacy descendants whose middleman
is gone are now swept too. Lookups are owner-agnostic at each
level (we can't recover ancestor owners from a legacy key), so the
path is intentionally lenient: false negatives (sparing a possibly-
orphaned item) beat false positives (deleting a live one) under
ambiguity.

### W7. ~~No timer-driven events~~ (closed)

Closed 2026-04-29 in 3.13.0. Two new event surfaces:

- **`AtCollection<T>.availableEvents`** — `Stream<CItemAvailable>`
  fired as each tracked item's `availableAt` passes. Lazy-starts a
  per-collection scheduler on first access; runs for the life of
  the collection. Items with no `availableAt` (immediately visible)
  or with `availableAt` already in the past at write time (the
  envelope rehydrator drops them — see `_liveAvailableAt`) aren't
  tracked. Flows through [`watch`] alongside the other typed
  sub-streams so a single `switch (event)` listener can pick it up.

- **`AtCollection<T>.expiringSoonEvents({required Duration leadTime})`**
  — single-subscription `Stream<CItemExpiringSoon>` fired
  `leadTime` before each item's `expiresAt`. Per-call scheduler
  lifecycle: spins up on listen, tears down on cancel. Items
  already inside their warning window (`expiresAt - leadTime`
  in the past) at subscription time fire on the next event-loop
  turn so listeners don't silently miss them. Does **not** flow
  through `watch` because the lead time is per-subscription —
  there's no single canonical value to surface on the master
  stream.

Implementation: a `_CItemTimerScheduler<E, T>` keeps a sorted-by-
`fireAt` list of pending `_Firing<E>` records and arms a single
shared `Timer` to the soonest. The scheduler subscribes to the
collection's `updates` / `deletes` streams to rebuild firings
when an item's `availableAt` / `expiresAt` changes or the item
disappears. On the initial scan it populates the heap from
`getItems`. The implementation is generic over the event type
and reused for both surfaces by passing a different
`fireAtOf` / `makeEvent` pair. List-based heap is O(N) per
mutation; with realistic item counts the per-event work is well
below `Timer` overhead, and a binary-heap swap is straightforward
if a real workload demands it.

### W8. ~~Cross-atSign interop fragility via the `type` string~~ (closed)

Closed 2026-04-29. The first time `_rehydrate` encounters an
envelope `type` tag with no registered factory (and the tag isn't
the synthetic `'n/a'` / `'binary'` markers), it logs a WARNING via
the per-collection `AtSignLogger`, naming the missing tag and the
target type, and points the developer at
`AtCollection.registerFactory<YourType>(... typeTag: '...')`. A
per-tag dedup set rate-limits the noise — one warning per unknown
tag per process. The runtime fallback (return the raw map cast to
V) is unchanged, so untyped consumers still work; the warning
just makes registry drift visible. Together with the W2 required-
`typeTag` change this closes the "silent rehydrate to wrong shape"
class of bugs.

### W9. ~~`notifications:` test hook remains on `subCollection`~~ (closed)

Closed 2026-04-29. The public `subCollection<U>(...)` method no
longer accepts a `notifications:` parameter; production IDE
auto-complete on the verb is back to just the parameters
production callers need. The test hook moved to a separate
`@visibleForTesting subCollectionWithInjectedNotifications<U>(...)`
entry point with the same surface plus the required `notifications`
stream. Internal callers (e.g. `Query<T>.watchWithSub`'s child
sub-collection setup) route through a private
`_subCollectionInternal<U>(...)` that keeps the optional
notifications stream so injected test streams still propagate to
descendants — no public surface leak.

### W10. No transactional semantics

Writes are best-effort per-key; there's no way to say "save item X
and sub-item Y atomically". For most atSign use-cases this is
acceptable (each recipient gets a copy independently), but an app
that wants "both writes or neither" has to implement compensation
manually.

## 9. LLM / AI-coding-assistance perspective

Why this API specifically helps auto-written code land correctly the
first time:

- **CRUD verbs match the reader's prior.** An LLM reaches for
  `create`, `update`, `delete`, `get`, `getItems` — and gets what it
  expects. Raw-AtClient code forces the LLM to first learn the atKey
  idiom, then emit it.
- **Typed sub-streams give event dispatch without a catch-all
  `switch`.** `collection.updates` / `.deletes` / `.readReceipts` /
  `.subUpdates` / `.subDeletes` are each already typed to the
  concrete event, so listeners drop in without a missing-case
  hazard. `CEvent` itself is not `sealed` — the typed streams are
  the LLM-safe dispatch surface.
- **No regex composition.** Generated code is notoriously bad at
  regex escaping; AtCollection removes that hazard.
- **Named parameters describe intent at the call site.** `create(obj:
  Todo(...), sharedWith: {...})` reads the same way the intent would
  be described in English — good for both readers and generators.
- **Throw-by-default, typed exceptions.** Generated code doesn't
  remember to check boolean success codes; exceptions propagate by
  default. The "I want partial results" caller uses
  `.getItemsAsStream()` or catches the typed exception.

Where the API still requires care:

- **Four persistence verbs (`draft`, `create`, `update`, plus
  `tryX` equivalents hidden internally).** An LLM may reach for
  `save`, find `create`, then be surprised that updating an existing
  item needs `update` instead. The file-level mental-model comment
  helps; deeper: a single surface like `collection.persist(item)`
  that dispatches internally was considered and deliberately rejected
  for the sake of explicit semantics.
- **Factory registration via string tag.** An LLM occasionally
  mistypes the tag; we surface a clear `StateError` at draft time.

On balance: the API is exceptionally friendly to AI code generation
because it looks like every other good CRUD library the model has
seen, and the *unique* atSign concepts (sharing, ownership, receipts)
are exposed via well-named methods that don't require the generator
to carry any hidden invariants.

## 10. Recommended next steps

State as of 2026-04-29:

- **Closed**: W3 read-before-write merge (no longer needed — see W4);
  W4 persisted `readBy` merge (replaced by `__rr` sub-collection);
  W6 middleman-orphan handling for enveloped items (chain-walk in
  `_cleanupOrphansFromRoot`). Depth-agnostic events + deep cascade
  + parent-owner envelope + `(owner, id)` disambiguation throughout
  the filter / cache / event surface also landed in this window.
  Phase 1 of the W1 query-builder landed on 2026-04-23:
  `collection.query()` returning an immutable `Query<T>` with
  modifiers `.where` / `.orderBy` / `.limit` / `.skip` and
  terminals `.fetch` / `.watch` / `.count` / `.any` / `.first` /
  `.firstOrNull` / `.groupBy` / `.watchWithSub<U>`. Also landed:
  public `readReceiptsFor(item)` and `CItem.receipts` exposing the
  `__rr` sub-collection as a queryable handle. **W2 closed**
  2026-04-29 (folded into 3.13.0): `typeTag` is now required
  wherever a `fromJson` factory is supplied; the registry also
  rejects silently changing a registered type's tag or sharing a
  tag across types. **W1(b) multi-key `orderBy` closed**
  2026-04-29: `Query<T>.thenBy(keyFn, {descending})` appends
  tiebreakers; `_QuerySpec` carries an ordered list of sort keys
  and `_apply` runs a stable multi-key compare in registration
  order. `orderBy` retains replace semantics (LINQ / Drift / Isar
  idiom). **W9 closed** 2026-04-29: public `subCollection` no
  longer exposes the test-only `notifications:` parameter — a
  separate `@visibleForTesting subCollectionWithInjectedNotifications`
  surface carries it. **W8 closed** 2026-04-29: unknown envelope
  type tags now log a one-shot WARNING via the per-collection
  logger pointing at `registerFactory`, with per-tag dedup so the
  noise is bounded. **W3 residual closed** 2026-04-29:
  `_seenSelfIds` per-collection cache elides the existence-probe
  round-trip on `update` for ids this process has just written.
  **W6 residual closed** 2026-04-29: legacy descendants (no
  `parents` envelope) now chain-walk by id-presence at each
  composed-namespace level via a per-sweep `_aliveIdsAt` cache —
  depth-2+ middleman orphans are reclaimed. **W1 phase-2 closed**
  2026-04-29: (a) `PathField<V>` + `Predicate` AST + `Query.wherePath`
  for typed, introspectable predicates (closures still supported);
  (c) per-stream result-cache delta maintenance in `Query.watch`,
  with limit/skip queries falling back to refetch; (d)
  `Query.watchWithTree` recursive terminal with `SubSpec<U>` and
  `TreeNode<T>` for arbitrary-depth parent-children-grandchildren
  joins. **W5 closed** 2026-04-29: public `getKeys` removed
  entirely (zero production callers); implementation lives behind
  the private `_getKeysInternal`. `AtKey` no longer appears
  anywhere in the AtCollection public surface. **W7 closed**
  2026-04-29: `availableEvents` (lazy per-collection scheduler,
  flows through `watch`) and `expiringSoonEvents({leadTime})`
  (per-subscription scheduler) added, backed by a generic
  `_CItemTimerScheduler` that keeps a sorted firing list and a
  single shared `Timer` per scheduler.
- **Ranked for impact**, still open:

1. **Transactional semantics** (§W10). Cross-key "save A and B
   atomically or neither". Open by design — most atSign use-cases
   (each recipient gets a copy independently) don't need it;
   cross-recipient atomicity would also clash with the
   asynchronous distribution model. Listed here only for
   completeness; no current consumer asks for it.

## Verification

- `dart analyze lib test example/bin` → clean.
- `dart test test/at_collections_test.dart test/at_collections_sub_test.dart test/at_collections_query_test.dart test/at_collections_query_sub_test.dart`
  → 110 passing as of 2026-04-23, post the Query<T> phase-1 work
  including the `watchWithSub` terminal and public
  `readReceiptsFor` surface. **2026-04-29 sweep adds 31 tests:**
  5 for W2 (required typeTag + collision rules), 5 for W1(b)
  thenBy (chains, descending, no-prior-orderBy guard), 1 for W8
  (unknown type tag rehydrate fallback), 2 for W3 residual
  (probe elision + cache invalidation on delete), 1 for W6
  residual (depth-2 legacy middleman orphan sweep), 3 for W1(d)
  watchWithTree (initial snapshot, grandchild arrival, cascade-
  cancel), 10 for W1(a) wherePath (eq/lt/and/or/not/AST flatten/
  introspection), 4 for W1(c) delta maintenance (single-item read
  on update, zero-read delete, predicate-fail removal,
  limit-fallback behaviour), 8 for W7 (3 availableEvents and 5
  expiringSoonEvents — fires-on-time, no-availableAt skip,
  watch-master integration, leadTime semantics, late-subscriber
  catch-up, cancellation tear-down, delete-unregisters,
  negative-leadTime guard). **147 total passing** (the W5
  closure also removed two now-redundant regex-shape tests for
  `getKeys` — the regex composition is exercised continuously
  through every read/write/cleanup test, so nothing was lost).
  Full `dart test --concurrency=1` is clean (543 across the
  at_client suite).
- `flutter analyze` on the Flutter todos example
  (`packages/at_client_flutter/examples/todos`) → clean. That app is
  the idiomatic Flutter reference for AtCollection — CLI developers
  can also consult `packages/at_client/example/bin/collections_*.dart`.

The API covered in this assessment is the shape landed on the
`gkc-enhance-api` branch of `at_client_sdk` as of 2026-04-23, plus
the 2026-04-29 snagging round on `gkc-at-collection-snagging`
that closed W2, W1 phase 2 (a/b/c/d), W3-residual, W5, W6-residual,
W7, W8, and W9. The implementation lives in
`packages/at_client/lib/src/collections/collections.dart`.
