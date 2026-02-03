# Codebase Structure

**Analysis Date:** 2026-02-03

## Directory Layout

```
at_client_sdk/
├── packages/                           # Pub workspace packages
│   ├── at_client/                      # High-level SDK (CRUD, sync, notifications)
│   ├── at_client_flutter/              # Flutter SDK wrapper
│   ├── at_auth/                        # Authentication and key management
│   ├── at_onboarding_cli/              # Onboarding service and CLI tools
│   ├── at_lookup/                      # Low-level protocol execution
│   ├── at_commons/                     # Shared data models and exceptions
│   ├── at_chops/                       # Cryptography operations
│   ├── at_utils/                       # Utility functions and logging
│   ├── at_cli_commons/                 # CLI argument parsing utilities
│   ├── at_contact/                     # Contact data models
│   ├── at_policy/                      # Policy/permission models
│   ├── at_server_status/               # Server health checks
│   ├── at_common_flutter/              # Shared Flutter utilities
│   ├── at_*_flutter/                   # Domain-specific Flutter widgets (chat, contacts, etc.)
│   └── base2e15/, dart_utf7/           # Encoding libraries
│
├── tests/                              # Test suites
│   ├── at_functional_test/             # Full-stack tests with Docker atServer
│   ├── at_onboarding_cli_functional_tests/ # Onboarding-specific functional tests
│   ├── at_onboarding_cli_functional_tests_proxy/ # Proxy connection tests
│   └── at_end2end_test/                # E2E tests with real servers
│
├── tools/                              # Development utilities
├── .github/workflows/                  # CI/CD pipelines
├── melos.yaml                          # Workspace configuration
├── pubspec.yaml                        # Root workspace manifest
└── README.md                           # Repository documentation
```

## Directory Purposes

**packages/at_client/**
- Purpose: Primary client SDK for application developers
- Contains:
  - `lib/src/client/`: Core `AtClientImpl`, `LocalSecondary`, `RemoteSecondary`
  - `lib/src/service/`: `SyncService`, `NotificationService`, `EncryptionService`, `EnrollmentService`
  - `lib/src/manager/`: `AtClientManager`, `SyncManager`, `StorageManager`
  - `lib/src/transformer/`: Request/response transformers for CRUD operations
  - `lib/src/converters/`: Encryption/decryption and encoding
  - `lib/src/preference/`: `AtClientPreference`, `AtClientConfig`
  - `test/`: Unit tests with mock dependencies
- Key files: `at_client.dart` (exports), `at_client_impl.dart`, `sync_service_impl.dart`

**packages/at_auth/**
- Purpose: Authentication, key generation, key storage
- Contains:
  - `lib/src/at_auth.dart`: Main `AtAuthImpl` implementation
  - `lib/src/auth/`: `PkamAuthenticator`, `CramAuthenticator`
  - `lib/src/enroll/`: `AtEnrollment` for APKAM enrollment
  - `lib/src/keys/`: `AtKeysIo` abstraction, `AtKeysFileIo` implementation
  - `lib/src/exception/`: Auth-specific exceptions
  - `test/`: Unit tests for auth flows
- Key files: `at_auth.dart`, `at_auth_impl.dart`, `at_keys_io_impl.dart`

**packages/at_onboarding_cli/**
- Purpose: High-level onboarding service and CLI tools
- Contains:
  - `lib/src/onboard/`: `AtOnboardingServiceImpl` (wraps `at_auth`)
  - `lib/src/cli/`: CLI argument parsing and command routing
  - `lib/src/util/`: Collision handlers, preference, onboarding utilities
  - `lib/src/activate_cli/`, `register_cli/`: Command implementations
  - `bin/`: Entry points for `at_activate` and `at_register` executables
  - `test/`: Unit tests for service and CLI
- Key files: `at_onboarding_cli.dart`, `at_onboarding_service_impl.dart`, `auth_cli.dart`

**packages/at_lookup/**
- Purpose: Low-level socket management and verb protocol execution
- Contains:
  - `lib/src/`: `AtLookupImpl`, verb execution, connection management
  - `lib/src/connection/`: `OutboundConnectionImpl`, socket factories
  - `lib/src/cache/`: Secondary address finder with caching
  - `test/`: Unit tests with mocked connections
- Key files: `at_lookup.dart`, `at_lookup_impl.dart`, `outbound_connection_impl.dart`

**packages/at_commons/**
- Purpose: Shared data models, verb builders, exceptions
- Contains:
  - `lib/src/keystore/`: `AtKey`, `Metadata`, key validation
  - `lib/src/verb/`: Verb builders (`UpdateVerbBuilder`, etc.), syntax validators
  - `lib/src/exception/`: Exception hierarchy (`AtClientException`, `AtServerException`)
  - `lib/src/auth/`: Auth mode enums, models
  - `lib/src/enroll/`: Enrollment constants and models
  - `lib/src/buffer/`: Message buffering
  - `test/`: Exception and validation tests
- Key files: `at_commons.dart`, `at_key.dart`, `verb/syntax.dart`

**packages/at_chops/**
- Purpose: Cryptographic operations (RSA, AES, ECC, signing)
- Contains:
  - `lib/src/`: `AtChopsImpl` with cipher implementations
  - No public verb execution (called by `at_auth` and `at_client`)
- Key files: `at_chops.dart`, integration with `better_cryptography`, `pointycastle`

**packages/at_utils/**
- Purpose: Logging, string utilities, common helpers
- Contains: `AtSignLogger`, utility functions
- Used by: All packages

**tests/at_functional_test/**
- Purpose: Full-stack testing with local Docker atServer
- Contains:
  - `test/config.yaml`: atServer and storage configuration
  - `test/docker-compose.yaml`: Docker Compose setup (atServer, SQLite, supervisord)
  - `test/check_docker_readiness.dart`: Startup check
  - `test/at_client_sync_test.dart`: Sync operations
  - `test/at_client_put_get_delete_test.dart`: CRUD operations
- Run: `cd tests/at_functional_test && ./runLocal.sh`

**tests/at_onboarding_cli_functional_tests/**
- Purpose: Functional testing of onboarding workflows
- Contains: Tests for activation, enrollment, collision handling
- Run: `cd tests/at_onboarding_cli_functional_tests && dart test`

## Key File Locations

**Entry Points:**
- `packages/at_client/lib/at_client.dart`: Main SDK export
- `packages/at_auth/lib/at_auth.dart`: Auth export
- `packages/at_onboarding_cli/lib/at_onboarding_cli.dart`: Onboarding export
- `packages/at_lookup/lib/at_lookup.dart`: Protocol export
- `packages/at_onboarding_cli/bin/activate_cli.dart`: CLI executable (at_activate)
- `packages/at_onboarding_cli/bin/register_cli.dart`: CLI executable (at_register)

**Configuration:**
- `packages/at_client/lib/src/preference/at_client_preference.dart`: Client preferences
- `packages/at_client/lib/src/preference/at_client_config.dart`: Client version and config
- `packages/at_onboarding_cli/lib/src/util/at_onboarding_preference.dart`: Onboarding preferences
- `packages/at_commons/lib/src/at_constants.dart`: Global constants
- `pubspec.yaml`: Root workspace manifest

**Core Logic:**
- `packages/at_client/lib/src/client/at_client_impl.dart`: Main client implementation (38KB)
- `packages/at_client/lib/src/service/sync_service_impl.dart`: Sync logic (46KB)
- `packages/at_client/lib/src/service/notification_service_impl.dart`: Notifications (23KB)
- `packages/at_lookup/lib/src/at_lookup_impl.dart`: Protocol execution (100KB)
- `packages/at_auth/lib/src/at_auth_impl.dart`: Authentication (varies)

**Data Models:**
- `packages/at_commons/lib/src/keystore/at_key.dart`: Key representation
- `packages/at_commons/lib/src/keystore/at_key.dart`: Metadata class
- `packages/at_auth/lib/src/keys/at_keys.dart`: AtKeys model
- `packages/at_commons/lib/src/verb/operation_enum.dart`: Operation types (UPDATE, DELETE, etc.)

**Testing:**
- `packages/at_client/test/at_client_impl_test.dart`: Client tests
- `packages/at_client/test/encryption_service_test.dart`: Encryption tests
- `packages/at_client/test/sync_service_test.dart`: Sync tests
- `packages/at_client/test/local_secondary_test.dart`: Local storage tests
- `packages/at_auth/test/at_auth_test.dart`: Auth tests
- `tests/at_functional_test/test/`: Full-stack tests

## Naming Conventions

**Files:**
- Dart files: `snake_case.dart` (e.g., `at_client_impl.dart`)
- Directories: `snake_case/` (e.g., `at_commons/`)
- Exports: `{package}.dart` in `lib/` root (e.g., `at_client.dart`)
- Tests: `*_test.dart` (e.g., `at_client_impl_test.dart`)

**Classes:**
- Implementation: `{Interface}Impl` (e.g., `AtClientImpl`, `AtLookupImpl`)
- Abstract interfaces: No suffix (e.g., `AtClient`, `Secondary`)
- Service layer: `{Service}ServiceImpl` (e.g., `SyncServiceImpl`, `NotificationServiceImpl`)
- Builders: `{Verb}VerbBuilder` (e.g., `UpdateVerbBuilder`, `DeleteVerbBuilder`)
- Handlers/Listeners: `{Domain}Listener` or `{Domain}Handler` (e.g., `OutboundMessageListener`)
- Exceptions: `{Domain}Exception` (e.g., `AtAuthenticationException`, `InvalidAtKeyException`)

**Methods:**
- Getters/Setters: `camelCase` (e.g., `get atClient`, `set syncService`)
- Regular methods: `camelCase` (e.g., `authenticate()`, `put()`, `sync()`)
- Private: Leading underscore (e.g., `_encryptData()`, `_connection`)
- Async: Regular names, return `Future` (e.g., `authenticate()`, `put()`)

**Variables:**
- Local/class fields: `camelCase` (e.g., `atSign`, `encryptionService`)
- Private: Leading underscore (e.g., `_atSign`, `_syncService`)
- Constants: `UPPER_CASE` (e.g., `MAX_RETRIES`, `DEFAULT_TIMEOUT`)
- Types: `PascalCase` (e.g., `AtKey`, `Metadata`, `AtClientImpl`)

**Packages (Dependencies):**
- at_* packages: Internal monorepo packages (e.g., `at_client`, `at_auth`)
- External: Version-pinned in `pubspec.yaml` (e.g., `http: ^1.2.1`, `hive: ^2.2.3`)
- Workspace resolution: `resolution: workspace` for monorepo interdependencies

## Where to Add New Code

**New Feature (High-level SDK):**
- Primary code: `packages/at_client/lib/src/service/` (for new service) or `packages/at_client/lib/src/client/` (for new method on `AtClient`)
- Examples:
  - New sync strategy: `packages/at_client/lib/src/manager/sync_manager.dart`
  - New encryption mode: `packages/at_client/lib/src/encryption_service/`
- Tests: `packages/at_client/test/{feature}_test.dart`
- Export in: `packages/at_client/lib/at_client.dart`

**New Component/Module:**
- If part of existing service layer: `packages/at_client/lib/src/service/{component}.dart`
- If cross-cutting utility: `packages/at_utils/lib/src/`
- If domain-specific: Create new package `packages/at_{domain}/`
  - Include: `lib/at_{domain}.dart` (export), `lib/src/` (implementation), `test/` (tests), `pubspec.yaml`
  - Update: Root `pubspec.yaml` workspace list, `.github/workflows/` CI

**New Flutter Widget:**
- Template: Copy `packages/at_*_flutter/` structure
- Main code: `packages/at_new_flutter/lib/src/widgets/`
- Models: `packages/at_new_flutter/lib/src/models/`
- Services: Delegate to `at_client` SDK
- Tests: `packages/at_new_flutter/test/`
- Example: `packages/at_new_flutter/example/` with sample app

**Authentication Logic (Auth Layer):**
- New authenticator: `packages/at_auth/lib/src/auth/new_authenticator.dart`
- New key storage: `packages/at_auth/lib/src/keys/custom_keys_io.dart` (implement `AtKeysIo`)
- New exception: `packages/at_auth/lib/src/exception/at_auth_exceptions.dart`
- Export in: `packages/at_auth/lib/at_auth.dart`

**Protocol Verb:**
- Verb builder: `packages/at_commons/lib/src/verb/new_verb_builder.dart`
- Register syntax: `packages/at_commons/lib/src/verb/syntax.dart` (add regex)
- Request transformer: `packages/at_client/lib/src/transformer/request_transformer/new_request_transformer.dart`
- Response transformer: `packages/at_client/lib/src/transformer/response_transformer/new_response_transformer.dart`

**Utility Functions:**
- Shared helpers: `packages/at_utils/lib/src/` (new file or extend existing)
- Logging: Use `AtSignLogger('Component')` from `at_utils`
- Validation: `packages/at_commons/lib/src/validators/` (new validators)

**Test Data/Fixtures:**
- Mock objects: `test/mock/` or `test/{feature}_mock.dart`
- Mock patterns: Use `mocktail` with `Mock` extends and `when(...).thenAnswer(...)`
- Sample data: In test file or `test/data/` directory
- Example: `packages/at_client/test/samples/at_client_listener_sample.dart`

## Special Directories

**packages/at_client/lib/src/client/**
- Purpose: Core client implementation and storage abstraction
- Generated: No
- Committed: Yes
- Key files: `at_client_impl.dart`, `local_secondary.dart`, `remote_secondary.dart`

**packages/at_client/lib/src/manager/**
- Purpose: Service lifecycle and multi-atSign management
- Generated: No
- Committed: Yes
- Key files: `at_client_manager.dart`, `sync_manager.dart`, `monitor.dart`

**packages/at_client/test/samples/**
- Purpose: Example usage for developers
- Generated: No
- Committed: Yes
- Usage: Reference implementations for common patterns

**.dart_tool/**
- Purpose: Build artifacts and dependency cache
- Generated: Yes
- Committed: No
- Created by: `dart pub get`

**test/hive/**
- Purpose: Local storage during functional tests
- Generated: Yes
- Committed: No
- Cleanup: `rm -rf test/hive` before running tests
- Isolation: Each test should clean up after itself to avoid conflicts

**test/commitLog/**
- Purpose: Commit log entries during functional tests
- Generated: Yes
- Committed: No
- Cleanup: `rm -rf test/commitLog` before running tests

**~/.atsign/keys/**
- Purpose: Persistent `.atKeys` files on developer machine
- Location: User home directory (not in repo)
- Format: JSON with RSA and AES keys
- Examples: `@alice.atKeys`, `@bob.atKeys`

**~/.atsign/@alice/hive/**
- Purpose: Hive local storage for @alice
- Location: User home directory
- Created by: `AtClientImpl` on first access
- Isolation: Per-atSign directory
- Cleanup: `rm -rf ~/.atsign/` to reset all storage

**.github/workflows/**
- Purpose: CI/CD pipeline definitions
- Generated: No
- Committed: Yes
- Key files: `at_client_sdk.yaml` (main), `at_libraries.yaml`, `at_widgets.yml`, `codeql.yml`
- Triggers: PR, push to trunk

**melos.yaml**
- Purpose: Workspace tool configuration for multi-package scripts
- Edited: When adding new packages or changing scripts
- Commands: `melos bootstrap`, `melos pub get`, `melos analyze`

## Package Dependency Resolution

**Workspace Resolution (`resolution: workspace`):**
- Used by: `at_client`, `at_auth`, `at_lookup`, `at_commons`, `at_chops`, test packages
- Benefit: Share dependency versions across monorepo
- Root `pubspec.yaml` defines: `at_base2e15`, `at_persistence_secondary_server`, external dependencies
- Child packages declare: `resolution: workspace` and omit version constraints

**Example (at_client pubspec.yaml):**
```yaml
dependencies:
  at_commons: ^5.7.0        # Pinned version if not in workspace
  at_lookup: ^3.1.0
  at_chops: ^3.0.0
  at_auth: ^3.0.0
  at_utils: ^3.2.0
```

**Lock File (pubspec.lock):**
- Generated by: `dart pub get` from root
- Location: Root directory only
- Updated: When running `melos pub get`
- Committed: Yes (ensures reproducible builds)

## Import Organization

**Pattern:**
1. Dart imports (`dart:...`)
2. Package imports (`package:...`)
3. Relative imports (`../`)

**Example (at_client_impl.dart):**
```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_base2e15/at_base2e15.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_lookup/at_lookup.dart';

import '../listener/at_sign_change_listener.dart';
import '../manager/storage_manager.dart';
import '../service/sync_service.dart';
```

**Path Aliases:**
- Not used in this codebase (uses relative imports and package imports only)
- Config would be in `pubspec.yaml` under `dev_dependencies:` (not currently present)

## Build and Run Commands

**Get Dependencies (Workspace):**
```bash
# From root or any package directory
dart pub get

# Or with melos
melos bootstrap
```

**Run Tests (Package-level):**
```bash
cd packages/at_client
dart test --concurrency=1                    # All tests
dart test test/at_client_impl_test.dart      # Single file
dart test --name "put operation"              # By name
dart test --coverage="coverage"               # With coverage
```

**Run Functional Tests:**
```bash
cd tests/at_functional_test
./runLocal.sh                                 # Full setup + tests
# OR manually:
dart pub get
docker compose -f test/docker-compose.yaml up -d
dart run test/check_docker_readiness.dart
docker exec test-virtualenv-1 supervisorctl start pkamLoad
dart test --concurrency=1
docker compose -f test/docker-compose.yaml down
```

**Code Quality:**
```bash
dart analyze                                  # Static analysis
dart format . -o none --set-exit-if-changed  # Check formatting
dart format .                                 # Fix formatting
```

**CLI Tools:**
```bash
# Development
dart run bin/activate_cli.dart -a @atsign -c cramSecret
dart run bin/register_cli.dart -e email@example.com

# Or after install:
at_activate -a @atsign -c cramSecret
```

---

*Structure analysis: 2026-02-03*
