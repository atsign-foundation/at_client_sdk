# at_onboarding_cli

**Deprecated.** [`at_client_cli`](https://pub.dev/packages/at_client_cli)
carries this package's code, and its `at_activate` and `at_register` tools.
Depend on `at_client_cli` and import
`package:at_client_cli/at_client_cli.dart`.

This last major re-exports at_client_cli, so a program that only bumps its
`at_onboarding_cli` constraint still compiles, with deprecation warnings pointing at the
move.
