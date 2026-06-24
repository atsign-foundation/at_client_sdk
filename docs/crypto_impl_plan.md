# Crypto implementation plan

The detailed, living implementation plan for the post-quantum / group-first
encryption work.

> **This is the build plan** — task breakdown, ordering, dependencies, PR
> carving, and acceptance (the *how* and *when*). It has two companions, and the
> three docs share one shape (design → build → worked example):
>
> - **[crypto-roadmap.md](crypto-roadmap.md)** — the design source of truth
>   (goals, architecture, phasing, the *why*). On a design question, it wins.
> - **[crypto-walkthroughs.md](crypto-walkthroughs.md)** — worked end-to-end
>   examples (NoPorts, a large group, an `at_talk` chat).
>
> See the [document map](#document-map) for how the sections pair up.

## Table of contents

- [Document map](#document-map)
- [1. Current state (2026-06-22)](#1-current-state-2026-06-22)
  - [Branches & delivery model (trunk-based)](#branches--delivery-model-trunk-based)
  - [Publish sequence (dependency-ordered) — status](#publish-sequence-dependency-ordered--status)
  - [What is built vs prototyped — re-baselined](#what-is-built-vs-prototyped--re-baselined-assume-only-trunk--1930--1993)
  - [Phase status](#phase-status)
- [2. D1 acceptance — what "done" means](#2-d1-acceptance--what-done-means)
- [3. D1 — detailed implementation plan](#3-d1--detailed-implementation-plan)
  - [D1-S · Structural enablers (prerequisite — lands first)](#d1-s--structural-enablers-prerequisite--lands-first)
  - [D1-A · Finish the PQ primitives (small)](#d1-a--finish-the-pq-primitives-small)
  - [D1-B · The `nskey` provider (D1 Tier1 — the default)](#d1-b--the-nskey-provider-d1-tier1--the-default)
  - [D1-C · Migration & rollout machinery](#d1-c--migration--rollout-machinery)
  - [D1-D · Versioning (the `disallowLegacyEncryption` flag)](#d1-d--versioning-the-disallowlegacyencryption-flag)
  - [D1-E · D1 Tier2 shape-corrections](#d1-e--d1-tier2-shape-corrections-fold-into-wp-gp)
  - [D1-F · Existing-client retrofit — auth upgrade & secret conveyance](#d1-f--existing-client-retrofit--auth-upgrade--secret-conveyance)
  - [D1 · Test & acceptance plan](#d1--test--acceptance-plan)
  - [D1 · PR delivery / publish](#d1--pr-delivery--publish)
- [4. D2 — pq-mls (placeholders; detailed planning deferred)](#4-d2--pq-mls-placeholders-detailed-planning-deferred)
- [5. Cross-repo PR / publish sequence & NoPorts](#5-cross-repo-pr--publish-sequence--noports)
- [6. Standing verification & implementation record](#6-standing-verification--implementation-record)
  - [Verification (every touched package)](#verification-every-touched-package)
  - [Record — Phase 6 (at_chops sole security-crypto dependency) — COMPLETE](#record--phase-6-at_chops-sole-security-crypto-dependency--complete)
  - [Record — at_persistence 5.x migration — DONE](#record--at_persistence-5x-migration--done)
  - [Record — 4b refresh + Mode-B fix + rebuild (2026-06-18/19)](#record--4b-refresh--mode-b-fix--rebuild-2026-06-1819)
  - [ADRs](#adrs)
- [7. Delivery plan & work packages](#7-delivery-plan--work-packages)
  - [Tracks (package domains, not people)](#tracks-package-domains-not-people)
  - [Reconciliations since the slim refactor](#reconciliations-since-the-slim-refactor-xl-pluggable)
  - [The work-package sequence — single source for ordering](#the-work-package-sequence--single-source-for-ordering)
  - [Package versions & release sequencing](#package-versions--release-sequencing)
  - [Integration is continuous, not a final step](#integration-is-continuous-not-a-final-step)
  - [Critical path & merge discipline](#critical-path--merge-discipline)
  - [Wave-1 PR stubs (ready to assign once Wave 0 is on trunk)](#wave-1-pr-stubs-ready-to-assign-once-wave-0-is-on-trunk)

By intent this plan is **much more detailed for Deliverable 1 (D1 — PQ-safe
messaging)**, which is the near-term build; **Deliverable 2 (D2 — pq-mls)** is
left as **sparser placeholders that call out where detailed planning is still
required**. See the roadmap's
[two deliverables](crypto-roadmap.md#the-two-major-deliverables).

## Document map

How the three docs line up — **design** (the roadmap, the source of truth) ↔
**build** (this doc) ↔ **worked example** (the walkthroughs). Find your row and
jump.

| Topic | Design (roadmap) | Build (plan) | Worked example |
|---|---|---|---|
| The two deliverables (D1 / D2) | [The two major deliverables](crypto-roadmap.md#the-two-major-deliverables) | [Current state (1)](crypto_impl_plan.md#1-current-state-2026-06-22) · [D1 acceptance (2)](crypto_impl_plan.md#2-d1-acceptance--what-done-means) | — |
| D1 Tier1 — the `nskey` default | [D1 — preserving legacy simplicity](crypto-roadmap.md#d1--preserving-legacy-simplicity-two-tiers) | [D1-B (3)](crypto_impl_plan.md#d1-b--the-nskey-provider-d1-tier1--the-default) | — |
| Migration, rollout & versioning | [Application migration & rollout](crypto-roadmap.md#application-migration--rollout) | [D1-C / D1-D (3)](crypto_impl_plan.md#d1-c--migration--rollout-machinery) | — |
| Existing-client retrofit (auth + key dist) | [Existing-client retrofit](crypto-roadmap.md#existing-client-retrofit--auth-upgrade--key-distribution) | [D1-F (3)](crypto_impl_plan.md#d1-f--existing-client-retrofit--auth-upgrade--secret-conveyance) | — |
| Identity, KeyPackages, self groups | [Phases 2–3](crypto-roadmap.md#phase-2--identity-layer-keypackages-and-per-client-atkeys) | [D1-E (3)](crypto_impl_plan.md#d1-e--d1-tier2-shape-corrections-fold-into-wp-gp) · [D2 (4)](crypto_impl_plan.md#4-d2--pq-mls-placeholders-detailed-planning-deferred) | — |
| Cross-atSign shared groups | [Phase 4](crypto-roadmap.md#phase-4--cross-atsign-groups-shared-encryption) | [D2 (4)](crypto_impl_plan.md#4-d2--pq-mls-placeholders-detailed-planning-deferred) | [C — `at_talk` chat](crypto-walkthroughs.md#walkthrough-c--a-two-atsign-chat-with-client-churn-at_talk) |
| pq-mls engine + Delivery Service | [atServer group Delivery Service](crypto-roadmap.md#atserver-group-delivery-service-target-design) | [D2 (4)](crypto_impl_plan.md#4-d2--pq-mls-placeholders-detailed-planning-deferred) | [B — a large group](crypto-walkthroughs.md#walkthrough-b--a-large-group-end-to-end) |
| NoPorts adoption | [Upgrading NoPorts](crypto-roadmap.md#upgrading-noports-with-daemon-ping-feature-discovery) | [Cross-repo & NoPorts (5)](crypto_impl_plan.md#5-cross-repo-pr--publish-sequence--noports) | [A — NoPorts](crypto-walkthroughs.md#walkthrough-a--noports-end-to-end) |
| Structural enablers / WASM split | [Component responsibilities & WASM-readiness](crypto-roadmap.md#component-responsibilities--wasm-readiness) | [D1-S (3)](crypto_impl_plan.md#d1-s--structural-enablers-prerequisite--lands-first) | — |
| Release order & work packages | [Starting point](crypto-roadmap.md#starting-point) | [Work packages (7)](crypto_impl_plan.md#7-delivery-plan--work-packages) | — |

---

## 1. Current state (2026-06-22)

### Branches & delivery model (trunk-based)
- **Trunk is the single integration point.** Each work package is a short-lived
  branch **merged to `trunk` when complete**, and **published to pub.dev as
  needed** in dependency order ([section 7](#7-delivery-plan--work-packages)). No long-lived shared integration branch.
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
   - **(4b)** pluggable crypto seam (slim) — **PR #1930, OPEN + green.**
   - **(4c)** the secret-sharing substrate, `nskey` / D1 Tier1, and the `group`
     provider — **land on trunk as the [section 7](#7-delivery-plan--work-packages) work packages complete** (WP-SS /
     WP6 / WP-GP …); the spike (`gkc-pqmls-spike`) holds working prototypes.

### What is built vs prototyped — re-baselined: assume only trunk + #1930 + #1993

**In trunk (the real baseline):**
- **at_chops PQ primitives** — X-Wing (ML-KEM-768 + X25519), AES-256-GCM,
  HKDF-SHA256, HMAC — vector-verified (3.2.1).
- **Commit-log-free 5.x keystore** (at_client 4a; at_persistence 5.x).
- **Phase 6 — at_chops is the sole security-crypto dependency**: at_client /
  at_lookup / at_auth / at_onboarding_cli route all security crypto through
  at_chops; a CI gate enforces it (the four small PRs #1995–1998, **merged**).
  (Record in [section 6](#6-standing-verification--implementation-record).)

**In flight (open PRs — the rest of the foundation):**
- **M0 pluggable crypto seam** — **PR #1930** (at_client). Stateless
  `CryptoProvider{id, encrypt(ctx, atKey, plaintext)→String, decrypt(ctx, atKey,
  ciphertext)→String}`; `CryptoRuntime` resolves put/get/notify/sync against the
  **live** `AtClientPreference.crypto` (`CryptoConfig{defaultProviderId,
  providers, lookup}`) by `appMetadata.providerId`, with `LegacyCryptoProvider`
  as the built-in fallback; the SDK stamps `providerId`+`isEncrypted`; an unknown
  scheme throws `CryptoProviderNotRegistered`; cached-client reuse adopts the new
  `preference.crypto`. Wire field `Metadata.appMetadata`. **This is the migration
  machinery** the whole rollout rides.
- **HPKE `pqSeal`/`pqOpen`** — **PR #1993** (at_chops).

**Prototyped on `gkc-pqmls-spike` but NOT landed — first-class WPs ([section 7](#7-delivery-plan--work-packages)), not
foundation.** The spike has working code for these; treat re-landing it on trunk
as real work (carve-out + alignment to the slim seam + `pqSeal`):
- **Secret-sharing substrate (PQ-native)** → **WP-SS**: per-client X-Wing
  `ClientKeyPackage`/`PackageKey`; namespace-scoped registration + discovery
  (`registerClient` / `discoverClients(namespace:)`, server-gated); AES-256-GCM
  `__ssenv.<ns>` envelopes (open-coded encapsulate+GCM on the spike — **to
  consolidate onto `pqSeal`/`pqOpen`**); in-memory `SecretStore`;
  `requestSecretsFromNamespace`; `waitForSecret`; `excludeEnrollmentIds`;
  reserved `__` system-secret names.
- **`group` provider (D1 Tier2 self)** → **WP-GP**: `SecureGroup`/`PairwiseGroup`
  v1 + the `group` `GroupCryptoProvider`; `__rk.<epoch>.<kid>` epoch keys; scope
  `self:<atSign>:<namespace>`; self-encryption only (refuses shared keys).

*(The original `CryptoRegistry` / `CryptoPolicy` / `CryptoStorage` / `initialize`
/ Request-Result wrappers were removed in #1930's slim refactor; the
`cryptoRegistry` getter is off the `AtClient` spec.)*

### Phase status
Cross-ref roadmap [Milestones](crypto-roadmap.md#milestones-and-capabilities).
"Prototyped on spike" means working code on `gkc-pqmls-spike` that is **not in
trunk** — first-class work to land (a WP), not "done". "In flight" is reserved
for the open PRs **#1930 / #1993**.

| Phase / Milestone | Status |
|---|---|
| 0 — foundations (secret sharing, pluggable crypto, jt-pq) | **Partial**: jt-pq + Phase-6 in trunk; pluggable crypto **in flight** (#1930); secret sharing **prototyped on spike, not landed** (→ WP-SS) |
| 1 — PQ primitives in at_chops (X-Wing, GCM, HKDF, HMAC) | **Done** (trunk); remaining: PQ enrollment-conveyance pubkey |
| 2 — identity layer (KeyPackages + per-client AtKeys) | KeyPackage framing **prototyped on spike, not landed** (→ WP-SS); AtKeys device-local split + identity resolution: not started (mostly D2 / D1 Tier2) |
| 2.5 — at_persistence 5.x migration | **Done & verified** |
| 3 — `SecureGroup` v1 + `group` provider (self) | **Prototyped on spike, not landed** (→ WP-GP); D1 Tier1 `nskey` self is **new D1 work** ([section 3](#3-d1--detailed-implementation-plan)) |
| 4 — cross-atSign shared | D1 Tier1 `nskey` shared is **new D1 work** ([section 3](#3-d1--detailed-implementation-plan)); per-client pair group is D1 Tier2 / D2 |
| 5 — pq-mls engine | **D2 placeholder** ([section 4](#4-d2--pq-mls-placeholders-detailed-planning-deferred)) |
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
5. The **usability acceptance test** holds at each milestone ([section 5](#5-cross-repo-pr--publish-sequence--noports)): no new flag a
   user must pass, file a user must manage, operator step, or peer-by-peer break.

The substantive D1 build is the **`nskey` provider (D1 Tier1)** and the
**migration/versioning machinery**, on top of the foundation that lands first:
the M0 seam (#1930), HPKE (#1993), and the carved-out **secret-sharing
substrate** (WP-SS). Only the at_chops primitives, the commit-log-free keystore,
and the Phase-6 routing ([section 1](#1-current-state-2026-06-22)) are already in trunk.

---

## 3. D1 — detailed implementation plan

Workstreams are roughly ordered; B is the centrepiece. Each task notes its
artifact and acceptance. Design references point at the roadmap. **D1-S
(structural enablers) lands first** — the `nskey` provider (D1-B) is built on
`WritableAtKeys` + stateless AtChops.

### D1-S · Structural enablers (prerequisite — lands first)
*Lands as [WP1–WP5 + WP8](#the-work-package-sequence--single-source-for-ordering)
across waves 1–3.* Design: roadmap
[Component responsibilities & WASM-readiness](crypto-roadmap.md#component-responsibilities--wasm-readiness).
The responsibilities reshape + the `at_auth` WASM split. Sequenced **before**
the feature workstreams; only `at_auth` takes a major bump (see
[package versions & release sequencing](#package-versions--release-sequencing)).

- [ ] **S1 · AtChops stateless core + `@Deprecated` shim** (`at_chops` minor
  `3.3.0`). Add a stateless functional surface (keys passed per call; the
  primitive algos already pure or trivially made so); keep `AtChopsImpl(keys)`
  as a `@Deprecated` shim over it so the ~65 construction sites compile
  unchanged and migrate gradually. *Acceptance:* all at_chops vectors green via
  both surfaces; consumers unbroken.
- [ ] **S2 · `WritableAtKeys` holder + explicit dumb stores** (`at_auth`). A
  **subclass of at_auth's `AtKeys`** (the key-material holder) adding
  `add`/`remove`/`write`; composed at AtClient construction; convergence stays
  in the secret-sharing substrate. *(NOT a wrapper around `AtChops` — `AtKeys`
  already produces one via `toAtChops()` and carries a `metadata` stash.)*
  Stores:
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
  `CryptoContext` gains a `WritableAtKeys keys` field (additive — after the slim
  refactor `CryptoContext` is `{atClient}`, so there is **no `atChops` field to
  deprecate**); the (stateless) `LegacyCryptoProvider` reads keys from
  `context.keys` instead of `context.atClient`; `LocalKeystoreAtKeysIo` is
  injected into `WritableAtKeys` at AtClient construction.
  *Acceptance:* legacy + group providers operate via `context.keys`; existing
  unit/functional suites green.
- [ ] **S6 · Consumer constraint bumps + sequencing.** `at_client` /
  `at_onboarding_cli` (`1.17.0`) / `at_client_flutter` (`1.2.0`) /
  `at_cli_commons` adopt `at_auth ^4.0.0`; publish in dependency order
  (at_chops → at_auth → at_client/onboarding/flutter → at_cli_commons). The
  [package-versions table (section 7)](#package-versions--release-sequencing) is
  authoritative.

### D1-A · Finish the PQ primitives (small)
*Lands as [WP1 (HPKE) + WP10 (enrollment-conveyance key)](#the-work-package-sequence--single-source-for-ordering),
waves 1–2.*
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
  alongside `public:publickey@alice` (e.g. `public:pqpublickey@alice` or a
  key-list); new enrollees prefer it for wrapping `apkamSymmetricKey`; approvers
  accept either. Closes the last harvest-now-decrypt-later hole; **no server
  change.** Design: roadmap
  [Phase 1](crypto-roadmap.md#phase-1--complete-the-pq-primitives-at_chops).
  *Acceptance:* enrollment round-trip uses X-Wing when both sides support it,
  falls back to RSA otherwise; functional enrollment test green.
  *Note:* this same atSign-level PQ key is the **cold-start fallback** for
  `nskey` (D1-B4) — build it first.

### D1-B · The `nskey` provider (D1 Tier1 — the default)
*Lands as [WP6 (B1–B4) + WP9 (B5/B6)](#the-work-package-sequence--single-source-for-ordering),
waves 3–4.* Design: roadmap
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
    `public:encryptionpublickey.<ns>@<atSign>` (or a hidden public key);
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
    `utf8.encode(toString())` bug, see [section 3](#3-d1--detailed-implementation-plan) D1 Tier2 shape tasks).
- [ ] **B3 · Capability marker + per-destination negotiation.** Per-`(atSign,
  namespace)` published marker `{nskey: true, nskeyPubKid, …}`, **initially
  not-ready**; the sender reads the recipient's marker (+ its own, for self
  copies) and selects the scheme. Design: roadmap
  [Mixed-tier](crypto-roadmap.md#mixed-tier-alice--bob) +
  [Application migration & rollout](crypto-roadmap.md#application-migration--rollout).
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
  enrollment's conveyance key); reuse the **WP-SS** `__`-secret substrate +
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
*Lands as [WP7](#the-work-package-sequence--single-source-for-ordering), wave 4.*
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
- [ ] **C3 · Strict-mode toggles (simple-code tier).** Policy options (a
  strict-mode mechanism to be designed — the early `CryptoPolicy` was removed in
  the slim-API refactor): refuse legacy fallback / require PQ in cold-start
  (seal-and-hold vs error vs notify); custom rotation triggers. These are
  app-facing in 3.x — alongside `disallowLegacyEncryption` (D1-D), which is the
  dedicated legacy-write switch.
- [ ] **C4 · Capability conformance.** Implement so the
  [capabilities table](crypto-roadmap.md#capabilities-by-application-code-change-level)
  holds: no-code = universal reader + back-compat; flag = PQ writer/recipient;
  code = override defaults / D1 Tier2.

### D1-D · Versioning (the `disallowLegacyEncryption` flag)
*Lands as [WP7 (flag, default off) + WP-D3 (v4 default flip)](#the-work-package-sequence--single-source-for-ordering),
waves 4 & 6.* Design: roadmap
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

### D1-E · D1 Tier2 shape-corrections (fold into WP-GP)
*Lands as [WP-GP](#the-work-package-sequence--single-source-for-ordering), wave 5.*
The `group` provider is prototyped on the spike (D1 Tier2 self) and lands as
WP-GP. These preserve its shape before the self→shared and MLS transitions;
apply them as part of that carve-out, while touching the area.
- [ ] **Lift membership into `SecureGroup`** (`members`/`add`/`remove`); v1
  derives them. Avoids a later breaking change to a published abstract.
- [ ] **Binary-safe `group` provider** — seal/open bytes, honour `isBinary`
  (currently `utf8.encode(plaintext.toString())` corrupts binary).
- [ ] **Rename `PairwiseGroup` → `SelfGroup`** to free "pair group" for the
  Phase-4 cross-atSign meaning.

### D1-F · Existing-client retrofit — auth upgrade & secret conveyance
*Lands as a new **WP-AU** (auth upgrade); gated on the F5 atServer enhancements
(cross-repo to `at_server`) — slot into the wave sequence at review.* Design: roadmap
[Existing-client retrofit](crypto-roadmap.md#existing-client-retrofit--auth-upgrade--key-distribution).

The one-time retrofit that brings an existing atSign's already-onboarded clients to
PQ-safe **auth** (PQ APKAM) and **encryption** (the atSign-level PQ key), reusing the
secret-sharing substrate (WP-SS). New atSigns (PQ-native at onboarding) and new enrollments
(approver push via WP10) do **not** run this.

- [ ] **F1 · `requestSecret(name)` primitive.** Generalise the substrate's
  `requestSecretsFromNamespace` to request a *named* secret; a holder responds with
  `shareSecretWith(requester.ClientKeyPackage, secret)` (`pqSeal`); requester
  `waitForSecret`. *Responder authorisation:* serve a namespaced secret only if the
  requester's enrollment covers that namespace; never to an `excludeEnrollmentIds` member.
  Handle no-holder-online (request persists; retry/backoff), thundering-herd (jitter +
  `putIfNewer` dedup), and freshness (version/`kid`). *Files:*
  `at_client/lib/src/secret_sharing/`.
- [ ] **F2 · atSign-level `pqpublickey` lifecycle.** `public:pqpublickey@alice` (root, no
  namespace — *not* `publickey.pq`). Create via immutable create-if-absent (F5); the
  creator generates the X-Wing keypair, stores the private half, seeds it as a conveyable
  secret (`pqid:<kid>`), and serves on request. A non-creator pulls via F1, **verifies
  public/private correspondence**, and stores into the local keystore (`WritableAtKeys`).
  Conveyed to *every* non-revoked client (root → no namespace gate).
- [ ] **F3 · Per-host PQ APKAM upgrade.** Mint-once **per (host, AtKeys file)** under a
  host-local lock (reuse an existing keyfile key; else mint + persist); publish the public
  half as an immutable per-host record; verify PQ APKAM auth; **then** delete the legacy RSA
  APKAM public key (delete-by-default, scope = auth key only — keep the legacy encryption
  key for reads). Uniform sequence per the roadmap; "creator vs requester" decided by F2's
  immutable create. *Storage:* keyfile/keychain by default; OS-keychain/hardware opt-in; a
  distinct labelled per-host record drives per-host revocation.
- [ ] **F4 · Revocation.** Per-host auth revocation = delete that host's PQ APKAM public key
  (meaningful only after F3's legacy deletion). Encryption revocation stays per-namespace
  rotation (D1-B / WP9). TTL/usage-based eviction of unused APKAM keys (F5).
- [ ] **F5 · atServer enhancements** *(cross-repo, `at_server`; gate F2/F3/F4).* Mint-once
  uses the **existing immutable write** (`Metadata.immutable` — already live, no change). New:
  - **multiple APKAM public keys per enrollment** + authenticate against any;
  - **PQ (ML-DSA) APKAM authentication**;
  - **delete a specific public key** (legacy on upgrade; a host's PQ key on revocation);
  - **TTL / usage-based eviction of APKAM keys** + a per-key **"last authenticated"
    timestamp** (updated on each successful auth).
- [ ] **F6 · Confirm WP10 alignment.** PQ-safe enroll/approve must convey `pqpublickey` +
  the new enrollment's PQ APKAM over the **PQ enrollment key**, not the RSA-wrapped
  `apkamSymmetricKey` — else the harvest-now hole reopens for new clients.

*Acceptance:* an existing client upgrades end-to-end (mints PQ APKAM, authenticates PQ,
legacy APKAM deleted, pulls `pqpublickey`, correspondence verified) with no re-onboarding; a
second host mints a *distinct* PQ APKAM key; revoking one host's key cuts only that host; no
secret is ever wrapped under an RSA-derived key.

### D1 · Test & acceptance plan
- Unit: `nskey` round-trips (self/shared/binary), negotiation matrix, rotation
  convergence, `disallowLegacyEncryption` enforcement (+ the creation-time
  `SHOUT` when `false`, + immutability after construction), cold-start fallback,
  the regression test
  pattern (a test that fails without the fix).
- Functional (live virtualenv): nskey self + shared, rotation, mixed-tier
  (nskey↔legacy), cold-start, enrollment-revoke + rotate-exclude.
- e2e (cross-atSign, `@ce2e*`): the `at_talk` chat scenario from
  [Walkthrough C](crypto-walkthroughs.md#walkthrough-c--a-two-atsign-chat-with-client-churn-at_talk)
  — alice1/2 ↔ bob1/2 bidirectional, then bob3/alice3 join (new + past
  messages). Run concurrently via the base-port `runLocal.sh` rigs (PR #1992).
- Usability acceptance test ([section 5](#5-cross-repo-pr--publish-sequence--noports)) at each milestone.

### D1 · PR delivery / publish
Each work package is its own short-lived branch **merged to trunk when
complete**, with pub.dev **published as needed** in dependency order ([section 7](#7-delivery-plan--work-packages)) — 4c
(secret sharing) and the `nskey`/migration work land the same way, not carved
from an integration branch at the end. Overall publish order: roadmap
[Dependencies](crypto-roadmap.md#dependencies) + the
[package-versions table (section 7)](#package-versions--release-sequencing).

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
  idempotency short-circuit returned the cached `AtClient` without re-applying
  the new preference's providers, so a same-atSign re-set with a new provider
  config dropped it → intermittent `CryptoProviderNotRegistered`. *(Later, when
  `CryptoRegistry` was folded into `CryptoConfig`, the `reconcileCryptoProviders`
  fix was replaced by adopting the new `preference.crypto` on reuse — same Mode-B
  guarantee, no registry; deterministic regression test retained.)* **PR #1930
  CI all green.**
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
onto the [section 3](#3-d1--detailed-implementation-plan) workstreams (D1-S / D1-A…E); this is the parallelisation/sequencing
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

### Reconciliations since the slim refactor (`xl-pluggable`)
The slim-API + registry-fold landed on `xl-pluggable` (PR #1930) after this [section 7](#7-delivery-plan--work-packages)
was first written; three assumptions shifted:
1. **`CryptoContext` is `{atClient}`** — no `atChops` field. WP3 just *adds*
   `WritableAtKeys keys`; nothing to deprecate.
2. **`WritableAtKeys` subclasses at_auth's `AtKeys`** (the material holder),
   not a wrapper over `AtChops` (WP2).
3. **No `CryptoRegistry`** — `CryptoRuntime` resolves against the live
   `AtClientPreference.crypto` (`CryptoConfig.lookup` + a built-in legacy
   fallback), and cached-client reuse adopts the new config. WP6/WP7 add a
   provider to `CryptoConfig.providers` and read `context`; there is no registry
   to register against. The SDK stamps `appMetadata.providerId` + `isEncrypted`,
   so providers only contribute `additional`.

### The work-package sequence — single source for ordering

**Baseline (built / in trunk):** at_commons 5.11.0 (`appMetadata` wire), at_chops
3.2.1 (X-Wing, AES-256-GCM, HKDF, HMAC), at_persistence 5.x (commit-log-free),
at_client commit-log-free migration (4a), Phase-6 at_chops routing in
at_lookup / at_auth / at_onboarding_cli (#1995–1998, **merged**). **In flight:**
#1993 (at_chops HPKE), #1930 (at_client M0 seam).

**Prototyped on `gkc-pqmls-spike` but NOT landed — first-class work to do, not
foundation:** the **secret-sharing substrate** (WP-SS) and the **`group`
provider** (WP-GP). They were previously folded into WP11/WP9 as "assumed
built"; they are now their own carve-out WPs.

Order is top-to-bottom; items in one **wave** run in parallel (different
package/track — A crypto-primitives, B key-management, C at_client seam,
D storage/consumers). **▶** marks a pub.dev release shipping user-visible
capability.

**WP ↔ workstream map.** Each work package realises one or more of the
[section 3](#3-d1--detailed-implementation-plan) workstreams; this table is the
two-way lookup (a WP row here links to its workstream, and each workstream
header links back to this section):

| WP | Workstream ([section 3](#3-d1--detailed-implementation-plan)) | Wave |
|---|---|---|
| #1993 / WP1 | [D1-A](#d1-a--finish-the-pq-primitives-small) (HPKE) + [D1-S](#d1-s--structural-enablers-prerequisite--lands-first) S1 | 0 / 1 |
| WP2 | [D1-S](#d1-s--structural-enablers-prerequisite--lands-first) S2 | 1 |
| WP3 | [D1-S](#d1-s--structural-enablers-prerequisite--lands-first) S5 | 1 |
| WP4 | [D1-S](#d1-s--structural-enablers-prerequisite--lands-first) S2/S3 (+ storage) | 1 |
| WP-SS | [Foundations — secret sharing](crypto-roadmap.md#foundations) | 2 |
| WP10 | [D1-A](#d1-a--finish-the-pq-primitives-small) (enrollment-conveyance key) | 2 |
| WP6 | [D1-B](#d1-b--the-nskey-provider-d1-tier1--the-default) B1–B4 | 3 |
| WP5 | [D1-S](#d1-s--structural-enablers-prerequisite--lands-first) S4 (WASM cut) | 3 |
| WP8 | [D1-S](#d1-s--structural-enablers-prerequisite--lands-first) S6 (consumer bumps) | 3 |
| WP7 | [D1-C](#d1-c--migration--rollout-machinery) + [D1-D](#d1-d--versioning-the-disallowlegacyencryption-flag) D2 | 4 |
| WP9 | [D1-B](#d1-b--the-nskey-provider-d1-tier1--the-default) B5/B6 | 4 |
| WP-GP | [D1-E](#d1-e--d1-tier2-shape-corrections-fold-into-wp-gp) | 5 |
| WP-D3 | [D1-D](#d1-d--versioning-the-disallowlegacyencryption-flag) D3 | 6 |

**Wave 0 — land the in-flight foundation (gates everything).** #1930 is the
single biggest unblock; #1993 can be reviewed alongside it.
- **#1993** (A) — fold HPKE `pqSeal`/`pqOpen` into at_chops (D1-A).
- **#1930** (C) — at_client M0 pluggable crypto seam.
  **▶ at_client (minor): the pluggable-crypto seam ships** — apps can register
  custom `CryptoProvider`s; legacy stays the default. (First capability release.)

**Wave 1 — contracts (WP1–WP4, parallel; merge the three interface PRs first).**
- **WP1** (A) at_chops stateless core + `@Deprecated` shim, HPKE folded in. **▶ at_chops 3.3.0.**
- **WP2** (B) `WritableAtKeys extends AtKeys` + `AtKeysIo` widening — API only. **▶ at_auth 3.2.0.**
- **WP3** (C) `CryptoContext.keys` field (additive). *(interface-first)*
- **WP4** (D) `LocalKeystoreAtKeysIo` + updatable `.atKeys`.

**Wave 2 — substrate + enrollment key (parallel; on at_chops 3.3.0).**
- **WP-SS** (A/C) carve the **secret-sharing substrate** spike → trunk:
  `ClientKeyPackage`, `SecretStore`, namespace registration/discovery, `__ssenv`
  envelopes **via `pqSeal`**, `requestSecretsFromNamespace`, `waitForSecret`,
  `excludeEnrollmentIds`.
- **WP10** (B) PQ enrollment-conveyance public key (also the nskey cold-start
  fallback) — land before WP6.

**Wave 3 — `nskey` core + the at_auth 4.0 cut (parallel).**
- **WP6** (C/A, D1-B B1–B4) the **`nskey` provider** — namespace keypair
  (derive/publish), seal/open via `pqSeal`, capability marker + negotiation,
  cold-start fallback. Needs WP1, WP3, WP10 (+ WP-SS for the non-derivable
  distribution path).
  **▶ at_client (minor): PQ-safe writes available** — a rebuilt app is a
  universal reader; one readiness-flag flip makes its new writes `nskey`.
- **WP5** (B) **`at_auth 4.0.0`** WASM barrel split (the one breaking cut). Needs WP2.
  **▶ at_auth 4.0.0** with **WP8** (D, consumer bumps onboarding/flutter/
  cli_commons) **▶** their minors right behind it.

**Wave 4 — D1 Tier1 completion (migration, rotation, versioning).**
- **WP7** (C, D1-C + D1-D flag) migration machinery (readiness-marker lifecycle,
  negotiation default, strict-mode toggles) + `disallowLegacyEncryption`
  (default `false`); legacy provider reads `WritableAtKeys`. Needs WP6.
- **WP9** (A/C, D1-B B5/B6) nskey **rotation + revocation**; `__ssenv`
  consolidated on `pqSeal`. Needs WP-SS, WP6.
  **▶ at_client `3.14.x`: D1 Tier1 GA — PQ-safe namespace messaging** (the
  headline: rebuild = universal reader, one flag = PQ writer, opt-in rotation).

**Wave 5 — D1 Tier2 (opt-in hardened) — parallel, off the Tier1 critical path.**
- **WP-GP** (A/C) carve the **`group` provider** (`SecureGroup` / `SelfGroup`)
  spike → trunk + the D1-E shape fixes (binary-safe, lift membership, rename).

**Wave 6 — the v4 cut (gated on the ecosystem floor).**
- **WP-D3** (D1-D) at_client **4.0.0** — flip `disallowLegacyEncryption` default
  to `true` + dead-code removal (the legacy provider itself stays — needed for
  reads). **▶ at_client 4.0.0: PQ-safe on every write path by default.**

D2 (pq-mls) is a separate deliverable — see [section 4](#4-d2--pq-mls-placeholders-detailed-planning-deferred).

### Package versions & release sequencing

Publish in dependency order. Only `at_auth` takes a major (the breaking WASM
barrel split); everyone else stays minor. The `at_auth` work is split into an
additive minor (`3.2.0`, WP2) then a breaking major (`4.0.0`, WP5) so
`WritableAtKeys` bakes before the barrel cut. Design rationale: roadmap
[package versions & release sequencing](crypto-roadmap.md#package-versions--release-sequencing).

| # | Package | Bump | WP | Why |
|---|---|---|---|---|
| 1 | `at_chops` | minor `3.2.1 → 3.3.0` | WP1 | stateless functional core + HPKE `pqSeal`/`pqOpen` **added**; stateful `AtChopsImpl` kept as `@Deprecated` shim (additive) |
| 2 | `at_auth` | minor `3.1.1 → 3.2.0` | WP2 | **additive API:** `WritableAtKeys` added; `AtKeysIo`/`WrittenAtKeysIo` widened (add/remove/update, default impls); `InMemoryAtKeysIo`. No barrel change yet — downstream can adopt `WritableAtKeys` immediately |
| 3 | `at_auth` | **major `3.2.0 → 4.0.0`** | WP5 | **breaking WASM cut:** `FileAtKeysIo` out of the main barrel (→ `at_auth_io.dart`); `FileAtKeysIo()` default removed; registrar → `package:http`; probe extracted; core compiles under `dart2wasm` |
| 4 | `at_client` | minor `3.13.0 → 3.14.0` | WP3 / WP6 | `at_auth ^4.0.0`; `CryptoContext` gains a `WritableAtKeys keys` field (additive; context is `{atClient}` today — nothing to deprecate); `LocalKeystoreAtKeysIo`; `nskey` provider scaffold |
| 5 | `at_onboarding_cli` | minor `1.16.0 → 1.17.0` | WP8 | `at_auth ^4.0.0`; imports `FileAtKeysIo` from `at_auth_io.dart`; injects it explicitly (default gone) |
| 6 | `at_client_flutter` | minor `1.1.3 → 1.2.0` | WP8 | `at_auth ^4.0.0`; `file_picker` imports `at_auth_io.dart` |
| 7 | `at_cli_commons` | minor (constraint bump) | WP8 | consumes the new `at_onboarding_cli` / `at_client` |

### Integration is continuous, not a final step
Each WP **merges to trunk when complete** and is **published to pub.dev as
needed** in dependency order (the
[package-versions table](#package-versions--release-sequencing) above). To prove
the full stack
before a batch lands, **spin up an ephemeral integration branch on demand**
(merge the in-flight WP branches, run unit + functional + e2e via the base-port
`runLocal.sh` rigs, discard) or rely on CI — so cross-package issues surface
early, with no standing integration branch to drift.

### Critical path & merge discipline
- **Critical path to D1 Tier1 GA:** #1930 → WP1 (`pqSeal`) + WP3
  (`CryptoContext`) + WP-SS (substrate) + WP10 (enrollment key) → WP6 (`nskey`)
  → WP7 (migration/flag) → WP9 (rotation). `at_auth 4.0` (WP5, WASM-readiness)
  and WP-GP (the `group` provider) run **in parallel, off this path**.
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

### Wave-1 PR stubs (ready to assign once Wave 0 is on trunk)

Four small, additive, single-package PRs — one per track, started in parallel.
Land the three interface-defining ones (WP1/WP2/WP3 signatures) first, stubs OK,
so every track compiles against stable shapes. Full acceptance detail is in [section 3](#3-d1--detailed-implementation-plan)
(D1-S S1/S2/S5, D1-A). **Prereqs on trunk:** PR #1930 (M0 seam), PR #1993 (HPKE),
the four at_chops-routing PRs (#1995–1998).

- **WP1 · `feat(at_chops): stateless core + HPKE`** (Track A).
  Add a stateless functional surface (keys passed per call) beside `AtChopsImpl`;
  keep `AtChopsImpl(keys)` as a `@Deprecated` shim. Fold `pqSeal`/`pqOpen` (from
  the revised #1993) onto the existing `AesGcm256EncryptionAlgo`/`HkdfSha256`/
  `HmacSha256`. *Files:* `at_chops/lib/src/` + `pq_hpke.dart`. *Bump:* `at_chops
  3.2.1 → 3.3.0`. *Depends:* #1993 revised. *Done:* all vectors green via both
  surfaces; pqSeal round-trip / tamper→`authFailure` / info-aad-mismatch tests.

- **WP2 · `feat(at_auth): WritableAtKeys + AtKeysIo widening (API only)`** (Track B).
  `WritableAtKeys extends AtKeys` (`add`/`remove`/`write`); widen
  `AtKeysIo`/`WrittenAtKeysIo` (add/remove/update with default impls);
  `InMemoryAtKeysIo`. No behaviour change to onboard/auth. *Files:*
  `at_auth/lib/src/keys/`. *Bump:* `at_auth 3.2.0`. *Depends:* #1996 merged.
  *Done:* existing at_auth suites green; new API unit-tested.

- **WP3 · `feat(at_client): CryptoContext.keys`** (Track C).
  `CryptoContext` gains a `WritableAtKeys keys` field (additive), built at
  AtClient construction from auth's `AtKeys`. Providers may read it; legacy
  unchanged for now. *Files:* `crypto.dart`, `at_client_impl.dart` (`_context()`),
  `crypto_runtime.dart`. *Bump:* at_client (fold into the in-progress version).
  *Depends:* #1930; WP2's `WritableAtKeys` type (interface-first). *Done:*
  context carries `keys`; crypto suites green.

- **WP4 · `feat: LocalKeystoreAtKeysIo + updatable .atKeys`** (Track D).
  `LocalKeystoreAtKeysIo` (at_client) + make the `.atKeys` path updatable
  (`WrittenAtKeysIo` update path; re-wrap self-enc key; atomic write + backup).
  *Files:* at_client storage + at_auth `FileAtKeysIo`. *Bump:* at_client /
  at_auth. *Depends:* WP2 (`AtKeysIo` API). *Done:* a post-onboarding key add
  persists + survives restart; migration test on a v(N-1) fixture.
