# Using AtCollectionModel to Store Data in a Dart App

`AtCollectionModel` is a utility class provided by the atPlatform Dart SDK (part of the `at_collection` package) that simplifies storing, retrieving, and managing structured data (collections of objects) on the atPlatform network.

---

## 1. Add the Dependency

In your `pubspec.yaml`, add the `at_collection` package:

```yaml
dependencies:
  at_collection: ^latest_version
  at_client_mobile: ^latest_version
```

Run:

```bash
dart pub get
```

---

## 2. Create a Model Class

Your data model must extend `AtCollectionModel` and implement the required serialization methods:

```dart
import 'package:at_collection/at_collection.dart';

class Note extends AtCollectionModel {
  String title;
  String content;

  Note({required this.title, required this.content});

  // Required: convert to JSON map
  @override
  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'content': content,
    };
  }

  // Required: populate fields from JSON map
  @override
  void fromJson(Map<String, dynamic> json) {
    title = json['title'] ?? '';
    content = json['content'] ?? '';
  }

  // Required: provide a unique collection name (used as a namespace/key prefix)
  @override
  String collectionName() => 'note';
}
```

Key points:
- `toJson()` must return a `Map<String, dynamic>` representing the object.
- `fromJson(Map<String, dynamic>)` populates the object from a map.
- `collectionName()` returns a string that acts as a key namespace for all instances of this model.

---

## 3. Save (Store) an Object

Use `AtCollectionModelOperations` (or the mixin methods available on the model) to save an instance:

```dart
final note = Note(title: 'My First Note', content: 'Hello, atPlatform!');

// Save to your own atSign's secondary server
bool success = await note.save();

if (success) {
  print('Note saved with id: ${note.id}');
} else {
  print('Failed to save note.');
}
```

- On the first call to `save()`, an `id` (UUID) is automatically assigned to the object.
- Subsequent calls to `save()` on the same instance will update the existing record.

---

## 4. Share an Object with Another atSign

You can share a saved object with one or more other atSigns:

```dart
// Share with @alice
bool shared = await note.share(['@alice']);

if (shared) {
  print('Note shared with @alice');
}
```

The shared data is stored under a key accessible to `@alice` on the atPlatform network.

---

## 5. Retrieve All Saved Objects

Use `AtCollectionModel.getAll()` to fetch all stored instances of a model:

```dart
List<Note> notes = await AtCollectionModelOperations<Note>(Note()).getAll();

for (var note in notes) {
  print('${note.id}: ${note.title}');
}
```

Alternatively, if your model class exposes a static helper:

```dart
List<Note> notes = await Note().getAll();
```

---

## 6. Retrieve a Specific Object by ID

```dart
Note? note = await AtCollectionModelOperations<Note>(Note()).getById('your-note-id');

if (note != null) {
  print(note.title);
}
```

---

## 7. Delete an Object

To delete a saved object (removes it from your secondary server and revokes shares):

```dart
bool deleted = await note.delete();

if (deleted) {
  print('Note deleted.');
}
```

---

## 8. Unshare an Object

To revoke access for a specific atSign without deleting the object entirely:

```dart
bool unshared = await note.unshare(['@alice']);
```

---

## Full Example

```dart
import 'package:at_collection/at_collection.dart';

class Note extends AtCollectionModel {
  String title;
  String content;

  Note({this.title = '', this.content = ''});

  @override
  Map<String, dynamic> toJson() => {'title': title, 'content': content};

  @override
  void fromJson(Map<String, dynamic> json) {
    title = json['title'] ?? '';
    content = json['content'] ?? '';
  }

  @override
  String collectionName() => 'note';
}

Future<void> main() async {
  // Assumes AtClient is already initialized and authenticated

  // Create and save
  final note = Note(title: 'Shopping List', content: 'Milk, Eggs, Bread');
  await note.save();
  print('Saved note id: ${note.id}');

  // Share
  await note.share(['@bob']);

  // Retrieve all
  final allNotes = await Note().getAll();
  for (final n in allNotes) {
    print('Note: ${n.title}');
  }

  // Delete
  await note.delete();
}
```

---

## Important Notes

- **AtClient must be initialized** and the user must be authenticated with their atSign before using `AtCollectionModel`.
- The `id` field on `AtCollectionModel` is auto-generated (UUID v4) on first save. You can also set a custom `id` before calling `save()` if you need a deterministic identifier.
- Data is end-to-end encrypted on the atPlatform; sharing with another atSign uses their public key for encryption.
- The `collectionName()` string should be lowercase and unique per model type in your app, as it forms part of the atKey used to store the data.
- As of some SDK versions, `AtCollectionModel` and related APIs have been marked as **deprecated** in favor of lower-level `AtKey` and `AtClient` APIs for more fine-grained control. Check the package changelog and migration guide when upgrading.
