# Unit Testing AtCollection-Backed Services Without a Real atServer

Testing services that depend on `AtCollection` (from the `at_collections` package) without spinning up a real atServer requires mocking or faking the underlying `AtClient` and related collaborators. This guide walks through the patterns and tools available.

## Core Concept

`AtCollection` ultimately delegates all persistence operations to an `AtClient` instance. The key to unit testing is to replace the real `AtClient` with a mock or fake so that no network calls are made and no atServer is needed.

---

## 1. Add Test Dependencies

In your `pubspec.yaml`:

```yaml
dev_dependencies:
  test: ^1.24.0
  mocktail: ^1.0.0   # or mockito: ^5.4.0 with build_runner
```

---

## 2. Mock the AtClient

### Using `mocktail`

```dart
import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';

class MockAtClient extends Mock implements AtClient {}
class MockAtClientManager extends Mock implements AtClientManager {}
```

### Using `mockito`

```dart
import 'package:mockito/annotations.dart';
import 'package:at_client/at_client.dart';

@GenerateMocks([AtClient, AtClientManager])
void main() {}
```

Then run `dart run build_runner build` to generate the mock classes.

---

## 3. Stub the Key AtClient Methods

`AtCollection` uses these `AtClient` methods internally:

| Method | Purpose |
|---|---|
| `put(AtKey, value)` | Persists a record |
| `get(AtKey)` | Retrieves a record |
| `delete(AtKey)` | Removes a record |
| `getKeys({regex})` | Lists matching keys |
| `notify(...)` | Sends notifications (sharing) |

Stub them to return controlled values:

```dart
final mockClient = MockAtClient();

// Stub put
when(() => mockClient.put(any(), any()))
    .thenAnswer((_) async => true);

// Stub get
when(() => mockClient.get(any()))
    .thenAnswer((_) async => AtValue()..value = '{"id":"1","name":"Alice"}');

// Stub getKeys
when(() => mockClient.getKeys(regex: any(named: 'regex')))
    .thenAnswer((_) async => ['cached:@alice:collection_item.0.myapp@alice']);

// Stub delete
when(() => mockClient.delete(any()))
    .thenAnswer((_) async => true);
```

---

## 4. Inject the Mock into Your Service

Your service should accept `AtClient` (or `AtClientManager`) via constructor injection so it can be replaced in tests:

```dart
// Production code
class TodoService {
  final AtCollection<Todo> _collection;

  TodoService(AtClient atClient)
      : _collection = AtCollection(
          Todo.fromJson,
          atClient: atClient,
          collectionName: 'todos',
        );

  Future<void> addTodo(Todo todo) => _collection.put(todo);
  Future<List<Todo>> fetchAll() => _collection.getAll();
}
```

```dart
// Test code
void main() {
  late MockAtClient mockClient;
  late TodoService service;

  setUp(() {
    mockClient = MockAtClient();
    service = TodoService(mockClient);
  });

  test('addTodo calls put on the collection', () async {
    when(() => mockClient.put(any(), any())).thenAnswer((_) async => true);

    final todo = Todo(id: '1', title: 'Write tests');
    await service.addTodo(todo);

    verify(() => mockClient.put(any(), any())).called(1);
  });
}
```

---

## 5. Use a Fake In-Memory AtClient

For more integration-style unit tests, implement a lightweight in-memory `AtClient` fake instead of a mock. This avoids setting up stub expectations for every call:

```dart
class FakeAtClient extends Fake implements AtClient {
  final Map<String, String> _store = {};

  @override
  Future<bool> put(AtKey key, dynamic value,
      {PutRequestOptions? putRequestOptions}) async {
    _store[key.toString()] = value.toString();
    return true;
  }

  @override
  Future<AtValue> get(AtKey key,
      {GetRequestOptions? getRequestOptions}) async {
    final raw = _store[key.toString()];
    if (raw == null) throw AtKeyNotFoundException('Key not found');
    return AtValue()..value = raw;
  }

  @override
  Future<List<String>> getKeys({
    String? regex,
    String? sharedBy,
    String? sharedWith,
    bool showHiddenKeys = false,
  }) async {
    if (regex == null) return _store.keys.toList();
    final pattern = RegExp(regex);
    return _store.keys.where((k) => pattern.hasMatch(k)).toList();
  }

  @override
  Future<bool> delete(AtKey key,
      {DeleteRequestOptions? deleteRequestOptions}) async {
    _store.remove(key.toString());
    return true;
  }
}
```

Use it in tests:

```dart
void main() {
  late FakeAtClient fakeClient;
  late TodoService service;

  setUp(() {
    fakeClient = FakeAtClient();
    service = TodoService(fakeClient);
  });

  test('round-trip: add then fetch', () async {
    final todo = Todo(id: '42', title: 'Buy milk');
    await service.addTodo(todo);

    final results = await service.fetchAll();
    expect(results, hasLength(1));
    expect(results.first.title, equals('Buy milk'));
  });
}
```

---

## 6. Handling AtClientManager.getInstance()

If your code calls `AtClientManager.getInstance().atClient`, you need to stub the manager too. Prefer injecting `AtClient` directly. If refactoring is not immediately possible, use a static override pattern:

```dart
// In your service, introduce a getter that can be overridden in tests:
AtClient get atClient => _atClient ?? AtClientManager.getInstance().atClient;
```

Or use a dependency-injection wrapper around `AtClientManager`:

```dart
class MockAtClientManager extends Mock implements AtClientManager {}

final mockManager = MockAtClientManager();
final mockClient = MockAtClient();

when(() => mockManager.atClient).thenReturn(mockClient);
AtClientManager.getInstance = () => mockManager; // if the SDK allows it
```

Note: `AtClientManager.getInstance()` is a static method, so direct mocking is not possible without refactoring. Prefer constructor injection.

---

## 7. Testing Notification / Sharing Paths

If your service uses `AtCollection.share()` or `AtCollection.unshare()`, stub `notify`:

```dart
when(() => mockClient.notify(
      any(),
      waitForFinalDeliveryStatus: any(named: 'waitForFinalDeliveryStatus'),
      checkForFinalDeliveryStatus:
          any(named: 'checkForFinalDeliveryStatus'),
    )).thenAnswer((_) async => 'notification-id-123');
```

---

## 8. Testing Error Scenarios

Simulate server errors to verify your service handles them gracefully:

```dart
test('fetchAll handles AtKeyNotFoundException gracefully', () async {
  when(() => mockClient.getKeys(regex: any(named: 'regex')))
      .thenThrow(AtKeyNotFoundException('No keys found'));

  final result = await service.fetchAll();
  expect(result, isEmpty);
});

test('addTodo propagates AtClientException', () async {
  when(() => mockClient.put(any(), any()))
      .thenThrow(AtClientException('Network error', null));

  expect(() => service.addTodo(Todo(id: '1', title: 'Fail')),
      throwsA(isA<AtClientException>()));
});
```

---

## 9. Example: Complete Test File

```dart
// test/todo_service_test.dart
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:at_client/at_client.dart';
import '../lib/todo_service.dart';
import '../lib/models/todo.dart';

class MockAtClient extends Mock implements AtClient {}

void main() {
  late MockAtClient mockClient;
  late TodoService service;

  setUpAll(() {
    registerFallbackValue(AtKey());
  });

  setUp(() {
    mockClient = MockAtClient();
    service = TodoService(mockClient);
  });

  group('TodoService', () {
    test('addTodo persists the item', () async {
      when(() => mockClient.put(any(), any()))
          .thenAnswer((_) async => true);

      await service.addTodo(Todo(id: '1', title: 'Learn atSign'));

      verify(() => mockClient.put(any(), any())).called(1);
    });

    test('fetchAll returns deserialized todos', () async {
      when(() => mockClient.getKeys(regex: any(named: 'regex')))
          .thenAnswer((_) async =>
              ['cached:@alice:todos.1.myapp@alice']);

      when(() => mockClient.get(any())).thenAnswer((_) async =>
          AtValue()..value = '{"id":"1","title":"Learn atSign"}');

      final todos = await service.fetchAll();

      expect(todos, hasLength(1));
      expect(todos.first.title, 'Learn atSign');
    });

    test('deleteTodo calls delete on the client', () async {
      when(() => mockClient.delete(any()))
          .thenAnswer((_) async => true);

      await service.deleteTodo('1');

      verify(() => mockClient.delete(any())).called(1);
    });
  });
}
```

---

## Summary

| Approach | Best For |
|---|---|
| `Mock` (mocktail / mockito) | Verifying exact interactions and call counts |
| `Fake` (in-memory implementation) | Integration-style logic tests without expectations overhead |
| Constructor injection | Decouples service from static `AtClientManager` |
| Stub error throws | Testing error-handling paths |

The key principle is: **never let your unit tests touch a real `AtClient` transport layer**. By injecting `AtClient` and stubbing or faking its methods, your tests run fast, deterministically, and offline.
