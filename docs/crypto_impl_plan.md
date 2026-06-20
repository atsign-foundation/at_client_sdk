# Crypto implementation plan

The detailed, living implementation plan for the post-quantum / group-first
encryption work. Its companion is [`crypto-roadmap.md`](crypto-roadmap.md) —
**the roadmap is the design source of truth** (goals, architecture, phasing,
and the *why*); **this file is the build plan** (task breakdown, ordering,
dependencies, PR carving, and acceptance — the *how* and *when*).

By intent this plan is **much more detailed for Deliverable 1 (D1 — PQ-safe
messaging)**, which is the near-term build; **Deliverable 2 (D2 — pq-mls)** is
left as **sparser placeholders that call out where detailed planning is still
required**. See the roadmap's
[two deliverables](crypto-roadmap.md#the-two-major-deliverables).

---

## 1. Current state (2026-06-20)

### Branches & delivery model (trunk-based)
- **Trunk is the single integration point.** Each work package is a short-lived
  branch **merged to `trunk` when complete**, and **published to pub.dev as
  needed** in dependency order (§7). No long-lived shared integration branch.
- **When the full stack needs proving before a batch lands**, spin up an
  *ephemeral* integration branch on demand (merge the in-flight WP branches, run
  the e2e rigs, discard) or rely on CI — not a standing branch.
- **`gkc-pqmls-spike`** is now just a **personal working branch + historical
  context** (it holds the pre-trunk-based integration of the in-flight work:
  `5493f6504` = `origin/xl-pluggable` `391f55f67` (the 4b base / PR #1930) **+
  51 cherry-picked commits**: secret sharing, the `group` provider,
  `onDecryptFailed`, the Phase-6 at_chops migration, the CRAM test). That work
  flows to trunk as its WPs complete.
- These **docs live on `trunk`** (canonical, shared, edited via small PRs).
- Sibling repos: `at_server` and `sshnoports` carry their changes on their own
  working branches.
- **PR #1976 is a frozen checkpoint**, not a merge target.

### Publish sequence (dependency-ordered) — status
1. **`at_commons 5.11.0`** (`Metadata.appMetadata` wire field) — **MERGED
   (#1981), published 5.11.0.**
2. **`at_chops`** (X-Wing KEM, AES-256-GCM, HKDF/HMAC, key-class consolidation)
   — **MERGED (#1982), published 3.2.1.**
3. **`at_persistence_secondary_server`** (commit-log-free client keystore +
   `appMetadata`, from `at_server`) — **MERGED (#2673), published 5.0.0 + 5.1.0.**
   The atServer supports `appMetadata` on the live fleet (virtualenv image, CI
   atSigns, canary).
4. **`at_client 3.x`** — in progress:
   - **(4a)** commit-log-free persistence migration — **MERGED to trunk (#1984).**
   - **(4b)** pluggable crypto — **PR #1930, OPEN + green** (`origin/xl-pluggable
     @ 391f55f67`, on `^5.1.0`, incl. the Mode-B reconcile fix).
   - **(4c)** secret sharing + the `nskey`/D1 Tier1 work below — **lands on
     trunk as its work packages complete** (§7); currently integrated on
     `gkc-pqmls-spike` for early verification.

### What is already built on the integration branch (the D1 foundation)
- **M0 pluggable crypto seam:** `CryptoProvider{id, initialize, encrypt,
  decrypt}`; `CryptoRuntime` dispatches put/get/notify/sync by
  `appMetadata.providerId`; `CryptoConfig` in `AtClientPreference`;
  `CryptoStorage`; `LegacyCryptoProvider`; `CryptoPolicy.onProviderNotFound` /
  `onDecryptFailed`. Wire field `Metadata.appMetadata`. **This is the migration
  machinery** the whole rollout rides.
- **Secret-sharing substrate (PQ-native):** per-client X-Wing `ClientKeyPackage`
  / `PackageKey`; namespace-scoped registration + discovery
  (`registerClient` / `discoverClients(namespace:)`, server-gated);
  AES-256-GCM `__ssenv.<ns>` envelopes (open-coded encapsulate+GCM today —
  **consolidate onto `pqSeal`/`pqOpen`** once #1993 lands, D1-A); in-memory
  `SecretStore` (app-pluggable persistence); `requestSecretsFromNamespace` pull
  flow; `waitForSecret`; `excludeEnrollmentIds`; reserved `__` system-secret
  names.
- **`group` provider (D1 Tier2 self):** `SecureGroup`/`PairwiseGroup` v1 + the
  `group` `GroupCryptoProvider`; `__rk.<epoch>.<kid>` epoch keys; scope
  `self:<atSign>:<namespace>`. Self-encryption only today (refuses shared keys).
- **at_chops PQ primitives:** X-Wing (ML-KEM-768 + X25519), AES-256-GCM,
  HKDF-SHA256, HMAC — vector-verified.
- **Persistence:** commit-log-free 5.x keystore.
- **Phase 6:** at_client / at_lookup / at_auth / at_onboarding_cli route all
  security crypto through at_chops; CI gate enforces it. (Record in §6.)

### Phase status (cross-ref roadmap [Milestones](crypto-roadmap.md#milestones-and-capabilities))
| Phase / Milestone | Status |
|---|---|
| 0 — foundations (secret sharing, pluggable crypto, jt-pq) | **Done** (rebuilt on xl-pluggable) |
| 1 — PQ primitives in at_chops (X-Wing, GCM, HKDF, HMAC) | **Done**; remaining: PQ enrollment-conveyance pubkey |
| 2 — identity layer (KeyPackages + per-client AtKeys) | KeyPackage framing **done**; AtKeys device-local split + identity resolution: not started (mostly D2 / D1 Tier2) |
| 2.5 — at_persistence 5.x migration | **Done & verified** |
| 3 — `SecureGroup` v1 + `group` provider (self) | **Built (D1 Tier2 self)**; D1 Tier1 `nskey` self is **new D1 work** (§3) |
| 4 — cross-atSign shared | D1 Tier1 `nskey` shared is **new D1 work** (§3); per-client pair group is D1 Tier2 / D2 |
| 5 — pq-mls engine | **D2 placeholder** (§4) |
| 6 — at_chops sole security-crypto dependency | **Complete** (in-scope) |

---

## 2. D1 acceptance — what "done" means

D1 is done when, per the roadmap
([D1 tiers](crypto-roadmap.md#d1--preserving-legacy-simplicity-two-tiers) +
[migration](crypto-roadmap.md#application-migration--rollout)):

1. An app **rebuilt with no code change** reads all legacy + PQ data and stays
   fully compatible with un-upgraded peers (universal-reader property).
2. **One readiness-flag flip** makes the app's new data PQ-safe (`nskey`) and
   namespace-scoped, negotiated down automatically for un-upgraded peers.
3. The legacy developer experience is preserved: *Alice shares with `@bob`;
   every bob client with namespace access, present and future, decrypts
   instantly, offline, with full history* — now PQ + namespace-scoped, with **no
   `SecureGroup` / `KeyPackage` / `clientId` / lock in the app's face**.
4. `selfEncryptionKey` and `shared_key.*` are on the retirement path; the
   **`disallowLegacyEncryption`** construction-time flag (default `false` in
   3.x, `true` in 4.0) lets a client forbid legacy-provider encryption, with a
   `SHOUT` log at creation whenever it is `false`
   ([versioning](crypto-roadmap.md#versioning-contract--the-legacy-encryption-flag-3x-default-off-4x-default-on)).
5. The **usability acceptance test** holds at each milestone (§5): no new flag a
   user must pass, file a user must manage, operator step, or peer-by-peer break.

The substantive *new* D1 build is the **`nskey` provider (D1 Tier1)** and the
**migration/versioning machinery** — the foundation (§1) already exists.

---

## 3. D1 — detailed implementation plan

Workstreams are roughly ordered; B is the centrepiece. Each task notes its
artifact and acceptance. Design references point at the roadmap. **D1-S
(structural enablers) lands first** — the `nskey` provider (D1-B) is built on
`WritableAtKeys` + stateless AtChops.

### D1-S · Structural enablers (prerequisite — lands first)
Design: roadmap
[Component responsibilities & WASM-readiness](crypto-roadmap.md#component-responsibilities--wasm-readiness).
The responsibilities reshape + the `at_auth` WASM split. Sequenced **before**
the feature workstreams; only `at_auth` takes a major bump (see the roadmap's
version/sequencing table).

- [ ] **S1 · AtChops stateless core + `@Deprecated` shim** (`at_chops` minor
  `3.3.0`). Add a stateless functional surface (keys passed per call; the
  primitive algos already pure or trivially made so); keep `AtChopsImpl(keys)`
  as a `@Deprecated` shim over it so the ~65 construction sites compile
  unchanged and migrate gradually. *Acceptance:* all at_chops vectors green via
  both surfaces; consumers unbroken.
- [ ] **S2 · `WritableAtKeys` holder + explicit dumb stores** (`at_auth`). The
  unified in-memory holder (`add`/`remove`/`write`); composed at AtClient
  construction; convergence stays in the secret-sharing substrate. Stores:
  `InMemoryAtKeysIo` (at_auth main), `FileAtKeysIo` (at_auth_io — updatable, see
  S4), `LocalKeystoreAtKeysIo` (at_client, injected), `KeychainAtKeysIo`
  (at_client_flutter). *Acceptance:* a provider can mint→add→write a key and
  read it back next run for a persistent client; ephemeral keys stay in-memory.
- [ ] **S3 · Make `.atKeys` / keychain *updatable*** (`at_auth` / flutter).
  `WrittenAtKeysIo` gains an update path (today write-once: `FileAtKeysIo`
  throws if the file exists); re-do the self-enc-key wrapping on rewrite; atomic
  write + backup. Keychain already appends. *Acceptance:* a post-onboarding key
  add persists to `.atKeys` and survives restart; migration test on a v(N-1)
  fixture.
- [ ] **S4 · `at_auth` WASM barrel split → core compiles under `dart2wasm`**
  (`at_auth` **major `4.0.0`**). Move `FileAtKeysIo` + the `dart:io` probe to a
  new **`at_auth_io.dart`** non-wasm barrel; drop the `atKeysIo ??=
  FileAtKeysIo()` default (require injection); extract `_defaultProbeSocket`;
  migrate the registrar to **`package:http`**. *Acceptance:* `dart compile wasm`
  succeeds against the `at_auth.dart` core; CLI + flutter (importing
  `at_auth_io.dart`) unbroken; auth/onboard functional tests green.
- [ ] **S5 · Providers onto `WritableAtKeys`** (`at_client` minor `3.14.0`).
  `CryptoContext` gains a `WritableAtKeys` field (additive; `atChops`
  `@Deprecated`); `LegacyCryptoProvider` reads keys from it; `LocalKeystoreAtKeysIo`
  lands here and is injected into `WritableAtKeys` at AtClient construction.
  *Acceptance:* legacy + group providers operate via `WritableAtKeys`; existing
  unit/functional suites green.
- [ ] **S6 · Consumer constraint bumps + sequencing.** `at_client` /
  `at_onboarding_cli` (`1.17.0`) / `at_client_flutter` (`1.2.0`) /
  `at_cli_commons` adopt `at_auth ^4.0.0`; publish in dependency order
  (at_chops → at_auth → at_client/onboarding/flutter → at_cli_commons). Roadmap
  version table is authoritative.

### D1-A · Finish the PQ primitives (small)
- [ ] **HPKE seal/open over X-Wing** (`at_chops`, from **PR #1993** once the
  requested changes land). `pqSeal(recipientPubKey, plaintext, {info, aad})` /
  `pqOpen(recipientSecretKey, envelope, …)` — KEM = X-Wing, KDF = HKDF-SHA256,
  AEAD = AES-256-GCM; **stateless**, KEM injected, single-shot derived nonce.
  The one audited PQ public-key-encryption primitive. **Merge conditions** (the
  #1993 review): add tests (round-trip · tamper→`authFailure` · `info`/`aad`
  mismatch · version/malformed); **reuse at_chops's existing
  `AesGcm256EncryptionAlgo` / `HkdfSha256` / `HmacSha256`** rather than
  re-importing `package:cryptography`; keep the primitive **protocol-agnostic**
  (make the NoPorts `pqDerive*` helpers label-generic or hoist them up);
  dartdoc as HPKE-*style* (custom envelope, not RFC-9180 wire). Lands
  **additively in the `at_chops 3.3.0` minor** — a down-payment on D1-S/S1's
  stateless surface. *Consumers:* B2 (`nskey`) and the `__ssenv` substrate
  seal/open **through this** (no open-coded encapsulate+GCM).
- [ ] **PQ enrollment-conveyance public key.** Publish an X-Wing pubkey
  alongside `public:publickey@alice` (e.g. `public:publickey.pq@alice` or a
  key-list); new enrollees prefer it for wrapping `apkamSymmetricKey`; approvers
  accept either. Closes the last harvest-now-decrypt-later hole; **no server
  change.** Design: roadmap
  [Phase 1](crypto-roadmap.md#phase-1--complete-the-pq-primitives-at_chops).
  *Acceptance:* enrollment round-trip uses X-Wing when both sides support it,
  falls back to RSA otherwise; functional enrollment test green.
  *Note:* this same atSign-level PQ key is the **cold-start fallback** for
  `nskey` (D1-B4) — build it first.

### D1-B · The `nskey` provider (D1 Tier1 — the default)
Design: roadmap
[D1 Tier1](crypto-roadmap.md#d1-tier-1--baseline-the-nskey-provider-default). New provider
on the M0 seam; legacy-shaped (copyable, enrollment-granular), PQ + namespace
-scoped. Build order:

- [ ] **B1 · Namespace keypair.** A per-`(atSign, namespace)` X-Wing keypair.
  - Type + storage: the private key held by every client of a namespace
    -authorized enrollment; new clients receive it at **enrollment approval**.
  - *Optional* deterministic derivation: `HKDF(master-seed, namespace [, epoch])
    → X-Wing seed`, so any client of the atSign derives the private key with **no
    distribution** (master seed is in `.atKeys`). Note the limit: alice cannot
    derive bob's per-namespace *public* key from his master public key (ML-KEM
    has no public child-derivation) — so the public key must still be published.
  - Publication: the first upgraded client publishes
    `public:<ns>.encryptionpublickey@<atSign>` (or a hidden public key);
    signed by the publishing enrollment.
  - *Acceptance:* a second client of the same atSign, authorized for the
    namespace, can obtain the private key (at approval or by derivation) and
    decrypt data sealed to the public key.
- [ ] **B2 · `nskey` `CryptoProvider`.** Encrypt/decrypt over the seam, sealing
  via **`pqSeal`/`pqOpen`** (D1-A) — do not open-code encapsulate+GCM.
  - **Self** → `pqSeal` the value's data key to *your own* namespace public
    key. **Shared** → `pqSeal` to the *recipient's* namespace public key. One
    code path, both directions. `selfEncryptionKey` and `shared_key.*` both
    collapse into "encrypt to the namespace keypair." Bind the scope via HPKE
    `info` (e.g. `groupId`/namespace) so an envelope can't be replayed cross-scope.
  - `appMetadata(providerId: 'nskey', additional: {ns, kid, env})` — `env` is the
    `pqSeal` envelope (carries the KEM ct + AEAD body); no separate `iv`/`kemCt`.
  - *Acceptance:* unit round-trips (self + shared); byte-exact decrypt; binary
    -safe (seal/open bytes, honour `isBinary` — do **not** repeat the
    `utf8.encode(toString())` bug, see §3 D1 Tier2 shape tasks).
- [ ] **B3 · Capability marker + per-destination negotiation.** Per-`(atSign,
  namespace)` published marker `{nskey: true, nskeyPubKid, …}`, **initially
  not-ready**; the sender reads the recipient's marker (+ its own, for self
  copies) and selects the scheme. Design: roadmap
  [Mixed-tier](crypto-roadmap.md#mixed-tier-alice--bob) + migration §.
  *Acceptance:* sender writes `nskey` only when the readers' marker is ready,
  legacy otherwise; mixed-fleet test (one legacy reader ⇒ legacy write).
- [ ] **B4 · Cold-start fallback + lazy upgrade.** When the recipient has no
  namespace key published, encapsulate to the **atSign-level PQ key** (D1-A);
  first namespace run mints/derives + publishes the namespace key; subsequent
  writes upgrade. Design: roadmap
  [Cold-start](crypto-roadmap.md#cold-start--bob-has-never-run-an-at_talk-app).
  *Acceptance:* alice→bob (bob never ran at_talk) is PQ (atSign-level) and
  readable by any bob at_talk client; upgrades to namespace-scoped after bob's
  first run. Strict-mode alternative (seal-and-hold) is a policy toggle (D1-C).
- [ ] **B5 · Opt-in rotation.** Mint a new namespace keypair → publish new
  public key → write the new private key as `__nsk.<epoch>` over the
  **per-enrollment** self-group secret channel (PQ-wrapped to each at_talk
  enrollment's conveyance key); reuse the built `__`-secret substrate +
  `requestSecretsFromNamespace` (push) + pull. Design: roadmap
  [Opt-in rotation](crypto-roadmap.md#opt-in-key-rotation-d1-tier1).
  *Buys:* namespace-granular **post-compromise security**; **not** FS / history
  re-encryption (old private keys retained → history-on).
  *Acceptance:* after rotation, new writes use epoch N+1; all current at_talk
  clients converge; a pre-rotation key reads nothing post-rotation.
- [ ] **B6 · Revocation wiring.** Compose: (1) enrollment revocation (APKAM —
  free, cuts future server access); (2) rotation **excluding** the revoked
  enrollment (`excludeEnrollmentIds`); (3) optional re-encrypt of history
  (expensive — D1 Tier2/D2). Design: roadmap
  [Revocation](crypto-roadmap.md#revocation-end-to-end).
  *Acceptance:* a revoked enrollment, excluded from a rotation, cannot read
  post-rotation data.
- [ ] **B7 · `selfEncryptionKey` + `shared_key.*` retirement (four phases).**
  Default-flip → lazy re-encrypt on touch → stop conveying → (v4) stop existing.
  Design: roadmap
  [Retiring selfEncryptionKey](crypto-roadmap.md#retiring-selfencryptionkey-and-shared_key).
  All but the last phase live in 3.x; the last is the v4 flag (D1-D).

### D1-C · Migration & rollout machinery
Design: roadmap
[Application migration & rollout](crypto-roadmap.md#application-migration--rollout).
- [ ] **C1 · Readiness-marker lifecycle.** Publish (not-ready) on upgrade; flip
  ready when the fleet is upgraded — operator-declared (one config/policy call)
  and/or auto-detected ("no legacy client checked in"). The SDK warns on a flip
  while a recent legacy check-in exists. *This is the "minimal (flag) code"
  capability tier.*
- [ ] **C2 · Negotiation default.** Rebuild stays **behaviour-neutral** (reads
  all schemes, keeps writing legacy) until the readiness flag flips — so a bare
  rebuild is a zero-risk soak. (An aggressive "prefer-best on rebuild" default is
  possible but off by default; see the capability table footnote.)
- [ ] **C3 · Strict-mode toggles (simple-code tier).** `CryptoPolicy` options:
  refuse legacy fallback / require PQ in cold-start (seal-and-hold vs error vs
  notify); custom rotation triggers. These are app-facing in 3.x — alongside
  `disallowLegacyEncryption` (D1-D), which is the dedicated legacy-write switch.
- [ ] **C4 · Capability conformance.** Implement so the
  [capabilities table](crypto-roadmap.md#capabilities-by-application-code-change-level)
  holds: no-code = universal reader + back-compat; flag = PQ writer/recipient;
  code = override defaults / D1 Tier2.

### D1-D · Versioning (the `disallowLegacyEncryption` flag)
Design: roadmap
[Versioning contract](crypto-roadmap.md#versioning-contract--the-legacy-encryption-flag-3x-default-off-4x-default-on).
- [ ] **D1 · All D1 lands in 3.x** — additive, backwards-compatible; a 3.x
  client may write legacy when a reader isn't PQ-ready.
- [ ] **D2 · The `disallowLegacyEncryption` flag** on `AtClientPreference`.
  Means literally "never write new data using the legacy provider for
  encryption." **Final at AtClient construction** (immutable for the client's
  lifetime). **Defaults `false` in 3.x, `true` in 4.0.** When `false`, the SDK
  **emits a `SHOUT` log at AtClient creation**. Scope is literal — it governs
  only legacy-provider *encryption*; legacy **read** and the
  `shouldEncrypt=false` *no-encryption* path are unaffected
  ([confidentiality](crypto-roadmap.md#what-the-atserver-can-and-cannot-see)).
  *Acceptance:* with the flag `true`, no write uses the legacy provider (test:
  every write's `appMetadata.providerId ∈ {nskey, group}` or the PQ fallback; a
  legacy-only recipient causes a refused write, never a legacy write; legacy
  **read** still works; the flag cannot be mutated after construction). With the
  flag `false`, a single `SHOUT` is logged at creation.
- [ ] **D3 · `at_client 4.0` = final 3.x + flip the flag's *default* to `true`
  + general dead-code removal** (deprecated stream/file methods etc.; the legacy
  provider itself **stays** — needed for reads always and for writes when the
  flag is `false`). Gated on the ecosystem floor.

### D1-E · D1 Tier2 shape-corrections (cheap-now, carry into D2)
The `group` provider exists (D1 Tier2 self). These keep its shape honest before
the self→shared and MLS transitions; do them while touching the area.
- [ ] **Lift membership into `SecureGroup`** (`members`/`add`/`remove`); v1
  derives them. Avoids a later breaking change to a published abstract.
- [ ] **Binary-safe `group` provider** — seal/open bytes, honour `isBinary`
  (currently `utf8.encode(plaintext.toString())` corrupts binary).
- [ ] **Rename `PairwiseGroup` → `SelfGroup`** to free "pair group" for the
  Phase-4 cross-atSign meaning.

### D1 · Test & acceptance plan
- Unit: `nskey` round-trips (self/shared/binary), negotiation matrix, rotation
  convergence, `disallowLegacyEncryption` enforcement (+ the creation-time
  `SHOUT` when `false`, + immutability after construction), cold-start fallback,
  the regression test
  pattern (a test that fails without the fix).
- Functional (live virtualenv): nskey self + shared, rotation, mixed-tier
  (nskey↔legacy), cold-start, enrollment-revoke + rotate-exclude.
- e2e (cross-atSign, `@ce2e*`): the `at_talk` chat scenario from roadmap
  [Appendix C](crypto-roadmap.md#appendix-c--a-two-atsign-chat-with-client-churn-at_talk-detailed)
  — alice1/2 ↔ bob1/2 bidirectional, then bob3/alice3 join (new + past
  messages). Run concurrently via the base-port `runLocal.sh` rigs (PR #1992).
- Usability acceptance test (§5) at each milestone.

### D1 · PR delivery / publish
Each work package is its own short-lived branch **merged to trunk when
complete**, with pub.dev **published as needed** in dependency order (§7) — 4c
(secret sharing) and the `nskey`/migration work land the same way, not carved
from an integration branch at the end. Overall publish order: roadmap
[Dependencies](crypto-roadmap.md#dependencies) + the version table.

---

## 4. D2 — pq-mls (placeholders; detailed planning deferred)

D2 swaps D1 Tier2's engine for MLS and adds the scaling/ordering infrastructure.
The **design** is in the roadmap; the **detailed build plan is intentionally
deferred** — each item below is a placeholder that **requires its own planning
pass** before implementation. Design refs:
[Deliverable 2](crypto-roadmap.md#deliverable-2--implement-pq-mls),
[Phase 5](crypto-roadmap.md#phase-5--pq-mls-engine-securegroup-v2),
[Delivery Service](crypto-roadmap.md#atserver-group-delivery-service-target-design).

> **⚠ DETAILED PLANNING REQUIRED** for every item in this section. Treat the
> bullets as scope markers, not a task breakdown.

- [ ] **Phase 4 (cross-atSign per-client pair groups) as D1 Tier2.** *Note:* D1's
  `nskey` covers cross-atSign **shared** data at enrollment granularity; the
  **per-client** `(pair, namespace)` group (per-device revocation/FS) is the
  D1 Tier2/D2 form. Greenfield: cross-atSign KeyPackage fetch+verify, consent
  hook, explicit membership, group state not derivable from one server. *Plan
  when starting D1 Tier2 cross-atSign.*
- [ ] **Phase 5 — MLS engine (`SecureGroup` v2).** Engine choice still open
  (openmls / mls-rs / pure-Dart); native bindings as a separate package so
  `at_client` stays pure Dart. Bootstrap from the same published KeyPackages;
  flip `groupId`/`providerId` on new writes; lazy re-encrypt on touch.
  **History vs forward-secrecy:** D1 is history-on (retained keys); MLS gives
  true FS, so "new member reads history" needs an explicit mechanism
  (re-encrypt-to-member or a separate history key) — *decide in the Phase-5
  plan.* *Plan: engine selection spike + binding package + state-ownership.*
- [ ] **atServer group Delivery Service.** Ciphertext-only group object
  (`ownerAcl` + plaintext roster + monotonic `seq` + TTL'd log) + verbs
  (`group:create/add/remove/members`, `group:append`, `group:fetch:since`);
  wake-then-pull O(member-atSigns); two retention classes + DS-minted
  tombstones. One design, two placements (dedicated DS atSign vs self-hosted on
  a member). Commit-ordering **DECIDED** (per-group `seq` = MLS total order).
  *Plan: atServer verb design + retention/ack + the membership-gated read
  capability.*
- [ ] **MLS engine state-ownership obligations.** Serialize crypto-state
  mutation within the `AtClientImpl` instance (a Commit can arrive mid-`seal()`);
  apply inbound handshake before sealing under the new epoch. Roadmap
  [Connection model & the MLS leaf](crypto-roadmap.md#connection-model--the-mls-leaf).
  *Plan with the engine integration.*
- [ ] **Per-client identity hardening (Phase 2 / D1 Tier2).** AtKeys device-local
  split (leaf keys never copied); client-identity resolution
  (label-keyed keysets, resume/fork/mint); **two-layer single-owner lock**
  (device-local file lock + atServer `(atSign, label)` lease w/ fencing token +
  TTL + heartbeat). MLS correctness precondition (one leaf per instance), not
  needed by D1 Tier1. Roadmap
  [Phase 2](crypto-roadmap.md#phase-2--identity-layer-keypackages-and-per-client-atkeys).
  *Plan with Phase 5.*

Guidance (carries from the roadmap): the v1 `PairwiseGroup` epoch engine + its
leaderless `kid`-is-truth convergence is **thrown away at the MLS swap** — don't
over-invest in hardening its concurrency; invest in interface / identity /
ordering decisions that carry forward.

---

## 5. Cross-repo PR / publish sequence & NoPorts

Nothing reaches NoPorts until the SDK ships in dependency order. Roadmap
[Dependencies](crypto-roadmap.md#dependencies).

1. `at_commons 5.11.0` — **done** (#1981) → 2. `at_chops 3.2.x` — **done**
   (#1982, 3.2.1) → 3. `at_persistence_secondary_server` + `at_secondary_server`
   — **done** (#2673; 5.0.0 + 5.1.0) → 4. `at_client 3.x` — **in progress**
   (4a merged #1984; 4b PR #1930; 4c + `nskey`/migration land on trunk as WPs
   complete) → eventual
   **`at_client 4.0`** (`disallowLegacyEncryption` default → `true` + dead-code
   removal) once the floor allows → 5. **`sshnoports`** consumes the released
   SDK (last).

**NoPorts adoption (finish line, mostly D2-gated).** Route session keys through
the group abstraction, daemon-feature-gated tiers 0–2; **target: zero
user-visible delta**. Tier 0 (transport PQ-safe) is reachable with the `nskey`
/ `group` path; tiers 1–2 (derive-don't-transmit, fleet self-group) lean on
D1 Tier2 / D2. Roadmap
[Upgrading NoPorts](crypto-roadmap.md#upgrading-noports-with-daemon-ping-feature-discovery)
+ Admission UX / User-visible-delta. *Detailed sshnoports plan: deferred.*

---

## 6. Standing verification & implementation record

### Verification (every touched package)
- `dart analyze --fatal-warnings`, `dart format`, `dart test --concurrency=1`.
- Crypto correctness: X-Wing draft vectors + GCM NIST vectors byte-exact.
- Functional: recycle virtualenv (`docker compose down` first — one-shot CRAM
  secrets) then the relevant `tests/at_functional_test` suite; e2e via the
  base-port `runLocal.sh` rigs.
- **Usability acceptance test:** a milestone is not done if it forces a new flag
  a user must pass, a file a user must manage, an operator step, or a
  peer-by-peer break. Roadmap
  [Usability](crypto-roadmap.md#usability--a-first-class-constraint).

### Record — Phase 6 (at_chops sole security-crypto dependency) — COMPLETE
Every in-scope consumer (at_client, at_lookup, at_auth, at_onboarding_cli)
routes encryption/signing/KDF through at_chops; `tools/check_crypto_imports.sh`
is the CI gate. Out of scope (whitelisted): `at_utils` (non-security naming hash,
leaf below at_chops — would be circular), `at_login_flutter` (being removed).
Time-boxed tail: at_client's two AES-on-`package:encrypt` files
(`encryption_util.dart`, `aes_converter.dart`) are deprecated-only and **deleted,
not migrated, at the v4 cut**. Commits: at_chops HKDF/HMAC `81b57f1c3`;
at_client batches `a04f5df9d` (+ later); at_lookup `2a58bc695`; at_auth
`59b50fd65`; at_onboarding_cli `5c8e5f050`; test fix `c3f3bb1b3`; gate +
whitelist (CI `crypto_import_gate`).

### Record — at_persistence 5.x migration — DONE
at_client moved to a commit-log-free 5.x keystore (factory/bundle bootstrap,
async keystore APIs, compaction removed, sync watermark = persisted pull cursor,
expiry timers on `nextExpiresAt`/`peekNewlyAvailable`). at_server
`gkc-app-metadata` merged `gkc-more-persistence-api`. Verified at the time:
analyze clean, 627 unit + 81/81 functional green; at_persistence 79 keystore
tests. Plan archived at `untracked/AT_PERSISTENCE_5_MIGRATION_PLAN.md`.

### Record — 4b refresh + Mode-B fix + rebuild (2026-06-18/19)
- **4b refresh** (`origin/xl-pluggable` `cc4e39107..b6944b6c6`): merged trunk
  into xl-pluggable (four conflicts resolved); bumped at_persistence to `^5.1.0`;
  cherry-picked `d78b2464f`; **required `LegacyDecryption` adaptation**
  (`af9d4d414`) — the 4.3.5→5.x keystore now *preserves* `appMetadata`, so a
  legacy-stamped value reads back non-null and the old `LegacyDecryption.build`
  threw; the fix also accepts `providerId == legacyProviderId`. **Lesson:**
  moving any older pluggable-crypto branch onto the 5.x keystore needs this
  adaptation; the cherry-pick alone is not enough. Verified 80/80 functional.
- **Mode-B flake fix** (`391f55f67` on xl-pluggable + spike): `setCurrentAtSign`'s
  idempotency short-circuit returned the cached `AtClient` without
  `reconcileCryptoProviders`, so a same-atSign re-set with a new provider config
  dropped it → intermittent `CryptoProviderNotRegistered`. Reconcile in the
  short-circuit + a deterministic regression test. **PR #1930 CI all green.**
- **e2e flake diagnosis:** three modes — A `@ce2e1` PKAM AT0401 (remote cicd
  infra, not an SDK bug; CI e2e runs against `@ce2e*`, not the local vip),
  B = the reconcile bug (fixed), C = notification-delivery timing. Lesson:
  diagnose e2e CI flakes from CI logs + code first; local repro against the
  stable vip is futile for A/C (80/80 local green).
- **Integration rebuild:** `gkc-pqmls-spike` rebuilt on `origin/xl-pluggable`
  (51 cherry-picks, 15 superseded commits dropped), force-pushed.
- **Supporting tooling (merged to trunk):** PR #1992 (base-port functional +
  e2e `runLocal.sh`); at_server #2677 (`Dockerfile.canary_to_vip` honours
  `VIRTUALENV_BASE_PORT`).

### ADRs
- [ADR 0001 — D1 delivers as two tiers](adr/0001-d1-simplicity-tiers.md).

## 7. Delivery plan & work packages

How the D1 work lands across **parallel tracks** with minimal merge friction.
Principle: **partition by package** (two tracks rarely edit the same file),
**land contracts first** (others build against stable shapes), keep merges
**additive / flag-gated** so trunk stays releasable. The work packages below map
onto the §3 workstreams (D1-S / D1-A…E); this is the parallelisation/sequencing
view.

### Tracks (package domains, not people)

- **Track A — crypto primitives + provider:** `at_chops` (stateless core +
  HPKE) → the `nskey` provider, `secret_sharing/`, `crypto/group/`.
- **Track B — key management:** `at_auth` (`WritableAtKeys`, `AtKeysIo`
  widening, the WASM barrel split) → PQ enrollment-conveyance key.
- **Track C — at_client crypto seam + migration:** `crypto.dart` /
  `crypto_runtime.dart` / `legacy/`, `AtClientPreference`; integration on
  `gkc-pqmls-spike`; the publish ladder.
- **Track D — storage + platform + consumers:** `LocalKeystoreAtKeysIo`, the
  updatable `.atKeys` file path, `at_onboarding_cli` / `at_client_flutter` /
  `at_cli_commons`.

Within `at_client/crypto/`, the file partition keeps A and C apart: **C** owns
`crypto.dart`, `crypto_runtime.dart`, `legacy/`; **A** owns `crypto/group/`,
`crypto/nskey/` (new), `secret_sharing/`. The `nskey` provider is mostly new
files — low collision by construction.

### Phase 0 — unblock (blocks everything)
- Land **PR #1930** (4b pluggable crypto) → trunk: the M0 seam in published
  at_client. **The single biggest unblock** — until it lands, the integration
  branch stays ahead of trunk.
- Revise + land **PR #1993** (HPKE) → trunk (`at_chops`).

### Phase 1 — contracts (small, fast-review PRs; all parallel, all additive)
| WP | Track | What | Bump |
|----|-------|------|------|
| WP1 | A | `at_chops` stateless core + `@Deprecated` shim; fold HPKE onto existing GCM/HKDF | `at_chops 3.3.0` |
| WP2 | B | `WritableAtKeys` + widen `AtKeysIo`/`WrittenAtKeysIo` (add/remove/update, default impls) + `InMemoryAtKeysIo` — **API only** | `at_auth 3.2.0` |
| WP3 | C | `CryptoContext` gains a `WritableAtKeys` field (additive; `atChops` `@Deprecated`) | at_client |
| WP4 | D | `LocalKeystoreAtKeysIo` + the updatable `.atKeys` file path | at_client / at_auth |

### Phase 2 — build on contracts (parallel)
| WP | Track | What | Bump |
|----|-------|------|------|
| WP5 | B | **`at_auth` WASM barrel split** — `at_auth_io.dart`, FileAtKeysIo move, default removal, probe extraction, registrar → `package:http` | **`at_auth 4.0.0`** (the one breaking cut) |
| WP6 | A | `nskey` provider on `pqSeal` + `WritableAtKeys` (new files) | at_client |
| WP7 | C | legacy provider reads `WritableAtKeys`; per-destination negotiation; `disallowLegacyEncryption` flag (default `false`) | at_client |
| WP8 | D | consumer bumps to `at_auth ^4.0.0` (onboarding / flutter / cli_commons) | minors — **gated on WP5** |

### Phase 3 — feature completion (parallel)
| WP | Track | What |
|----|-------|------|
| WP9 | A | nskey rotation / cold-start / revocation; `__ssenv` consolidation onto `pqSeal`; group shape fixes (binary-safe, lift membership, rename) |
| WP10 | B | PQ enrollment-conveyance public key |
| WP11 | C | migration machinery (readiness-marker lifecycle, strict-mode toggles); 4c secret-sharing carve-out |

### Phase 4 — integration is continuous, not a final step
Each WP **merges to trunk when complete** and is **published to pub.dev as
needed** in dependency order (roadmap version table). To prove the full stack
before a batch lands, **spin up an ephemeral integration branch on demand**
(merge the in-flight WP branches, run unit + functional + e2e via the base-port
`runLocal.sh` rigs, discard) or rely on CI — so cross-package issues surface
early, with no standing integration branch to drift.

### Critical path & merge discipline
- **Critical path:** #1930 → `at_auth 4.0` (WP5) → at_client seam (WP7) +
  `nskey` (WP6).
- **Interface-first:** the `pqSeal` signature (WP1), `WritableAtKeys` API (WP2),
  and `CryptoContext` field (WP3) are tiny PRs — merge them first (stubs OK) so
  every track compiles against stable shapes and never blocks on another.
- **Split the `at_auth` bump:** additive `3.2.0` (WP2) lands the `WritableAtKeys`
  API early; the breaking barrel split is a separate, telegraphed `4.0.0` (WP5)
  with consumer bumps (WP8) batched right behind it.
- **Rules:** per-package PRs to **trunk** in dependency order (no mega-PRs);
  rebase on trunk daily; keep PRs small + additive so trunk stays releasable;
  path `dependency_overrides` for local cross-package dev (don't commit lock
  churn); **trunk is the integration point** — prove cross-package combinations
  with an *ephemeral* integration branch (or CI), not a standing one.
