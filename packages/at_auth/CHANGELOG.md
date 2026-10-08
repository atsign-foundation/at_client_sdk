## 4.0.0-rc5

- feat: `AtKeys.fileLink`, `linkFor` and `dropLink` hold a link signed for
  one of the keyfile's enrollments until it is published.
- feat: `RegistrarService.registerAtSign` (v4 `/register-atsign/`).
- feat: `RegistrarAdminService` for the v4 `/manage-atsigns/` delete flow
  (Super API key).
- refactor: `registrarApiRequest`'s `data` is now `Map<String, dynamic>`.
- BREAKING: removed `getFreeAtSign`, `getFreeAtSignByCategory`,
  `registerPerson` and `validatePerson`; use `registerAtSign`.

## 4.0.0-rc4

- fix: waiting for an enrollment's approval ends at once, with the atServer's
  reason, when the enrollment has expired or the atServer has no record of it
  (`AT0028`), instead of after the whole retry budget.

## 4.0.0-rc3

- fix: a keyfile lock left behind by a process that stopped mid-write is
  released within 5 seconds, instead of blocking every other writer for 30.

## 4.0.0-rc2

Logging in and managing enrollments moved to at_client (`Atsign.open`,
`Atsign.enroll` and `client.enrollments`); this release removes what they
replace.

- BREAKING: `AtAuth` and its request and response objects (`AtAuthRequest`,
  `AtAuthResponse`, `AuthRequest`, `AuthResponse`, `AtOnboardingRequest` and
  `AtOnboardingResponse`) are removed. Activate with `activateAtSign(...)`;
  log in with at_client's `Atsign.open`, or check credentials with
  `Atsign.authenticatesAs`. `RetryOptions` is still exported.
- BREAKING: `AtEnrollment` keeps `submit`, `approve` and `waitForApproval`.
  `deny`, `revoke`, `list`, `generateOtp` and `setSpp`, with `Otp` and
  `defaultOtpExpiry`, are at_client's `client.enrollments`; `update` and
  `EnrollmentUpdateRequest` are at_client's `EnrollmentUpdater`.
- BREAKING: `activateAtSign` requires `atLookUp` and
  `AtEnrollment.waitForApproval` requires `atLookup`, each an
  `AtLookupMuxable` it neither builds nor closes.
- BREAKING: `AtEnrollment.approve` requires `approverKeys`, an
  `ApproverKeyMaterial`; `approverChops` is removed, and `approve` no longer
  writes the APKAM symmetric key into the caller's `AtChops`.
- BREAKING: no caller names the enrollment to authenticate as: the keys decide,
  through `AtKeys.enrollmentToAuthenticateAs()`, and a retrofitted keyfile
  authenticates as its successor. A keyfile holding several live enrollments
  throws, naming them.
- BREAKING: `apkamSymmetricKeyResolver` on `AtEnrollmentRequest.pq` and
  `AtEnrollmentResponse` returns a `Stream<String>` rather than one key.
- BREAKING: a self-enrollment no longer approves its own request; a `pending`
  answer is denied and thrown.
- BREAKING: `AtAuthSession` no longer carries `atLookUp`.
- BREAKING: `httpsProbe`, `defaultProbe` and `secureSocketProbe` are removed;
  the check before an activation uses at_lookup's `checkAtSignServer`. at_auth
  no longer depends on at_server_status.
- BREAKING: `AtKeys.toAtChops` and `toAtChopsForEnrollment` are private; use
  `AtKeys.authenticationFor`, or `authenticationKeyPairFor`,
  `encryptionKeyPair` and `selfEncryptionKey` for the material itself.
- BREAKING: `AtKeys.copyWith` is removed; use `addKey`.
- BREAKING: `KeyIOMixin` is removed; read and write a `.atKeys` file with
  `FileAtKeysIo.read` and `write`, or use `AtKeysIo.passphraseCodec` for the
  passphrase envelope alone.
- BREAKING: the registrar's `ActivateApiEndpoint` and
  `RegistrarApiEndpoint.login`/`validate` are removed; use
  `RegistrarApiEndpoint.requestOtp`/`validateOtp`.
- feat: `activateAtSign(...)` activates an atSign with its CRAM secret and
  answers the new enrollment's id.
- feat: `CryptographicMaterialStatus.pending` marks an enrollment's keys between
  submission and approval, managed with `AtKeys.activatePending`,
  `discardEnrollment` and `pendingEnrollmentIds`.
- feat: `AtKeys.holdsAuthenticationMaterial`, `authenticationKeyPairFor`,
  `encryptionKeyPair` and `selfEncryptionKey`.
- feat: `AtKeys.fileLegacyMaterial`, `AtKeys.legacy`,
  `enrollmentSymmetricKey` and `storedEnrollmentId` reach a keyfile's flat
  legacy fields without the deprecated members.
- feat: `InMemoryAtKeysIo.holding(atSign, keys)`, an in-memory store already
  holding a key set.
- feat: the first time `FileAtKeysIo` writes typed keys into a flat keyfile, it
  keeps a `<keyfile>.pre-v1` copy.
- fix: a typed keyfile is written with `"keys": []` again, so an application on
  at_auth 3.3.0 can still read it.
- fix: an approval can fill legacy fields its submission left empty, and a
  keyfile emptied by a denial can take the next request.
- fix: a keyfile whose atSign keys are typed produces working encryption keys.
- fix: activation works with at_lookup's `close()`, which now ends a lookup.
- fix: `waitForApproval` with `logProgress` set no longer waits 500 ms before
  each attempt.
- fix: `AtKeys.metadata` is no longer deprecated.
- build: requires `at_lookup` ^3.7.0-rc2 and `at_commons` ^5.18.0.

## 4.0.0-rc1

A release candidate: adopt it deliberately. The headline is post-quantum
credentials, with an enrollment able to authenticate with ML-DSA-65 while
deployed peers still read what it advertises.

- BREAKING: `package:at_auth/at_auth.dart` no longer reaches `dart:io`.
  `FileAtKeysIo`, and anything else needing a filesystem, a socket or HTTP, is
  in `package:at_auth/at_auth_io.dart`.
- BREAKING: `AtEnrollmentRequest` requires `signingAlgo`.
- BREAKING: `AtOnboardingRequest.atKeysIo` no longer defaults to
  `FileAtKeysIo()`.
- BREAKING: `authenticatorForChops` requires `signingAlgo` and `hashingAlgo`.
- BREAKING: the `.atKeys` typed document groups keys by enrollment, role and
  algorithm. Legacy keyfiles, and those written by 3.3.0, still read.
- BREAKING: a keyfile's role, algorithm and status values are types, and
  `CryptographicMaterialStatus` and `KeyEntryStatus` read values a newer client
  writes rather than refusing them.
- BREAKING: `_apsk` advertises a list. One active `rsa2048` key is still the
  bare public key every deployed peer reads; anything else is a JSON array,
  which deployed peers cannot read.
- BREAKING: `AtKeys.authenticationAlgorithmFor` throws for an algorithm this
  build cannot sign with, rather than returning null.
- BREAKING: `AtOnboardingRequest.atKeys`, `AtAuthRequest.encryptedKeysMap` and
  `AtKeysIo.generateKeyPairs`'s `atSign` are removed; the other members marked
  for removal in v4 now say v5.
- feat: post-quantum self-retrofit: `AtSelfEnrollmentRequest` moves an
  enrollment to an ML-DSA-65 APKAM key, and `AtEnrollment.update` sends the
  `enroll:update` with the possession proof the atServer checks.
- feat: a CRAM activation can mint an ML-DSA-65 APKAM key from the start, and
  `mintLegacyMaterial` opts out of classical keys beside it.
- feat: an enrollment holds one signing key per algorithm and advertises them
  all at `_apsk`; a retired key stays advertised, so what it signed still
  verifies.
- feat: `AtAuthenticator`: at_lookup is handed an authenticator for a PKAM
  key, an `AtChops`, a CRAM secret or an enrollment, rather than credential
  fields.
- feat: `AtEnrollmentRequest.pq(...)` has the approver seal the symmetric key
  to the request's key package, so nothing RSA-wrapped rides the enrollment.
- feat: a keyfile holding several live enrollments is read, and
  `resolveAuthenticatingEnrollment()` lists them rather than choosing one.
- feat: a self-enrollment from an atSign that holds no enrollment approves
  itself over the connection that requested it.
- fix: two processes sharing a keyfile no longer lose each other's writes:
  `FileAtKeysIo` locks across processes, and `WrittenAtKeysIo.update` is one
  operation.
- fix: the `.atKeys` passphrase envelope uses a random salt and carries a
  version; files without one still open.
- fix: `FileAtKeysIo.update` no longer recreates a keyfile deleted while it
  ran, and throws `AtKeysSourceAbsentException`.
- fix: an OTP enrollment that advertises a signing key keeps its private half,
  so the next start no longer mints and advertises a second one.
- fix: `waitForApproval` stops on a refusal it cannot resolve, counts its
  retries as consecutive failures, and opens key records written without an
  `iv`.
- fix: an aborted self-retrofit denies the pending enrollment it created.
- build: requires `at_commons` ^5.16.0, `at_chops` ^3.6.0 and `at_lookup`
  ^3.7.0-rc1.

## 3.3.0
- feat: add `AtAuthSession` (exported) — the explicit auth→client hand-off artifact: the confirmed subset of an auth request that client creation actually needs (`atSign`, `rootDomain`, `namespace`, `atKeysIo`, `enrollmentId`), promoted to its own type so "request" no longer doubles as "session". Keys cross the boundary as an `AtKeysIo` *source*, not as live crypto state: the client derives its own `AtKeys` via `atKeysIo.read(atSign)` rather than adopting auth's `AtChops`/`AtLookUp`. The session also carries auth's already-authenticated `atLookUp` so a caller can *opt in* to reusing that connection (`AtClientManager.fromAuthSession(session, reuse: true)`) and skip a second PKAM handshake; the default hand-off rebuilds a fresh connection.
- feat: `AtAuthImpl.authenticate(...)` and `.onboard(...)` populate the new `AuthResponse.session` on success whenever the request supplied an `atKeysIo` — pass it straight to `AtClientManager.fromAuthSession(...)`. The legacy `atAuthKeys`-only path has no key source to hand across, so it gets no session and keeps behaving exactly as before.
- feat: `AtEnrollmentRequest` now takes a `session` (the requesting app's atSign, rootDomain and the `atKeysIo` its new keys will be persisted into) in place of the individual `atSign`/`rootDomain`/`apkamPublicKey`/`encryptedAPKAMSymmetricKey` params. On approval, `waitForApproval(...)` flushes the completed keyset into `session.atKeysIo` (when it is a `WrittenAtKeysIo`) and hands back a ready-to-use `AtEnrollmentResponse.session`. Supplying neither `session` nor the deprecated `atSign` throws `ArgumentError`. The legacy path (no session, or a read-only `AtKeysIo`) leaves `atAuthKeys` populated for the caller to persist and sets `session` to null.
- deprecation: everything the `AtAuthSession` hand-off replaces is marked `@Deprecated(... 'remove in v4')` and still fully functional in 3.3.0 — `AuthResponse` and its `AtAuthResponse`/`AtOnboardingResponse` subclasses, the `atAuthKeys`/`atLookUp`/`atChops` response fields, `AtEnrollmentResponse.atSign`/`.rootDomain`/`.atAuthKeys`, and the `AtEnrollmentRequest` params listed above. No runtime behaviour changed; this release is additive so consumers can migrate to `session` before at_auth 4.
- feat: add `AtKeysMaterial` — the only key type `AtKeys`'s API deals in (`addKey`, `getKey`, `keysForKeyId`, `keysForEnrollment`, `retireKey`, the `keysList` constructor param, ...). It's fully self-describing: `keyId`/`enrollmentId` plus `keyPartType` (an open `String` — the mechanical crypto role; known tokens in `CryptographicKeyType`: symmetric encryption/authentication and the public/private halves of encryption, verification/signing, encapsulation/decapsulation and key agreement), `keyAlgorithmType` (an open `String` — the algorithm family; known tokens in `KeyAlgorithmType`: `aes256`/`rsa2048`/`ecc_secp256r1`/`ed25519`/`x25519`/`mlkem768`/`mldsa65`/`xwing`, matching the pkam/enrollment `signingAlgo` literals), `bytes`, `operations`, `createdAt`, and `status` (`active`/`retired`/`dead`; `withStatus(...)` copies a material at a new status). Both token fields are deliberately Strings, not enums: unknown tokens are preserved and round-tripped, so a keyfile written by a newer client stays readable — and losslessly flushable — by an older one; whether an algorithm is classical, post-quantum or hybrid is carried by the algorithm token (e.g. `xwing`), not a separate role axis. The wire's nested `keys[].keyParts[]` document shape — grouping the materials sharing a `keyId` (e.g. the public+private halves of a keypair) — is produced/consumed by `encodeAtKeysDocument`/`parseAtKeysDocument` (also exported), not a separate model type. Keys produced by one enrollment are grouped by an optional `enrollmentId` and queried via `AtKeys.keysForEnrollment(...)`; at most one material of a given `CryptographicKeyType` may share an `enrollmentId`.
- feat: `AtKeys.toJson()`/`.fromJson(...)` now produce/consume the versioned typed-keys document shape (`version`, `atsign`, `keys`, with legacy fields flat at the top level — upgrading a legacy file to the typed-keys document is additive, not a format swap), replacing the former codec/resolver/document layer. Backward compatible: `fromJson` accepts json without a `version` field as the legacy flat shape, and throws `AtKeysUnsupportedVersionException` on an unknown version. Typed materials are looked up via `AtKeys.getKey(keyId, type)` and `.keysForKeyId(keyId)`.
- feat: add `WrittenAtKeysIo.flush(Atsign, AtKeys)` — the runtime persist operation: mutate the in-memory `AtKeys` (`addKey`, `retireKey`, ...), then flush the complete state. On an existing file, flush safety-checks the rewrite (`AtKeysAssurance.validateMapUpdate` — nothing may be lost: every existing `(keyId, keyPartType)` must survive with identical fields, though `status` may move forward `active` → `retired` → `dead` and new materials may be added), then rewrites; flushing a legacy `.atKeys` file upgrades it in place to the typed-keys document format (legacy fields preserved byte-for-byte). On a missing file, flush creates it. `write(...)` stays the create-only initial persist. (The `append`/`save` methods that existed briefly during this release's development are gone — never published.) `FileAtKeysIo` writes are atomic (write-to-temp + rename, so a crash can never truncate the keyfile) and a flush over an existing file first preserves it as `<file>.bak`.
- feat: `AtKeysAssurance` is now the single home for all atKeys validation — both the low-level `expect*`/`optional*` value/type checks used by `AtKeysMaterial.fromJson`/`AtKeys.fromJson`, and the structural invariants (`validateKeyMaterials`: duplicate `keyId`, one material of each `CryptographicKeyType` per enrollment, the flush-safety check `validateMapUpdate`).
- feat: add passphrase envelope support via `AtKeysPassphraseEnvelopeCodec` (`encode`/`decode`/`isEnvelope`, argon2id key derivation), and add `InMemoryAtKeysIo` for in-memory/test flows (both exported).
- fix: `AtKeys.==`/`hashCode` now also cover `atsign`, `metadata` (compared structurally — nested maps/lists by value, not identity) and the typed key materials (order-insensitive).
- chore(deps): require `at_chops` ^3.4.1 for hashing algorithm barrel exports used by AtKeys passphrase handling.
- fix: `RegistrarService` now fails loudly on a bad API key instead of reporting
  an ordinary negative result. The constructor throws `AtException` when `apiKey`
  is empty or whitespace-only, and every registrar call that requires
  authentication throws `AtException` naming the endpoint and status code when
  the registrar answers 401/403. Previously a rejected key surfaced as
  `sendActivationOtp()` returning `false` (or an empty atsign list), which is
  indistinguishable from a legitimate "no" — callers that treated a falsy result
  as an expected outcome will now see an exception (#1909).

## 3.2.0
- feat: bound `AtAuthImpl.validateAtServer` with a single overall deadline so a
  dead network can no longer hang authentication/onboarding. `RetryOptions` gains
  an optional `overallTimeout`; when null the default depends on the request:
  authentication uses `AtNetworkTimeouts.effectiveDefault` (30s) so a dead network
  fails fast, while ONBOARDING uses `AtNetworkTimeouts.defaultOnboardingTimeout`
  (5 min) because a newly-registered atSign can take minutes to be provisioned.
  The loop is deadline-driven — it retries every `retryDelay` until the budget is
  spent, then throws `AtTimeoutException`; each inner network call (the atDirectory
  lookup and the connectivity probe) is bounded by the remaining budget and capped
  at 60s. **`RetryOptions.maxRetries` no longer bounds this loop** (the deadline
  does) (#1923). Requires `at_commons ^5.13.0`.
- chore(deps): `at_lookup: ^3.6.0` — `validateAtServer` passes the `timeout`
  parameter that `SecondaryAddressFinder.findSecondary` gained in at_lookup
  3.6.0, so this version does not compile against at_lookup ≤3.5.x.

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
