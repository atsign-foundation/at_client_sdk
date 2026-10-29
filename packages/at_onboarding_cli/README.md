# at_onboarding_cli

**Deprecated.** [`at_client_cli`](https://pub.dev/packages/at_client_cli)
carries this package's code, and its `at_activate` and `at_register` tools.
Depend on `at_client_cli` and import
`package:at_client_cli/at_client_cli.dart`.

This last major re-exports at_client_cli and keeps one-line `at_activate`
and `at_register` executables that run at_client_cli's, so
`dart pub global activate at_onboarding_cli` still installs working tools.
A program importing this package changes code if it uses
`AtOnboardingService`, `AtOnboardingPreference`, `OnboardingUtil` or
`AuthKeyType`, which at_client_cli does not carry:
at_client_cli's README says what replaces each, under
[Moving from at_onboarding_cli and at_cli_commons](https://pub.dev/packages/at_client_cli#moving-from-at_onboarding_cli-and-at_cli_commons).
Otherwise it compiles after bumping its `at_onboarding_cli` constraint. The
analyzer does not flag an import of this deprecated library, so nothing at
compile time points at the move: change the import to at_client_cli's.

[Upgrading to at_client 4.0](https://github.com/atsign-foundation/at_client_sdk/blob/trunk/docs/upgrade-to-4.md) takes a program through the whole move.
