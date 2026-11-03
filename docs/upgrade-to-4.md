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
4. Move to post-quantum in two releases
   ([section 5](#5-post-quantum-in-two-steps)).

Every "after" sample compiles against this release as written. The samples
leave out the import of your platform package, which every file needs. They
spell atSigns as string literals; an `Atsign` passes where they do, since it
is a `String`.

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
handlers, and with at_client all of `at_commons.dart` and the parts of
at_lookup and at_utils a client uses (`AtLookUpFactory`,
`SecondaryAddressFinder`, `AtSignLogger` and their kind). A file that goes on
importing one of those packages beside it gets an `unnecessary_import` info
for each import whose every name it now has from at_client_cli; delete those
imports. Regenerate a committed `pubspec.lock`, or a CI step running
`pub get --enforce-lockfile` fails. Install the
tools with `dart pub global activate at_client_cli`. `at_register`, and
`at_activate onboard` without `-c`, ask the registrar with the API key in
`AT_REGISTRAR_API_KEY` when it is set, and otherwise with a key built into
at_client_cli, as at_onboarding_cli did, so they work without it. An app may
create its own key via the registrar at my.atsign.com.

From at_utils it re-exports `AtSignLogger` and the three io handlers, but not
the `LoggingHandler` interface or `AtUtils`. A program that implements a
`LoggingHandler` or calls `AtUtils` keeps `at_utils: ^4.0.0` beside
at_client_cli, and the file that does keeps its own import:
`package:at_utils/at_logger.dart` for `LoggingHandler`,
`package:at_utils/at_utils.dart` for `AtUtils`. With the `depend_on_referenced_packages` lint off, such a call
still compiles after at_utils is dropped, through at_client_cli's own
dependency, so list it anyway.

at_onboarding_cli 2.0.0 and at_cli_commons 4.0.0 re-export at_client_cli, so
bumping either alone compiles in the meantime for a program that uses only
what at_client_cli keeps (`CLIBase`, `createAtClient` and the path helpers).
The analyzer reports an import of either deprecated library as a
`deprecated_member_use` info, which a build and `dart analyze --fatal-warnings`
still pass, so change the import too. A program on `AtOnboardingService`,
`AtOnboardingPreference` or `OnboardingUtil` changes code either way:
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

### A library that both a command-line program and a Flutter app use

Such a library depends on at_client, the platform-neutral core, as the SDK's
feature packages do, and never on a platform package: each app brings its own.
It takes what differs by platform (the keys, the storage, the transport and the
atDirectory) as parameters from the app that calls it, and a native-only
library takes the native pieces from `package:at_client/at_client_io.dart`.

Where the library also holds files only a command-line program reaches, such
as commands that call `createAtClient`, `CliKeys` or `requestEnrollmentOtp`,
it can list at_client_cli as well and import it in those files alone: every
platform at_client_flutter supports has `dart:io`, so a Flutter app built on
the library still resolves. Its other files keep importing at_client. A file
on at_client alone asks for a passcode with
`(await client.enrollments.otp(expiry: ...)).value`, which is what
`requestEnrollmentOtp` returns.

### "version solving failed" on at_utils

A direct `at_utils: ^3.x` constraint cannot resolve beside at_client 4. Drop
it when `AtSignLogger` is all a program uses from it, since your platform
package re-exports that, or move it to `^4.0.0`.

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
AtClient? current;

Future<AtClient> switchTo(String atSign, AtClientPreference preference) async {
  // setCurrentAtSign reused the client of the atSign already current...
  final previous = current;
  if (previous != null && previous.atSign == Atsign(atSign)) {
    return previous;
  }
  final client = await Atsign(atSign).open(
      keys: FileAtKeysIo(filePath: (_) => 'keys/${atSign}_key.atKeys'),
      preference: preference,
      storage: HiveAtClientStorage(
          atSign: atSign, storagePath: 'storage/hive', closedByClient: true),
      lookUps: secureSocketLookUps(),
      secondaryAddressFinder: CacheableSecondaryAddressFinder(
          preference.rootDomain, preference.rootPort));
  current = client;
  // Only for code that still reads AtClientManager.getInstance().atClient.
  AtClientManager.getInstance().use(client);
  // ...and stopped the one it replaced. use() does not, and an atSign whose
  // client is still live cannot be opened again.
  await previous?.stop();
  return client;
}

Future<void> openAlice(AtClientPreference preference) async {
  try {
    final client = await switchTo('@alice', preference);
    print('@alice is ${client.connection.current}');
  } on AtEnrollmentPendingException catch (e) {
    print('awaiting approval of ${e.pendingEnrollmentIds}');
  } on AtOpenRefusedException catch (e) {
    print('refused: ${e.state}');
  }
}
```

A client is its opener's to stop: stop the one you are finished with, as
`switchTo` does, and every one still open before the program exits. Opening an
atSign again as an enrollment whose client is still live throws a
`StateError`; another enrollment of the atSign opens beside it.
`AtClientImpl.liveClientsFor(atSign)` lists every live client of an atSign.

On the first open of an atSign on a device, `Atsign.open` throws
`AtEnrollmentPendingException` when the keys hold only an enrollment request
that has not been approved, `AtNoCredentialException` at once when they hold
no credential and no request, as a denial, a cancel or an expiry leaves them,
and
`AtOpenRefusedException` when the atServer refuses the keys or the atDirectory
knows no atServer for the atSign; its `state` says which. Otherwise
`Atsign.open` returns once its one attempt to reach the atServer has ended,
within `connectBudget` (5 seconds by default), and
`client.connection.current` says whether it is online, offline or refused. A command-line program usually lets
`CLIBase` do all of this; a Flutter app lets the dialogs do it. Sections
[3](#3-a-command-line-program-at_client_cli) and
[4](#4-a-flutter-app-at_client_flutter) show both. A Flutter app with its own
UI calls these verbs through at_client_flutter's `AtsignFlows`, which supplies
the store, the transport and the atDirectory, so it wires none of them by
hand as the sample above does.

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
root domain beginning `proxy:`, and `secureSocketLookUps()` otherwise.

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
the three handlers. `AtSignLogger.stdErrLoggingHandler` is gone: construct
`StdErrLoggingHandler()` from `at_utils_io.dart`.

```dart after-cli
void logToStderr() {
  AtSignLogger.defaultLoggingHandler = StdErrLoggingHandler();
}
```

### `The method 'write' isn't defined for the type 'StringBuffer'`

at_commons defines a `StringBuffer` of its own, which your platform package
re-exports, and it shadows dart:core's. A file that imported
`at_client.dart hide StringBuffer` keeps the `hide` on every import that now
brings it in: at_client_cli's, and at_cli_commons' or at_onboarding_cli's,
which re-export it:

```dart
import 'package:at_client_cli/at_client_cli.dart' hide StringBuffer;
```

### `The getter 'atChops' isn't defined`

`AtClient.atChops`, `RemoteSecondary.atChops` and the `atChops:` parameter of
`AtClientImpl.create` are gone. A client is given its keys as an `AtKeysIo`,
such as `FileAtKeysIo`, and signs and encrypts with them itself. at_client 4.0
stays on at_chops 3.7, so a program calling at_chops directly changes nothing
for this release.

### `The setter 'commitLogPath' isn't defined`, and other `AtClientPreference` fields

These fields are gone. Delete each assignment:

| Field | Instead |
|---|---|
| `commitLogPath`, `keyStoreSecret`, `downloadPath`, `atProtocolEmitted` | nothing; they were read by nothing |
| `outboundConnectionTimeout` | nothing |
| `syncStrategy`, and the `SyncStrategy` enum | nothing; they were read by nothing |
| `syncIntervalMins` | nothing; it was read by nothing, and sync's fallback timer runs every 30 seconds |
| `isLocalStoreRequired`, `useAtChops`, `hashingAlgoType` | nothing; they were read by nothing |
| `privateKey`, `signingAlgoType` | nothing: a client signs with the keys in its `AtKeysIo`, which name the algorithm; a `RemoteSecondary` built without one takes `privateKey:` |
| `enforceNamespace` | nothing; every key except a `local:` one names a namespace |
| `decryptPackets`, `pathToCerts`, `tlsKeysSavePath` | a `SecureSocketConfig` given to `secureSocketLookUps`, below |

```dart after
AtLookUpFactory debuggingTls() => secureSocketLookUps(
    config: SecureSocketConfig()
      ..decryptPackets = true
      ..pathToCerts = 'certs'
      ..tlsKeysSavePath = 'tls_keys.log');
```

This is for debugging, never production: `tlsKeysSavePath` writes each
connection's TLS keys to that file, and anyone holding the file can read the
traffic it captured.

`hiveStoragePath` remains, deprecated and read by nothing in at_client; it
goes in 5.0.

### `No named parameter with the name 'isDedicated'`, or `'sync'`

Delete the argument. `isDedicated:` left `put`, `get`, `delete`,
`getMeta` and `notifyList`; `sync:` left `executeVerb` and
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

### `Undefined class 'LocalSecondary'`, or `'RemoteSecondary'`

`package:at_client/at_client.dart` no longer exports `LocalSecondary` or
`RemoteSecondary`: they are the client's own plumbing, and an app should not
need them. `AtClient.getLocalSecondary()` and `getRemoteSecondary()` remain,
and their dartdoc says the same. If you have to use one, because nothing else
does what you need, please file a feature request at
https://github.com/atsign-foundation/at_client_sdk/issues so that there is an
alternative; until then the type comes from
`package:at_client/src/client/local_secondary.dart` or `remote_secondary.dart`.

### Other methods that are gone

| Before | After |
|---|---|
| `atClient.stream(...)`, `sendStreamAck(...)` | `put` the value, or `notify` it |
| `atClient.notify(...)`, `notifyChange(...)`, `notifyAll(...)` | `notificationService.notify(...)`, once per recipient |
| `atClient.startMonitor(...)` | `notificationService.subscribe(...)` |
| `startCompactionJob`, `stopCompactionJob` | none; they did nothing |
| `NotificationParams.forText(...)` | `NotificationParams.forUpdate(...)`; atServers refuse text notifications |
| `notificationService.send(namespace: ...)` | `send(idAndNamespace: ...)`, the same value |
| `AtClientManager.getInstance().syncService`, `.notificationService` | `client.syncService`, `client.notificationService` |
| `syncService.sync(onDone: ...)`, `setOnDone(...)` | a `SyncProgressListener` added with `addProgressListener` |
| `syncService.sync(onError: ...)` | a `SyncProgressListener`, which hears each sync that fails |
| `AtServiceFactory.atClient(...)` | `Atsign(a).open(...)` or `buildAtClient(...)` |
| `PutRequestOptions.storeSharedKeyEncryptedMetadata` | nothing; it was always true |
| `RemoteSecondary(..., signingAlgoType: ...)` | nothing; the keys name the algorithm |
| `uploadFile`, `downloadFile`, `reuploadFiles`, `shareFiles` | none; file transfer belongs in the app |
| `ConnectivityListener` | a connectivity package of the app's choosing |
| `RemoteSecondary.isAvailable()` | `checkAtSignServer(lookUp, atSign)` |
| `Query.fetch()` | `get()` |
| `LocalSecondary.getPrivateKey()`, `getPublicKey()` | `getPkamPrivateKey()`, `getPkamPublicKey()` |
| `EncryptionUtil.decryptKey(...)` | at_chops' `RsaEncryptionAlgo`, with the private key as its `atPrivateKey` |
| `RemoteSecondary.authenticateCram(secret)` | `Atsign.activate`, which takes the CRAM secret |
| `AtClientUtil.findSecondary(...)` | `findSecondary(atSign)` on the `SecondaryAddressFinder` the client was opened with |
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
the `AtLookupImpl(...)` constructor, which 4.0 makes internal to at_lookup:

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
`AtConnection.getSocket()` are gone. `AtLookupTransport` takes a
`transportFactory`, an `AtTransportFactory`, in place of its `socketFactory`
and `secureSocketConfig`; a `secureSocketTransport(...)` caller changes
nothing. An `AtLookUpFactory`, and the `secureSocketLookUps` and
`webSocketLookUps` that build one, take no `clientConfig`: give it to at_auth's
`authenticatorFor`, which sends it in `from:`. `AtLookUp.withSecureSocket`
and `withTransport` take no `clientConfig:` either.
`CacheableSecondaryAddressFinder`, `SecureSocketUtil` and
`AtLookupSecureSocketFactory` moved to
`package:at_lookup/at_lookup_io.dart`, and a failed write throws
`AtIOException` rather than `SocketException`.

### A test double for the atServer

A double that extended `AtLookupSecureSocketFactory`, or wrapped a fake
`SecureSocket`, no longer reaches a client's connections:
`AtLookupSecureSocketFactory` now opens only the atDirectory's socket, and
at_lookup opens each connection to the atServer through the
`AtTransportFactory` its `AtLookupTransport` is given. A double implements
the two interfaces `package:at_lookup/at_lookup.dart` exports, so its test
lists at_lookup among its `dev_dependencies`:

- `AtTransportFactory.connect(host, port, {timeout})` returns an
  `AtTransport`, and throws `SecondaryConnectException` when nothing answers.
  Any other exception, a `SocketException` among them, escapes at_lookup
  uncaught and loses the atSign the connection was for.
- `AtTransport` is `inbound`, `add`, `flush`, `destroy`, `isOpen` and
  `description`. A transport over a socket returns the socket itself as
  `inbound`, never a `StreamController`, since pausing it is how at_lookup
  holds the atServer back. A double that only answers what it is sent holds
  at most one reply per command while paused, so it may feed `inbound` from
  a controller, as this one does.
- Each reply is one line, such as `data:ok`.

```dart after
import 'dart:async';
import 'dart:convert';

import 'package:at_lookup/at_lookup.dart';

/// A stand-in atServer: [reply] answers each command a client sends.
class FakeAtServer implements AtTransportFactory {
  FakeAtServer(this.reply, {this.reachable = true});

  final String Function(String command) reply;
  final bool reachable;

  @override
  Future<AtTransport> connect(String host, String port,
      {Duration? timeout}) async {
    if (!reachable) {
      throw SecondaryConnectException('nothing answers at $host:$port');
    }
    return _FakeConnection(this);
  }

  /// What a client under test is given as `lookUps:`.
  AtLookUpFactory get lookUps => ({
        required String atSign,
        required AtRootDomain rootDomain,
        required AtAuthenticator? authenticator,
        SecondaryAddressFinder? secondaryAddressFinder,
      }) =>
          AtLookUp.withTransport(
              atSign: atSign,
              rootDomain: rootDomain,
              authenticator: authenticator,
              transport: AtLookupTransport(transportFactory: this),
              secondaryAddressFinder: secondaryAddressFinder ??
                  FixedSecondaryAddressFinder('fake.atserver', 6464));
}

class _FakeConnection implements AtTransport {
  _FakeConnection(this._server);

  final FakeAtServer _server;
  final _inbound = StreamController<List<int>>();

  @override
  Stream<List<int>> get inbound => _inbound.stream;

  @override
  void add(List<int> bytes) {
    if (_inbound.isClosed) throw AtIOException('the connection is closed');
    for (final command in const LineSplitter().convert(utf8.decode(bytes))) {
      final answer = _server.reply(command);
      scheduleMicrotask(() {
        if (!_inbound.isClosed) _inbound.add(utf8.encode('$answer\n'));
      });
    }
  }

  @override
  Future<void> flush() async {}

  @override
  void destroy() {
    if (!_inbound.isClosed) _inbound.close();
  }

  @override
  bool get isOpen => !_inbound.isClosed;

  @override
  String get description => 'fake atServer';
}
```

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
| `AtEnrollmentRequest(atSign: ..., rootDomain: ..., apkamPublicKey: ..., encryptedAPKAMSymmetricKey: ...)`, and the same on `.pq` | `session: AtAuthSession(...)`, which names the atSign, the root domain and where the new keys go; or at_client's `Atsign(atSign).enroll(...)` |

`client.enrollments` is the `AtClientEnrollments` extension, so an import
that names what it shows names `AtClientEnrollments` too. at_client's own
`EnrollmentService`, at `client.enrollmentService`, still lists requests by an
`EnrollmentListRequestParam` and approves, denies or revokes from an
`EnrollmentRequestDecision`.

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

### `Undefined class 'AtOnboardingPreference'`, or `'AtOnboardingService'`

at_client_cli opens a client with `CLIBase`, or with `Atsign.open` and
`CliKeys`: [section 3](#3-a-command-line-program-at_client_cli) shows both.

### `Target of URI doesn't exist: 'package:at_onboarding_cli/src/cli/auth_cli.dart'`

at_activate is embedded through `AtActivate.main`, with no `src/` import, as
[section 3](#3-a-command-line-program-at_client_cli) shows.

### `The argument type 'AtClientStorage?' can't be assigned to the parameter type 'AtClientStorage'`

`storage` is required and cannot be null. A program whose own store may be
null passes a default in its place, such as
`CliKeys.storageFor(atSign, program: ...)` or at_client_flutter's
`storageOrDefault`.

### Mocks and implementations that no longer compile

`AtClient` gained `atKeysIo`, `connection` and `ensureReachable`, and
`AtLookUp` gained `authenticator` and `stop`. Regenerate generated mocks, and
add the members to any class implementing either. A `SyncService` of your own
drops `setOnDone` and `sync`'s `onDone` and `onError`, and an `AtServiceFactory` of your own
drops `atClient` and takes only the client in `notificationService` and
`syncService`.

### Changes the analyzer won't show

These compile and then fail when the code runs, usually first in a test:

- A keyfile that is not valid JSON throws `AtKeysFormatException`, as
  [above](#a-keyfile-that-is-not-valid-json-throws-atkeysformatexception).
- `storage` cannot be null, so a mocktail stub that matches it with `any()`
  needs `registerFallbackValue` for `AtClientStorage` first, for instance an
  `InMemoryAtClientStorage`.
- A client does not publish an `_apsk` that names no active signing key: it
  throws `AtKeyNotFoundException`, `an _apsk advertisement must name at least
  one active signing key, and this one names none, so it is not published`.
  Real keyfiles always hold an APKAM keypair; a test whose stand-in keys hold
  none gives them one.
- At a post-quantum posture, a 4.0 client sends `enroll:link`. A test double
  standing in for the atServer answers it, or replies
  `error:AT0003-Invalid syntax` as an atServer without the verb does; the
  client then goes on without it, and the test exercises no link.
- at_lookup reads a connection through an `AtTransport` and calls `cast()` on
  its `inbound` stream. A test double for the atServer gives at_lookup its own
  `AtTransport`, rather than wrapping a partial fake socket in
  `SecureSocketTransport`, as
  [above](#a-test-double-for-the-atserver).
- A program built on `CLIBase.createArgsParser` or `fromCommandLineArgs` that
  never passed `addLegacyRootDomainArg:` had `-d`/`--legacy-root-domain` by
  default, and loses it with no compile error: its users who type it get
  `Could not find an option or flag "-d"`, and pass the root domain as `-r`
  instead, as [section 3](#3-a-command-line-program-at_client_cli) says.

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
`CliKeys.storageFor` is the store `CLIBase` opens for that namespace:
`~/.atsign/storage/<atSign>/<program>/single`, not at_onboarding_cli's
`~/.atsign/at_onboarding_cli/storage/`. `program` names the program's own
folder there, and `CLIBase` passes its namespace; a `path` is the folder
itself, used as given. A program that relied on the old
default passes that folder as `path` to keep its store. The default store
is one per atSign and program, whichever enrollment opens it, so a program
that holds more than one enrollment of an atSign over time gives each its
own, for example with `id: pending.enrollmentId`.

**`Atsign.open` stops no client already live for the atSign.**
`AtOnboardingServiceImpl.authenticate()` stopped any such client before it
opened; `Atsign.open` throws a `StateError` instead, so a program that opens
an atSign again stops the client it opened before. `authenticate()` also
returned whether it authenticated: read `client.connection.current` instead,
and stop a client the program has no use for:

```dart after-cli
Future<AtClient?> openIfOnline(Future<AtClient> Function() open) async {
  final client = await open();
  if (client.connection.current.isOnline) return client;
  await client.stop();
  return null;
}
```

**From a 4.0 release candidate.** at_onboarding_cli 2.0.0's release
candidates gave `AtOnboardingPreference` a `storageFor` and a `lookUps`.
`CliKeys.storageFor` and `lookUpsFor(preference.rootDomain)` replace them,
and an `AtClientPreference` replaces the preference itself. A program on a
release candidate also meets three changes section 2 covers by error:
`open`, `activate`, `enroll` and `resumeEnrollment` require
`secondaryAddressFinder`, a service factory's `notificationService` and
`syncService` take only the client, and `AtLookUp.withSecureSocket` takes no
`clientConfig:`.

**`CLIBase` tells a refusal from an outage.** It throws
`AtCredentialRefusedException` when the atServer refuses the keys, saying when
an enrollment awaits approval or was denied; `SecondaryNotFoundException` when
the atDirectory has no atServer for the atSign; and
`SecondaryServerConnectivityException` only when the atServer is not reached
in time. A retry loop catches the last alone. A keyfile still holding only its
enrollment request is resumed: the program says it is waiting for that
enrollment, waits for its approval as at_activate does, then runs, and a
denial or expiry ends it with `AtEnrollmentException`.

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

**Embedding at_activate** no longer needs a `src/` import, and a program
that ships it to its own users, as an installer does, keeps working without
`AT_REGISTRAR_API_KEY`: `at_activate onboard` without `-c` asks the
registrar with the built-in key unless the variable is set:

```dart after-cli
import 'dart:io';

Future<void> main(List<String> args) async {
  exitCode = await AtActivate.main(args);
}
```

**Two command-line options are gone.** `CLIBase` takes the root domain
only as `-r`/`--root-server`: a program built on it, run with
`-d`/`--legacy-root-domain`, stops with `Could not find an option or flag
"-d"`. `at_activate` never took that option, and its `-d` is still the
device name, so `at_activate enroll -d <device>` is unchanged. `at_activate`
and `at_register` no longer take `--hashingAlgoType`, which did nothing. A
program passing `addLegacyRootDomainArg:` to `CLIBase.createArgsParser` or
`fromCommandLineArgs` deletes it.

**Checklist**

- [ ] `at_client_cli: ^1.0.0` replaces at_client, at_onboarding_cli,
      at_cli_commons and at_utils in `pubspec.yaml`; a program implementing
      `LoggingHandler` or calling `AtUtils` keeps `at_utils: ^4.0.0`.
- [ ] Every SDK import is `package:at_client_cli/at_client_cli.dart`.
- [ ] `AtOnboardingService` calls are `CLIBase` or `Atsign.open` with
      `CliKeys`; `createAtClient` calls stay as they are.
- [ ] `CLIBase`'s `preference:`, if passed, is an `AtClientPreference`.
- [ ] A retry loop around `CLIBase` catches
      `SecondaryServerConnectivityException`, not every exception.
- [ ] Scripts name `at_activate`'s command (`at_activate onboard ...`).
- [ ] An app that names itself to the registrar sets `AT_REGISTRAR_API_KEY`;
      without it, `at_register` and `at_activate onboard` send the built-in
      key, as before.
- [ ] Scripts pass a `CLIBase` program's root domain as `-r`, not `-d`;
      `at_activate`'s `-d` stays the device name, and nothing passes
      `--hashingAlgoType`.
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

After a restart, `AtsignFlows().resumeEnrollment('@alice', app:, device:,
keys:, preference:)` hands back the request already filed in the keys and
awaiting approval, or null when there is none, rather than filing another.

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

## 5. Post-quantum in two steps

An app built on 3.x writes legacy-encrypted data, and every client that
reads it is a legacy client. at_client 4.0's default posture is still
`PqPosture.legacy`, so an app upgraded by sections 1 to 4 reads and writes
as it did. It moves to post-quantum in two steps, each one a release rolled
out to every client of the app:

1. Rebuild it with `PqPosture.pqReady` and roll that out. Each client then
   authenticates with ML-DSA-65 and can read post-quantum data, and still
   writes legacy, so the clients not yet updated read what it writes.
2. Rebuild it with `PqPosture.pqActive` and roll that out. It now writes
   post-quantum by default, which every client can read after step 1.

```dart after
// Step 1: every client of the app.
final stepOne = AtClientPreference(posture: PqPosture.pqReady)
  ..namespace = 'my_app';

// Step 2: once every client runs step 1.
final stepTwo = AtClientPreference(posture: PqPosture.pqActive)
  ..namespace = 'my_app';
```

After step 2, a device's first write in a namespace needs the atServer,
which seeds or conveys that namespace's key, and a share needs it whenever
the client holds no current copy of the recipient's key. Once a device has
written in a namespace, it goes on writing there offline, across restarts.

A new app has no legacy readers, so it starts at `PqPosture.pqActive`. The
[at_client README](../packages/at_client/README.md#post-quantum-cryptography)
says what each posture switches on.

At `pqActive`, a write made right after the client opens can wait, up to 30
seconds, while the client's start-up publishes the namespace key it seals
to. An app that writes as soon as it opens needs no change for this.
