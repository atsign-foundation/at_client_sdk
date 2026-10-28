## 1.0.0

- docs: [Upgrading to at_client 4.0](https://github.com/atsign-foundation/at_client_sdk/blob/trunk/docs/upgrade-to-4.md) takes an app from at_client 3 to 4.
- feat: at_client_cli is at_onboarding_cli and at_cli_commons in one package:
  `CLIBase`, the at_activate and at_register tools, and the library behind
  them. `AtActivate.main` and `AtRegister.main` run the tools inside another
  program.
- feat: `package:at_client_cli/at_client_cli.dart` is the only SDK import a
  command-line program needs: it re-exports at_client's native API, the Hive,
  SQLite and in-memory stores, at_client's mixins (`AtClientInvitations`,
  `EnrollmentUpdater`), `RegistrarService` and the io logging handlers.
- feat: `CliKeys.fileFor` and `CliKeys.storageFor` are the keyfile and local
  store a command-line program keeps for an atSign, ready for at_client's
  `Atsign.activate`, `open` and `enroll`.
- breaking: `AtOnboardingService`, `AtOnboardingPreference`, `createAtClient`,
  `OnboardingUtil`, `AuthKeyType`, `MySyncProgressListener`,
  `EnrollmentDetails`, `PrintAllArgParserUsage` and the
  `AtOnboardingException` family are not carried over. A program opens its
  client with `CLIBase` or `Atsign.open`; the README's migration table names
  what replaces each.
- breaking: `CLIBase`'s `preference` is an `AtClientPreference`.
- breaking: `CLIBase` throws `AtCredentialRefusedException` for every
  refusal and `SecondaryNotFoundException` for an atSign the atDirectory does
  not know; `SecondaryServerConnectivityException` now means only an outage.
- fix: on Windows, `standardAtClientStorageDir` returns its directory under
  `TEMP` rather than overflowing the stack.
