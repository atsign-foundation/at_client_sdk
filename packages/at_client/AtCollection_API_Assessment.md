# Assessment v3: `AtCollection<T>` in `at_client`

A from-scratch assessment of the `AtCollection<T>` API in
`packages/at_client/lib/src/collections/collections.dart` as of
2026-04-29 (UTC); originally written end-of-day Thu Apr 23, with a
2026-04-29 update for W2 closure (required `typeTag` in 3.14.0).

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

Phase 1 of a composable query-builder (`collection.query()` →
`Query<T>` with `.where` / `.orderBy` / `.limit` / `.skip` and
terminals `.fetch` / `.watch` / `.count` / `.any` / `.first` /
`.firstOrNull` / `.groupBy` / `.watchWithSub`) landed on 2026-04-23
alongside the rest of the v3 work. The
`getItemsAsStream().where(...)` stream-transformer path remains
supported as an escape hatch for ad-hoc pipelines outside the
builder's vocabulary. What's still outstanding is phase-2 polish:
typed field-accessor values (so the spec can be introspected for
secondary-index push-down when the local store eventually gains
JSON indexes), multi-key `orderBy`, deeper-than-one-level
sub-collection joining (`watchWithTree`), and incremental delta
maintenance in `.watch()` — see §W1. None of that is
architectural.

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
  `collection.query()`. Modifiers (`.where`, `.orderBy`, `.limit`,
  `.skip`) compose; terminals (`.fetch`, `.watch`, `.count`, `.any`,
  `.first`, `.firstOrNull`, `.groupBy`, `.watchWithSub`) execute
  against the synced local store.
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
  (`.where` / `.orderBy` / `.limit` / `.skip` / terminals
  `.fetch` / `.watch` / `.count` / `.any` / `.first` / `.firstOrNull`
  / `.groupBy` / `.watchWithSub`). `getItemsAsStream()` remains as
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
| Regex composition for key scans             | Caller writes regexes by hand                   | Hidden — `getKeys` / `getItems` compose internally                    |
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

| Category                 | Methods / fields exposed                                                                                                                                                                                                                                                                                                         |
|--------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Construction             | `AtCollection(atClient, namespace, defaultExpiration, {fromJson, typeTag})`, `AtCollection.withInjectedNotifications(...)` (testing)                                                                                                                                                                                             |
| Identity                 | `atSign`, `namespace`, `defaultExpiration`, `isSubCollection`                                                                                                                                                                                                                                                                    |
| Factory                  | `registerFactory<U>(fromJson, {required typeTag})`                                                                                                                                                                                                                                                                               |
| Drafting                 | `draft({obj, id?, sharedWith?, expiresAt?, availableAt?})` (no I/O)                                                                                                                                                                                                                                                              |
| Create / Update / Delete | `create({obj, id?, sharedWith?, expiresAt?, availableAt?})` (throws on collision), `update(item, {unshareWithOthers})` (throws if missing), `delete(item, {cascade})`                                                                                                                                                            |
| Read one                 | `get(id, owner)` (throws if missing), `getOrNull(id, owner)` (null if missing)                                                                                                                                                                                                                                                   |
| Read many                | `getItems({id?, owner?})` (List, throws on decode error), `getItemsAsStream({id?, owner?})` (Stream, errors yielded in-band), `getKeys({id?, owner?})` (raw AtKeys)                                                                                                                                                              |
| Query builder            | `query()` → `Query<T>`; modifiers `.where(p)`, `.orderBy(keyFn, {descending})`, `.limit(n)`, `.skip(n)`; terminals `.fetch()`, `.watch()`, `.count()`, `.any([p])`, `.first()`, `.firstOrNull()`, `.groupBy<K>(keyFn)`, `.watchWithSub<U>(subName, subDefaultExpiration, {subFromJson, subTypeTag})` (live parent+children join) |
| Read receipts            | On `CItem`: `markReadByMe()`, `wasMarkedReadByMe()`, `readBy` (Future), `readBySnapshot` (sync), `receipts` (the `__rr` sub-collection). On `AtCollection`: `markReadByMe(item)` / `wasMarkedReadByMe(item)` shims, `readReceiptsFor(item)` → queryable receipts sub-collection.                                                 |
| Sub-collections          | `subCollection<U>({parent, subName, defaultExpiration, fromJson?, typeTag?})` (plus `notifications:` test hook — see §W9), `cleanupOrphans()` (works on root and sub)                                                                                                                                                            |
| Events                   | `watch()` → Stream<CEvent>; typed getters `updates` / `deletes` / `readReceipts` / `subUpdates` / `subDeletes`                                                                                                                                                                                                                   |
| Exceptions               | `CollectionOpException` (write failures), `CollectionGetException` (read/decode failures), `StateError` (create-collides / update-missing / cascade-needed), `ArgumentError` (invalid input), `AtKeyNotFoundException` (get of absent)                                                                                           |

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

### (a) Typed field-accessor values in predicates

**What's missing.** `.where((t) => !t.obj.done)` is an opaque Dart
closure. The query spec (`_QuerySpec`) stores it as a
`bool Function(CItem<T>)` — something the library can *execute* but
can't *inspect*. It has no idea the predicate tests `obj.done`; all
it sees is "a function".

**Why it matters.** Two consequences:

- **No secondary-index push-down.** When the local store migrates
  from Hive to SQLite and grows JSON-field indexes, the library
  would in principle be able to translate `$Todo.done == false`
  into a SQL `WHERE obj_done = 0` and use the index rather than
  scanning. It can't do that against a closure — a closure could
  do anything.
- **No predicate introspection for devtools, caching, or
  serialisation.** "What queries are currently active?" "Can I
  reuse this predicate's result set for a derived query?" "Show me
  the query as a string in the log." All blocked by opacity.

**Shape of a phase-2 fix.** Each domain type exposes a
path-accessor object:

```dart
class $Todo {
  static const done    = PathField<bool>(['obj', 'done']);
  static const dueDate = PathField<DateTime?>(['obj', 'dueDate']);
  static const owner   = PathField<Atsign>(['owner']);
}

todos.query().where($Todo.done.eq(false).and($Todo.dueDate.lt(today)));
```

`.eq` / `.lt` / `.and` return typed AST nodes. The resulting
predicate is a data tree the library can walk:

```
AndNode(
  EqNode(path: ['obj', 'done'], value: false),
  LtNode(path: ['obj', 'dueDate'], value: today),
)
```

Now `_apply` can either evaluate the tree in-memory (same cost as
today) or delegate to an indexed backend.

**Tradeoff / dependency.** Either the user writes `$Todo` by hand
(boilerplate) or we adopt a build-step (`build_runner`, Drift-style)
to generate it. Closures stay supported alongside for ad-hoc
predicates — the field-accessor form is for predicates the library
is expected to optimise. **Only worth landing once we have an
indexed local store to push down to**; otherwise it's pure
API-surface work with no performance payoff.

### (b) Multi-key `orderBy`

**What's missing.** Calling `.orderBy(...)` twice replaces the first
one; it doesn't append. Single sort key only.

**Why it matters.** The common case is tie-breaking: "sort by due
date ascending, then by title". Today the caller writes a composite
key:

```dart
.orderBy((t) => (t.obj.dueDate ?? maxDate, t.obj.title))
```

Dart records are `Comparable` when all their fields are, so it
works — but it's awkward, and you can't independently reverse one
key's direction (the whole record reverses together).

**Shape of a phase-2 fix.** Append rather than replace:

```dart
q.orderBy((t) => t.obj.dueDate)
 .thenBy((t) => t.obj.title, descending: true)
 .thenBy((t) => t.createdAt);
```

`_QuerySpec` holds a `List<_OrderBy<T>>` instead of a single
`_OrderBy<T>?`. The `_apply` sort runs a stable multi-key
comparison. Five to ten lines of SDK change plus a couple of tests.

**Tradeoff / dependency.** None, really. This is the smallest of
the four — the only reason it's phase 2 is that nobody has asked
for it yet and the composite-key workaround exists.

### (c) Incremental delta maintenance in `watch()`

**What's missing.** Today, when the collection emits a
`CItemUpdated` / `CItemDeleted` event, `Query.watch()` reacts by
calling `fetch()` — which re-runs the *full scan*: re-reads local
keys, re-decodes every envelope, re-applies every predicate,
re-sorts, re-limits. Every event. Every time.

**Why it matters.** At demo scales (tens to a few thousand items),
local scans are in the low-milliseconds range — invisible. Above
~10K items with indexes gone, it starts to matter; above ~100K it's
expensive enough to think about.

The event payload (`CItemUpdated` carries `owner` + `id`) already
tells us *which* item changed. A smart implementation could:

- **Fetch only the affected item**, decode it once
- **Re-evaluate predicates against just that item** — keep / drop
  / reposition in the current sorted result set
- **Emit a new snapshot** without re-scanning everything else

**Shape of a phase-2 fix.** Cache the current result set as a
sorted list inside `Query.watch()`'s state. On each event:

```
onUpdate(owner, id):
  current = cache.findByOwnerId(owner, id)
  fresh   = collection.getOne(owner, id)          // one local read
  passes  = spec.predicates.every((p) => p(fresh))
  if current != null && !passes:
    cache.remove(current)                         // left the result set
  else if current == null && passes:
    cache.insertSorted(fresh)                     // entered the result set
  else if current != null && passes:
    cache.replaceInPlace(fresh, maybeReSort: true)
  emit(cache.asList())

onDelete(owner, id):
  cache.removeByOwnerId(owner, id)
  emit(cache.asList())
```

**Hard bits.**

- **Sort-stable insert** when `orderBy` is set — need a small
  binary-search helper.
- **limit/skip windows.** If a visible item falls out of the
  window, the *next* item needs to come back in — which means the
  cache has to keep one past the window, or fall back to a fetch
  for the next page. The simple delta model breaks down a bit
  when limit is in play.
- **Race with concurrent events.** If two events land during an
  in-flight single-item re-decode, their observed state can
  interleave. Serialise via a small per-query queue.
- **Cache correctness when the spec changes.** A new `.where()`
  composed onto the query creates a new `Query<T>` value — the
  cache belongs to the specific `watch()` call, not across
  modifier chains. That's already fine given today's one-
  controller-per-watch pattern.

**Tradeoff / dependency.** Pairs cleanly with (a): once the
library can see that a predicate tests `done` and the change event
shows `done` didn't change, it can skip predicate re-evaluation
entirely. Without that, delta maintenance is still beneficial but
smaller — maybe a 10× win rather than 100×. **Only worth landing
when a real workload (hundreds of events/second against a large
collection) is measured.** "Correct before fast" is the right
posture until that profile arrives.

### (d) Deeper sub-collection queries

**What's missing.** `watchWithSub<U>` joins a parent query with one
named sub-collection level: `posts → comments`, or `todos → notes`.
Two levels (`posts → comments → replies`) requires the caller to
orchestrate the second `watchWithSub` manually per-parent and
combineLatest the results — exactly the manual dance
`watchWithSub` was introduced to eliminate.

**Why it matters.** Any hierarchical model bumps into it. Blog
comments with threaded replies. Kanban boards with cards with
checklists. Issue tracker with comments with reactions. The todos
app caps at one level, so the demo doesn't expose the gap, but a
real app will hit it immediately.

**Shape of a phase-2 fix.** A recursive / tree-shaped terminal:

```dart
posts.query().watchWithTree([
  SubSpec<Comment>(
    subName: 'comments',
    subDefaultExpiration: const Duration(days: 30),
    subFromJson: Comment.fromJson,
    children: [
      SubSpec<Reply>(
        subName: 'replies',
        subDefaultExpiration: const Duration(days: 30),
        subFromJson: Reply.fromJson,
      ),
    ],
  ),
]);
```

Snapshot becomes a tree node rather than a flat `(parent, children)`
record; for rendering, the widget tree maps directly onto it.

Internally: the terminal orchestrates layered `watchWithSub`
subscriptions, combineLatest-style, and emits a fresh tree on any
change at any level. When a level-1 parent leaves the result set,
cascade-cancel all of its level-2 and level-3 subscriptions; when a
level-2 child leaves, cancel its level-3.

**Tradeoff / dependency.** Independently useful — doesn't depend on
(a) or (c). The SDK cost is the stream-orchestration plumbing
(~150 LOC + tests, roughly double the size of phase-1 `watchWithSub`).
Whether to land it depends on whether a concrete consumer app
needs it; our reference apps don't (the todos app is deliberately
one-level). First consumer to ask for two-level joining is the
trigger.

### Summary (one sentence each)

1. **(a) Typed field accessors** — turn closures into an inspectable
   AST. Worthwhile only when we have an indexed local store to push
   down to.
2. **(b) Multi-key `orderBy`** — append rather than replace on
   repeated calls. Any time; small.
3. **(c) Delta maintenance in `.watch()`** — single-item cache
   maintenance instead of full re-scan on each event. Worthwhile
   once a real workload shows scan cost matters.
4. **(d) `watchWithTree`** — recursive terminal for multi-level
   parent/child joins. Worthwhile as soon as a real consumer
   models more than one level.

None are blockers for 3.13; all four are the kind of polish that
lands when the first caller bangs on them hard.

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

### W3. ~~`put`-on-update is still reads-before-writes~~ (mostly closed)

`update(item)` still does one round-trip for the existence probe, but
the readBy-merge read was removed when read receipts moved to the
reserved `__rr` sub-collection (see W4). For bulk edits, the cost is
now one pre-write `get` per item (the existence check) plus the put —
a measurable improvement over the previous two-read pattern. The
existence probe itself could be elided via a small "I just wrote this"
cache; parked until there's a concrete bulk-edit workload to measure
against.

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

### W5. `getKeys(...)` leaks `AtKey` into the public API

Only used by the example apps for a debug command. Could be marked
`@visibleForTesting` / `@protected`. Small API hygiene.

### W6. ~~`cleanupOrphans` only catches root-ancestor orphans~~ (mostly closed)

`_cleanupOrphansFromRoot` now chain-walks every ancestor in the
descendant's `parents` envelope — if any level between root and
direct parent is locally absent, the descendant is orphaned and
swept. Middleman-orphan case is handled for items written post-
envelope (Commit 4 of the 2026-04-21 tidy-up). **Residual work**:
legacy items (no `parents` field) still fall back to root-ancestor-
only checking — intentional, since we can't recover owner info from
the key alone. If a migration sweep is ever desired, that's where to
add it.

### W7. No timer-driven events

`CItemAvailable` (when `availableAt` passes) and `CItemExpiringSoon`
would require an internal timer; useful for reminder-style apps but
non-trivial to implement efficiently. Consider adding later with a
config knob so apps opt into the cost.

### W8. Cross-atSign interop fragility via the `type` string

Interop between two apps over the same collection relies on both
sides agreeing on the `type` string of every record. There's no
guard against a sender calling `registerFactory<Todo>(...)` while a
receiver registers `Task.fromJson` under tag `'Task'`. Apps should
document a "wire-format" contract, but the library could surface a
warning when rehydration falls back to `n/a` because no matching
factory exists.

### W9. `notifications:` test hook remains on `subCollection`

We added `AtCollection.withInjectedNotifications` for constructor-
level testing. The `subCollection(...)` method still accepts a
`notifications:` param for the same purpose, which means production
callers see it too. Low-priority polish — could be hidden behind a
second test-only overload of `subCollection`.

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
- **`getKeys`, `AtKey`** — if an LLM wanders into these, raw
  AtClient concepts leak through.

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
  tag across types.
- **Ranked for impact**, still open:

1. **Query/filter phase 2** (residual of §W1). Typed field
   accessors (so the spec can be introspected for index push-down,
   unlocking the SQLite-indexed execution path when local storage
   gets there); multi-key `orderBy`; deeper sub-collection joining
   than one level; incremental delta maintenance in `.watch()`
   (today any event triggers a full refetch — correct, but cheaper
   options exist once profiling demands).
2. **`CItemAvailable` / `CItemExpiringSoon` events** (§W7). Unlocks
   reminder / alarm UIs without app-level timers.
3. **Existence-probe elision** (residual of §W3). Tiny cache of
   "keys we just wrote" so subsequent `update` can skip the
   existence probe on the same process's own writes.
4. **Recursive orphan sweep for deep legacy data** (residual of
   §W6). Only matters if anyone ends up with middleman-orphaned
   legacy sub-items (no `parents` envelope); chain-walk handles
   the enveloped case today.
5. **Cross-atSign `type` contract guard** (§W8). Warn when
   rehydration falls back to `n/a` because no factory matches the
   envelope's `type` tag — catches registry drift between peers.
6. **Hide the `notifications:` test hook from public
   `subCollection` surface** (§W9). Pure polish.

## Verification

- `dart analyze lib test example/bin` → clean.
- `dart test test/at_collections_test.dart test/at_collections_sub_test.dart test/at_collections_query_test.dart test/at_collections_query_sub_test.dart`
  → 49 + 18 + 38 + 5 = 110 passing as of 2026-04-23, post the
  Query<T> phase-1 work including the `watchWithSub` terminal and
  public `readReceiptsFor` surface. Plus 5 new W2 validation tests
  added 2026-04-29: 115 total passing in the AtCollection-focused
  suite; full `dart test --concurrency=1` is clean (511 passing).
- `flutter analyze` on the Flutter todos example
  (`packages/at_client_flutter/examples/todos`) → clean. That app is
  the idiomatic Flutter reference for AtCollection — CLI developers
  can also consult `packages/at_client/example/bin/collections_*.dart`.

The API covered in this assessment is the shape landed on the
`gkc-enhance-api` branch of `at_client_sdk` as of 2026-04-23; the
implementation lives in
`packages/at_client/lib/src/collections/collections.dart`. The
Query<T> builder (phase 1) was added in commits dated 2026-04-23.
