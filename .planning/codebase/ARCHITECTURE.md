# Architecture

**Analysis Date:** 2026-02-03

## Pattern Overview

**Overall:** Multi-layered, vertically-sliced monorepo architecture organized around the atProtocol specification. Uses a factory/manager pattern for dependency injection with explicit service layer abstractions. Authentication and encryption are first-class concerns.

**Key Characteristics:**
- **Protocol-driven**: All operations translated through verb builders following atProtocol syntax
- **End-to-end encrypted**: Encryption/decryption handled at client layer, never transmitted unencrypted
- **Dual-store model**: Local Hive storage synchronized with remote atServer via commit log comparison
- **Asynchronous service operations**: Sync, notifications, and enrollment use async streams and callbacks
- **Request/Response transformation**: Plain data objects transformed through request/response pipelines before verb execution

## Layers

**Presentation/Application Layer:**
- Location: `packages/at_client_flutter/`, `packages/at_*_flutter/` (Flutter widgets)
- Purpose: UI components for authentication, contacts, chat, location, etc.
- Contains: Flutter widgets, state management, UI models
- Depends on: `at_client` SDK
- Used by: End applications

**High-level SDK Layer (`at_client`):**
- Location: `packages/at_client/lib/src/`
- Purpose: Primary API for applications - CRUD operations, sync, notifications
- Contains:
  - `AtClientImpl`: Main client facade exposing `put()`, `get()`, `delete()`, `scan()`, `notify()`
  - `SyncServiceImpl`: Bidirectional sync between local and remote secondary
  - `NotificationService`: Real-time change notifications via MONITOR verb
  - `EnrollmentService`: APKAM enrollment request handling
  - Request/response transformers: Convert high-level operations to/from verbs
  - Encryption service: Manages AES key generation and storage
- Depends on: `at_lookup`, `at_auth`, `at_chops`, `at_commons`, `at_persistence_secondary_server`
- Used by: Applications, Flutter widgets

**Authentication & Onboarding Layer:**
- **at_auth** (`packages/at_auth/lib/src/`):
  - Purpose: CRAM and PKAM authentication, key management, APKAM enrollment
  - Contains: `AtAuthImpl`, `CramAuthenticator`, `PkamAuthenticator`, `AtEnrollment`, `AtKeysIo`
  - Delegates verb execution to `at_lookup`
  - Generates and stores keys via `AtKeysIo` abstraction (files, keychains, etc.)

- **at_onboarding_cli** (`packages/at_onboarding_cli/lib/src/`):
  - Purpose: High-level onboarding/activation service and CLI
  - Contains: `AtOnboardingServiceImpl` (delegates to `at_auth`), collision handlers, CLI parsers
  - Exposed as: `at_activate` and `at_register` CLI tools

**Protocol & Verb Layer (`at_lookup`):**
- Location: `packages/at_lookup/lib/src/`
- Purpose: Low-level socket management and verb protocol execution
- Contains:
  - `AtLookupImpl`: Verb executor, delegates to `OutboundConnection`
  - `OutboundConnectionImpl`: TCP socket management with authentication
  - Secondary address finder: Root server lookup with caching
  - Secure socket factory: TLS configuration
- Executes verbs: All protocol operations (UPDATE, DELETE, LOOKUP, PKAM, CRAM, MONITOR, NOTIFY, SYNC, etc.)
- Depends on: `at_commons` (verb builders)
- Used by: `at_client`, `at_auth`

**Cryptography Layer (`at_chops`):**
- Location: `packages/at_chops/lib/src/`
- Purpose: RSA/ECC key generation and management, AES-256-GCM encryption/decryption, signing
- Contains: `AtChopsImpl` with AES, RSA, ECC, HMAC, signing operations
- Used by: `at_lookup` (PKAM signing), `at_client` (data encryption), `at_auth` (key generation)

**Data Model Layer (`at_commons`):**
- Location: `packages/at_commons/lib/src/`
- Purpose: Shared data structures and verb definitions
- Contains:
  - `AtKey`: Represents atProtocol key with metadata (encryption, TTL, sharing)
  - `Metadata`: Key metadata (TTL, IV, encryption key name, etc.)
  - Verb builders: `UpdateVerbBuilder`, `DeleteVerbBuilder`, `LookupVerbBuilder`, etc.
  - `AtMessage`: Buffered protocol messages
  - Verb syntax validators: Regex patterns from spec
  - Exceptions: `AtClientException`, `AtServerException`, etc.
- Used by: All layers

**Persistence Layer:**
- Local: `packages/at_client/lib/src/client/local_secondary.dart`
  - Implementation: Hive (key-value store with ACID)
  - Storage: `~/.atsign/` directory with per-atSign isolation
  - Contains: Commit log (sequence-numbered operations), keys
  - Accessed by: `at_client` for local reads, sync service for push

- Remote: Server-based (no direct access, via `at_lookup` verbs)
  - Source of truth for shared data
  - Accessed by: Sync service via SYNC, LOOKUP verbs

## Data Flow

**Put Operation (Write with Encryption):**

1. **Application**: `atClient.put(AtKey()..key='phone', '+1234567890')`
2. **AtClientImpl.put()**: Validates key, creates `AtKey` object
3. **PutRequestTransformer.transform()**:
   - Checks if key is public (no encryption) or private (encrypt)
   - For private keys: Gets AES encryption key from `EncryptionService`
   - Encrypts value with AES-256-GCM, stores IV in metadata
   - Builds `UpdateVerbBuilder` with encrypted value
4. **VerbBuilderManager**: Converts `UpdateVerbBuilder` to verb string syntax
   - Example: `update:ttl:3600:@bob:phone@alice encrypted_value\n`
5. **AtLookupImpl.executeCommand()**: Sends verb to secondary via `OutboundConnection`
6. **RemoteSecondary**: Server stores encrypted data
7. **LocalSecondary.put()**: Stores local copy in Hive with commit log entry
8. **Response**: `AtValue` returned to application

**Get Operation (Read with Decryption):**

1. **Application**: `atClient.get(AtKey()..key='phone')`
2. **AtClientImpl.get()**: Creates LOOKUP verb via `GetRequestTransformer`
3. **AtLookupImpl.executeCommand()**: Sends `llookup` (local) or `lookup` (remote)
4. **LocalSecondary/RemoteSecondary**: Returns encrypted value + metadata (IV, encryption key name)
5. **GetResponseTransformer.transform()**:
   - If encrypted: Gets AES key from `EncryptionService` using `metadata.encKeyName`
   - Decrypts with IV from metadata
   - Verifies signature if public key
6. **Application**: Receives plaintext `AtValue`

**Sync Flow:**

1. **SyncServiceImpl.sync()**:
   - Compares local and remote commit log sequence numbers
   - Notifies listeners: `SYNC_PROGRESS(fetchingServerCommitId)`

2. **If local ahead**:
   - PUSH phase: Iterate local commit log entries newer than remote
   - For each entry: Re-execute UPDATE/DELETE via SYNC verb
   - Update remote secondary

3. **If remote ahead**:
   - PULL phase: SYNC verb fetches remote entries by sequence range
   - For each entry: Decrypt and store in local secondary
   - Update local commit log

4. **Conflict Resolution**:
   - Default: Last-write-wins (by server timestamp)
   - Configurable via `ResolutionStrategy` in `SyncUtil`

5. **Completion**:
   - Update `lastSyncedEntry` metadata
   - Notify listeners: `SYNC_PROGRESS(syncComplete)`

**Notification Flow (Real-time Changes):**

1. **Application**: `notificationService.subscribe(regex: 'phone.*')`
2. **NotificationServiceImpl.subscribe()**: Registers regex in local set
3. **Background monitor**: Opens MONITOR verb connection (persistent)
4. **Server pushes**: When `@alice` updates key matching regex, server sends NOTIFICATION
5. **StreamNotificationHandler**: Parses notification, decrypts value
6. **Application listener**: Receives `AtNotification` with key, value, operation

**Authentication Flow (PKAM):**

1. **Application**: `AtAuth.authenticate(AtAuthRequest('@alice'))`
2. **AtAuthImpl.authenticate()**:
   - Reads keys from `AtKeysIo` (file or keychain)
   - Creates `AtLookupImpl` with secondary address lookup
3. **PkamAuthenticator.authenticate()**:
   - Executes FROM verb: `from:@alice`
   - Server responds with random challenge (proof)
   - Signs challenge with APKAM private key using `AtChops`
   - Executes PKAM verb: `pkam:signature_digest`
4. **Server**: Validates signature with stored public key
5. **AtAuthImpl**: Returns `AtAuthResponse` with authenticated `AtLookUpImpl`
6. **Application**: Uses `atLookUp` for subsequent operations

**Onboarding Flow (CRAM):**

1. **Application**: `AtAuth.onboard(AtOnboardingRequest('@alice'), cramSecret)`
2. **AtAuthImpl.onboard()**:
   - Server validation: Check atSign not activated
   - Creates temporary `AtLookupImpl` with CRAM secret
3. **CramAuthenticator.authenticate()**:
   - FROM verb, CRAM verb with secret hash
   - Server approves if CRAM secret matches
4. **Key generation**:
   - `AtChops.generateKeyPair()` creates RSA 2048 for APKAM + encryption
   - Creates AES symmetric key for encrypting private keys
5. **Enrollment submission**:
   - ENROLL verb with APKAM public key, app metadata
   - Server generates `enrollmentId`, sets to pending
6. **If autoCompleteActivation**:
   - PKAM authenticate with new keys
   - Upload encryption public key
   - Delete CRAM secret
7. **Key storage**:
   - `AtKeysIo.write()` stores to `~/.atsign/keys/@alice.atKeys`
   - Atomic write: temp file → collision check → rename
8. **Return**: `AtOnboardingResponse` with keys, enrollmentId

**State Management (Multi-atSign):**

1. **AtClientManager.setCurrentAtSign('@alice', namespace, preferences)**:
   - Pause sync/monitor on previous atSign
   - Load @alice storage (`~/.atsign/@alice/hive`)
   - Create new `AtClientImpl` with fresh service instances
   - Subscribe to atSign change events
2. **Storage isolation**: Each atSign has separate Hive directory
3. **Service pause/resume**: Sync and notification services stopped/started per atSign

## Key Abstractions

**AtClient Interface:**
- Purpose: Primary API contract for CRUD and sync operations
- Located: `packages/at_client/lib/src/client/at_client_spec.dart`
- Implementation: `AtClientImpl`
- Methods: `put()`, `get()`, `delete()`, `scan()`, `notify()`, `getEncryptionPublicKey()`
- Pattern: Facade pattern hiding service complexity

**Secondary Interface:**
- Purpose: Abstract local vs remote storage
- Implementations:
  - `LocalSecondary`: Hive-based, accessed via `SecondaryKeyStore`
  - `RemoteSecondary`: Server-based, accessed via `AtLookupImpl` verbs
- Used by: `AtClientImpl` for dual-store operations

**VerbBuilder Pattern:**
- Purpose: Fluent API for constructing protocol verbs
- Examples: `UpdateVerbBuilder`, `DeleteVerbBuilder`, `LookupVerbBuilder`
- Pattern: Builder with late binding of parameters
- Output: Verb string (`update:ttl:3600 @bob:phone@alice value`)

**Request/Response Transformers:**
- Purpose: Translate between domain objects and protocol verbs
- Request transformers: `PutRequestTransformer`, `GetRequestTransformer`
  - Input: `Tuple<AtKey, dynamic>`
  - Output: `VerbBuilder` (e.g., `UpdateVerbBuilder`)
- Response transformers: `PutResponseTransformer`, `GetResponseTransformer`
  - Input: Raw server response string
  - Output: Domain object (e.g., `AtValue`)

**EncryptionService:**
- Purpose: Manages AES key generation, storage, and retrieval
- Located: `packages/at_client/lib/src/service/encryption_service.dart`
- Stores keys in local secondary as `@recipient:shared_key@sender`
- Accessed by: Request/response transformers for transparent encryption/decryption

**SyncService Interface:**
- Purpose: Bidirectional sync between local and remote
- Located: `packages/at_client/lib/src/service/sync_service.dart`
- Implementation: `SyncServiceImpl` with `SyncManager` for isolation
- Methods: `sync()`, `isInSync()`, `addProgressListener()`
- Pattern: Observer pattern for progress events

**NotificationService:**
- Purpose: Real-time change notifications
- Located: `packages/at_client/lib/src/service/notification_service.dart`
- Pattern: Stream-based (async listening) + callback (blocking)
- Methods: `subscribe()`, `notify()`, `unsubscribe()`

**AtAuth Interface:**
- Purpose: Authentication and key management
- Located: `packages/at_auth/lib/src/at_auth.dart`
- Implementations: `AtAuthImpl`
- Pattern: Service layer with pluggable authenticators and key storage

**AtKeysIo Abstraction:**
- Purpose: Storage-agnostic key file access
- Located: `packages/at_auth/lib/src/keys/at_keys_io.dart`
- Implementations:
  - `AtKeysFileIo`: Filesystem (`~/.atsign/keys/`)
  - Custom: Keychains, secure elements, cloud storage
- Pattern: Strategy pattern for different storage backends

## Entry Points

**at_client (SDK):**
- Location: `packages/at_client/lib/at_client.dart`
- Triggers: Application `import 'package:at_client/at_client.dart'`
- Responsibilities:
  - Export `AtClient`, `AtClientManager`, `SyncService`, `NotificationService`
  - Provide high-level API for data operations and sync
  - Hide complexity of encryption, verb building, persistence

**at_auth (Authentication):**
- Location: `packages/at_auth/lib/at_auth.dart`
- Triggers: Onboarding/authentication workflows
- Responsibilities:
  - Export `AtAuth`, `AtAuthRequest`, `AtAuthResponse`, `AtEnrollment`
  - Manage CRAM/PKAM authentication flows
  - Handle key generation and storage

**at_onboarding_cli (CLI & Service):**
- Location: `packages/at_onboarding_cli/lib/at_onboarding_cli.dart`
- Triggers: CLI invocation (`at_activate`, `at_register`) or programmatic use
- Responsibilities:
  - Export `AtOnboardingService`, `AtOnboardingServiceImpl`
  - Provide high-level onboarding service wrapping `at_auth`
  - Handle collision resolution, file I/O, user interaction

**Flutter Widgets:**
- Location: `packages/at_*_flutter/lib/` (e.g., `at_login_flutter`, `at_contacts_flutter`)
- Triggers: Application Flutter widget tree
- Responsibilities:
  - Provide composable UI components for atPlatform features
  - Delegate business logic to `at_client` SDK

**Functional Tests:**
- Location: `tests/at_functional_test/test/`
- Triggers: `dart test` or CI/CD workflows
- Responsibilities:
  - Test full stack with local Docker-based atServer
  - Validate sync, encryption, and multi-atSign scenarios
  - Run with `--concurrency=1` to avoid Hive conflicts

## Error Handling

**Strategy:** Hierarchical exception inheritance with context-specific error messages.

**Patterns:**

1. **Validation Errors**:
   - `InvalidAtKeyException`: Bad key format
   - Location: `at_commons/lib/src/exception/at_client_exceptions.dart`
   - Thrown by: Key validators, verb builders

2. **Authentication Errors**:
   - `AtAuthenticationException`: Auth/onboarding failures
   - `UnAuthenticatedException`: Missing PKAM validation
   - Location: `at_auth/lib/src/exception/at_auth_exceptions.dart`
   - Thrown by: `PkamAuthenticator`, `CramAuthenticator`

3. **Key Management Errors**:
   - `AtKeyException`: File I/O failures
   - `AtPrivateKeyNotFoundException`: Missing key in `.atKeys`
   - `AtKeyFileExistsException`: Collision handling
   - Location: `at_auth/lib/src/exception/at_auth_exceptions.dart`
   - Thrown by: `AtKeysFileIo`, collision handlers

4. **Server Errors**:
   - `AtServerException`: Server returned error verb
   - Parsed into subtypes: `InvalidRequest`, `ServerUnavailable`, `InternalServerError`
   - Location: `at_commons/lib/src/exception/at_server_exceptions.dart`
   - Thrown by: `OutboundMessageListener`, response parsers

5. **Sync/Notification Errors**:
   - Generic `Exception` with specific messages
   - Notified via `SyncProgressListener.onError()` or `notificationService` error streams
   - Location: `at_client/lib/src/service/sync_service_impl.dart`

**Error Recovery:**
- Retry logic in `AtAuth` via `RetryOptions(maxRetries, retryDelay)`
- Sync errors don't halt: Logged and re-attempted on next sync cycle
- Connection errors: Auto-reconnect with exponential backoff (via `OutboundConnectionImpl`)

## Cross-Cutting Concerns

**Logging:**
- Framework: `package:at_utils/at_logger.dart` (wrapper around `dart:developer` and `package:logging`)
- Pattern: Hierarchical logger names (`'AtClient (@alice)'`, `'SyncService'`)
- Configuration: `AtSignLogger` initialized per component

**Validation:**
- Framework: `at_commons/lib/src/validators/` with regex-based validators
- Pattern: Validators called before verb execution, response parsing
- Examples: `AtKeyValidator`, `VerbSyntaxValidator`

**Authentication:**
- Framework: PKAM via `PkamAuthenticator`, CRAM via `CramAuthenticator`
- Pattern: Pluggable authenticators in `at_auth`, injected into `at_lookup`
- Scope: All verb execution requires prior authentication (except FROM/CRAM)

**Encryption:**
- Framework: AES-256-GCM via `at_chops`, IV stored in `Metadata`
- Pattern: Transparent in request/response transformers
- Scope: All non-public keys encrypted by default, configurable per operation

**Telemetry (Experimental):**
- Framework: `@experimental AtTelemetryService` in `at_client`
- Pattern: Optional service injected into `AtClientImpl`
- Scope: Tracks client operations, sync progress, errors

---

*Architecture analysis: 2026-02-03*
