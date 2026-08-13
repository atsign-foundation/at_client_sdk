# Roadmap & high-level design — PQ-safe encryption for the Atsign Protocol

**Status:** design source of truth (high-level WHY + WHAT). Companion docs carry
the build sequence, detailed mechanics, acceptance tests, and the decision log.
**Scope:** the move from the legacy encryption schemes to post-quantum-safe
encryption with rotating keys — the single-tier `nskey` data path (D1), then
group-based `at/pqmls` (D2) — preserving every current capability
(encrypt/decrypt for other clients of the same atSign, encrypt/decrypt for other
atSigns) — framed as two deliverables, **D1** (the single-tier `nskey` data
path) and **D2** (the `at/pqmls` group provider, referenced not detailed here).

> This doc is the **high-level WHY + WHAT** only: the two deliverables, the
> conceptual `nskey` shape, mixed-scheme + migration philosophy, the
> usability/crypto-agility constraints, and the phase trajectory at a glance.
> When a companion disagrees on design *intent*, this document wins; for
> mechanics, sequencing, tests, or rulings the companion named below is
> authoritative.

## Table of contents

- [Document map](#document-map)
- [The two major deliverables (D1 / D2)](#the-two-major-deliverables-d1--d2)
- [D1 — preserving legacy simplicity (single-tier: the nskey data path)](#d1--preserving-legacy-simplicity-single-tier-the-nskey-data-path)
- [Mixed-scheme coexistence & migration philosophy](#mixed-scheme-coexistence--migration-philosophy)
- [Usability & crypto-agility constraints](#usability--crypto-agility-constraints)
- [The phase trajectory at a glance](#the-phase-trajectory-at-a-glance)

## Document map

This is one of **six** docs. Each keeps to its lane; cross-references point at
the canonical home rather than duplicating it.

| Doc | What lives there |
|---|---|
| **roadmap.md** (this doc) | Roadmap & high-level design — the WHY + WHAT: deliverables D1/D2, the conceptual `nskey` shape, migration philosophy, usability/crypto-agility constraints, the phase trajectory at a glance. |
| [`implementation-plan.md`](implementation-plan.md) | The build sequence — the project list (Wave-0 baseline, P-1..P-3, S-1..S-6, SS-*, B-*, RF-*, R-1/R-2, ON-1, D2-1), the dependency graph, waves/parallelism, effort, publish gates, the critical path, and the coverage map. |
| [`design.md`](design.md) | Detailed designs by subsystem — the D1 `nskey` data-path key shapes / 3 providers / `appMetadata` / CK model / cold-start / FS + rotation levers; the secret-sharing substrate (`kpid`, `__ssenv`, `SecretStore`, push/pull, `enroll:listns`, the enrollment record + self-retrofit flow); at_chops primitives; the `CryptoProvider` seam / key stores / WASM split; and the worked walkthroughs (NoPorts, at_talk). Build-level notes with `file:line`. |
| [`acceptance.md`](acceptance.md) | The given/when/then use-case catalogue (A1.x–A5.x, B0.x–B5.x) with concrete at-keys plus the impl/verify steps and the test harness. |
| [`decisions.md`](decisions.md) | The decision log — the design rulings (the verb wire shape, the 1:1:1 ruling), the resolved and open decisions, and a dated timeline. The WHY behind every choice. |
| [`seal-spec.md`](seal-spec.md) | The byte-level `atPQv1-base` seal specification a second implementation builds from, paired with `packages/at_chops/test/vectors/pq_seal_v1.json`. |

## The two major deliverables (D1 / D2)

This roadmap delivers two distinct things. The second builds on the first and
they ship in sequence — but they deliver different security properties and have
different urgency, so they are worth naming separately.

### D1 — make Atsign Protocol messaging post-quantum safe

Every message the SDK encrypts — self data, data shared with other atSigns, and
the enrollment-approval key conveyance — becomes protected with post-quantum /
hybrid primitives, so an adversary who records today's ciphertext cannot read it
once a cryptographically-relevant quantum computer exists. This is the **urgent**
deliverable: harvest-now-decrypt-later capture is a present-day threat, and PQ
confidentiality is the defence.

D1 does **not** require MLS. It is reached by routing every encryption path
through pluggable PQ providers — a post-quantum **KEM** for key transport,
**AES-256-GCM** for data — publishing a PQ enrollment-conveyance key, then
making the **`nskey` data path** the default for both self and shared data and
retiring the classical-only `selfEncryptionKey` and `shared_key.*`.

**Two KEMs, chosen per deployment.** The default is the **X-Wing hybrid
(ML-KEM-768 + X25519)**, which keeps a hedge against ML-KEM falling to
*classical* cryptanalysis. The alternative is **pure ML-KEM-1024**, selected by
`AtClientPreference.keyEstablishmentAlgo` — it exists for its citation rather
than its strength, being the only option here whose specification chain contains
no draft, and the parameter set CNSA 2.0 mandates. Neither restricts who an
atSign can talk to: a sender follows whatever the recipient advertised, and
every build produces and opens both.

D1's data path is the **`nskey` data path** — `at/nskey` conveys a symmetric
content key (CK) and `at/symmetric/AES/GCM` encrypts the data under it — **not**
the group engine. The `nskey` data path is PQ-native by construction, so PQ-safe
messaging does not wait on the MLS (group) work, which is the separate D2
`at/pqmls` provider. (For the data-path mechanics see
[`design.md`](design.md); for tests, [`acceptance.md`](acceptance.md).)

**Authentication is PQ-safe too.** D1 also moves APKAM/PKAM signatures to
**ML-DSA-65**. Unlike confidentiality, signatures are not
harvest-now-decrypt-later-vulnerable — a recorded signature is worthless once
its key is retired — so the adversary here is an *active* cryptographically-relevant
quantum computer forging live authentications, not a passive recorder. ML-DSA
APKAM auth rides D1 because the enrollment-record reshape and the substrate's
envelope-trust both already touch the auth path, so doing it separately would
mean a second server-schema migration; it is record-authoritative (the atServer
verifies against the algorithm stored on the enrollment record, never the
wire-declared one).

### D2 — implement pq-mls (the `at/pqmls` group provider)

Replace the interim v1 group engine with a real MLS engine (RFC 9420 — TreeKEM,
forward secrecy, post-compromise security) on post-quantum ciphersuites, behind
the same `SecureGroup` interface and served by the atServer group Delivery
Service. D1 already gives *coarse* forward secrecy (CK rotation + delete) and
post-compromise security (`nskey`-keypair rotation); what D2 adds over D1 is:

- **robust / per-message FS** — ratcheted leaves, no standing master key, so a
  compromised key does not expose past traffic at message granularity;
- **scale** — O(log n) membership changes that make large groups practical;
- **decoupled membership** — groups whose membership is not tied to namespace
  authorisation.

D1 makes the bytes quantum-safe (coarse FS + PCS available); D2 makes the
*group* quantum-safe with robust/per-message forward secrecy, scale, and
decoupled membership. The roadmap is deliberately shaped so **D2 is an engine
swap under D1's stable `SecureGroup` interface — not a second migration.**
NoPorts adoption (the production payoff) is reachable as soon as D1 lands, and is
strengthened — not gated — by D2.

D2 is **referenced, not detailed** in this doc set. The `at/pqmls` provider shape,
the SecureGroup interface, the epoch/TreeKEM design, and the atServer group Delivery
Service are **D2 — out of scope here** (a dedicated D2 design is a separate effort);
the `D2-1` carve placeholder is in [`implementation-plan.md`](implementation-plan.md),
and [`design.md`](design.md) covers only the D1 `CryptoProvider` seam the provider
plugs into.

## D1 — preserving legacy simplicity (single-tier: the nskey data path)

D1's design objective is to keep the **legacy developer experience** — *Alice
shares with `@bob`; every bob client with namespace access, present and future,
decrypts it instantly, offline, with no ceremony* — while making it
post-quantum-safe and closing the cheap legacy weaknesses.

**D1 ships as a single tier: the `nskey` data path** — the only data path for
both self and shared data. Conceptually the path is **two providers** plus the
built-in legacy provider:

- **`at/nskey`** conveys a symmetric **content key (CK)**, sealing it once to an
  `nskey` and writing it as a discrete record; and
- **`at/symmetric/AES/GCM`** encrypts the data (AES-256-GCM) under that CK,
  citing it by `ckKid`.

An **`nskey` is an asymmetric KEM keypair you encapsulate symmetric CKs to** —
it never encrypts application data directly. Per `(atSign, namespace)` there is
**one** `nskey` keypair, under whichever KEM that atSign's deployment
configured, and it is the recipient key for *both* directions: Alice
encapsulates her **own** CKs to it for self data, and external senders
encapsulate CKs to it when sharing with her. Its published advertisement names
its algorithm, because a sender cannot tell one encapsulation key from another
by looking and getting it wrong writes a record Alice can never open.

- The **private half** lives in each of Alice's `<ns>`-authorised clients,
  conveyed per-APKAM as a secret over the shared substrate. It is a KEM private:
  it **decapsulates** CKs — both Alice's own and inbound ones — and never
  decrypts application data.
- The **public half is published eagerly** — written at mint, always, to
  `public:__nskey.<ns>@alice`, so a sender never has to wonder whether a recipient
  has published yet. The leading underscore keeps it out of every scan while an
  exact `plookup` still resolves it, so publishing it does not advertise that the
  namespace exists. The record is **mutable**: rotation overwrites it, serialised
  by a short-lived lock key, and each conveyance names the generation it was
  sealed to.

So Alice's self data and a share to `@bob` both encapsulate the CK to the **same**
`nskey`; the directions differ by *which atSign owns the CK record*, not by which
key is used. **One mechanism, both directions.** The developer API is unchanged:
`put` / `get` / AtCollection, with identity staying the *enrollment*, exactly as
legacy.

D1 ships as a single tier. Forward secrecy is a **rotation policy** of the single `nskey` data path, not a separate provider, and D1 provides it coarsely and cheaply. Data is encrypted under symmetric CKs delivered **per-APKAM** (the secret-sharing substrate + push); there are no per-device data keys, and a *future* device is served by **push** — instant, offline — so instant/offline access and per-APKAM revocation coexist within the single tier. (See [`decisions.md`](decisions.md) for the rationale.)

What D1 closes vs legacy, at **zero developer-visible change**:

| Legacy weakness | D1 (the `nskey` data path) |
|---|---|
| Not PQ-safe (RSA-2048) | **Closed** — X-Wing hybrid KEM by default, pure ML-KEM-1024 by configuration |
| Crypto broader than transport (one key spans all namespaces) | **Closed** — per-namespace keypair mirrors enrollment authorization |
| `selfEncryptionKey` sits still forever, conveyed to every enrollment | **Closed** — per-namespace, **rotatable**; per-namespace blast radius, not atSign-wide |
| No per-device revocation granularity | **Closed** — per-APKAM future-data revocation: rotate the `nskey` keypair excluding the revoked keypair |
| No rotation / forward secrecy | **Coarse FS** — rotate + delete the content keys (O(1) wrap to the shared `nskey`); robust/per-message FS is D2 (`at/pqmls`) |

The concrete key shapes (the `nskey` strings and their lazy-publish lifecycle, the `<ckKid>.__ck`
CK-conveyance record, the value shapes), the three layers and their
`appMetadata`, the CK model, the `public:pq_signing_root` signing root and the
cold-start refusal, and the forward-secrecy / rotation levers all live in
[`design.md`](design.md). The `at/pqmls` group provider — KeyPackages, ratcheted
leaf keys, TreeKEM, membership decoupled from namespace authorisation — is
**D2**, not a D1 tier; most apps never touch it. Crucially, the **per-APKAM
secret-sharing substrate is shared**: D1 uses it to convey `nskey` privates
per-APKAM, and D2's `at/pqmls` uses the same substrate for group messages — so
the substrate work serves both deliverables.

### D1 scope boundaries

**In D1 scope:** self data, data shared with other atSigns, the
enrollment-approval key conveyance, APKAM/PKAM authentication signatures
(ML-DSA), and — ruled in 2026-07-02 — **`.atKeys`-at-rest protection**: once
payloads are PQ-safe, the keyfile holding the PQ private material becomes the
highest-value harvest target, so encrypting the PQ privates at rest and the
keyfile backup/restore story are D1 concerns (sequenced as `KF-1` in the
implementation plan).

**Explicit non-goals (D1):** the **TLS session** to the atServer/atDirectory —
post-D1 the payloads inside are already E2E PQ-safe, so the residual TLS
exposure is verb-level metadata (key names, timing) the atServer sees by design
anyway; and the **atDirectory** itself, which holds no ciphertext. Both may be
revisited as separate efforts; neither gates D1. (For the ruling see
[`decisions.md`](decisions.md).)

## Mixed-scheme coexistence & migration philosophy

Existing apps are all on legacy. The migration must let **each client upgrade
independently** (rebuild on its own schedule) while staying compatible with
peers — and with other clients of its own atSign — that have not yet upgraded.
The M0 provider seam is what makes this work; the whole plan is one invariant
plus **each app's own two releases** — capability, then active use. (There is no
rollout *machinery*: the readiness-marker/negotiation layer was built and removed
2026-08-05 —
[`decisions.md` 36](decisions.md#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05);
the two-release model + the flag semantics live in [`design.md`](design.md) [section 1.8](design.md#18-migration-rollout--the-disallowlegacyencryption-flag-d1-c--d1-d).)

**The seam lets schemes coexist per value, so the sender encrypts in the scheme
the recipient can decrypt** — discovered from what the recipient publishes:

- a published **`public:__nskey`** for the namespace → the `nskey` data path;
- only an **RSA pubkey** → `legacy`;
- **KeyPackages + a group advertised** → `at/pqmls` (in D2).

**The migration invariant:**

> A value is only ever *written* in a scheme every client that must *read* it
> supports. **Reads are universal** — each value carries
> `appMetadata.providerId`, and an upgraded client keeps *all* older providers,
> so it decrypts anything ever written.

Compatibility is therefore **asymmetric**: upgrading only ever adds
read-capability; the risk is writing too *new*, never reading too *old*.

**The versioning contract**, conceptually, is one construction-time flag —
`disallowLegacyEncryption` on `AtClientPreference`:

- **default `false` in 3.x** = "PQ when the app says so, legacy otherwise" — a
  3.x client is PQ-*capable* but stays legacy-*compatible*; which scheme it
  writes is its app's release decision, and the cold-start refusal (plus the
  explicit fallback) is the only per-destination gate;
- **default `true` in 4.0** = "PQ — refuse rather than write legacy";
- **final at construction** (no mid-run flipping), and the SDK **SHOUTs at
  startup when it is `false`** so a client permitting legacy writes is never
  silent about it;
- **scope is literal** — it governs only legacy *encryption*, never legacy
  *read* and never the `shouldEncrypt=false` no-encryption path.

(The full flag semantics — strict-mode, the SHOUT, immutability, the
`shouldEncrypt=false` carve-out — are in [`design.md`](design.md); only the
high-level 3.x-off / 4.x-on trajectory belongs here.)

**The rollout trajectory at a glance** (one line per step; the two-release
model's detail lives in [`design.md`](design.md) [section 1.8](design.md#18-migration-rollout--the-disallowlegacyencryption-flag-d1-c--d1-d), the sequencing in
[`implementation-plan.md`](implementation-plan.md)):

0. **Baseline** — all legacy.
1. **The app's capability release (final 3.x — the soak).** Rebuild only: adds
   the PQ providers + provider routing on *read*, upgrades the app's enrollment,
   mints the namespace `nskey` (publishing its public half immediately at
   `public:__nskey.<ns>@alice`, the private conveyed per-APKAM over the
   substrate) or self-heals the private from a holder — and keeps *writing*
   legacy. A zero-risk, install-by-install deploy, and the one discipline of the
   whole migration: **this build reaches every install before the next one
   ships**.
2. **The app's active release (4.x, or an explicit config).** The app now writes
   the `nskey` data path. The SDK never makes this decision — the app's build
   does. Cross-atSign, a write toward a peer whose install has not reached
   capability fails **cold start by name** (or takes the explicit legacy
   fallback); the peer's key appearing is what ends that, with no action on the
   sender's side.
3. **Both ends capable ⇒ end-to-end D1** — the pair runs the `nskey` data path
   both directions; a mixed pair stays legacy *in that direction only*, by the
   app's own choice of fallback.
4. **Retire legacy, then the v4 default flip** — lazy re-encrypt on touch, then
   `at_client 4.0` flips its default posture from `ReleasePosture.migration()`
   to `ReleasePosture.postQuantum()`: one edit moving all five rollout axes at
   once (era config, `disallowLegacyEncryption`, the in-use signing set,
   enrolment key exchange, retrofit signing algorithm), which is why the flag
   and the era default can no longer be flipped apart
   ([`decisions.md` 70](decisions.md#70-workstream-a-capstone-releaseposture-the-five-flags-as-one-value-2026-08-10)).
   Legacy *reads* and the legacy provider remain. Minting/conveying legacy key
   material stops only in a later, **ecosystem-gated** release
   ([`decisions.md` 37](decisions.md#37-legacy-key-material-is-retained-until-the-ecosystem-is-pq-not-the-atsign-2026-08-05)).

In short: **3.x defaults to "PQ when it can, legacy when it must"; 4.x defaults
to "PQ — refuse rather than write legacy" — overridable either way, but never
silently.**

## Usability & crypto-agility constraints

`AtCollection` / `at_client` exists so application authors — **human and AI** —
can build on the Atsign Platform with minimal footguns. The group/PQ migration
must not erode that. The guiding constraint is: **the user sees no new task and
the app author writes no new code in the common case.** Every milestone is held
to that bar.

The promises, at a high level:

- **No per-invocation identity tax** — a program is never told *which* APKAM
  keypair it is; the SDK resolves it by label, so CLIs and the desktop app run
  under one atSign with no `--client-id` args and no clones.
- **No manual "add to group" step** — admission is a *consequence* of decisions
  already made (self-group membership derives from enrollment authorisation;
  session/cross-atSign admission rides the existing accept policy).
- **Apps supply nothing** — the identity resolver, `SecretStorePersistence`, and
  the client key load/save plumbing all ship default implementations.
- **Old data stays readable forever; migration is lazy** — the seam routes per
  value by `appMetadata`, re-encryption is on-touch, there is never a flag-day.
- **Backwards-compatible rollout** — reads are universal, and which scheme an
  app writes is its own release decision; the only per-destination gate is the
  cold-start refusal with its explicit legacy fallback
  ([`decisions.md` 36](decisions.md#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05)).
  An old peer keeps the legacy path by never having published a namespace key.
- **Safety is automatic** — a duplicate same-identity launch forks or refuses
  deterministically rather than corrupting state.
- **For NoPorts the target is zero user-visible delta** — same commands, args,
  setup and authorisation.

**The usability acceptance bar for any milestone:** does it add a flag a user
must pass, a file a user must manage, an operator step, or a peer-by-peer break?
If yes, it isn't done.

**Crypto-agility** is a sibling constraint: schemes upgrade **by id with no
schema change** — the provider seam routes per value, so new algorithms and
providers drop in without a flag-day. Key lists and envelopes carry their
`{kid, use, alg}` / `{suite, kid}` descriptors so the wire format never
has to change when a primitive is replaced.

How these constraints are realised — the `CryptoProvider` seam and the NoPorts
admission UX — lives in [`design.md`](design.md) (identity resolution is D2/deferred; the
default `SecretStorePersistence` ships in D1 at SS-3); the per-milestone
usability tests live in [`acceptance.md`](acceptance.md).

## The phase trajectory at a glance

The path to the end state, framed by capability. Each milestone is usable on its
own; later ones build on earlier. **M0–M3 are Deliverable 1** (PQ-safe messaging
via the `nskey` data path); **M4–M6 are Deliverable 2** (the `at/pqmls` group
provider through to the pq-mls engine).

| Milestone | Capability added | Why it matters |
|---|---|---|
| **M0 · Pluggable crypto seam** | Per-value `CryptoProvider` routing via `appMetadata`; legacy + new schemes coexist | The migration machinery — old data readable forever, new schemes drop in as providers, no flag-day. Everything rides this seam. **Landed** (Wave-0). |
| **M1 · PQ primitives** | X-Wing hybrid KEM and pure ML-KEM-1024, AES-256-GCM, HKDF in at_chops; PQ enrollment-conveyance pubkey | The PQ/hybrid building blocks; closes the last harvest-now-decrypt-later hole (enrollment); the crypto-agile base. **Primitives landed and published** (`at_chops` 3.3.0 + 3.4.0, incl. ML-DSA-65 verify dispatch and the AES-GCM FFI backend); the enrollment-conveyance pubkey (P-3) is the remaining piece. ⚠️ **`at_chops` 3.6.0 — the second KEM, `pqSeal ver 0x03`, and the seed contract — is in-tree and NOT yet published** (KE-1). A published `at_chops` 3.5.0 exists but is a trunk release carrying `RsaSignatureAlgo` and PQ length validation, not this work. |
| **M2 · Per-APKAM identity / substrate** | Each APKAM keypair carries a key package naming its own KEM; the per-APKAM secret-sharing substrate beneath the `nskey` data path | The substrate that conveys `nskey` privates per-APKAM (D1) and underpins `at/pqmls` (D2); per-APKAM granularity + revocability. **In progress** — the substrate baseline (SS-0) and the atServer discovery verb (SS-1b) landed 2026-07-17 and 2026-07-07; wiring it to the live verbs and into AtClient is SS-1c/SS-2. |
| **M3 · the `nskey` data path** | `at/nskey` conveys the CK + `at/symmetric/AES/GCM` encrypts the data, as D1's default self **and** shared encryption; coarse FS via CK rotation; per-APKAM future-data revocation + PCS via `nskey`-keypair rotation; retires `selfEncryptionKey`/`shared_key.*` | **Completes Deliverable 1** — PQ-safe self + shared messaging, no group machinery in the app's face. |
| **M4 · `at/pqmls` intra-atSign groups (D2)** | `SecureGroup` v1 epoch engine; per-APKAM leaves; two-lever rotation | First forward-secure (intra-atSign) group encryption; the stable interface MLS later swaps under. |
| **M5 · `at/pqmls` cross-atSign groups + Group Delivery Service (D2)** | `(pair, namespace)`-scoped groups; the ciphertext-only Group Delivery Service (wake-then-pull, ordering/catch-up/retention) | First cross-atSign group encryption + the delivery service that makes *large* groups scale; precursor to NoPorts sessions. |
| **M6 · pq-mls engine (D2)** | Swap the v1 engine for MLS (TreeKEM, RFC 9420 FS/PCS, PQ ciphersuites) behind the same interface + DS | O(log n) commits, standardized + audited group security — the actual end state for the group path. |
| **NoPorts adoption** (finish line) | Session keys via `SecureGroup.export`; daemon-feature-gated tiers | The production payoff: PQ-safe NoPorts, derived (not transmitted) session keys, fleet management — reachable once D1 lands. |

> **Per-APKAM *groups* are D2 (`at/pqmls`), not D1's data path.** D1's self +
> shared path is the `nskey` data path; the shared secret-sharing substrate
> conveys `nskey` privates per-APKAM for D1 and group messages for D2.

**The phase trajectory in one line:** the build moves through **Phase A** (PQ
primitives & the enrollment-conveyance key) → **Phase S** (structural enablers:
the key stores and the WASM-readiness split) → **Phase SS** (the per-APKAM
secret-sharing substrate) → **Phase B** (the `nskey` data path) → **Phase R**
(rollout: the `disallowLegacyEncryption` flag, the key-material self-heal, and
the server self-enroll — the readiness lifecycle was removed,
[`decisions.md` 36](decisions.md#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05)) —
with, off the critical path, **Phase RF's client half** (the retrofit
orchestration), the
`selfEncryptionKey` retirement, PQ-native onboarding, and the **D2** carve. The
critical-path shape to GA is **seam → primitives → substrate → data path →
rollout → rotation** (D1 GA), with the v4 default flip as the final gated
cutover. The GA version slot is re-derived at execution against pub.dev — both
`at_client` 3.13.0 and 3.14.0 published on 2026-07-17, so it is no longer 3.14.x
— trunk already sits at 3.14.1.

**D1 development is complete; a "make it right" quality pass
follows before GA** — structural refactoring (readability, maintainability,
explainability) that lands the design goals the spike left implicit. Those goals
are ruled in [`decisions.md` §56](decisions.md#56-the-make-it-right-quality-pass-and-the-design-goals-it-settled-2026-08-09):
the signing chain is **root-anchored** (chain links provisional, the sweep
upgrades them; a root-holder conveys root links, not chain links); retrofit has
**three modes** with a per-retrofit signing-algorithm selector; and — the frame
for the whole cutover — **from the PQ project's view, 4.0 is final-3.x code with
only flag *defaults* changed.** Every rollout stage (the crypto era default,
`disallowLegacyEncryption`, the signed-envelope version, `EnrollmentKeyExchangeMode`,
the retrofit signing algorithm) is an independent flag with a 3.x and a 4.0
default, plus a convenience posture that sets them as a group; all the code ships
in 3.x, and the acceptance suite drives the entire rollout by flag manipulation.
No PR opens until the published atServer image verifies ML-DSA PKAM.

**Baseline on trunk** (so M0 and the M1 primitives are landed, not in flight):
`#1930` (the M0 pluggable-crypto seam), `#1993` / `at_chops 3.3.0`
(`pqSeal`/`pqOpen`), and `#2035` (design fixes). **As of the 2026-07-17 release
train**, `at_chops 3.4.0`, `at_commons 5.13.0`, `at_client 3.14.0` (carrying the
SS-0 substrate as an experimental surface) and `at_auth 3.3.0-rc1` are published,
and SS-0 / SS-1b / S-1 / S-2 are satisfied — `SS-1c` is the next actionable
project on the critical path. The full project sequence, the
dependency graph (ASCII), waves/parallelism, effort sizing, publish gates, the
critical path, and the coverage map are in
[`implementation-plan.md`](implementation-plan.md).
