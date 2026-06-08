# Difference Between `at_client` and `at_client_flutter`

## Summary

`at_client` is the core Dart SDK for the atProtocol. `at_client_flutter` is a Flutter-specific layer that adds authentication dialogs, device keychain integration, and Flutter-aware lifecycle management on top of `at_client`. Flutter apps need both.

---

## `at_client`

**pub.dev:** `at_client: ^3.12.0`

This is the foundation package. Every app that uses the atProtocol — whether it runs as a Dart CLI tool, a server, an IoT device, or a Flutter mobile app — depends on `at_client`.

It provides:

- `AtClient` — the main entry point for all atProtocol operations
- `AtCollection<T>` — the modern typed collection API for storing and sharing data
- `CItem<T>` — a collection item wrapper
- `Query<T>` — an immutable query builder for filtering and sorting collections
- `NotificationService` — for sending and receiving real-time cross-atSign notifications
- `SyncService` — for syncing the local keystore with the atServer
- All collection event streams (`updates`, `deletes`, `readReceipts`, `subUpdates`, etc.)

```yaml
# Dart CLI / server / IoT — at_client only
dependencies:
  at_client: ^3.12.0
```

---

## `at_client_flutter`

**pub.dev:** `at_client_flutter: ^1.1.2`

This package adds the Flutter-specific layer. It does not replace `at_client` — it depends on it. A Flutter app needs both packages.

It provides:

- **Authentication dialogs** — ready-made Flutter widgets for each auth flow:
  - `AtSignSelectionDialog` — lets the user pick or enter an atSign
  - `PkamDialog` — performs PKAM authentication (used in most flows)
  - `CramDialog` / `RegistrarCramDialog` — for activating a brand-new atSign
  - `AtKeysFileDialog` — lets the user pick an `.atKeys` file from their device
  - `ApkamActivationDialog` / `ApkamDialog` — for APKAM multi-device enrollment
- **Device keychain integration:**
  - `KeychainStorage` — reads and writes atSign keys to the iOS Keychain / Android Keystore
  - `KeychainAtKeysIo` — an `AtKeysIo` implementation backed by the device keychain
- **Flutter-aware client lifecycle:**
  - `AtClientManager` — singleton that manages the current authenticated `AtClient` instance
  - `AtClientPreference` — configuration object for namespace, storage paths, root domain, etc.
- **Flutter extensions** via `package:at_client_flutter/extensions.dart`

```yaml
# Flutter app — needs both
dependencies:
  at_client: ^3.12.0
  at_client_flutter: ^1.1.2
```

---

## Side-by-Side Comparison

| | `at_client` | `at_client_flutter` |
|---|---|---|
| **Platform** | Dart (any: CLI, server, IoT, Flutter) | Flutter only |
| **What it provides** | Core protocol, collections, sync, notifications | Auth dialogs, keychain, Flutter lifecycle |
| **Required for** | Every atProtocol app | Flutter apps that need auth UI |
| **Depends on the other?** | No | Yes — depends on `at_client` |
| **Can be used alone?** | Yes (for CLI/server/IoT) | No — always used with `at_client` |

---

## Typical pubspec.yaml by Project Type

### Dart CLI / server / IoT

```yaml
dependencies:
  at_client: ^3.12.0
  at_cli_commons: ^3.1.0   # helpers for headless environments
```

### Flutter mobile / desktop app

```yaml
dependencies:
  at_client: ^3.12.0
  at_client_flutter: ^1.1.2
  at_auth: ^3.1.0          # if using RegistrarService or custom APKAM flows
  path_provider: ^2.0.0    # for getApplicationSupportDirectory()
```

---

## Authentication Flows in Flutter

`at_client_flutter` covers four authentication flows. All of them end with the same `_setupAtClient()` call that initialises `AtClient` via `AtClientManager`.

**Flow 1 — New atSign (CRAM):** Activates a brand-new atSign using a registrar URL and API key.

**Flow 2 — Existing `.atKeys` file:** The user picks an `.atKeys` file from their device. Most common for returning developers.

**Flow 3 — Device keychain:** Fast re-login when the device already has stored keys (iOS Keychain / Android Keystore).

**Flow 4 — APKAM enrollment:** Adds a new device to an existing atSign; requires approval on a manager device.

Example of Flow 2:

```dart
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_client_flutter/extensions.dart';
import 'package:at_auth/at_auth.dart';

Future<void> loginWithFile(BuildContext context) async {
  final atKeysIo = await AtKeysFileDialog.show(context);
  if (atKeysIo == null || !context.mounted) return;

  final authRequest = AtAuthRequest(
    atKeysIo.getAtsign(),            // .getAtsign() comes from extensions.dart
    atKeysIo: atKeysIo,
    rootDomain: AtRootDomain.atsignDomain,
  );
  final response = await PkamDialog.show(
    context,
    request: authRequest,
    backupKeys: [KeychainAtKeysIo()],  // saves to device keychain for future logins
  );
  if (response?.isSuccessful == true) await _setupAtClient(authRequest, response!);
}
```

Post-auth setup (same for all four flows):

```dart
import 'package:path_provider/path_provider.dart';

Future<void> _setupAtClient(AuthRequest authRequest, AuthResponse response) async {
  final dir = await getApplicationSupportDirectory();
  final acp = AtClientPreference()
    ..rootDomain      = authRequest.rootDomain.rootDomain
    ..rootPort        = authRequest.rootDomain.rootPort
    ..namespace       = 'my_namespace'
    ..commitLogPath   = dir.path
    ..hiveStoragePath = dir.path;

  await AtClientManager.getInstance().setCurrentAtSign(
    response.atSign, 'my_namespace', acp,
    enrollmentId: response.enrollmentId,
    atChops:  response.atChops,
    atLookUp: response.atLookUp,
  );
}
```

After setup, get the `AtClient` from the manager:

```dart
final atClient = AtClientManager.getInstance().atClient;
```

To log out:

```dart
AtClientManager.getInstance().reset();
```

---

## Key Imports

```dart
// Core atProtocol + collections API (all platforms)
import 'package:at_client/at_client.dart';

// Flutter auth dialogs + keychain + AtClientManager (Flutter only)
import 'package:at_client_flutter/at_client_flutter.dart';

// Flutter extensions: FileAtKeysIo.getAtsign() helper
import 'package:at_client_flutter/extensions.dart';

// Note: String.toAtsign() comes from at_client/at_client.dart, NOT extensions.dart

// Auth types used across flows (often a transitive dep, pin if using directly)
import 'package:at_auth/at_auth.dart';
```

---

## What to Avoid

- **Never add `at_common_flutter`** — it is deprecated in favour of `at_client_flutter`.
- **Never add `at_backupkey_flutter`** — it is deprecated; copy the backup-key logic into your app directly.
- **Never use `AtCollectionModel`** — it is deprecated. Use `AtCollection<T>` via `atClient.collection(...)`.
