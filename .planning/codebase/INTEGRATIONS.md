# External Integrations

**Analysis Date:** 2026-02-03

## APIs & External Services

**Registrar Service (atSign Registration):**
- Service: atSign activation/registration service (private/hosted)
- What it's used for: Verifying OTP for atSign activation and initial registration
- SDK/Client: `http` package v1.2.1
- Implementation: `packages/at_auth/lib/src/registrar/registrar.dart`
- Auth: API key-based authentication
- Endpoints:
  - `POST /authenticate/atsign/login` - OTP verification before activation
  - `POST /authenticate/atsign/activate` - Validate activation with OTP
- Environment: URL configurable via `AtOnboardingPreference.registrarUrl`

**Root Server (atProtocol Directory):**
- Service: atProtocol root server (well-known)
- What it's used for: Directory lookup to find secondary server for each atSign
- Implementation: `packages/at_lookup/lib/src/at_lookup_impl.dart::findSecondary()`
- Default: `root.atsign.org:64`
- Purpose: Maps atSign (@alice) to secondary server hostname:port
- Used by: All authentication and client operations

**Secondary Server (atProtocol):**
- Service: Personal secondary server for each atSign (atServer)
- What it's used for: All data operations, authentication, sync, notifications
- Protocol: Text-based atProtocol over TLS sockets
- Verbs: `UPDATE`, `LOOKUP`, `LLOOKUP`, `PLOOKUP`, `SCAN`, `DELETE`, `NOTIFY`, `MONITOR`, `SYNC`, `FROM`, `CRAM`, `PKAM`, `ENROLL`
- Implementation: `packages/at_lookup/lib/src/at_lookup_impl.dart`
- Socket connections via `OutboundConnection` and `InboundConnection`
- Default port: 64 (configurable)

**atServer Status Service:**
- Service: atServer availability and status checking
- What it's used for: Pre-flight validation before authentication/onboarding
- Implementation: `packages/at_server_status/lib/at_status_impl.dart`
- Checks: Root server availability, secondary server health, atSign activation status
- Status codes: `RootStatus` (found, notFound, unavailable), `ServerStatus` (running, stopped, unavailable, error, activated)
- Used by: `at_auth` for `validateAtServer()` pre-auth validation

## Data Storage

**Databases:**
- **Hive**: Local key-value NoSQL database (embedded)
  - Type: File-based, embedded Hive DB
  - Purpose: Local storage of synced key-value data, commit logs, metadata
  - Client: `hive` v2.2.3
  - Location: Configurable, default `./hive/` or `~/.atsign/hive/`
  - Used by: `at_client` for local secondary via `LocalSecondary`
  - Isolation: Per-atSign storage in separate Hive boxes (`@alice/`, `@bob/`)

**Remote Secondary (atServer):**
- Type: atServer (proprietary)
- Purpose: Central source of truth for shared data, remote persistence
- Connection: TCP TLS socket to secondary server
- Storage format: Key-value pairs with metadata, commit logs
- Used by: All data sync and cross-device operations

**File Storage:**
- **Local filesystem**: `.atKeys` files for cryptographic keys
  - Location: `~/.atsign/keys/@alice.atKeys`
  - Format: JSON containing RSA/ECC public/private keys, AES encryption keys
  - Managed by: `AtKeysFileIo` (atomic writes with collision handling)
  - Alternates: `biometric_storage` (iOS keychain), `flutter_keychain` (iOS/macOS)

**Caching:**
- **Flutter Network Cache** (if using `cached_network_image`):
  - Purpose: Caching fetched network images locally
  - Package: `cached_network_image` v3.3.1
  - Location: Flutter cache directory (platform-specific)

## Authentication & Identity

**Auth Provider:**
- Custom end-to-end encrypted authentication (no third-party provider)

**Mechanisms:**

1. **CRAM (Challenge-Response Authentication Mechanism)**
   - Type: Initial onboarding only
   - Implementation: `packages/at_auth/lib/src/authenticator/cram_authenticator.dart`
   - Secret: One-time CRAM secret provided during atSign registration
   - Protocol: Single exchange with server challenge
   - Used by: `at_auth.onboard()` for first-time atSign activation

2. **PKAM (Public Key Authentication Mechanism)**
   - Type: Standard authentication post-onboarding
   - Implementation: `packages/at_auth/lib/src/authenticator/pkam_authenticator.dart`
   - Keys: RSA 2048-bit APKAM key pair (generated during onboarding)
   - Protocol: Challenge-response with RSA signature
   - Used by: `at_auth.authenticate()` for normal authentication
   - Verb: `PKAM` with signed digest

3. **APKAM (Application Public Key Authentication Mechanism)**
   - Type: Application-specific secondary device enrollment
   - Implementation: `packages/at_auth/lib/src/at_enrollment.dart`
   - Keys: Ephemeral RSA key pair generated per app/device
   - Encryption: Symmetric key encrypted with encryption public key
   - Used by: Secondary app/device enrollment via OTP approval
   - Enrollment process: submit → wait for approval → activate

**Key Hierarchy:**
- RSA 2048-bit key pairs for PKAM (authentication)
- RSA 2048-bit key pairs for encryption (data at-rest)
- AES-256-GCM symmetric keys for shared data encryption
- AES symmetric key for encrypting private keys in APKAM

**Key File Management:**
- Location: `~/.atsign/keys/@alice.atKeys`
- Format: JSON with base64-encoded keys
- Collision handling: Abort/overwrite/rename (configurable via `FileCollisionBehavior`)
- Atomic writes: Temp file → collision check → atomic rename
- Secure alternatives: Biometric storage, keychains, secure enclaves

## Monitoring & Observability

**Logging:**
- Framework: `logging` v1.2.0 (Dart standard logging)
- Implementation: `AtSignLogger` hierarchical logger per component
- Output: Console stderr by default, configurable handlers
- Usage: `AtSignLogger('ComponentName (@atsign)')` for structured logs
- Examples in codebase: Encryption operations, sync progress, authentication steps

**Error Tracking:**
- None detected (no Sentry, Crashlytics integration)
- Errors propagated as exceptions: `AtException`, `AtAuthenticationException`, `AtKeyException`
- Manual error handling via `try-catch` and error listeners

**Progress/Status Monitoring:**
- `notificationService.progressListener` - Sync and operation progress
- `atAuth.progressStream` - Authentication/onboarding progress events
- `SyncService.addProgressListener()` - Sync operation updates
- Real-time updates via `MONITOR` verb for data changes

**Connectivity:**
- `internet_connection_checker` v1.0.0+1 - Check internet availability
- `ConnectivityListener` - Monitor network state changes
- Automatic retry logic in auth with `RetryOptions`

## CI/CD & Deployment

**Hosting:**
- GitHub-hosted (repository at `github.com/atsign-foundation/at_client_sdk`)
- Publishing: Pub.dev (packages distributed via pub.dev)

**CI Pipeline:**
- GitHub Actions workflows in `.github/workflows/`
- Workflows:
  - `at_libraries.yaml` - Unit/analysis tests for core packages (at_lookup, at_chops, at_commons, etc.)
  - `at_client_sdk.yaml` - Tests for at_client and at_client_flutter
  - `at_widgets.yml` - Tests for Flutter widget packages
  - `codeql.yml` - CodeQL security scanning
  - `osv-scanner.yaml` - Dependency vulnerability scanning
  - `dependency-review.yml` - PR dependency review
  - `autobug.yaml` - Automated bug detection
  - `scorecards.yml` - Security scorecard

**Build Steps:**
- Checkout code
- Setup Dart/Flutter via custom action `./actions/setup-flutter-and-dart`
- `dart pub get` - Install dependencies
- `dart analyze` - Static analysis
- `dart format --set-exit-if-changed` - Format checking
- `dart test --concurrency=1` - Unit tests with Hive serialization
- `flutter test --concurrency=1` - Flutter tests
- Coverage collection with `coverage` package

**Deployment:**
- Pub.dev packages: Each package released as standalone Dart package
- Versioning: Semantic versioning with workspace version coordination
- Melos: Used for coordinated multi-package releases
- Version bumping: Automated bot PRs for version updates

**Testing Infrastructure:**
- **Unit Tests**: `test` framework, `mocktail` for mocking
- **Functional Tests**: Docker Compose with local atServer
  - Location: `tests/at_functional_test/test/docker-compose.yaml`
  - Database: SQLite backend for test atServer
  - Supervisor: PKAM load testing via supervisorctl
- **End-to-End Tests**: Real atServer instances with CICD atSigns
  - Location: `tests/at_end2end_test/`
  - Requires live atServer connectivity

## Environment Configuration

**Required Environment Variables:**
- None hardcoded in source
- Configuration via preference objects: `AtClientPreference`, `AtOnboardingPreference`
- CLI arguments: Root domain, storage paths, registrar URL, API key (if using custom registrar)

**Key Configuration Settings:**
- `rootDomain` - Root server for directory lookup (default: `root.atsign.org`)
- `rootPort` - Root server port (default: 64)
- `atKeysFilePath` - Location of `.atKeys` file (default: `~/.atsign/keys/`)
- `hiveStoragePath` - Location of Hive database (default: `./hive/`)
- `commitLogPath` - Location of commit logs (default: `./commitLog/`)
- `registrarUrl` - Registrar API endpoint for OTP verification
- `apiKey` - API key for registrar (if using custom registrar)
- `namespace` - App namespace for multi-tenant isolation
- `isLocalStoreRequired` - Use Hive local storage (default: true)
- `syncStrategy` - Sync interval and batch size

**Secrets Location:**
- `.atKeys` file contains private encryption and APKAM keys
- CRAM secret: Only used during onboarding, not stored
- API keys: Passed via CLI arguments or preferences
- No `.env` file detected; configuration via code/CLI

## Webhooks & Callbacks

**Incoming:**
- None detected (no webhook receivers)
- Instead uses: `MONITOR` verb for real-time data change notifications
- `NotificationService.subscribe()` for listening to key changes

**Outgoing:**
- `NOTIFY` verb sends notifications to remote atSigns
- Real-time notification protocol via secondary server
- Example: Notifying @bob of new message from @alice
- No HTTP webhooks; uses native atProtocol messaging

**Real-time Streams:**
- `MONITOR` verb: Subscribe to key changes on secondary server
- Returns stream of `AtNotification` events
- Filtered by key pattern regex
- Used by: `MonitorClient` and `NotificationService`

**Stream Notifications (File Transfer):**
- Large file transfer notifications via `AtStreamNotification`
- Separate TCP socket connection for binary data
- Callbacks: `streamCompletionCallBack`, `streamReceiveCallBack`
- Implementation: `packages/at_client/lib/src/stream/stream_notification_handler.dart`

---

*Integration audit: 2026-02-03*
