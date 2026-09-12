<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

[![pub package](https://img.shields.io/pub/v/at_onboarding_cli)](https://pub.dev/packages/at_onboarding_cli) [![pub points](https://img.shields.io/pub/points/at_onboarding_cli?logo=dart)](https://pub.dev/packages/at_onboarding_cli/score) [![gitHub license](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)

# at_onboarding_cli

CLI-side wrapper around [`at_auth`](../at_auth) that provides the
command-line tooling end users and CLI apps need to **register**,
**onboard**, and **enroll** atSigns — plus a library surface for
building your own onboarding tooling.

If you're new to the Atsign Protocol lifecycle (register → onboard → APKAM
enroll), read
[`at_auth`'s README](../at_auth/README.md#the-atsign-lifecycle) first —
this package is the CLI concretisation of that model. [`at_client_flutter`](../at_client_flutter)
is the Flutter-UI equivalent.

## Turnkey CLI tools

Both ship as executables when this package is globally activated:

```sh
dart pub global activate at_onboarding_cli
```

### `at_register` — get a free atSign

```sh
at_register -e your_email@example.com
```

Fetches a free atSign, emails you a verification code, then runs
`at_activate` automatically once you paste the code back. The generated
`.atKeys` file lands in `~/.atsign/keys/`.

### `at_activate` — onboard an atSign (Phase 2 of the lifecycle)

```sh
# Using a CRAM secret from email / registrar
at_activate -a @alice -c <cram_secret>

# OR using an email-delivered verification code
at_activate -a @alice
```

Either form produces the **master `.atKeys`** in `~/.atsign/keys/`.
**These are the root of trust for `@alice` — back them up.**

## APKAM enrollment

A new device / app authenticating as an existing atSign should go
through APKAM rather than asking the user for their master keys. The
worked example lives under [`example/apkam_examples/`](example/apkam_examples):

- [`apkam_enroll.dart`](example/apkam_examples/apkam_enroll.dart) —
  the **new** device submits an enrollment request scoped to specific
  namespaces
- [`enroll_app_listen.dart`](example/apkam_examples/enroll_app_listen.dart)
  — a device holding the master keys listens for and approves /
  denies incoming requests
- [`apkam_authenticate.dart`](example/apkam_examples/apkam_authenticate.dart)
  — the new device authenticates with its newly-issued scoped keys

Full step-by-step walkthrough:
[`example/README.md`](example/README.md).

## Library usage

The lifecycle is at_client's: one import, and the verbs are on the atSign.

```dart
import 'package:at_auth/at_auth_io.dart' show FileAtKeysIo;
import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';

final keys = FileAtKeysIo(filePath: (_) => 'storage/@alice_key.atKeys');
final pref = AtOnboardingPreference()
  ..rootDomain = 'root.atsign.org'
  ..namespace = 'my_app'
  ..storagePath = 'storage/hive';

// Activate a new atSign with its CRAM secret; `OnboardingUtil` fetches one
// from the registrar against an emailed verification code.
final client = await Atsign('@alice').activate(
    cramSecret: secret, keys: keys, preference: pref,
    storage: pref.storageFor('@alice'));

// Open a client on keys already held. It comes back online, offline or
// refused, and `connection` says which.
final client = await Atsign('@alice').open(
    keys: keys, preference: pref, storage: pref.storageFor('@alice'));
print(client.connection.current);

// Enrol a new device, quoting a passcode an enrolled client issued, and wait
// for that client to approve. The keyfile is the resume record: a request
// already in it is picked up by `resumeEnrollment` rather than repeated.
final pending = await Atsign('@alice').enroll(
    otp: otp, app: 'my_app', device: 'laptop',
    namespaces: {'my_app': 'rw'}, keys: keys, preference: pref);
final client = await pending.client(pref, storage: pref.storageFor('@alice'));

// The approving side, on an enrolled client.
for (final request in await client.enrollments.pending()) {
  await client.enrollments.approve(request.enrollmentId!);
}
final otp = await client.enrollments.otp();
```

`AtOnboardingService` stays for programs written against earlier versions of
this package: `AtOnboardingServiceImpl('@alice', pref).authenticate()` opens
the client from `pref.atKeysFilePath`, makes it
`AtClientManager.getInstance().atClient`, and answers whether it is online.

Worked examples covering each flow:
[`example/`](example) and
[`example/legacy_examples/`](example/legacy_examples).

Most **app** developers don't need this library directly — they use
[`at_cli_commons`](../at_cli_commons)' `CLIBase`, which opens the client
through at_client.

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
