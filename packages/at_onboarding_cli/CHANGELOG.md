## 1.16.0

- chore(deps): at_chops ^3.0.0

## 1.15.0

- feat: add `--root-server` option to specify root server domain
- feat: add `--license-key` alias for `--cramkey`
- chore(deps): at_commons: ^5.6.0
- chore(deps): args gkc/show-aliases-in-usage dependency override
## 1.14.2

 - chore: export createAtClientCli() to be used downstream

## 1.14.1

- build: remove the dependency override on the `args` package
- feat: export method requestEnrollmentOtp() to be used downstream
- feat: expose atKeysFile in OnboardingService.enroll() method signature

## 1.14.0

- feat: export the PrintAllArgParserUsage mixin on ArgParser
- feat: export AuthCliArgs

## 1.13.0

- add a warning message before onboarding attempts to cut keys that presents a message explaining importance of backing up keys and prompting the user asking if they understand the risks of not backing up keys
- made it so that passing `--cramkey` to the `onboard` command will skip the warning message inherently
- add a `--yes` | `-y` flag to the `onboard` command to skip this warning message
- Added proxy support for: `at_activate onboard --rootServer proxy:<host>:<port>`
- Added proxy support for: `at_activate enroll --rootServer proxy:<host>:<port>`
- feat: add `--root-server` option to specify root server domain
- feat: add `--license-key` alias for `--cramkey`
- chore(deps): at_commons: ^5.6.0
- chore(deps): args gkc/show-aliases-in-usage dependency override

## 1.12.0

- chore: fix lint warnings
- chore(deps): at_commons ^5.5.0
- chore(deps): at_client ^3.7.0
- chore(deps): chalkdart ">=2.0.9<4.0.0"

## 1.11.0

- feat: reuse the authenticated connection from AtAuth.authenticate when
  creating the AtClient which is handed back to the calling code.

## 1.10.1

- feat: remove unnecessary dependency on at_persistence_secondary_server

## 1.10.0

- feat: better user feedback during onboarding / enrollment / etc

## 1.9.0

- fix: have `onboard` only perform post-auth activation completion once the
  atKeys file has been successfully saved.

## 1.8.3

- fix: potential bug handling atSigns which end in `data` e.g. `@foo_data`

## 1.8.2

- fix: path resolution for temporary directory on Windows

## 1.8.1

- fix: Replace legacy IVs with random IVs for encrypting "defaultEncryptionPrivateKey" and "selfEncryptionKey" in APKAM flow
- build[deps]: upgrade at_persistence_secondary_server to v3.1.0

## 1.8.0

- feat: add `unrevoke` command to the activate CLI
- feat: add `delete` command to the activate CLI
- fix: When submitting an enrollment request, check for write permissions of AtKeys file path.
- build[deps]: upgrade: \
  at_auth to 2.0.9 | at_chops to 2.2.0 | at_client to 3.3.0 \
  at_commons to 5.0.2 | at_cli_commons to 1.2.1 | at_persistence_secondary_server to 3.0.65
- feat: Support password protection of atKeys file with a pass phrase

## 1.7.0

- feat: add `auto` command to the activate CLI

## 1.6.4

- build[deps]: upgrade: \
  at_client to 3.2.2 | at_commons to 5.0.0 | at_lookup to 3.0.49 | at_utils to 3.0.19 \
  at_persistence_secondary_server to 3.0.64 | at_auth to 2.0.7 | at_chops to 2.0.1 \
  at_server_status to 1.0.5

## 1.6.3

- fix: `.atKeys` filename was trimmed when filename has period('.') in it
- build[deps]: upgrade: \
    at_client to 3.2.1 | at_commons to 4.1.1 | at_lookup to 3.0.48 | at_utils to 3.0.18 \
    at_persistence_secondary_server to 3.0.63

## 1.6.2

- fix: `.atKeys` file was being generated in the wrong location in some cases

## 1.6.1

- feat: save enrollment details to local keystore
- build[deps]: upgrade at_auth to 2.0.5 | at_commons to 4.0.11

## 1.6.0

- feat: add 'status' command to the activate cli to check the status of an
  atSign

## 1.5.0

- feat: 'activate' CLI is now APKAM-aware, and supports
  - onboarding (as before)
  - submitting enrollment requests
  - listing / approving / denying / revoking enrollment requests
  - generating one-time passcodes
  - setting semi-permanent passcode

## 1.4.4

- feat: uptake changes for at_auth 2.0.0
- build[deps]: upgrade at_auth to 2.0.2 | at_lookup to 3.0.46 | at_client to 3.0.75 \
  at_commons to 4.0.5

## 1.4.3

- build[deps]: upgrade at_chops to 2.0.0 | at_lookup to 3.0.45 | at_client to 3.0.74

## 1.4.2

- build[deps]: upgrade: \
    at_commons to 4.0.0 | at_auth to 1.0.4 | at_chops to 1.0.7 | at_client to 3.0.73 \
    at_lookup to 3.0.44 | at_server_status to 1.0.4 | at_utils to 3.0.16

## 1.4.1

- feat: remove duplicate enrollment code and use at_auth
- chore: upgrade at_auth to 1.0.3, at_chops to 1.0.6, at_client to 3.0.69,at_lookup to 3.0.43

## 1.4.0

- feat: support for APKAM based authentication
- build: require at_client 3.0.65 or above
- build(deps): Upgrade at_client dependency to v3.0.67
- build(deps): Upgrade http dependency to v1.0.0

## 1.3.0

- feat: Introduced verification-code based activation of atsigns
- fix: deprecate qr_code based activation
- feat: introduced new exceptions
- fix: improve existing logger messages and added some
- fix: minor bug fixes

## 1.2.6

- feat: changes to integrate onboarding_cli with pkam secure element
- fix: issue with atKeys file creation while onboarding if the downloadPath directory does not exist
- fix: activate_cli throws exit(0) even though the process fails
- fix: onboarding_cli throws exception now when secondary address not found. Previously exit(1)

## 1.2.5

- feat: atkeys file now placed in standard location ~/.atsign/keys

## 1.2.4

- fix: Onboarding_cli throws exception when atsign does not start with '@'
- build: upgrade dependency at_utils to v3.0.12
- feat: Add atServiceFactory to AtOnboardingServiceImpl so that it can later be passed to AtClientManager.setCurrentAtSign

## 1.2.3

- Enable use of AtChops

## 1.2.2

- Minor reformatting of user logs and minor bugfixes
- Fixed issue with using executables
- activate_cli can now be used with a qr_code instead of cram secret
- Removed option to use staging env in register_cli
- Upgrade dependency at_client to latest version v3.0.49
- Upgrade dependency at_lookup to latest version v3.0.33
- Upgrade dependency at_commons to latest version v3.0.32

## 1.2.1

- Introducing register_cli that fetches a free atsign and registers it to provided email
- fix: check to ensure secondary is created before trying to activate it
- Introducing binaries from register_cli and activate_cli

## 1.1.2

- Introducing activate_cli, a simple tool to activate atSigns from command-line
- Introducing a close() method to safely close the OnboardingService object
- Allow custom names for .atKeysFile when the file name is passed as atKeysFilePath during onboarding(activating)
- Removed at_client dependency in onboarding process flow
- correct example link replace @sign -> atSign
- Upgrade dependency at_client to latest version v3.0.38
- Upgrade dependency at_lookup to latest version v3.0.30
- Upgrade dependency at_utils to latest version v3.0.11
- Upgrade dependency at_commons to latest version v3.0.24

## 1.1.1

- Method to check and format atsign.
- Upgrade dependency at_client to latest version v3.0.32

## 1.1.0

- Fixed encryption public key with malformed syntax being synced to local secondary.
- [Breaking Change] Migrating AtException to AtClientException.
- Code refactoring and adjusting AtLogger log levels to differentiate important logs.
- Enforcing Strict data typing on method params and return types.
- Upgrade dependency at_client to latest version v3.0.31
- Upgrade dependency at_lookup to latest version v3.0.28
- Upgrade dependency at_commons to latest version v3.0.21

## 1.0.0

- Initial version.
