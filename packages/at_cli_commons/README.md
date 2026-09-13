# at_cli_commons

Small helper library for **Dart CLI / server programs** that use the
[`at_client`](../at_client) SDK. Wraps the boilerplate of parsing
command-line flags, loading keys, and producing an authenticated
`AtClient` behind a single call.

## Usage

```dart
import 'package:at_cli_commons/at_cli_commons.dart';

Future<void> main(List<String> args) async {
  final atClient = (await CLIBase.fromCommandLineArgs(args)).atClient;
  // atClient is authenticated and ready to use
}
```

`CLIBase.fromCommandLineArgs(...)` parses the standard at-SDK flags
(`-a <atsign>`, `-k <keys-file>`, `-n <namespace>`, `-r <root-domain>`,
`-s <storage-dir>`, `-P <pass-phrase>`, `--never-sync`,
`--max-connect-attempts`, `-v`), loads the user's `.atKeys` file, opens the
client through at_client's `Atsign.open`, waits for its connection to come
online — `max-connect-attempts` tries, three seconds apart — and hands back
a ready `AtClient`. A refusal by the atServer (revoked keys, an unapproved
enrollment) is thrown at once as `AtOpenRefusedException`; a connection
still offline when the budget is spent is
`SecondaryServerConnectivityException`.

Two worked examples live under [`example/bin/`](example/bin):

- [`scan_example.dart`](example/bin/scan_example.dart) — list every key
  on the atServer
- [`put_and_get_example.dart`](example/bin/put_and_get_example.dart) —
  end-to-end put / get round-trip with TTL

More programs using `CLIBase` in anger:
[`at_lorawan`](https://github.com/atsign-foundation/at_lorawan) and the
examples under [`../at_client/example/`](../at_client/example/README.md).

## Injecting an AtOnboardingPreference

If you need to pre-configure fields on the `AtOnboardingPreference`
before `CLIBase` builds its client — custom storage paths, hooks, test
overrides — pass an instance in. `CLIBase` will fill in the
CLI-derived fields in place rather than constructing its own preference
object:

```dart
final pref = AtOnboardingPreference()
  ..appName = 'my_app';

final atClient = (await CLIBase.fromCommandLineArgs(
  args,
  preference: pref,
)).atClient;

// pref.hiveStoragePath, pref.namespace, etc. are now populated by CLIBase.
// pref.appName is untouched.
```

The post-quantum rollout flags are **final at construction** — what a client
writes must not change meaning while it is running — so those are named in the
constructor rather than assigned afterwards:

```dart
final pref = AtOnboardingPreference(
  posture: PqPosture.pqActive,
)..appName = 'my_app';
```

`posture`, `authenticationKeyAlgorithm`, `dataSigningKeyAlgorithms` and
`sealsToKeyAlgorithms` are all available there, and each is optional. Every
type they take — including `SigningAlgoType` — is nameable from
`package:at_client/at_client.dart` alone.

`disallowLegacyEncryption` is deliberately **not** among them: it is settable
only through the posture, so an app that wants legacy writes refused adopts
`PqPosture.pqActive` or builds a posture that says so.

## Upgrading

`CLIBase` kept its API through at_onboarding_cli 2.0 and at_auth 4.0: a
program that calls `CLIBase.fromCommandLineArgs(args)` needs no change. What
moved underneath is that the client is opened through `Atsign.open` rather
than re-authenticated in a loop, so a refusal surfaces as
`AtOpenRefusedException` where it used to surface as a connectivity
exception, and the local storage location is
`AtOnboardingPreference.storagePath` rather than the deprecated
`hiveStoragePath` (the store lands in the same place).

## Where to go next

- [`at_client`](../at_client) — the SDK whose `AtClient` this produces
- [`at_onboarding_cli`](../at_onboarding_cli) — how to first-time
  **provision** an atSign (register, CRAM-onboard, APKAM-enroll). Once
  you have a `.atKeys` file, `CLIBase` takes over.
- [`at_auth`](../at_auth) — the lifecycle story behind those keys

## Open source usage and contributions

BSD3-licensed. See [`CONTRIBUTING.md`](../../CONTRIBUTING.md) for
guidance on setting up tools, running tests, and raising a PR.
