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
etc.), loads the user's `.atKeys` file, runs PKAM authentication via
[`at_onboarding_cli`](../at_onboarding_cli), and hands back a ready
`AtClient`.

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
  ..someCustomField = 'my value';

final atClient = (await CLIBase.fromCommandLineArgs(
  args,
  preference: pref,
)).atClient;

// pref.hiveStoragePath, pref.namespace, etc. are now populated by CLIBase.
// pref.someCustomField is untouched.
```

## Where to go next

- [`at_client`](../at_client) — the SDK whose `AtClient` this produces
- [`at_onboarding_cli`](../at_onboarding_cli) — how to first-time
  **provision** an atSign (register, CRAM-onboard, APKAM-enroll). Once
  you have a `.atKeys` file, `CLIBase` takes over.
- [`at_auth`](../at_auth) — the lifecycle story behind those keys

## Open source usage and contributions

BSD3-licensed. See [`CONTRIBUTING.md`](../../CONTRIBUTING.md) for
guidance on setting up tools, running tests, and raising a PR.
