# Events & Streams API Reference

## Event Source Overview

`AtCollection<T>` surfaces all state changes as typed events on
broadcast-style streams. There are two sources of events (controlled by
`EventSource` at collection creation):

| `EventSource`        | What fires events                                                                                                                            |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `EventSource.data`   | All local keystore mutations via `AtClient.dataEvents` — locally-driven writes AND TTL expiry deletions AND sync-applied cross-atSign writes |
| `EventSource.notifs` | Cross-atSign writes received via `NotificationService` — locally-driven writes are NOT visible                                               |
| `EventSource.both`   | Both sources; the same cross-atSign write can fire **twice** (no dedup); default                                                             |

---

## CEvent Hierarchy

All events extend `CEvent` (abstract). All event classes are `final`.

```text
CEvent
├── CItemUpdated         — item created or updated (L0)
├── CItemDeleted         — item deleted (L0, includes TTL expiry)
├── CItemAvailable       — item's availableAt timestamp has passed
├── CItemExpiringSoon    — item will expire within the lead time
├── CReadReceipt         — someone read my item
├── CSubItemUpdated      — any sub-item at any depth changed
└── CSubItemDeleted      — any sub-item at any depth was deleted
```

---

## Event Classes: Fields

### `CItemUpdated`

```dart
final class CItemUpdated extends CEvent {
  final Atsign owner;   // atSign that owns the item
  final String id;      // item id
}
```

### `CItemDeleted`

```dart
final class CItemDeleted extends CEvent {
  final Atsign owner;
  final String id;
  final bool wasExpired;  // true if deleted by TTL expiry, false if explicit delete
}
```

### `CItemAvailable`

```dart
final class CItemAvailable extends CEvent {
  final Atsign owner;
  final String id;
  final DateTime availableAt;   // the scheduled timestamp that just passed
}
```

Fires when an item's `availableAt` timestamp passes. Subscribe to
`availableEvents` then call `collection.getOrNull(event.id, event.owner)` to
fetch the now-visible item.

### `CItemExpiringSoon`

```dart
final class CItemExpiringSoon extends CEvent {
  final Atsign owner;
  final String id;
  final DateTime expiresAt;
  final Duration leadTime;  // the lead time configured on expiringSoonEvents(leadTime:)
}
```

### `CReadReceipt`

```dart
final class CReadReceipt extends CEvent {
  final Atsign owner;   // owner of the item that was read
  final String id;      // id of the item that was read
  final Atsign from;    // who did the reading
  final DateTime readAt;
}
```

### `CSubItemUpdated`

```dart
final class CSubItemUpdated extends CEvent {
  final Atsign owner;               // owner of the leaf sub-item
  final String id;                  // id of the leaf sub-item
  final List<CAncestor> ancestry;   // root-to-direct-parent chain
  String get subName => ancestry.last.subName;  // convenience accessor
}

// CAncestor carries an ancestor's id, the sub-collection name below it, and its owner
final class CAncestor {
  final String id;        // ancestor item id
  final String subName;   // sub-collection name one level below this ancestor
  final Atsign? owner;    // owner of the ancestor; null on CSubItemDeleted events
}
```

**Ancestry ordering:** `ancestry` is a **root-to-direct-parent** chain.
`ancestry[0]` is the **root ancestor**; `ancestry.last` is the
**direct parent** of the leaf.

Example: for a reply on a comment on a post:

- `ancestry[0]` = the post (root)
- `ancestry[1]` = the comment (direct parent of the reply)
- `event.id` = the reply id

To fetch the leaf, use
`collection.getDescendant(ancestry: event.ancestry, id: event.id, ...)`.

### `CSubItemDeleted`

```dart
final class CSubItemDeleted extends CEvent {
  final Atsign owner;                // the leaf sub-item's owner (non-nullable)
  final String id;                   // id of the leaf sub-item
  final List<CAncestor> ancestry;    // same as CSubItemUpdated
}
```

> **Pitfall:** `CAncestor.owner` inside `ancestry` is **always `null`** on
> `CSubItemDeleted` events — the sub-item is gone by the time the notification
> arrives, so there is no envelope to recover parent owners from. This means
> `getDescendant()` cannot be called on a delete event because it requires
> non-null ancestor owners.
>
> **Fix:** Cache the last `CSubItemUpdated` for each `(id, subName)` pair so
> you can reuse the populated `ancestry` (with non-null owners) when the
> corresponding delete fires.

---

## Streams on AtCollection\<T>

### `Stream<CEvent> watch()`

All events. Useful for debugging or aggregate reacting.

### Typed streams (prefer these in production code)

| Getter / Method                 | Stream type                 | Fires when                                   |
| ------------------------------- | --------------------------- | -------------------------------------------- |
| `updates`                       | `Stream<CItemUpdated>`      | Any L0 item created or updated               |
| `deletes`                       | `Stream<CItemDeleted>`      | Any L0 item deleted (TTL or explicit)        |
| `readReceipts`                  | `Stream<CReadReceipt>`      | A recipient marks my item as read            |
| `subUpdates`                    | `Stream<CSubItemUpdated>`   | Any descendant item created or updated       |
| `subDeletes`                    | `Stream<CSubItemDeleted>`   | Any descendant item deleted                  |
| `availableEvents`               | `Stream<CItemAvailable>`    | Lazy-started scheduler; `availableAt` passed |
| `expiringSoonEvents(leadTime:)` | `Stream<CItemExpiringSoon>` | Item expiring within `leadTime`              |

**Getters vs methods:**  
Parameterless event surfaces are **getters** (`updates`, `deletes`, etc.).  
Parameterised surfaces are **methods** (`watch()` — filter by event type;
`expiringSoonEvents(leadTime:)` — per-call lead time).

### `availableEvents` scheduler

Lazy-starts a single per-collection scheduler on first access. Runs for the
lifetime of the collection. Enrolls existing items with future `availableAt`
at startup. Re-enrolls items on every `CItemUpdated`.

### `expiringSoonEvents({required Duration leadTime})`

Starts an **independent** scheduler per call — each caller can have a
different `leadTime`.

---

## Flutter Subscribe/Dispose Pattern

```dart
late StreamSubscription<CItemUpdated> _sub;

@override
void initState() {
  super.initState();
  _sub = collection.updates.listen((_) => setState(() {}));
}

@override
void dispose() {
  _sub.cancel();
  super.dispose();
}
```

For `watch()` in `StreamBuilder`, hold the stream in `State` — never create it
in `build()` (see [03-query-api.md](03-query-api.md)):

```dart
late final _todos = todos.query().where((t) => !t.obj.done).watch();
// ...
StreamBuilder<List<CItem<Todo>>>(stream: _todos, builder: (ctx, snap) { ... })
```

---

## EventSource Decision Guide

```text
Does your app write items locally (not just receive from others)?
├─ YES → Does it run SyncService?
│  ├─ YES → EventSource.data  (tightest write→event; no duplicate events)
│  └─ NO  → EventSource.both  (locally-driven writes need data path)
└─ NO (receive-only) → EventSource.notifs  (saves one subscription)

Do you need tightest write→event semantics after await create()?
├─ YES → EventSource.data or EventSource.both
└─ NO  → any

Are duplicate events acceptable?
├─ YES → EventSource.both (default; simplest)
└─ NO  → EventSource.data or EventSource.notifs (pick based on above)
```

---

## Reading After a CSubItemUpdated

When you receive a `CSubItemUpdated` event, use `getDescendant` to fetch
the leaf:

```dart
collection.subUpdates.listen((event) async {
  final leaf = await collection.getDescendant<Reply>(
    ancestry: event.ancestry,
    id: event.id,
    owner: event.owner,
    leafExpiration: const Duration(days: 7),
    leafFromJson: Reply.fromJson,
    leafTypeTag: 'Reply',
  );
  if (leaf == null) return;  // ancestor expired in the meantime
  handleReply(leaf);
});
```

Do NOT construct a flat collection at the composed namespace to read sub-items —
reads will return null even though notifications match.

> **Note on ancestry ordering:** `ancestry` is root-first. `ancestry[0]` is the
> outermost ancestor; `ancestry.last` is the direct parent of the leaf. To
> filter events to a specific parent, check
> `event.ancestry.last.id == myParentItem.id`.
