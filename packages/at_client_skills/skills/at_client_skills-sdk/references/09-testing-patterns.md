<!-- verified: at_client ^3.12.0 — update on next minor release -->

# Testing Patterns

`at_client` ships a test-only library that lets you unit-test collection-backed services
without a running atServer or network connection. Import it directly — it is intentionally
**not** re-exported from `at_client.dart`.

---

## Setup

Add `test` and `mocktail` as dev dependencies:

```yaml
dev_dependencies:
  test: ^1.24.0
  mocktail: ^1.0.0
```

Import the test hooks library in your test file:

```dart
import 'package:at_client/at_client.dart';
import 'package:at_client/src/collections/collections_test_hooks.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
```

---

## The Three Injection Functions

Each function builds an `AtCollection<T>` wired to injected streams instead of live
server connections. You own the `StreamController` and push events when you want them.

### `collectionWithInjectedNotifications` — `EventSource.notifs` path

```dart
final collection = collectionWithInjectedNotifications<T>(
  atClient,
  'namespace.my_app',
  const Duration(days: 7),
  notifications: notifController.stream,   // StreamController<AtNotification>.broadcast()
  fromJson: T.fromJson,
  typeTag: 'T',
);
```

Use this to test how your service reacts to incoming cross-atSign notifications.

### `collectionWithInjectedDataEvents` — `EventSource.data` path

```dart
final collection = collectionWithInjectedDataEvents<T>(
  atClient,
  'namespace.my_app',
  const Duration(days: 7),
  dataEvents: dataEventsController.stream,  // StreamController<DataEvent>.broadcast()
  fromJson: T.fromJson,
  typeTag: 'T',
);
```

Use this to test local write → event → UI update semantics (e.g., after a `create()`).

### `collectionWithInjectedBoth` — `EventSource.both` path

```dart
final collection = collectionWithInjectedBoth<T>(
  atClient,
  'namespace.my_app',
  const Duration(days: 7),
  notifications: notifController.stream,
  dataEvents: dataEventsController.stream,
  fromJson: T.fromJson,
  typeTag: 'T',
);
```

Use this to verify dual-emission and deduplication behaviour.

---

## Sub-collection Testing

```dart
final subColl = subCollectionWithInjectedNotifications<Parent, Child>(
  parentCollection,
  parentItem: parentItem,
  subName: 'replies',
  defaultExpiration: const Duration(days: 30),
  notifications: notifController.stream,
  fromJson: Child.fromJson,
  typeTag: 'Child',
);
```

---

## Minimal Test Template

```dart
import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/collections/collections_test_hooks.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtClient extends Mock implements AtClient {}
class FakeAtKey extends Fake implements AtKey {}

class Todo {
  final String title;
  bool done;
  Todo({required this.title, this.done = false});
  factory Todo.fromJson(Map<String, dynamic> json) =>
      Todo(title: json['title'] as String, done: json['done'] as bool? ?? false);
  Map<String, dynamic> toJson() => {'title': title, 'done': done};
}

void main() {
  setUpAll(() => registerFallbackValue(FakeAtKey()));

  late MockAtClient atClient;
  late StreamController<AtNotification> notifStream;
  late AtCollection<Todo> todos;

  final selfAtsign = '@alice'.toAtsign();

  setUp(() {
    clearFactoriesForTest();  // reset process-global factory registry between tests

    atClient = MockAtClient();
    notifStream = StreamController<AtNotification>.broadcast();

    when(() => atClient.atSign).thenReturn(selfAtsign);

    // Stub getAtKeys to return empty list by default
    when(() => atClient.getAtKeys(regex: any(named: 'regex')))
        .thenAnswer((_) async => []);

    todos = collectionWithInjectedNotifications<Todo>(
      atClient,
      'todos.my_app',
      const Duration(days: 7),
      notifications: notifStream.stream,
      fromJson: Todo.fromJson,
      typeTag: 'Todo',
    );
  });

  tearDown(() async {
    await notifStream.close();
  });

  test('emits CItemUpdated when a notification arrives', () async {
    // Arrange: listen for update events
    final events = <CItemUpdated>[];
    final sub = todos.updates.listen(events.add);

    // Act: push a synthetic notification into the stream.
    // AtNotification constructor: positional (id, key, from, to, epochMillis,
    //   messageType, isEncrypted), then named (value:, operation:, ...).
    // from/to are plain String, not Atsign.
    final notif = AtNotification(
      'notif-1',
      'abc12345.todos.my_app@bob',
      '@bob',    // String — not .toAtsign()
      '@alice',  // String — not .toAtsign()
      DateTime.now().millisecondsSinceEpoch,
      'key',     // messageType (required positional)
      false,     // isEncrypted (required positional)
      value: '{"type":"Todo","readBy":[],"obj":{"title":"Buy milk","done":false}}',
      operation: 'update',
    );
    notifStream.add(notif);

    await Future.delayed(Duration.zero); // let the async handler run

    // Assert
    expect(events, hasLength(1));
    expect(events.first.id, 'abc12345');

    await sub.cancel();
  });
}
```

---

## Key Helper Functions

### `clearFactoriesForTest()`

Resets the process-global factory registry to an empty state. Call in `setUp()` or
`tearDown()` to prevent cross-test pollution when different tests register different types:

```dart
setUp(() {
  clearFactoriesForTest();
  AtCollection.registerFactory<Todo>(Todo.fromJson, typeTag: 'Todo');
});
```

### `handleNotificationForTest(collection, notification)`

Directly routes a single `AtNotification` into the collection's notification handler.
Use when you want finer control than pushing to the broadcast stream:

```dart
await handleNotificationForTest(todos, myNotification);
```

### `handleDataEventForTest(collection, dataEvent)`

Directly routes a `DataEvent` into the collection's data-event handler (the
`EventSource.data` path):

```dart
await handleDataEventForTest(todos, myDataEvent);
```

### `clearMissingFactoryWarningsForTest()`

Clears the set of already-warned missing-factory type tags. Prevents log spam when a test
intentionally exercises the "unknown typeTag" path multiple times.

---

## Mocking `AtClient` for Read Operations

Collection read methods (`getItems`, `getOrNull`, etc.) call through to `atClient.get()`
and `atClient.getAtKeys()`. Stub these with `mocktail`:

```dart
// Return specific keys from getAtKeys
when(() => atClient.getAtKeys(regex: any(named: 'regex')))
    .thenAnswer((_) async => [AtKey.fromString('abc12345.todos.my_app@alice')]);

// Return a specific value from get
when(() => atClient.get(any())).thenAnswer((_) async {
  final v = AtValue();
  v.value = jsonEncode({
    'type': 'Todo',
    'readBy': <String>[],
    'obj': {'title': 'Buy milk', 'done': false},
  });
  v.metadata = Metadata()
    ..createdAt = DateTime.now().toUtc()
    ..expiresAt = DateTime.now().add(const Duration(days: 7));
  return v;
});
```

---

## Test File References in the SDK Repo

The SDK's own test suite demonstrates every pattern in detail:

| File | What it covers |
| ------ | ---------------- |
| `packages/at_client/test/at_collections_test.dart` | Core CRUD, factory registry, draft, basic events via `EventSource.notifs` |
| `packages/at_client/test/at_collections_query_test.dart` | `Query<T>` builder, `where`, `orderBy`, `watch`, `watchWithSub` |
| `packages/at_client/test/at_collections_data_events_test.dart` | `EventSource.data` path, local write → event |
| `packages/at_client/test/at_collections_events_both_test.dart` | `EventSource.both` dual-emission semantics |
| `packages/at_client/test/key_stream_collection_test.dart` | Sub-collections, cascade delete, `getDescendant` |

---

## Important Notes

- The test hooks file (`collections_test_hooks.dart`) is **NOT** exported from
  `at_client.dart` — you must import it by path. The `@visibleForTesting` annotation
  means production code that accidentally imports it gets an analyzer warning.
- `collectionWithInjectedNotifications` bypasses the cached-per-namespace instance
  management. Each call returns a fresh instance — safe for test isolation.
- Always call `clearFactoriesForTest()` in `setUp()` when your tests register factories,
  to prevent one test's registrations from bleeding into the next.
