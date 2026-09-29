## 2.0.0-rc2

- **FEAT**: at_activate interactive now has `exit` and `quit`
- **FIX**: better string parsing in at_activate interactive

## 2.0.0-rc1

- **BREAKING:** `AtOnboardingService` keeps `AtOnboardingServiceImpl(atSign,
  preference)`, `authenticate()` and `atClient`; what else it orchestrated is
  at_client's. `onboard` is `Atsign.activate`; `enroll`, `sendEnrollRequest`,
  `awaitApproval` and `createAtKeysFile` are `Atsign.enroll`,
  `Atsign.resumeEnrollment` and `PendingEnrollment.client`; `close` is
  `atClient.stop()`. `completeActivation`, `getAtClient`, `isOnboarded`,
  `getAtLookup`, `atLookUp`, `atChops` and `atAuth` are removed.
- **BREAKING:** `authenticate()` takes no `enrollmentId`: it authenticates as
  the keyfile's own enrollment. It opens the client through `Atsign.open`,
  stopping any client already live for the atSign, and answers true only when
  the connection is online; an offline client is still held and its
  `connection` says why. It no longer copies the keyfile's keys into local
  storage.
- **BREAKING:** `at_activate` needs a command. `at_activate -a @alice -c
  <secret>` is no longer treated as `onboard`; it prints the command list and
  exits 1. The deprecated `lib/src/activate_cli/activate_cli.dart` is removed;
  the `at_activate` binary is unaffected.
- **BREAKING:** the `*.enrollment.checkpoint` file is gone. The keyfile named
  on `enroll` holds the pending keys, and running `at_activate enroll` again
  for the same app and device resumes the wait for approval.
- feat: `--posture legacy|pqReady|pqActive` on every command; unset, each runs
  at at_client's default posture, which `onboard` and `enroll` announce.
  `enroll --key-exchange legacy|pq` chooses how the enrollment's key travels.
- feat: `AtOnboardingPreference(posture: ..., authenticationKeyAlgorithm: ...,
  dataSigningKeyAlgorithms: ...)`. `storage`, `storagePath` and
  `storageFor(atSign)` choose the client's local storage, replacing
  `hiveStoragePath`; `lookUps` and `proxyLookUps()` choose its transport.
- feat: `createAtClient` opens the client through `Atsign.open`, waits for it
  to come online for up to `maxConnectAttempts` tries three seconds apart, and
  with `waitForPqStartup` (default true) waits for its post-quantum startup.
- **Compatibility, passphrase-protected keyfiles only:** the `.atKeys` file is
  written by at_auth's `FileAtKeysIo`, and a passphrase now uses at_auth's
  version 1 envelope, whose AES key comes from a random per-file salt. at_auth
  reads both versions, but older tooling cannot read version 1.
  `AtOnboardingPreference.hashingAlgoType` no longer affects the file, and
  `--hashingAlgoType` is ignored and hidden from help: it had been setting the
  PKAM hash of the client `onboard` and `enroll` build, which an RSA-2048 key
  refuses for argon2id.
- fix: `--version` reports the package's actual version, and the enrollment
  commands say what was done rather than echoing the atServer's response.
- build: requires `at_client` ^3.15.0-rc1, `at_auth` ^4.0.0-rc2 and
  `at_lookup` ^3.7.0-rc2. `at_server_status` is no longer a dependency.

## 1.16.1-rc1
- fix: pass passPhrase to FileAtKeysIo during onboarding so password-protected atKeys files are written correctly

## 1.16.0
- refactor: route enrollment crypto — `sha256` hashing, AES key generation and RSA keypair generation — through at_chops (`SHA256HashingAlgo`, `AtChopsUtil.generateSymmetricKey`, `AtChopsUtil.generateAtEncryptionKeyPair`). `crypto`, `encrypt` and `crypton` are no longer imported anywhere in the package and have been dropped from `dependencies`. Byte-identical by construction.
- feat: enrollment authorization wait can now be resumed across sessions
- feat: atKeys files are now restricted to read/write permissions for the current user only
- feat: atKeys file writability is verified before enrollment or onboarding begins
- feat: activate_cli: new `decrypt` command outputs a passphrase-decrypted version of the atKeys file
- feat: activate_cli: version is now shown via `--version`, `--help`, and `help`
- fix: at_onboarding_cli now subscribes to at_auth progress stream events
- chore(deps): `at_auth: ^3.2.0`, `at_lookup: ^3.6.0` — onboarding/auth network
  waits are time-bounded (deadline-driven `validateAtServer`, bounded
  atDirectory lookups) only with these versions resolved.

## 1.15.0

- feat: add `--root-server` option to specify root server domain
- feat: add `--license-key` alias for `--cramkey`
- chore(deps): at_commons: ^5.6.0
- chore(deps): args gkc/show-aliases-in-usage dependency override
- chore(deps): at_auth ^3.0.0
- chore(deps): at_chops ^3.0.0

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
