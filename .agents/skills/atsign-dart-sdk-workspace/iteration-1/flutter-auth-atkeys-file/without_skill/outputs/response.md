# Flutter atSign Authentication Flow: Existing User with .atKeys File

## Overview

An atSign is a unique identifier (e.g., `@alice`) on the atPlatform. When a user already has a `.atKeys` file, it means they have previously onboarded and their cryptographic keys have been generated and exported. The `.atKeys` file contains the encrypted private keys needed to authenticate with the atServer.

The authentication flow for an existing user involves importing the `.atKeys` file, decrypting it with the user's secret phrase (the backup key password), and then authenticating with the atServer using PKAM (Public Key Authentication Mechanism).

---

## Key Concepts

- **.atKeys file**: A JSON file containing the atSign's encrypted cryptographic keys (PKAM private key, encryption keys, etc.).
- **PKAM**: Public Key Authentication Mechanism — the atPlatform's method for authenticating an atSign owner to their atServer.
- **AtClientManager**: The central singleton for managing atSign client sessions in the Dart/Flutter SDK.
- **OnboardingService**: A service provided by the `at_onboarding_flutter` package (or similar) that handles the onboarding and key management workflow.

---

## Packages Involved

The typical packages used for this flow are:

- `at_client_mobile` — mobile-specific atClient implementation
- `at_onboarding_flutter` — UI and logic for onboarding/authentication (wraps the lower-level SDK)
- `at_utils` — utilities including atSign formatting

For lower-level control without the UI package, you would use:

- `at_client` — core client SDK
- `at_chops` — cryptographic operations

---

## High-Level Flow

```
1. User provides their atSign (@alice)
2. User selects their .atKeys file (via file picker)
3. App reads the .atKeys file contents (a JSON string)
4. User enters the backup key passphrase (used to encrypt the keys at export time)
   -- OR the file may be unencrypted in older versions --
5. The keys are decrypted and stored in the device's secure keystore
6. AtClientManager is initialized with the atSign and preference settings
7. PKAM authentication is performed against the atServer
8. On success, the user is authenticated and the app can proceed
```

---

## Detailed Steps

### Step 1: Initialize AtClientPreference

```dart
AtClientPreference buildAtClientPreference() {
  return AtClientPreference()
    ..rootDomain = 'root.atsign.org'   // production root
    ..namespace = 'my_app'             // your app's namespace
    ..hiveStoragePath = '/path/to/hive/storage'  // from path_provider
    ..commitLogPath = '/path/to/commit/log'
    ..isLocalStoreRequired = true;
}
```

### Step 2: Pick the .atKeys File

Use a file picker (e.g., `file_picker` package) to let the user select their `.atKeys` file:

```dart
import 'package:file_picker/file_picker.dart';

Future<String?> pickAtKeysFile() async {
  FilePickerResult? result = await FilePicker.platform.pickFiles(
    type: FileType.any,
    allowMultiple: false,
  );
  if (result != null && result.files.single.path != null) {
    final file = File(result.files.single.path!);
    return await file.readAsString();
  }
  return null;
}
```

### Step 3: Onboard with the .atKeys File Contents

Using the `at_onboarding_flutter` package's `OnboardingService`:

```dart
import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';

Future<void> authenticateWithAtKeysFile({
  required String atSign,
  required String atKeysFileContent,
  required AtClientPreference preference,
}) async {
  final onboardingService = OnboardingService.getInstance()
    ..setAtClientPreference = preference
    ..setAtSign = atSign;

  // The atKeys JSON string is passed directly.
  // If the file is encrypted with a passphrase, supply it here.
  await onboardingService.authenticate(atSign, jsonData: atKeysFileContent, decryptKey: userPassphrase);
}
```

If you are using the lower-level SDK without the onboarding package:

```dart
import 'package:at_client_mobile/at_client_mobile.dart';
import 'dart:convert';

Future<void> onboardWithAtKeys({
  required String atSign,
  required String atKeysJson,
  required AtClientPreference preference,
}) async {
  final atClientManager = await AtClientManager.getInstance()
      .setCurrentAtSign(atSign, 'my_app', preference);

  // Parse the .atKeys JSON
  final keysMap = jsonDecode(atKeysJson) as Map<String, dynamic>;

  // Store keys in the local keystore (KeyChain on iOS, Keystore on Android)
  final keyChainManager = KeyChainManager.getInstance();
  await keyChainManager.storeAtKeysData(atSign, keysMap);

  // Authenticate (PKAM)
  final atClient = AtClientManager.getInstance().atClient;
  final authenticated = await atClient.authenticate(atSign);
  if (!authenticated) {
    throw Exception('Authentication failed for $atSign');
  }
}
```

### Step 4: Handle the AtClientManager After Authentication

Once authenticated, `AtClientManager.getInstance()` gives you a fully initialized client:

```dart
final atClient = AtClientManager.getInstance().atClient;

// Example: get a value
final atKey = AtKey()
  ..key = 'name'
  ..sharedBy = '@alice';

final result = await atClient.get(atKey);
print(result.value); // 'Alice Wonderland'
```

---

## Using the at_onboarding_flutter UI Package (Recommended Approach)

The `at_onboarding_flutter` package provides a ready-made UI flow that handles `.atKeys` file import automatically:

```dart
import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';

// In your widget:
OnboardingWidget(
  domain: 'root.atsign.org',
  atClientPreference: myAtClientPreference,
  appAPIKey: 'your-registrar-api-key',  // only needed for new registrations
  onboard: (value, atsign) {
    // value is a Map containing the onboarding result
    // atsign is the successfully authenticated atSign
    Navigator.pushReplacementNamed(context, '/home');
  },
  onError: (error) {
    print('Onboarding error: $error');
  },
  nextScreen: HomeScreen(),
);
```

The widget automatically provides:
- A QR code scanner option (for new onboarding)
- A "Upload .atKeys file" button for existing users
- Passphrase entry if the keys file is encrypted
- PKAM authentication on success

---

## .atKeys File Format

A `.atKeys` file is a JSON object with keys like:

```json
{
  "@alice:pkamPrivateKey@alice": "<encrypted_or_plaintext_private_key>",
  "@alice:pkamPublicKey@alice": "<public_key>",
  "@alice:encryptionPrivateKey@alice": "<encrypted_private_key>",
  "@alice:encryptionPublicKey@alice": "<public_key>",
  "@alice:selfEncryptionKey@alice": "<encrypted_aes_key>"
}
```

In older SDK versions these may be unencrypted base64 strings. In newer versions the private keys are AES-encrypted with a passphrase derived from the user's backup key (the 30-character secret shown during onboarding).

---

## Error Handling

Common errors to handle:

| Error | Cause | Resolution |
|---|---|---|
| `KeyNotFoundException` | atSign keys not found in keystore | Ensure keys were stored correctly before authenticating |
| `UnAuthenticatedException` | PKAM failed | Keys may be wrong, corrupted, or atServer unreachable |
| `InvalidAtSignException` | Malformed atSign string | Normalize with `AtUtils.fixAtSign(atSign)` |
| `AtConnectException` | Cannot reach atServer | Check network / root domain |
| `InvalidBackupKeyException` | Wrong passphrase for encrypted .atKeys | Prompt user to re-enter passphrase |

---

## Important Notes

1. **Normalize the atSign** before any operation: `AtUtils.fixAtSign('@Alice')` returns `@alice`.
2. **Storage paths** must be obtained from `path_provider` at runtime (e.g., `getApplicationSupportDirectory()`). Do not hardcode them.
3. **The backup key / passphrase** is the 30-character secret the user received when they first onboarded. Without it, an encrypted `.atKeys` file cannot be used.
4. **One atSign per session** — `AtClientManager` manages one active atSign at a time. If your app supports switching atSigns, call `AtClientManager.getInstance().setCurrentAtSign(...)` again.
5. **Keys are stored on-device** after the first import. Subsequent app launches only need `AtClientManager.getInstance().setCurrentAtSign(...)` with the preference — no need to re-import the `.atKeys` file.
