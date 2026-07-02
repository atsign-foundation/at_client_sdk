# design.md — Detailed designs & implementation steps (by subsystem)

**Status:** working design doc (not plan-of-record). Lives in `docs/`.
**Purpose:** the detailed per-subsystem design + build-level implementation steps
(with `file:line` pointers) for the post-quantum crypto work — D1 (the nskey data
path) and the secret-sharing substrate it rides on. This is the "how it is built"
companion to four sibling docs (see the orientation table in [section 0](#0-scope-conventions--document-map)).

## Table of contents

- [0. Scope, conventions & document map](#0-scope-conventions--document-map)
- [1. Subsystem A — D1 nskey data path](#1-subsystem-a--d1-nskey-data-path)
- [2. Subsystem B — the secret-sharing substrate (WP-SS)](#2-subsystem-b--the-secret-sharing-substrate-wp-ss)
- [3. Subsystem C — at_chops PQ primitives](#3-subsystem-c--at_chops-pq-primitives)
- [4. Subsystem D — structural design (CryptoProvider seam, WritableAtKeys / key stores, WASM barrel)](#4-subsystem-d--structural-design-cryptoprovider-seam-writableatkeys--key-stores-wasm-barrel)
- [5. Subsystem E — worked design walkthroughs (NoPorts, at_talk)](#5-subsystem-e--worked-design-walkthroughs-noports-at_talk)
- [6. Implementation notes & file-level pointers (consolidated)](#6-implementation-notes--file-level-pointers-consolidated)
- [7. Trust boundary & residual threats](#7-trust-boundary--residual-threats)

---

## 0. Scope, conventions & document map

### This doc's lane

`design.md` owns the **detailed mechanics** of each subsystem and the
**build-level implementation steps** that realise them. It states *how* a thing
works and *where* the code lives — concrete key shapes, `appMetadata` encodings,
provider routing, the substrate envelope and verb contracts, the at_chops
primitives, the structural seams, and two worked design walkthroughs.

Explicitly **out of this lane** (cross-referenced, never duplicated):

| Not here | Lives in |
|---|---|
| The project sequence, dependency graph, waves, effort, publish gates, critical path | [`implementation-plan.md`](implementation-plan.md) |
| The Given/When/Then use-case catalogue (A1.x–A5.x, B0.x–B5.x) + test harness | [`acceptance.md`](acceptance.md) |
| The design rulings, the resolved and open decisions, and the decision timeline | [`decisions.md`](decisions.md) |
| The high-level WHY/WHAT — deliverables D1/D2, the nskey two-layer shape *conceptually*, migration philosophy, the phase trajectory | [`roadmap.md`](roadmap.md) |

When a mechanism's *rationale* matters, this doc links the decision in
`decisions.md` and states only the mechanics. When a mechanism needs a testable
case, this doc links `acceptance.md` and does not re-narrate the Given/When/Then.

### Conventions

- **`aS = pq`** (PQ-capable atServer) unless stated otherwise.
- **Key names are shown complete** — with the `@<owner>` suffix
  (`public:nskey.app_1.my_apps@alice`, not a bare `nskey`).
- **"Working name"** marks an at-key, provider, or verb name not yet finalised.
- Notation (namespace key-shape legend, `(owner, namespace)` identity discipline)
  follows the use-case catalogue in [`acceptance.md`](acceptance.md).
- Worked examples here are **mechanics traces**, not Given/When/Then — the
  testable form of each is in [`acceptance.md`](acceptance.md).

### Subsystem map

- **[Subsystem A — D1 nskey data path](#1-subsystem-a--d1-nskey-data-path)** (§1) — the three layers, three providers, key shapes, CK model, cold-start, FS/rotation levers, and migration/rollout + the `disallowLegacyEncryption` flag (§1.8).
- **[Subsystem B — the secret-sharing substrate (WP-SS)](#2-subsystem-b--the-secret-sharing-substrate-wp-ss)** (§2) — kpid addressing, `__ssenv`, push/pull, the discovery verb, the enrollment record, the self-retrofit flow.
- **[Subsystem C — at_chops PQ primitives](#3-subsystem-c--at_chops-pq-primitives)** (§3) — X-Wing, `pqSeal`/`pqOpen`, ML-DSA verify.
- **[Subsystem D — structural design](#4-subsystem-d--structural-design-cryptoprovider-seam-writableatkeys--key-stores-wasm-barrel)** (§4) — the CryptoProvider seam, `WritableAtKeys`/key stores, the WASM barrel split.
- **[Subsystem E — worked design walkthroughs](#5-subsystem-e--worked-design-walkthroughs-noports-at_talk)** (§5) — NoPorts, at_talk.
- **[Implementation notes & file-level pointers](#6-implementation-notes--file-level-pointers-consolidated)** (§6) — the consolidated `file:line` build map.

Within this doc: §1 (nskey data path) forward-refs §2 for its Layer-1 plumbing;
§2 references §3 for the seal/sign primitives; §4 (the structural seam) underpins
both §1 providers and §2 substrate; §5 walkthroughs reference §1/§2 for mechanics.

---

## 1. Subsystem A — D1 nskey data path

D1 ships a **single tier — the nskey data path** (rationale in
[`decisions.md`](decisions.md)).
Application data is encrypted under a symmetric **content key (CK)**; the CK is
X-Wing-sealed once to the recipient's **nskey** and written as a discrete conveyance
record; the nskey *private* reaches each authorised APKAM keypair over the
secret-sharing substrate. Each `(atSign, namespace)` has **one** nskey keypair: the
owner encapsulates her own CKs to it for self data, and external senders encapsulate
CKs to it when sharing with her. Self data and cross-atSign sharing use the
**identical** flow — only *whose* nskey the CK is sealed to differs.

This subsystem is the nskey data path's mechanics, in seven parts:

### 1.1 The three layers

The seam routes each stored value to a provider by its `appMetadata.providerId`:

```
LAYER 3  application data   ── AES-256-GCM under a symmetric CK ───────▶  provider  at/symmetric/AES/GCM
LAYER 2  content key (CK)   ── X-Wing-sealed to an nskey ──────────────▶  provider  at/nskey   (a discrete, once-delivered <ckKid>.__ck record)
LAYER 1  nskey PRIVATE      ── pqSeal to an APKAM key package ─────────▶  the secret-sharing substrate (plumbing, beneath the seam)
```

- **Layer 3 (data)** is pure symmetric: a value carries its AES-256-GCM
  ciphertext and *references* a CK by `ckKid`. It never touches asymmetric crypto.
- **Layer 2 (CK conveyance)** is the `at/nskey` provider: the CK is X-Wing-sealed
  to an nskey and written **once** as its own `<ckKid>.__ck.<ns>@<owner>` record;
  every Layer-3 value under that CK just cites the `ckKid`. This is decision **(a)**
  (decoupled content keys; rationale in [`decisions.md`](decisions.md)).
- **Layer 1 (nskey bootstrap)** gets the nskey *private* into each authorised
  APKAM keypair's keystore. It uses the same X-Wing sealing but is delivered
  **per-APKAM by the secret-sharing substrate** ([§2](#2-subsystem-b--the-secret-sharing-substrate-wp-ss)) — **transport, not a
  value-level provider** (decision **(ii)**). Once a client holds the nskey
  private, it unwraps any Layer-2 CK with one sync, O(1).

Layer 1 happens rarely (a client joins/upgrades); Layer 2 per CK (per epoch);
Layer 3 per data write.

### 1.2 The three providers (legacy, at/nskey, at/symmetric/AES/GCM)

| `providerId` | Tags a value that is… | Mechanism | Recipient (kid in metadata) |
|---|---|---|---|
| `legacy` | legacy data + inline-wrapped key (modern values never inline a key) | RSA-2048 + AES (monolithic) | RSA keypair. **Bare-name default** for an *absent* `providerId` (pre-convention data) |
| `at/nskey` | a **CK-conveyance record** (a sealed content key, cited by `ckKid`) | `X-Wing-seal` (the CK encapsulated to an nskey public half) — via `pqSeal`/`pqOpen` ([§3](#3-subsystem-c--at_chops-pq-primitives)) | the recipient's **nskey** — the owner's own nskey (self data) or another atSign's nskey (shared) |
| `at/symmetric/AES/GCM` | **application data** | AES-256-GCM under a CK | n/a (symmetric); the CK is cited by `ckKid` and resolved from cache (populated by `at/nskey` when its conveyance record synced) |

Notes:

- **`at/nskey` names a *role*.** The nskey system is stable; its KEM (X-Wing) is
  versioned by the key's kid, not by the providerId. The same X-Wing sealing also
  conveys nskey *privates* in Layer 1, but those ride the substrate as transport
  and are **not** value-level `at/nskey` records (decision (ii)).
- **`at/symmetric/AES/GCM` names the *algorithm* deliberately** — that is the
  layer that needs crypto-agility. A future `at/symmetric/AES/SIV` coexists; old
  values keep their tag.
- **Legacy interop.** A value with **no** `appMetadata.providerId` defaults to
  `legacy`. `legacy`, `at/nskey`, and `at/symmetric/AES/GCM` values coexist within
  a namespace and the seam routes per value. A writer emits the nskey data path's
  providers once the namespace has an nskey (else cold-start, [§1.4](#14-the-nskey-and-the-pqpublickey-root)); legacy data is read in place and re-encrypted only if rewritten.
- **Cold-start is NOT a third providerId.** Sealing the CK to the recipient's
  atSign-level root key is still an `at/nskey` record — only with
  `recipientKind: "root-pqpublickey"` ([§1.4](#14-the-nskey-and-the-pqpublickey-root)).

(The seam itself — `CryptoRuntime`, `CryptoConfig`, `appMetadata.providerId`
routing — is the structural subsystem [§4](#4-subsystem-d--structural-design-cryptoprovider-seam-writableatkeys--key-stores-wasm-barrel).)

### 1.3 Keys & key shapes

Concrete, `@alice` owner, namespace `app_1.my_apps` (reads right-to-left,
DNS-style). `K1…` = APKAM keypairs, `kp1…` their key-package kids, `ck7…`
content-key kids. Working names marked.

| Object | Shape | Published? | Who holds the private | Role |
|---|---|---|---|---|
| **nskey** | public half is the self at-key `nskey.app_1.my_apps@alice`, promoted to `public:nskey.app_1.my_apps@alice` on the namespace's first cross-atSign share | self at-key synced to Alice's `<ns>`-authorised clients; world-readable once promoted to `public:` | Alice's authorised clients (private conveyed via substrate) | Alice encapsulates **her own** CKs to it; external senders encapsulate CKs to it |
| **CK conveyance** *(working)* | `<ckKid>.__ck.app_1.my_apps@alice` (self key) | no | n/a (it *is* a sealed CK) | `at/nskey` value: `X-Wing-seal(ck)` to the nskey |
| **data value** | `<key>.app_1.my_apps@alice` | no | n/a | `at/symmetric/AES/GCM`: AES-GCM under a CK, cites `ckKid` |
| **substrate envelope** *(working)* | `<msgId>.<kpid>.__ssenv.app_1.my_apps@alice` (self key) | no | n/a | Layer-1 plumbing: `pqSeal(nskey private)` to key package `kp` |
| **APKAM key package** | per [§2.1](#21-kpid-addressing-__ssenv-envelope-signverify) | (enrollment record) | the APKAM keypair | recipient unit for Layer-1 |

Cross-atSign mirrors this with `@bob` as owner of the values he writes for
Alice — e.g. the data value `@alice:<key>.app_1.my_apps@bob` and the CK conveyance
`@alice:<ckKid>.__ck.app_1.my_apps@bob`, both sealed to Alice's **nskey** (its
`public:` half, which she published on this namespace's first cross-atSign share)
and synced to Alice as cached replicas. (This ownership is why cross-atSign
FS is bilateral — [§1.7](#17-forward-secrecy--rotation-levers-ck-rotation-vs-nskey-keypair-rotation).)

**The nskey private** for a namespace lives in an authorised client's keystore. It
is one KEM private that decapsulates both the owner's own CKs and the CKs external
senders sealed to her — it **decapsulates CKs**, it never decrypts application data.

**Multi-namespace keying.** The nskey private is keyed by `(owner atSign, namespace)`;
the CK cache by `(owner, namespace, ckKid)` — **never `ckKid` alone**, since kids
are not unique across namespaces. A value in a namespace for which the client holds
no nskey private is left **undecryptable** (yielded as an error), not silently
skipped — mirroring the `(owner, id)` identity discipline used elsewhere in the SDK.

**1:1:1 holding.** Each authorised APKAM keypair (one per keyfile/install/
enrollment — [§2](#2-subsystem-b--the-secret-sharing-substrate-wp-ss), decision #F in [`decisions.md`](decisions.md)) holds the namespace's
nskey private, received per-APKAM over the substrate.

**B1 build detail (one nskey keypair per namespace).** Per-`(atSign, namespace)` there
is **one** X-Wing nskey keypair. Its private is **minted as a fresh random keypair
and distributed per-APKAM over the substrate** (sealed to each authorised
enrollment's key package) — it is **never derived from a shared seed** ([`decisions.md`](decisions.md) §11).
The public half is published **lazily**: it starts as the self at-key
`nskey.<ns>@<atSign>` (synced to the owner's own `<ns>`-authorised clients, which is
all self data needs), and on the namespace's **first cross-atSign share** the same
public half is promoted to the world-readable `public:nskey.<ns>@<atSign>`
(immutable create-if-absent, **advertised as an APKAM-signed envelope** by the
publishing enrollment — verified against its `_apsk`, exactly as a key package; see
*Advertised-key authenticity*, [§2.1](#21-kpid-addressing-__ssenv-envelope-signverify))
so a sender can fetch it via plookup and verify its authenticity. A namespace used
only for the owner's own data keeps the self at-key form and never publishes a
`public:` key.

### 1.4 the nskey and the pqpublickey root

**The nskey's public half is published lazily.** It begins as the self at-key
`nskey.app_1.my_apps@alice` — an ordinary self key, synced to every one of Alice's
clients authorised for the namespace, exactly as any self key is. In this form it is
**not** a `public:` (world-readable) key and it **is** an at-key; the owner's own
clients hold it, which is all self data needs. On the namespace's **first
cross-atSign share** the *same* public half is promoted to the world-readable
`public:nskey.app_1.my_apps@alice` so an external sender can fetch it via plookup.
Only the public half's visibility changes (self at-key → `public:`); it is one
keypair throughout, and a namespace used only for the owner's own data never
advertises a `public:` key. The *private* half is the sensitive part: it cannot
ride the RSA-tainted self-encryption-key chain, so it is conveyed PQ-safely
per-APKAM as a `Secret` over the substrate. A client gets the public by ordinary
sync and the private from the substrate.

**pqpublickey root.** `public:pqpublickey@alice` is the atSign-level root KEM
target — the universal cold-start recipient (and the legacy default-encryption-key
replacement). When a sender has no `public:nskey.<ns>@<recipient>` to seal to
(namespace uninitialised / first contact), it falls back to encapsulating the
**CK** to `public:pqpublickey@<recipient>` (`recipientKind: "root-pqpublickey"`).
**Only the CK is sealed to the root key — application data is never encrypted
directly to it**, so the nskey-never-encrypts-data invariant holds (`pqpublickey`
is just another KEM target for the CK). Like the `nskey` public half, the published
`public:pqpublickey@<atSign>` is **advertised as an APKAM-signed envelope** by the
creating enrollment and verified against its `_apsk` (see *Advertised-key
authenticity*, [§2.1](#21-kpid-addressing-__ssenv-envelope-signverify)), so a
cold-start sender authenticates the root key before encapsulating to it. Once the
namespace promotes its nskey's public half to `public:nskey.<ns>@<recipient>`, new
CKs target the nskey; the root-keyed conveyance is the transient cold-start bridge,
lazily upgraded (B4).

**Naming.** Because this key is root (no namespace), its name carries no namespace
suffix: use **`pqpublickey`**, not `publickey.pq` (a `.pq` suffix would land it
*in* a namespace called `pq`). It mirrors the legacy `public:publickey@alice`
exactly. Its lifecycle (immutable create-if-absent, seed/serve/pull) is in
[§2.5](#25-the-authenticated-self-retrofit-flow-fresh-auto-approved-enrollment).

### 1.5 The CK model, cache, ckKid & appMetadata encoding

**`appMetadata` encoding — carries no `ns` field** (namespace comes from the
at-key name and the HPKE `info`, not from `appMetadata`):

- On an `at/nskey` **CK-conveyance record**:
  `{ providerId: "at/nskey", recipientKind, ckKid }` where
  `recipientKind ∈ { "nskey", "root-pqpublickey" }`.
  The record's `@<owner>` + key name identify *whose* nskey the CK was sealed to;
  `recipientKind` selects the recipient key class — the owner's `nskey` (used both
  for the owner's own CKs and for inbound CKs) or the cold-start `root-pqpublickey`.
  The `<ckKid>` in the key name equals
  `appMetadata.ckKid`. The value is the `pqSeal` envelope wrapping the CK (KEM ct +
  AEAD body) — **no separate `iv`/`kemCt`** on the conveyance.
- On an `at/symmetric/AES/GCM` **data value**:
  `{ providerId: "at/symmetric/AES/GCM", ckKid, iv }`. `iv` is the base64 12-byte
  GCM nonce, per value. **No sealed key is present** (decision (a)).

**`ckKid`** is the content key's id — a SHA-256 prefix of the CK (deterministic;
dedupes identical keys) or a random id. It must be unique within `(owner, namespace)`
and is the CK cache key alongside them.

**CK cache.** Keyed by `(owner, namespace, ckKid)`. Populated by the `at/nskey`
provider when a `<ckKid>.__ck` record syncs (decapsulate-then-cache); read by the
`at/symmetric/AES/GCM` provider on each data value.

**Key discovery.** A sender obtains a recipient's `public:nskey.<ns>@<recipient>`
via an ordinary public-key `plookup`, and re-fetches on a decapsulation-failure /
rotation signal (the recipient may have rotated the nskey keypair). The owner's
**own nskey is never looked up** for self data — her clients hold it from the
substrate ([§2](#2-subsystem-b--the-secret-sharing-substrate-wp-ss)); the
`plookup` is only how an external sender reaches the recipient's published nskey.

### 1.6 The uniform data flow + cold-start + resolution/ordering

One write/read pattern, **identical for self (Alice→self) and cross-atSign
(Bob→Alice)** — only *whose* nskey is the target differs:

**Write** (sender = whoever owns the data):
1. Choose/cut a symmetric **CK** (cadence is the sender's policy).
2. **Convey the CK once** (`at/nskey`): `X-Wing-seal(CK)` to the recipient's
   nskey — the owner's **own** nskey for self data; the recipient's **published**
   nskey (its `public:` half) for shared — written as a `<ckKid>.__ck.<ns>@<owner>`
   record. (Skip if the CK is already conveyed.)
3. **Write data** (`at/symmetric/AES/GCM`): AES-256-GCM under the CK; stamp
   `ckKid` (+ `iv`) in `appMetadata`.

**Read** (recipient = an authorised client):
1. On syncing a `…__ck…` record, `at/nskey` **decapsulates the CK** with the
   matching nskey private and caches it by `ckKid`.
2. On a data value, `at/symmetric/AES/GCM` **resolves the CK by `ckKid`** (from
   cache) and AES-GCM-decrypts.

**Resolution & ordering.** Sync is not ordered, so a Layer-3 data value can arrive
**before** (or without) its CK conveyance. On a `ckKid` cache miss the
`at/symmetric/AES/GCM` reader (a) decapsulates the local `<ckKid>.__ck` record on
demand if present, else (b) yields a `Stream.error` / deferred state and re-attempts
when the conveyance syncs — mirroring `getItemsAsStream`'s per-key decode-failure
convention. A value whose CK was deleted for forward secrecy stays undecryptable,
by design.

**Cold-start.** When the sender has no `public:nskey.<ns>@<recipient>` (namespace
uninitialised / first contact), seal the **CK** to the recipient's root
`public:pqpublickey@<recipient>` (`recipientKind: "root-pqpublickey"`) — data is
still AES-256-GCM under that CK; data is **never** encrypted directly to root
([§1.4](#14-the-nskey-and-the-pqpublickey-root)). The first cross-atSign share promotes the namespace's nskey
public half to `public:nskey.<ns>@<recipient>`; subsequent writes upgrade to
namespace-scoped (B4 lazy upgrade). A strict-mode
seal-and-hold alternative is a policy toggle (D1-C, see [`roadmap.md`](roadmap.md)).

**Binary-safe.** Seal/open **bytes** and honour `isBinary`; never round-trip binary
through `utf8.encode(plaintext.toString())`, which corrupts it.

### 1.7 Forward secrecy & rotation levers (CK rotation vs nskey-keypair rotation)

Two distinct levers with very different costs. (The FS-as-policy ruling and why D1
is single-tier are in [`decisions.md`](decisions.md); the testable rotation/revocation cases
are in [`acceptance.md`](acceptance.md).)

**(B5a) CK rotation — the cheap, coarse-FS lever. O(1).**
Mint a fresh CK, cut a new `<ckKid>.__ck` conveyance sealed to the namespace's
nskey; new data uses the new CK. For FS: **delete the old `at/nskey` conveyance
record** and **every client evicts the cached CK when it observes that record's
deletion via sync** — that observed deletion is the eviction trigger. The
superseded CK can no longer be unwrapped (decision (a) makes this possible: the CK
was never embedded in data values). It rides **ordinary sync, not the substrate**.
Conveying the new CK is O(1) — one record, every client unwraps with the shared
nskey private.

- **Retention knob.** Default: **retain** the `__ck` records (no ttl) → a
  late-joining APKAM keypair reads history (legacy-like; no FS). **Delete** on
  rotation → coarse FS. An offline / never-resynced client that retains a cached
  CK is the residual: coarse FS is bounded by eviction *reachability*, not only by
  record deletion. Deletion discipline is the FS trusted-computing base.

**(B5b) nskey-keypair rotation — the expensive PCS + revocation lever. O(n) per-APKAM.**
Mint a **new nskey keypair** → re-publish its public half (re-promote to
`public:nskey.<ns>@<atSign>` if the old one was published) → convey the new nskey
private **per-APKAM over the substrate** (`__ssenv` envelopes sealed to each
authorised APKAM keypair's key package, pushed via `enroll:listns` + the
pull backstop — [§2](#2-subsystem-b--the-secret-sharing-substrate-wp-ss)),
**excluding** any revoked keypairs (`excludeEnrollmentIds`). Buys
namespace-granular **post-compromise security**; it is the per-APKAM revocation
lever. It does **not** give per-message FS or history re-encryption (the old nskey
private retained → history-on). Coarse FS comes from B5a, not from this.

**(B6) Revocation wiring.** Composes: (1) enrollment revocation (`enroll:revoke` —
APKAM, free, cuts future server access); (2) nskey-keypair rotation **excluding**
the revoked enrollment (`excludeEnrollmentIds`, B5b); (3) optional history
re-encrypt (expensive — D2). A revoked enrollment, excluded from a rotation, cannot
read post-rotation data.

**Cross-atSign FS is bilateral.** For self data the owner is both endpoints — she
cuts the CK and owns the authoritative conveyance + cache, so she forward-secures
unilaterally. For inbound, the sender (`@bob`) cuts the CK on **his** cadence and
the authoritative `at/nskey` conveyance lives in a record **owned by `@bob` on
bob's atServer**; Alice holds only a synced cached replica keyed to her stable
nskey private. Alice can purge her cache but cannot delete Bob's
authoritative copy — so closing inbound FS depends on Bob's cooperation (or the
heavier nskey **keypair** rotation lever, B5b). This is normal for any FS
system, not an nskey deficiency.

**Out of scope (D2 — `at/pqmls`).** Robust/per-message FS via ratcheted leaves (no
standing master key), O(log n) large-group scale, and groups whose membership is
decoupled from namespace authorisation. See [`roadmap.md`](roadmap.md) /
[`decisions.md`](decisions.md).

### 1.8 Migration, rollout & the `disallowLegacyEncryption` flag (D1-C / D1-D)

The nskey data path coexists with legacy and is adopted by **negotiation + a gated
rollout** — no flag day. (Sequencing: `R-1` lands this machinery + the flag
default-`false` in 3.x; `R-2` flips the default `true` in 4.0 — see
[`implementation-plan.md`](implementation-plan.md); the rationale/timeline is in
[`decisions.md`](decisions.md).)

**Capability tiers — what a build gets for what effort.**
- *Rebuild only* → a **universal reader** + back-compat writer: decrypts anything
  ever written (legacy or nskey) and keeps writing legacy. Upgrading only ever
  **adds** read capability — a rebuilt client never loses access.
- *Set `disallowLegacyEncryption`* → a **PQ writer/recipient**.
- *Write code* → override the per-destination defaults.

**C1 — readiness-marker lifecycle.** A per-`(atSign, namespace)` marker is published
**not-ready** on upgrade and flips **ready** when the namespace's fleet is upgraded.
The flip is **operator-declared** (one config/policy call — the primary lever)
and/or **auto-detected** ("no legacy client has checked in recently"); the SDK warns
on a flip while a recent legacy check-in exists. The flip is the **only operator
judgement call** — flipping while a legacy reader still runs is the one way to break
a reader. 

**C2 — per-destination negotiation (behaviour-neutral by default).** The sender
writes the scheme **every required reader supports**: the nskey data path only when
the readers' marker (and, for self copies, its own) is **ready**, else legacy. A
bare rebuild **reads** all schemes but keeps **writing legacy** until the marker
flips — a zero-risk soak. `appMetadata.providerId` on each stored value **and** on
the notification frame tells the recipient which provider opens it; **reads are
universal** regardless of the writer's scheme.

**C3 — strict-mode toggles (per-namespace, simple-code tier).** Refuse legacy
fallback; cold-start policy (**seal-and-hold** vs error vs notify —
[§1.6](#16-the-uniform-data-flow--cold-start--resolutionordering)); custom rotation triggers.

**D1-D — the `disallowLegacyEncryption` flag.** A flag on `AtClientPreference`:
- **Final at `AtClient` construction (immutable)** — no mid-run flipping, no setter.
- **Default `false` in 3.x → `true` in 4.0** (the cutover is `R-2`).
- Means literally: **never write *new* data using the legacy provider for
  encryption** — use a PQ path or **refuse the write** (a legacy-only recipient ⇒
  refused, never a silent legacy write).
- **SHOUT-level log at creation whenever it is `false`**, so a non-PQ default is
  never silent.
- **Governs only legacy-provider *encryption*.** Legacy **read** is always available
  (history stays readable) and `shouldEncrypt=false` (the app-accessible no-crypto
  path) is unaffected.
- The **cold-start PQ fallback** (CK X-Wing-sealed to `public:pqpublickey@<recipient>`
  via `at/nskey`, [§1.4](#14-the-nskey-and-the-pqpublickey-root)) is a
  **PQ path, not a legacy write** — it must **not** trip the `=true` refusal.

All additive within `at_client` 3.x; the legacy provider itself **stays** — it is
needed for reads forever.

---

## 2. Subsystem B — the secret-sharing substrate (WP-SS)

The substrate is the PQ-safe per-APKAM transport beneath both D1 (Layer 1: the
nskey privates) and D2 (`at/pqmls` group keys). **Pull (`requestSecret`) and push
(`pushSecretToNamespaceMembers`) are dual facets of ONE substrate** — the shared
substrate facts (envelope shape, the discovery verb, seal-vs-gate security,
idempotent merge, transport) are stated **once** below; the pull and push
subsections reference them rather than restate.

**Recipient unit = an APKAM keypair**, addressed by `kpid` (the kid of its X-Wing
key-package public half). **1:1:1:** one keyfile = one APKAM keypair = one key
package = one enrollment (decision #F, [`decisions.md`](decisions.md)) — there is **never** more
than one keypair per enrollment. A secret sealed to a key package is openable by
every client process sharing that keyfile, so per-process sealing would be
redundant. The genuinely per-APKAM artefacts (the PQ APKAM signing keypair, the
X-Wing key-package *private* half) are minted locally and **never on the wire**;
everything *shared* is scoped at atSign / namespace / group level.

**Current state.** The client substrate is built and unit-green on
`gkc-jt-secret-sharing-substrate` (`pairwise_secret_sharing.dart`,
`secret_envelope.dart`, `key_package.dart`, `secret_store.dart`,
`enrollment_directory.dart`, `mixins/envelope_signing.dart`) — but it is **not
wired into AtClient**, the **server verb is absent**, and the **consumer layers**
(nskey minting, `pqpublickey` lifecycle, PQ APKAM mint + retrofit) are absent.
Additionally, the built `VerbEnrollmentDirectory` still speaks the **retired** wire
shape — a nested `apkam[]` response parse plus the removed `enroll:metadata`
registration write — contrary to decision #F (1:1:1) / OQ9; the WP-SS rework
(PR #2037 / SS-1c) rewrites it to the flat, single-key, `enroll:listns`,
no-write-path model. The
full built/gap inventory with `file:line` evidence is in
[§6](#6-implementation-notes--file-level-pointers-consolidated).

### 2.1 kpid addressing, __ssenv envelope, sign/verify

**Envelope key shape.** `<msgId>.<kpid>.__ssenv.<ns>@<owner>` — a self key,
`shouldEncrypt=false` (the value is already ciphertext). The body is raw `pqSeal`
bytes (HPKE + AES-256-GCM, HKDF info domain-separation `'at_client/secret_sharing/v1'`).
The same envelope carries both the *request* (pull) and the *response*.

**Two gates protect every copy:**

- **Transport gate (atServer, by namespace).** The envelope carries the `<ns>`
  suffix, so the atServer delivers it only to enrollments authorised for `<ns>` —
  identical to the gate on the data itself. **Defence in depth.**
- **Crypto gate (the key package private).** The body is `pqSeal`ed to one
  specific APKAM keypair's key package, so only the holder of that keyfile's
  key-package private half can open it. **This is the confidentiality boundary.**

So even if a sender sealed to the wrong key package, the server would not deliver
it: discovery/sealing mistakes cannot leak. Gate = defence in depth; seal = boundary.

**Sign / verify-before-decrypt.** Each envelope is **APKAM-signed**; the receiver
**verifies before decrypt** (`_consume`), proving a genuine owner-client wrote it.
Per-enrollment `_apsk` signing-key resolution drives the verify.

**Advertised-key authenticity (decision 2026-07-02, [`decisions.md`](decisions.md) §6).**
Every *advertised recipient key* — the per-enrollment **key package** (Layer 1), the
published **`nskey`** public half, and **`public:pqpublickey@<atSign>`** — is itself
wrapped in an **APKAM-signed envelope** by the enrollment that generates it (the same
`wrapAndSign` / `AtSigningMode.pkam` construction as `__ssenv`, `envelope_signing.dart`).
Verifiers — **same-atSign and cross-atSign, identically** — fetch the generating
enrollment's `_apsk` public key
(`public:_apsk.<enrollmentId>.<perEnrollmentApproved>@<atSign>`, per the
`ApkamSigning` mixin) and verify the signature. The signed envelope **self-describes
enough to verify** — `signingAlgo` (which implies the `_apsk` key type: RSA / ML-DSA /
ECC) and `hashingAlgo` — so the verifier selects the right routine and a lie about
`signingAlgo` merely fails the verify against the real `_apsk` key; authenticity
anchors on that key. This **supersedes** the earlier "key packages are unsigned; the
atServer vouches" stance — the crypto gate's *recipient key is now authenticated*, not
merely server-asserted. For a **keypair secret** conveyed over the substrate
(`nskey` / `pqpublickey` privates) the receiver additionally checks public/private
correspondence against the (signed) published public half — a useful secondary check,
subordinate to the signature.

**Trust nuance.** The signature is verified against `_apsk`, which the atServer serves —
so it authenticates against a rogue *insider* enrollment (under an honest server) but
**not** against a malicious atServer *operator*, which controls both the signature key
and the `_apsk` it is checked against. This holds same-atSign and cross-atSign alike;
the operator of an atSign's atServer stays in the confidentiality TCB for data destined
to that atSign until the anchor is distributed independently. See
[§7 Trust boundary & residual threats](#7-trust-boundary--residual-threats) for the full
model and the mitigation ladder — do **not** describe signing as removing the atServer
from the TCB.
*(Current gaps: advertised-key signing + verify is not yet implemented — the substrate
signs `__ssenv` envelopes but advertises the key package unsigned
[`pairwise_secret_sharing.dart:360-407`], and the correspondence check is likewise
pending. Both are substrate work: sign in the mint paths [SS-2 / SS-4], verify on read
[SS-1c].)*

`file:line` evidence: `pqSeal`/`pqOpen` of `__ssenv` (`pairwise_secret_sharing.dart:191,398,99`;
`pq_hpke.dart:80`); sign + verify-before-decrypt (`envelope_signing.dart:74,152`;
verify precedes open at `pairwise_secret_sharing.dart:366`); kpid addressing
(`secret_envelope.dart` `toKpid`/`fromKpid`); per-APKAM `KeyPackage`
(`key_package.dart:29,76,108,156`).

### 2.2 SecretStore, push & pull primitives

**Shared substrate facts (stated once):**

- **`SecretStore.putIfNewer`** — idempotent, **monotonic-version** merge
  (version-ordered, so wall-clock skew cannot reorder writes); reserved `__` system-secret-name guard. This is why push ∥
  pull compose: arrival is idempotent, so a push failure is never fatal — pull
  still serves a missed client later (pull is the correctness backstop).
  (`secret_store.dart:117,126,98`.)
- **Transport** = `atClient.put` of the `__ssenv` key + a **sync** delivery path
  (sync-progress listener + periodic local sweep → `receivedSecrets`), so it is
  offline-tolerant by construction; **plus an optional wake-up `notify`**
  (default on) per put, so sync-less clients wake on their notification monitor
  and `get` the key (`useRemoteAtServer`). Applies to both request and response.
  (Future: the atServer auto-notifies on `__ssenv` puts — see DEP4 in
  [§6](#6-implementation-notes--file-level-pointers-consolidated); DEP4 is delivered
  inside SS-2 per the implementation plan — the auto-notify is additive and could ship
  independently, but the client default-flip is sequenced in SS-2.)
- **Responder authorisation = namespace authorisation.** Serve a namespaced secret
  to requester `R` only if `R`'s enrollment is authorised for that namespace; the
  authoritative source is the server-sourced discovery verb ([§2.3](#23-the-enrolllistns-verb--enrollparamsmetadata)), not a client
  self-claim. **Never serve to an `excludeEnrollmentIds` member** (revoked).
- **Root `pqpublickey` is the no-namespace exception** — like the legacy default
  encryption private key, it is served to **every non-revoked enrollment**
  regardless of scope (no namespace gate). *(Current gap: this serve branch is not
  yet implemented — `grep pqpublickey` in `secret_sharing/` = 0.)*
- **`namespaceAuthorizes`** — suffix/`*` match mirroring the atServer rule
  (`secret_store.dart:169`).
- **No-holder-online** → the request persists on the secondary; a holder answers
  on next online. **Thundering-herd** → responders jitter + suppress on observing
  the answer already delivered; dedup via `putIfNewer`. **Freshness** → secrets
  carry a version (epoch / `kid`); `putIfNewer` keeps the newest.

**`requestSecret(name)` / `waitForSecret` (pull).** Targeted fan-out — **no
keyless broadcast**. Discover the namespace's authorised APKAM keypairs and their
key packages via the gated verb ([§2.3](#23-the-enrolllistns-verb--enrollparamsmetadata)); `pqSeal` a request to each `kpid`,
carrying the requester's *own* `kpid` so responders know where to seal the answer.
A holder serves with `shareSecretWith(keyPackage, Secret)` (`pqSeal` back to the
carried `kpid`); the requester `waitForSecret` resolves on the first valid
response, verifies, and stores. (`pairwise_secret_sharing.dart:479,454,497`.)

**`pushSecretToNamespaceMembers(Secret, {exclude})` (push).** Verb → seal once per
key package → `put` the `__ssenv` envelope → wake-up notify. This is the
steady-state convergence that keeps reads fast (the secret is already on-device
before a client needs it). Requirements 1 (mint) and 3 (rotation) collapse to this
one method; only the `Secret` and exclude-set differ.
(`pairwise_secret_sharing.dart:662`.)

**`shareAllSecretsWithEnrollment(E, approvedNamespaces)` (approval-time conveyance).**
The approver already holds the new enrollment's id, its granted namespaces, and its
key package, so it conveys each held secret for a granted namespace **without a verb
call or poll** (no enumerate-all step). (`pairwise_secret_sharing.dart:689`;
`excludeEnrollmentIds` guard threaded at `:458,641,694`.)

### 2.3 The enroll:listns verb + EnrollParams.metadata

A pusher (or puller) needs two facts: **who** is authorised for the namespace, and
**what key** to seal to for each. One gated verb returns both.

> **`enroll:listns:<ns>`** — returns every **approved**
> enrollment authorised for `<ns>`, with its access level, its APKAM public key,
> and its key-package metadata. **Gated:** the caller must hold ≥`r` on `<ns>`.

- **Server-sourced & authoritative** — the authorisation comes from the atServer's
  enrollment records, not a client self-claim, so the member list is complete and
  trustworthy, **including read-only enrollments** (which cannot self-advertise
  into a namespace they can't write).
- **Self-contained** — the X-Wing key package travels in the enrollment record
  alongside the ML-DSA APKAM public key; the verb returns it. One gated call yields
  *authorisation + every encapsulation key* — no separate fetch, no public records.
- **Gate scope** — ≥`r` is the right bar: any pusher (the `rw` minter, a rotator)
  clears it, and a read-only co-member learning the roster of a namespace it
  already belongs to is not a leak.

**Response shape — FLATTENED, one element per enrollment (1:1:1):**

```
data:[{ enrollmentId, access:'r'|'rw', apkamPubKey, metadata }]
```

There is **no nested `apkam[]` array** — each enrollment has exactly one APKAM
keypair and one key package, so the element is flat.

**Key package rides `EnrollParams.metadata`.** The key package is registered as an
**opaque `Map<String,dynamic>` on `EnrollParams.metadata`** at `enroll:request`
time (a JSON tail on the existing request — **no grammar change**); the server
stores it on the enrollment record and returns it from the discovery verb. There
is **no `enroll:metadata` verb** and **no post-enrollment metadata write, ever**.
Old clients tolerate an absent `metadata` (the discovery element simply omits it).

The key package sits at a **singular `metadata.keyPackage`** (1:1:1 — one enrollment,
one key package; **no format-keyed `keyPackages` map** — key/suite agility already
lives inside the package via `keys[].alg` + `KeyPackage.v`). Its value is the
**APKAM-signed envelope** wrapping the key-package payload (see *Advertised-key
authenticity*, [§2.1](#21-kpid-addressing-__ssenv-envelope-signverify)); the server
stores and returns it opaquely and has no opinion on its contents.

**atServer build points** (verb spec; effort **L** — full DEP1 spec in
[§6](#6-implementation-notes--file-level-pointers-consolidated)):

- `at_commons/lib/src/verb/operation_enum.dart:24-33` — add `listns`
  to `EnrollOperationEnum` (adjacent to `list`).
- `at_commons/lib/src/verb/syntax.dart:151` — **fold `listns` INTO the
  `(?<operation>…)` group, longest-first (before `list`, else `list` prefix-wins)**,
  with an optional `:(?<listNamespace>…)` segment. A *separate* top-level
  alternative leaves the `operation` group null and the handler does `operation!`
  (`enroll_verb_handler.dart:85`) → NPE — so the op token **must** populate
  `operation`.
- `at_secondary_server/.../enroll_verb_handler.dart` — extend the enrollParams
  guard (`:74-83`) to exempt `listns`; add `case 'listns':`
  (after `:144`) → a new `_listForNamespace` helper (model on `_fetchEnrollmentRequests :481`);
  add a `_validateParams` case (`:630`) asserting the namespace is present.
- **Gate** with a fresh helper that **mirrors `_checkForNamespaceAuthorization`**
  (`abstract_verb_handler.dart:332-365`, suffix-match + `*` fallback) then requires
  `access ∈ {r, rw}` — **do NOT reuse `_isReadAllowed` (`:412`)**, which is
  verb-type-gated and excludes `Enroll`. Legacy null-enrollmentId connection = full
  access.

### 2.4 The atServer enrollment record + ML-DSA APKAM auth

**The enrollment record stores a SINGLE `apkamPublicKey` + a `signingAlgo`**
(`rsa2048 | mldsa65`) — 1:1:1 (decision #F). There is **no list of APKAM keypairs**,
no verify-against-any, no `ApkamPublicKey[]`. PKAM verifies against that one key,
bound to its stored algo.

**ML-DSA APKAM auth is retained** (PQ-safe authentication):

- **at_chops** — the `mldsa65` `SigningAlgoType` member ALREADY ships
  (`algo_type.dart:10`); add only the `mldsa65` branch in `_getVerificationAlgorithm`
  (`at_chops_impl.dart:284`) returning the existing `MlDsa65PureDartAlgo` /
  `MlDsa65FfiAlgo` ([§3](#3-subsystem-c--at_chops-pq-primitives)).
- **at_commons** — widen the pkam `signingAlgo` alternation for an ML-DSA literal
  (`syntax.dart:10`).
- **at_secondary_server** — `_getSigningAlgoType` (`pkam_verb_handler.dart:199-210`)
  gains an ML-DSA branch and must read the **RECORD's** `signingAlgo`
  (**record-authoritative**), **not** the client-supplied wire value (`:164`).
  This prevents algorithm-confusion: a forger cannot down/upgrade the verify path
  by lying on the wire.

**Migration.** A legacy single-string record migrates to `signingAlgo=rsa2048` on
`fromJson` (the historical default); the legacy `atPkamPublicKey` mirror is
preserved so old clients authenticate unchanged. `enroll_datastore_value.dart`
gains the `signingAlgo` + `metadata` fields; regenerate `.g.dart` via `build_runner`
(don't hand-drift). Full DEP3 spec (effort **XL**) in
[§6](#6-implementation-notes--file-level-pointers-consolidated).

**Cross-tier property (atServer-guaranteed): `_apsk` is present and write-restricted.**
Both envelope sender-authenticity **and** advertised-key authenticity
([§2.1](#21-kpid-addressing-__ssenv-envelope-signverify)) rest on the `_apsk` published
signing key. The atServer guarantees two things about
`public:_apsk.<enrollmentId>.<perEnrollmentApproved>@<atSign>`:

1. **Always present (decision 2026-07-02).** The atServer populates `_apsk` from the
   enrollment record's stored `apkamPublicKey` (on approval / first authenticated use),
   rather than leaving it to the client-side `ApkamSigning.publishPublicSigningKey`
   get-then-put — which removes a race (a verifier fetching before a generator has
   published) and a missing-key failure mode. A verifier can always resolve a signer's /
   generator's `_apsk`.
2. **Write-restricted.** Writes to that key are restricted to that enrollment's own
   authenticated connection — a client fetches the `_apsk` public key and trusts it.

The write-restriction was verified empirically against the released atServer (June 2026);
both properties MUST be asserted by e2e tests (a second enrollment cannot overwrite
another's `_apsk`; an approved enrollment's `_apsk` is fetchable without the client
having published it) and are stated in the atServer DEP list, because both the
substrate's sender-authentication and its advertised-key authenticity collapse if these
regress.

### 2.5 The authenticated self-retrofit flow (fresh, auto-approved enrollment)

**Retrofit is a fresh, self-spawned, AUTO-APPROVED enrollment — NOT a mutation of
an existing one.** (Rationale in [`decisions.md`](decisions.md); the testable
sequence in [`acceptance.md`](acceptance.md).)

**The flow.** An authenticated pre-PQ client:

1. **Submits `enroll:request` with a NEW `enrollmentId` on its already-authenticated
   connection** — **no OTP** (it is already authenticated). The request carries the
   PQ APKAM public key + `signingAlgo=mldsa65` and the X-Wing key package via
   `EnrollParams.metadata` ([§2.3](#23-the-enrolllistns-verb--enrollparamsmetadata)).
2. The **server validates** that the requested namespaces are a **subset** of the
   authenticating enrollment's namespaces, then **auto-approves** (no human step,
   no OTP).
3. The server **COPIES the old enrollment's expiry** (or `null`) to the new
   enrollment, and **CAPS the old enrollment to `min(now + server-config grace,
   its existing expiry)` WITHOUT removing it**. The old enrollment ages out on the
   expiry timer; it is not deleted in place.
4. The new client **registers** its key package (already carried in step 1's
   `EnrollParams.metadata` — no post-enrollment write), then **pulls** `pqpublickey`
   + the namespace nskey privates over the substrate ([§2.2](#22-secretstore-push--pull-primitives)), **verifies
   correspondence**, and stores them in the local keystore (`WritableAtKeys`, [§4](#4-subsystem-d--structural-design-cryptoprovider-seam-writableatkeys--key-stores-wasm-barrel)).

**Each cloned pre-PQ keyfile retrofits to its OWN distinct `enrollmentId`** (1:1:1).
A keyfile copied onto a second host mints its own single, *different* PQ APKAM
keypair and spawns its own enrollment — never a shared one.

**Mint-once per keyfile.** Under a host-local lock: if the keyfile already carries
a PQ APKAM keypair, use it; else mint one and persist it. Storage decision
(2026-06-24): the **copyable AtKeys file by default** (portable, dev/test-clean —
a reused keyfile doesn't re-mint); **OS-keychain / hardware is opt-in hardening**
(off by default); revocation is **per-keyfile-key**; server-side **TTL / usage
eviction** prunes keys unused for N days. A distinct labelled per-APKAM record
(hostname / install-UUID) drives a usable per-APKAM revocation UI (the label is an
administration aid, not a security boundary).

**Legacy retirement.** Driven by the **enrollment-expiry timer** (the capped old
enrollment ages out) **+ the existing `enroll:revoke`**. There is **no
per-APKAM-key delete operation** — the old enrollment's expiry cap is what retires
the pre-PQ credential. (Per-APKAM auth revocation of a *live* PQ enrollment is the
existing `enroll:revoke`; per-APKAM future-data revocation is nskey-keypair rotation
excluding it, [§1.7](#17-forward-secrecy--rotation-levers-ck-rotation-vs-nskey-keypair-rotation).)

**`pqpublickey` lifecycle.** Immutable **create-if-absent** (`Metadata.immutable` —
a long-standing atServer feature, already live; no server change). The creator wins
the create, generates the X-Wing keypair (`kid = H(pub)`), stores the private half,
seeds it as the conveyable root secret `pqid:<kid>`, and serves it on request. A
non-creator's create is rejected → it **pulls** the private half ([§2.2](#22-secretstore-push--pull-primitives)), verifies
public/private correspondence, and stores. Because the immutable write is atomic,
exactly one keypair is ever published; everyone else falls through deterministically
to "pull." Two populations **never** run this retrofit: a new atSign is PQ-native at
onboarding; a new (post-PQ) enrollment receives `pqpublickey` *pushed* by the
approver. F-section build detail (F1–F6) in [§6](#6-implementation-notes--file-level-pointers-consolidated).

---

## 3. Subsystem C — at_chops PQ primitives

The providers and the substrate seal through one audited PQ primitive.

**X-Wing KEM** (`draft-connolly-cfrg-xwing-kem-10`): ML-KEM-768 + X25519 with the
SHA3-256 combiner; 32-byte seed secret keys expanded via SHAKE-256. Vector-verified
byte-exact against the draft's Appendix C vectors (incl. derandomized encapsulation).
**ON TRUNK** (`at_chops 3.3.0`, published 2026-06-23).

**`pqSeal` / `pqOpen`** — the one audited PQ public-key-encryption primitive:

```
pqSeal(recipientPubKey, plaintext, {info, aad}) → envelope
pqOpen(recipientSecretKey, envelope, {info, aad}) → plaintext
```

- KEM = X-Wing; KDF = HKDF-SHA256; AEAD = AES-256-GCM. **Stateless**, KEM
  injected, single-shot derived nonce. (`pq_hpke.dart:80`.)
- **Properties:** round-trip /
  tamper→`authFailure` / `info`-`aad`-mismatch / version-malformed tests; **reuse
  the existing `AesGcm256EncryptionAlgo` / `HkdfSha256` / `HmacSha256`** rather than
  re-importing `package:cryptography`; keep the primitive **protocol-agnostic**
  (label-generic — hoist any NoPorts `pqDerive*` helpers up); dartdoc as
  **HPKE-*style*** (a custom envelope, not the RFC-9180 wire).
- **BASELINE:** `pqSeal`/`pqOpen` ship in **`at_chops 3.3.0` (ON TRUNK)** alongside
  the **stateless functional core** (keys passed per call) + a `@Deprecated
  AtChopsImpl(keys)` shim over it so the ~65 construction sites compile unchanged
  and migrate gradually.

**ML-DSA (`mldsa65`) verify.** `MlDsa65PureDartAlgo` / `MlDsa65FfiAlgo` (implementing
`AtSigningAlgorithm.verify`) **already ship** in at_chops. To wire PQ APKAM auth,
add only the `_getVerificationAlgorithm` branch (the `mldsa65` member already ships)
returning the existing algo (FFI vs pure-Dart) — **do not write a new algo class** ([§2.4](#24-the-atserver-enrollment-record--ml-dsa-apkam-auth)).

**Backend policy (2026-07-02).** The FFI backend auto-resolves as the default where a
native library is present, with the pure-Dart backend as fallback; WASM builds force
pure-Dart. (Ruling in [`decisions.md`](decisions.md).)

**PQ enrollment-conveyance public key.** Publishing the atSign-level X-Wing public
key (`public:pqpublickey@alice`) alongside `public:publickey@alice` closes the last
harvest-now-decrypt-later hole — new enrollees prefer it for wrapping
`apkamSymmetricKey`; approvers accept either. **No server change.** (This is also
the cold-start fallback recipient for the nskey data path — [§1.4](#14-the-nskey-and-the-pqpublickey-root) — so build it first.)

---

## 4. Subsystem D — structural design (CryptoProvider seam, WritableAtKeys / key stores, WASM barrel)

The seams every other subsystem is built on. The S-1..S-6 *project* sequencing is
in [`implementation-plan.md`](implementation-plan.md); this section owns the *design*.

### The CryptoProvider seam (M0)

**ON TRUNK** (`#1930`, merged). Stateless `CryptoProvider`:

```
CryptoProvider { id; encrypt(CryptoContext, AtKey, String) → String; decrypt(CryptoContext, AtKey, String) → String }
```

- **`CryptoRuntime`** resolves each put/get/notify/sync against the **live**
  `AtClientPreference.crypto` (`CryptoConfig { defaultProviderId, providers, lookup }`)
  by `appMetadata.providerId`, falling back to the built-in `LegacyCryptoProvider`.
- The wire carries `Metadata.appMetadata = AppMetadata{ providerId, additional }`;
  the SDK **stamps `providerId` + `isEncrypted`** after a successful encrypt, so a
  provider only contributes `additional`.
- An unknown scheme throws `CryptoProviderNotRegistered`.
- `PutRequestOptions.cryptoProviderId` overrides per operation (the per-destination
  gate the NoPorts walkthrough uses, [§5](#5-subsystem-e--worked-design-walkthroughs-noports-at_talk)).
- **Cached-client reuse adopts the new `preference.crypto`**: a
  same-atSign re-set with a new provider config re-applies it — no
  `CryptoProviderNotRegistered` flake.
- **No `CryptoRegistry` / `CryptoPolicy` / `CryptoStorage`** and **no `cryptoRegistry`
  getter on the `AtClient` spec.**

**Get-path invariants.** `get` respects the `isEncrypted` tri-state (explicit
`false` skips decryption; absent = try-decrypt fallback; `true` decrypts via the
routed provider). `shouldEncrypt = false` is a true no-crypto path on write and
read — secret-sharing envelopes and key-package copies are stored that way.

### `WritableAtKeys` + key stores

**`WritableAtKeys`** (working name; deferred — not yet wired) is a **subclass of
at_auth's `AtKeys`** (the key-material holder) adding `add` / `remove` / `write`.
It is the single in-memory holder of every key the client knows (per-enrollment
*and* per-APKAM), which providers read keys from and mint/add/write through.
*(NOT a wrapper over `AtChops` — `AtKeys` already produces one via `toAtChops()`
and carries a `metadata` stash.)* `CryptoContext` gains a `WritableAtKeys keys`
field — **additive** (`CryptoContext` is `{atClient}`, with no `atChops` field). Convergence (newest-wins / pull recovery)
stays in the secret-sharing substrate; the stores are **dumb** key-value backends.

**Key taxonomy → store routing** (explicit named stores, no magic router):

| Key class | Store | Persistence |
|---|---|---|
| Enrollment bootstrap (encryption/PKAM/APKAM keypair, selfEnc, apkamSym) | `.atKeys` file **or** keychain | persisted, now **updatable** (today write-once) |
| Distributed / rotating (nskey namespace keypairs, content keys, D2 epoch `__rk`, persistent leaf) | local keystore (Hive) | persisted, per-key |
| Ephemeral per-APKAM leaf (npt/sshnp throwaway keypairs) | in-memory | write-only; regenerated each run |

Store homes: `InMemoryAtKeysIo` + the interfaces in `at_auth` (main barrel);
`FileAtKeysIo` (updatable) in `at_auth_io.dart`; `LocalKeystoreAtKeysIo` in
`at_client` (needs at_persistence, injected down); `KeychainAtKeysIo` in
`at_client_flutter`. `.atKeys` / keychain are made **updatable** (re-wrap the
self-enc key on rewrite; atomic write + backup). `WritableAtKeys` is born at
AtClient construction and immutable after.

### WASM barrel split (`at_auth 4.0.0`)

`at_auth`'s core must compile under `dart2wasm` (the running client, incl. web,
authenticates via at_auth; only onboarding/setup is desktop/CLI). `dart2wasm`
errors on any `dart:io` reachable from the entry point, so:

- **`at_auth.dart`** (main barrel, WASM-safe): `AtKeys` / `WritableAtKeys`, the
  `AtKeysIo` / `WrittenAtKeysIo` interfaces, `InMemoryAtKeysIo`, the auth core,
  and the registrar **on `package:http`** (no `dart:io HttpClient`, so it is WASM-safe).
- **`at_auth_io.dart`** (new non-wasm barrel): `FileAtKeysIo` + the `dart:io`
  socket-probe default. CLI and `at_client_flutter`'s `file_picker` import it —
  so `FileAtKeysIo` never leaves `at_auth` (no relocation, no UI→CLI arrow).
- Two inline-`dart:io` bits in `at_auth_impl.dart` are **extracted**: drop the
  `atKeysIo ??= FileAtKeysIo()` default (require injection); move `_defaultProbeSocket`
  to the io barrel, leaving only the injected `probeSocket` hook in the core.

### File partition

Within `at_client/crypto/`: track-C owns `crypto.dart`, `crypto_runtime.dart`,
`legacy/`; track-A owns `crypto/group/`, `crypto/nskey/` (new), `secret_sharing/`.
The nskey data-path providers are mostly new files — low collision by construction.

---

## 5. Subsystem E — worked design walkthroughs (NoPorts, at_talk)

Two design-level traces of the mechanics in action. These are **not** the
Given/When/Then catalogue — the testable form (including the at_talk e2e scenario)
is in [`acceptance.md`](acceptance.md). The large-group `at/pqmls` walkthrough is a D2 scenario
(see [`roadmap.md`](roadmap.md)).

### Walkthrough A — NoPorts (the nskey data path for self + pair traffic)

Actors: **@client** (sshnp), **@daemon** (sshnpd; a device may run many), **@srvd**
(relay; a third atSign). The recipient unit is the **APKAM keypair** (one per
keyfile/install); each has a per-APKAM key package in its enrollment record (never
published). NoPorts' ephemeral one-shot clients use throwaway per-APKAM keypairs.

**Feature discovery is the back-compat lever.** The daemon's ping response carries
`supportedFeatures: {name: bool}` (`sshnpd_impl.dart`), read null-tolerantly (a
missing map = an old daemon) — exactly how `twinKeys` rolled out. Two new
`DaemonFeature`s:

| Feature | Daemon advertises that it… |
|---|---|
| `pqData` | can decrypt notifications written on the D1 nskey data path (`at/nskey` + GCM) |
| `pqSessionKeys` | supports deriving session keys via the D2 `at/pqmls` group `export()` (none in flight) |

The crucial subtlety: a client must **NOT** flip its default provider for traffic
to a daemon that can't decrypt it. `PutRequestOptions.cryptoProviderId` (the
per-operation override from the M0 seam, [§4](#4-subsystem-d--structural-design-cryptoprovider-seam-writableatkeys--key-stores-wasm-barrel)) is the per-destination gate.

**One session, step by step:**

1. **Discovery.** sshnp pings @daemon; the ping response carries `supportedFeatures`.
   The client learns `pqData` / `pqSessionKeys`.
2. **Session request (the nskey data path).** With `pqData`, the request
   notification is written on the D1 nskey data path: the client cuts (or reuses) a
   CK, conveys it once via `at/nskey` **sealed to @daemon's published nskey** (its
   `public:` half) for the session namespace, and seals the request body with `at/symmetric/AES/GCM`
   under that CK (citing `ckKid`). With `legacy`, it is byte-identical to today.
   Because the (still RSA-wrapped) session key rides *inside* this PQ-safe payload,
   a recorded exchange can no longer be peeled open later — the harvest-now hole is
   closed.
3. **Session keys (convey as a CK, don't transmit raw).** The session material
   rides inside the AES-GCM body, so no key travels in the clear and the per-session
   RSA-2048 keypair generation can be deleted. If both sides advertise
   `pqSessionKeys`, they may *optionally* derive the session keys from a D2
   `at/pqmls` pair-group `export()` instead of conveying them — a D2 optimisation,
   not a D1 step.
4. **srvd relay.** The relay-auth key involves a third atSign; rather than seal a
   CK to a third party's nskey per session, it stays transmitted, protected
   by the nskey data path of the request that carries it.
5. **Delivery.** Self data within one atSign and the @client↔@daemon pair are both
   the nskey data path — **there is no group and no DS host**. The CK conveyance and
   the data ride ordinary pairwise notify + sync; the recipient atServer syncs to
   that atSign's authorised APKAM keypairs. (The Delivery Service is only for large
   D2 groups — [`roadmap.md`](roadmap.md).)
6. **Fleet management (self data on the nskey data path).** Many sshnpd on one
   device atSign plus a policy/management client share a config secret as **self
   data**, encrypted under a CK conveyed via `at/nskey` to the device atSign's own
   **nskey**. Management writes once; every authorised daemon reads it after
   one sync (it already holds the nskey private, delivered per-APKAM by the
   substrate at enrollment). A **stolen device** → `enroll:revoke` the offending
   enrollment, then **rotate the nskey keypair excluding the revoked APKAM keypair**
   (and rotate the CK): the successor conveyance is never sealed to the revoked
   keypair, so everything shared after that instant is unreadable by it ([§1.7](#17-forward-secrecy--rotation-levers-ck-rotation-vs-nskey-keypair-rotation)).
7. **Rollout.** (1) ship dual-stack daemons that advertise the features (safe —
   nothing changes on the wire); (2) ship clients that prefer the nskey data path
   when `pqData` is advertised; (3) once the deployed-daemon floor includes
   `pqData`, flip the client default; (4) `pqSessionKeys` (the optional D2 `export()`)
   retires `genBundle`/ephemeral-keypair code when the floor allows. Consolidation
   bonus: NoPorts can replace `validation_utils` signing with the SDK's
   `EnvelopeSigning` (its descendant), moving verification onto the per-enrollment
   `_apsk` trust chain.

Net: every request/response/heartbeat becomes PQ-safe on the nskey data path; the
session key stops travelling raw; fleet secrets distribute per-APKAM via the
substrate, with **coarse FS** by CK rotation + conveyance deletion and **per-APKAM
future-data revocation** by rotating the nskey keypair to exclude a revoked keypair
— old peers always negotiating cleanly via feature discovery.

### Walkthrough B — a two-atSign chat with APKAM-keypair churn (`at_talk`)

The **cross-atSign nskey data path** (D1): two atSigns, multiple APKAM keypairs
each, bidirectional messaging, late-joining APKAM keypairs.

**Setup.** Four APKAM keypairs — `Ka1`, `Ka2` (`@alice`) and `Kb1`, `Kb2` (`@bob`)
— each `rw` on `at_talk`, each with a per-APKAM key package in its enrollment record
(an X-Wing encapsulation key + an APKAM-certified signing key; **not** published).
The relevant keys are each atSign's `at_talk` **nskey**: `@alice`'s one nskey
(public half published as `public:nskey.at_talk@alice` on the first cross-atSign
share), and `@bob`'s likewise. **There is no group
and no epoch key.** Alice→Bob data is encrypted under a CK, conveyed once via
`at/nskey` sealed to **Bob's published nskey** (its `public:` half); Bob→Alice
symmetrically. Alice's own clients read her sent CKs via the same `@alice` nskey.
CKs are minted lazily.

**Whose nskey the CK is sealed to** is per recipient, not a group:

- Alice writing data **Bob should read** → seal the CK to `public:nskey.at_talk@bob`.
- Alice writing **self data** → seal the CK to Alice's own `at_talk` nskey; never
  shared cross-atSign by construction, so Bob never sees Alice's self data.

There is no "(pair, namespace) group" to scope: the atServer's namespace gate
decides who may *fetch*; the nskey the CK is sealed to decides who can *decapsulate*.
Both are keyed to `at_talk`, so the set is exactly "both sides' `at_talk`-authorised
APKAM keypairs."

**How a late-joining APKAM keypair (e.g. `Kb3`) reads** — two independent steps:

1. **Layer 1 — the nskey private, per-APKAM (substrate).** `Kb3` generates its key
   package locally and registers the *public* half in its enrollment record (gated,
   never published). A holder (`Kb1`) `pqSeal`s the `at_talk` nskey **private** to
   `Kb3`'s key package and writes `<msgId>.<kp(Kb3)>.__ssenv.at_talk@bob` —
   addressed by `kpid`, per-APKAM, once per APKAM keypair (approval-time push /
   `enroll:listns` / `requestSecret` pull backstop). Both gates of
   [§2.1](#21-kpid-addressing-__ssenv-envelope-signverify) protect the copy: the transport gate (Kb3 is `at_talk`-authorised) and the
   crypto gate (sealed to Kb3's key package).
2. **Layer 2 — the CK, on ordinary sync.** Once `Kb3` holds the nskey private, it
   syncs the current `<ckKid>.__ck.at_talk@<owner>` conveyances; `at/nskey`
   decapsulates the live CK with the nskey private and caches it by `ckKid`;
   `at/symmetric/AES/GCM` then resolves data values and decrypts. **No epoch
   rotation on join, no per-message key push, no Add+Commit.** For `Ka3` (`@alice`),
   the same nskey private also lets it decapsulate Alice's own self CKs — no
   self group to join.

**New vs. past data:**

| APKAM keypair | New data | Past data |
|---|---|---|
| **Kb3** (@bob) | Receives the `at_talk` nskey private per-APKAM (push, or `requestSecret` pull), syncs the current `__ck` conveyances, decapsulates the live CK → reads all new data. No epoch rotation / `__ck` re-mint on join. | Reads whatever `__ck` conveyances are still **retained**. **Retain** → opens past messages. **Delete-for-FS** → CKs whose conveyance was deleted on rotation stay opaque. |
| **Ka3** (@alice) | Symmetric: receives @alice's `at_talk` nskey private; reads current `__ck` conveyances → reads all new data. The same nskey private also decapsulates @alice's own self CKs. | Reads retained `__ck` conveyances; same retain-vs-delete fork. |

**Caveats this example surfaces:**

- **History is a policy fork, not a mechanism gap.** The D1 artefact is the
  `at/nskey` CK-conveyance record, not a per-group epoch key. Retain → any
  `at_talk`-authorised keypair reads history; delete on CK rotation (+ evict the
  cached CK) → that era's data is undecryptable — D1's coarse FS ([§1.7](#17-forward-secrecy--rotation-levers-ck-rotation-vs-nskey-keypair-rotation)). D1 **does**
  have FS: coarse FS by CK rotation + conveyance deletion, plus PCS via the
  expensive nskey-keypair rotation lever.
- **A new APKAM keypair does NOT force a rotation.** Joining `at_talk` just conveys
  the nskey private to the new keypair and lets it read existing CKs (mandatory
  rotation on join is a D2 / MLS property, not D1).
- **Cross-atSign FS is bilateral** ([§1.7](#17-forward-secrecy--rotation-levers-ck-rotation-vs-nskey-keypair-rotation)).

Cross-ref [`acceptance.md`](acceptance.md) for the testable Given/When/Then versions of this
scenario (it drives a cross-atSign e2e test).

---

## 6. Implementation notes & file-level pointers (consolidated)

Build-level pointers gathered for implementers — the "how" detail this doc owns.
Project sequencing / waves / effort live in [`implementation-plan.md`](implementation-plan.md);
Given/When/Then acceptance in [`acceptance.md`](acceptance.md); decisions/timeline in
[`decisions.md`](decisions.md).

**Baseline (terse — full status is [`implementation-plan.md`](implementation-plan.md)'s lane).**
`#1930` (M0 crypto seam) **merged**; `at_chops 3.3.0` (`pqSeal`/`pqOpen` + stateless
core) **on trunk**; PR `#2035` (design fixes) **merged**. `at_commons 5.11.0`
(`appMetadata` wire), `at_chops 3.3.0` (X-Wing, AES-256-GCM, HKDF, HMAC; published 2026-06-23), and the
commit-log-free 5.x keystore are on trunk.

### Client substrate — built, unit-green (`gkc-jt-secret-sharing-substrate`)

| Capability | Evidence (`file:line`) |
|---|---|
| X-Wing `pqSeal`/`pqOpen` of `__ssenv` (HPKE + AES-256-GCM, HKDF info `'at_client/secret_sharing/v1'`) | `pairwise_secret_sharing.dart:191,398,99`; `pq_hpke.dart:80` |
| Per-envelope APKAM sign + verify-before-decrypt; per-enrollment `_apsk` resolution | `mixins/envelope_signing.dart:74,152`; verify precedes open `pairwise_secret_sharing.dart:366` |
| `kpid` addressing throughout (envelopes and fan-out keyed by the key-package kid) | `secret_envelope.dart` `toKpid`/`fromKpid`; `key_package.dart:29` |
| Per-APKAM `KeyPackage` keyed by `(enrollmentId, apkamId)`; crypto-agile parse + `bestKeyFor` | `key_package.dart:76,108,156`; `algo_ids.dart:34,46` |
| `requestSecret(name)` / `waitForSecret`; request/serve (kpid fan-out, reply to carried kpid) | `pairwise_secret_sharing.dart:479,454,497` |
| `pushSecretToNamespaceMembers(Secret,{exclude})` | `pairwise_secret_sharing.dart:662` |
| `shareAllSecretsWithEnrollment` (approval path, no poll, dedup byKpid) | `pairwise_secret_sharing.dart:689` |
| `excludeEnrollmentIds` guard threaded request/serve/approve | `:458,641,694`; `enrollment_directory.dart:97` |
| `SecretStore.putIfNewer` monotonic-version ordering; reserved `__` guard | `secret_store.dart:117,126,98` |
| `namespaceAuthorizes` (suffix/`*` match) | `secret_store.dart:169` |
| Transport: put + sync listener + optional wake-up notify; `receivedSecrets` + `_consume` | `:220,724,239,360,601` |

**Known client gaps** (within the substrate): **advertised-key signing + verify is not
yet implemented** — the substrate signs `__ssenv` envelopes but advertises the key
package (and, later, the `nskey` / `pqpublickey` public halves) **unsigned**, so the
authenticity decision of [§2.1](#21-kpid-addressing-__ssenv-envelope-signverify) is
target-not-built (sign in the mint paths SS-2 / SS-4, verify on read SS-1c); the
public/private correspondence check is likewise missing
(`pairwise_secret_sharing.dart:360-407`); the root `pqpublickey`
no-namespace serve exception is missing (`grep pqpublickey` = 0); durable storage
is deferred (in-memory `SecretStore` + a pluggable persistence hook,
`secret_store.dart:62`; `WritableAtKeys` not wired); anti-storm is a plain rate cap
without jitter (`:539`). `pushSecretToNamespaceMembers` is untested. Finally, the
built `VerbEnrollmentDirectory` still speaks the **retired** wire shape — it parses
a nested `apkam[]` response and performs an `enroll:metadata` registration write —
contrary to decision #F (1:1:1) / OQ9; the WP-SS rework (PR #2037 / SS-1c) rewrites
it to the flat, single-key, `enroll:listns`, no-write-path model (singular signed
`metadata.keyPackage`, no format-keyed map).

### atServer change lists (DEP1–DEP4)

`at_server` is a sibling repo present locally; these are "in-repo (sibling) but
unimplemented."

- **DEP1 — `enroll:listns:<ns>` gated discovery verb** (effort **L**).
  Enum + regex + handler + gate per [§2.3](#23-the-enrolllistns-verb--enrollparamsmetadata). Returns the **flattened**
  `[{enrollmentId, access, apkamPubKey, metadata}]`. Purely additive; old clients
  never send it; old servers reject as `InvalidSyntaxException` (client treats
  non-`data:` as `[]`).
- **The `EnrollParams.metadata`-on-`enroll:request` store** (effort **M**). The key package rides an
  opaque `Map<String,dynamic>` on the existing `enroll:request` JSON tail; the
  server stores it verbatim on `EnrollDataStoreValue.metadata` (nullable additive
  field; regenerate `.g.dart` via `build_runner`; legacy records read back
  `metadata: null`) and returns it from DEP1. **No `enroll:metadata` verb, no
  post-enrollment metadata write.**
- **DEP3 — single `apkamPublicKey` + `signingAlgo` + ML-DSA verify** (effort **XL**),
  **record-authoritative**. Per [§2.4](#24-the-atserver-enrollment-record--ml-dsa-apkam-auth): one APKAM key per enrollment (1:1:1),
  `signingAlgo ∈ {rsa2048, mldsa65}`; `_getSigningAlgoType`
  (`pkam_verb_handler.dart:199-210`) reads the **record's** algo, not the wire
  value (`:164`); at_chops wires the existing `MlDsa65*Algo`
  (the `mldsa65` member already ships at `algo_type.dart:10`; add the branch at
  `at_chops_impl.dart:284`); at_commons widens the pkam
  `signingAlgo` literal (`syntax.dart:10`). Legacy single-string record → `rsa2048`
  on `fromJson`; legacy `atPkamPublicKey` mirror preserved.
- **DEP4 — atServer auto-notify on `__ssenv` puts** (effort **M**; delivered inside
  SS-2 per [`implementation-plan.md`](implementation-plan.md) — the auto-notify itself
  is additive and could ship independently, but the client
  `sendWakeUpNotification=false` default-flip is sequenced in SS-2). On an `update`
  put to a key whose name contains the full
  `.__ssenv.` segment, enqueue a value-less self-notification (`NotificationType.self`,
  `opType=update`), model on `_storeNotification` (`enroll_verb_handler.dart:529-560`)
  but **drop the `rethrow` (`:558`)** so a failed enqueue can't fail the put; gate
  strictly to `opType=update` (a recipient's *delete* of a consumed envelope must
  not fire a spurious wake-up). Later, default the client `sendWakeUpNotification=false`.
- **`_apsk` presence + write-restriction ACL** — the atServer MUST (1) **keep `_apsk`
  present**, populating `public:_apsk.<enrollmentId>.<perEnrollmentApproved>@<atSign>`
  from the enrollment record's `apkamPublicKey` rather than relying on the client-side
  `publishPublicSigningKey` (removes a race + a missing-key failure mode), and (2)
  **restrict writes** to that key to the owning enrollment's own authenticated
  connection (verified empirically June 2026). Needs e2e tests for both (an approved
  enrollment's `_apsk` is fetchable without a client publish; a second enrollment cannot
  overwrite another's `_apsk`). Both envelope sender-authentication and advertised-key
  authenticity ([§2.1](#21-kpid-addressing-__ssenv-envelope-signverify),
  [§2.4](#24-the-atserver-enrollment-record--ml-dsa-apkam-auth)) collapse if these
  regress.

### Verification recipe

`dart analyze --fatal-warnings`, `dart format`, `dart test --concurrency=1` on
every touched package. Crypto correctness: X-Wing draft vectors + GCM NIST vectors
byte-exact. Functional: recycle the virtualenv (`docker compose down` first —
one-shot CRAM secrets), then `tests/at_functional_test` via `runLocal.sh`. e2e:
`tests/at_end2end_test` via the base-port `runLocal.sh` rigs. The full
Given/When/Then test plan + harness mapping is in [`acceptance.md`](acceptance.md).

---

## 7. Trust boundary & residual threats

This section records the confidentiality trust boundary honestly, so nothing elsewhere
in the doc set overclaims what the advertised-key signing ([§2.1](#21-kpid-addressing-__ssenv-envelope-signverify),
[decisions.md §12](decisions.md)) achieves. The headline: **the operator of an atSign's
atServer is in the confidentiality TCB for all data destined to that atSign**, and the
signing does not, by itself, change that. The last subsection sketches the key-transparency
direction that would.

### 7.1 The anchor problem: an atServer is the de-facto CA for its own atSign

D1 encryption is only as trustworthy as the binding *atSign → recipient public key*. A
sender obtains that binding from the recipient's atServer (directly, or proxied through
its own). Advertised-key signing chains the recipient key to the enrollment's `_apsk`,
but **`_apsk` is itself served by the same atServer** — so the anchor of the whole chain
is a key the atServer supplies. In effect, an atServer is the certificate authority for
its own atSign's keys. This is a property of the Atsign Protocol, not of the substrate:
classical Atsign has it too (a sender fetches `public:publickey@alice` from @alice's
atServer and encrypts to whatever it returns).

### 7.2 The malicious-operator attack (transparent, split-view MITM)

A maliciously-operated @alice-atServer can read data sent *to* @alice:

1. It generates its own keypair `EVIL`.
2. It serves `EVIL_pub` as an @alice enrollment's `_apsk`.
3. It serves an advertised recipient key (a `nskey` public / `pqpublickey` / key package)
   that it generated, **signed with `EVIL_priv`**.
4. A sender (a peer `@bob`, or one of @alice's own clients) fetches the advertised key,
   verifies its signature against the `_apsk` — which is `EVIL_pub` — and it **passes**,
   because the server controls both halves of the chain.
5. The sender seals the content key to the server's key; the server decapsulates and reads.

It is **transparent to both ends**: after reading, the server re-seals the plaintext to
@alice's *real* recipient key (which it holds — @alice's own client published it) and
stores that, so @alice's client decrypts normally. The sender saw a signature that
"verified"; @alice received a message that decrypts. Neither observes an anomaly.

The signing gives the sender **zero** protection here, because the sender's only source
for the `_apsk` it verifies against is the same server that forged the signature — the
trust is circular for any party whose sole path to @alice's keys is @alice's atServer.

### 7.3 Impact scope — precisely what an operator can and cannot do

- **Can — read:** transparently MITM (read) all data **destined to** the atSigns it hosts
  — inbound cross-atSign shares, and self-data where the client relies on server-served
  keys rather than locally-held ones — by substituting the *recipient* key. The power is
  **per-inbound and symmetric**: @alice's operator owns inbound-to-@alice; @bob's operator
  owns inbound-to-@bob. @alice's operator cannot read what @alice sends *out* to @bob (that
  is sealed to @bob's key, from @bob's atServer).
- **Can — modify (a strictly harder bar):** read and integrity are **asymmetric**. Pure
  read is a pass-through re-seal, so any *sender* signature inside the payload survives
  unchanged and still verifies. To silently **modify**, the operator must also defeat that
  sender signature — which for a §2.1-signed payload means substituting the *sender's*
  signing key **as the recipient's client sees it**. It can (it mediates that client's
  lookups too), so modify is achievable — but it needs a **second** substitution and is
  defeated the moment the recipient anchors the sender's key independently (out-of-band
  pin / KT). An unsigned or self-data payload is silently modifiable with the single
  recipient-key substitution. So: read depends on one substitution; silent modify depends
  on two (and both collapse under an independent anchor).
- **Cannot:** decrypt data sealed to the atSign's *real* keys that never passed through a
  substituted exchange (e.g. a key a peer pinned out-of-band); break the primitives
  (X-Wing / AES-GCM are sound — this is key substitution at the anchor, not a crypto
  break); or MITM traffic to atSigns it does not host.
- **Self-data caveat:** a client that mints or holds its own `nskey` private also holds
  the matching public and should seal self-data to the **locally-held** key, never a
  server-fetched one — which takes self-data out of the operator's reach. Clients SHOULD
  prefer locally-held keys over server-served keys wherever they hold the private.

### 7.4 Detectability — undetectable to a *targeted* victim today

- **Untargeted** substitution (the server shows `EVIL` to everyone, including @alice's own
  clients) is **detectable**: an @alice client knows its own real public key (it holds the
  private), so a **self-audit** — fetch my own `_apsk` / `public:nskey@alice` as served and
  compare to what I published — catches it. Cheap; catches the lazy attacker immediately.
- **Targeted** substitution (the server shows the *real* keys to @alice's authenticated
  clients and `EVIL` only to remote lookups) is **effectively undetectable by @alice's
  clients**, because they never observe the response the server gives a peer. The server
  discriminates trivially — it knows whether a lookup arrives on @alice's authenticated
  APKAM connection or as a remote/proxied request. This is a classic **split-view** attack;
  it is caught only by a mechanism that cross-checks the two sides' views (an out-of-band
  fingerprint, or a gossiped transparency log — [§7.6](#76-key-transparency-on-the-atdirectory)).

### 7.5 Mitigation ladder

Ordered roughly cheapest/soonest → strongest/longest. These compose; they are not
exclusive.

1. **Self-hosting (Atsign-native, strongest for a privacy-critical atSign).** If @alice
   runs her own atServer, the operator *is* @alice — no third party in her inbound TCB.
   First-class in the platform; residual risk moves to the resolution path (a malicious
   atDirectory, or the peer's own atServer), addressed by 3–4 below.
2. **Client self-audit of own advertised keys.** Each client periodically fetches its own
   `_apsk` / `nskey` public / `pqpublickey` as a remote party would and compares to the
   locally-held truth. Cheap; defeats *untargeted* substitution and forces an attacker to
   target, which raises cost and risk.
3. **Out-of-band fingerprint / safety number (TOFU-then-verify, the Signal model).** Peers
   compare a fingerprint of the atSign's identity key over an independent channel (QR,
   voice, printed code) and pin it. Catches *targeted* split views; needs **no** trust in
   the server implementation. Natural fit for pairwise relationships (NoPorts device pairs,
   at_talk contacts). Weakness: first-contact and user friction.
4. **atDirectory Key Transparency + root-anchored signatures ([§7.6](#76-key-transparency-on-the-atdirectory)).**
   The structural answer for *hosted* atSigns: publish atSign→identity-key bindings to an
   append-only, gossiped, auditable log; sign advertised keys with the atSign's long-term
   **root** identity key (not just the per-enrollment `_apsk`); serve an inclusion proof
   alongside each key. Makes operator substitution *detectable and attributable* without
   trusting any binary.
5. **Attestation / audit of the atServer implementation.** Remote attestation (TEE) or
   reproducible-build + independent audit proves the deployed instance runs honest,
   unmodified code. The only family that gives *prevention with full user-transparency
   while still trusting a third-party host* — but the heaviest: TEEs move trust to the
   silicon vendor and carry side-channel/rollback risk; audit proves the *source* honest,
   not that the *running instance* is that source (needs attestation to bridge the gap).

**Note on `disallowLegacyEncryption` / PQ scope:** none of the above is a PQ-specific
problem — it is the standard end-to-end trust-root problem, present classically. PQ makes
the *bytes* harvest-resistant; the anchor problem is orthogonal and is not solved (or
worsened) by the D1 work. It is called out here so the doc set does not imply otherwise.

### 7.6 Key transparency on the atDirectory

> **Status: forward-looking design sketch, not a D1 decision.** Recorded so the
> operator-in-TCB gap has a credible answer on file. Belongs to a separate effort
> (identity / transparency), not the D1 substrate.

The atDirectory already maps *atSign → atServer address*. Key Transparency (KT) adds a
second job: **atSign → identity-key binding**, published so that misbehaviour is
*detectable* rather than *preventable-only-by-trust*. The security comes from
verifiability, witnessing, and monitoring — **not** from trusting the log operator — so it
holds **even if Atsign hosts the atDirectory**.

**What is logged.** The atSign's long-term **root identity public key** (the onboarding
PKAM key in the `.atKeys`) — the stable anchor; the volatile `nskey` / `pqpublickey`
publics then chain to it via signatures ([§2.1](#21-kpid-addressing-__ssenv-envelope-signverify))
and need not be logged individually. Logging the stable root minimises churn.

**Structure (CONIKS / Key-Transparency lineage).** A **verifiable key directory**: a
Merkle prefix tree keyed by atSign, giving each atSign an efficient proof of *its current
binding* and of *absence of any other binding*. Each **epoch** the directory publishes a
**signed tree head (STH)** committing to the whole tree; STHs form a hash chain (each
commits to the previous) so the operator cannot silently rewrite history — the log is
append-only and that is *provable*. A **VRF over the atSign** gives the tree a private
index, so the log does not enumerate atSigns (their names stay confidential — important
given atSigns are identifiers); only a party who already knows `@alice` can request and
verify her proof.

**Why it holds even when Atsign runs the atDirectory — three interdependent checks.**
No single check prevents substitution; together they force any substitution to go
*through the witnessed, append-only log*, where it is *caught*. (KT is **detection**, not
prevention — see the Net effect below.)

1. **Inclusion proof on every key fetch** forces substitution on-log. When a sender
   fetches @alice's advertised key (from her atServer), it also obtains a KT **inclusion
   proof** binding @alice → root in a recent STH, plus the signature chain root → advertised
   key, and accepts the key only if all verify. A malicious atServer therefore cannot serve
   a rogue key that is *not* backed by a rogue root **in the log** — it can no longer
   substitute *undetectably* off-log; it must get a rogue root inserted (checks 2–3).
2. **Witness co-signing defeats split views.** A set of **independent witnesses**
   (community members, self-hosters, an org's own nodes — *not* only Atsign) co-sign each
   STH; clients accept an STH only with a quorum of witness signatures. Atsign alone then
   cannot produce a valid STH, so it cannot show a *different* tree to a targeted victim
   than to everyone else without colluding with the witnesses. Gossip of STHs (piggybacked
   on ordinary atServer-to-atServer traffic) reinforces this — a split view surfaces the
   moment two parties compare roots.
3. **Per-atSign monitoring makes insertion loud.** A malicious atDirectory *can* insert a
   rogue @alice root and produce a valid inclusion proof for it — checks 1–2 do not prevent
   that. What stops it being *silent* is monitoring: @alice (or monitors she delegates to)
   watches the log for any binding under @alice she did not create, and the append-only log
   guarantees she detects a rogue insertion by the next epoch. Security reduces from "trust
   Atsign" to "Atsign cannot cheat @alice without @alice (or her monitor) noticing."

**Net effect — detection, not TCB removal.** With KT anchoring the root and
[§2.1](#21-kpid-addressing-__ssenv-envelope-signverify) signatures chaining advertised keys
to it, a cheating operator is made **detectable and attributable** rather than removed from
the TCB: it converts an *undetectable* confidentiality adversary into one that is *caught*,
which deters sustained abuse — but a one-shot attacker can still read a single epoch's
traffic before the rogue binding is exposed, so the operator is **not** removed from the
confidentiality TCB (do not claim otherwise — that is the same detection-as-prevention
overclaim §7 exists to avoid). The residual is "Atsign *and* a witness quorum collude, *or*
@alice is not (or does not delegate) monitoring, for one epoch." Self-hosting the atDirectory
+ witnesses (split-horizon, already supported) removes Atsign entirely for a closed
ecosystem; pairing KT with out-of-band fingerprints ([§7.5](#75-mitigation-ladder) item 3)
closes the one-epoch window for the highest-assurance pairs.

**Honest limits (this is a sketch — these are the open problems a real design must close).**

- **First contact is TOFU.** KT protects the *continuity* of a binding, not the initial
  root publication (trust-on-first-use unless verified out-of-band, [§7.5](#75-mitigation-ladder)
  item 3).
- **Assurance = witness independence.** A handful of genuinely independent witnesses makes
  targeted equivocation hard; Atsign-only witnesses make it weak.
- **Detection, not prevention** (restated because it is the crux): a cheating operator is
  *caught*, which deters, but a one-shot attacker may still read one epoch before exposure.
  Out-of-band fingerprints close that last window for the highest-assurance pairs.
- **Root rotation / revocation is unspecified here.** Logging only the stable root means a
  compromised or rotated root needs a *monitored key-change entry* and defined
  revocation/rotation semantics; without them a stolen root stays a valid chain anchor.
- **STH freshness / liveness is unspecified here.** Clients must reject stale STHs (bound
  the max STH age), or a freeze/rollback that pins a victim to an old epoch hides a
  legitimate rotation and delays exposure of a rogue insertion.
- **Monitoring is the element most users won't run themselves.** For a typical end user the
  *delegated-monitor* path is the one that actually carries the guarantee — an atSign with
  no monitor (self- or delegated) gets **zero** KT protection. A real design must make
  independent delegated monitoring the default, not an opt-in.
