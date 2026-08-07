## 4.0.0

### Breaking

- **The whole `AtKeysIo` surface takes `Atsign`, not `String`.** `read`, `write`
  and `WrittenAtKeysIo.flush` all take a normalized `Atsign`, and
  `FileAtKeysIo.filePath` is now `String Function(Atsign)`. Previously `read`
  took `Atsign` while `write` took `String`, and because `Atsign` is a subtype
  of `String` the analyzer could never flag the drift.
- **`write` moved from `WrittenAtKeysIo`/`InMemoryAtKeysIo` up to `AtKeysIo`.** A
  caller holding a plain `AtKeysIo` can now persist a fresh keyset without
  switching on the subtype (`AtAuthImpl.onboard` had a `switch` with two
  identical branches). The tradeoff is explicit: there is no read-only
  implementation. `flush` stays on `WrittenAtKeysIo`; `append`/`retire`/
  `dispose` stay on `InMemoryAtKeysIo`.
- **`appName`/`deviceName` are named parameters on `AtAuth.onboard`** (same
  `'firstApp'`/`'firstDevice'` defaults, now applied by
  `AtEnrollment.firstEnrollment`) instead of mutable fields on a request object
  settable only by cascade after construction.
- **`enrollmentId` is a structural field of the typed-keys document**, alongside
  `version`/`atsign`/`keys` — read and written explicitly rather than carried in
  the legacy flat payload. The on-disk bytes are unchanged; what changes is that
  a keyfile field named `enrollmentId` (or `version`/`atsign`/`keys`) is never
  captured into `AtKeys.metadata`. `KeyIds.reservedTopLevelKeys` and
  `KeyIds.isMetadata` are the single source of truth for that split, replacing
  two divergent private copies. `flush` now permits an `enrollmentId` to be set
  once (`null` → value, which is what enrollment approval does) but rejects
  repointing an existing one at a different enrollment.

#### Direct parameters and void returns replace the request/response/session types

Onboarding and authentication no longer traffic in objects. Every `AtAuth` and
`AtEnrollment` entry point takes the atsign, its atServer and the key source
directly, and `AtAuth`'s four methods return `void`: **completing without
throwing is the success signal**, and failure throws
`AtAuthenticationException`.

- **`AtAuthRequest`, `AtOnboardingRequest`, `AuthRequest` and `AtAuthSession` are
  gone.** The signatures are now
  `authenticate(Atsign, AtRootDomain, AtKeysIo, {enrollmentId})`,
  `onboard(Atsign, AtRootDomain, AtKeysIo, cramSecret, {autoCompleteActivation,
  appName, deviceName})`, `completeActivation(Atsign, AtRootDomain, AtKeysIo)`
  and `validateAtServer(Atsign, AtRootDomain, {onboarding})`. `RetryOptions`
  moves from the request to `AtAuth.create({options})`. The request types'
  `namespace`, `signingAlgoType` and `hashingAlgoType` fields had no consumer and
  are gone with no replacement.
- **`AtAuth` builds its own `AtLookUp`; `AtAuth.create` no longer takes one.**
  at_lookup 4.0.0 binds its PKAM key and signing algorithm at construction and
  keeps them immutable, so the connection cannot exist until the keys have been
  read or minted — which means authentication has to own that step. An
  activation needs a second connection besides, signing with a key that did not
  exist when the first was built. `atEnrollmentBase:` likewise becomes
  `enrollmentFactory:`.
- **`atLookUpFactory:` on `AtAuth.create` and `AtEnrollment.create` takes over
  that construction.** A single `AtLookUpFactory` —
  `AtLookUp Function(Atsign, AtRootDomain, AtKeys?, {String? enrollmentId})` —
  builds every connection at_auth authenticates on, so substituting it
  substitutes all of them. Left null it defaults to
  `AtAuthScheme.lookUpFactory`, which is `buildAtLookUp` curried with the
  chosen scheme. A connection the factory returns belongs to at_auth, which closes it
  when the operation fails or finishes with it.

  This replaces the `AtAuthImpl.lookUpOverride` and
  `AtEnrollmentImpl.lookUpOverride` `@visibleForTesting` fields, both removed.
- **The at_auth scheme is a constructor option, not something inferred
  from key material.** `AtAuth.create({AtAuthScheme scheme})` and
  `AtEnrollment.create(atLookUp, {scheme})`, defaulting to
  `AtAuthScheme.legacy` (RSA-2048/SHA-256, `AtLookUp.legacy`);
  `AtAuthScheme.postQuantum` selects ML-DSA-65 (`AtLookUp.pq`).
  `AtKeys.generate` mints both a classical and a post-quantum APKAM key, so the
  material cannot express which one an atServer expects — that is a property of the deployment,
  and the application owns it. A keyset that cannot satisfy the chosen scheme
  throws `AtAuthenticationException` rather than falling back to the other one,
  which would authenticate as an identity the caller did not ask for.
- **`AtAuthScheme` is a sealed class, not a Dart enum.** The singleton
  spelling remains (`AtAuthScheme.legacy`,
  `AtAuthScheme.postQuantum`), but enum-specific APIs such as
  `AtAuthScheme.values`, `.name`, `is Enum` and enum exhaustiveness no
  longer apply.
- **`AtAuth.signing` / `AtEnrollment.signing` and the `signing:` constructor
  parameter are now `scheme` / `scheme:`.** The scheme controls the broader
  at_auth behavior derived from the caller's choice, not only the PKAM signing
  algorithm.
- **`AtAuth.atLookUp` is now a nullable getter** holding the connection the most
  recent successful call authenticated — this is how a void-returning call still
  hands its connection forward. It is null before the first success and after a
  failure.
- **`onboard` uses two connections.** CRAM auth and the auto-approved first
  enrollment run on a keyless connection; the connection that PKAMs afterwards is
  built from the keypair that did not exist when the first was constructed.
- **`AtEnrollmentResponse` is `{enrollmentId, enrollStatus}`.** The deprecated
  `atSign`, `rootDomain` and `atAuthKeys` fields are gone, and so is the `session`
  that briefly replaced them. `toJson`/`fromJson` carry those two fields and
  nothing else — key material never crosses a process boundary in a response.
- **New `PendingEnrollment extends AtEnrollmentResponse`**, returned by `enroll`
  for an `AtEnrollmentRequest`. It adds `atKeys`: the APKAM keypair and symmetric
  key minted at submit time, which `waitForApproval` completes with the material
  the atServer was holding. They travel on the response because the partial
  keyset is deliberately not persistable — it has no `defaultSelfEncryptionKey`
  yet, which `FileAtKeysIo` requires to self-encrypt the APKAM fields at rest.
- **`AtEnrollment` takes its `AtLookUp` at construction**
  (`AtEnrollment.create(atLookUp)`) rather than per call; `enroll`, `deny`,
  `revoke`, `list`, `generateOtp` and `setSpp` all run on it.
  `approve(Atsign, AtKeysIo, decision)` reads the approver's own encryption
  private key and self encryption key from the `AtKeysIo` it is given.
- **`waitForApproval(Atsign, AtRootDomain, AtKeysIo, PendingEnrollment)` returns
  `void`** and builds its *own* connection from `pending.atKeys` — the injected
  one belongs to whoever submitted the request and cannot sign for the new
  enrollment. On success the completed keyset is persisted through the given
  `AtKeysIo` (`flush` for a durable store, `write` otherwise). Its retry defaults
  now live on `AtEnrollment.defaultRetryInterval` / `defaultMaxRetries`, so the
  interface and implementation can no longer disagree about them.
- **`EnrollmentRequest.atSign` is now `atsign` and typed `Atsign`**, matching the
  rest of the package. `apkamPublicKey` moves off the base class onto
  `FirstEnrollmentRequest`, the only subclass that uses it, which also gains
  `defaultAppName`/`defaultDeviceName` constants.
- **`PkamAuthenticator.authenticate` drops its `AtKeys` parameter.** It never
  used it — the signing key reaches PKAM through the connection.
  `CramAuthenticator` no longer downcasts to `AtLookupImpl`, which at_lookup 4
  does not export.
- **`RetryOptions`, `CramAuthenticator`, `PkamAuthenticator`, `KeyIds`,
  `AtAuthScheme` and `buildAtLookUp` are now exported** from
  `package:at_auth/at_auth.dart`. Most were public parameter and field types
  that consumers could not name.
- **`AtKeysMaterial.bytes` is a `Uint8List`, not an `AtBytes`.** base64 is a
  property of how a *keyfile* stores key material, so it now applies only at the
  JSON boundary; in memory the material is bytes. That removes the `.bytes.bytes`
  double-hop every read of typed material used to need.
  `AtKeysAssurance.expectBytes` returns `Uint8List` for the same reason.
  `operator ==` compares element-wise (`Uint8List ==` is identity) and `hashCode`
  uses `Object.hashAll` — same cost as the `AtBytes` implementations they
  replace. **Watch for `material.bytes.toString()`**: that used to give base64
  and now gives `[1, 2, 3]` — use `base64Encode(material.bytes)`. The six legacy
  flat fields on `AtKeys` are unchanged and still hold `AtBytes`.

#### at_lookup 4.0.0 and at_chops 4.0.0

- Requires `at_lookup: ^4.0.0` and `at_chops: ^4.0.0`, and requires
  `at_server_status: ^2.0.0` for the same reason. Detached from the pub workspace
  with path overrides until those are published, as at_lookup already is.
- The at_chops keypair wrappers are gone: key minting uses
  `RsaSigningAlgo().generateKeyPair()` and `AesCtrEncryptionAlgo(n)` instead of
  `RsaKeyPair.generate()` / `AESKey.generate(n)`, and `AESEncryptionAlgo` /
  `StringAESEncryptor` become `AesCtrEncryptionAlgo` with the key passed per
  call. **The `.atKeys` on-disk bytes are unchanged** — same AES-CTR/PKCS7 under
  the same keys and IVs, and the AES strength still follows the length of the
  keyfile's own `selfEncryptionKey` rather than being fixed.

### Fixed

- `AtKeys.toJson` wrote `namespaces` as a comma-joined string while `fromJson`
  read it with `optionalStringList`, so a keyset carrying namespaces could not
  round-trip. It is now a JSON array of `ns:rw` tokens, and `namespaces` is
  registered in `KeyIds.reservedTopLevelKeys` so it is no longer captured into
  `AtKeys.metadata` on read.

#### Deprecated API removed

A major version is the moment to settle these. The legacy `.atKeys` JSON format
is untouched by all of it — it stays readable *and* writable, and the six legacy
`AtKeys` key fields stay too (see Deprecations below).

- **`AuthResponse`, `AtAuthResponse`, `AtOnboardingResponse` are gone** (the
  whole `at_auth_responses.dart`). They were tagged "remove in v4" and had no
  remaining references — `authenticate`/`onboard` return nothing, and failure
  throws rather than returning `isSuccessful: false`.
- **`AtAuth.create` no longer accepts `atChops`.** The parameter was accepted and
  then never passed on, so supplying it did nothing.
- **`AtEnrollmentRequest` no longer accepts `apkamPublicKey` or
  `encryptedAPKAMSymmetricKey`.** Both were dead on this class — `enroll`
  generates its own APKAM keypair and encrypts its own symmetric key.
  (`apkamPublicKey` remains on `FirstEnrollmentRequest`, which needs it.)
- **`ActivateApiEndpoint` and `ActivateApiEndpointLegacy` are gone.** Use
  `RegistrarApiEndpoint`; the legacy `login`/`validate` getters map to
  `requestOtp`/`validateOtp` (their deprecation notices named replacements that
  never existed).
- **`EnrollmentBase`, `EnrollmentServerResponse` and
  `ServerEnrollmentRequest.namespace` are gone.** Use `AtEnrollmentRecord`,
  `ServerEnrollmentRequest` and `namespacePermissions` — one name per type.


### Added

- `AtKeys.generate(Atsign, {enrollmentId, mintLegacy})` — mints a fresh keyset
  (ML-DSA-65 APKAM signing + X-Wing encryption always; the legacy RSA/AES fields
  too unless `mintLegacy: false`). This is the onboarding key-minting entry
  point, now a static factory on the type it returns rather than a separate
  helper class. A `mintLegacy: false` keyset can authenticate under
  `AtAuthScheme.postQuantum`, but whether the atServer verifies an
  ML-DSA-65 signature is not settled here — leave the default unless you are exercising
  the PQ material.
- `AtAuthScheme` and `buildAtLookUp(...)` — the auth scheme a caller selects
  and the connection builder that applies it, pulling the matching key from an
  `AtKeys`.
- **`AtAuthScheme` owns the derived auth behavior end to end**:
  `signatureAlgorithm` (the at_chops signer), `signingAlgo` (the
  `rsa2048`/`mldsa65` wire token), `mintKeys(AtKeys)` and
  `requireApkamPublicKey`/`requireApkamPrivateKey`. One scheme now drives the
  keypair an enrollment mints, where in the keyset it lands, and the key PKAM
  later signs with — they can no longer disagree.
  `mintKeys` delegates its post-quantum arm to
  `AtKeys.generatePQEnrollmentPackage`, so an enrollment-minted keyset keeps
  its APKAM signing key under the same keyId while keeping its X-Wing material
  under the enrollment keypackage keyId.
- `ApkamKeyConveyance` with its default `RsaKeyConveyance` — how an
  enrollment's `apkamSymmetricKey` reaches its approver, injectable on
  `AtEnrollment.create(atLookUp, conveyance:)`. Deliberately an axis *separate*
  from `AtAuthScheme`: ML-DSA signs and X-Wing encapsulates, and one
  keypair cannot do both. The wire bytes are unchanged.


### Migration

- **Callers**: normalize once at the boundary — `atKeysIo.read(Atsign atsign)`
  instead of `atKeysIo.read(String atsign)`. If you already hold an `Atsign`, nothing
  changes.
- **Authentication**: drop the request object and the return value.

  ```dart
  // before
  final atAuth = AtAuth.create(atLookUp: atLookUp);
  final response = await atAuth.authenticate(AtAuthRequest(atsign, io));
  if (response.isSuccessful) { useChops(atAuth.atChops!); }

  // after — no throw means authenticated
  final atAuth = AtAuth.create();
  await atAuth.authenticate(atsign, AtRootDomain.atsignDomain, io);
  final authenticated = atAuth.atLookUp!;   // hand this to client creation
  ```

  Do **not** construct an `AtLookUp` to pass in: `authenticate` builds one from
  the keys it reads, because at_lookup binds its PKAM key at construction. If you
  were substituting a connection in tests, pass `lookUpFactory:` instead.
- **Onboarding**: `onboard(atsign, rootDomain, io, cramSecret, appName: 'wavi')`,
  and read `atAuth.atLookUp` afterwards rather than a returned session.
- **Enrollment (requesting app)**: `enroll` an `AtEnrollmentRequest` and narrow
  the result, then hand it to `waitForApproval` along with where the keys go:

  ```dart
  final atEnrollment = AtEnrollment.create(atLookUp);
  final pending = await atEnrollment.enroll(request) as PendingEnrollment;
  await atEnrollment.waitForApproval(atsign, rootDomain, atKeysIo, pending);
  // keys are now persisted in atKeysIo
  ```

  Reading keys off the response (`response.atAuthKeys`) is gone — after
  `waitForApproval` they are in the `AtKeysIo` you passed.
- **Enrollment (approving app)**: `approve(atsign, myKeysIo, decision)` where you
  used to pass `AtKeys` (or a session); `deny`/`revoke` take the decision alone.
  The approver's keys are read from the `AtKeysIo`.
- **`AtEnrollmentRequest`/`FirstEnrollmentRequest`**: pass `atsign:` (and
  `rootDomain:` if not the default) rather than `atSign:` or `session:`.
  `namespaces` is a `List<NamespacePermission>`, not a `Map<String, String>`.

## 3.3.0-rc1
- feat: add `AtKeysMaterial` — the only key type `AtKeys`'s API deals in (`addKey`, `getKey`, `keysForKeyId`, `keysForEnrollment`, `retireKey`, the `keysList` constructor param, ...). It's fully self-describing: `keyId`/`enrollmentId` plus `keyPartType` (an open `String` — the mechanical crypto role; known tokens in `CryptographicKeyType`: symmetric encryption/authentication and the public/private halves of encryption, verification/signing, encapsulation/decapsulation and key agreement), `keyAlgorithmType` (an open `String` — the algorithm family; known tokens in `KeyAlgorithmType`: `aes256`/`rsa2048`/`ecc_secp256r1`/`ed25519`/`x25519`/`mlkem768`/`mldsa65`/`xwing`, matching the pkam/enrollment `signingAlgo` literals), `bytes`, `operations`, `createdAt`, and `status` (`active`/`retired`/`dead`; `withStatus(...)` copies a material at a new status). Both token fields are deliberately Strings, not enums: unknown tokens are preserved and round-tripped, so a keyfile written by a newer client stays readable — and losslessly flushable — by an older one; whether an algorithm is classical, post-quantum or hybrid is carried by the algorithm token (e.g. `xwing`), not a separate role axis. The wire's nested `keys[].keyParts[]` document shape — grouping the materials sharing a `keyId` (e.g. the public+private halves of a keypair) — is produced/consumed by `encodeAtKeysDocument`/`parseAtKeysDocument` (also exported), not a separate model type. Keys produced by one enrollment are grouped by an optional `enrollmentId` and queried via `AtKeys.keysForEnrollment(...)`; at most one material of a given `CryptographicKeyType` may share an `enrollmentId`.
- feat: `AtKeys.toJson()`/`.fromJson(...)` now produce/consume the versioned typed-keys document shape (`version`, `atsign`, `keys`, with legacy fields flat at the top level — upgrading a legacy file to the typed-keys document is additive, not a format swap), replacing the former codec/resolver/document layer. Backward compatible: `fromJson` accepts json without a `version` field as the legacy flat shape, and throws `AtKeysUnsupportedVersionException` on an unknown version. Typed materials are looked up via `AtKeys.getKey(keyId, type)` and `.keysForKeyId(keyId)`.
- feat: add `WrittenAtKeysIo.flush(Atsign, AtKeys)` — the runtime persist operation: mutate the in-memory `AtKeys` (`addKey`, `retireKey`, ...), then flush the complete state. On an existing file, flush safety-checks the rewrite (`AtKeysAssurance.validateMapUpdate` — nothing may be lost: every existing `(keyId, keyPartType)` must survive with identical fields, though `status` may move forward `active` → `retired` → `dead` and new materials may be added), then rewrites; flushing a legacy `.atKeys` file upgrades it in place to the typed-keys document format (legacy fields preserved byte-for-byte). On a missing file, flush creates it. `write(...)` stays the create-only initial persist. (The `append`/`save` methods that existed briefly during this release's development are gone — never published.) `FileAtKeysIo` writes are atomic (write-to-temp + rename, so a crash can never truncate the keyfile) and a flush over an existing file first preserves it as `<file>.bak`.
- feat: `AtKeysAssurance` is now the single home for all atKeys validation — both the low-level `expect*`/`optional*` value/type checks used by `AtKeysMaterial.fromJson`/`AtKeys.fromJson`, and the structural invariants (`validateKeyMaterials`: duplicate `keyId`, one material of each `CryptographicKeyType` per enrollment, the flush-safety check `validateMapUpdate`).
- feat: add passphrase envelope support via `AtKeysPassphraseEnvelopeCodec` (`encode`/`decode`/`isEnvelope`, argon2id key derivation), and add `InMemoryAtKeysIo` for in-memory/test flows (both exported).
- fix: `AtKeys.==`/`hashCode` now also cover `atsign`, `metadata` (compared structurally — nested maps/lists by value, not identity) and the typed key materials (order-insensitive).
- chore(deps): require `at_chops` ^3.4.1 for hashing algorithm barrel exports used by AtKeys passphrase handling.

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
