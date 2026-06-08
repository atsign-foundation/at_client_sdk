# Migrating from atClient.put() / atClient.get() to AtCollection

## Short Answer

Yes, you can migrate to `AtCollection` without breaking existing data — but it requires careful planning. `AtCollection` is a higher-level abstraction built on top of the same underlying atProtocol key-value store that `atClient.put()` and `atClient.get()` use. The key concern is **key naming conventions**: `AtCollection` uses a specific key format that differs from keys you may have created manually, so you will need a migration strategy to avoid data loss or duplication.

---

## Understanding the Key Difference

### Raw atClient.put() / atClient.get()

When you use `atClient.put()` directly, you construct an `AtKey` manually:

```dart
final key = AtKey()
  ..key = 'phone'
  ..namespace = 'myapp'
  ..sharedBy = '@alice';

await atClient.put(key, '555-1234');
```

This creates a key like: `phone.myapp@alice`

### AtCollection

`AtCollection` (from the `at_collections` package or similar) wraps objects and stores them using a structured key format, typically incorporating:

- A collection name
- An ID (often a UUID)
- A namespace
- Metadata about the collection type

A key stored by `AtCollection` might look like: `collectionname-uuid.namespace@atSign`

Because these key formats differ, **data stored with raw `put()` will NOT automatically appear in an `AtCollection` query**, and vice versa.

---

## Migration Strategies

### Option 1: Read-and-Rewrite (Recommended for Small Datasets)

1. Read all existing keys using `atClient.getAtKeys()` or `atClient.get()`.
2. Deserialize the stored values.
3. Write each value into the `AtCollection` using the collection's `put()` or `add()` method.
4. Optionally delete the old raw keys after confirming migration success.

```dart
// Example sketch (pseudocode)
final atKeys = await atClient.getAtKeys(regex: '.*\\.myapp@alice');

for (final atKey in atKeys) {
  final value = await atClient.get(atKey);
  // Deserialize value to your model object
  final myModel = MyModel.fromJson(jsonDecode(value.value));
  // Write into collection
  await myCollection.put(myModel.id, myModel);
}

// After verifying, optionally clean up old keys
for (final atKey in atKeys) {
  await atClient.delete(atKey);
}
```

### Option 2: Dual-Read Compatibility Layer

During a transition period, keep your existing `get()` calls working while also writing to the collection. This lets you migrate gradually:

1. Continue reading from raw keys for existing records.
2. Write all new records to `AtCollection`.
3. Over time, migrate old records as they are accessed ("lazy migration").

```dart
Future<MyModel?> getRecord(String id) async {
  // Try collection first
  final fromCollection = await myCollection.get(id);
  if (fromCollection != null) return fromCollection;

  // Fall back to legacy key
  final legacyKey = AtKey()..key = id..namespace = 'myapp';
  final raw = await atClient.get(legacyKey);
  if (raw?.value != null) {
    final model = MyModel.fromJson(jsonDecode(raw!.value));
    // Migrate on access
    await myCollection.put(id, model);
    await atClient.delete(legacyKey); // optional cleanup
    return model;
  }
  return null;
}
```

### Option 3: Namespace Isolation

If your old data uses a different namespace than the collection will use, there is no conflict at all. You can leave old data in place and start fresh with `AtCollection` under a new namespace. This is safe but means old data is not accessible through the collection API.

---

## Important Considerations

### 1. Key Enumeration

Before migrating, enumerate all existing keys to understand what you have:

```dart
final existingKeys = await atClient.getAtKeys(
  regex: r'.*\.myapp@alice',
);
print('Found ${existingKeys.length} keys to migrate');
```

### 2. Data Serialization

`AtCollection` typically works with typed objects and handles serialization internally. Make sure your existing data is stored in a format (e.g., JSON) that can be deserialized into the models `AtCollection` expects.

### 3. Shared / Public Keys

If any of your existing keys were shared with other atSigns (`sharedWith`) or made public, be aware that `AtCollection` may handle sharing differently. Verify that your collection's sharing semantics match your original intent.

### 4. No Automatic Schema Migration

The atProtocol does not provide a built-in migration tool. All migration logic must be written in your application code.

### 5. Test in a Staging Environment First

Use a test atSign to validate your migration logic before running it against production data. The atProtocol's data is stored on the atServer, and while deletions are reversible in some cases, it is safest to test first.

### 6. Metadata Preservation

Raw `atClient.put()` calls allow you to set TTL, TTB, and other metadata. When migrating to `AtCollection`, verify whether the collection abstraction preserves or discards this metadata, and handle it explicitly if needed.

---

## Summary Checklist

- [ ] Audit existing keys with `atClient.getAtKeys()`
- [ ] Understand the key format used by the specific `AtCollection` implementation you are adopting
- [ ] Write and test a migration function on a test atSign
- [ ] Decide on a migration strategy: big-bang rewrite, lazy/on-access migration, or namespace isolation
- [ ] Handle serialization/deserialization explicitly
- [ ] Verify shared and public key semantics are preserved
- [ ] Clean up old raw keys after confirming migration success

---

## Bottom Line

Migrating is safe and feasible — the atProtocol store is the same underneath. The work is in mapping your existing key naming scheme to the collection's key naming scheme, and writing the migration code to move the data. There is no risk of data corruption from simply starting to use `AtCollection` alongside existing `put()`/`get()` code, as long as you are aware that the two approaches use different key formats and will not automatically see each other's data.
