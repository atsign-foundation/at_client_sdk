## 1.0.0

- docs: [Upgrading to at_client 4.0](https://github.com/atsign-foundation/at_client_sdk/blob/trunk/docs/upgrade-to-4.md) takes an app from at_client 3 to 4.
- feat: `at_activate approve` warns when it approves a request made at the
  legacy key exchange on an atSign that publishes a namespace key: the
  approval conveys none of the atSign's namespace keys, and requesting again
  at `--posture pqReady` conveys them.
- feat: a `CLIBase` program that cannot reach the atServer names the
  atDirectory address and what failed.
- feat: a `CLIBase` program whose keyfile holds no credential, as a denial,
  a cancel or an expiry leaves it, says so on stderr and stops at once.
- feat: a `CLIBase` program shows the SDK's warnings on stderr by default,
  such as a notification it could not decrypt; `-v` shows the rest.
- feat: `at_register`, and `at_activate onboard` without `-c`, ask the
  registrar with the API key in `AT_REGISTRAR_API_KEY` when it is set, and
  otherwise with a built-in key, so both work without it. A key that is set
  but holds a character an HTTP header cannot carry is refused before
  anything is sent.
- feat: a program built on `CLIBase` whose keyfile still holds only its
  enrollment request waits for the approval, as at_activate does, and then
  runs, rather than throwing.
- feat: instances of a program that share a keyfile opened through
  `CliKeys.fileFor`, as `CLIBase` opens it, retrofit it one at a time.
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
- feat: `lookUpsFor(rootDomain)` gives a program that opens its own client
  the connections `CLIBase` makes, through a proxy when the root domain names
  one (`proxy:host:port`).
- feat: `createAtClient` opens a command's client from its keyfile, syncing
  nothing, as at_activate's commands do. It takes at_onboarding_cli
  2.0.0-rc8's parameters, so a program that called it there compiles
  unchanged.
- breaking: `AtOnboardingService`, `AtOnboardingPreference`,
  `OnboardingUtil`, `AuthKeyType`, `MySyncProgressListener`,
  `EnrollmentDetails`, `PrintAllArgParserUsage` and the
  `AtOnboardingException` family are not carried over. A program opens its
  client with `CLIBase` or `Atsign.open`; the README's migration table names
  what replaces each.
- breaking: `CLIBase`'s `preference` is an `AtClientPreference`.
- breaking: `CLIBase` takes no `-d`/`--legacy-root-domain`, so use
  `-r`/`--root-server`, and `CLIBase.createArgsParser` and
  `fromCommandLineArgs` take no `addLegacyRootDomainArg`. `at_activate`'s
  `-d` is still the device name. The tools take no `--hashingAlgoType`,
  which did nothing.
- breaking: `CLIBase` takes no `downloadDir`, which nothing read.
- breaking: `CLIBase` throws `AtCredentialRefusedException` for every
  refusal and `SecondaryNotFoundException` for an atSign the atDirectory does
  not know; `SecondaryServerConnectivityException` now means only an outage.
- fix: on Windows, `standardAtClientStorageDir` returns its directory under
  `TEMP` rather than overflowing the stack.
- fix: `at_activate auto` goes on listening after an enrollment request it
  cannot read or act on, which it reports on stderr, until it has approved as
  many as it was asked to.
- fix: with debug logging on, a registrar request is logged by its URL and
  response status, never by its body.
- fix: `RegistrationFlow.start`, and so `Register.main`, throw an
  `AtClientException` when the registrar refuses a step.
- fix: at_activate's `--mca` sets how many times a command tries to connect,
  three seconds apart; the default of 10 waits about 30 seconds.
- fix: at_register exits with at_activate's non-zero code, instead of 0,
  when the activation after registration fails.
- fix: at_register confirms a verification code the registrar accepts with a
  follow-up at once, so the third code accepted still gets the CRAM key. A
  registrar that asks again to confirm a confirmed code ends the registration
  with exit 4.
- fix: the at_activate Dockerfile builds from the repo root on Dart 3.
- fix: at_register exits 5, not 4, after three refused verification codes,
  and asks for no fourth code.
