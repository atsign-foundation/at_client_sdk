# Upgrading to at_client 4.0

at_client 4.0 is a major release, and so is the platform package an app
depends on. An app moves by bumping that one package and importing only it:
**at_client_cli 1.0** for a command-line program, daemon or server, and
**at_client_flutter 2.0** for a Flutter app. [The SDK shape](sdk-shape.md)
explains why. Most of the work is imports and naming the client's storage;
the rest is API that earlier releases had deprecated.

1. Change your dependencies and imports ([section 1](#1-change-your-dependencies)).
2. Run `dart analyze` or `flutter analyze`, and find each error in
   [section 2](#2-by-the-error-you-see).
3. Finish with your path's checklist:
   [a command-line program](#3-a-command-line-program-at_client_cli) or
   [a Flutter app](#4-a-flutter-app-at_client_flutter).

Every "after" sample compiles against this release as written. The samples
leave out the import of your platform package, which every file needs.

## 1. Change your dependencies

### A command-line program, daemon or server

```yaml
# before
dependencies:
  at_client: ^3.14.0
  at_onboarding_cli: ^1.16.0
  at_cli_commons: ^3.1.1
  at_utils: ^3.5.0

# after
dependencies:
  at_client_cli: ^1.0.0
```

Import `package:at_client_cli/at_client_cli.dart` in place of
`at_client.dart`, `at_onboarding_cli.dart`, `at_cli_commons.dart`,
`at_logger.dart` and `at_client_io.dart`. It re-exports at_client's native
API, its storage backends and mixins, the registrar and the io logging
handlers. Install the
tools with `dart pub global activate at_client_cli`.

at_onboarding_cli 2.0.0 and at_cli_commons 4.0.0 re-export at_client_cli, so
bumping either alone compiles in the meantime for a program that uses only
what at_client_cli keeps (`CLIBase`, `createAtClient` and the path helpers).
The analyzer does not flag an import of either deprecated library, so change
the import too. A program on `AtOnboardingService`, `AtOnboardingPreference`
or `OnboardingUtil` changes code either way:
[section 3](#3-a-command-line-program-at_client_cli) says to what.

### A Flutter app

```yaml
# before
dependencies:
  at_client_flutter: ^1.1.4
  at_client: ^3.14.0
  at_auth: ^3.3.0

# after
dependencies:
  at_client_flutter: ^2.0.0
```

Import `package:at_client_flutter/at_client_flutter.dart` in place of
`at_client.dart`, `at_auth.dart` and `at_client_io.dart`.

### "version solving failed" on at_utils

A direct `at_utils: ^3.x` constraint cannot resolve beside at_client 4. Drop
it, since your platform package re-exports `AtSignLogger`, or move it to
`^4.0.0`.

## 2. By the error you see

### `The method 'setCurrentAtSign' isn't defined`

`AtClientManager.setCurrentAtSign` is gone. A client is opened on the atSign,
from the keys, the storage and the transport it is given:

```dart
// before
await AtClientManager.getInstance()
    .setCurrentAtSign('@alice', 'my_app', preference);
final atClient = AtClientManager.getInstance().atClient;
```

```dart after
Future<AtClient> openAlice(AtClientPreference preference) async {
  final client = await Atsign('@alice').open(
      keys: FileAtKeysIo(filePath: (_) => 'keys/@alice_key.atKeys'),
      preference: preference,
      storage: HiveAtClientStorage(
          atSign: '@alice', storagePath: 'storage/hive', closedByClient: true),
      lookUps: secureSocketLookUps(),
      secondaryAddressFinder: CacheableSecondaryAddressFinder(
          preference.rootDomain, preference.rootPort));
  // Only for code that still reads AtClientManager.getInstance().atClient.
  AtClientManager.getInstance().use(client);
  return client;
}
```

`Atsign.open` comes back online, offline or refused, and
`client.connection.current` says which. A command-line program usually lets
`CLIBase` do all of this; a Flutter app lets the dialogs do it. Sections
[3](#3-a-command-line-program-at_client_cli) and
[4](#4-a-flutter-app-at_client_flutter) show both.

### `The named parameter 'storage' is required`

Every call that builds a client names its storage: `Atsign.open` and
`activate`, `PendingEnrollment.client`, `buildAtClient` and
`AtClientImpl.create`. To keep the store an app used before, name the folder
it set as `hiveStoragePath`:

```dart after
AtClientStorage sameStoreAsBefore(String atSign, String hiveStoragePath) =>
    HiveAtClientStorage(
        atSign: atSign, storagePath: hiveStoragePath, closedByClient: true);
```

`closedByClient: true` lets the client close the store when it stops; without
it the store stays open for the app to close. `hiveStoragePath` itself is
deprecated, and at_client no longer reads it. at_client_flutter's dialogs and
flows still read it when an app passes no storage, until 5.0.

### `The named parameter 'lookUps' is required`, and `'secondaryAddressFinder'`

Every client, enrollment and lookup is handed its transport and the atDirectory
it asks: `secureSocketLookUps()` and
`CacheableSecondaryAddressFinder(preference.rootDomain, preference.rootPort)`,
as above. A command-line program takes its transport from at_client_cli's
`lookUpsFor(preference.rootDomain)`, as `CLIBase` does: `proxyLookUps()` for a
root domain of the form `proxy:host:port`, and `secureSocketLookUps()`
otherwise.

### `Undefined name 'FileAtKeysIo'`, `'CacheableSecondaryAddressFinder'`, `'HiveAtClientStorage'`

These native pieces left the libraries a browser build imports:
`FileAtKeysIo` left `at_auth.dart` and `CacheableSecondaryAddressFinder` left
`at_lookup.dart`, and the Hive store is at_client's `hive.dart`. Your platform
package re-exports all three, so its import is the fix. A program that
imports at_client directly takes them from
`package:at_client/at_client_io.dart` and `package:at_client/hive.dart`.

### `Undefined name 'StdErrLoggingHandler'`, `'FileLoggingHandler'`, `'CLILoggingHandler'`

The io logging handlers moved to `package:at_utils/at_utils_io.dart`, with
`PseudoServerSocket` and `ApplicationConfiguration`. at_client_cli re-exports
the three handlers. `AtSignLogger.stdErrLoggingHandler` still works, deprecated.

```dart after-cli
void logToStderr() {
  AtSignLogger.defaultLoggingHandler = StdErrLoggingHandler();
}
```

### `The getter 'atChops' isn't defined`

`AtClient.atChops`, `RemoteSecondary.atChops` and the `atChops:` parameters of
`AtClientImpl.create` and `AtServiceFactory.atClient` are gone. A client is
given its keys as an `AtKeysIo`, such as `FileAtKeysIo`, and signs and
encrypts with them itself. at_client 4.0 stays on at_chops 3.7, so a program
calling at_chops directly changes nothing for this release.

### `The setter 'commitLogPath' isn't defined`, and other `AtClientPreference` fields

These fields are gone. Delete each assignment:

| Field | Instead |
|---|---|
| `commitLogPath`, `keyStoreSecret`, `downloadPath`, `atProtocolEmitted` | nothing; they were read by nothing |
| `outboundConnectionTimeout` | nothing |
| `enforceNamespace` | nothing; every key except a `local:` one names a namespace |
| `decryptPackets`, `pathToCerts`, `tlsKeysSavePath` | a `SecureSocketConfig` given to `secureSocketLookUps`, below |

```dart after
AtLookUpFactory debuggingTls() => secureSocketLookUps(
    config: SecureSocketConfig()
      ..decryptPackets = true
      ..pathToCerts = 'certs'
      ..tlsKeysSavePath = 'tls_keys.log');
```

`hiveStoragePath`, `isLocalStoreRequired` and `hashingAlgoType` remain,
deprecated and read by nothing in at_client; they go in 5.0.

### `No named parameter with the name 'isDedicated'`, or `'sync'`

Delete the argument. `isDedicated:` left `put`, `get`, `delete`, `notify`,
`getMeta`, `notifyList` and `notifyAll`; `sync:` left `executeVerb` and
`executeAndParse`.

### `Undefined class 'AtCollectionModel'`

The legacy collection models (`AtCollectionModel`, `AtJsonCollectionModel`,
their factories and operations, `KeyMaker` and `ObjectLifeCycleOptions`) are
gone. `AtClient.collection<T>` replaces them; the
[at_client README](../packages/at_client/README.md#collections) and the
`collections_*.dart` examples show the verbs.

```dart after
Future<AtCollection<Map<String, dynamic>>> notes(AtClient client) =>
    client.collection<Map<String, dynamic>>(
        'notes.my_app', const Duration(days: 30));
```

### Other methods that are gone

| Before | After |
|---|---|
| `atClient.stream(...)`, `sendStreamAck(...)` | `put` the value, or `notify` it |
| `uploadFile`, `downloadFile`, `reuploadFiles`, `shareFiles` | none; file transfer belongs in the app |
| `ConnectivityListener` | a connectivity package of the app's choosing |
| `RemoteSecondary.isAvailable()` | `checkAtSignServer(lookUp, atSign)` |
| `RemoteSecondary.authenticateCram(secret)` | `Atsign.activate`, which takes the CRAM secret |
| `AtClientUtil.findSecondary(...)` | `RemoteSecondary.findSecondaryUrl()` |
| `ApkamSigning.publicSigningKey`, `privateSigningKey` | `signingKeys` |
| `atClient.persistenceBundle` | the `AtClientStorage` the client was given |
| `AtUtils.formatAtSign` | `AtUtils.fixAtSign` |
| `AtClient.telemetry` and the `AtClientTelemetry*` types | none |
| `AtClientManager.setSecondaryAddressFinder(...)`, `AtClientManager.secondaryAddressFinder` | the `secondaryAddressFinder` the client is built with |

### Programs that call at_lookup directly

`AtLookUp.update`, `lookup`, `plookup`, `llookup`, `delete` and `scan` give way
to `executeVerb` with a verb builder. A lookup authenticates through its
`authenticator` rather than `cramAuthenticate(secret)` or
`authenticate(privateKey)`, and a lookup is built by an `AtLookUpFactory`, not
the deprecated `AtLookupImpl(...)` constructor:

```dart after
import 'package:at_commons/at_builders.dart';

Future<String?> publicValue(String atSign, String key) async {
  final lookUp = secureSocketLookUps()(
      atSign: atSign,
      rootDomain: AtRootDomain('root.atsign.org', 64),
      authenticator: null);
  try {
    return await lookUp.executeVerb(PLookupVerbBuilder()
      ..atKey = (AtKey()
        ..key = key
        ..sharedBy = atSign));
  } finally {
    await lookUp.close();
  }
}
```

The verb builders come from `package:at_commons/at_builders.dart`, so such a
program lists at_commons among its dependencies. `MonitorClient` and
`AtConnection.getSocket()` are gone.
`CacheableSecondaryAddressFinder` and `SecureSocketUtil` moved to
`package:at_lookup/at_lookup_io.dart`, and a failed write throws
`AtIOException` rather than `SocketException`.

### Programs that call at_auth directly

`AtAuth` and its request and response types (`AtAuthRequest`,
`AtOnboardingRequest` and the rest) are no longer exported: at_client's
`Atsign.open`, `activate` and `authenticatesAs` do what they did. Deciding
enrollments moved onto the client:

| Before | After |
|---|---|
| `AtEnrollment.list`, `deny`, `revoke` | `client.enrollments.list`, `deny`, `revoke` |
| `AtEnrollment.generateOtp`, `setSpp`, `Otp` | `client.enrollments.otp`, `spp`, `Passcode` |
| `AtKeys.toAtChops()` | `authenticationKeyPairFor`, `encryptionKeyPair`, `selfEncryptionKey` |
| `KeyIOMixin` | `FileAtKeysIo.read` and `write` |
| `RegistrarService.getFreeAtSign`, `registerPerson`, `validatePerson` | `registerAtSign` |
| `FileAtKeysIo`, `getHomeDirectory`, `getDefaultAtKeysFilePath` from `at_auth.dart` | your platform package, or `package:at_auth/at_auth_io.dart` |

```dart after
Future<void> approveWhatIsPending(AtClient client) async {
  for (final request in await client.enrollments.pending()) {
    await client.enrollments.approve(request.enrollmentId!);
  }
  final passcode = await client.enrollments.otp();
  print('quote ${passcode.value} to enrol a new device');
}
```

### A keyfile that is not valid JSON throws `AtKeysFormatException`

`FileAtKeysIo` reads a keyfile that is not valid JSON as
`AtKeysFormatException`, a `FormatException`, so a `catch` for one still
catches it. Its `reason` is the JSON parser's own wording and its `position`
the 1-based character where the parser stopped; its `source` is always null.
A keyfile holding JSON that is not an object throws it too, with a null
`position`, where it used to fail as a `TypeError`. A passphrase-protected
keyfile whose decrypted content does not parse still fails as
`AtDecryptionException`. An app that built its message from the old
exception's `source` or `offset` reads `reason` and `position` instead:

```dart after
String unreadableKeyfile(AtKeysFormatException e) => e.position == null
    ? 'The atKeys file is not a JSON object'
    : 'The atKeys file is not valid JSON: ${e.reason} '
        'at character ${e.position}';
```

### Mocks and implementations that no longer compile

`AtClient` gained `atKeysIo`, `connection` and `ensureReachable`, and
`AtLookUp` gained `authenticator` and `stop`. Regenerate generated mocks, and
add the members to any class implementing either.

## 3. A command-line program: at_client_cli

at_client_cli carries at_onboarding_cli's and at_cli_commons' code. Its
[README](../packages/at_client_cli/README.md#moving-from-at_onboarding_cli-and-at_cli_commons)
has the full table; these are the changes most programs make.

**`AtOnboardingService` is gone.** A program with the standard flags opens
through `CLIBase`; one that names its own keyfile and store uses `CliKeys`
with at_client's verbs:

```dart
// before
final pref = AtOnboardingPreference()
  ..namespace = 'my_app'
  ..atKeysFilePath = 'keys/@alice_key.atKeys'
  ..storagePath = 'storage/hive';
final service = AtOnboardingServiceImpl('@alice', pref);
await service.authenticate();
final atClient = service.atClient!;
```

```dart after-cli
Future<AtClient> openFromFlags(List<String> args) async =>
    (await CLIBase.fromCommandLineArgs(args,
            parser: CLIBase.createArgsParser(namespace: 'my_app')))
        .atClient;

Future<AtClient> openFromKeyfile() {
  final preference = AtClientPreference()..namespace = 'my_app';
  return Atsign('@alice').open(
      keys: CliKeys.fileFor('@alice', path: 'keys/@alice_key.atKeys'),
      preference: preference,
      storage: CliKeys.storageFor('@alice',
          program: 'my_app', path: 'storage/hive'),
      lookUps: lookUpsFor(preference.rootDomain),
      secondaryAddressFinder: CacheableSecondaryAddressFinder(
          preference.rootDomain, preference.rootPort));
}
```

With no `path`, `CliKeys.fileFor` is `~/.atsign/keys/<atSign>_key.atKeys` and
`CliKeys.storageFor` is the store `CLIBase` opens for that namespace.

**`CLIBase` tells a refusal from an outage.** It throws
`AtCredentialRefusedException` when the atServer refuses the keys, saying when
an enrollment awaits approval or was denied;
`AtEnrollmentPendingException` when the keyfile still holds only its
enrollment request; `SecondaryNotFoundException` when the atDirectory has no
atServer for the atSign; and `SecondaryServerConnectivityException` only when
the atServer is not reached in time. A retry loop catches the last alone.

```dart after-cli
Future<AtClient> openWhenReachable(List<String> args) async {
  while (true) {
    try {
      return (await CLIBase.fromCommandLineArgs(args,
              parser: CLIBase.createArgsParser(namespace: 'my_app')))
          .atClient;
    } on SecondaryServerConnectivityException {
      await Future<void>.delayed(const Duration(seconds: 10));
    }
  }
}
```

**`createAtClient` is unchanged.** It takes at_onboarding_cli 2.0.0-rc8's
parameters and opens the client at_activate's commands use: from the keyfile,
syncing nothing, on a store of its own.

```dart after-cli
Future<AtClient> commandClient() => createAtClient(
    atSign: '@alice',
    atKeysFilePath: 'keys/@alice_key.atKeys',
    waitForPqStartup: false,
    maxConnectAttempts: 3);
```

**Embedding at_activate** no longer needs a `src/` import:

```dart after-cli
import 'dart:io';

Future<void> main(List<String> args) async {
  exitCode = await AtActivate.main(args);
}
```

**Checklist**

- [ ] `at_client_cli: ^1.0.0` replaces at_client, at_onboarding_cli,
      at_cli_commons and at_utils in `pubspec.yaml`.
- [ ] Every SDK import is `package:at_client_cli/at_client_cli.dart`.
- [ ] `AtOnboardingService` calls are `CLIBase` or `Atsign.open` with
      `CliKeys`; `createAtClient` calls stay as they are.
- [ ] `CLIBase`'s `preference:`, if passed, is an `AtClientPreference`.
- [ ] A retry loop around `CLIBase` catches
      `SecondaryServerConnectivityException`, not every exception.
- [ ] Scripts name `at_activate`'s command (`at_activate onboard ...`).
- [ ] `dart analyze` is clean.

## 4. A Flutter app: at_client_flutter

`AuthService` and `FlutterEnrollmentService` are gone. The dialogs take the
atSign, the keys store and the preference, and hand back the `AtClient`.
[at_client_flutter's README](../packages/at_client_flutter/README.md#migrating-from-1x)
has the full table and before-and-after for each flow.

```dart
// before
final response = await PkamDialog.show(context,
    request: AtAuthRequest('@alice'),
    onAuthenticationComplete: (request) {});
```

```dart after-flutter
import 'package:flutter/widgets.dart';

Future<AtClient?> signIn(BuildContext context, AtClientPreference preference) =>
    PkamDialog.show(context,
        atSign: '@alice', keys: KeychainAtKeysIo(), preference: preference);
```

An app with its own UI calls the verbs through `AtsignFlows`, which supplies
the store, the transport and the atDirectory as the dialogs do, and a pending
enrollment's client takes its store from `storageOrDefault`:

```dart after-flutter
Future<AtClient> activateWith(String cramSecret, AtClientPreference preference) =>
    const AtsignFlows().activate('@alice',
        cramSecret: cramSecret, keys: KeychainAtKeysIo(), preference: preference);

Future<AtClient> openWith(AtClientPreference preference) => const AtsignFlows()
    .open('@alice', keys: KeychainAtKeysIo(), preference: preference);

Future<AtClient> enrollWith(String otp, AtClientPreference preference) async {
  final pending = await const AtsignFlows().enroll('@alice',
      otp: otp,
      app: 'my_app',
      device: 'my_phone',
      namespaces: {'my_app': 'rw'},
      keys: KeychainAtKeysIo(),
      preference: preference);
  return pending.client(preference,
      storage: await storageOrDefault('@alice', preference));
}
```

When an app passes no `storage:`, the dialogs and flows use
`hiveStoragePath` while the app still sets it, and otherwise the app support
directory, where at_client_mobile's examples kept the store. Pass `storage:`
to choose another.

`KeychainStorage` no longer holds enrollment data, since the keys store holds
a pending enrollment, and `saveSpp` takes a `Passcode`.
`KeychainAtKeysIo.read` of an atSign it has no keys for throws
`AtKeysSourceAbsentException`.

**Checklist**

- [ ] `at_client_flutter: ^2.0.0` replaces at_client and at_auth in
      `pubspec.yaml`.
- [ ] Every SDK import is `package:at_client_flutter/at_client_flutter.dart`.
- [ ] `AuthService` and `FlutterEnrollmentService` calls are the dialogs, or
      `AtsignFlows`' `open`, `activate` and `enroll`.
- [ ] Each dialog's result is read as the `AtClient` it returns.
- [ ] Generated mocks of `AtClient` are regenerated.
- [ ] `flutter analyze` is clean.

## 5. A keyfile written by a release candidate

This concerns only an atSign that ran an at_client release candidate under
`PqPosture.pqReady` or `PqPosture.pqActive`.

A keyfile such a release candidate wrote can hold the enrollment's first key
package without its enrollment id. If `keyEstablishmentAlgorithms` later names
a second algorithm, the client files a key for it beside the first, and the
key package it publishes names both keys, but the client then holds only the
new one: the first key stays advertised and is not held. Until the client
next starts, what other enrollments seal to that first key is not opened; that
start files a fresh key for the first algorithm and stops advertising the old
one. No posture's default names a second algorithm.
