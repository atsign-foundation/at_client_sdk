<!-- verified: at_client ^3.12.0 — update on next minor release -->

# AtCollection\<T> Complete API Reference

## Obtaining an Instance

**Always use `AtClient.collection(...)` — never instantiate directly.**

```dart
final collection = await atClient.collection<T>(
  namespace,                       // String: must contain '.', e.g. 'todos.my_app'
  defaultExpiration,               // Duration: default TTL for new items
  fromJson: T.fromJson,            // T Function(Map<String,dynamic>)? — auto-registers factory
  typeTag: 'T',                    // String? — required when fromJson is supplied
  cleanupOrphansOnCreation: false, // bool: run orphan sweep at startup (default: false)
  eventSource: EventSource.both,   // EventSource: default EventSource.both
);
```

The call is **cached per `(namespace, eventSource)` pair** — subsequent calls
with the same namespace AND the same `eventSource` return the same
`AtCollection<T>` instance. Different `eventSource` values for the same
namespace produce separate instances.

---

## Constructor Validation Rules

- `namespace` must contain `.` → throws
  `ArgumentError('namespace must be fully qualified')`
- `fromJson` and `typeTag` must be supplied together → throws `ArgumentError`
  if one is given without the other
- `typeTag` must be non-empty / non-whitespace → throws `ArgumentError`

---

## Factory Registration

### `static void registerFactory<U>(U Function(Map<String,dynamic>) fromJson, {required String typeTag})`

Registers a deserialization factory. **Process-global** — shared across all
`AtCollection` instances in the Dart isolate.

```dart
AtCollection.registerFactory<Dog>(Dog.fromJson, typeTag: 'Dog');
AtCollection.registerFactory<Cat>(Cat.fromJson, typeTag: 'Cat');
// Then create a polymorphic collection:
final pets = await atClient.collection<Pet>('pets.my_app', ttl);
```

**Re-registration rules:**

- Same `(Type, typeTag)` → idempotent, last write wins
- Same `Type`, different tag → throws `StateError` (wire-format contract)
- Same tag, different `Type` → throws `StateError` (tag uniqueness)

---

## Basic Getters

| Getter              | Type       | Description                                  |
| ------------------- | ---------- | -------------------------------------------- |
| `atSign`            | `Atsign`   | The atSign this `atClient` is acting as      |
| `self`              | `Atsign`   | Alias for `atSign` — use for ownership tests |
| `namespace`         | `String`   | The fully-qualified namespace                |
| `defaultExpiration` | `Duration` | Default TTL for new items                    |
| `isSubCollection`   | `bool`     | True if created via `subCollection(parent:)` |

---

## Drafting (No I/O)

### `CItem<T> draft({required T obj, String? id, Set<Atsign>? sharedWith, DateTime? expiresAt, DateTime? availableAt})`

Builds an in-memory item without persisting. Use `create` to persist.

- `id` — auto-generates 8-character `[a-z0-9]` id if omitted; **no uniqueness
  check**
- `expiresAt` — defaults to `now + defaultExpiration`
- `availableAt` — `null` = visible immediately

---

## CRUD Methods

### `Future<CItem<T>> create({required T obj, String? id, Set<Atsign>? sharedWith, DateTime? expiresAt, DateTime? availableAt})`

Creates and persists a new item. On `EventSource.data` / `EventSource.both`,
awaits local emission so `watch()` listeners see the update before
`await create(...)` returns.

- Throws `StateError` if `id` is supplied and already exists on the atServer
- If `id` omitted: retries on collision (astronomically unlikely); throws
  `StateError` after 10 attempts
- Throws `CollectionOpException` on any key-level write failure

### `Future<CItem<T>> upsert({required String id, required T obj, Set<Atsign>? sharedWith, DateTime? expiresAt, DateTime? availableAt})`

Idempotent write. Creates if not exists, rewrites if it does.
Use for re-runnable publishers that may restart within the TTL window.

### `Future<void> update(CItem<T> item, {bool unshareWithOthers = true})`

Persists an existing item. With `unshareWithOthers: true` (default), deletes
recipient copies for atSigns removed from `item.sharedWith`.

- Throws `ArgumentError` if `item.owner != self`
- Throws `StateError` if self-key does not exist

### `Future<void> updateSharedWith(CItem<T> item, Set<Atsign> sharedWith, {bool unshareWithOthers = true})`

Changes the recipient set **without rewriting the self-key**. Delta-only: adds
new recipients, removes dropped ones (when `unshareWithOthers: true`), leaves
unchanged recipients untouched.

Does NOT emit a local `CItemUpdated` on this collection (value unchanged).

- Throws `ArgumentError` if `item.owner != self`
- Throws `StateError` if self-key does not exist
- Throws `ArgumentError` if adding recipients to an expired item

### `Future<void> delete(CItem<T> item, {bool cascade = false})`

Deletes the item and all recipient copies.

- Throws `ArgumentError` if `item.owner != self`
- Throws `StateError` if `cascade: false` and self-owned descendants exist
- With `cascade: true`: deletes self-owned descendants at any depth first

---

## Read Methods

### `Future<CItem<T>> get(String id, Atsign owner)`

Throws `AtKeyNotFoundException` if not found.

### `Future<CItem<T>?> getOrNull(String id, Atsign owner)`

Returns `null` if not found. Same error-propagation semantics for decode
failures.

### `Future<List<CItem<T>>> getItems({String? id, Atsign? owner})`

Returns all matching items as a list. A per-key decode failure aborts the list.

### `Stream<CItem<T>> getItemsAsStream({String? id, Atsign? owner})`

Yields each item as it is fetched. **Per-key decode failures are yielded as
stream errors** (not swallowed). Chain `.handleError(...)` to restore
silent-skip behaviour.

### `Future<bool> exists(String id, Atsign owner)`

Cheap presence check. Prefers the `_seenSelfIds` cache for self-owned items.

---

## Sub-collection Construction

### `AtCollection<U> subCollection<U>({required CItem<T> parent, required String subName, required Duration defaultExpiration, U Function(Map<String,dynamic>)? fromJson, String? typeTag})`

Opens a typed sub-collection scoped to `parent`. Sub-collections inherit the
parent's `eventSource`.

**Constraints:**

- `subName` must NOT contain `.`
- `parent.id` must NOT contain `.`
- `ArgumentError` thrown if composed namespace would exceed 255-char atServer
  key limit (max ~11 levels)

### `Future<CItem<U>?> getDescendant<U>({required List<CAncestor> ancestry, required String id, required Atsign owner, required Duration leafExpiration, Duration? intermediateExpiration, U Function(Map<String,dynamic>)? leafFromJson, String? leafTypeTag})`

Walks the parent chain from `ancestry` (from a `CSubItemUpdated` event) and
fetches the leaf item. Returns `null` if any ancestor is unavailable/expired.

- `leafFromJson` and `leafTypeTag` are **optional** — omit them if the leaf
  type's factory was already registered via
  `AtCollection.registerFactory<U>(...)`.
- `intermediateExpiration` — optional TTL for intermediate ancestors fetched
  during the walk (defaults to `leafExpiration` if omitted).
- Throws `ArgumentError` if any `CAncestor.owner` in `ancestry` is `null` (as
  happens on `CSubItemDeleted` events — cache the last `CSubItemUpdated`
  ancestry instead).

### `Future<List<OpResult>> cleanupOrphans()`

Sweeps the local keystore and removes sub-collection items whose parent chain
is broken (parent has been deleted or expired). Returns a list of `OpResult`
entries — inspect them to see which keys were removed and whether any
deletions failed. Runs asynchronously in the background when
`cleanupOrphansOnCreation: true` is passed to `atClient.collection()`.

---

## Query Builder Entry Point

### `Query<T> query()`

Returns an immutable `Query<T>` builder. See [03-query-api.md](03-query-api.md).

---

## Event Streams

| Stream                          | Type                        | Description                           |
| ------------------------------- | --------------------------- | ------------------------------------- |
| `watch()`                       | `Stream<CEvent>`            | All events below                      |
| `updates`                       | `Stream<CItemUpdated>`      | Item created or updated               |
| `deletes`                       | `Stream<CItemDeleted>`      | Item deleted (has `wasExpired` flag)  |
| `readReceipts`                  | `Stream<CReadReceipt>`      | Someone read your item                |
| `subUpdates`                    | `Stream<CSubItemUpdated>`   | Any sub-item changed (has `ancestry`) |
| `subDeletes`                    | `Stream<CSubItemDeleted>`   | Any sub-item deleted (has `ancestry`) |
| `availableEvents`               | `Stream<CItemAvailable>`    | Item's `availableAt` has passed       |
| `expiringSoonEvents(leadTime:)` | `Stream<CItemExpiringSoon>` | Item expiring within `leadTime`       |

See [04-events-api.md](04-events-api.md) for full event class fields.

---

## Namespace Budget

The SDK enforces a **128-character limit** on the composed namespace string
(the constant `maxComposedNsLength = 128`). `subCollection()` throws
`ArgumentError` before any I/O if the composed namespace would exceed
this limit.

With a 15-char application namespace and minimally-named collections, the
practical depth ceiling is **11 levels (root + 10 nested sub-collections)**.

---

## Key Naming (Internal, for debugging)

| Item type            | Key format                                         |
| -------------------- | -------------------------------------------------- |
| Self copy            | `<id>.<namespace>@<atSign>`                        |
| Recipient copy       | `<recipient>:<id>.<namespace>@<atSign>`            |
| Cached incoming copy | `cached:<id>.<namespace>@<sender>`                 |
| Read receipt         | `<receiptId>.__rr.<parentId>.<namespace>@<reader>` |

---

## EventSource Reference

```dart
enum EventSource {
  data,   // AtClient.dataEvents: all local keystore mutations + TTL expiries
  notifs, // NotificationService: cross-atSign writes via notification pipeline only
  both,   // both sources; same change may surface twice (no dedup)
}
```

**Which to pick:**

- `EventSource.data` — requires SyncService running; tightest write→event
  guarantee; locally-driven writes visible immediately
- `EventSource.notifs` — if app is primarily a notification receiver;
  locally-driven writes invisible to watch streams
- `EventSource.both` — default; works without SyncService; watch streams see
  everything but may fire twice for cross-atSign writes
