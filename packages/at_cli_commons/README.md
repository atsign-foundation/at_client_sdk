# at_cli_commons

**Deprecated.** [`at_client_cli`](https://pub.dev/packages/at_client_cli)
carries this package's code.
Depend on `at_client_cli` and import
`package:at_client_cli/at_client_cli.dart`.

This last major re-exports at_client_cli, so a program using `CLIBase` and
the storage-path helpers compiles after bumping its `at_cli_commons`
constraint, with deprecation warnings pointing at the move. A program that
uses `MySyncProgressListener`, or passes `CLIBase` an
`AtOnboardingPreference`, changes code: at_client_cli's README says to what,
under
[Moving from at_onboarding_cli and at_cli_commons](https://pub.dev/packages/at_client_cli#moving-from-at_onboarding_cli-and-at_cli_commons).
