# Storing and Sharing Todos in Flutter

## Overview

To build a Flutter app that stores todos and shares them with other users, you have several options depending on your backend preference. The most common approaches use Firebase or a custom backend. Below is guidance using Firebase (the most popular choice for Flutter apps), along with notes on alternatives.

---

## Recommended Packages

### Core Packages

Add these to your `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter

  # Firebase core
  firebase_core: ^2.0.0

  # Firestore for storing todos
  cloud_firestore: ^4.0.0

  # Firebase Auth for user identity (required for sharing)
  firebase_auth: ^4.0.0

  # Optional: state management
  provider: ^6.0.0
  # or
  riverpod: ^2.0.0
```

---

## Setup Steps

### 1. Initialize Firebase

Follow the FlutterFire CLI setup:

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

Then initialize Firebase in `main.dart`:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}
```

---

## Data Model

Design your Firestore document structure to support sharing:

```
/todos/{todoId}
  - title: String
  - description: String
  - completed: bool
  - ownerId: String          // UID of the creator
  - sharedWith: List<String> // UIDs or email addresses of users with access
  - createdAt: Timestamp
  - updatedAt: Timestamp
```

In Dart, represent this as:

```dart
class Todo {
  final String id;
  final String title;
  final String description;
  final bool completed;
  final String ownerId;
  final List<String> sharedWith;
  final DateTime createdAt;
  final DateTime updatedAt;

  Todo({
    required this.id,
    required this.title,
    this.description = '',
    this.completed = false,
    required this.ownerId,
    this.sharedWith = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'completed': completed,
      'ownerId': ownerId,
      'sharedWith': sharedWith,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  factory Todo.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Todo(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      completed: data['completed'] ?? false,
      ownerId: data['ownerId'] ?? '',
      sharedWith: List<String>.from(data['sharedWith'] ?? []),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    );
  }
}
```

---

## Creating a Todo

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TodoService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference get _todosCollection =>
      _firestore.collection('todos');

  /// Creates a new todo owned by the current user
  Future<String> createTodo({
    required String title,
    String description = '',
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final now = DateTime.now();
    final todo = Todo(
      id: '', // Firestore generates this
      title: title,
      description: description,
      ownerId: user.uid,
      createdAt: now,
      updatedAt: now,
    );

    final docRef = await _todosCollection.add(todo.toMap());
    return docRef.id;
  }
}
```

---

## Sharing a Todo With Another User

To share a todo, add the recipient's UID to the `sharedWith` list:

```dart
  /// Share a todo with another user by their UID
  Future<void> shareTodo({
    required String todoId,
    required String recipientUid,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    await _todosCollection.doc(todoId).update({
      'sharedWith': FieldValue.arrayUnion([recipientUid]),
      'updatedAt': Timestamp.now(),
    });
  }
```

If you only have the recipient's email, look up their UID first (requires a separate users collection or a Cloud Function):

```dart
  /// Look up a user's UID by email (requires a /users collection)
  Future<String?> getUidByEmail(String email) async {
    final query = await _firestore
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();

    if (query.docs.isEmpty) return null;
    return query.docs.first.id;
  }
```

---

## Reading Todos (Own + Shared)

```dart
  /// Stream all todos the current user owns or has been shared with them
  Stream<List<Todo>> getTodos() {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();

    // Todos owned by the user
    final ownedStream = _todosCollection
        .where('ownerId', isEqualTo: user.uid)
        .snapshots();

    // Todos shared with the user
    final sharedStream = _todosCollection
        .where('sharedWith', arrayContains: user.uid)
        .snapshots();

    // Merge both streams
    // Note: for a cleaner merge, use rxdart's MergeStream
    return ownedStream.map((snapshot) =>
        snapshot.docs.map((doc) => Todo.fromDoc(doc)).toList());
  }
```

For combining both streams, add `rxdart`:

```yaml
  rxdart: ^0.27.0
```

```dart
import 'package:rxdart/rxdart.dart';

Stream<List<Todo>> getAllTodos() {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return const Stream.empty();

  final owned = FirebaseFirestore.instance
      .collection('todos')
      .where('ownerId', isEqualTo: user.uid)
      .snapshots()
      .map((s) => s.docs.map(Todo.fromDoc).toList());

  final shared = FirebaseFirestore.instance
      .collection('todos')
      .where('sharedWith', arrayContains: user.uid)
      .snapshots()
      .map((s) => s.docs.map(Todo.fromDoc).toList());

  return Rx.combineLatest2(owned, shared, (a, b) => [...a, ...b]);
}
```

---

## Firestore Security Rules

Protect your data so users can only access their own or shared todos:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /todos/{todoId} {
      allow read: if request.auth != null &&
        (resource.data.ownerId == request.auth.uid ||
         request.auth.uid in resource.data.sharedWith);

      allow create: if request.auth != null &&
        request.resource.data.ownerId == request.auth.uid;

      allow update: if request.auth != null &&
        resource.data.ownerId == request.auth.uid;

      allow delete: if request.auth != null &&
        resource.data.ownerId == request.auth.uid;
    }

    match /users/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

---

## Alternative Approaches

### Supabase (PostgreSQL-based)

If you prefer an open-source backend with row-level security:

```yaml
  supabase_flutter: ^1.0.0
```

Supabase provides row-level security policies in PostgreSQL and real-time subscriptions, making sharing straightforward with foreign-key relationships.

### Local-only with Drift (SQLite)

For offline-first with no sharing:

```yaml
  drift: ^2.0.0
  sqlite3_flutter_libs: ^0.5.0
```

Drift does not support multi-user sharing on its own — you would need a sync layer.

### Hive (lightweight key-value)

```yaml
  hive_flutter: ^1.1.0
```

Good for simple local storage, not suitable for multi-user sharing without a backend.

---

## Summary

| Need | Package |
|---|---|
| Cloud database | `cloud_firestore` |
| User authentication | `firebase_auth` |
| Firebase setup | `firebase_core` |
| Stream merging | `rxdart` |
| State management | `provider` or `riverpod` |

**Minimum steps to create and share a todo:**

1. Authenticate the user with `firebase_auth`.
2. Call `TodoService().createTodo(title: 'Buy groceries')` to write to Firestore.
3. Obtain the recipient's UID.
4. Call `TodoService().shareTodo(todoId: id, recipientUid: uid)` to add them to `sharedWith`.
5. Apply Firestore security rules so only authorized users can read the document.
