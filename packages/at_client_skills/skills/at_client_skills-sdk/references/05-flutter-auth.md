<!-- verified: at_client_flutter ^1.1.2 — update on next minor release -->

# Flutter Auth Guide

`at_client_flutter` provides four authentication flows as dialog-based helpers.
All flows end with the same `_setupAtClient(...)` call.

## pubspec.yaml

```yaml
dependencies:
  at_client: ^3.12.0
  at_client_flutter: ^1.1.2
  at_auth: ^3.1.0
  path_provider: ^2.0.0  # for getApplicationSupportDirectory()
```

---

## Flow 1: New atSign — CRAM Activation (first-time only)

Use when a developer wants to activate a brand-new atSign for a user.
Requires a `RegistrarService` configured with a registrar URL and API key.

```dart
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_auth/at_auth.dart';

// Configure registrar (typically once at app startup)
final registrar = RegistrarService(
  registrarUrl: 'my.atsign.com',
  apiKey: 'your-api-key',        // get from atsign.com developer portal
);

Future<void> activateNewAtSign(BuildContext context) async {
  // Step 1: User picks / types an atSign
  AuthRequest? authRequest = await AtSignSelectionDialog.show(context);
  if (authRequest == null || !context.mounted) return;

  // Step 2: Obtain CRAM key from registrar
  final cramKey = await RegistrarCramDialog.show(
    context,
    authRequest as AtOnboardingRequest,
    registrar: registrar,
  );
  if (cramKey == null || !context.mounted) return;

  // Step 3: Complete onboarding with CRAM key
  final response = await CramDialog.show(
    context,
    request: authRequest,
    cramKey: cramKey,
  );
  if (response == null || !response.isSuccessful) return;

  await _setupAtClient(authRequest, response);
}
```

---

## Flow 2: Existing .atKeys File

Use when the user has an `.atKeys` file (typically from a previous device).

```dart
Future<void> loginWithFile(BuildContext context) async {
  // Step 1: User picks the .atKeys file
  final atKeysIo = await AtKeysFileDialog.show(context);
  if (atKeysIo == null || !context.mounted) return;

  // Step 2: Authenticate
  final authRequest = AtAuthRequest(
    atKeysIo.getAtsign(),
    atKeysIo: atKeysIo,
    rootDomain: AtRootDomain.atsignDomain,
  );
  final response = await PkamDialog.show(
    context,
    request: authRequest,
    backupKeys: [KeychainAtKeysIo()],   // saves to device keychain for future logins
  );
  if (response == null || !response.isSuccessful) return;

  await _setupAtClient(authRequest, response);
}
```

---

## Flow 3: Device Keychain (Returning User)

Use for fast re-login on a device that has already onboarded an atSign.
Reads existing atSigns from the device keychain (iOS Keychain /
Android Keystore).

```dart
Future<void> loginWithKeychain(BuildContext context) async {
  // Step 1: Read atSigns already stored on this device
  final atSigns = await KeychainStorage().getAllAtsigns();
  if (atSigns.isEmpty) {
    _showMessage(context, 'No atSigns in keychain. Onboard one first.');
    return;
  }
  if (!context.mounted) return;

  // Step 2: User picks an atSign from the list
  final request = await AtSignSelectionDialog.show(
    context,
    existingAtSigns: atSigns,
  );
  if (request == null || !context.mounted) return;

  // Step 3: Authenticate from keychain
  final authRequest = AtAuthRequest(
    request.atSign,
    atKeysIo: KeychainAtKeysIo(),
    rootDomain: request.rootDomain,
  );
  final response = await PkamDialog.show(
    context,
    request: authRequest,
    backupKeys: [KeychainAtKeysIo()],
  );
  if (response == null || !response.isSuccessful) return;

  await _setupAtClient(authRequest, response);
}
```

---

## Flow 4: APKAM — New Device Enrollment

Use when a user wants to add a new device to an existing atSign.
The manager device (another phone already authenticated) must approve
the enrollment.

```dart
Future<void> loginWithApkam(BuildContext context) async {
  // Step 1: User picks an atSign to enroll this device with
  final request = await AtSignSelectionDialog.show(context);
  if (request == null || !context.mounted) return;

  // Step 2: Send enrollment request (user approves on another device)
  final enrollment = await ApkamActivationDialog.show(
    context,
    atSign: request.atSign,
    rootDomain: request.rootDomain,
    appName: 'my_app',             // must match what the manager device sees
    deviceName: 'default',
    namespaces: {'my_namespace': 'rw'},   // permissions this device needs
  );
  if (enrollment?.atAuthKeys == null || !context.mounted) return;

  // Step 3: Authenticate with the enrolled keys
  final authRequest = AtAuthRequest(
    request.atSign,
    atAuthKeys: enrollment!.atAuthKeys!,
    rootDomain: request.rootDomain,
  );
  final response = await PkamDialog.show(
    context,
    request: authRequest,
    backupKeys: [KeychainAtKeysIo()],
  );
  if (response == null || !response.isSuccessful) return;

  await _setupAtClient(authRequest, response);
}
```

---

## Post-Auth Setup (all flows)

After any successful authentication, initialize `AtClient`:

```dart
import 'package:path_provider/path_provider.dart' show getApplicationSupportDirectory;

// authRequest is typed as the sealed base AuthRequest so this helper works for
// all four flows. (AtAuthRequest and AtOnboardingRequest are sibling subtypes —
// neither is a subtype of the other.)
Future<void> _setupAtClient(
  AuthRequest authRequest,
  AuthResponse response,
) async {
  final dir = await getApplicationSupportDirectory();

  final acp = AtClientPreference()
    ..rootDomain    = authRequest.rootDomain.rootDomain
    ..rootPort      = authRequest.rootDomain.rootPort
    ..namespace     = 'my_namespace'
    ..commitLogPath  = dir.path
    ..hiveStoragePath = dir.path;

  await AtClientManager.getInstance().setCurrentAtSign(
    response.atSign,
    'my_namespace',
    acp,
    enrollmentId: response.enrollmentId,
    atChops:  response.atChops,
    atLookUp: response.atLookUp,
  );
}
```

**AtClientPreference required fields:**

| Field | Type | Description |
| ------- | ------ | ------------- |
| `namespace` | `String` | App namespace — must match `AtCollection` namespace suffix |
| `commitLogPath` | `String` | Path to local commit log directory |
| `hiveStoragePath` | `String` | Path to Hive storage directory |
| `rootDomain` | `String` | atServer root domain (from `authRequest.rootDomain.rootDomain`) |
| `rootPort` | `int` | atServer root port (from `authRequest.rootDomain.rootPort`) |

**Important:** Use `atChops` and `atLookUp` from the `response` (not freshly
created) — these are already authenticated instances.

---

## Logout

```dart
AtClientManager.getInstance().reset();
```

---

## Getting the AtClient After Setup

```dart
final atClient = AtClientManager.getInstance().atClient;
// Then: await atClient.collection<Todo>('todos.my_namespace', ttl, ...);
```

---

## Canonical Examples

<!-- pyml disable-num-lines 2 md013-->
- [packages/at_client_flutter/examples/todos/lib/onboarding.dart](../../packages/at_client_flutter/examples/todos/lib/onboarding.dart) — Flows 2, 3, 4 with `_setupAtClient`
- [packages/at_client_flutter/example/lib/walkthrough.dart](../../packages/at_client_flutter/example/lib/walkthrough.dart) — All 4 flows in one file

---

## Key Imports

```dart
import 'package:at_client_flutter/at_client_flutter.dart';
// Exports: AtSignSelectionDialog, PkamDialog, CramDialog, RegistrarCramDialog,
//          AtKeysFileDialog, ApkamActivationDialog, ApkamDialog, KeychainStorage,
//          KeychainAtKeysIo, AtClientPreference, AtClientManager

import 'package:at_client_flutter/extensions.dart';
// Adds FileAtKeysIo.getAtsign() helper (used in Flow 2).
// Note: String.toAtsign() comes from at_client/at_client.dart, NOT this import.

import 'package:at_auth/at_auth.dart';
// AtAuthRequest, AuthResponse, AtAuthenticationException, AtOnboardingRequest,
// AtEnrollmentResponse, AtRootDomain, RegistrarService
```
