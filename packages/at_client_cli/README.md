<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

[![pub package](https://img.shields.io/pub/v/at_client_cli)](https://pub.dev/packages/at_client_cli) [![pub points](https://img.shields.io/pub/points/at_client_cli?logo=dart)](https://pub.dev/packages/at_client_cli/score) [![gitHub license](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)

# at_client_cli

The Atsign Protocol for a Dart command-line program, daemon or server:

- `at_activate` and `at_register`, for **registering**, **activating** and
  **enrolling** atSigns from a terminal;
- `CLIBase`, which turns a program's standard command-line flags into an
  online `AtClient`;
- `CliKeys`, where those programs keep an atSign's keyfile and local store.

The lifecycle itself is [`at_client`](../at_client)'s — `Atsign.activate`,
`Atsign.open` and `Atsign.enroll` do the work, and this package gives them a
command line. It replaces at_onboarding_cli and at_cli_commons: see
[Moving from at_onboarding_cli and at_cli_commons](#moving-from-at_onboarding_cli-and-at_cli_commons).

If you're new to the Atsign Protocol lifecycle (register → activate → APKAM
enroll), read
[`at_auth`'s README](../at_auth/README.md#the-atsign-lifecycle) first —
this package is the CLI concretisation of that model.
[`at_client_flutter`](../at_client_flutter) is the Flutter-UI equivalent.

## Turnkey CLI tools

Both ship as executables when this package is globally activated:

```sh
dart pub global activate at_client_cli
```

### `at_register` — get a free atSign

```sh
at_register -e your_email@example.com
```

Fetches a free atSign, emails you a verification code, then activates the
atSign once you paste the code back. The generated `.atKeys` file lands in
`~/.atsign/keys/`.

### `at_activate` — the atSign's lifecycle from the terminal

Every invocation should name a command. With none, `at_activate` still runs
`onboard`, as at_onboarding_cli 1.x did, but prints a deprecation warning,
because a later major will refuse it.

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
An unnamed `--posture` is at_client's default on every command (`legacy`
today), and `onboard` and `enroll` say which posture they ran at. Approving
a post-quantum enrollment needs the post-quantum providers, so under `legacy`
at_client refuses such an approval when it reads the request; pass
`--posture pqReady` to approve one. `enroll --key-exchange legacy|pq`
chooses how the enrollment's symmetric key travels, for the approver that
will pick the request up.

## APKAM enrollment

A new device / app authenticating as an existing atSign should go
through APKAM rather than asking the user for their master keys. The
worked example lives under [`example/bin/apkam_examples/`](example/bin/apkam_examples):

- [`apkam_enroll.dart`](example/bin/apkam_examples/apkam_enroll.dart) —
  the **new** device submits an enrollment request scoped to specific
  namespaces
- [`enroll_app_listen.dart`](example/bin/apkam_examples/enroll_app_listen.dart)
  — a device holding the master keys listens for and approves /
  denies incoming requests, through `client.enrollments`
- [`apkam_authenticate.dart`](example/bin/apkam_examples/apkam_authenticate.dart)
  — the new device authenticates with its newly-issued scoped keys

Full step-by-step walkthrough:
[`example/README.md`](example/README.md).

## Library usage

### A program's client: `CLIBase`

`CLIBase` turns the standard command-line flags into an online client:

```dart
import 'package:at_client_cli/at_client_cli.dart';

Future<void> main(List<String> args) async {
  final parser = CLIBase.createArgsParser(namespace: 'my_app');
  final AtClient client =
      (await CLIBase.fromCommandLineArgs(args, parser: parser)).atClient;
  // ...
  await client.stop();
}
```

`-a` names the atSign, `-k` its keyfile (`~/.atsign/keys/<atSign>_key.atKeys`
by default), `-r` the atDirectory, `-s` the local store and `-P` the keyfile's
pass-phrase; `--help` lists the rest. `fromCommandLineArgs` waits up to
`--max-connect-attempts` tries, 3 seconds apart, for the client to come
online, and throws if it does not. Pass `preference:` an
`AtClientPreference` to set anything the flags do not.

### The lifecycle verbs, with `CliKeys`

A program that does not take `CLIBase`'s flags calls at_client's verbs
itself. The one import carries them, since at_client_cli re-exports
at_client's native API, the Hive store, the registrar and the logging
handlers. `CliKeys` gives the verbs the keyfile and store a command-line
program keeps:

```dart
import 'package:at_client_cli/at_client_cli.dart';

final preference = AtClientPreference()..namespace = 'my_app';
final keys = CliKeys.fileFor('@alice');       // ~/.atsign/keys/@alice_key.atKeys
final storage = CliKeys.storageFor('@alice', program: 'my_app');
final lookUps = secureSocketLookUps();
final atDirectory =
    CacheableSecondaryAddressFinder(preference.rootDomain, preference.rootPort);
```

`CliKeys.fileFor` takes a `path` and a `passPhrase`; `CliKeys.storageFor`
puts the store under `~/.atsign/storage/<atSign>/<program>/`, where `CLIBase`
keeps it for that namespace, or at `path`, and the client closes it when it
stops. `lookUps` builds every connection the
client opens: `proxyLookUps()` when the root domain names a proxy
(`proxy:host:port`), which sends `from:<atSign>` first on every connection so
the proxy can route it, and TLS on TCP otherwise.

Activate a new atSign with its CRAM secret (or run `at_activate onboard`,
which fetches one from the registrar against an emailed verification code):

```dart
final owner = await Atsign('@alice').activate(
    cramSecret: secret, keys: keys, preference: preference, storage: storage,
    lookUps: lookUps, secondaryAddressFinder: atDirectory);
```

Open a client on keys already held. It comes back online, offline or
refused, and `connection` says which:

```dart
final client = await Atsign('@alice').open(
    keys: keys, preference: preference, storage: storage,
    lookUps: lookUps, secondaryAddressFinder: atDirectory);
print(client.connection.current);
```

Enrol a new device, quoting a passcode an enrolled client issued, and wait
for that client to approve. The keyfile is the resume record: a request
already in it is picked up by `resumeEnrollment` rather than repeated.

```dart
final deviceKeys = CliKeys.fileFor('@alice', path: 'my_app_laptop.atKeys');
final pending = await Atsign('@alice').enroll(
    otp: otp, app: 'my_app', device: 'laptop',
    namespaces: {'my_app': 'rw'}, keys: deviceKeys, preference: preference,
    lookUps: lookUps, secondaryAddressFinder: atDirectory);
final enrolled = await pending.client(preference,
    storage: CliKeys.storageFor('@alice',
        program: 'my_app', id: pending.enrollmentId));
```

The approving side, on an enrolled client:

```dart
for (final request in await owner.enrollments.pending()) {
  await owner.enrollments.approve(request.enrollmentId!);
}
final passcode = await owner.enrollments.otp();
```

Worked examples covering each flow are in [`example/bin/`](example/bin).

## Moving from at_onboarding_cli and at_cli_commons

at_client_cli carries both packages' code. Their last majors,
at_onboarding_cli 2.0.0 and at_cli_commons 4.0.0, re-export it under a
deprecated library and keep the `at_activate` and `at_register` executables,
so `dart pub global activate at_onboarding_cli` still installs working tools.
A program that used `AtOnboardingService`, `AtOnboardingPreference` or the
helpers below changes code at the bump; one that used only `CLIBase` and the
path helpers changes its dependency and import. The `.atKeys` file
at_onboarding_cli 1.x wrote is read unchanged.

| at_onboarding_cli 1.x, at_cli_commons 3.x                                                       | at_client_cli 1.0                                                                                                                                                       |
| ------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `package:at_onboarding_cli/at_onboarding_cli.dart`, `package:at_cli_commons/at_cli_commons.dart` | `package:at_client_cli/at_client_cli.dart`                                                                                                                              |
| `dart pub global activate at_onboarding_cli`                                                     | `dart pub global activate at_client_cli`; the old command still installs the same tools                                                                                 |
| `CLIBase(..., preference: AtOnboardingPreference())`                                             | unchanged, except that `preference:` takes an `AtClientPreference`                                                                                                      |
| `AtOnboardingServiceImpl(atSign, pref).authenticate()`, then `.atClient`                         | `CLIBase.fromCommandLineArgs(...)`, or `Atsign(atSign).open(...)` with `CliKeys`                                                                                        |
| `.onboard()`                                                                                     | `Atsign(atSign).activate(...)`, or `at_activate onboard`                                                                                                                |
| `.enroll(...)`, `.sendEnrollRequest(...)`, `.awaitApproval(...)`, `.createAtKeysFile(...)`       | `Atsign(atSign).enroll(...)` and `PendingEnrollment.client(...)`; `Atsign.resumeEnrollment` picks a pending request up after a restart                                  |
| `.isOnboarded()`                                                                                 | `at_activate status`, or at_lookup's `checkAtSignServer`                                                                                                                |
| `.close()`                                                                                       | `atClient.stop()`                                                                                                                                                       |
| `.atLookUp`, `.atChops`, `.atAuth`, `.completeActivation()`, `.getAtClient()`                    | none; the client's own connection does what they exposed                                                                                                                |
| `AtOnboardingPreference`                                                                         | `AtClientPreference`; its `atKeysFilePath` and `passPhrase` are `CliKeys.fileFor(atSign, path: ..., passPhrase: ...)`, its `storagePath` is `CliKeys.storageFor(...)` |
| `AtOnboardingPreference()..signingAlgoType = ...`                                                | `AtClientPreference(posture: ..., authenticationKeyAlgorithm: ...)`, fixed at construction                                                                              |
| `createAtClient(...)`                                                                            | `CLIBase`                                                                                                                                                               |
| `OnboardingUtil`                                                                                 | `at_activate onboard` fetches a CRAM secret, and `at_register` a free atSign                                                                                            |
| `AuthKeyType`                                                                                    | none: read a keyfile with `CliKeys.fileFor(atSign).read(atSign)`                                                                                                        |
| `MySyncProgressListener`                                                                         | a `SyncProgressListener` of the program's own                                                                                                                           |
| `package:at_onboarding_cli/src/activate_cli/activate_cli.dart`                                   | `AtActivate.main(args)`, or the `at_activate` executable                                                                                                                |
| `AtOnboardingException` and its subclasses                                                       | `AtClientException`, which they extended                                                                                                                                |
| `at_activate -a @alice -c <secret>` (no command)                                                 | `at_activate onboard -a @alice -c <secret>`; an invocation naming no command still runs `onboard`, with a deprecation warning                                           |
| (no signing-algorithm flag)                                                                      | `--posture legacy\|pqReady\|pqActive` on every command; `enroll --key-exchange legacy\|pq` for how the enrollment's key travels                                          |
| the `*.enrollment.checkpoint` file                                                               | gone; the keyfile holds the pending keys                                                                                                                                |
| at_activate's store under `~/.atsign/at_onboarding_cli/storage/`                                 | under `~/.atsign/storage/<atSign>/at_activate/`, started afresh; the keys, in the keyfile, are untouched                                                               |
| the keyfile `onboard` writes                                                                     | at_auth's own document: the self-encryption key is no longer duplicated under the atSign, and a passphrase-protected file uses a salted envelope that 1.x tooling cannot read |

## Where to go next

- [`at_auth`](../at_auth) — the keyfile format and key stores, and the
  protocol layer under at_client
- [`at_client_flutter`](../at_client_flutter) — the Flutter-UI
  equivalent of this package

## Open source usage and contributions

BSD3-licensed. See [`CONTRIBUTING.md`](../../CONTRIBUTING.md) for
guidance on setting up tools, running tests, and raising a PR.
