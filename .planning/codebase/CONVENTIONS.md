# Coding Conventions

**Analysis Date:** 2026-02-03

## Naming Patterns

**Files:**
- Snake case for files: `sync_service_impl.dart`, `at_notification.dart`, `logger_util.dart`
- Implementation files suffix with `_impl`: `sync_service_impl.dart`, `at_auth_impl.dart`, `at_onboarding_service_impl.dart`
- Test files suffix with `_test.dart`: `sync_service_test.dart`, `at_client_impl_test.dart`
- Utility files suffix with `_util.dart`: `logger_util.dart`, `encryption_util.dart`, `sync_util.dart`
- Converters/transformers in dedicated directories: `src/converters/encryption/aes_converter.dart`, `src/response/response_parser.dart`

**Functions:**
- Camel case: `createRandomString()`, `getAtChops()`, `encryptStream()`, `_getAESKeyForEncryption()`
- Private functions prefixed with underscore: `_getAESKeyForEncryption()`, `_scheduleSyncRun()`, `_addProgress()`
- Factory methods use `create()` static methods: `AtAuth.create()`, `SyncService.create()`
- Getter/setter style: `getCurrentAtSign()`, `getPreferences()`, `getLocalSecondary()`
- Async functions use async naming convention (no special suffix): `authenticate()`, `onboard()`, `enroll()`

**Variables:**
- Camel case: `currentAtSign`, `atSign`, `atClientManager`, `mockNotificationService`
- Type-prefixed where helpful: `mockAtClient`, `fakeAtKey`, `mockRemoteSecondary` (in tests)
- Final/immutable variables follow camel case: `localCommitId`, `atClientInstanceMap`

**Types:**
- Pascal case: `AtClient`, `SyncService`, `AtNotification`, `AtAuthResponse`
- Exception classes: `AtAuthenticationException`, `AtKeysFileExistsException`, `AtKeyException`
- Builder classes: `UpdateVerbBuilder`, `DeleteVerbBuilder`, `SyncVerbBuilder`
- Interface/abstract base classes use clear suffixes: `Interface` (rare) or no suffix with descriptive names
- Mixin classes follow Pascal case: Standard Dart conventions

**Constants:**
- Upper snake case: `encryptedSharedKeyMatcher`, `syncRequestThreshold`, `queueSize`
- Class-level static constants: `static int syncRequestThreshold = 3`

## Code Style

**Formatting:**
- Dart's built-in formatter used: `dart format`
- 80-character line limit (standard Dart)
- Indentation: 2 spaces per level

**Linting:**
- Analyzer: Dart's built-in analyzer with custom rules in `analysis_options.yaml`
- Linting tool: `lints` package (v6.0.0) with recommended rules enabled
- Key lint rules enforced:
  - `camel_case_types: true` - Type names must be PascalCase
  - `unnecessary_string_interpolations: true` - No string interpolations for single variables
  - `await_only_futures: true` - Only await actual futures
  - `unawaited_futures: true` - Flag unawaited futures (must use `unawaited()` or comment)
  - `depend_on_referenced_packages: false` - Some transitive deps allowed

**Code Metrics** (via dart_code_metrics):
- Cyclomatic complexity limit: 20
- Maximum nesting level: 5
- Number of parameters limit: 4
- Source lines of code limit: 50 per method
- Anti-patterns checked: long-method, long-parameter-list

**Dart Code Quality Rules:**
- `no-boolean-literal-compare` - Don't compare booleans to true/false
- `no-empty-block` - Avoid empty code blocks
- `prefer-conditional-expressions` - Use ternary operators where readable
- `no-equal-then-else` - Don't have identical then and else blocks

## Import Organization

**Order:**
1. Dart imports (standard library): `import 'dart:async';`, `import 'dart:io';`
2. Package imports (pub.dev): `import 'package:at_commons/at_builders.dart';`
3. Relative imports (local files): `import 'package:at_client/src/service/sync_service_impl.dart';`

**Path Aliases:**
- No path aliases (monorepo uses workspace resolution)
- Imports always use full package paths: `package:at_client/src/`, `package:at_auth/src/`
- Workspace resolution configured in `pubspec.yaml`: `resolution: workspace`

**Import Best Practices:**
- Group imports by category with blank lines between
- Avoid circular imports by respecting layered architecture
- Use `show` to expose specific symbols when clarifying: `import 'package:test/test.dart' show test, expect;`
- Avoid `as` aliases except when disambiguating: `import 'package:at_client/src/response/at_notification.dart' as at_notification;`

Example from `sync_service_test.dart`:
```dart
import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/response/at_notification.dart' as at_notification;
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
```

## Error Handling

**Patterns:**
- Custom exception hierarchy extending `AtException` base class from `at_commons`
- Specific exceptions for different error scenarios: `AtAuthenticationException`, `AtKeysFileExistsException`, `AtKeyException`, `AtClientException`
- Exception chaining preserved (cause information maintained)
- Error handling via try/catch with specific exception types

**Throwing Exceptions:**
```dart
try {
  atAuthKeys = await atAuthRequest.atKeysIo!.read(atAuthRequest.atSign);
} on AtKeyException catch (e) {
  _addProgress(
    "authentication",
    "Unable to read keys for atSign: ${atAuthRequest.atSign}",
    ProgressEventType.error,
  );
  throw AtAuthenticationException(
    'Unable to read keys for atSign: ${atAuthRequest.atSign} | Cause: ${e.message}',
  );
}
```

**Logging Exceptions:**
```dart
on Exception catch (e, trace) {
  var cause = (e is AtException) ? e.getTraceMessage() : e.toString();
  _logger.finest(trace);
  _logger.severe('exception while running process sync. Reason: $cause');
  _syncInProgress = false;
}
```

**Null Coalescing in Initializers:**
- Use `??=` operator for lazy initialization: `atChops ??= _createAtChops(atAuthKeys);`
- Used to support testing with mocked objects

## Logging

**Framework:** `AtSignLogger` from `at_utils` package

**Logger Creation:**
```dart
late final AtSignLogger _logger;

// In constructor or initialization
_logger = AtSignLogger('SyncService (${_atClient.getCurrentAtSign()})');
```

**Logging Levels:**
- `finest()` - Detailed debugging information, method entry/exit
- `finer()` - Detailed diagnostic information
- `fine()` - General diagnostic information
- `config()` - Configuration-related messages
- `info()` - General informational messages
- `warning()` - Warning messages
- `severe()` - Error messages
- `shout()` - Critical errors

**Patterns:**
- Logger name includes component name and context: `'SyncService (@alice)'`, `'AtAuthServiceImpl'`
- Use string interpolation with variables: `'exception while running process sync. Reason: $cause'`
- Include relevant state in debug logs: commit IDs, key names, operation status
- Log exceptions with trace: `_logger.finest(trace)` for stack traces

**Extension Method for Context:**
```dart
extension AtClientLogging on AtSignLogger {
  String getLogMessageWithClientParticulars(
      AtClientParticulars atClientParticulars, String logMessage) {
    StringBuffer stringBuffer = StringBuffer();
    stringBuffer.write('${atClientParticulars.clientId}|');
    // ... adds app name, version, platform context
  }
}
```

## Comments

**When to Comment:**
- Complex algorithms with non-obvious logic
- Regex patterns: `// "^shared_key\..+@.+" matches the key that starts-with shared_key.<someone>@<me>`
- Important implementation notes and gotchas
- Integration points with other systems
- Server response interpretations

**JSDoc/Doc Comments:**
- Triple-slash comments (`///`) for public API documentation
- Single-line comments for context: `// Handle collision if target exists`
- Inline comments for non-obvious operations

Example from `sync_service_impl.dart`:
```dart
/// A local AtKey to persist the last received server commitId
late final AtKey _lastReceivedServerCommitIdAtKey;

/// A local AtKey to store skipDeletesUntil value
late final AtKey _skipDeletesUntilCommitId;

// "^shared_key\..+@.+" matches the key that starts-with shared_key.<someone>@<me>
// "@.+:shared_key@.+" matches the key that starts-with @<someone>:shared_key@<me>
@visibleForTesting
RegExp encryptedSharedKeyMatcher =
    RegExp(r'^shared_key\..+@.+|@.+:shared_key@.+');
```

## Function Design

**Size:** Functions kept under 50 lines of code (enforced via dart_code_metrics)

**Parameters:**
- Maximum 4 parameters (enforced via dart_code_metrics)
- Use named parameters for optional values
- Use builder pattern or config objects when many parameters needed

Example parameter pattern:
```dart
static Future<SyncService> create(AtClient atClient,
    {required AtClientManager atClientManager,
    RemoteSecondary? remoteSecondary}) async {
```

**Return Values:**
- Functions return specific, meaningful types (rarely generic `dynamic`)
- Factory methods return Future of the built type: `Future<SyncService>`
- Async operations always return Futures
- Void functions reserved for side-effect-only operations: `void scheduleCompactionJob()`

**Example Method Structure:**
```dart
Future<String> _getAESKeyForEncryption(String sharedWith) async {
  bool isSharedKeyInLocal = false;
  var sharedKey = await _getSharedKeyFromLocalForEncryption(sharedWith);
  if (sharedKey != null && sharedKey.isNotEmpty && sharedKey != 'data:null') {
    isSharedKeyInLocal = true;
  }
  // ... logic continues
  if (sharedKey == null || sharedKey == 'data:null') {
    logger.finer('Generated a new AES Key for $sharedWith');
  }
  return sharedKey;
}
```

## Module Design

**Exports:**
- Public API defined in package `lib/` root: `lib/at_auth.dart`, `lib/at_client.dart`
- Internal APIs in `lib/src/` are private to package
- Barrel files expose grouped functionality

**Barrel File Pattern:**
```dart
// lib/at_auth.dart (main export)
export 'src/at_auth_impl.dart';
export 'src/auth/cram_authenticator.dart';
export 'src/enroll/at_enrollment.dart';
export 'src/enroll/models/at_enrollment_request.dart';
// ... more exports
```

**Access Modifiers:**
- `@visibleForTesting` annotation marks APIs exposed only for testing: `@visibleForTesting late AtKeyDecryptionManager atKeyDecryptionManager;`
- Private members use underscore prefix: `late final AtSignLogger _logger;`
- Internal classes stay in `src/` and not exported

**Dependency Injection Pattern:**
- Services accept dependencies in constructors
- Allows mocking for testing
- Nullable optional dependencies initialized with `??=`: `atChops ??= _createAtChops(atAuthKeys);`

---

*Convention analysis: 2026-02-03*
