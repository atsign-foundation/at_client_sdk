## 3.1.0

- feat: `CLIBase` constructor and `CLIBase.fromCommandLineArgs` now accept an
  optional `preference` parameter (`AtOnboardingPreference`). When supplied,
  `init()` updates that instance in place rather than creating a new one,
  allowing callers to pre-set fields that `CLIBase` does not manage.

## 3.0.1

- feat: Add support for legacy `-d` option. This will be added to the default
  CLIBase ArgParser but, if you wish to use `-d` for some other purpose in your
  program, you may specify `addLegacyRootDomainArg: false` when calling
  `CLIBase.fromCommandLineArgs` or `CLIBase.createArgsParser`
- feat: for better balance between backwards compatibility and forward-looking
  feature, removed the `rootPort` field from CLIBase; instead CLIBase
  constructor will accept *either* `rootDomain` (a String, backwards compatible)
  or `atRootDomain` (an AtRootDomain) and will set CLIBase.atRootDomain (an
  AtRootDomain) accordingly.
- feat: updated the example programs

## 3.0.0

- feat!: changed `-d` (root-domain) option to `-r`
- chore(deps): at_commons ^5.6.0
- feat: Add `license-key` alias to `cramkey` argument in auth CLI
- fix: Implement rootPort functionality
- fix: Various improvements and dependency updates
- feat: `--root-domain` is now an alias of `--root-server` command

## 2.2.0

- chore(deps): at_client ^3.7.0
- chore(deps): chalkdart ">=2.0.9<4.0.0"

## 2.1.0

- feat: Improve usability for args management, including the ability to hide
  some args which, while they are very helpful for dev purposes, are not so
  friendly for end-users.

## 2.0.0

- feat!: (breaking) : remove onboarding capability from CLIBase. (Use
  the at_onboarding_cli package instead.)

## 1.3.0

- feat: Add passPhrase as optional argument to "CLIBase" to support
  password-protected atKeys file.
- build: Upgraded the following dependencies
  - args to v2.6.0
  - at_client to v3.3.0
  - at_onboarding_cli to v1.8.0
  - test to v1.25.9

## 1.2.1

- fix: fix impl of `standardAtClientStoragePath`

## 1.2.0

- feat: Add `standardAtClientStoragePath` and `standardAtClientStorageDir`
  to utils.dart

## 1.1.0

- feat: Add `maxConnectAttempts` parameter to CLIBase. The default is 20,
  i.e. 20 attempts to connect, with a 3-second delay between attempts. When
  used in scripts this is important, as the previous behaviour (retry
  forever) is usually not what is required.

## 1.0.5

- fix: Make CLIBase write progress messages to stderr, not stdout

## 1.0.4

- fix: handle malformed atsigns (no leading `@`) in CLIBase constructor
- build: updated dependencies

## 1.0.3

- Added `example/` package, moved code samples from `bin/` to `example/`

## 1.0.2

- docs: Added some code samples in bin/ directory
- docs: Added some class and method documentation to CLIBase
- docs: Updated README
- feat: Added static `fromCommandLineArgs` factory method to CLIBase

## 1.0.1

- Small edits to README

## 1.0.0

- Initial version.
