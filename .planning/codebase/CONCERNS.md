# Codebase Concerns

**Analysis Date:** 2026-02-03

## Tech Debt

### SHA512 Password Hashing Type Mismatch
- **Issue:** Type interface mismatch in password encryption for passphrase-protected keys
- **Files:** `packages/at_chops/lib/src/algorithm/default_hashing_algo.dart`, `packages/at_chops/lib/src/at_keys_crypto.dart:110-114`
- **Impact:** Production deployments using passphrase + SHA512 hashing fail due to type signature mismatch. Tests must use Argon2id as workaround.
- **Fix approach:** Create `SHA512PasswordHashingAlgo` class implementing `AtHashingAlgorithm<String, String>` interface that converts String to bytes internally before hashing.
- **Workaround:** Use `HashingAlgoType.argon2id` instead of `sha512Password` in `packages/at_onboarding_cli/test/at_keys_file_io_test.dart:169-170`

### Incomplete Sync Error Handling in SyncService
- **Issue:** FormatException caught in sync progress listener with unclear recovery path
- **Files:** `packages/at_client/lib/src/service/sync_service_impl.dart:154-156`
- **Impact:** Comment indicates uncertainty about when/why FormatException occurs and what correct behavior should be. Error is logged but recovery is unclear.
- **Fix approach:** Add unit tests for edge cases that trigger FormatException, document expected conditions, implement explicit recovery strategy (retry vs abort vs fallback).
- **Current behavior:** Exception is caught and wrapped in SyncProgress with failure status, but root cause is not well-understood.

### Stream Closure Bug in NotificationService
- **Issue:** Stream closure logic has syntax error preventing proper cleanup
- **Files:** `packages/at_client/lib/src/service/notification_service_impl.dart:176`
- **Current code:** `if (!streamController.isClosed) () => streamController.close();`
- **Impact:** StreamController is not actually closed due to lambda not being invoked. This causes resource leaks when switching atSigns or stopping notifications.
- **Fix approach:** Change to `if (!streamController.isClosed) streamController.close();` to actually call the close() method.
- **Risk:** Resource leaks in long-running applications and mobile apps with multi-atSign support.

### Persistent Local Secondary Keys Backup TODO
- **Issue:** Duplicate key storage in local secondary planned for removal
- **Files:** `packages/at_onboarding_cli/lib/src/onboard/at_onboarding_service_impl.dart:837-860`
- **Current behavior:** Keys backed up to local secondary (`_persistKeysLocalSecondary()`) as temporary measure while migration to AtChops key management is pending.
- **Fix approach:** Complete migration to read all keys from AtChops, then remove `_persistKeysLocalSecondary()` method entirely. Requires updating key retrieval logic throughout codebase.
- **Timeline:** Marked as future cleanup, no immediate deadline specified.

### Code Duplication in CLI Interactive Mode
- **Issue:** Shared command parsing logic duplicated between interactive and main CLI functions
- **Files:** `packages/at_onboarding_cli/lib/src/cli/auth_cli.dart:608`
- **Impact:** Bug fixes and feature additions to CLI must be applied in two places, increasing maintenance burden.
- **Fix approach:** Extract shared command processing logic into utility function, use from both `main()` and `interactive()` entry points.

## Known Bugs

### Keychain Storage Segmentation Legacy Bug
- **Issue:** Legacy fallback for keychain storage uses package name as segment prefix, which is inconsistent with new implementation
- **Symptoms:** Keychain data may not be retrieved correctly when reading data created with old segment prefix format
- **Files:** `packages/at_client_flutter/lib/src/keychain/keychain_storage.dart:220-236`
- **Details:** Code infers `segmentPrefix = '${packageName}_data'` for legacy data, but modern code uses `'${keychainStoreName}_segment'`. This causes data compatibility issues.
- **Workaround:** Data migration path exists but requires manual intervention in some cases.
- **Risk:** Silent data loss in Flutter apps upgrading from older versions.

## Deprecated Features Pending Removal

### AtClientPreference enforceNamespace Flag
- **Status:** Marked for removal in next major version
- **Files:** `packages/at_client/lib/src/preference/at_client_preference.dart:115`
- **Current behavior:** When true, rejects keys without namespace; when false, accepts unnamespaced keys
- **Migration path:** Applications should always use namespaced keys. Setting to false is deprecated.
- **Impact:** Requires major version bump to remove this boolean.

### AtClientPreference useAtChops Flag
- **Status:** Deprecated, ignored in current implementation
- **Files:** `packages/at_client/lib/src/preference/at_client_preference.dart:121`
- **Details:** Variable has no effect. AtChops is always used for cryptography.
- **Cleanup:** Safe to remove in next major version.

### AtClientPreference atProtocolEmitted Version
- **Status:** Deprecated, fully ignored
- **Files:** `packages/at_client/lib/src/preference/at_client_preference.dart:126`
- **Details:** Previously controlled encryption behavior, now has no effect.
- **Cleanup:** Safe to remove in next major version.

### Deprecated Stream/Monitoring APIs
- **Status:** Multiple deprecated methods pending removal in v4
- **Files:** `packages/at_client/lib/src/client/at_client_impl.dart:1017`
- **Affected methods:** `stream()`, `sendStreamAck()`, `startMonitor()`, deprecated `notify()`
- **Replacement:** Use `syncService` and `notificationService` instead
- **Impact:** These are low-usage legacy APIs; migration path is straightforward.

### Old SyncManager Pattern
- **Status:** Deprecated in favor of SyncService
- **Files:** `packages/at_client/lib/src/client/at_client_impl.dart`
- **Impact:** Apps still using `getSyncManager()` receive deprecation warnings. SyncService is recommended.

## Security Considerations

### Passphrase-Protected Keys Vulnerability
- **Risk:** If passphrase encryption is used with SHA512, keys fail to encrypt/decrypt properly due to type bug
- **Files:** `packages/at_chops/`, `packages/at_onboarding_cli/`
- **Current mitigation:** Argon2id can be used as alternative; SHA512 path is largely untested
- **Recommendations:**
  - Fix type signature bug in at_chops before any production use of passphrase+SHA512
  - Add integration tests covering passphrase encryption with multiple algorithms
  - Document which hashing algorithms are production-ready

### Missing Input Validation in Sync
- **Risk:** FormatException suggests unvalidated/unexpected data from server in sync process
- **Files:** `packages/at_client/lib/src/service/sync_service_impl.dart:154-170`
- **Current mitigation:** Exception is caught and logged, but root cause is not addressed
- **Recommendations:**
  - Add strict validation on server commit IDs before parsing
  - Document expected format and valid ranges
  - Add telemetry to track when this path is triggered

### Unvalidated Key Metadata in Local Secondary
- **Risk:** Keys backup to local secondary without namespace validation
- **Files:** `packages/at_onboarding_cli/lib/src/onboard/at_onboarding_service_impl.dart:837-860`
- **Current mitigation:** Keys are re-validated when retrieved from AtChops
- **Recommendations:**
  - Enforce namespace validation consistently at storage layer
  - Audit all local secondary write paths for consistency

## Performance Bottlenecks

### Large Test Files Indicate Complex Test Suites
- **Problem:** Very large test files suggest monolithic test structure
- **Files:**
  - `packages/at_client/test/sync_new_test.dart` (4,875 lines)
  - `packages/at_commons/test/at_key_test.dart` (1,296 lines)
  - `packages/at_onboarding_cli/lib/src/onboard/at_onboarding_service_impl.dart` (1,138 lines)
- **Cause:** Test suites have grown without refactoring into focused test classes
- **Improvement path:**
  - Break sync_new_test.dart into focused test files by feature (push tests, pull tests, conflict resolution, etc.)
  - Extract common test utilities into shared fixtures
  - Consider parameterized tests for repetitive scenarios

### Sync Service Cron Scheduling
- **Problem:** Sync runs on fixed 5-second interval regardless of network/device state
- **Files:** `packages/at_client/lib/src/service/sync_service_impl.dart:93-96`
- **Current behavior:** `syncRunIntervalSeconds = 5` is hardcoded static variable
- **Improvement path:**
  - Make sync interval configurable per AtClient
  - Implement exponential backoff on failures
  - Add network state awareness (skip syncs when offline)
  - Add battery/thermal awareness for mobile platforms

### Regex Matching for Shared Key Detection
- **Problem:** Every sync loop evaluates regex patterns on all keys
- **Files:** `packages/at_client/lib/src/service/sync_service_impl.dart:56-58`
- **Pattern:** `RegExp(r'^shared_key\..+@.+|@.+:shared_key@.+')`
- **Improvement path:**
  - Cache compiled regex as field (already done via @visibleForTesting)
  - Consider prefix-based matching instead of full regex for hot path
  - Profile sync operation to quantify regex overhead

## Fragile Areas

### AtOnboardingServiceImpl - Monolithic Implementation
- **Files:** `packages/at_onboarding_cli/lib/src/onboard/at_onboarding_service_impl.dart` (1,138 lines)
- **Why fragile:**
  - Single class handles onboarding, authentication, enrollment, key storage, and APKAM operations
  - Multiple conditional branches for `authMode` (keysFile vs SIM vs HSM)
  - Complex state management across enum values and boolean flags
  - Limited test isolation due to tight coupling to file I/O and network operations
- **Safe modification:**
  - Add comprehensive unit tests for each auth mode before refactoring
  - Extract auth mode-specific logic into strategy classes
  - Create test doubles for file operations and AtLookUp communication
- **Test coverage gaps:**
  - APKAM enrollment flow with multiple key types not fully covered
  - Error recovery paths (network failures, partial writes) under-tested
  - Multi-step onboarding with cancellation scenarios lacking tests

### AuthCli - Complex Command Routing
- **Files:** `packages/at_onboarding_cli/lib/src/cli/auth_cli.dart` (1,130 lines)
- **Why fragile:**
  - 25+ subcommands with independent argument parsing
  - Error handling scattered across command implementations
  - Shared error recovery logic duplicated between main() and interactive()
  - Limited validation of argument combinations (e.g., mutual exclusivity)
- **Safe modification:**
  - Create test coverage for each command with valid/invalid arguments
  - Extract command factory to reduce main() complexity
  - Create shared command validation utility
- **Test coverage gaps:**
  - Interactive mode command loop error recovery not tested
  - Argument parsing edge cases (empty strings, special characters) under-tested
  - Cross-command state consistency (e.g., switching between enroll and approve)

### SyncServiceImpl - Complex State Machine
- **Files:** `packages/at_client/lib/src/service/sync_service_impl.dart` (1,126 lines)
- **Why fragile:**
  - Multiple overlapping boolean flags control sync state (`_syncInProgress`, `isSyncInProgress`)
  - Listeners can be added/removed during sync execution
  - Exception handling in stats notification listener with unclear semantics
  - Hard-coded static configuration values (syncRequestThreshold, syncRunIntervalSeconds)
- **Safe modification:**
  - Add explicit state machine (enum SyncState) instead of boolean flags
  - Create integration tests for listener lifecycle during sync
  - Add defensive checks before accessing listener collections
  - Document exception scenarios and recovery strategies
- **Test coverage gaps:**
  - Listener addition/removal during active sync not tested
  - Exception recovery in stats notification handler not covered
  - Cron scheduler cancellation and restart scenarios missing
  - Multi-threaded access to _syncRequests queue under-tested

### At_lookup - Socket Management
- **Files:** `packages/at_lookup/lib/src/at_lookup_impl.dart` (707 lines)
- **Why fragile:**
  - Socket lifecycle management across multiple authentication steps
  - Comment at line 342 indicates uncertainty about server migration compatibility
  - Connection state not explicitly tracked (relies on socket exceptions)
- **Safe modification:**
  - Add unit tests for socket creation/closure under various conditions
  - Document required migrations for different server versions
  - Create explicit connection state tracking
  - Test failure scenarios (premature socket closure, server hangs)

## Scaling Limits

### Hive Storage Concurrency
- **Limit:** Tests must run with `--concurrency=1` to avoid storage conflicts
- **Files:** Entire test suite (enforced in CI/CD)
- **Current capacity:** Single-threaded sequential test execution only
- **Scaling path:**
  - Implement per-test storage isolation (unique Hive database per test)
  - Migrate to more concurrent-safe storage backend
  - Add storage locking with timeouts for controlled concurrent access
  - Note: This is a testing infrastructure issue, not production code

### Monorepo Dependency Resolution
- **Limit:** Workspace uses `resolution: workspace` for internal dependencies
- **Files:** `pubspec.yaml` (root), multiple package `pubspec.yaml` files
- **Current capacity:** All packages must maintain API compatibility when workspace dependencies change
- **Scaling path:**
  - Consider semantic versioning for workspace packages
  - Implement deprecation periods for breaking changes
  - Document upgrade paths for dependent packages
  - Add validation in CI to catch workspace dependency breakage

### Multi-AtSign Storage
- **Limit:** Hive storage isolation per atSign required (separate directories `@alice/`, `@bob/`)
- **Current capacity:** Works fine for typical 2-4 atSigns per app
- **Scaling path:**
  - Profile Hive performance with 10+ atSigns
  - Consider storage backend change if performance degrades
  - Add metrics for storage size per atSign

## Test Coverage Gaps

### SyncService Listener Lifecycle
- **What's not tested:** Addition/removal of sync progress listeners during active sync
- **Files:** `packages/at_client/test/sync_new_test.dart`, `packages/at_client/lib/src/service/sync_service_impl.dart:180-188`
- **Risk:** Concurrent modification exceptions or missed progress updates
- **Priority:** High - affects production user experience in UI that dynamically subscribes to sync

### Notification Stream Cleanup
- **What's not tested:** StreamController closure when switching atSigns or stopping listener
- **Files:** `packages/at_client/test/notification_service_test.dart`, `packages/at_client/lib/src/service/notification_service_impl.dart:170-179`
- **Risk:** Resource leaks, dangling listeners, memory exhaustion in long-running apps
- **Priority:** High - especially critical for mobile where resources are constrained

### APKAM Enrollment Multi-Step Scenarios
- **What's not tested:**
  - Enrollment request timeout/cancellation
  - Partial approval (some namespaces approved, others denied)
  - Re-enrollment with same device but new namespaces
  - Revocation followed by immediate re-enrollment
- **Files:** `packages/at_auth/test/at_enrollment_test.dart`
- **Risk:** Broken enrollment state recovery
- **Priority:** Medium - affects multi-device use cases

### PassPhrase-Protected Keys Integration
- **What's not tested:**
  - Full round-trip (onboard with passphrase → store → load → authenticate)
  - PassPhrase with different hashing algorithms
  - PassPhrase with encrypted private key storage
  - PassPhrase recovery/reset scenarios
- **Files:** `packages/at_onboarding_cli/test/at_keys_file_io_test.dart`
- **Risk:** Passphrase feature completely broken in production
- **Priority:** High - currently blocked by SHA512 type bug, affects security-conscious users

### File Collision Handler Edge Cases
- **What's not tested:**
  - Collision with immovable file (permission denied)
  - Disk full during temp file write
  - Temp file cleanup on process crash
  - Race condition between collision check and atomic rename
- **Files:** `packages/at_onboarding_cli/test/at_keys_file_collision_test.dart`, `packages/at_onboarding_cli/lib/src/at_keys/keys_file_writer.dart`
- **Risk:** Corrupted or lost .atKeys files on edge case failures
- **Priority:** Medium - atomic write structure is solid but edge cases need coverage

### Sync Conflict Resolution
- **What's not tested:**
  - Multiple simultaneous UPDATE/DELETE operations on same key from different sources
  - Conflict resolution with custom strategies
  - Metadata conflicts (TTL, encryption keys, timestamps)
  - Cascade delete interactions with concurrent operations
- **Files:** `packages/at_client/test/sync_new_test.dart` (partially tested, gaps remain)
- **Risk:** Data inconsistency, lost updates
- **Priority:** Medium - core sync feature, some coverage exists but edge cases uncovered

---

*Concerns audit: 2026-02-03*
