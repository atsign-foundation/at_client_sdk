# Unit Testing an AtCollection-Backed Service Without a Live atServer

`at_client` ships a dedicated test-only library that lets you unit-test any service built on
`AtCollection<T>` with no network, no atServer process, and no authentication flow. You
inject synthetic streams in place of the live notification pipeline or data-event bus, then
push events to exercise your service logic.

---

## 1. Add Dev Dependencies

```yaml
dev_dependencies:
  test: ^1.24.0
  mocktail: ^1.0.0
```

---

## 2. Import the Test Hooks Library

The test hooks file is **not** re-exported from `at_client.dart`. You must import it by path:

```dart
import 'package:at_client/at_client.dart';
import 'package:at_client/src/collections/collections_test_hooks.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
```

The `@visibleForTesting` annotation on this library means any production code that
accidentally imports it will get an analyzer warning — so the boundary is enforced.

---

## 3. Choose the Right Injection Function

There are three factory functions, each corresponding to an `EventSource`:

| Function | EventSource path | Use when |
|---|---|---|
| `collectionWithInjectedNotifications` | `EventSource.notifs` | Testing reaction to incoming cross-atSign notifications |
| `collectionWithInjectedDataEvents` | `EventSource.data` | Testing local write → event → UI update (e.g., after `create()`) |
| `collectionWithInjectedBoth` | `EventSource.both` | Testing dual-emission or deduplication behaviour |

Each function takes a `StreamController` you own. You push events into it to simulate
server activity without any real network.

---

## 4. Mock AtClient

Collection read methods (`getItems`, `getOrNull`, `get`, `exists`) call through to
`atClient.get()` and `atClient.getAtKeys()`. Stub these with `mocktail`:

```dart
class MockAtClient extends Mock implements AtClient {}
class FakeAtKey extends Fake implements AtKey {}
```

Register the fallback value in `setUpAll`:

```dart
setUpAll(() => registerFallbackValue(FakeAtKey()));
```

Stub the methods your service calls:

```dart
// Default: nothing in the store
when(() => atClient.getAtKeys(regex: any(named: 'regex')))
    .thenAnswer((_) async => []);

// Or return a specific key for a targeted test
when(() => atClient.getAtKeys(regex: any(named: 'regex')))
    .thenAnswer((_) async => [AtKey.fromString('abc12345.todos.my_app@alice')]);

// Return a specific stored value
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

## 5. Prevent Cross-Test Factory Pollution

`AtCollection.registerFactory<T>()` is **process-global** — registrations persist across
tests in the same process. Always call `clearFactoriesForTest()` in `setUp()`:

```dart
setUp(() {
  clearFactoriesForTest();   // reset factory registry
  // Now register only the types this test needs
  AtCollection.registerFactory<Todo>(Todo.fromJson, typeTag: 'Todo');
});
```

If you skip this step, a registration from one test can bleed into the next and cause
confusing `StateError` failures.

---

## 6. Complete Test Template

This template covers the notification path (`EventSource.notifs`) — the most common case
when you want to verify that your service reacts correctly to incoming data.

```dart
import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/collections/collections_test_hooks.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

// ── Mocks ──────────────────────────────────────────────────────────────────

class MockAtClient extends Mock implements AtClient {}
class FakeAtKey extends Fake implements AtKey {}

// ── Domain object ──────────────────────────────────────────────────────────

class Todo {
  final String title;
  bool done;

  Todo({required this.title, this.done = false});

  factory Todo.fromJson(Map<String, dynamic> json) => Todo(
        title: json['title'] as String,
        done: json['done'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {'title': title, 'done': done};
}

// ── Tests ──────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() => registerFallbackValue(FakeAtKey()));

  late MockAtClient atClient;
  late StreamController<AtNotification> notifStream;
  late AtCollection<Todo> todos;

  final selfAtsign = '@alice'.toAtsign();

  setUp(() {
    clearFactoriesForTest(); // prevent cross-test factory pollution

    atClient = MockAtClient();
    notifStream = StreamController<AtNotification>.broadcast();

    when(() => atClient.atSign).thenReturn(selfAtsign);
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
    // Arrange
    final events = <CItemUpdated>[];
    final sub = todos.updates.listen(events.add);

    // Act — push a synthetic notification.
    // AtNotification constructor:
    //   positional: id, key, from, to, epochMillis, messageType, isEncrypted
    //   named:      value:, operation:, ...
    // from/to are plain String — NOT .toAtsign()
    final notif = AtNotification(
      'notif-1',
      'abc12345.todos.my_app@bob',
      '@bob',    // String, not Atsign
      '@alice',  // String, not Atsign
      DateTime.now().millisecondsSinceEpoch,
      'key',     // messageType
      false,     // isEncrypted
      value: jsonEncode({
        'type': 'Todo',
        'readBy': <String>[],
        'obj': {'title': 'Buy milk', 'done': false},
      }),
      operation: 'update',
    );
    notifStream.add(notif);

    await Future.delayed(Duration.zero); // let the async handler run

    // Assert
    expect(events, hasLength(1));
    expect(events.first.id, 'abc12345');
    expect((events.first.obj as Todo).title, 'Buy milk');

    await sub.cancel();
  });

  test('getItems returns stubbed keys and values', () async {
    // Stub the read path
    when(() => atClient.getAtKeys(regex: any(named: 'regex')))
        .thenAnswer((_) async => [
              AtKey.fromString('abc12345.todos.my_app@alice'),
            ]);

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

    final items = await todos.getItems();

    expect(items, hasLength(1));
    expect(items.first.obj.title, 'Buy milk');
  });
}
```

---

## 7. Testing the Data Events Path

If your service uses `EventSource.data` (local write → event → UI), swap to
`collectionWithInjectedDataEvents`:

```dart
late StreamController<DataEvent> dataEventsStream;
late AtCollection<Todo> todos;

setUp(() {
  clearFactoriesForTest();
  atClient = MockAtClient();
  dataEventsStream = StreamController<DataEvent>.broadcast();

  when(() => atClient.atSign).thenReturn('@alice'.toAtsign());
  when(() => atClient.getAtKeys(regex: any(named: 'regex')))
      .thenAnswer((_) async => []);

  todos = collectionWithInjectedDataEvents<Todo>(
    atClient,
    'todos.my_app',
    const Duration(days: 7),
    dataEvents: dataEventsStream.stream,
    fromJson: Todo.fromJson,
    typeTag: 'Todo',
  );
});

tearDown(() async => dataEventsStream.close());
```

---

## 8. Testing Both Event Sources

Use `collectionWithInjectedBoth` when you want to verify that your service handles
the `EventSource.both` dual-emission semantics (the same remote write can surface via
both the notification pipeline and the data pipeline):

```dart
todos = collectionWithInjectedBoth<Todo>(
  atClient,
  'todos.my_app',
  const Duration(days: 7),
  notifications: notifStream.stream,
  dataEvents: dataEventsStream.stream,
  fromJson: Todo.fromJson,
  typeTag: 'Todo',
);
```

---

## 9. Testing Sub-collections

```dart
final parentItem = todos.draft(obj: Todo(title: 'Parent'));

final notes = subCollectionWithInjectedNotifications<Todo, Note>(
  todos,
  parentItem: parentItem,
  subName: 'notes',
  defaultExpiration: const Duration(days: 30),
  notifications: notifStream.stream,
  fromJson: Note.fromJson,
  typeTag: 'Note',
);
```

---

## 10. Fine-grained Event Injection

Instead of pushing to the broadcast `StreamController`, you can route a single event
directly into the collection's handler — useful when you want synchronous-style control
without the broadcast stream's async delay:

```dart
// Notification path
await handleNotificationForTest(todos, myAtNotification);

// Data event path
await handleDataEventForTest(todos, myDataEvent);
```

---

## 11. Suppressing Log Noise in Unknown-TypeTag Tests

If a test intentionally exercises the "unknown typeTag" path multiple times, the SDK logs a
warning once per unique tag (to avoid spam in production). Call this helper to reset the
already-warned set so the log appears fresh each time:

```dart
clearMissingFactoryWarningsForTest();
```

---

## 12. Key Pitfalls

| Pitfall | Fix |
|---|---|
| `from`/`to` in `AtNotification` are plain `String` | Do NOT call `.toAtsign()` — pass `'@bob'`, not `'@bob'.toAtsign()` |
| Factory `StateError` across tests | Call `clearFactoriesForTest()` in every `setUp()` |
| `collectionWithInjected*` ignores the cached-per-namespace registry | Each call returns a fresh instance — safe for isolation, but do not mix with `atClient.collection()` calls in the same test |
| `typeTag` derived from `T.toString()` | Always use a string literal — minifier renames types in release builds |
| Missing `setUpAll(() => registerFallbackValue(FakeAtKey()))` | Add this if `mocktail` throws "No fake registered" for `AtKey` |

---

## 13. SDK Test Files to Study

The SDK's own test suite demonstrates every pattern:

| File | What it covers |
|---|---|
| `packages/at_client/test/at_collections_test.dart` | Core CRUD, factory registry, basic events via `EventSource.notifs` |
| `packages/at_client/test/at_collections_query_test.dart` | `Query<T>` builder, `where`, `orderBy`, `watch`, `watchWithSub` |
| `packages/at_client/test/at_collections_data_events_test.dart` | `EventSource.data` path, local write → event |
| `packages/at_client/test/at_collections_events_both_test.dart` | `EventSource.both` dual-emission semantics |
| `packages/at_client/test/key_stream_collection_test.dart` | Sub-collections, cascade delete, `getDescendant` |
