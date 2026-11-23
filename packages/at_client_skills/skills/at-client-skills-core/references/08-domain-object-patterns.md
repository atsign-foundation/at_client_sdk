# Domain-Object Patterns

`AtCollection<T>` stores your domain objects as JSON. Any Dart class with
`toJson()` and a `fromJson` factory works. This guide covers the required
contract, polymorphic types, factory registration, and primitive/binary
payloads.

---

## Minimal Domain Object

A domain object needs two things:

1. `Map<String, dynamic> toJson()` — serialize to JSON
2. `factory T.fromJson(Map<String, dynamic> json)` — deserialize from JSON

```dart
class Todo {
  final String title;
  final String description;
  bool done;
  DateTime? dueDate;

  Todo({
    required this.title,
    required this.description,
    this.done = false,
    this.dueDate,
  });

  factory Todo.fromJson(Map<String, dynamic> json) {
    return Todo(
      title: json['title'] as String,
      description: json['description'] as String,
      done: json['done'] as bool? ?? false,
      dueDate: json['dueDate'] != null
          ? DateTime.parse(json['dueDate'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'done': done,
    if (dueDate != null) 'dueDate': dueDate!.toIso8601String(),
  };
}
```

Then pass `fromJson` and `typeTag` when creating the collection:

```dart
final todos = await atClient.collection<Todo>(
  'todos.my_app',
  const Duration(days: 365),
  fromJson: Todo.fromJson,
  typeTag: 'Todo',   // ← must be a string literal — never derive from runtimeType
);
```

---

## Sub-collection Domain Objects

Sub-collection items follow the exact same pattern — they just live in a
child collection:

```dart
class TodoNote {
  final String note;

  TodoNote({required this.note});

  factory TodoNote.fromJson(Map<String, dynamic> json) =>
      TodoNote(note: json['note'] as String);

  Map<String, dynamic> toJson() => {'note': note};
}

// Usage
final notes = todos.subCollection<TodoNote>(
  parent: todoItem,
  subName: 'notes',
  defaultExpiration: const Duration(days: 30),
  fromJson: TodoNote.fromJson,
  typeTag: 'TodoNote',
);
```

---

## Polymorphic Types

When multiple concrete types share a base type, register each concrete type
separately and create the collection typed as the abstract base:

```dart
// Abstract base — no fromJson (cannot be instantiated directly)
abstract class Pet {
  final String name;
  Pet({required this.name});
  String get sound;
  Map<String, dynamic> toJson();
}

class Dog extends Pet {
  Dog({required super.name});

  @override String get sound => 'Woof!';

  factory Dog.fromJson(Map<String, dynamic> json) => Dog(name: json['name'] as String);

  @override
  Map<String, dynamic> toJson() => {'name': name};
}

class Cat extends Pet {
  Cat({required super.name});

  @override String get sound => 'Meoow!';

  factory Cat.fromJson(Map<String, dynamic> json) => Cat(name: json['name'] as String);

  @override
  Map<String, dynamic> toJson() => {'name': name};
}
```

Register concrete factories **before** creating the collection (typically in
`main()`):

```dart
void main() async {
  // Register all concrete subtypes
  AtCollection.registerFactory<Dog>(Dog.fromJson, typeTag: 'Dog');
  AtCollection.registerFactory<Cat>(Cat.fromJson, typeTag: 'Cat');

  // Collection typed as the base — no fromJson/typeTag on the collection itself
  final pets = await atClient.collection<Pet>(
    'pets.my_app',
    const Duration(days: 365),
    eventSource: EventSource.both,
  );

  // Creates store a Dog in the pets collection
  await pets.create(obj: Dog(name: 'Rex'));
  await pets.create(obj: Cat(name: 'Felix'));

  // Reads return the correct concrete type
  final items = await pets.getItems();
  for (final item in items) {
    print('${item.obj.name} says ${item.obj.sound}');
  }
}
```

---

## `AtCollection.registerFactory` Rules

```dart
AtCollection.registerFactory<T>(T.fromJson, typeTag: 'MyTag');
```

- Call once at app startup, before any `atClient.collection(...)` that uses that
  type
- **Same `(Type, typeTag)` pair** → idempotent; last write wins (safe to call
  multiple times)
- **Same `Type`, different `typeTag`** → throws `StateError` — tag is part of
  the wire format
- **Same `typeTag`, different `Type`** → throws `StateError` — tags must be
  globally unique
- Registration is **process-global** across all `AtCollection` instances in
  the Dart isolate

---

## `typeTag` Must Be a String Literal

The `typeTag` is stored in the atServer keystore alongside your data. It must
be stable across app versions and build modes (debug, profile, release).

```dart
// ✓ Correct — stable string literal
AtCollection.registerFactory<Dog>(Dog.fromJson, typeTag: 'Dog');

// ✗ Wrong — breaks in minified/obfuscated release builds
// typeTag: Dog.runtimeType.toString()
// typeTag: '$T'
```

If you ever change a `typeTag` in a published app, existing stored items
become undeserializable. Treat `typeTag` values as part of your public API
once deployed.

---

## Primitive and Map Collections

For simple payloads — plain strings, raw JSON maps, or lists — you don't
need `fromJson`:

```dart
// String collection
final notes = await atClient.collection<String>('notes.my_app', ttl);
await notes.create(obj: 'Hello world');

// Map collection (arbitrary JSON object)
final configs = await atClient.collection<Map<String, dynamic>>('configs.my_app', ttl);
await configs.create(obj: {'theme': 'dark', 'lang': 'en'});
```

No `fromJson` or `typeTag` needed for `String`, `int`, `double`, `bool`,
`Map<String, dynamic>`, or `List`.

---

## Binary Payloads

For raw binary data (images, files, encrypted blobs), use `Uint8List`:

```dart
import 'dart:typed_data';

final images = await atClient.collection<Uint8List>(
  'photos.my_app', ttl,
  typeTag: 'binary',  // ← required for Uint8List
);

final bytes = await File('photo.jpg').readAsBytes();
await images.create(obj: bytes);
```

`typeTag: 'binary'` is the reserved tag for `Uint8List` — use it exactly as
shown.

---

## Schema Evolution

`AtCollection<T>` stores raw JSON, so you can evolve your schema across app
versions:

- **Adding a field** → give it a default in `fromJson`; old items
  deserialize without it
- **Removing a field** → ignore it in `fromJson`; old JSON fields are
  silently skipped
- **Renaming a field** → read both old and new keys in `fromJson`
  during a transition period
- **Changing a field type** → handle both shapes in `fromJson`

```dart
// Evolved fromJson — safely handles both old (no dueDate) and new items
factory Todo.fromJson(Map<String, dynamic> json) {
  return Todo(
    title: json['title'] as String,
    description: json['description'] as String? ?? '',  // added default
    done: json['done'] as bool? ?? false,
    // Handles both old 'due' key and new 'dueDate' key
    dueDate: json['dueDate'] != null
        ? DateTime.parse(json['dueDate'] as String)
        : json['due'] != null
            ? DateTime.parse(json['due'] as String)
            : null,
  );
}
```

---

## Canonical Example

See the full polymorphic example in the SDK repo at:  
`packages/at_client/example/bin/collections_domain_objects.dart`  
`packages/at_client/example/lib/domain_objects.dart`
