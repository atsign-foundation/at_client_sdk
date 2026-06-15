<!-- verified: at_client ^3.12.0 — update on next minor release -->

# Common Pitfalls

## 1. Using `create()` in a Re-runnable Publisher

**Problem:** A periodic publisher (cron, daemon, IoT device) calls
`create(id: fixedId, ...)`. On restart within the TTL window the item still
exists → `StateError`.

**Fix:** Use `upsert()` for any publisher that may run more than once with the
same id:

```dart
await collection.upsert(id: 'daily-report', obj: report);
```

---

## 2. Polling a Pre-visibility Item

**Problem:** An item with `availableAt` set in the future returns `null` from
`getOrNull()`. Calling `getOrNull()` in a loop hoping it will eventually return
a value is wasteful and misses the intended delivery model.

**Fix:** Subscribe to `availableEvents` and fetch only when the scheduler fires:

```dart
collection.availableEvents.listen((event) async {
  final item = await collection.getOrNull(event.id, event.owner);
  if (item != null) handleItem(item);
});
```

---

## 3. Constructing a Sub-collection at a Composed Namespace

**Problem:** Calling `atClient.collection('replies.comments.posts.my_app', ...)`
to read sub-items. Even if the namespace string looks right, reads return `null`
and events don't match because `AtCollection` ties key routing to the
`subCollection()` chain.

**Fix:** Always walk the parent chain:

```dart
// ✓ Correct
final comments = postCollection.subCollection<Comment>(
  parent: post, subName: 'comments', defaultExpiration: ttl,
  fromJson: Comment.fromJson, typeTag: 'Comment',
);

// ✗ Wrong — do NOT do this
// atClient.collection<Comment>('comments.posts.my_app', ttl);
```

To read a leaf item after a `CSubItemUpdated` event, use `getDescendant()`.

---

## 4. Unhandled Decode Errors in `getItemsAsStream()`

**Problem:** A single corrupt or schema-mismatched item in the keystore causes
an unhandled stream error that terminates the stream and may crash the widget.

**Fix:** Chain `.handleError()` to log-and-skip corrupt items, or use
`getItems()` if you want the entire list or nothing:

```dart
// Silent-skip pattern — omit `test:` to catch all stream errors,
// since the SDK yields decode failures as plain string errors, not a named type
collection
    .getItemsAsStream()
    .handleError((e) => logger.warning('decode error: $e'))
    .listen((item) { ... });

// All-or-nothing (a single decode failure aborts the entire list)
final items = await collection.getItems();
```

---

## 5. Deriving `typeTag` from `T.toString()` or `runtimeType`

**Problem:** Flutter/Dart tree-shaking and minification rename types in release
builds. A `typeTag` computed from `T.runtimeType.toString()` will produce
different strings across build modes → deserialization silently returns null or
throws.

**Fix:** Always pin `typeTag` as a string literal at registration and
collection creation:

```dart
AtCollection.registerFactory<Todo>(Todo.fromJson, typeTag: 'Todo');

// ✓ Correct
final todos = await atClient.collection<Todo>(
  'todos.my_app', ttl, fromJson: Todo.fromJson, typeTag: 'Todo',
);

// ✗ Wrong — breaks in release builds
// typeTag: Todo.runtimeType.toString()
```

---

## 6. Dots in `subName` or `parent.id`

**Problem:** Sub-collection key composition uses `.` as a separator. A
`subName` or item id containing `.` breaks key parsing and produces
`ArgumentError` at runtime (or, worse, silently routes to the wrong
namespace).

**Fix:** Use dot-free identifiers. Generate item ids with
alphanumeric characters only:

```dart
// ✓ OK
final sub = parentCollection.subCollection<Reply>(
  parent: comment, subName: 'replies', ...
);

// ✗ Wrong — 'sub.replies' has a dot
// subName: 'sub.replies'
```

The `AtCollection` constructor validates this and throws `ArgumentError`
before any I/O.

---

## 7. `CAncestor.owner` Is Always Null on `CSubItemDeleted`

**Problem:** The `owner` field on every `CAncestor` inside
`CSubItemDeleted.ancestry` is always `null` — the sub-item envelope is gone
by deletion time, so there's no way to recover ancestor owners. This means
you cannot call `getDescendant()` from a delete handler, because it requires
non-null ancestor owners.

Note: `CSubItemDeleted.owner` (the leaf event's own owner, inherited from
`CEvent`) is **not** null. It's specifically `ancestry[n].owner` that is null.

**Fix:** Cache the last `CSubItemUpdated` for each `(id, subName)` pair. On
delete, reuse the cached event's populated ancestry:

```dart
final Map<String, CSubItemUpdated> _lastUpdate = {};

collection.subUpdates.listen((e) {
  _lastUpdate['${e.id}:${e.subName}'] = e;
});

collection.subDeletes.listen((e) {
  // e.ancestry[n].owner is null — use cached ancestry instead
  final cached = _lastUpdate['${e.id}:${e.subName}'];
  if (cached != null) handleDelete(e.id, cached.ancestry);
  _lastUpdate.remove('${e.id}:${e.subName}');
});
```

---

## 8. Unintended Cascade Delete

**Problem:** Passing `cascade: true` to `delete()` removes **all self-owned
descendants** at any depth — not just direct children. On a deep tree this
can silently wipe a large amount of data.

**Fix:** Only use `cascade: true` when you explicitly intend to delete the
entire subtree. For interactive UIs, confirm with the user first. Without
`cascade`, `delete()` throws `StateError` if descendants exist, giving you a
safe default:

```dart
// Safe default — throws if sub-items exist
await collection.delete(item);

// Intentional deep delete — confirm intent first
await collection.delete(item, cascade: true);
```

---

## 9. `EventSource.both` Fires Twice for Cross-atSign Writes

**Problem:** With `EventSource.both` (the default), a cross-atSign write
surfaces on both the `data` path (via SyncService) and the `notifs` path
(via NotificationService). The same change fires two `CItemUpdated` events —
no automatic deduplication.

**Fix options:**

- **Accept it** if your handler is idempotent (e.g., just calls
  `setState(() {})`)
- **Debounce** with a short timer if processing is expensive
- **Switch source** — use `EventSource.data` (requires SyncService) or
  `EventSource.notifs` if you only need one path

```dart
// If you use SyncService and want exactly-once events:
final collection = await atClient.collection<T>(
  'ns.my_app', ttl, eventSource: EventSource.data,
);
```

---

## 10. Using Raw Strings Instead of the `Atsign` Type

**Problem:** Passing plain `String` values where `Atsign` is expected (e.g.,
in `sharedWith`, `getOrNull(id, owner)`, or event fields). Raw strings may
lack the `@` prefix, use uppercase, or contain invalid characters — causing
silent mismatches or runtime errors. Direct string comparisons between
atsigns also fail when one has `@` and the other doesn't.

**Fix:** Use the `Atsign` extension type (from `at_commons`, re-exported by
`at_client`) in your own method signatures. When you receive a string from
user input or an external source, call `.toAtsign()` to normalise and
validate it:

```dart
import 'package:at_client/at_client.dart'; // re-exports Atsign

// ✓ In your own APIs — use Atsign, not String
Future<void> shareWith(Atsign recipient) async {
  await collection.updateSharedWith(item, {recipient});
}

// ✓ Converting user input or an external string
final atsign = userInput.toAtsign(); // normalises, validates, adds @ if missing

// ✓ Creating a known atsign inline
final bob = '@bob'.toAtsign();

// ✗ Wrong — skips validation, comparison may silently fail
// shareWith('@Bob');   // uppercase, not an Atsign
// item.owner == '@bob' // String equality on extension type is fragile
```

`toAtsign()` normalises: converts to lowercase, auto-adds `@` prefix if
missing, and **silently strips dots from the domain part** (e.g.
`@colin.constable` → `@colinconstable`). It **throws**
`InvalidAtSignException` for whitespace, multiple `@` characters, empty
strings, and reserved characters — surface this to the user rather than
swallowing it.

**Note on spelling:** The SDK spells the type as `Atsign` (not `AtSign`) and
the concept as `atsign` (not `atSign`). Use these spellings consistently in
your own code.
