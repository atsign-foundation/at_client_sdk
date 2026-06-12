# Phase 3 — `SecureGroup` v1 + the `group` CryptoProvider (design / audit)

Design source of truth: `docs/crypto-roadmap.md` (Phase 3). This is the
implementation-level audit that grounds that phase in the *current* code on
the integration branch, with per-component MATCHED / MISSING deltas at
file:line, before any code is written.

Scope of Phase 3: turn the existing secret-sharing substrate + the pluggable
`CryptoProvider` seam into a working **self-encryption** provider that
encrypts app data under per-(atSign, namespace) rotating epoch keys. Cross-
atSign (shared) groups are Phase 4; the pq-mls engine is Phase 5. This phase
begins `selfEncryptionKey` retirement (phases 1–2 of that retirement).

## 1. What exists, and what it gives us

### 1a. Secret-sharing substrate (`lib/src/secret_sharing/`)

`PairwiseSecretSharing` mixin (`pairwise_secret_sharing.dart`) — the delivery
+ store layer the group rides on:

| Capability | Symbol (file:line) | Phase-3 use | Status |
|------------|--------------------|-------------|--------|
| Encrypted addressed delivery | `sendEnvelope(ClientKeyPackage to, String appNamespace, Map payload)` (:130) | distribute epoch keys | MATCHED |
| Per-secret share | `shareSecretWith(ClientKeyPackage, Secret)` (:403) | push `__rk.*` to a member | MATCHED |
| Bulk share, namespace-filtered | `shareAllSecretsWith(to, {approvedNamespaces})` (:420) | seed a new member | MATCHED |
| Approver seeding | `shareAllSecretsWithEnrollment(eid, approvedNamespaces, …)` (:447) | post-approval group add | MATCHED |
| Inbound store + emit | `receivedSecrets` stream, `_handleSecretPayload` (:372) | epoch-key arrival | MATCHED |
| Race-free await | `waitForSecret(namespace, name, {timeout})` (:346) | decrypt-miss recovery | MATCHED |
| Delivery driver | `startListening()/stopListening()/sweepOnce()` | run the group | MATCHED |
| Payload kinds | `secretPayloadKind='secret'`; `'request'`/`'response'` **reserved** (:335) | pull flow | MISSING (request/response handling) |

`PairwiseClientRegistration` mixin (`pairwise_client_registration.dart`) — the
identity + roster layer:

| Capability | Symbol (file:line) | Phase-3 use | Status |
|------------|--------------------|-------------|--------|
| Register identity + namespaces | `registerClient({Iterable<String>? namespaces})` (:171), additive | provider joins scope | MATCHED |
| Roster discovery | `discoverClients({String? enrollmentId, String? namespace})` (:310) | who to distribute to | MATCHED |
| Self identity | `clientId` (:117), `xWingPublicKey` (:131), `xWingSeed` `@protected` (:141), `myKeyPackage` (:127) | — | MATCHED |
| Registered namespaces | `registeredNamespaces` (:112) | — | MATCHED |
| Revocation-aware roster | — | exclude revoked enrollments | MISSING (`excludeEnrollmentIds`) |
| Roster-change events | — | push to late joiners | MISSING (`onNewClientDiscovered`) |

`SecretStore` (`secret_store.dart`) — the local key table:

| Capability | Symbol (file:line) | Phase-3 use | Status |
|------------|--------------------|-------------|--------|
| `(namespace,name)→Secret{value,createdAt}` | `Secret` (:11–14) | epoch keys + pointer | MATCHED |
| Reserved-name write | `putSecret(secret, {allowReservedName})` (:87) | `__rk.*` writes | MATCHED |
| Newest-wins merge | `putIfNewer(secret)` (:102) | pointer convergence | MATCHED |
| Lookup / remove | `getSecret` (:111), `removeSecret` (:114) | — | MATCHED |
| Namespace authorization (server-mirrored) | `namespaceAuthorizes(approved, ns)` (:134, static) | filter sharing | MATCHED |
| App-pluggable persistence | `SecretStorePersistence` (:50) | epoch keys at rest | MATCHED |
| Prefix enumeration | `listSecrets({String? namespace})` (:123) — **no `namePrefix`** | enumerate `__rk.*` per scope | MISSING (`namePrefix:`) |

Shared instance: `AtClientSecretSharing.forClient(atClient, {persistence,
publicKeyCacheSettings})` (`at_client_secret_sharing.dart`) — Expando-cached,
one client identity per `AtClient`. The group provider MUST obtain its
substrate through this, never construct its own (would mint a second
identity).

### 1b. Pluggable crypto seam (`lib/src/crypto/`)

| Capability | Symbol (file:line) | Status |
|------------|--------------------|--------|
| Provider contract | `CryptoProvider{id; initialize(CryptoContext); encrypt(CryptoEncryptRequest)→CryptoEncryptResult; decrypt(CryptoDecryptRequest)→CryptoDecryptResult}` (`crypto.dart`:175) | MATCHED |
| Injected context | `CryptoContext{atClient, currentAtSign, atChops, storage}` (:89) | MATCHED |
| Config | `CryptoConfig{defaultProviderId, providers, policy}` (:64) | MATCHED |
| Routing | `CryptoRuntime` routes encrypt/decrypt by `appMetadata.providerId` (`crypto_runtime.dart`) | MATCHED |
| Wire metadata | `AppMetadata{providerId, additional: Map<String,dynamic>?}`, `additional` flat-serialized (`at_commons` at_key.dart:838) | MATCHED |
| Encrypt I/O | `CryptoEncryptRequest{atKey, plaintext, existingMetadata}` → `CryptoEncryptResult{ciphertext, metadata: AppMetadata, isEncrypted}` (:188) | MATCHED |
| Decrypt I/O | `CryptoDecryptRequest{atKey, ciphertext, metadata: AppMetadata}` → `CryptoDecryptResult{plaintext}` (:212) | MATCHED |
| Provider storage | `CryptoStorage{read, write}`, `CryptoStorageKey{owner, recipient, namespace, name}` (:153) | MATCHED (unused by v1 — epoch keys live in SecretStore, see §6) |
| Missing-provider policy | `CryptoPolicy.onProviderNotFound` (:110) | MATCHED |
| Decrypt-failure policy | — | MISSING (`onDecryptFailed`) |

### 1c. Primitives (at_chops, all on-branch)

- X-Wing KEM: `XWingPureDartAlgo.instance.encapsulate(pub)→({ciphertext,
  sharedSecret})`, `.decapsulate(seed, ct)→Uint8List`.
- AEAD: `AesGcm256EncryptionAlgo(AESKey).encrypt/decrypt(bytes, {iv})`;
  `AtChopsUtil.generateRandomIV(12)`.
- KDF for `export()`: `Hkdf` from `package:cryptography` (already a dep) —
  `Hkdf(hmac: Hmac.sha256(), outputLength: n)`.

**Reuse verdict:** ~all of the delivery, store, identity, discovery, crypto-
seam, and primitive layers are MATCHED. Phase 3 is mostly *composition* plus
five small substrate additions (the MISSING rows) and two new classes
(`SecureGroup`/`PairwiseGroup`, the `group` provider).

## 2. The five deferred substrate additions (build first)

Each is small and independently testable; they unblock the group.

1. **`SecretStore.listSecrets({String? namespace, String? namePrefix})`** —
   add the optional prefix filter (one line in the `.where`). The provider
   enumerates `__rk.*` per scope on load and for old-epoch pruning.
   *Target:* `secret_store.dart:123`.
2. **`excludeEnrollmentIds` on roster/sharing** — `discoverClients({…,
   Set<String>? excludeEnrollmentIds})` filters returned packages;
   `shareAllSecretsWith(…, {Set<String>? excludeEnrollmentIds})` passes
   through. Revocation correctness: revoked enrollments' key packages stay
   published until TTL, so rotation must skip them explicitly.
   *Targets:* `pairwise_client_registration.dart:310`,
   `pairwise_secret_sharing.dart:420`.
3. **`kind:'request'`/`'response'` pull flow** — in `_handleSecretPayload`'s
   sibling path, handle `kind:'request'` envelopes `{kind:'request', want:
   [name…] | namePrefix}`: resolve the requester's key package
   (`fromClientId`/`fromEnrollmentId` are on the envelope → `discoverClients(
   enrollmentId:)` + match), consult an app-settable **answer policy**
   (default: answer only same-atSign clients of an *approved* enrollment for
   the namespace — which the server already gates), respond via
   `shareSecretWith`. Guard against answering your own request and against
   request storms (per-(clientId,name) rate cap).
   *Target:* new code beside `pairwise_secret_sharing.dart:372`.
4. **`onNewClientDiscovered` roster watch** — periodic `discoverClients(
   namespace:)` diff per registered namespace, emitting new `(clientId,
   ClientKeyPackage)`. Lets a holder *push* current epoch keys to a client
   that just appeared (complements pull). Not strictly required by the
   rotating provider — it always knows to request `__rk.current` — but needed
   for the second-client-on-existing-enrollment case and for generic app
   secrets.
   *Target:* `pairwise_secret_sharing.dart` (alongside the sync listener).
5. **`CryptoPolicy.onDecryptFailed`** — a hook the runtime calls when a
   provider's `decrypt` throws, returning throw / skip / retry-after-sync.
   The group provider's decrypt-miss path uses it to choose between blocking
   on `waitForSecret` and surfacing a typed `CryptoKeyUnavailableException`.
   *Targets:* `crypto.dart:107` (add method), `crypto_runtime.dart` (call it
   in `_decrypt`).

## 3. `SecureGroup` interface

A stable contract with two implementations over time (v1 `PairwiseGroup`
here; v2 `MlsGroup` in Phase 5). v1 keeps it minimal and honest — membership
is *derived* from the substrate roster, not managed by explicit add/remove
(those arrive with MLS in v2).

```dart
abstract class SecureGroup {
  /// Deterministic, e.g. `self:<atSign>:<namespace>` — so concurrent
  /// first-use by two clients converges on the same group.
  String get groupId;

  /// The epoch this group will seal new data under.
  int get currentEpoch;

  /// AEAD-seal [plaintext] under the current epoch key (rotating first if
  /// the rotation policy says the epoch is stale).
  Future<Sealed> seal(Uint8List plaintext);

  /// Reverse [seal]. Resolves the epoch key by (epoch, kid); on a local
  /// miss, runs the pull-then-wait recovery, then throws
  /// [CryptoKeyUnavailableException] if still unavailable.
  Future<Uint8List> open(Sealed sealed);

  /// Mint a new epoch key and distribute it to current members, excluding
  /// [excludeEnrollmentIds] (revocation). Any member may call this.
  Future<void> rotate({Set<String> excludeEnrollmentIds});

  /// HKDF a deterministic secret bound to the current epoch, for app use
  /// (e.g. NoPorts session keys). Same (label, length, epoch) → same bytes
  /// for every member.
  Future<Uint8List> export(String label, int length);
}

class Sealed {
  final int epoch;
  final String kid;     // names the epoch key (sha256 prefix of key bytes)
  final Uint8List iv;   // 12-byte GCM nonce
  final Uint8List ciphertext;
}
```

`Sealed` ↔ `AppMetadata.additional` is a 1:1 map (§5).

## 4. `PairwiseGroup` v1

Scope = **(atSign, namespace)**; `groupId = 'self:<atSign>:<namespace>'`.
Backed entirely by the substrate — no new storage.

**Epoch keys as Secrets** (in the scope's namespace, reserved `__` names):
- `__rk.<epoch>.<kid>` → `{"v":1,"alg":"aes-256","key":"<b64-32B>"}` —
  immutable, one per epoch key, written with `allowReservedName: true`.
- `__rk.current` → `{"epoch":N,"kid":"<kid>","createdAt":"<iso>"}` — the only
  mutable pointer; `putIfNewer` gives newest-`createdAt`-wins convergence for
  free, and the provider additionally refuses to move its local pointer
  backward in `epoch`.

`kid = sha256(keyBytes)[:8 bytes hex]` — **kid is the truth, epoch an
ordering hint.** Two clients can concurrently mint "epoch N+1" with different
keys; both `__rk.<N+1>.<kidA>` / `<kidB>` survive (distinct names), every
ciphertext carries its own `(epoch, kid)`, and the pointer converges. No
coordination protocol.

**Membership** = `discoverClients(namespace: scope)` at distribution time
(minus `excludeEnrollmentIds`). No explicit add/remove in v1: a newly-
registered client of an authorized enrollment simply appears in the roster;
it gets keys by the pull flow on first decrypt-miss (and/or push via the
roster watch).

**Operations:**
- `seal(pt)`: ensure a current epoch exists (else `rotate` to create epoch 1);
  if `RotationPolicy.maxEpochAge` exceeded, `rotate` first; GCM-encrypt under
  the current key with a fresh 12-byte nonce → `Sealed`.
- `open(sealed)`: look up `__rk.<epoch>.<kid>` in the scope; hit → GCM-
  decrypt; miss → send a `kind:'request'` for that name to namespace clients,
  `waitForSecret(scope, '__rk.<epoch>.<kid>', timeout)`, retry; still miss →
  `CryptoKeyUnavailableException`.
- `rotate({exclude})`: `K=32 random bytes`, `kid`, `epoch=current+1`;
  `putSecret` both Secrets (reserved); `discoverClients(namespace: scope,
  excludeEnrollmentIds: exclude)` → `shareSecretWith` both to each. Offline
  members catch up via pull.
- `export(label, n)`: `Hkdf(hmac: Hmac.sha256(), outputLength: n)` over the
  current epoch key with `info = utf8(label)`, `nonce = utf8(groupId)`
  (salt). Deterministic across members at the same epoch.

`RotationPolicy{Duration? maxEpochAge, bool rotateOnRevocation=true}` —
manual + revocation-triggered by default; time-based enforced lazily at
`seal`. No scheduler, no leader.

## 5. The `group` CryptoProvider

`id = 'group'`. A thin adapter from the `CryptoProvider` contract to a
per-scope `PairwiseGroup`. (Phase 5's pq-mls provider is a *separate* id,
e.g. `'mls'`, so the two coexist by id.)

```
initialize(ctx):
  _sharing = AtClientSecretSharing.forClient(ctx.atClient)   // shared identity
  await _sharing.startListening()
  // groups are materialized lazily per scope on first seal/open

encrypt(req):
  scope = req.atKey.namespace            // the (atSign,namespace) scope
  assert self-key (sharedWith == null || == currentAtSign)  // §7
  await _ensureRegistered(scope)         // additive registerClient([scope])
  group = _groupFor(scope)
  sealed = await group.seal(utf8(req.plaintext))
  return CryptoEncryptResult(
    ciphertext: base64(sealed.ciphertext),
    metadata: AppMetadata(providerId:'group', additional:{
      'scope': scope, 'epoch': sealed.epoch, 'kid': sealed.kid,
      'enc': 'aes-256-gcm', 'iv': base64(sealed.iv)}),
    isEncrypted: true)

decrypt(req):
  a = req.metadata.additional
  group = _groupFor(a['scope'])
  pt = await group.open(Sealed(epoch:a['epoch'], kid:a['kid'],
                               iv:base64Decode(a['iv']),
                               ciphertext:base64Decode(req.ciphertext)))
  return CryptoDecryptResult(plaintext: utf8.decode(pt))
```

`AppMetadata.additional` shape: `{scope, epoch, kid, enc, iv}` — `enc`
present for agility (Phase 6 swaps it without schema change). `additional` is
flat-serialized by `AppMetadata.toJson` (at_key.dart:852), so these keys go
straight onto the wire metadata.

**Routing back:** `CryptoRuntime` already routes decrypt by
`appMetadata.providerId` (crypto_runtime.dart) — a value sealed by `group`
returns to `group`. No runtime change needed beyond the `onDecryptFailed`
hook (#5).

## 6. Why epoch keys live in `SecretStore`, not `CryptoStorage`

`CryptoStorage` (crypto.dart:153) is a generic secondary-backed K/V for
provider state. The group provider deliberately does **not** use it for epoch
keys, because epoch keys need *distribution to other clients*, which is
exactly what the `SecretStore` + envelope machinery already does (with
namespace authorization, newest-wins merge, pull recovery). Putting them in
`CryptoStorage` would re-implement distribution. `CryptoStorage` may still be
used later for purely-local provider bookkeeping (e.g. a rotation timestamp);
not needed in v1.

Persistence of epoch keys at rest = `SecretStorePersistence`, wired once via
`AtClientSecretSharing.forClient(persistence:)` (the app supplies platform
keystore / biometric storage). The `__rk.*` names are reserved-system so app
code can't collide.

## 7. Lifecycle, boundaries, and `selfEncryptionKey` retirement

- **Self-encryption only (v1).** `encrypt` asserts `sharedWith == null ||
  sharedWith == currentAtSign`; anything else must be configured to route to
  `'legacy'` (cross-atSign is Phase 4). Apps set `defaultProviderId: 'group'`
  knowing it governs self keys; shared keys keep their own provider.
- **Creation** is lazy + leaderless (deterministic `groupId`); **membership**
  derives from the roster; **enrollment approval** seeds a new client via the
  existing `shareAllSecretsWithEnrollment` (now passing the `__rk.*` of every
  authorized scope); **revocation** = app revokes the enrollment then
  `rotate(excludeEnrollmentIds:{E})` for each scope E could read.
- **`selfEncryptionKey` retirement phases 1–2 begin here:** flipping
  `defaultProviderId` to `'group'` stops new self writes using
  `selfEncryptionKey` (phase 1); a lazy re-encrypt-on-touch / background
  sweep migrates old values (phase 2). Old values keep routing to `'legacy'`
  via `AppMetadata` — zero breakage. Phases 3–4 (stop conveying it; stop
  generating it) are later and touch at_auth — out of scope here.

## 8. Open decisions (resolve before / during build)

1. **Provider id** — `'group'` (chosen) vs `'rotating'` (older roadmap text).
   `'group'` matches the Phase-3 heading and leaves room for `'mls'` in
   Phase 5. *Recommend `'group'`.*
2. **`export()` salt/info binding** — proposal: `info=label`,
   `salt=groupId`. Confirm this matches what NoPorts tier-1 needs (both sides
   derive `c2d:<sessionId>` / `d2c:<sessionId>`).
3. **Answer-policy default for `kind:'request'`** — proposal: answer only
   same-atSign requesters whose enrollment is approved for the namespace
   (server already enforces deliverability; this is defense-in-depth +
   anti-storm). Confirm before building #3.
4. **Pull vs push for late joiners in v1** — pull (request `__rk.current` on
   first miss) is sufficient and simplest; the roster watch (#4) is a
   proactive complement. *Recommend pull-primary for v1, roster-watch
   optional.*
5. **`CryptoKeyUnavailableException`** — new typed exception in at_client (or
   reuse an at_commons one?). *Recommend new, under the crypto package.*

## 9. Implementation plan (commit sequence)

Substrate additions first (each green before the next), then the group:

1. `feat(at_client): SecretStore.listSecrets namePrefix filter` (+test).
2. `feat(at_client): excludeEnrollmentIds on discovery and sharing` (+test).
3. `feat(at_client): request/response pull flow with answer policy` (+test) —
   the reserved `kind` values become live.
4. `feat(at_client): onNewClientDiscovered roster watch` (+test) — optional;
   can defer if pull-primary holds.
5. `feat(at_client): CryptoPolicy.onDecryptFailed hook` (+test) — at_client
   crypto seam.
6. `feat(at_client): SecureGroup + PairwiseGroup v1` (+unit tests over the
   mocked-remote harness: rotate, concurrent-rotate convergence, open-miss →
   pull → recover, export determinism, revocation exclusion).
7. `feat(at_client): group CryptoProvider` (+tests: put/get round-trip via
   CryptoRuntime, AppMetadata shape, self-key assertion, decrypt-miss policy).
8. `feat(at_client): example + functional test` — two clients, one atSign:
   client A puts under `group`, rotates; client B reads; revoked client can't
   read post-rotation (functional, vs virtualenv).

## 10. Verification

- Unit (mocked remote, the `full_stack_test`/secret-sharing harness pattern):
  every substrate addition; group rotate/open/export/recover/revoke; provider
  round-trip through `CryptoRuntime`.
- Crypto correctness: GCM AEAD already vector-verified; `export()` HKDF
  determinism across two independently-constructed groups at the same epoch.
- Functional (virtualenv, `docker compose down` first): put-under-group →
  sync → second client reads; rotation → evicted enrollment blocked.
- Regression: full at_client suite stays green; the secret-sharing and
  isEncrypted/`shouldEncrypt=false` invariants unaffected.
- End-to-end gate (deferred): real-atServer round-trip of `appMetadata`
  depends on the at_server work (separate session).
