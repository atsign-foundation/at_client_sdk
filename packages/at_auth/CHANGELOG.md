## 4.0.0-rc1

A release candidate: adopt it deliberately. The headline is post-quantum
credentials — an enrollment can authenticate with ML-DSA-65 while the fleet
still reads what it advertises.

### Breaking

- **Two barrels.** `package:at_auth/at_auth.dart` no longer reaches `dart:io`;
  anything needing a filesystem, a raw socket or the `dart:io` HTTP stack is
  exported from `package:at_auth/at_auth_io.dart`. Nothing left the package —
  `FileAtKeysIo` is still at_auth's — so a `dart:io` consumer adds one import.
- **`AtOnboardingRequest.atKeysIo` no longer defaults to `FileAtKeysIo()`.**
  Onboarding must persist what it mints and the core cannot assume a
  filesystem, so it throws naming what to set.
- **`AtEnrollmentRequest` requires `signingAlgo`** on both constructors. An app
  enrolling over OTP always got RSA-2048 and could not ask otherwise, so on an
  atSign whose deployment had moved to post-quantum every install created an
  RSA-authenticating enrollment the client then retrofitted away. Required
  rather than defaulted, so each call site states what it means.
- **The `.atKeys` typed document groups by enrollment.** Key material is
  addressed by enrollment, role and algorithm rather than by the flat
  `apkamPublicKey`/`apkamPrivateKey` fields. Legacy keyfiles still read, and a
  keyfile written by 3.3.0 is read rather than refused. The flat fields stay
  where a retrofit left them: they carry the capped legacy enrollment's RSA
  credentials while the typed section carries the live one's.
- **The keyfile's String vocabularies become types** — material role, algorithm
  and status. `CryptographicMaterialStatus` and `KeyEntryStatus` are open
  vocabularies rather than enums, so a value a newer client writes is read
  rather than refused.
- **`_apsk` advertises a list.** One active `rsa2048` key still spells as the
  bare public-key string every deployed peer can parse; a second key, or a
  non-rsa2048 one, spells as a JSON array, which a deployed peer cannot. That
  asymmetry is the rollout's mechanism, not an implementation detail.
- **Three "remove in v4" members are gone**: `AtOnboardingRequest.atKeys`
  (which never worked — `onboard()` overwrote it before anything read it),
  `AtAuthRequest.encryptedKeysMap`, and `AtKeysIo.generateKeyPairs`'s ignored
  `atSign`. Everything else that said "remove in v4" now says v5.
- **Dependency floors** raised to `at_commons ^5.16.0`, `at_chops ^3.6.0`,
  `at_lookup ^3.7.0-rc1`.

### New

- **PQ self-retrofit.** `AtSelfEnrollmentRequest` moves an existing enrollment
  to an ML-DSA-65 APKAM key; `AtEnrollment.update` is the `enroll:update`
  caller, with the possession proof the atServer verifies.
- **PQ-native activation.** A CRAM onboard can mint an ML-DSA-65 APKAM key
  from the start, and `mintLegacyMaterial` is an opt-out for a deployment that
  no longer wants classical material beside it.
- **Enrollments own signing keys.** An enrollment holds one signing key per
  algorithm, advertises every one it holds at `_apsk`, and retiring a key
  withdraws it from use while leaving it advertised — so everything it signed
  still verifies.
- **An authenticator seam.** at_lookup is handed an `AtAuthenticator` rather
  than loose credential fields, so which credential shape authenticates a
  connection is decided once, where the keys are. Four shapes: PKAM private
  key, `AtChops`, CRAM secret, and enrollment-derived.
- **pq-mode enrollment.** `AtEnrollmentRequest.pq(...)` has the approver mint
  the symmetric key and seal it to the key package the request advertises, so
  nothing RSA-wrapped rides the enrollment.
- **A keyfile holding several live enrollments is read**, and only a writer
  refuses to create one. `resolveAuthenticatingEnrollment()` offers the
  candidates and throws rather than choosing between them.

### Durability and correctness

- `FileAtKeysIo` takes an inter-process advisory lock, and
  `WrittenAtKeysIo.update` makes read-mutate-write one operation, so two
  processes sharing a keyfile cannot lose each other's writes.
- The `.atKeys` passphrase envelope derives its AES key from a random salt and
  carries a version. **Compatibility:** envelopes without a `v` field keep the
  old derivation, so existing files still open.
- `waitForApproval` stops polling on a refusal it cannot resolve, counts its
  retry budget as consecutive failures, and opens key records written without
  an `iv`.
- An aborted self-retrofit denies the pending enrollment it created.
- **`FileAtKeysIo.update` no longer recreates a keyfile deleted while the
  update was in flight**, and throws `AtKeysSourceAbsentException` instead.
  `update` is a read-modify-write of material that must already be there —
  its own read throws when the file is absent at the start — so writing a
  file that is absent at the end contradicted the call it began. Deleting a
  `.atKeys` file is how a device is decommissioned, and a background task
  mid-update would silently put it back. `flush` is unchanged and still
  creates the file, which is its job.
- **An OTP enrolment that advertises a signing key now files its private half.**
  `AtEnrollmentRequest.advertisedSigningKey` reached the `_apsk` advertisement
  but never the keyfile, so the enrolment published a key it did not hold: the
  next start found the in-use algorithm missing, minted a second keypair and
  republished, orphaning the advertised key and unverifying anything signed
  against it. The self-enrolment and first-enrolment paths already filed it;
  this was the third.

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
