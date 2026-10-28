## 1.0.0

- feat: at_client_cli is at_onboarding_cli and at_cli_commons in one package:
  `CLIBase`, the at_activate and at_register tools, and the library behind
  them. `AtActivate.main` and `AtRegister.main` run the tools inside another
  program.
- feat: `CliKeys.fileFor` and `CliKeys.storageFor` are the keyfile and local
  store a command-line program keeps for an atSign, ready for at_client's
  `Atsign.activate`, `open` and `enroll`.
- breaking: `AtOnboardingService`, `AtOnboardingPreference`, `createAtClient`,
  `OnboardingUtil`, `AuthKeyType`, `MySyncProgressListener` and the
  `AtOnboardingException` family are not carried over. A program opens its
  client with `CLIBase` or `Atsign.open`; the README's migration table names
  what replaces each.
- breaking: `CLIBase`'s `preference` is an `AtClientPreference`.
- fix: on Windows, `standardAtClientStorageDir` returns its directory under
  `TEMP` rather than overflowing the stack.
