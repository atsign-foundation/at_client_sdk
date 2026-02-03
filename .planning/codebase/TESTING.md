# Testing Patterns

**Analysis Date:** 2026-02-03

## Test Framework

**Runner:**
- Test framework: `test` package v1.25.0
- Config file: No test configuration file needed (default behavior)
- Test discovery: Automatic from `test/` directory

**Assertion Library:**
- Built-in matchers and `expect()` from `test` package
- Custom matchers for domain-specific assertions

**Run Commands:**
```bash
# Run all tests (from package directory)
dart test

# Run all tests with concurrency=1 (REQUIRED - prevents Hive storage conflicts)
dart test --concurrency=1

# Watch mode for development
dart test --watch

# Verbose output
dart test --reporter expanded

# Run specific test file
dart test test/sync_service_test.dart

# Run test by name pattern
dart test -t "test name substring"

# Coverage report
dart test --concurrency=1 --coverage="coverage"

# Format coverage (after running tests with coverage)
dart run coverage:format_coverage --lcov --in=coverage --out=coverage.lcov --report-on=lib
```

**Important:** All tests must run with `--concurrency=1` due to Hive local storage conflicts. Running tests concurrently will cause unpredictable failures and file lock issues.

## Test File Organization

**Location:**
- Co-located with source: Tests in `test/` directory at package root
- Mirror source structure: Not required; files can be flat in `test/`
- Functional tests separate: `tests/at_functional_test/test/`, `tests/at_onboarding_cli_functional_tests/test/`

**Naming:**
- `*_test.dart` suffix: `sync_service_test.dart`, `at_client_impl_test.dart`, `at_onboarding_cli_test.dart`
- No underscore between package name and `_test`: `at_client_impl_test.dart` not `at_client_impl_test_test.dart`

**Structure:**
```
packages/at_client/
├── lib/
├── test/
│   ├── at_client_impl_test.dart
│   ├── sync_service_test.dart
│   ├── test_utils/
│   │   ├── test_utils.dart
│   │   └── no_op_services.dart
│   └── [other test files]
```

## Test Structure

**Suite Organization:**
```dart
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

void main() {
  group('A group of positive tests on sync service', () {
    var localCommitId = -1;

    setUp(() async {
      mockAtClient = MockAtClient();
      mockAtClientManager = MockAtClientManager();
      // ... initialize mocks
    });

    test('sync server changes to local', () async {
      registerFallbackValue(FakeSyncVerbBuilder());
      // ... test implementation
      expect(mockCommitLogStore.isNotEmpty, true);
    });
  });

  group('A group of tests to validate exception chaining', () {
    test('A test to validate server responds with AtTimeOutException', () async {
      // ... test implementation
    });
  });
}
```

**Patterns:**

1. **Group Organization:** Tests organized into logical groups with `group()` for related test cases
2. **Naming:** Descriptive group and test names starting with article "A": `'A test to verify...'`, `'A group of...'`
3. **setUp():** Runs before each test in the group to initialize mocks and state
4. **tearDown():** Runs after each test to clean up resources
5. **Variable Scope:** Variables can be declared at suite level but are scoped to group execution
6. **Async Tests:** Tests marked `async` for Future-returning code

## Mocking

**Framework:** `mocktail` package v1.0.4 (Dart replacement for mockito)

**Mock Class Patterns:**
```dart
// Simple mock extending Mock interface
class MockAtClient extends Mock implements AtClient {
  @override
  String? getCurrentAtSign() {
    return '@alice';
  }

  @override
  AtClientPreference getPreferences() {
    return AtClientPreference();
  }
}

// Mock with custom List behavior
class MockSecondaryKeyStore extends Mock implements SecondaryKeyStore {
  Map<String, AtData> localKeyStore = {
    'mobile.wavi': AtData()..data = '12345',
    'country.wavi': AtData()..data = 'India',
  };

  @override
  Future<AtData> get(key) async {
    return Future.value(localKeyStore[key]);
  }
}
```

**Fake Classes for Test Values:**
```dart
// Use Fake for types that need to be passed as arguments
class FakeSyncVerbBuilder extends Fake implements SyncVerbBuilder {}
class FakeUpdateVerbBuilder extends Fake implements UpdateVerbBuilder {}
class FakeAtKey extends Fake implements AtKey {}

// Register fallback values for stubbing
registerFallbackValue(FakeSyncVerbBuilder());
registerFallbackValue(FakeUpdateVerbBuilder());
registerFallbackValue(FakeAtKey());
```

**Stubbing Behavior:**
```dart
// Simple return value
when(() => mockAtClient.getCurrentAtSign())
    .thenReturn('@alice');

// Async return value
when(() => mockRemoteSecondary.executeVerb(any()))
    .thenAnswer((_) => Future.value('data:response'));

// Exception throwing
when(() => mockAtClient.get(any(that: LastReceivedServerCommitIdMatcher())))
    .thenAnswer((invocation) =>
        throw AtKeyNotFoundException('key is not found in keystore'));

// Custom matcher
when(() => mockAtClient.put(
        any(that: LastReceivedServerCommitIdMatcher()), any()))
    .thenAnswer((_) => Future.value(true));
```

**Custom Matchers:**
```dart
// Domain-specific matchers for complex stub conditions
class LastReceivedServerCommitIdMatcher extends Matcher {
  @override
  Description describe(Description description) =>
      description.add('matches lastreceivedservercommitid key');

  @override
  bool matches(item, Map matchState) {
    if (item is AtKey) {
      return item.key == 'lastreceivedservercommitid';
    }
    return false;
  }
}

// Usage in stubs
when(() => mockAtClient.put(
        any(that: LastReceivedServerCommitIdMatcher()), any()))
    .thenAnswer((_) => Future.value(true));
```

**What to Mock:**
- External dependencies: `AtClient`, `AtLookUp`, `RemoteSecondary`, `LocalSecondary`
- Service layer: `NotificationService`, `SyncService`, `EncryptionService`
- Storage: `SecondaryKeyStore`, `AtCommitLog`
- Network: `RemoteSecondary` and verb responses

**What NOT to Mock:**
- Data models: `AtKey`, `AtData`, `AtNotification`, `Metadata`
- Value objects: `CommitEntry`, `SyncResult`, `AtAuthResponse`
- Builders: Create real instances instead of mocking
- Utilities: Test with real implementations: `EncryptionUtil`, `SyncUtil`

## Fixtures and Factories

**Test Data:**
```dart
// Utility class for test data generation
class TestUtils {
  static String createRandomString(int length) {
    final String characters =
        '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_';
    return String.fromCharCodes(Iterable.generate(length,
        (index) => characters.codeUnitAt(Random().nextInt(characters.length))));
  }

  static Future<AtChops> getAtChops() async {
    AtEncryptionKeyPair atEncryptionKeyPair =
        AtChopsUtil.generateAtEncryptionKeyPair();
    AtPkamKeyPair atPkamKeyPair = AtChopsUtil.generateAtPkamKeyPair();
    AtChopsKeys atChopsKeys =
        AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair);
    atChopsKeys.selfEncryptionKey =
        AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
    atChopsKeys.apkamSymmetricKey =
        AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);

    return AtChopsImpl(atChopsKeys);
  }
}
```

**Location:**
- `test/test_utils/test_utils.dart` - Shared test utilities
- `test/test_utils/no_op_services.dart` - Empty/no-op service implementations
- `test/fake_registrar.dart` - Mock registrar for auth tests
- `test/config.yaml` - Test configuration (functional tests)

**Factory Pattern for Setup:**
```dart
setUp(() async {
  AtClientImpl.atClientInstanceMap.remove(atSign);
  AtClientManager.getInstance().removeAllChangeListeners();
});

tearDown(() async {
  AtClientImpl.atClientInstanceMap.remove(atSign);
  AtClientManager.getInstance().removeAllChangeListeners();
});
```

## Coverage

**Requirements:** No enforced coverage target (varies by package)

**View Coverage:**
```bash
# Generate coverage after running tests
dart test --concurrency=1 --coverage="coverage"

# Format and view coverage report
dart run coverage:format_coverage --lcov --in=coverage --out=coverage.lcov --report-on=lib

# View HTML report (if generated)
# Coverage reports can be opened in browsers or IDE coverage viewers
```

**Coverage Tracking:**
- `coverage: ^1.14.0` package used for coverage collection
- LCOV format for integration with CI/CD systems
- Coverage data directory: `coverage/` (in .gitignore)

## Test Types

**Unit Tests:**
- Scope: Individual classes and methods in isolation
- Location: `test/` directory within package
- Approach: Mock all external dependencies
- Speed: Fast (milliseconds per test)
- Example: `sync_service_test.dart`, `at_client_impl_test.dart`

**Integration Tests:**
- Scope: Multiple components working together
- Location: `test/` directory (marked with integration comments if needed)
- Approach: Real service instances, mocked external APIs
- Speed: Moderate (seconds per test)
- Example: Encryption service tests that use real AtChops

**End-to-End Tests:**
- Scope: Full authentication and client operations
- Location: `tests/at_functional_test/` and `tests/at_end2end_test/`
- Framework: Docker Compose with real atServer
- Speed: Slow (minutes for full suite)
- Approach: Real servers, no mocking
- Commands:
  ```bash
  cd tests/at_functional_test
  ./runLocal.sh  # Automated Docker + tests
  # OR manually:
  docker compose -f test/docker-compose.yaml up -d
  dart run test/check_docker_readiness.dart
  docker exec test-virtualenv-1 supervisorctl start pkamLoad
  dart test --concurrency=1 -r expanded
  docker compose -f test/docker-compose.yaml down
  ```

## Common Patterns

**Async Testing:**
```dart
test('sync server changes to local', () async {
  registerFallbackValue(FakeSyncVerbBuilder());

  when(() => mockAtClient.put(any(), any()))
      .thenAnswer((_) => Future.value(true));

  var serverCommitId = 2;
  var syncRequest = SyncRequest()..result = SyncResult();

  await syncServiceImpl.syncInternal(serverCommitId, syncRequest);

  expect(mockCommitLogStore.isNotEmpty, true);
});
```

**Exception Testing:**
```dart
test('A test to validate server responds with AtTimeOutException', () async {
  when(() => mockRemoteSecondary.executeVerb(any()))
      .thenThrow(AtTimeOutException('timeout'));

  expect(
    () async => await syncServiceImpl.syncInternal(2, SyncRequest()),
    throwsA(isA<AtTimeOutException>()),
  );
});

// Or with custom matcher
expect(
  () => mockAtClient.get(any(that: LastReceivedServerCommitIdMatcher())),
  throwsA(isA<AtKeyNotFoundException>()),
);
```

**Stream Testing:**
```dart
test('notification stream emits updates', () async {
  final controller = StreamController<AtNotification>();

  when(() => mockNotificationService.subscribe(regex: any(named: 'regex')))
      .thenReturn(controller.stream);

  final subscription = service.subscribe().listen((notification) {
    expect(notification.key, 'test_key');
  });

  controller.add(AtNotification(/* data */));

  await subscription.cancel();
  await controller.close();
});
```

**Argument Verification:**
```dart
// Verify method was called
verify(() => mockAtClient.put(any(), any())).called(1);

// Verify with specific arguments
verify(() => mockAtClient.put(
    any(that: LastReceivedServerCommitIdMatcher()),
    'expected_value'
)).called(1);

// Verify never called
verifyNever(() => mockAtClient.delete(any()));
```

**Setup/Teardown Cleanup:**
```dart
setUp(() async {
  // Initialize for each test
  AtClientImpl.atClientInstanceMap.remove(atSign);
  AtClientManager.getInstance().removeAllChangeListeners();
});

tearDown(() async {
  // Cleanup after each test
  AtClientImpl.atClientInstanceMap.remove(atSign);
  AtClientManager.getInstance().removeAllChangeListeners();

  // Release resources
  await tearDownFunc();  // Custom cleanup function
});
```

## Test Best Practices

1. **Concurrency Setting:** Always run with `--concurrency=1` to avoid Hive storage conflicts
2. **Test Isolation:** Each test should be independent; don't rely on test execution order
3. **Mock Reset:** Call `reset()` on mocks in setUp to ensure clean state
4. **Explicit Fallback Values:** Register fallback values for all stub arguments: `registerFallbackValue(FakeSyncVerbBuilder())`
5. **Meaningful Test Names:** Use descriptive names starting with "A test to..." to clarify intent
6. **Single Assertion Focus:** While multiple assertions are acceptable, each test should focus on one behavior
7. **No Test Dependencies:** Avoid tests that depend on other tests running first
8. **Matcher Specificity:** Use custom matchers for complex conditions instead of generic `any()`
9. **Resource Cleanup:** Always clean up resources in tearDown (close streams, stop crons)
10. **Mock Complex Objects:** Only mock what's necessary; prefer real instances for value objects

## Running Tests in CI/CD

**CI Workflow Integration:**
```bash
# Full test suite with coverage
dart analyze
dart format . -o none --set-exit-if-changed
dart test --concurrency=1 --coverage="coverage"
dart run coverage:format_coverage --lcov --in=coverage --out=coverage.lcov --report-on=lib
```

**Functional Test Execution:**
```bash
# Setup Docker environment
docker compose -f tests/at_functional_test/test/docker-compose.yaml up -d
dart run tests/at_functional_test/test/check_docker_readiness.dart

# Run functional tests
dart test tests/at_functional_test/test --concurrency=1 -r expanded

# Cleanup
docker compose -f tests/at_functional_test/test/docker-compose.yaml down
```

---

*Testing analysis: 2026-02-03*
