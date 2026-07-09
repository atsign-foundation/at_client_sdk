## 3.2.0
- feat: add versioned AtKeys document serialization (codec/resolver/document layers) with validation for duplicate ids, malformed records, unsupported versions, and invalid protection references.
- feat: add typed key materials — `AtPublicKey`, `AtPrivateKey`, `AtSymmetricKey` (with `KeyProtection`) — exported from `at_auth.dart`. Keys produced by one enrollment are grouped by an optional `enrollmentId` and queried via `AtKeys.keysForEnrollment(...)`; the codec enforces at most one key of each kind per `enrollmentId`.
- feat: add passphrase envelope support using `argon2id`, and add `InMemoryAtKeysIo` for in-memory/test flows (both exported).
- feat: add `FileAtKeysIo.append(...)`, which safety-checks the rewrite (`AtKeysAssurance`) and archives the prior file before overwriting.
- refactor: move AtKeys IO implementations under `src/keys/io` (`FileAtKeysIo` stays exported).
- fix: preserve legacy `.atKeys` read/write behavior, including legacy self-encrypted key files and generated keys after write/read.
- chore(deps): require `at_chops` ^3.4.1 for hashing algorithm barrel exports used by AtKeys passphrase handling.

## 3.1.1
- refactor: route enrollment RSA (encrypt/decrypt `apkamSymmetricKey` under the default encryption keypair) through at_chops (`RsaEncryptionAlgo`) — `crypton` no longer imported in `lib` and moved to `dev_dependencies` (only the enrollment test still uses it for RSA keypair fixtures). Same framing, byte-identical by construction.
- fix: `decodeAtKeys()` now reliably throws `AtDecryptionException` on an incorrect passphrase. The `jsonDecode` of the decrypted bytes now runs inside the decrypt try/catch, so wrong-passphrase garbage no longer escapes as an uncaught `FormatException` (an intermittent failure in `at_keys_io_test`).

## 3.1.0
- feat: `validateAtServer()` now emits progress events and probes atSign connectivity before returning
- fix: `decodeAtKeys()` now throws when an invalid passphrase is provided
- fix: `FileAtKeysIO` now encrypts the key file with a passphrase when one is available
- fix: throws `AtAuthenticationException` when the atSign is already onboarded
- feat: use AtBytes.equals in `AtKeys` (requires at_commons: ^5.9.0)

## 3.0.1
- feat: improve `AtEnrollmentImpl`
- feat: introduce `NamespacePermission`
- fix: ensure directory when writing keys in FileAtKeysIo

## 3.0.0 

- chore(deps): at_chops ^3.0.0
- refactor: remove all singletons, injecting dependecies via `AuthRequest`
- feat: `AtKeysIo` interface which defines interaction between stored/generated keys and at_auth
- feat: `FileAtKeysIo` class which defines implementation
- feat: authentication returns `AtLookup` and `AtChops` via `AuthResponse`
- feat: `AtAuth` exposes a `ProgressStream` to consume status of at_auth

## 2.4.0

- chore(deps): at_commons ^5.5.0

## 2.3.0
- feat: add `AtLookUp? atLookUp` to the `AtAuth` interface so that it can be 
  reused (e.g. by AtClient) once auth is complete

## 2.2.0

- feat: enable callers of `AtAuth.onboard` to control post-auth activation
  completion (set the encryption public key on the server, delete the "cram"
  secret)

## 2.1.0
- fix: potential bug handling atSigns which end in `data` e.g. `@foo_data`

## 2.0.10
- fix: Replace legacy IVs with random IVs for encrypting "defaultEncryptionPrivateKey" and "selfEncryptionKey" in APKAM flow
## 2.0.9
- fix:Enable caching of encryption public key
## 2.0.8
- feat: Add "passPhrase" in "AtAuthRequest" to support password protected atKeys file
- build[deps]: Upgraded the following packages:
  - at_commons to v5.0.2
  - at_auth to v2.2.0
  - lints to v5.0.0
  - test to v1.25.8
  - mocktail to v1.0.4
## 2.0.7
- build[deps]: Upgraded the following packages:
  - at_commons to v5.0.0
  - at_lookup to v3.0.49
  - at_utils to v3.0.19
  - at_chops to v2.0.1
## 2.0.6
- fix: Add "apkamKeysExpiryDuration" to "EnrollmentRequest" to support auto expiry of APKAM keys
## 2.0.5
- fix: set atChops in atLookup before pkam auth in AtAuthImpl
- build[deps]: Upgraded the following packages:
  - at_commons to 4.0.11
  - at_lookup to 3.0.47
- feat: Add signing SigningAlgoType and HashingAlgoType in AtAuthRequest, AtOnboardingRequest
## 2.0.4
- fix: Add "revoke" to the "AtEnrollmentBase" to support enroll:revoke operation
## 2.0.3
- fix: Add optional parameters to the "atAuth" method in "AtAuthInterface"
## 2.0.2
- fix: set default value for app name and device name if they are not passed in the onboarding request.
## 2.0.1
- fix: deprecate enableEnrollment flag in OnboardingRequest and removed the check in AtAuthImpl
## 2.0.0
- build[deps]: Upgraded the following packages:
  - at_commons to 4.0.5
  - at_lookup to 3.0.46
- Implement new methods for enrollment operations within AtEnrollmentImpl and remove older methods.
- Enhance readability by renaming the current classes associated with EnrollmentRequest.

## 1.0.5
- build[deps]: Upgraded the following packages:
  - at_chops to v2.0.0
  - at_lookup to v3.0.45
## 1.0.4
- build[deps]: Upgraded the following packages:
    - at_commons to v4.0.0
    - at_utils to v3.0.16
    - at_chops to v1.0.7
    - at_lookup to v3.0.44
## 1.0.3
- fix: upgrade at_lookup to 3.0.43 since 3.0.42 has breaking change for private key reference
## 1.0.2
- feat: enrollment common code from at_client_mobile and at_onboarding_cli
- chore: upgrade at_lookup to 3.0.42 and at_demo_data to 1.0.3
## 1.0.1
- feat: Introduce "submitEnrollment" and "manageEnrollment" methods for APKAM
## 1.0.0
- Implemented onboard and authenticate methods.
