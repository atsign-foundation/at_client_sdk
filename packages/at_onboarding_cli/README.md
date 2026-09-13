<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

[![pub package](https://img.shields.io/pub/v/at_onboarding_cli)](https://pub.dev/packages/at_onboarding_cli) [![pub points](https://img.shields.io/pub/points/at_onboarding_cli?logo=dart)](https://pub.dev/packages/at_onboarding_cli/score) [![gitHub license](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)

# at_onboarding_cli

The command-line tools, and a small library, for **registering**,
**activating** and **enrolling** atSigns from a terminal or a headless
program. The lifecycle itself is [`at_client`](../at_client)'s —
`Atsign.activate`, `Atsign.open` and `Atsign.enroll` do the work — and this
package wraps those verbs in two binaries, plus an `AtOnboardingService`
for programs written against earlier versions.

If you're new to the Atsign Protocol lifecycle (register → activate → APKAM
enroll), read
[`at_auth`'s README](../at_auth/README.md#the-atsign-lifecycle) first —
this package is the CLI concretisation of that model.
[`at_client_flutter`](../at_client_flutter) is the Flutter-UI equivalent.

## Turnkey CLI tools

Both ship as executables when this package is globally activated:

```sh
dart pub global activate at_onboarding_cli
```

### `at_register` — get a free atSign

```sh
at_register -e your_email@example.com
```

Fetches a free atSign, emails you a verification code, then activates the
atSign once you paste the code back. The generated `.atKeys` file lands in
`~/.atsign/keys/`.

### `at_activate` — the atSign's lifecycle from the terminal

Every invocation names a command; `at_activate` with none prints the list
and exits 1.

```sh
# Activate a newly registered atSign with the CRAM secret the registrar sent
at_activate onboard -a @alice -c <cram_secret>

# ...or let at_activate fetch it: the registrar emails a verification code,
# which you paste back
at_activate onboard -a @alice
```

Either form writes the **master `.atKeys`** to
`~/.atsign/keys/@alice_key.atKeys`. **These are the root of trust for
`@alice` — back them up.**

The remaining commands run on the keyfile `-k` names (that one by default):

| Command                                            | What it does                                                                                                             |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `status -a @alice`                                 | asks where the atSign stands; the exit code says: 0 activated, 1 atServer up but not yet activated, 2 atServer unreachable, 3 no such atSign, 4 atDirectory unreachable |
| `enroll -a @alice --app <app> --device <device> --namespaces <ns:rw,...> --passcode <otp>` | submits an APKAM enrollment for a new app and device and waits for its approval; run again for the same app and device, it resumes the wait rather than submitting a second request |
| `otp` / `spp`                                      | issues a one-time passcode, or sets a semi-permanent one, that a new enrollment quotes                                    |
| `list`, `fetch`                                    | the enrollment roster, or one enrollment's record                                                                        |
| `approve`, `deny`, `revoke`, `unrevoke`, `delete`  | decides an enrollment by its id; `auto` listens and approves the requests that match its app and device patterns        |
| `interactive`                                      | a shell over the commands above                                                                                          |
| `decrypt`                                          | writes a passphrase-protected keyfile out decrypted                                                                     |

`--posture legacy|pqReady|pqActive` is accepted on every command and decides
what a client built for it does post-quantum (see the
[at_client README](../at_client/README.md#post-quantum-cryptography)).
`onboard` and `enroll` default to `legacy`, so the keys they write stay
usable by a legacy app; every other command defaults to `pqReady` and refuses
`legacy`, since approving a post-quantum enrollment needs the post-quantum
providers. `enroll --key-exchange legacy|pq` chooses how the enrollment's
symmetric key travels, for the approver that will pick the request up.

## APKAM enrollment

A new device / app authenticating as an existing atSign should go
through APKAM rather than asking the user for their master keys. The
worked example lives under [`example/apkam_examples/`](example/apkam_examples):

- [`apkam_enroll.dart`](example/apkam_examples/apkam_enroll.dart) —
  the **new** device submits an enrollment request scoped to specific
  namespaces
- [`enroll_app_listen.dart`](example/apkam_examples/enroll_app_listen.dart)
  — a device holding the master keys listens for and approves /
  denies incoming requests, through `client.enrollments`
- [`apkam_authenticate.dart`](example/apkam_examples/apkam_authenticate.dart)
  — the new device authenticates with its newly-issued scoped keys

Full step-by-step walkthrough:
[`example/README.md`](example/README.md).

## Library usage

The lifecycle is at_client's: one import, and the verbs are on the atSign.
`AtOnboardingPreference` extends `AtClientPreference` with where the keyfile
and the local storage live, and `storageFor(atSign)` is the store a client
for that atSign opens under it.

```dart
import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';

final keys = FileAtKeysIo(filePath: (_) => 'storage/@alice_key.atKeys');
final pref = AtOnboardingPreference()
  ..rootDomain = 'root.atsign.org'
  ..namespace = 'my_app'
  ..storagePath = 'storage/hive';
```

Activate a new atSign with its CRAM secret (`OnboardingUtil` fetches one
from the registrar against an emailed verification code):

```dart
final owner = await Atsign('@alice').activate(
    cramSecret: secret, keys: keys, preference: pref,
    storage: pref.storageFor('@alice'));
```

Open a client on keys already held. It comes back online, offline or
refused, and `connection` says which:

```dart
final client = await Atsign('@alice').open(
    keys: keys, preference: pref, storage: pref.storageFor('@alice'));
print(client.connection.current);
```

Enrol a new device, quoting a passcode an enrolled client issued, and wait
for that client to approve. The keyfile is the resume record: a request
already in it is picked up by `resumeEnrollment` rather than repeated.

```dart
final pending = await Atsign('@alice').enroll(
    otp: otp, app: 'my_app', device: 'laptop',
    namespaces: {'my_app': 'rw'}, keys: keys, preference: pref);
final enrolled = await pending.client(pref, storage: pref.storageFor('@alice'));
```

The approving side, on an enrolled client:

```dart
for (final request in await owner.enrollments.pending()) {
  await owner.enrollments.approve(request.enrollmentId!);
}
final passcode = await owner.enrollments.otp();
```

Two helpers stay for programs written against earlier versions of this
package. `AtOnboardingServiceImpl('@alice', pref).authenticate()` opens the
client from `pref.atKeysFilePath`, makes it
`AtClientManager.getInstance().atClient`, and answers whether it is online;
`createAtClient(atSign: '@alice', atKeysFilePath: ..., rootDomain: ...)`
does the same from bare arguments and waits for the connection with a
budget of `maxConnectAttempts` tries.

Worked examples covering each flow:
[`example/`](example) and
[`example/legacy_examples/`](example/legacy_examples).

Most **app** developers don't need this library directly — they use
[`at_cli_commons`](../at_cli_commons)' `CLIBase`, which opens the client
through at_client.

## Migrating from 1.x

2.0 moves everything `AtOnboardingService` orchestrated to at_client, keeps
`authenticate()` and `atClient` for the programs that call them, and makes
`at_activate` name its command. The `.atKeys` file a 1.x tool wrote is read
unchanged.

| 1.x                                                                                        | 2.0                                                                                                                                                                                  |
| ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `at_activate -a @alice -c <secret>` (no command)                                           | `at_activate onboard -a @alice -c <secret>`; an invocation naming no command prints the list and exits 1                                                                             |
| `--signingAlgoType mldsa65` on `onboard`                                                   | `--posture legacy\|pqReady\|pqActive`, honoured on every command; `enroll --key-exchange legacy\|pq` for how the enrollment's key travels                                            |
| `AtOnboardingServiceImpl(atSign, pref).onboard()`                                          | `Atsign(atSign).activate(cramSecret: ..., keys: ..., preference: pref, storage: pref.storageFor(atSign))`                                                                            |
| `.authenticate()`                                                                          | unchanged: opens the client through `Atsign.open`, makes it current, and answers true only when its connection is online; an offline client is still held, `atClient.connection` says why |
| `.authenticate(enrollmentId: ...)`                                                         | the keyfile decides which enrollment authenticates; a value that disagrees is logged and ignored                                                                                     |
| `.enroll(...)`, `.sendEnrollRequest(...)`, `.awaitApproval(...)`, `.createAtKeysFile(...)` | `Atsign(atSign).enroll(...)` and `PendingEnrollment.client(...)`; the keyfile named on `enroll` is the resume record, and `Atsign.resumeEnrollment` picks a pending request up after a restart |
| the `*.enrollment.checkpoint` file                                                         | gone; the keyfile holds the pending keys                                                                                                                                             |
| `.close()`                                                                                 | `atClient.stop()`                                                                                                                                                                    |
| `.isOnboarded()`                                                                           | the atDirectory's answer: `at_activate status`, or at_server_status's `AtStatusImpl`                                                                                                 |
| `.atLookUp`, `.atChops`, `.atAuth`, `.completeActivation()`                                | none; the client's own connection does what they exposed                                                                                                                             |
| `.getAtClient()`                                                                           | `.atClient`                                                                                                                                                                          |
| `AtOnboardingPreference.hiveStoragePath`, `.commitLogPath`                                 | `.storagePath`, or `.storage` for a bundle of your own; `commitLogPath` was never read                                                                                               |
| `AtOnboardingPreference()..signingAlgoType = ...`                                          | `AtOnboardingPreference(posture: ..., authenticationKeyAlgorithm: ..., dataSigningKeyAlgorithms: ...)`, fixed at construction                                                       |
| `package:at_onboarding_cli/src/activate_cli/activate_cli.dart`                             | removed; run the `at_activate` binary                                                                                                                                                |
| `authenticate()` copying the keyfile's keys into the client's local storage                | the client reads them from its key source                                                                                                                                            |
| the keyfile `onboard` writes                                                               | at_auth's own document: the self-encryption key is no longer duplicated under the atSign, and a passphrase-protected file uses a salted envelope that 1.x tooling cannot read      |

## Where to go next

- [`at_auth`](../at_auth) — the keyfile format and key stores, and the
  protocol layer under at_client
- [`at_cli_commons`](../at_cli_commons) — thin layer that gets you from
  already-onboarded atKeys to an authenticated `AtClient` in one line
- [`at_client_flutter`](../at_client_flutter) — the Flutter-UI
  equivalent of this package

## Open source usage and contributions

BSD3-licensed. See [`CONTRIBUTING.md`](../../CONTRIBUTING.md) for
guidance on setting up tools, running tests, and raising a PR.
