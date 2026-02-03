# Technology Stack

**Analysis Date:** 2026-02-03

## Languages

**Primary:**
- Dart 3.6.0+ - Core SDK and all backend packages
- Dart for Flutter - Mobile/desktop development

**Secondary:**
- YAML - Configuration and workflow files
- Shell - CLI scripts and tooling

## Runtime

**Environment:**
- Dart SDK: `^3.6.0`
- Flutter SDK: `^3.29.2` (ships with Dart 3.7.2)

**Package Manager:**
- Pub (Dart package manager)
- Melos 7.0.0-dev.8 - Monorepo management tool
- Lockfile: `pubspec.lock` (present, managed by pub)

## Frameworks

**Core SDKs:**
- `at_client` v3.11.0 - Platform-agnostic atProtocol client SDK
- `at_client_flutter` v0.1.2 - Flutter extension with mobile/desktop support

**Authentication & Onboarding:**
- `at_auth` v3.0.0 - CRAM/PKAM/APKAM authentication
- `at_onboarding_cli` v1.15.0 - CLI tools for onboarding and enrollment management

**Protocol & Communication:**
- `at_lookup` v3.5.0 - Low-level atProtocol verb execution
- `at_commons` v5.8.0 - Shared data models and utilities

**Cryptography:**
- `at_chops` v3.0.0 - Cryptographic operations (RSA, AES, ECC, key generation)

**Utilities:**
- `at_utils` v3.4.0 - Shared utility functions
- `at_server_status` v1.1.0 - Server health and status checking
- `at_policy` - Policy management
- `at_contact` - Contact data structures
- `at_cli_commons` - CLI utilities

**Testing:**
- `test` v1.25.0 - Unit testing framework
- `flutter_test` (SDK) - Flutter testing
- `mocktail` v1.0.4 - Mocking library

**Build & Code Generation:**
- `build_runner` v2.4.13 - Code generation runner
- `json_serializable` v6.9.0 - JSON serialization code generation
- `json_annotation` v4.9.0 - JSON annotation library

**Code Quality:**
- `lints` v6.0.0 - Dart linting rules
- `flutter_lints` v6.0.0 - Flutter-specific linting rules
- `dart_periphery` v0.9.5 - Unused code detection
- `coverage` v1.14.0 - Code coverage reporting

**Development:**
- `melos` v7.0.0-dev.8 - Workspace task orchestration
- `build_version` v2.1.1 - Version management

## Key Dependencies

**Critical Cryptography:**
- `encrypt` v5.0.3 - Encryption/decryption operations (AES, RSA)
- `cryptography` v2.7.0 - Cryptographic algorithms
- `better_cryptography` v1.0.0+1 - Enhanced cryptography primitives
- `pointycastle` v3.9.1 - Elliptic curve and asymmetric crypto
- `crypton` v2.2.1 - RSA/ECC key operations
- `ecdsa` v0.1.0 - ECDSA signing
- `elliptic` v0.3.10 - Elliptic curve math
- `crypto` v3.0.5 - Hash algorithms (MD5, SHA, HMAC)
- `asn1lib` v1.5.3 - ASN.1 encoding/decoding

**Data & Serialization:**
- `archive` v4.0.7 - ZIP/TAR file handling
- `yaml` v3.1.0 - YAML parsing
- `convert` v3.0.2 - Base64/Base16 encoding

**Storage & Persistence:**
- `hive` v2.2.3 - Local key-value store (Hive DB)
- `shared_preferences` v2.2.2 - Flutter shared preferences
- `biometric_storage` v5.0.0 - Secure biometric-locked key storage
- `flutter_keychain` v2.2.1 - iOS keychain access
- `at_persistence_secondary_server` v4.2.0 - Remote server persistence layer
- `at_persistence_spec` v3.0.0 - Storage specification abstraction
- `path_provider` v2.1.2 - File system paths

**HTTP & Networking:**
- `http` v1.2.1 - HTTP client for REST calls
- `internet_connection_checker` v1.0.0+1 - Connectivity detection

**UI & Mobile (Flutter-specific):**
- `flutter` (SDK) - Flutter framework
- `flutter_image` v4.1.8 (FIXME: discontinued) - Image caching
- `cached_network_image` v3.3.1 - Network image caching
- `image` v4.1.7 - Image processing
- `image_compression` v1.0.4 - Image compression
- `flutter_image_compress` v2.0.4 - Flutter image compression
- `qr_code_scanner` v1.0.1 - QR code scanning
- `zxing2` v0.2.0 - 2D barcode reading
- `file_picker` v10.3.8 - File selection UI
- `flutter_local_notifications` v19.0.0 - Local push notifications
- `fluttertoast` v8.2.2 - Toast notifications
- `flutter_toastr` v1.0.3 - Alternative toast notifications
- `flutter_slidable` v4.0.0 - Swipe actions
- `sliding_up_panel` v2.0.0+1 - Bottom panel widget
- `emoji_picker_flutter` v4.3.0 - Emoji selector
- `positioned_tap_detector_2` v1.0.4 - Position-aware tap detection
- `showcaseview` v4.0.1 - Widget showcase/tutorial
- `tutorial_coach_mark` v1.2.11 - Interactive tutorials
- `webview_flutter` v4.5.0 - WebView widget
- `share_plus` v11.0.0 - System share functionality
- `url_launcher` v6.2.4 - URL and app launching
- `uni_links` v0.5.1 (FIXME: discontinued, replace with app_links) - Deep linking
- `geolocator` v14.0.0 - Geolocation services
- `permission_handler` v12.0.0 - Permission management
- `device_info_plus` v11.3.3 - Device information
- `package_info_plus` v8.0.0 - App package information
- `intl` v0.20.2 - Internationalization
- `phosphor_flutter` v2.1.0 - Icon library

**Utilities:**
- `uuid` v4.0.0 - UUID generation
- `version` v3.0.2 - Version parsing and comparison
- `at_base2e15` v1.0.0 - Base2e15 encoding for special characters
- `at_utf7` v1.0.0 - UTF-7 encoding
- `collection` v1.16.0+ - Collection utilities
- `async` v2.9.0 - Async utilities
- `meta` v1.16.0 - Metadata annotations
- `mutex` v3.0.0+ - Mutual exclusion/synchronization
- `args` v2.6.0 - Command-line argument parsing
- `basic_utils` v5.6.1 - Basic utility functions
- `path` v1.9.0 - Path manipulation
- `duration` v4.0.3 - Duration parsing and formatting
- `vector_math` v2.1.4 - Vector and matrix math
- `tuple` v2.0.2 (TODO: replace with Dart records) - Tuple data structure
- `latlong2` v0.9.1 - LatLng coordinate representation
- `proj4dart` v2.1.0 - Cartographic projection
- `transparent_image` v2.0.1 - Transparent image data
- `chalkdart` v2.0.9-3.9.x - Colored console output
- `logging` v1.2.0 - Logging framework
- `cron` v0.5.1 - Cron expression parsing
- `provider` v6.0.5 - State management
- `at_demo_data` v1.2.0 (dev) - Test data fixtures

**CLI & Tooling (Dev):**
- `alfred` v1.1.2+1 - HTTP server for testing
- `test_process` v2.1.0 - Process testing utilities

## Configuration

**Environment:**
- Configured via command-line arguments (`AuthCliArgs`, `AtOnboardingPreference`)
- Root domain: `root.atsign.org` (default), customizable via `AtRootDomain`
- Storage paths: `~/.atsign/keys/` for .atKeys files, `./hive/` for local data (configurable)
- Registrar URL: Customizable endpoint for OTP/activation API

**Build:**
- No special build configuration files detected
- Melos workspace configuration: `melos.yaml` for multi-package management
- Pubspec workspaces: Root `pubspec.yaml` defines 13+ workspace packages

**Environment Variables:**
- None detected as hardcoded requirements
- Configuration via `AtClientPreference` and `AtOnboardingPreference` objects

## Platform Requirements

**Development:**
- Dart 3.6.0+
- Flutter 3.29.2+ (for Flutter packages)
- Node.js/npm (optional, for certain CI workflows)
- Docker (for functional testing with atServer)

**Production:**
- Dart runtime 3.6.0+ for backend packages
- Flutter runtime 3.29.2+ for mobile/desktop apps
- Connection to atServer (secondary server at `root.atsign.org` on port 64)
- File system access for `.atKeys` storage (or alternative `AtKeysIo` implementation)
- Secure socket connections (TLS/SSL to atServers)

**Deployment:**
- Supports multiple deployment targets:
  - **Dart CLI**: Linux, macOS, Windows (via Dart native executables)
  - **Flutter Mobile**: iOS 14.0+, Android API 21+ (via flutter_version constraints)
  - **Flutter Desktop**: macOS, Windows, Linux (via Flutter desktop support)

---

*Stack analysis: 2026-02-03*
