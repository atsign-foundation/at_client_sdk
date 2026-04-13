<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>


[![pub package](https://img.shields.io/pub/v/at_client_flutter)](https://pub.dev/packages/at_client_flutter) [![pub points](https://img.shields.io/badge/dynamic/json?url=https://pub.dev/api/packages/at_client_flutter/score&label=pub%20score&query=grantedPoints)](https://pub.dev/packages/at_client_flutter/score) [![build status](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_client_sdk.yaml/badge.svg?branch=trunk)](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_client_sdk.yaml) [![gitHub license](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)

# at_client_flutter

### Introduction

A Flutter extension to the at_client library which adds support for mobile, desktop, and IoT devices.

SDK that provides the essential methods for building an app using [The atProtocol](https://atsign.com/flip-the-internet/). You may also want to look at [at_client](https://pub.dev/packages/at_client).

**at_client_flutter** package is written in Dart, supports Flutter, and follows the
atPlatform's decentralized, edge computing model with the following features: 
- Cryptographic control of data access through personal data stores
- No application backend needed
- End to end encryption where only the data owner has the keys
- Private and surveillance free connectivity

We call giving people control of access to their data "*flipping the internet*".

## Get Started

> Before using this package for the first time, you should follow the
> [getting started guide](https://docs.atsign.com/)

You may find it useful to read the [atPlatform overview](https://docs.atsign.com/).

This package is available on [pub.dev](https://pub.dev) at https://pub.dev/packages/at_client_flutter

## Usage

See `at_client_flutter/example` for complete working implementations of all workflows.

Package provides Flutter Dialogs for the following workflows:
 1. Onboarding a new atSign via Registrar / CRAM
 2. Authentication via atKeys file
 3. Authentication via Keychain
 4. Authentication via APKAM enrollment

Additionally, 1.1.0 introduced extensions.dart as a new import to add flutter specific helpers.

---

### Workflow 1: Onboard a new atSign (Registrar / CRAM)

Use this flow to register a brand-new atSign for the first time.

```dart
// Step 1: Let the user enter/select their atSign and root domain
AuthRequest? authRequest = await AtSignSelectionDialog.show(context);
if (authRequest == null) return; // user cancelled

// Step 2: Fetch the CRAM key from the registrar
RegistrarService registrar = RegistrarService(
  registrarUrl: "my.atsign.com",
  apiKey: "yourApiKey",
);
String? cramKey = await RegistrarCramDialog.show(
  context,
  authRequest as AtOnboardingRequest,
  registrar: registrar,
);
if (cramKey == null) return; // user cancelled

// Step 3: Perform CRAM onboarding
AuthResponse? response = await CramDialog.show(
  context,
  request: authRequest,
  cramKey: cramKey,
);
if (response == null || !response.isSuccessful) return;

// Step 4: Initialize the atClient with the authenticated session
await _setupAtClient(context, authRequest, response);
```

---

### Workflow 2: Login with an existing atKeys file

Use this flow to authenticate using a `.atKeys` file from the device filesystem.

```dart
// Step 1: Let the user pick a .atKeys file
FileAtKeysIo? atKeysIo = await AtKeysFileDialog.show(context);
if (atKeysIo == null) return; // user cancelled

// Step 2: Extract the atSign from the filename (e.g. "@alice_key.atKeys")
var filepath = atKeysIo.filePath!('');
var atSign = path.basenameWithoutExtension(filepath).split('_').first;

// Step 3: Build an auth request
AtAuthRequest authRequest = AtAuthRequest(
  atSign,
  atKeysIo: atKeysIo,
  rootDomain: AtRootDomain.atsignDomain,
);

// Step 4: Authenticate and optionally back up keys to the keychain
AuthResponse? response = await PkamDialog.show(
  context,
  request: authRequest,
  backupKeys: [KeychainAtKeysIo()],
);
if (response == null || !response.isSuccessful) return;

// Step 5: Initialize the atClient
await _setupAtClient(context, authRequest, response);
```

---

### Workflow 3: Login with Keychain

Use this flow when the user has previously authenticated and their keys are stored in the device keychain.

```dart
// Step 1: Load stored atSigns
final KeychainStorage keychainStorage = KeychainStorage();
List<String> atSigns = await keychainStorage.getAllAtsigns();
if (atSigns.isEmpty) return; // nothing stored yet

// Step 2: Let the user choose which atSign to use
AuthRequest? request = await AtSignSelectionDialog.show(
  context,
  existingAtSigns: atSigns,
);
if (request == null) return; // user cancelled

// Step 3: Build an auth request backed by the keychain
AtAuthRequest authRequest = AtAuthRequest(
  request.atSign,
  atKeysIo: KeychainAtKeysIo(),
  rootDomain: request.rootDomain,
);

// Step 4: Authenticate
AuthResponse? response = await PkamDialog.show(
  context,
  request: authRequest,
  backupKeys: [KeychainAtKeysIo()],
);
if (response == null || !response.isSuccessful) return;

// Step 5: Initialize the atClient
await _setupAtClient(context, authRequest, response);
```

---

### Workflow 4: Login via APKAM enrollment

Use this flow to enroll a new device/app using an APKAM approval from an existing authenticated device.

```dart
// Step 1: Let the user enter their atSign
AuthRequest? request = await AtSignSelectionDialog.show(context);
if (request == null) return;

// Step 2: Start APKAM enrollment (waits for approval on another device)
AtEnrollmentResponse? enrollmentResponse = await ApkamActivationDialog.show(
  context,
  atSign: request.atSign,
  rootDomain: request.rootDomain,
  appName: 'myApp',
  deviceName: 'myDevice',
  namespaces: {'myApp': 'rw'},
);
if (enrollmentResponse == null || enrollmentResponse.atAuthKeys == null) return;

// Step 3: Build an auth request using the enrollment keys
AtAuthRequest authRequest = AtAuthRequest(
  request.atSign,
  atAuthKeys: enrollmentResponse.atAuthKeys!,
  rootDomain: request.rootDomain,
);

// Step 4: Authenticate and back up keys to the keychain
AuthResponse? response = await PkamDialog.show(
  context,
  request: authRequest,
  backupKeys: [KeychainAtKeysIo()],
);
if (response == null || !response.isSuccessful) return;

// Step 5: Initialize the atClient
await _setupAtClient(context, authRequest, response);
```

---

### Post-authentication: Initializing the atClient

After any successful authentication, call `AtClientManager.setCurrentAtSign` to create the atClient instance. Use the `atChops` and `atLookUp` from the `AuthResponse` — these are already authenticated.

```dart
Future<void> _setupAtClient(
  BuildContext context,
  AtAuthRequest authRequest,
  AuthResponse response,
) async {
  var dir = await getApplicationSupportDirectory();
  var acp = AtClientPreference()
    ..rootDomain = authRequest.rootDomain.rootDomain
    ..rootPort = authRequest.rootDomain.rootPort
    ..namespace = 'myApp'
    ..commitLogPath = dir.path
    ..hiveStoragePath = dir.path;

  await AtClientManager.getInstance().setCurrentAtSign(
    response.atSign,
    'myApp',
    acp,
    enrollmentId: response.enrollmentId,
    atChops: response.atChops,
    atLookUp: response.atLookUp,
  );
}
```

---

### Keychain Storage

`KeychainStorage` provides direct access to manage keys stored in the device keychain.

```dart
final KeychainStorage keychainStorage = KeychainStorage();

// Get a specific atSign's keys
AtKeys? alice = await keychainStorage.getAtsign("@alice");

// Get all atSigns stored for this app
List<String> atsigns = await keychainStorage.getAllAtsigns();

// Append atKeys to the keychain
await keychainStorage.appendAtKeysToKeychain(atKeys);

// Remove a specific atSign from the keychain
await keychainStorage.removeAtsignFromKeychain("@alice");

// Delete all atKeys data for this app
await keychainStorage.deleteAllAtKeysData();
```

Keychain Authentication is handled automatically when you provide a `KeychainAtKeysIo` instance in your `AtAuthRequest`. This class reads and writes AtKeys to the keychain during authentication.

> If your app supports the Windows platform, add `biometric_storage` to your app's dependencies:
> ```
> dependencies:
>   biometric_storage: ^4.1.3
> ```

#### Enrollments in the keychain

Enrollment data for ongoing/approved/denied APKAM enrollments is managed by `KeychainStorage`:

```dart
await keychainStorage.readEnrollmentData("@alice");

await keychainStorage.writeEnrollmentData("@alice", enrollmentData);

await keychainStorage.deleteEnrollmentData("@alice");

bool isValidated = await keychainStorage.validateEnrollment("@alice");
```

---

### Exporting atKeys to a file

```dart
final atsign = AtClientManager.getInstance().atClient.getCurrentAtSign()!;
AtKeys? atKeys = await keychainStorage.getAtsign(atsign);
if (atKeys == null) throw Exception('No keys found for $atsign');

FileAtKeysIo atKeysIo = FileAtKeysIo(filePath: (_) => '/path/to/${atsign}_key.atKeys');
atKeysIo.write(atsign, atKeys);
```

## Example

Full working examples are available in the example app:
- `at_client_flutter/example/lib/main.dart` — UI and navigation
- `at_client_flutter/example/lib/walkthrough.dart` — all authentication flows with error handling


## Migration from at_client_flutter & at_onboarding_flutter

There has been significant changes to functionality between these packages.
- The majority of functionality in at_onboarding_flutter lives here in at_client_flutter, including new widgets.
- The majority of at_client_mobile has been brought into at_auth and anything else related to mobile functions live here.
