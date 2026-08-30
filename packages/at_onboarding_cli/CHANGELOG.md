## 1.17.0-rc1

- **Behaviour change, from `at_client` rather than from this package.**
  `authenticate()` builds an `AtClient`, and a client at a post-quantum posture
  now gives an atSign that holds no enrollment its first one — rewriting the
  `.atKeys` file. `AtOnboardingPreference` inherits `AtClientPreference`'s
  `PqPosture.pqReady` default, so this happens unless a caller names
  `PqPosture.legacy`. Every `at_activate` command that authenticates is
  affected.

- fix: **an enrolment now owns a data signing key from birth.**
  `sendEnrollRequest` advertised the APKAM authentication key in `_apsk` and
  signed the key package with it, so the new client's first start minted a
  signing key and republished — dropping the APKAM entry. The key package then
  stopped verifying, and any signing link the approver had conveyed against that
  exact advertised value stopped matching, so the enrolment was approved and
  then sealed nothing.
  - The keypair is minted under the algorithm the posture's
    `dataSigningKeyAlgorithms` names and passed to the request **and** to the
    key-package builder, so the record names the key that signed the package.
  - A **legacy-mode** enrolment under a posture that names a signing algorithm
    advertises one too, and still carries no key package: the mode decides
    whether a package exists, while `_apsk` is what every peer verifies
    signatures against whatever the mode.

- fix: a client that retrofits its enrolment at startup can run authenticated
  verbs again. `at_activate list` on a keyfile that had been retrofitted printed
  "Connected" and then failed the verb, and it failed on every run — the
  retrofit deliberately leaves the keyfile's own `enrollmentId` at the capped
  legacy enrolment, so it is due again at each start.
  - `_initAtClient` stamped three things on the client's lookup and took them
    from two places: the enrolment id and the signing algorithm from the client,
    which had moved to the new enrolment, and the **signer** from the caller,
    which at_auth had built for the old one. The lookup then declared
    `mldsa65` over an RSA-2048 keypair.
  - `authenticatorFor` could not reconcile them, which is what made it silent:
    given an injected signer it takes only the *algorithm* from the keyfile, so
    both halves are read from one file for one enrolment id and still disagree.
    at_chops refuses the pair outright.
  - The signer is now resolved beside the id and the algorithm, from whichever
    source that flow trusts — the client when authenticating, the caller when
    enrolling, where the APKAM keypair was minted moments earlier and no keyfile
    holds it yet. `AtLookUp.atChops` stays the caller's on both: that field is
    what at_auth's `EnrollmentApprover` reads for enrollment crypto, which is
    not authentication.
  - Authentication itself was never broken, which is why nothing caught this:
    at_auth authenticates on its own connection, before the client exists.

- fix: an enrolment now travels its key under the posture's key-exchange mode,
  and can be told otherwise. This is the second half of the same defect as the
  entry below: `--posture` reached the preference and the authentication key
  and stopped, so `sendEnrollRequest` went on building the **unnamed**
  `AtEnrollmentRequest(...)`, whose initialiser hard-sets
  `EnrollmentKeyExchangeMode.legacy`. `at_activate enroll --posture pqActive`
  therefore submitted a legacy request, the enrolment advertised **no key
  package**, and nothing said so.
  - `enroll` and `sendEnrollRequest` take a `keyExchangeMode`. Nullable, and
    null means "whatever this service's posture implies" — resolved exactly as
    `signingAlgo` is, against the same preference.
  - The mode is not a settable field, deliberately: the constructor decides it,
    so a mode and the callbacks it requires cannot be chosen separately. The
    service picks between `AtEnrollmentRequest` and `AtEnrollmentRequest.pq`
    instead, supplying `enrollmentKeyPackageBuilder` and
    `enrollmentApkamSymmetricKeyResolver` on the pq branch.
  - ⚠️ **This changes the default.** `PqPosture.pqReady` is the SDK default and
    its key-exchange mode is `pq`, so an `at_activate enroll` naming no
    `--posture` now submits a pq request. A pq request carries no RSA-wrapped
    key and relies on the approver sealing one to the advertised key package —
    against an approver that predates conveyance the enrolment is approved and
    then cannot decrypt anything, where before it silently degraded to legacy.
  - So `enroll` gains **`--key-exchange legacy|pq`**, on that command alone. It
    exists for the half a posture cannot see: which approver will pick the
    request up. Unset means the posture decides.

- fix: `at_activate enroll --posture pqActive` now enrols under the posture's
  authentication algorithm. `--posture` is on the shared arg parser, so
  `enroll` has always accepted it — and it reached the client's preference and
  nothing else, so the enrolment still minted RSA-2048 and the client
  retrofitted it away on its first start.
  - `enroll` and `sendEnrollRequest` take a `signingAlgo`. It is **nullable**,
    and null means "the position this service was built at" — the preference's
    `authenticationKeyAlgorithm`, which is the same field `authenticate()`
    stamps on the connection. ⚠️ It defaulted to `rsa2048` at that boundary,
    on the argument that an app calling `enroll` knows its appName and
    namespaces rather than the atSign's rollout position. That made **two
    defaults for one fact**, and they agreed only while the shipped posture
    also meant RSA: once it became `pqReady`, the enrolment minted an RSA-2048
    APKAM keypair while `authenticate()` declared ML-DSA-65 for it, and
    at_chops refused the pair by size. `auth_cli`'s own
    `?? SigningAlgoType.rsa2048` went with it, for the same reason — the
    preference it sits beside is built from the same `--posture`.
  - `enroll` forwards it to `sendEnrollRequest`, which it did not, so the
    parameter would have existed and done nothing.

- fix: an enrolment checkpoint can hold **typed** key material. `enroll` saves
  one so an interrupted enrolment resumes, and `AtKeys.toJson` refuses a
  document carrying enrollments or atSign keys with no `atsign` — so
  `at_activate enroll --posture pqActive` threw `atsign is required to
  serialize typed atKeys material` and could not checkpoint at all. Unnoticed
  because the only post-quantum enrolment test drives `sendEnrollRequest`,
  which never reaches a checkpoint.
  - ⚠️ **The checkpoint now records which atSign it belongs to**, where it
    deliberately removed that. The property is not compatible with typed
    material, and it was thin: the file already holds the enrollment's own
    APKAM private key material at chmod 600.

- refactor: follows at_auth's barrel split — `FileAtKeysIo` now comes from
  `package:at_auth/at_auth_io.dart`. No API change here.
- fix: `auth_cli` assigns `retrofitSerializer = fileRetrofitSerializer` at
  startup, so a retrofit still takes a lock beside the keyfile. at_auth no
  longer decides that for itself — only a caller knows its keys are on disk —
  and without this two CLIs pointed at one keyfile could each read the
  pre-retrofit state and write a different enrollment into it.

- refactor: the five lookups this service built, which differed only in
  formatting, come from one `_newLookUp()` helper over
  `AtLookUp.withSecureSocket`. `close()` no longer casts to at_lookup's
  implementation class to ask whether a connection is open; it tests for
  `AtLookupMuxable`, which also stops it throwing when a test injects a plain
  `AtLookUp`.
- fix: authentication reads a password-protected keyfile again. The
  authenticator's key source omitted the passphrase, so every authenticated
  command against a protected `.atKeys` failed with "Pass Phrase is required"
  - a long way from where the omission was. The construction was copied
  faithfully from the onboarding path, where it is right because onboarding
  writes; reading needs the passphrase, as the same file's other source
  already did. Caught by the new functional runner, not by the 54 unit tests.

- feat: installs an `AtAuthenticator` on its lookup, so authentication reads
  the keyfile rather than credentials parked on at_lookup. Where the keys live
  now has one definition, `_keysIo()`, used both when onboarding hands a source
  to at_auth and when authentication needs one.
- **BREAKING** feat: `--posture legacy|pqReady|pqActive` on **every** command,
  replacing `--signingAlgoType`, which is removed.
  - It named the PKAM *authentication* key while reading like the data signing
    key, and it silently did nothing on every command but `onboard`
    ([#2161](https://github.com/atsign-foundation/at_client_sdk/issues/2161)) —
    which is why the replacement is honoured everywhere rather than at
    activation alone. A posture means the same thing wherever a client is
    created.
  - It has no default. An unnamed `--posture` leaves whatever the at_client
    this was built against defaults to, so the binary is not pinned to the
    stage that was current on the day it was compiled.
  - Reaching every command means two routes, not one: `onboard` and `enroll`
    read it through `createOnboardingService`, everything else through
    `createAtClient`, which gains an optional `posture` — it is exported, so
    apps that already call it are unaffected. Both go through
    `AuthCliArgs.preferenceUnder`, which is the single place that decides what
    an unnamed posture means — it names no posture itself, which is the point,
    so the argument map stays the only code in the package that names a
    `PqPosture` constant at all.
  - **A parser that accepts an argument is not a client that runs under it.**
    For a day this reached every parser while only the two onboarding-service
    commands read the value, which is the same silent no-op `--signingAlgoType`
    was retired for. The tests now check the argument reaches a client, not
    only a parser.
  - Activation reads `AtClientPreference.authenticationKeyAlgorithm` — the
    posture's axis — rather than the deprecated `signingAlgoType`. Every
    activation the old argument could express is expressible as a posture, and
    an app needing a combination none of the three offers builds its own
    `PqPosture`.
- feat: `AtOnboardingPreference` takes the flags `AtClientPreference` fixes at
  construction — `posture`, `disallowLegacyEncryption`,
  `authenticationKeyAlgorithm` and
  `dataSigningKeyAlgorithms`. It declared no constructor, and those fields are
  final in the superclass, so a CLI application could neither pass them nor
  assign them afterwards: the whole fleet ran on the defaults with no way off
  them, `at_cli_commons` consumers included. Every parameter is optional and
  the superclass supplies each default, so `AtOnboardingPreference()` is
  unchanged. Naming `dataSigningKeyAlgorithms` needs `SigningAlgoType`, which
  at_client does not export — import it from at_chops.
- fix: an authenticated client keeps the PKAM algorithm it resolved from its
  keyfile. `_initAtClient` serves two flows through one method. Enrolment hands
  it a lookup this service built for an APKAM keypair minted moments earlier,
  with no keyfile yet to resolve from, so the preference is the only source
  there is. Authentication hands it nothing, so it adopts the client's own
  lookup — and that client has already read the keyfile. The preference was
  stamped over both, and `at_activate otp`, `list` and `spp` build their client
  through `createAtClient`, which names no posture: on a PQ-native atSign the
  stamp claimed `rsa2048` for an ML-DSA enrollment and the next connection
  signed the challenge with the RSA routine
  ([#2161](https://github.com/atsign-foundation/at_client_sdk/issues/2161)).
  Key material now wins for a lookup adopted from the client, and the
  preference still decides for one this service built.
- fix: `authenticate()` hands its key source to the AtClient it creates. It
  built a `FileAtKeysIo` for `AtAuth` and then created the client without one,
  so every consumer — including everything built on `at_cli_commons` — got a
  client with no key-material source at all: it could not resolve its PKAM
  algorithm from the keyfile, file conveyed private keys, or reach an
  enrollment's typed material. The client still authenticates with the AtChops
  auth hands over; the source is what it keeps for everything that AtChops
  cannot answer.
- docs: `auth enroll --max-retries` and `AtOnboardingService.awaitApproval`
  both described a give-up that does not exist. Waiting for an approval
  decision is unbounded — somebody has to decide the request, on their own
  schedule — and the option budgets consecutive failures to reach the
  atServer instead. `auth onboard --max-retries` is unchanged and its help
  was already accurate: that one feeds a `RetryOptions` on the activation
  check, which really is a bounded retry.
- refactor: the `.atKeys` file is written by at_auth's `FileAtKeysIo` — the
  same store `authenticate()` has always read it back through — instead of
  being assembled here. The legacy fields keep their names and their exact
  self-encrypted bytes, and the atSign-keyed copy of the self-encryption key
  that every keyfile carries is preserved; the document gains the typed-keys
  `version`/`atsign`/`keys` fields, which is what lets a keyfile hold
  post-quantum key material at all. `allowOverwrite: true` now replaces the
  file explicitly, since the store's `write` is create-only by contract.
- **Compatibility, passphrase-protected keyfiles only:** a keyfile written
  with `AtOnboardingPreference.passPhrase` set now uses at_auth's version 1
  envelope, which derives its AES key from a random per-file salt. The
  previous envelope used the passphrase itself as the salt, so two users who
  chose the same passphrase derived the same key. at_auth reads both, but
  **older tooling cannot read a version 1 envelope** — keep an older
  `.atKeys` file if you need to open it with an older client.
  `AtOnboardingPreference.hashingAlgoType` no longer affects the written
  file: version 1 is argon2id.
- refactor: `awaitApproval` delegates the approval handshake —
  PKAM-until-approved, then fetching and decrypting the encryption private
  key and self-encryption key — to at_auth's `waitForApproval`, deleting
  this package's ~170-line copy of it. The checkpoint-resumed response gets
  its atSign and root domain restored before the handshake runs (the
  checkpoint file deliberately strips the atSign), and at_auth's progress
  events are forwarded to this service's subscribers for the duration.
  The `at_auth` constraint floor rises to `^3.4.0` in the same change: the
  delegation depends on that version's legacy-IV fix and on `atLookup` being
  on the `AtEnrollment` interface, and workspace resolution would otherwise
  hide a stale floor from a consumer.
- feat: `onboard` can activate an atSign **post-quantum**. Pass
  `--signingAlgoType mldsa65` (or set `AtOnboardingPreference.signingAlgoType`)
  and the activation mints an ML-DSA-65 APKAM, advertises the first
  enrollment's key package on the `enroll:request` that creates the record, and
  creates the atSign-level signing root — all three, because an ML-DSA APKAM
  without a key package produces an atSign that can never be repaired. Matched
  on `mldsa65` exactly, so the existing `ecc_secp256r1` option is unaffected.
  The signing root is minted after activation and does not fail the onboard: by
  then the CRAM secret is spent, and a later start retries it.
- fix: `authenticate` no longer throws `Null check operator used on a null
  value` on a post-quantum keyfile. The local-secondary key back-up
  dereferenced the flat `apkamPublicKey`/`apkamPrivateKey` fields, which a PQ
  enrollment deliberately leaves empty (its APKAM is typed material under the
  enrollment id), and which an atSign activated without legacy material lacks
  entirely. It now persists whatever the keyfile actually holds.
- fix: `--version` reports the package's actual version. `lib/src/version.dart`
  is generated from the pubspec by `build_version` and had not been regenerated
  since 1.15.0, so the published 1.16.0 CLI reported `1.15.0`.
- **BREAKING** chore: removed `lib/src/activate_cli/activate_cli.dart`, whose
  `main`, `wrappedMain` and `activate` were all `@Deprecated('Use auth_cli')`.
  The `at_activate` binary has routed to `auth_cli` for several releases and is
  unaffected; nothing in this package imported the library.
  - Marked breaking because the file was reachable, if only by importing
    `package:at_onboarding_cli/src/…` directly — a path Dart convention marks
    as private, and one at least one downstream program does use. If you are
    that program, call the shipped `at_activate` binary rather than
    re-implementing its `main`; there is no supported library entry point for
    activation, and there was not one before.

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
