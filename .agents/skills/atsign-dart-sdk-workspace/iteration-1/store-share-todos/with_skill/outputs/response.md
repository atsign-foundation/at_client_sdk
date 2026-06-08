# Storing and Sharing Todos in a Flutter App with the atProtocol

## 1. Which Packages Do You Need?

For a Flutter app that stores and shares todos, add the following to your `pubspec.yaml`:

```yaml
dependencies:
  at_client: ^3.12.0
  at_client_flutter: ^1.1.2
  at_auth: ^3.1.0          # for AtAuthRequest and auth flow helpers
  path_provider: ^2.0.0    # for getApplicationSupportDirectory()
```

**Do NOT add** `at_common_flutter` or `at_backupkey_flutter` — both are deprecated.

---

## 2. Define Your Todo Domain Object

Your domain object needs `toJson()` and a `fromJson` factory. Nothing else is required.

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

**Important rules:**
- `typeTag` must always be a string literal (e.g. `'Todo'`). Never derive it from `runtimeType.toString()` or `'$T'` — Dart's tree-shaker and obfuscator rename types in release builds, which would break deserialization.
- Treat `typeTag` values as part of your public API once deployed — changing them makes existing stored items undeserializable.

---

## 3. Authenticate the User (Flutter)

Authentication must happen before you use `AtCollection`. `at_client_flutter` provides
dialog-based helpers for all four auth flows. Here is the most common flow for a returning
user who has an `.atKeys` file, and one for a user already on the same device.

### Flow 2: Login with an .atKeys File (most common for returning developers)

```dart
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_client_flutter/extensions.dart';
import 'package:at_auth/at_auth.dart';
import 'package:path_provider/path_provider.dart';

Future<void> loginWithFile(BuildContext context) async {
  final atKeysIo = await AtKeysFileDialog.show(context);
  if (atKeysIo == null || !context.mounted) return;

  final authRequest = AtAuthRequest(
    atKeysIo.getAtsign(),
    atKeysIo: atKeysIo,
    rootDomain: AtRootDomain.atsignDomain,
  );
  final response = await PkamDialog.show(
    context,
    request: authRequest,
    backupKeys: [KeychainAtKeysIo()], // saves keys to device keychain for future logins
  );
  if (response?.isSuccessful == true) await _setupAtClient(authRequest, response!);
}
```

### Flow 3: Login from Device Keychain (returning user on same device)

```dart
Future<void> loginWithKeychain(BuildContext context) async {
  final atSigns = await KeychainStorage().getAllAtsigns();
  if (atSigns.isEmpty || !context.mounted) return;

  final request = await AtSignSelectionDialog.show(context, existingAtSigns: atSigns);
  if (request == null || !context.mounted) return;

  final authRequest = AtAuthRequest(
    request.atSign,
    atKeysIo: KeychainAtKeysIo(),
    rootDomain: request.rootDomain,
  );
  final response = await PkamDialog.show(
    context,
    request: authRequest,
    backupKeys: [KeychainAtKeysIo()],
  );
  if (response?.isSuccessful == true) await _setupAtClient(authRequest, response!);
}
```

### Post-Auth Setup (required after all flows)

```dart
Future<void> _setupAtClient(AuthRequest authRequest, AuthResponse response) async {
  final dir = await getApplicationSupportDirectory();

  final acp = AtClientPreference()
    ..rootDomain      = authRequest.rootDomain.rootDomain
    ..rootPort        = authRequest.rootDomain.rootPort
    ..namespace       = 'todos_app'       // your app namespace
    ..commitLogPath   = dir.path
    ..hiveStoragePath = dir.path;

  await AtClientManager.getInstance().setCurrentAtSign(
    response.atSign,
    'todos_app',
    acp,
    enrollmentId: response.enrollmentId,
    atChops:  response.atChops,
    atLookUp: response.atLookUp,
  );
}
```

After setup, retrieve `AtClient` wherever you need it:

```dart
final atClient = AtClientManager.getInstance().atClient;
```

---

## 4. Get an AtCollection for Todos

Call `atClient.collection(...)` — never construct `AtCollection` directly.

```dart
import 'package:at_client/at_client.dart';

final todos = await atClient.collection<Todo>(
  'todos.todos_app',              // namespace — MUST contain '.'; suffix matches AtClientPreference.namespace
  const Duration(days: 365),     // default expiration for new todos
  fromJson: Todo.fromJson,        // auto-registers the factory
  typeTag: 'Todo',                // must be a string literal
  cleanupOrphansOnCreation: true, // recommended — sweeps expired sub-items at startup
  eventSource: EventSource.both,  // default; receives both local writes and cross-atSign notifications
);
```

**Rules:**
- The namespace must contain `.` — `ArgumentError` is thrown otherwise.
- `typeTag` is mandatory when `fromJson` is supplied.
- The collection is cached per `(namespace, eventSource)` pair — the same call twice returns the same instance.

---

## 5. Create a Todo

### Create for yourself only

```dart
final item = await todos.create(
  obj: Todo(title: 'Buy milk', description: 'From the corner shop'),
);
```

### Create and share with other atSign users

Pass a `sharedWith` set containing the recipient atSigns. The atProtocol
encrypts each recipient copy end-to-end — the atServer never sees the plaintext.

```dart
final item = await todos.create(
  obj: Todo(
    title: 'Plan team lunch',
    description: 'Venue TBD',
    dueDate: DateTime.now().add(const Duration(days: 3)),
  ),
  sharedWith: {'@alice'.toAtsign(), '@bob'.toAtsign()},
);
```

`create` is strict — it throws `StateError` if the generated or supplied `id` already
exists. Use `upsert` instead if you need idempotent / re-runnable writes:

```dart
await todos.upsert(
  id: 'my-stable-id',
  obj: Todo(title: 'Buy milk', description: 'Skimmed'),
  sharedWith: {'@alice'.toAtsign()},
);
```

---

## 6. Read Todos

```dart
// All todos visible to this atSign (own + received)
final all = await todos.getItems();

// Only your own todos
final mine = await todos.getItems(owner: atClient.atSign);

// A specific todo by id (throws if not found)
final one = await todos.get('abc123', atClient.atSign);

// A specific todo by id (returns null if not found)
final maybeOne = await todos.getOrNull('abc123', atClient.atSign);
```

---

## 7. Update a Todo

```dart
// Mutate the object, then call update to persist
item.obj.done = true;
await todos.update(item);

// Change who it is shared with (without rewriting the item value)
await todos.updateSharedWith(item, {'@alice'.toAtsign(), '@carol'.toAtsign()});
```

---

## 8. Delete a Todo

```dart
await todos.delete(item);                // throws StateError if item has sub-items
await todos.delete(item, cascade: true); // removes all sub-items first, then the item
```

---

## 9. React to Changes in Real Time

`AtCollection` exposes event streams so your UI can react without polling.

```dart
class _TodoListState extends State<TodoList> {
  late StreamSubscription<CItemUpdated> _sub;

  @override
  void initState() {
    super.initState();
    _sub = todos.updates.listen((_) => setState(() {}));
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
```

Available streams:

| Stream | What it fires |
|--------|--------------|
| `todos.updates` | `CItemUpdated` — item created or updated |
| `todos.deletes` | `CItemDeleted` — item deleted (`wasExpired` flag available) |
| `todos.readReceipts` | `CReadReceipt` — a recipient read your todo |
| `todos.subUpdates` | `CSubItemUpdated` — a sub-item (e.g. a note on a todo) changed |

---

## 10. Query Todos

Queries are immutable — each modifier returns a new `Query<T>`. Execution is on-device
(the atServer never sees your plaintext).

```dart
// Get all incomplete todos due before the end of today, sorted by due date
final upcoming = await todos.query()
    .where((t) => !t.obj.done && t.obj.dueDate != null &&
                  t.obj.dueDate!.isBefore(DateTime.now().add(const Duration(days: 1))))
    .orderBy((t) => t.obj.dueDate)
    .limit(20)
    .get();

// Live-updating stream for the same query
final stream = todos.query()
    .where((t) => !t.obj.done)
    .orderBy((t) => t.obj.dueDate)
    .watch();
```

---

## 11. Complete Minimal Example (putting it all together)

```dart
import 'package:flutter/material.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_client_flutter/extensions.dart';
import 'package:at_auth/at_auth.dart';
import 'package:path_provider/path_provider.dart';

// --- Domain object ---

class Todo {
  final String title;
  bool done;

  Todo(this.title, {this.done = false});

  factory Todo.fromJson(Map<String, dynamic> json) =>
      Todo(json['title'] as String, done: json['done'] as bool? ?? false);

  Map<String, dynamic> toJson() => {'title': title, 'done': done};
}

// --- Auth helper (call after a successful PkamDialog) ---

Future<void> _setupAtClient(AuthRequest authRequest, AuthResponse response) async {
  final dir = await getApplicationSupportDirectory();
  final acp = AtClientPreference()
    ..rootDomain      = authRequest.rootDomain.rootDomain
    ..rootPort        = authRequest.rootDomain.rootPort
    ..namespace       = 'todos_app'
    ..commitLogPath   = dir.path
    ..hiveStoragePath = dir.path;

  await AtClientManager.getInstance().setCurrentAtSign(
    response.atSign, 'todos_app', acp,
    enrollmentId: response.enrollmentId,
    atChops:  response.atChops,
    atLookUp: response.atLookUp,
  );
}

// --- Collection + CRUD ---

Future<void> runTodoDemo() async {
  final atClient = AtClientManager.getInstance().atClient;

  final todos = await atClient.collection<Todo>(
    'todos.todos_app',
    const Duration(days: 365),
    fromJson: Todo.fromJson,
    typeTag: 'Todo',
  );

  // Create a private todo
  final item = await todos.create(obj: Todo('Buy milk'));

  // Create a todo shared with @bob
  await todos.create(
    obj: Todo('Plan lunch'),
    sharedWith: {'@bob'.toAtsign()},
  );

  // Mark done and persist
  item.obj.done = true;
  await todos.update(item);

  // Read all your todos
  final all = await todos.getItems(owner: atClient.atSign);
  for (final t in all) {
    print('${t.id}: ${t.obj.title} (done=${t.obj.done})');
  }
}
```

---

## Summary

| Step | What to use |
|------|------------|
| Add packages | `at_client: ^3.12.0`, `at_client_flutter: ^1.1.2`, `at_auth: ^3.1.0`, `path_provider: ^2.0.0` |
| Authenticate | `AtKeysFileDialog` + `PkamDialog` + `_setupAtClient(...)` |
| Get collection | `atClient.collection<Todo>('todos.todos_app', ttl, fromJson: ..., typeTag: 'Todo')` |
| Create (private) | `todos.create(obj: Todo('...'))` |
| Create (shared) | `todos.create(obj: ..., sharedWith: {'@alice'.toAtsign()})` |
| Read | `todos.getItems()` / `todos.get(id, owner)` |
| Update | mutate `item.obj`, then `todos.update(item)` |
| Delete | `todos.delete(item)` |
| React to changes | `todos.updates.listen(...)` in `initState`, cancel in `dispose` |

**Never use** `AtCollectionModel` — it is deprecated. Always use `AtCollection<T>` via `atClient.collection(...)`.
