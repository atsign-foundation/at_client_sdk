## 4.0.0-rc2

at_auth is the protocol layer under at_client's lifecycle verbs. What an
application used to call here — logging in, approving and deciding
enrollments — is `Atsign.open`, `Atsign.enroll` and `client.enrollments` in
at_client, and this release removes the surface those replace.

### Removed

- **BREAKING:** `AtAuth`, with `authenticate`, `onboard`, `atChops`,
  `atLookUp` and `completeActivation`, and the request and response objects
  `AtAuthRequest`, `AtAuthResponse`, `AuthRequest`, `AuthResponse`,
  `AtOnboardingRequest` and `AtOnboardingResponse`. Activation is
  `activateAtSign(...)`; logging in is at_client's `Atsign.open`, and
  `Atsign.authenticatesAs` is the check that builds no client.
  `RetryOptions` keeps its export, from a file of its own.
- **BREAKING:** `AtEnrollment` keeps `submit`, `approve` and
  `waitForApproval`. `deny`, `revoke`, `list`, `generateOtp` and `setSpp` are
  at_client's `client.enrollments`, run on the client's own connection, and
  `Otp` and `defaultOtpExpiry` go with them. `update` and
  `EnrollmentUpdateRequest` are at_client's `EnrollmentUpdater`, exported
  from `package:at_client/at_client_mixins.dart`.
- **BREAKING:** `AtAuthSession` carries no `atLookUp`. A session is what a
  client is built from — the atSign, where its atServer is looked up, the key
  source and the enrollment the keys authenticate as — and the client opens
  a connection of its own.
- **BREAKING:** `httpsProbe`, `defaultProbe` and `secureSocketProbe` are
  removed, and at_auth builds no connection of its own. The atServer check
  before an activation asks over the activation's own lookup with at_lookup's
  `checkAtSignServer`: the atDirectory through that lookup's finder, the
  atServer over its transport. at_auth no longer depends on
  at_server_status, and nothing its main barrel reaches imports
  `at_lookup_io.dart`.
- **BREAKING:** `AtKeys.toAtChops` and `.toAtChopsForEnrollment` are
  library-private; `AtKeys.authenticationFor` is the public route, and
  `authenticationKeyPairFor`, `encryptionKeyPair` and `selfEncryptionKey`
  hand back the material without an `AtChops` around it.
- **BREAKING:** `AtKeys.copyWith` is removed; use `addKey`.
- **BREAKING:** `KeyIOMixin` and its `decryptAtKeysWithSelfEncKey`,
  `encryptAtKeysWithSelfEncKey`, `generateKeyPairs` and `decodeAtKeys` are
  removed. A `.atKeys` document is read and written through
  `FileAtKeysIo.read`/`.write`, which apply the passphrase envelope and the
  self-encryption; `passphraseCodec` on `AtKeysIo` remains for a caller that
  needs the envelope alone.
- **BREAKING:** the registrar's legacy aliases `ActivateApiEndpoint` and
  `RegistrarApiEndpoint.login`/`.validate` are removed; use
  `RegistrarApiEndpoint.requestOtp`/`.validateOtp`.
- `example/authenticate.dart` is gone with `authenticate`;
  `example/onboard.dart` runs over `activateAtSign`.

### Changed

- **BREAKING:** `activateAtSign` requires `atLookUp` and
  `AtEnrollment.waitForApproval` requires `atLookup`, each an
  `AtLookupMuxable`, because each installs an authenticator on it. Neither
  builds a connection when none is given, and neither closes the one it is
  given. The at_lookup floor moves to `^3.7.0-rc2`, the release carrying
  `checkAtSignServer`.
- **BREAKING:** `AtEnrollment.approve` takes `approverKeys`, an
  `ApproverKeyMaterial` holding the approver's encryption private key and
  self-encryption key, and it is required: approval reads nothing off the
  connection any more, and `approverChops` is removed. `approve` no longer
  writes the unwrapped APKAM symmetric key into the caller's `AtChops`.
- **BREAKING:** no caller names the enrollment to authenticate as. The keys
  decide, through `AtKeys.enrollmentToAuthenticateAs()`: the one enrollment
  holding active typed authentication material, else the flat stored id,
  else `primary` for a keyfile that predates enrollments. A retrofitted
  keyfile therefore authenticates as its successor with nothing passed. A
  keyfile holding several live enrollments throws naming them. `primary`
  never reaches the wire: at_commons 5.18.0's `PkamVerbBuilder` omits it, so
  the floor moves to that release.
- **BREAKING:** a self-enrollment no longer approves its own request and no
  longer sends `encryptedAPKAMSymmetricKey`: the atServer approves a
  retrofit outright, and a `pending` answer is denied and thrown.
- A PKAM challenge is signed from the keypair the keyfile holds for the
  enrollment, through one rule in every authenticator at_auth builds: the
  keyfile's keypair signs when it holds one, and an injected `AtChops` signs
  when it holds none. The bytes are unchanged and pinned against openssl.
- `waitForApproval` no longer pauses 500 ms before every PKAM attempt when
  `logProgress` is set; the progress events and the retry interval are
  unchanged.
- `AtKeys.metadata` is no longer deprecated: it carries a legacy keyfile's
  entries outside the flat schema, and the typed document has no
  equivalent.
- A typed keyfile (`"version": 1`) is written with an empty top-level
  `"keys": []` again, as 3.3.0 wrote it. at_auth 3.3.0 refuses a versioned
  keyfile without the array, so a keyfile written by 4.0.0-rc1 could not be
  read by an application still on 3.3.0. Typed material stays in
  `enrollments` and `atsignKeys`, and a document holding none is still
  written in the legacy shape with neither field.

### Added

- `activateAtSign(atSign: ..., cramSecret: ..., keys: ..., signingAlgo: ...,
  atLookUp: ...)`: CRAM activation as a parameter list. It waits for the
  atServer, mints the keys, submits and authenticates as the first
  enrollment, writes the keys to the store named and completes the
  activation, answering the enrollment id. The `atLookUp` it runs over is
  taken as having already reached the atServer unless `awaitProvisioning` is
  set, for a caller that has not reached the atServer on it yet.
- `CryptographicMaterialStatus.pending`, the status of an enrollment's key
  material between submission and approval, ranking before `active`.
  `AtKeys.activatePending`, `AtKeys.discardEnrollment` and
  `AtKeys.pendingEnrollmentIds` manage it, and a flush may drop pending
  material. A store written by an earlier build carries `pending` through
  unchanged as a token it does not know.
- `AtKeys.fileLegacyMaterial` and `AtKeys.legacy`, the one writer of the flat
  keyfile document that names no deprecated member, with
  `AtKeys.enrollmentSymmetricKey` and `AtKeys.storedEnrollmentId` reading the
  two flat fields the typed accessors did not cover. The seven flat fields
  stay deprecated, and their annotations now name these.
- `AtKeys.holdsAuthenticationMaterial`, `AtKeys.authenticationKeyPairFor`,
  `.encryptionKeyPair` and `.selfEncryptionKey`. The last two prefer typed
  material under the atSign and fall back to the flat fields, with the
  algorithm checked rather than assumed from the role.
- `InMemoryAtKeysIo.holding(atSign, keys)`: an in-memory store already
  holding a key set, for a caller that has keys in hand and needs a source.
- `FileAtKeysIo` keeps a one-off `<keyfile>.pre-v1` copy of the flat
  document the first time it writes typed material into it, announced at
  `shout`; the rolling `.bak` is unchanged.

### Fixed

- The never-lose rule on the flat legacy fields protects a credential and
  nothing else: a null field may gain a value, and a document holding no
  active typed material and none of the three flat secrets may have its
  legacy fields replaced. An approval can therefore fill the fields its
  submission left empty, and a store emptied by a denial can take the next
  request.
- A typed document holding no credential — every material pending — may go
  back to the legacy shape, which is what a denied enrollment leaves behind.
- A keyfile whose atSign material is typed derives a working `AtChops`; a
  typed-only document produced empty encryption keys.
- The enrolment handshake installs an authenticator on its lookup and never
  writes at_lookup's credential fields; both were written, and one was never
  read.

## 4.0.0-rc1

- fix: **`authenticatorForChops` requires `signingAlgo` and `hashingAlgo`.**
  ⚠️ This tightens a signature added earlier in this same **unpublished**
  `4.0.0-rc1`; `3.3.0`, the last published version, carries no
  `at_authenticator.dart` at all. Both parameters defaulted, to `rsa2048` and
  `sha256`. This is the one authenticator with no keystore behind its signer,
  so the caller is the only party that knows what the AtChops holds — and a
  default made a caller that forgot indistinguishable from one that meant RSA.
  An ML-DSA key put through the RSA routine fails inside at_chops on a key
  length, naming neither the caller nor the mismatch. The compiler now names
  the call site instead.
- fix: **`AtKeys.authenticationAlgorithmFor` refuses an algorithm this build
  cannot sign with, rather than returning null.** ⚠️ Also unpublished — the
  method does not exist in `3.3.0`. Null had two meanings — "this enrollment
  files no typed material, so its keypair is the flat RSA pair" and "its typed
  material names an algorithm I cannot read" — and a caller could not tell them
  apart afterwards. The obvious reading of null, *legacy, so rsa2048*, signs a
  different enrollment's credentials with the wrong routine on the second.
  `authenticationFor` already refused exactly that case; the refusal moves up
  so the algorithm-only call is held to the same terms, and a caller holding
  its own signer stops being the one path that guesses.
  `signingAlgorithmForEnrollment` still reports both as null and is unchanged —
  it is the call to make where that is wanted.

- fix: **the `_apsk` an enrolment advertises is spelled by its
  algorithm alone.** ⚠️ This changes behaviour introduced earlier in this same
  **unpublished** `4.0.0-rc1`; it is not a break against `3.3.0`, the last
  published version. Exactly one active `rsa2048` key rides `apskLegacy` as the
  bare string; anything else rides `apsk` as the array. A key package used to
  force the array as well, on the grounds that a bare value cannot state the
  algorithm of whatever signed the package — but where that signer is rsa2048
  the bare value states exactly it, and where it is not, the algorithm already
  chose the array. So the condition only ever fired on the case it was wrong
  about, and that case is reachable: a legacy posture names an empty data
  signing set, so nothing is advertised, while a pq key-exchange mode still
  carries a package.
  **Why it mattered.** at_client composes this same record at every start and
  republishes on any difference, and it spells that key bare. The two composers
  of one record therefore disagreed about its shape — at_auth installed the
  array, the enrolment's first start rewrote it bare — and that republish
  discards the chain link the approver conveyed against the old value, leaving
  the enrollment silently unsigned. Pinned in `enrollment_test.dart` with the
  mldsa65 arm as its control.

- feat: **a self-enrollment submitted by an atSign that holds no enrollment is
  approved over the connection that requested it.** The atServer's
  self-enrolment auto-approve needs an APKAM-authenticated connection, and an
  atSign authenticating with its flat PKAM key has none — so its request lands
  `pending`. It is approvable on that same connection, because a connection
  carrying no enrollment id is granted full access, so such a request now mints
  a symmetric key, wraps it to the atSign's own encryption public key, and
  approves itself through the ordinary approver. The wrap is what keeps the
  record's copy recoverable afterwards.
  The discriminator is the **session's** enrollment id rather than the
  connection's: `pending` also means an atServer too old to auto-approve an
  APKAM retrofit, and that case keeps its existing deny-and-throw.

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
