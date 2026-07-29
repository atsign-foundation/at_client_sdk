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
- **`AtOnboardingRequest.appName`/`deviceName` are now `final` constructor
  parameters** (same `'firstApp'`/`'firstDevice'` defaults) instead of mutable
  fields settable only by cascade after construction.
- **`enrollmentId` is a structural field of the typed-keys document**, alongside
  `version`/`atsign`/`keys` — read and written explicitly rather than carried in
  the legacy flat payload. The on-disk bytes are unchanged; what changes is that
  a keyfile field named `enrollmentId` (or `version`/`atsign`/`keys`) is never
  captured into `AtKeys.metadata`. `KeyIds.reservedTopLevelKeys` and
  `KeyIds.isMetadata` are the single source of truth for that split, replacing
  two divergent private copies. `flush` now permits an `enrollmentId` to be set
  once (`null` → value, which is what enrollment approval does) but rejects
  repointing an existing one at a different enrollment.

#### The enrollment models are session-scoped

The session is now the single carrier of "which atsign, reached how, with keys
read from where" throughout enrollment — replacing the loose `atSign` /
`rootDomain` / `atAuthKeys` fields that were duplicated across request and
response.

- **`AtEnrollmentResponse` is now `{enrollmentId, enrollStatus, session}`.** The
  deprecated `atSign`, `rootDomain` and `atAuthKeys` fields are gone; `session`
  is required. `toJson` emits `enrollmentId`, `enrollStatus` and the session's
  atsign; `fromJson` takes the session from the caller, since a session holds a
  live `AtKeysIo` and cannot round-trip through json.
- **New `PendingEnrollment extends AtEnrollmentResponse`**, the declared return
  type of `submit`. It adds `keys`: the APKAM keypair and symmetric key minted at
  submit time, which `waitForApproval` completes with the material the atServer
  was holding. They travel on the response because the partial keyset is
  deliberately not persistable — it has no `defaultSelfEncryptionKey` yet, which
  `FileAtKeysIo` requires to self-encrypt the APKAM fields at rest.
- **`submit` is now the app-enrollment method alone: `Future<PendingEnrollment>
  submit(AtEnrollmentRequest, AtLookUp)`.** The first enrollment moves to
  `submitFirstEnrollment(FirstEnrollmentRequest, AtLookUp)`, which still returns
  a plain `AtEnrollmentResponse`. `submit` previously took the abstract
  `EnrollmentRequest`, dispatched on its runtime subtype and declared the base
  return type, so callers had to write `as PendingEnrollment` to reach the keys —
  and passing anything else threw `InvalidRequestException` at runtime. Splitting
  the two makes both illegal at compile time instead: the request type picks the
  method, and the method's return type is exactly what that path produces.
  Only the first enrollment can mint no keys — it is auto-approved and receives
  only an `apkamPublicKey` — which is why the two return types differ.
- **`apkamPublicKey` moved from `EnrollmentRequest` down to
  `FirstEnrollmentRequest`, and is non-nullable there.** It was inherited but
  permanently `null` on `AtEnrollmentRequest`, whose `submit` mints its own
  keypair.
- **`waitForApproval` takes a `PendingEnrollment`**, so it cannot be called
  without the keys it needs. On success it persists the completed keyset through
  the session's `atKeysIo` (`flush` for a durable store, `write` otherwise) and
  replaces `session` with one carrying the approved enrollmentId and the
  authenticated connection.
- **`approve`/`deny`/`revoke` take the approving app's `AtAuthSession`** instead
  of (for `approve`) a bare `AtKeys`. Approval reads the approver's encryption
  private key and self encryption key via `session.atKeysIo.read(...)` — the same
  path every other key consumer uses — and the returned response is scoped to
  that session.
- **`EnrollmentRequest.atSign` is now `atsign` and typed `Atsign`**, matching the
  rest of the package. `FirstEnrollmentRequest` takes a `session` and derives
  `atsign`/`rootDomain` from it, as `AtEnrollmentRequest` already did.
- **`EnrollmentRequestDecision` is sealed, with one subtype per operation:
  `EnrollmentApproval`, `EnrollmentDenial`, `EnrollmentRevocation`.** Each of
  `approve`/`deny`/`revoke` takes its own subtype, so handing a decision to the
  wrong operation is a compile error — previously `deny(EnrollmentRequestDecision
  .revoked(id, atSign))` compiled and sent `enroll:revoke` from `deny`. The
  `approved`/`denied`/`revoked` factories keep their names and now statically
  return the narrow type, so existing construction sites keep working. Each field
  lives on the operation that reads it: `encryptedApkamSymmetricKey` on the
  approval, `force` on the revocation, `enrollmentId` on the base.
- **`EnrollmentRequestDecision.atSign` and `.enrollOperationEnum` are gone.** The
  atsign now comes from the `AtAuthSession` these methods already take — at_auth
  read `session.atsign` and ignored the decision's copy, so the two were rival
  sources of truth for whose enrollment was being decided. `enrollOperationEnum`
  was a discriminator nothing dispatched on: `approve` hand-builds its command and
  `revoke` hardcoded its own operation, leaving `deny` the only reader; `deny` now
  hardcodes `EnrollOperationEnum.deny` as `revoke` always did. `force` is also
  `final` now, rather than a public mutable field settable on an approval.
- **`EnrollmentRequestDecision.approved` takes
  `String encryptedApkamSymmetricKey`** instead of `AtBytes apkamSymmetricKey`.
  Callers were building an `AtBytes` from the base64 string the atServer gave them,
  only for the factory to `toString()` it and `approve` to `base64Decode` it. The
  `String` also matches `ServerEnrollmentRequest.encryptedAPKAMSymmetricKey`, which
  is where the value comes from. One spelling now, too — the getter used to be
  `encryptedAPKAMSymmetricKey` while the parameter was `apkamSymmetricKey`.

#### The wasm-safe barrel split

The running client — including web — authenticates through at_auth; only
onboarding/setup is desktop/CLI. So at_auth's own sources reachable from
`at_auth.dart` no longer import `dart:io`, and the VM-only pieces move behind a
new barrel. CI compiles `tool/wasm_entry.dart` for wasm to keep the surface
building.

- **New `at_auth_io.dart` barrel carries the VM-only surface: `FileAtKeysIo`
  (with `getDefaultAtKeysFilePath`/`getHomeDirectory`) and the new
  `defaultProbeSocket`.** It re-exports `at_auth.dart`, so importing it is
  enough — the same shape as `at_chops_ffi.dart`. `FileAtKeysIo` itself is
  unchanged and stays in at_auth; only the barrel that exports it moved.
  `EphemeralAtKeysIo` and the `AtKeysIo` interfaces stay on `at_auth.dart`.
- **`AtAuthImpl` no longer has a built-in socket probe.** `validateAtServer`'s
  TLS reachability check was a `SecureSocket` call in the core; it is now
  `defaultProbeSocket` in `at_auth_io.dart`, injected via
  `AtAuth.create(probeSocket: ...)`. `probeSocket` was already an
  injectable field (`@visibleForTesting`) — it is now the only implementation
  route, and a constructor parameter. **Left unset, the reachability probe is
  skipped** with a `warning` log; the atDirectory lookup still runs, so an
  unreachable atServer surfaces from the connection attempt instead of from
  validation.
- **`RegistrarService` no longer defaults to an HTTP client that accepts every
  certificate.** It defaulted to an `IOClient` whose `badCertificateCallback`
  returned `true` unconditionally, for a client carrying an API key and CRAM
  secrets; the default is now `http.Client()`, which validates certificates and
  resolves per platform. To reach a registrar with a self-signed certificate,
  pass your own `IOClient` as `httpClient` — that injection point is unchanged.
- **`RegistrarService`'s unused `atAuth` constructor parameter is gone.** It was
  never read, and it was the class's only path to at_lookup, i.e. to `dart:io`.

#### Deprecated API removed

A major version is the moment to settle these. The legacy `.atKeys` JSON format
is untouched by all of it — it stays readable *and* writable, and the six legacy
`AtKeys` key fields stay too (see Deprecations below).

- **`AuthResponse`, `AtAuthResponse`, `AtOnboardingResponse` are gone** (the
  whole `at_auth_responses.dart`). They were tagged "remove in v4" and had no
  remaining references — `authenticate`/`onboard` return `AtAuthSession`, and
  failure throws rather than returning `isSuccessful: false`.
- **`AtAuth.create` no longer accepts `atChops`.** The parameter was accepted and
  then never passed on, so supplying it did nothing.
- **`AtEnrollmentRequest` requires `session`** and no longer accepts `atSign`,
  `rootDomain`, `apkamPublicKey` or `encryptedAPKAMSymmetricKey`. `atSign` and
  `rootDomain` come from the session; the other two were dead on this class —
  `submit` generates its own APKAM keypair and encrypts its own symmetric key.
  (`apkamPublicKey` now lives on `FirstEnrollmentRequest`, which needs it.)
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
  helper class. Note that `mintLegacy: false` cannot yet PKAM-authenticate:
  PKAM signs with the RSA `apkamPrivateKey`, and `MlDsaPkamSigner` remains
  experimental.

### Migration

- **Callers**: normalize once at the boundary — `atKeysIo.read(Atsign atsign)`
  instead of `atKeysIo.read(String atsign)`. If you already hold an `Atsign`, nothing
  changes.
- **`AtOnboardingRequest`**: replace
  `AtOnboardingRequest(a, io)..appName = 'wavi'` with
  `AtOnboardingRequest(a, io, appName: 'wavi')`.
- **Enrollment (requesting app)**: `submit` an `AtEnrollmentRequest` and hand the
  result to `waitForApproval` — no cast, `submit` returns the `PendingEnrollment`:

  ```dart
  final pending = await atEnrollment.submit(request, atLookUp);
  await atEnrollment.waitForApproval(pending);
  AtClientManager.fromAuthSession(pending.session);   // keys already persisted
  ```

  Reading keys off the response (`response.atAuthKeys`) is gone — after
  `waitForApproval` they are in `pending.session.atKeysIo`.
- **First enrollment**: `submit(firstEnrollmentRequest, atLookUp)` becomes
  `submitFirstEnrollment(firstEnrollmentRequest, atLookUp)`. `AtAuthImpl.onboard`
  does this internally, so it only affects callers driving the first enrollment
  themselves — or mocking `AtEnrollment`, where the stubbed method name changes.
- **Enrollment (approving app)**: pass your own session where you used to pass
  `AtKeys` (or nothing): `approve(decision, atLookUp, mySession)`, and likewise
  for `deny`/`revoke`. The approver's keys are read from `mySession.atKeysIo`.

  The decision factories keep their names; drop the `atSign` argument (the session
  supplies it) and pass the encrypted APKAM symmetric key as the base64 `String`
  the atServer gave you:

  ```dart
  // before
  approve(EnrollmentRequestDecision.approved(
      enrollmentId: request.enrollmentId,
      apkamSymmetricKey: AtBytes.fromString(request.encryptedAPKAMSymmetricKey!),
      atSign: atSign), atLookUp);
  deny(EnrollmentRequestDecision.denied(id, atSign), atLookUp);
  revoke(EnrollmentRequestDecision.revoked(id, atSign, force: true), atLookUp);

  // after
  approve(EnrollmentRequestDecision.approved(
      enrollmentId: request.enrollmentId,
      encryptedApkamSymmetricKey: request.encryptedAPKAMSymmetricKey!),
      atLookUp, mySession);
  deny(EnrollmentRequestDecision.denied(id), atLookUp, mySession);
  revoke(EnrollmentRequestDecision.revoked(id, force: true), atLookUp, mySession);
  ```

  If you were storing a decision in a variable typed `EnrollmentRequestDecision`
  and passing it to one of the three methods, narrow the variable's type (or use
  `final`/`var`) — the methods now take `EnrollmentApproval`, `EnrollmentDenial`
  and `EnrollmentRevocation` respectively.
- **`FirstEnrollmentRequest`**: pass `session:` instead of `atSign:`/`rootDomain:`.
  `AtAuthImpl.onboard` builds that session from the onboarding request, so this
  only affects callers constructing the request directly.
- **`FileAtKeysIo`**: swap the import. `at_auth_io.dart` re-exports everything
  `at_auth.dart` has, so this is one line, not two:

  ```dart
  // before
  import 'package:at_auth/at_auth.dart';
  // after — VM and Flutter callers
  import 'package:at_auth/at_auth_io.dart';
  ```

- **The socket probe**: every `AtAuth.create()` on the VM or in Flutter should
  become `AtAuth.create(probeSocket: defaultProbeSocket)`, or it loses the
  atServer reachability check. This compiles either way, so it needs a sweep —
  the bare call sites in this repo are
  `at_onboarding_cli/lib/src/onboard/at_onboarding_service_impl.dart:184,708`,
  `at_client_flutter/lib/src/services/auth_service.dart:14`,
  `at_client_flutter/examples/dockerstats/lib/main_smoke.dart:100`,
  `tests/at_functional_test/test/enrollment_test.dart`,
  `tests/at_functional_test/test/auth_session_handoff_test.dart` and
  `tests/at_end2end_test/lib/src/test_initializers.dart:106`.
- **`RegistrarService`**: drop the `atAuth:` argument if you passed one. If you
  relied on the old default to talk to a registrar with a self-signed
  certificate, inject the permissive client explicitly:

  ```dart
  RegistrarService(
    registrarUrl: url,
    apiKey: key,
    httpClient: IOClient(HttpClient()
      ..badCertificateCallback = (cert, host, port) => true),
  );
  ```

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
