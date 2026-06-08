# Setting Up APKAM Enrollment to Add a New Device to an Existing atSign

APKAM (Application Key Management) enrollment is the process by which a user adds a new device to an existing atSign. A manager device (another phone or client already authenticated with the atSign) must approve the request before the new device can authenticate.

---

## 1. Add the Required Dependencies

```yaml
dependencies:
  at_client: ^3.12.0
  at_client_flutter: ^1.1.2
  at_auth: ^3.1.0          # provides AtAuthRequest, AtEnrollmentResponse, AtRootDomain
  path_provider: ^2.0.0    # for getApplicationSupportDirectory()
```

> `at_auth` may be a transitive dependency for standard Flutter apps using the dialog helpers, but add it explicitly if you reference its types directly (e.g., `AtAuthRequest`, `AtEnrollmentResponse`).

---

## 2. Key Imports

```dart
import 'package:at_client_flutter/at_client_flutter.dart';
// Exports: ApkamActivationDialog, PkamDialog, AtSignSelectionDialog,
//          KeychainAtKeysIo, KeychainStorage, AtClientPreference, AtClientManager

import 'package:at_auth/at_auth.dart';
// Exports: AtAuthRequest, AuthResponse, AtEnrollmentResponse, AtRootDomain

import 'package:path_provider/path_provider.dart';
// for getApplicationSupportDirectory()
```

---

## 3. Implement APKAM Enrollment (Flow 4)

APKAM enrollment involves three steps:

1. The user selects the atSign to enroll on the new device.
2. The new device sends an enrollment request; the manager device approves it.
3. The new device authenticates using the enrolled keys and initializes `AtClient`.

```dart
Future<void> loginWithApkam(BuildContext context) async {
  // Step 1: User picks the atSign to enroll this device with
  final request = await AtSignSelectionDialog.show(context);
  if (request == null || !context.mounted) return;

  // Step 2: Send enrollment request — user must approve on the manager device
  //         ApkamActivationDialog polls until approval is granted or times out
  final enrollment = await ApkamActivationDialog.show(
    context,
    atSign: request.atSign,
    rootDomain: request.rootDomain,
    appName: 'my_app',                      // must match what the manager device sees
    deviceName: 'default',                  // a human-readable name for this device
    namespaces: {'my_namespace': 'rw'},     // permissions this device needs
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
    backupKeys: [KeychainAtKeysIo()],   // saves keys to device keychain for future logins
  );
  if (response == null || !response.isSuccessful) return;

  await _setupAtClient(authRequest, response);
}
```

### Notes on `ApkamActivationDialog.show()`

| Parameter | Required | Description |
|-----------|----------|-------------|
| `atSign` | Yes | The existing atSign the new device is enrolling with |
| `rootDomain` | Yes | The atServer root domain (from `AtSignSelectionDialog` result) |
| `appName` | Yes | Application name — must match what the manager device sees in its approval UI |
| `deviceName` | Yes | Human-readable name for this device |
| `namespaces` | Yes | Map of namespace to permission level (`'rw'` for read-write, `'r'` for read-only) |

The dialog polls the atServer until the manager device approves (or the user cancels). Once approved, it returns an `AtEnrollmentResponse` containing `atAuthKeys`.

---

## 4. Post-Auth Setup (identical for all flows)

After a successful `PkamDialog.show()`, initialize `AtClientManager`:

```dart
import 'package:path_provider/path_provider.dart' show getApplicationSupportDirectory;

// authRequest is the sealed base AuthRequest — works for all four auth flows.
Future<void> _setupAtClient(
  AuthRequest authRequest,
  AuthResponse response,
) async {
  final dir = await getApplicationSupportDirectory();

  final acp = AtClientPreference()
    ..rootDomain      = authRequest.rootDomain.rootDomain
    ..rootPort        = authRequest.rootDomain.rootPort
    ..namespace       = 'my_namespace'
    ..commitLogPath   = dir.path
    ..hiveStoragePath = dir.path;

  await AtClientManager.getInstance().setCurrentAtSign(
    response.atSign,
    'my_namespace',
    acp,
    enrollmentId: response.enrollmentId,  // important: pass the enrollment ID
    atChops:  response.atChops,           // use response instances — already authenticated
    atLookUp: response.atLookUp,
  );
}
```

**Important:** Always pass `enrollmentId`, `atChops`, and `atLookUp` from the `response` object — do not create new instances of these. They are already authenticated.

### Required `AtClientPreference` fields

| Field | Description |
|-------|-------------|
| `namespace` | App namespace — must match the `AtCollection` namespace suffix |
| `commitLogPath` | Path to local commit log directory |
| `hiveStoragePath` | Path to Hive storage directory |
| `rootDomain` | atServer root domain |
| `rootPort` | atServer root port |

---

## 5. After Setup: Get the AtClient

```dart
final atClient = AtClientManager.getInstance().atClient;
// Now use atClient normally, e.g.:
final todos = await atClient.collection<Todo>(
  'todos.my_namespace',
  const Duration(days: 7),
  fromJson: Todo.fromJson,
  typeTag: 'Todo',
);
```

---

## 6. Logout

```dart
AtClientManager.getInstance().reset();
```

---

## 7. How It Differs from Other Auth Flows

| Flow | When to use |
|------|-------------|
| Flow 1: CRAM | Activating a brand-new atSign (first-time only) |
| Flow 2: .atKeys file | Returning user with an `.atKeys` backup file |
| Flow 3: Device keychain | Returning user on a device that already has the keys |
| **Flow 4: APKAM** | **Adding a new device to an existing atSign — manager must approve** |

All four flows converge on the same `_setupAtClient()` helper.

---

## 8. Complete Worked Example

```dart
import 'package:flutter/material.dart';
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_auth/at_auth.dart';
import 'package:path_provider/path_provider.dart';

class ApkamEnrollmentPage extends StatelessWidget {
  const ApkamEnrollmentPage({super.key});

  Future<void> _enroll(BuildContext context) async {
    // 1. User selects the atSign
    final request = await AtSignSelectionDialog.show(context);
    if (request == null || !context.mounted) return;

    // 2. Send enrollment request and wait for manager approval
    final enrollment = await ApkamActivationDialog.show(
      context,
      atSign: request.atSign,
      rootDomain: request.rootDomain,
      appName: 'my_app',
      deviceName: 'default',
      namespaces: {'my_namespace': 'rw'},
    );
    if (enrollment?.atAuthKeys == null || !context.mounted) return;

    // 3. Authenticate with enrolled keys
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
    if (response == null || !response.isSuccessful || !context.mounted) return;

    // 4. Initialize AtClient
    await _setupAtClient(authRequest, response);

    // 5. Navigate to main app
    if (context.mounted) {
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  Future<void> _setupAtClient(
    AuthRequest authRequest,
    AuthResponse response,
  ) async {
    final dir = await getApplicationSupportDirectory();
    final acp = AtClientPreference()
      ..rootDomain      = authRequest.rootDomain.rootDomain
      ..rootPort        = authRequest.rootDomain.rootPort
      ..namespace       = 'my_namespace'
      ..commitLogPath   = dir.path
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add This Device')),
      body: Center(
        child: ElevatedButton(
          onPressed: () => _enroll(context),
          child: const Text('Enroll with APKAM'),
        ),
      ),
    );
  }
}
```

---

## 9. Canonical Reference

For a full working implementation showing all four flows side-by-side, see:

- `packages/at_client_flutter/examples/todos/lib/onboarding.dart` — Flows 2, 3, and 4 with `_setupAtClient`
- `packages/at_client_flutter/example/lib/walkthrough.dart` — All 4 flows in one file
