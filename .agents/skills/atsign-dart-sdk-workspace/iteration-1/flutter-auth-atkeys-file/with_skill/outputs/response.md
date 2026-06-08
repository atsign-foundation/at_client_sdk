# Signing In with an atSign Using an .atKeys File in Flutter

This is **Flow 2** in `at_client_flutter` — the standard path for an existing user who has a `.atKeys` file from a previous device or onboarding session.

---

## 1. Add the Required Dependencies

In your `pubspec.yaml`:

```yaml
dependencies:
  at_client: ^3.12.0
  at_client_flutter: ^1.1.2
  at_auth: ^3.1.0
  path_provider: ^2.0.0
```

Do NOT add `at_common_flutter` or `at_backupkey_flutter` — both are deprecated.

---

## 2. Imports

```dart
import 'package:at_client/at_client.dart';
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_client_flutter/extensions.dart'; // adds FileAtKeysIo.getAtsign()
import 'package:at_auth/at_auth.dart';              // AtAuthRequest, AtRootDomain
import 'package:path_provider/path_provider.dart';  // getApplicationSupportDirectory()
```

---

## 3. The Authentication Flow (Step-by-Step)

### Step 1 — User Picks the .atKeys File

```dart
final atKeysIo = await AtKeysFileDialog.show(context);
if (atKeysIo == null || !context.mounted) return;
```

`AtKeysFileDialog.show()` opens a file picker. The user selects their `.atKeys` file. The result is a `FileAtKeysIo` object. If the user cancels, it returns `null`.

### Step 2 — Build the Auth Request

```dart
final authRequest = AtAuthRequest(
  atKeysIo.getAtsign(),              // reads the atSign from the file
  atKeysIo: atKeysIo,
  rootDomain: AtRootDomain.atsignDomain,
);
```

`atKeysIo.getAtsign()` is provided by `at_client_flutter/extensions.dart` — make sure that import is present.

`AtRootDomain.atsignDomain` is the production atSign root domain. Use this for apps connecting to the live atsign.com infrastructure.

### Step 3 — Authenticate with PKAM

```dart
final response = await PkamDialog.show(
  context,
  request: authRequest,
  backupKeys: [KeychainAtKeysIo()],  // saves keys to device keychain for future logins
);
if (response == null || !response.isSuccessful) return;
```

`PkamDialog.show()` performs PKAM (Public Key Authentication Method) authentication against the atServer using the keys in the `.atKeys` file. The `backupKeys` parameter is important: it saves the loaded keys into the device keychain so the user can use Flow 3 (keychain login) on their next session without needing the file again.

### Step 4 — Initialize AtClient

After a successful authentication, you must call `_setupAtClient` to finish wiring everything up:

```dart
await _setupAtClient(authRequest, response);
```

---

## 4. Complete loginWithFile Function

```dart
Future<void> loginWithFile(BuildContext context) async {
  // Step 1: User picks the .atKeys file
  final atKeysIo = await AtKeysFileDialog.show(context);
  if (atKeysIo == null || !context.mounted) return;

  // Step 2: Build the auth request from the file
  final authRequest = AtAuthRequest(
    atKeysIo.getAtsign(),
    atKeysIo: atKeysIo,
    rootDomain: AtRootDomain.atsignDomain,
  );

  // Step 3: Authenticate (PKAM) and save to device keychain
  final response = await PkamDialog.show(
    context,
    request: authRequest,
    backupKeys: [KeychainAtKeysIo()],
  );
  if (response == null || !response.isSuccessful) return;

  // Step 4: Set up AtClient
  await _setupAtClient(authRequest, response);
}
```

---

## 5. Post-Auth Setup (_setupAtClient)

This helper is shared by all four auth flows. The `AuthRequest` parameter is the sealed base type, so it works with both `AtAuthRequest` (Flows 2, 3, 4) and `AtOnboardingRequest` (Flow 1).

```dart
Future<void> _setupAtClient(
  AuthRequest authRequest,
  AuthResponse response,
) async {
  final dir = await getApplicationSupportDirectory();

  final acp = AtClientPreference()
    ..rootDomain      = authRequest.rootDomain.rootDomain
    ..rootPort        = authRequest.rootDomain.rootPort
    ..namespace       = 'my_namespace'   // replace with your app namespace
    ..commitLogPath   = dir.path
    ..hiveStoragePath = dir.path;

  await AtClientManager.getInstance().setCurrentAtSign(
    response.atSign,
    'my_namespace',   // must match acp.namespace
    acp,
    enrollmentId: response.enrollmentId,
    atChops:  response.atChops,
    atLookUp: response.atLookUp,
  );
}
```

Key notes:
- Use `rootDomain` and `rootPort` from `authRequest.rootDomain` — do not hard-code them.
- Use `atChops` and `atLookUp` from the `response`, not freshly constructed — they are already authenticated instances.
- `namespace` must match the suffix used in your `AtCollection` calls (e.g., if your collection is `'todos.my_namespace'`, then `namespace` should be `'my_namespace'`).

---

## 6. Getting the AtClient After Setup

Once `_setupAtClient` completes successfully, retrieve the `AtClient` singleton:

```dart
final atClient = AtClientManager.getInstance().atClient;
```

From here you can create collections, run queries, etc.:

```dart
final todos = await atClient.collection<Todo>(
  'todos.my_namespace',
  const Duration(days: 7),
  fromJson: Todo.fromJson,
  typeTag: 'Todo',
);
```

---

## 7. Logout

```dart
AtClientManager.getInstance().reset();
```

---

## 8. What Happens on the Next Login?

Because you passed `backupKeys: [KeychainAtKeysIo()]` in Step 3, the user's keys are now stored in the device keychain (iOS Keychain / Android Keystore). On their next session, they can skip the file picker entirely and use Flow 3 (keychain login):

```dart
// Flow 3 — no .atKeys file needed after first login
final atSigns = await KeychainStorage().getAllAtsigns();
final request = await AtSignSelectionDialog.show(context, existingAtSigns: atSigns);
final authRequest = AtAuthRequest(
  request!.atSign,
  atKeysIo: KeychainAtKeysIo(),
  rootDomain: request.rootDomain,
);
final response = await PkamDialog.show(context, request: authRequest, backupKeys: [KeychainAtKeysIo()]);
if (response?.isSuccessful == true) await _setupAtClient(authRequest, response!);
```

---

## 9. Summary of the Full Flow

```
User taps "Sign In with .atKeys file"
        |
        v
AtKeysFileDialog.show(context)
  → user selects file → returns FileAtKeysIo
        |
        v
AtAuthRequest(atKeysIo.getAtsign(), atKeysIo: atKeysIo, rootDomain: ...)
        |
        v
PkamDialog.show(context, request: authRequest, backupKeys: [KeychainAtKeysIo()])
  → PKAM handshake with atServer
  → keys saved to device keychain
  → returns AuthResponse (isSuccessful: true)
        |
        v
_setupAtClient(authRequest, response)
  → AtClientManager.getInstance().setCurrentAtSign(...)
        |
        v
AtClientManager.getInstance().atClient   ← ready to use
```

---

## 10. Canonical Example

The full working implementation of this flow (alongside Flows 3 and 4) is in the todos reference app:

```
packages/at_client_flutter/examples/todos/lib/onboarding.dart
```

This file shows all three non-CRAM flows wired together in a single onboarding screen.
