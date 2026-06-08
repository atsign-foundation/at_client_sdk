# Migrating from `atClient.put()` / `atClient.get()` to `AtCollection<T>`

Short answer: **you can use both APIs simultaneously in the same app, but `AtCollection<T>` manages its own key namespace and will not automatically discover or expose keys you wrote with the raw `atClient.put()` API.** A migration requires you to read your existing data with the raw API and re-write it through `AtCollection<T>`.

This guide walks through exactly what is different, what the migration steps are, and how to keep your app working during the transition.

---

## What is different under the hood

`atClient.put()` and `atClient.get()` are a raw key-value API. You control the full key string (e.g. `phone.contacts.me@alice`). The SDK stores and retrieves exactly that key.

`AtCollection<T>` is a higher-level abstraction on top of the same atServer keystore. It imposes a structured key format:

| Item type | Key format used by AtCollection |
|-----------|--------------------------------|
| Your own copy | `<id>.<namespace>@<atSign>` |
| Shared copy for a recipient | `<recipient>:<id>.<namespace>@<atSign>` |
| Cached incoming copy | `cached:<id>.<namespace>@<sender>` |
| Read receipt | `<receiptId>.__rr.<parentId>.<namespace>@<reader>` |

The `<id>` is an auto-generated or caller-supplied 8-character `[a-z0-9]` string. The `<namespace>` must be a fully-qualified name containing `.` (e.g. `todos.my_app`).

Because `AtCollection<T>` uses this specific structure, it will not recognise keys that were written by `atClient.put()` unless those keys happen to match the pattern exactly (which they won't in practice). **Existing raw keys are not broken** — they remain in the keystore and are still readable via `atClient.get()`. They are simply invisible to `AtCollection<T>`.

---

## Step-by-step migration

### 1. Keep both APIs running during transition

You do not need to migrate everything in one release. The raw API and `AtCollection<T>` coexist safely. Write new data through `AtCollection<T>` immediately; migrate old data separately.

### 2. Ensure your domain class has `toJson` / `fromJson`

`AtCollection<T>` serialises to JSON. If your existing objects were stored as JSON strings, you can reuse the same serialisation logic.

```dart
class Contact {
  final String name;
  final String phone;

  Contact({required this.name, required this.phone});

  Map<String, dynamic> toJson() => {'name': name, 'phone': phone};

  factory Contact.fromJson(Map<String, dynamic> json) => Contact(
    name: json['name'] as String,
    phone: json['phone'] as String,
  );
}
```

### 3. Register the factory and create the collection

Call `AtCollection.registerFactory` once at app startup (before any `atClient.collection()` call), then obtain the collection:

```dart
// In main() or your app's initialisation, before any atClient.collection() call
AtCollection.registerFactory<Contact>(Contact.fromJson, typeTag: 'Contact');

// Then obtain the collection
final contacts = await atClient.collection<Contact>(
  'contacts.my_app',           // namespace — must contain '.'
  const Duration(days: 365),   // default TTL for new items
  fromJson: Contact.fromJson,
  typeTag: 'Contact',          // must be a string literal — never T.toString()
);
```

The `typeTag` is stored alongside your data in the keystore. It must be a stable string literal. Do not derive it from `T.runtimeType.toString()` — minification in release builds renames types, which breaks deserialisation.

### 4. Read your old data and re-write it via AtCollection

Use a one-time migration function. Run it on first launch after the update, guard it with a migration-complete flag (stored wherever makes sense for your app — `shared_preferences`, or even a well-known `atClient.put()` key itself):

```dart
Future<void> migrateContactsIfNeeded(AtClient atClient) async {
  // Check if migration has already run
  final flagKey = AtKey()
    ..key = 'contacts_migrated_v1'
    ..namespace = 'my_app';
  final flagValue = await atClient.get(flagKey).then((v) => v.value).catchError((_) => null);
  if (flagValue == 'true') return;

  // Read all old keys that match your original naming convention
  final oldKeys = await atClient.getAtKeys(regex: r'contact\..+\.my_app@');
  for (final key in oldKeys) {
    final rawValue = await atClient.get(key);
    if (rawValue.value == null) continue;

    // Deserialise from your old format
    final json = jsonDecode(rawValue.value as String) as Map<String, dynamic>;
    final contact = Contact.fromJson(json);

    // Write into AtCollection — use upsert so re-runs are safe
    await contacts.upsert(
      id: key.key!,   // reuse old key name as the AtCollection id if it's dot-free
                       // (AtCollection ids must not contain dots — see note below)
      obj: contact,
    );

    // Optionally delete the old raw key once migrated
    // await atClient.delete(key);
  }

  // Mark migration complete
  await atClient.put(flagKey, AtValue()..value = 'true');
}
```

**Important:** `AtCollection` item ids must not contain dots. If your existing keys used dots as separators in the key name portion, you will need to generate new ids or strip the dots. The `upsert()` method is idempotent — safe to call if the migration is interrupted and re-run.

### 5. Stop writing to the raw API

Once migration is complete, route all reads and writes through `AtCollection<T>`:

```dart
// Before migration — raw API
final key = AtKey()..key = 'contact_alice'..namespace = 'my_app';
await atClient.put(key, AtValue()..value = jsonEncode(contact.toJson()));
final value = await atClient.get(key);

// After migration — AtCollection
await contacts.upsert(id: 'contact_alice', obj: contact);
final item = await contacts.getOrNull('contact_alice', atClient.atSign.toAtsign());
```

---

## Key rules to stay safe during migration

### Use `upsert`, not `create`, in migration code

`create()` throws `StateError` if the id already exists. `upsert()` is idempotent — it creates if the item does not exist, and overwrites if it does. This makes re-runnable migration code safe:

```dart
// Safe — works even if migration runs twice
await contacts.upsert(id: existingId, obj: contact);

// Unsafe in migration — throws on second run
// await contacts.create(id: existingId, obj: contact);
```

### Dot-free ids only

`AtCollection` uses `.` as a structural separator in key names. Item ids and sub-collection names must not contain dots. If you stored data with keys like `first.last`, map to a dot-free form during migration:

```dart
// Old key: 'alice.smith.contacts.my_app@myatsign'
// New id:  'alice_smith' (replace dots or use a generated id)
final newId = oldKeyName.replaceAll('.', '_');
await contacts.upsert(id: newId, obj: contact);
```

### `typeTag` is permanent

Once you write items with a `typeTag` (e.g. `'Contact'`), you cannot rename it in a future release. Items written with a different tag become undeserializable. Treat it as part of your public data contract.

### Schema evolution is handled in `fromJson`

If your old raw-API data had a different JSON structure, handle both shapes in `fromJson` during the transition:

```dart
factory Contact.fromJson(Map<String, dynamic> json) => Contact(
  name: json['name'] as String? ?? json['fullName'] as String,  // handles old 'fullName' key
  phone: json['phone'] as String? ?? json['phoneNumber'] as String? ?? '',
);
```

---

## What you gain after migration

Once your data is in `AtCollection<T>`, you get:

- **Typed reactive queries** — filter, sort, paginate, and watch for changes with `Query<T>`
- **Per-item sharing** — share specific records with named atSigns via `sharedWith`
- **Sub-collections** — attach nested typed records to any item
- **Event streams** — `updates`, `deletes`, `readReceipts`, `subUpdates`, `availableEvents`
- **Read receipts** — know when recipients have read a shared item
- **Expiry scheduling** — `availableAt` and `expiringSoonEvents`

```dart
// Reactive query replacing manual getAtKeys + loop
final liveContacts = contacts
    .query()
    .where((c) => c.obj.name.startsWith('A'))
    .orderBy((c) => c.obj.name)
    .watch();  // Stream<List<CItem<Contact>>>

// Share a contact with another atSign
final item = await contacts.upsert(id: 'alice', obj: alice);
await contacts.updateSharedWith(item, {'@bob'.toAtsign()});
```

---

## Summary checklist

- [ ] Add `toJson()` / `fromJson` to each domain class
- [ ] Register factories at startup: `AtCollection.registerFactory<T>(T.fromJson, typeTag: 'T')`
- [ ] Pick a stable `typeTag` string literal for each type
- [ ] Write migration function using `atClient.getAtKeys()` + `upsert()`
- [ ] Guard migration with a completion flag so it runs only once
- [ ] Ensure ids are dot-free before passing to `upsert()`
- [ ] Handle old JSON shapes in `fromJson` during transition period
- [ ] After confirming migration, remove the raw-API write paths from your app code
- [ ] Optionally delete old raw keys after confirming migrated data is correct

The raw `atClient.put()` / `atClient.get()` API and `AtCollection<T>` share the same underlying atServer keystore and can coexist indefinitely. Migration is opt-in and incremental — there is no flag to flip and no forced cutover.
