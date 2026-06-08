# Reactive Todo Query in Flutter with StreamBuilder

This guide shows how to query todos reactively in a Flutter `StreamBuilder`, filtering for `done=false` and sorting by due date.

## Overview

The approach depends on your data backend. The most common patterns in Flutter are:

1. **Cloud Firestore** — built-in reactive queries
2. **SQLite (via `sqflite` or `drift`)** — stream-based queries
3. **Isar / Hive** — reactive local databases
4. **Custom stream + in-memory state**

The examples below cover the most common cases.

---

## Option 1: Cloud Firestore

Firestore supports server-side filtering and ordering natively.

### Setup

```yaml
# pubspec.yaml
dependencies:
  flutter:
    sdk: flutter
  cloud_firestore: ^4.0.0
  firebase_core: ^2.0.0
```

### Stream definition

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

Stream<List<Todo>> incompleteTodosStream() {
  return FirebaseFirestore.instance
      .collection('todos')
      .where('done', isEqualTo: false)
      .orderBy('dueDate')
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map((doc) => Todo.fromFirestore(doc))
          .toList());
}
```

### Todo model

```dart
class Todo {
  final String id;
  final String title;
  final bool done;
  final DateTime? dueDate;

  Todo({
    required this.id,
    required this.title,
    required this.done,
    this.dueDate,
  });

  factory Todo.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Todo(
      id: doc.id,
      title: data['title'] as String,
      done: data['done'] as bool,
      dueDate: (data['dueDate'] as Timestamp?)?.toDate(),
    );
  }
}
```

### StreamBuilder widget

```dart
import 'package:flutter/material.dart';

class TodoListScreen extends StatelessWidget {
  const TodoListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Todos')),
      body: StreamBuilder<List<Todo>>(
        stream: incompleteTodosStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No pending todos'));
          }

          final todos = snapshot.data!;

          return ListView.builder(
            itemCount: todos.length,
            itemBuilder: (context, index) {
              final todo = todos[index];
              return ListTile(
                title: Text(todo.title),
                subtitle: todo.dueDate != null
                    ? Text('Due: ${_formatDate(todo.dueDate!)}')
                    : null,
                trailing: Icon(
                  todo.done ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: todo.done ? Colors.green : Colors.grey,
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
```

---

## Option 2: Drift (SQLite, type-safe, reactive)

Drift generates reactive streams from SQLite queries.

### Setup

```yaml
# pubspec.yaml
dependencies:
  drift: ^2.0.0
  sqlite3_flutter_libs: ^0.5.0
  path_provider: ^2.0.0
  path: ^1.8.0

dev_dependencies:
  drift_dev: ^2.0.0
  build_runner: ^2.0.0
```

### Database definition

```dart
// database.dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

part 'database.g.dart';

class Todos extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  DateTimeColumn get dueDate => dateTime().nullable()();
}

@DriftDatabase(tables: [Todos])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  // Reactive query: incomplete todos sorted by due date
  Stream<List<Todo>> watchIncompleteTodos() {
    return (select(todos)
          ..where((t) => t.done.equals(false))
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.dueDate,
                  mode: OrderingMode.asc,
                  nulls: NullsOrder.last,
                )
          ]))
        .watch();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'todos.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
```

### StreamBuilder with Drift

```dart
import 'package:flutter/material.dart';

class TodoListScreen extends StatelessWidget {
  final AppDatabase db;

  const TodoListScreen({super.key, required this.db});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Todos')),
      body: StreamBuilder<List<Todo>>(
        stream: db.watchIncompleteTodos(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final todos = snapshot.data ?? [];

          if (todos.isEmpty) {
            return const Center(child: Text('No pending todos'));
          }

          return ListView.builder(
            itemCount: todos.length,
            itemBuilder: (context, index) {
              final todo = todos[index];
              return ListTile(
                title: Text(todo.title),
                subtitle: todo.dueDate != null
                    ? Text('Due: ${todo.dueDate!.toLocal()}')
                    : null,
                leading: Checkbox(
                  value: todo.done,
                  onChanged: (value) {
                    db.update(db.todos).replace(
                          todo.copyWith(done: value ?? false),
                        );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
```

---

## Option 3: Custom In-Memory Stream (No External Database)

If you manage state yourself (e.g., with a `StreamController`), filter and sort client-side.

### Repository with StreamController

```dart
import 'dart:async';

class Todo {
  final String id;
  final String title;
  final bool done;
  final DateTime? dueDate;

  Todo({
    required this.id,
    required this.title,
    required this.done,
    this.dueDate,
  });

  Todo copyWith({String? id, String? title, bool? done, DateTime? dueDate}) {
    return Todo(
      id: id ?? this.id,
      title: title ?? this.title,
      done: done ?? this.done,
      dueDate: dueDate ?? this.dueDate,
    );
  }
}

class TodoRepository {
  final _todos = <Todo>[];
  final _controller = StreamController<List<Todo>>.broadcast();

  Stream<List<Todo>> get incompleteTodosSortedByDueDate {
    return _controller.stream.map(_filterAndSort);
  }

  List<Todo> _filterAndSort(List<Todo> todos) {
    final incomplete = todos.where((t) => !t.done).toList();
    incomplete.sort((a, b) {
      if (a.dueDate == null && b.dueDate == null) return 0;
      if (a.dueDate == null) return 1;  // nulls last
      if (b.dueDate == null) return -1;
      return a.dueDate!.compareTo(b.dueDate!);
    });
    return incomplete;
  }

  void _emit() => _controller.add(List.unmodifiable(_todos));

  void addTodo(Todo todo) {
    _todos.add(todo);
    _emit();
  }

  void updateTodo(Todo updated) {
    final index = _todos.indexWhere((t) => t.id == updated.id);
    if (index != -1) {
      _todos[index] = updated;
      _emit();
    }
  }

  void dispose() => _controller.close();
}
```

### StreamBuilder usage

```dart
class TodoListScreen extends StatelessWidget {
  final TodoRepository repository;

  const TodoListScreen({super.key, required this.repository});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Todos')),
      body: StreamBuilder<List<Todo>>(
        stream: repository.incompleteTodosSortedByDueDate,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final todos = snapshot.data!;

          if (todos.isEmpty) {
            return const Center(child: Text('All done!'));
          }

          return ListView.builder(
            itemCount: todos.length,
            itemBuilder: (context, index) {
              final todo = todos[index];
              return ListTile(
                title: Text(todo.title),
                subtitle: todo.dueDate != null
                    ? Text('Due: ${todo.dueDate!.toLocal()}')
                    : const Text('No due date'),
                trailing: IconButton(
                  icon: const Icon(Icons.check),
                  onPressed: () {
                    repository.updateTodo(todo.copyWith(done: true));
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
```

---

## Key Points

### Handling null due dates in sorting

When sorting by due date, decide whether nulls sort first or last:

```dart
// Nulls last (items without due dates appear at the bottom)
incomplete.sort((a, b) {
  if (a.dueDate == null && b.dueDate == null) return 0;
  if (a.dueDate == null) return 1;
  if (b.dueDate == null) return -1;
  return a.dueDate!.compareTo(b.dueDate!);
});
```

### StreamBuilder connection states

Always handle all three meaningful states:

```dart
StreamBuilder<List<Todo>>(
  stream: myStream,
  builder: (context, snapshot) {
    // Waiting for first data
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const CircularProgressIndicator();
    }

    // Stream emitted an error
    if (snapshot.hasError) {
      return Text('Error: ${snapshot.error}');
    }

    // Stream closed with no data (rare)
    if (snapshot.connectionState == ConnectionState.done && !snapshot.hasData) {
      return const Text('Stream closed');
    }

    // Data available (including empty list)
    final todos = snapshot.data ?? [];
    // ... render todos
  },
)
```

### Avoid rebuilding the stream on every build

Do not create the stream inside the `build` method — it will reconnect on every rebuild:

```dart
// BAD — creates a new stream on every rebuild
@override
Widget build(BuildContext context) {
  return StreamBuilder(
    stream: db.watchIncompleteTodos(), // called on every rebuild
    ...
  );
}

// GOOD — store stream in initState or use a provider
class _TodoListScreenState extends State<TodoListScreen> {
  late final Stream<List<Todo>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = widget.db.watchIncompleteTodos();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _stream, // stable reference
      ...
    );
  }
}
```

### Using with state management

For larger apps, consider pairing streams with `Provider`, `Riverpod`, or `BLoC`:

```dart
// With Riverpod
final incompleteTodosProvider = StreamProvider<List<Todo>>((ref) {
  return ref.watch(databaseProvider).watchIncompleteTodos();
});

// In widget
final asyncTodos = ref.watch(incompleteTodosProvider);
return asyncTodos.when(
  data: (todos) => ListView.builder(...),
  loading: () => const CircularProgressIndicator(),
  error: (e, _) => Text('Error: $e'),
);
```

---

## Summary

| Backend | Filtering | Sorting | Reactivity |
|---------|-----------|---------|------------|
| Firestore | `.where('done', isEqualTo: false)` | `.orderBy('dueDate')` | `.snapshots()` |
| Drift | `.where((t) => t.done.equals(false))` | `.orderBy([...])` | `.watch()` |
| Custom | `list.where((t) => !t.done)` | `list.sort(...)` | `StreamController` |

All three approaches work seamlessly with Flutter's `StreamBuilder` widget — the key is ensuring the stream emits a new `List<Todo>` whenever the underlying data changes.
