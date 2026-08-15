# design.md — Detailed designs & implementation steps (by subsystem)

> ⛔ **PARTLY SUPERSEDED, 2026-08-14. Read this before building from any
> section that names a rollout stage or the `.atKeys` shape.**
>
> [`decisions.md` 98](decisions.md#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14)
> redefined the rollout stages and
> [99](decisions.md#99-the-keyfile-groups-by-enrollment-and-the-atsigns-own-keys-move-out-2026-08-14)
> reshaped the at-rest keyfile. **Neither is built**, so this document still
> describes what the *code* does — and that is exactly the trap: it reads as
> current because it matches the tree.
>
> Two statements in [section 9](#9-subsystem-g--signature-agility-the-authsigning-key-split)
> are now false, and both are called out in place below: **`rollout1` writes
> exactly what `now` writes**, and the **file-wide single-active-authentication
> rule** as the thing that makes the enrollment id derivable.
>
> The order to build the replacements in is
> [`implementation-plan.md` 14.20](implementation-plan.md#1420-building-rulings-98-and-99--the-sequence).

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
  - [3.1 What the standards check established](#31-what-the-standards-check-established)
- [4. Subsystem D — structural design (CryptoProvider seam, AtKeys/AtKeysIo & key stores, WASM barrel)](#4-subsystem-d--structural-design-cryptoprovider-seam-atkeysatkeysio--key-stores-wasm-barrel)
- [5. Subsystem E — worked design walkthroughs (NoPorts, at_talk)](#5-subsystem-e--worked-design-walkthroughs-noports-at_talk)
- [6. Implementation notes & file-level pointers (consolidated)](#6-implementation-notes--file-level-pointers-consolidated)
- [7. Trust boundary & residual threats](#7-trust-boundary--residual-threats)
- [8. Subsystem F — inter-server PQ authentication (IS-1)](#8-subsystem-f--inter-server-pq-authentication-is-1)
- [9. Subsystem G — signature agility (the auth/signing key split)](#9-subsystem-g--signature-agility-the-authsigning-key-split)

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
  (`public:__nskey.app_1.my_apps@alice`, not a bare `nskey`).
- **"Working name"** marks an at-key, provider, or verb name not yet finalised.
- Notation (namespace key-shape legend, `(owner, namespace)` identity discipline)
  follows the use-case catalogue in [`acceptance.md`](acceptance.md).
- Worked examples here are **mechanics traces**, not Given/When/Then — the
  testable form of each is in [`acceptance.md`](acceptance.md).

### Subsystem map

- **[Subsystem A — D1 nskey data path](#1-subsystem-a--d1-nskey-data-path)** (§1) — the three layers, three providers, key shapes, CK model, cold-start, FS/rotation levers, and migration/rollout + the `disallowLegacyEncryption` flag ([section 1.8](#18-migration-rollout--the-disallowlegacyencryption-flag-d1-c--d1-d)).
- **[Subsystem B — the secret-sharing substrate (WP-SS)](#2-subsystem-b--the-secret-sharing-substrate-wp-ss)** (§2) — kpid addressing, `__ssenv`, push/pull, the discovery verb, the enrollment record, the self-retrofit flow.
- **[Subsystem C — at_chops PQ primitives](#3-subsystem-c--at_chops-pq-primitives)** (§3) — X-Wing, `pqSeal`/`pqOpen`, ML-DSA verify.
- **[Subsystem D — structural design](#4-subsystem-d--structural-design-cryptoprovider-seam-atkeysatkeysio--key-stores-wasm-barrel)** (§4) — the CryptoProvider seam, `AtKeys`/`AtKeysIo` & key stores, the WASM barrel split.
- **[Subsystem E — worked design walkthroughs](#5-subsystem-e--worked-design-walkthroughs-noports-at_talk)** (§5) — NoPorts, at_talk.
- **[Implementation notes & file-level pointers](#6-implementation-notes--file-level-pointers-consolidated)** (§6) — the consolidated `file:line` build map.

Within this doc: [section 1](#1-subsystem-a--d1-nskey-data-path) (nskey data path) forward-refs [section 2](#2-subsystem-b--the-secret-sharing-substrate-wp-ss) for its Layer-1 plumbing;
[section 2](#2-subsystem-b--the-secret-sharing-substrate-wp-ss) references [section 3](#3-subsystem-c--at_chops-pq-primitives) for the seal/sign primitives; [section 4](#4-subsystem-d--structural-design-cryptoprovider-seam-atkeysatkeysio--key-stores-wasm-barrel) (the structural seam) underpins
both [section 1](#1-subsystem-a--d1-nskey-data-path) providers and [section 2](#2-subsystem-b--the-secret-sharing-substrate-wp-ss) substrate; [section 5](#5-subsystem-e--worked-design-walkthroughs-noports-at_talk) walkthroughs reference [section 1](#1-subsystem-a--d1-nskey-data-path)/[section 2](#2-subsystem-b--the-secret-sharing-substrate-wp-ss) for mechanics.

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
| `at/nskey/XWING/AES/GCM` | a **CK-conveyance record** (a sealed content key, cited by `ckKid`) | `X-Wing-seal` (the CK encapsulated to an nskey public half) — via `pqSeal`/`pqOpen` ([§3](#3-subsystem-c--at_chops-pq-primitives)) | the recipient's **nskey** — the owner's own nskey (self data) or another atSign's nskey (shared) |
| `at/symmetric/AES/GCM` | **application data** | AES-256-GCM under a CK | n/a (symmetric); the CK is cited by `ckKid` and resolved from cache (populated by `at/nskey` when its conveyance record synced) |

Notes:

- **A provider id names the role, then every algorithm a reader needs code for**
  ([`decisions.md`](decisions.md) section 16): `at/<role>/<algorithms…>`. Anything a
  reader can discover from the value — the envelope version, `iv`, `ckKid`,
  `nskeyKid` — stays out. So the conveyance provider is
  `at/nskey/XWING/AES/GCM` (KEM + envelope AEAD) and the data provider is
  `at/symmetric/AES/GCM`. `at/nskey` remains the **family prefix**: prose about "an
  `at/nskey` record" means `at/nskey/*`.
- **This is what makes an algorithm change rollable.** Reads stay universal — a
  reader registers every scheme it supports and values route by their own id, so
  retired schemes keep opening forever, and coexisting schemes need no flag day.
  (*Which* scheme is written is the app's release decision — the SDK never
  chooses one per destination,
  [`decisions.md` 36](decisions.md#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05).)
  `at/nskey/MLKEM1024/AES/GCM` and
  `at/symmetric/AES/SIV` each coexist with today's; old values keep their tag.
- The same X-Wing sealing also conveys nskey *privates* in Layer 1, but those ride
  the substrate as transport and are **not** value-level `at/nskey/*` records
  (decision (ii)).
- **Legacy interop.** A value with **no** `appMetadata.providerId` defaults to
  `legacy`. `legacy`, `at/nskey`, and `at/symmetric/AES/GCM` values coexist within
  a namespace and the seam routes per value. A writer emits the nskey data path's
  providers once the namespace has an nskey (else cold-start, [§1.4](#14-the-nskey-and-the-signing-root)); legacy data is read in place and re-encrypted only if rewritten.
- **Cold-start has no providerId at all**, because it has no target: the only
  atSign-level key is a signing root, which cannot receive an encapsulation. A
  namespace with no nskey fails the write ([§1.4](#14-the-nskey-and-the-signing-root)).

(The seam itself — `CryptoRuntime`, `CryptoConfig`, `appMetadata.providerId`
routing — is the structural subsystem [§4](#4-subsystem-d--structural-design-cryptoprovider-seam-atkeysatkeysio--key-stores-wasm-barrel).)

### 1.3 Keys & key shapes

Concrete, `@alice` owner, namespace `app_1.my_apps` (reads right-to-left,
DNS-style). `K1…` = APKAM keypairs, `kp1…` their key-package kids, `ck7…`
content-key kids. Working names marked.

| Object | Shape | Published? | Who holds the private | Role |
|---|---|---|---|---|
| **nskey** | `public:__nskey.app_1.my_apps@alice` — written at mint, **mutable**, APKAM-signed `{v, createdAt, keys:[{use, alg, pub, kid, status?}], suites}` | published from mint; **hidden from scan** (double `_` — revealed only by `scan showhidden:true`; a single `_` would never sync) but served on an exact `plookup`, cross-atSign | Alice's authorised clients (private conveyed via substrate) | Alice encapsulates **her own** CKs to it; external senders encapsulate CKs to it |
| **nskey mint/rotate lock** *(working)* | `_nskeylock.app_1.my_apps@alice` (self key, immutable create, short ttl) | no | n/a | serialises create and rotate between the owner's own enrollments |
| **signing-root mint lock** *(working)* | `_rootlock@alice` (self key, immutable create, short ttl — no namespace, matching the record it guards) | no | n/a | serialises minting the signing root between the owner's own privileged enrollments |
| **CK conveyance** *(working)* | `<ckKid>.__ck.app_1.my_apps@alice` (self key) | no | n/a (it *is* a sealed CK) | `at/nskey` value: `pqSeal(ck)` to the nskey named by `nskeyKid`, under the KEM that nskey's `alg` names |
| **data value** | `<key>.app_1.my_apps@alice` | no | n/a | `at/symmetric/AES/GCM`: AES-GCM under a CK, cites `ckKid` |
| **substrate envelope** *(working)* | `<msgId>.<kpid>.__ssenv.app_1.my_apps@alice` (self key) | no | n/a | Layer-1 plumbing: `pqSeal(nskey private)` to key package `kp` |
| **APKAM key package** | per [§2.1](#21-kpid-addressing-__ssenv-envelope-signverify) | (enrollment record) | the APKAM keypair | recipient unit for Layer-1 |

Cross-atSign mirrors this with `@bob` as owner of the values he writes for
Alice — e.g. the data value `@alice:<key>.app_1.my_apps@bob` and the CK conveyance
`@alice:<ckKid>.__ck.app_1.my_apps@bob`, both sealed to Alice's **nskey** (fetched
from `public:__nskey.app_1.my_apps@alice`, which exists from the moment she minted
it) and synced to Alice as cached replicas. (This ownership is why cross-atSign
FS is bilateral — [§1.7](#17-forward-secrecy--rotation-levers-ck-rotation-vs-nskey-keypair-rotation).)

**Two atSigns, never one.** Every operation resolves both the **record owner**
(`sharedBy` — what the HPKE `info` binds, so self and inbound stay domain-separated
under one key) and the **nskey owner** (`sharedWith ?? sharedBy` — whose nskey seals
or opens it, and the CK cache's scope). On an inbound record these differ: the record
is the sender's, the nskey is the recipient's. Conflating them is why a reader must
never look the key ring up by `sharedBy`
([`decisions.md`](decisions.md) [section 15](decisions.md#15-the-record-owner-and-the-nskey-owner-are-different-atsigns-2026-08-02)).

**The nskey private** for a namespace lives in an authorised client's keystore. It
is one KEM private that decapsulates both the owner's own CKs and the CKs external
senders sealed to her — it **decapsulates CKs**, it never decrypts application data.

**Multi-namespace keying.** The nskey private is keyed by
`(owner atSign, namespace, nskeyKid)` — the kid because rotation leaves earlier
generations in play for retained history ([§1.7](#17-forward-secrecy--rotation-levers-ck-rotation-vs-nskey-keypair-rotation)) — with a *current* pointer per
`(owner, namespace)` for sealing. The CK cache is keyed
`(owner, namespace, ckKid)` — **never `ckKid` alone**, since kids are not unique
across namespaces. In both, `owner` is the **nskey owner** (`sharedWith ?? sharedBy`),
not the record owner. A value in a namespace for which the client holds no nskey
private is left **undecryptable** (yielded as an error), not silently skipped —
mirroring the `(owner, id)` identity discipline used elsewhere in the SDK.

**1:1:1 holding.** Each authorised APKAM keypair (one per keyfile/install/
enrollment — [§2](#2-subsystem-b--the-secret-sharing-substrate-wp-ss), decision #F in [`decisions.md`](decisions.md)) holds the namespace's
nskey private, received per-APKAM over the substrate.

**B1 build detail (one nskey keypair per namespace).** Per-`(atSign, namespace)` there
is **one** nskey keypair, under the KEM this deployment configured
(`AtClientPreference.keyEstablishmentAlgo` — X-Wing by default, ML-KEM-1024 the
no-hybrid option). Its private is **minted as a fresh random keypair
and distributed per-APKAM over the substrate** (sealed to each authorised
enrollment's key package) — it is **never derived from a shared seed** ([`decisions.md`](decisions.md) [section 11](decisions.md#11-single-nskey-per-namespace-lazily-published-2026-06-30)).
The public half is published **eagerly** — written at mint, always, to
`public:__nskey.<ns>@<atSign>` as an **APKAM-signed envelope** carrying
`{v, createdAt, keys:[{use, alg, pub, kid, status?}], suites}`, verified against the publishing enrollment's
`_apsk` exactly
as a key package is (see *Advertised-key authenticity*,
[§2.1](#21-kpid-addressing-__ssenv-envelope-signverify)). There is no owner-only stage
and no promotion step ([`decisions.md`](decisions.md) [section 13](decisions.md#13-the-nskey-is-published-eagerly-mutable-and-generation-addressed-2026-08-02)).

**`alg` and `suites` on the advertisement, and why both are needed.** `alg` names the
key-establishment algorithm the published key **is a key for**: a sender cannot tell an
X-Wing encapsulation key from an ML-KEM one by looking — both are opaque byte strings —
and encapsulating under the wrong KEM produces a conveyance the owner can never open.
An advertisement carrying no `alg` reads as the hybrid, which is what every one
published before the field existed was by construction; one naming an algorithm this
build cannot encapsulate to is **refused rather than guessed at**. `suites` names the
sealing **constructions the owner can open**, which `alg` does not determine — a KEM key
opens every construction built on that KEM, and which of those the holder implements
depends on its build. The sender takes the strongest entry both sides list and derives
the `pqSeal` version from it, so the conveyance version is negotiated rather than
fixed: a modern X-Wing owner receives `0x02`, one whose advertisement predates the
field receives `0x01`, ML-KEM-1024 receives `0x03`, and no overlap is a refusal. The
published list is derived from **the generation's own KEM**, never from what this build
supports, and the absent-field default must never grow — unlike a key package, an
advertisement is fetched by *senders*, who act on the claim immediately. See
[`decisions.md` 50.3](decisions.md#503-the-kem-is-configured-the-construction-is-negotiated).

### 1.4 the nskey and the signing root

> **Revised 2026-08-03.** What this section used to say — that
> `public:pqpublickey@<atSign>` was the atSign-level root **KEM** target and the
> universal cold-start recipient — is gone. The key signs and verifies only, is named
> `public:pq_signing_root@<atSign>`, and is the user-owned root of trust. The full
> reasoning, and what it replaced, is
> [decisions.md section 18](decisions.md#18-pqpublickey-becomes-the-user-owned-signing-root-2026-08-03).

**The nskey's public half is published eagerly.** Minting writes
`public:__nskey.app_1.my_apps@alice` there and then — before any data, before any
share. A sender never has to wonder whether a recipient has "published yet": if the
recipient has ever used the namespace, the key is there.

**Why the double underscore.** A published key advertises that the namespace
*exists*, and namespaces are app names, so the set of them profiles an atSign. A
`public:__` key is revealed only *by* `showhidden`, and an **unauthenticated scan
ignores `showhidden`** — so the only scan an outsider can issue never returns it, while
`plookup` still serves it on an exact name, cross-atSign. Fetchable by anyone who
already knows the namespace; enumerable by nobody who matters.

A *single* underscore hides the key from every scan, the owner's own included, which is
strictly stronger — but such a key is written with **commit id -1**: it sits outside
the commit log, so **sync can never push it**, and an advertisement that cannot leave
the device is not an advertisement. The second underscore is therefore a requirement,
not a preference. For the same reason the advertisement is written **straight to the
atServer** rather than through the local-first put path — it is only useful once a
*peer* can fetch it. Both facts are measured against a live atServer, not inferred
([`decisions.md`](decisions.md) [section 13](decisions.md#13-the-nskey-is-published-eagerly-mutable-and-generation-addressed-2026-08-02)).

**The advertisement is mutable, and writes take a lock.** The record holds the
*current* generation and is **overwritten** on rotation — it has to be, or B5b could
not run ([§1.7](#17-forward-secrecy--rotation-levers-ck-rotation-vs-nskey-keypair-rotation)). Immutability here was
never a confidentiality control; substitution is prevented by the APKAM signature over
the envelope, verified against `_apsk`. What immutability *was* doing is stopping two
of the owner's enrollments creating or rotating at once, so that job moves to an
explicit **short-ttl immutable lock key**, `_nskeylock.<ns>@<atSign>` — a self key,
since no one else can write the owner's records. Take the lock, mint, write the
advertisement, convey the private, release (or let the ttl expire). The loser of the
race backs off and re-reads. The root `public:pq_signing_root@<atSign>` now follows
exactly the same pattern, behind `_rootlock@<atSign>`
([`decisions.md` 101](decisions.md#101-the-signing-root-becomes-an-ordinary-signing-key-and-rotatable-2026-08-15)):
it is an ordinary signing key, and advertising a successor beside a retired
predecessor is a rewrite, which an immutable record makes unimplementable.

**The private half** is the sensitive part: it cannot ride the RSA-tainted
self-encryption-key chain, so it is conveyed PQ-safely per-APKAM as a `Secret` over
the substrate. A client gets the public by `plookup` and the private from the
substrate.

**The signing root.** `public:pq_signing_root@alice` is the atSign-level,
user-owned root of trust: ML-DSA-65, no namespace, **mutable** behind
`_rootlock@<atSign>`, and destined for a key-transparency log. It signs and verifies. Nothing is ever
encapsulated to it, so it is **not** a cold-start recipient and there is no
`recipientKind` for it.

**Cold start therefore fails.** When a sender has no
`public:__nskey.<ns>@<recipient>` to seal to, there is no PQ key to substitute, and
under eager publication that missing nskey means exactly one thing: **the recipient
has never used or authorised that namespace**. The write raises
`NamespaceKeyUnavailableException`, carrying the atSign and the namespace so an app
can say which recipient has not enabled what. `CryptoRuntime.isReadyFor` answers the
same question before a user composes anything. The one escape is the legacy path, and
it is opt-in (`AtClientPreference.allowLegacyCryptoFallback`, default off) precisely
because a silent downgrade to RSA is what this design exists to stop; it is applied
per write, so it is forward-only — the first write after the recipient publishes is PQ
again. Once they mint, the sender's next re-`plookup`
([§1.5](#15-the-ck-model-cache-ckkid--appmetadata-encoding)) picks the nskey up.

**Naming.** The root carries no namespace suffix — `pq_signing_root`, not
`publickey.pq`, since a `.pq` suffix would land it *in* a namespace called `pq`. Its
value is a JSON structure, `{v, keys[]}` in the `_apsk` advertisement vocabulary —
`{kid, use, alg, pub, status?}` per entry — so the algorithm can evolve without a
second record and a retired root stays advertised for what it signed
([`decisions.md` 101](decisions.md#101-the-signing-root-becomes-an-ordinary-signing-key-and-rotatable-2026-08-15)).
Only an enrollment with
`rw` on `*` and `__manage` may create it; the private rides that app's `.atKeys` and
reaches the other privileged enrollments over the substrate. The `_rootlock@<atSign>`
mint lock is what stops two of them minting two roots, which would still be
unrecoverable: D1 builds the root's rotat*ability*, not a rotation that could
reconcile a split. Lifecycle
in [§2.5](#25-the-authenticated-self-retrofit-flow-fresh-auto-approved-enrollment).

**One key per advertisement, and the assumption that rests on.** The record
carries a single `publicKey` with a single `alg`. A sender gets no choice: if the
advertised algorithm is not the KEM its provider handles, it refuses rather than
falling back, since encapsulating under the wrong KEM produces a conveyance the
owner could never open. That restricts nobody *while every build carries every
KEM*, which is true today because both shipped in one codebase
([decisions.md §50.2](decisions.md#502-the-sender-follows-the-recipient-so-configuring-a-kem-restricts-nobody)).

It stops being true the moment a **third** KEM is added, or a consumer pins an
older `at_client` than its peer. From then on, a recipient who rotates to the
newer algorithm stops every sender that has not shipped it, and those senders
recover only when *they* upgrade — a flag day imposed on senders by a recipient,
which is the failure
[§1.8](#18-migration-rollout--the-disallowlegacyencryption-flag-d1-c--d1-d)
exists to prevent. `suites` gives agility over the *construction*; nothing gives
it over the KEM. The direction of travel is a set-valued `keys[]` on the
advertisement, mirroring the key package, added while no advertisement has been
published anywhere and the change is still a shape rather than a migration:
[decisions.md §76](decisions.md#76-the-nskey-advertises-one-kem-key-and-50s-premise-is-a-release-property-2026-08-10).

### 1.5 The CK model, cache, ckKid & appMetadata encoding

**`appMetadata` encoding — carries `ns`, and on a data value `ckNs` too**
([`decisions.md`](decisions.md) [section 19](decisions.md#19-nested-namespaces-the-nskey-is-resolved-by-walking-up-2026-08-03), which supersedes this section's former
"carries no `ns` field"). The namespace cannot come from the at-key name:
`AtKey.fromString` splits at the **last** dot, so `someid.d.c.b.a@alice` parses back
as `key = someid.d.c.b`, `namespace = a`, and a multi-segment namespace is
unrecoverable from the wire. Every record therefore states its own. This is not a new
disclosure — the namespace is already plaintext in the key name.

- On an `at/nskey/*` **CK-conveyance record**:
  `{ providerId: "at/nskey/XWING/AES/GCM", recipientKind, ckKid, nskeyKid, ns }` where
  `recipientKind` has one member, `"nskey"`, and `ns` is the resolved namespace the
  conveyance lives at. `nskeyKid` names the
  **generation** the CK was sealed to, so a reader holding several after a rotation
  indexes straight to the right private instead of trial-decapsulating each in turn
  ([§1.7](#17-forward-secrecy--rotation-levers-ck-rotation-vs-nskey-keypair-rotation)).
  The record's `@<owner>` + key name identify *whose* nskey the CK was sealed to;
  `recipientKind` is on the wire so a future recipient key class can be told apart on
  a record already written — the signing root is not and never will be one of them.
  The `<ckKid>` in the key name equals
  `appMetadata.ckKid`. The value is the `pqSeal` envelope wrapping the CK (KEM ct +
  AEAD body) — **no separate `iv`/`kemCt`** on the conveyance.
- On an `at/symmetric/AES/GCM` **data value**:
  `{ providerId: "at/symmetric/AES/GCM", ckKid, iv, ns, ckNs }`. `iv` is the base64
  12-byte GCM nonce, per value. **No sealed key is present** (decision (a)). `ns` is
  the value's **own** full namespace — it is what the AAD binds, so two items under
  different sub-collections cannot have their ciphertexts swapped. `ckNs` is the
  namespace the CK and its conveyance live at, which differs from `ns` whenever
  resolution walked up: every AtCollection sub-collection item, and the stale-sender
  window of [`decisions.md`](decisions.md) [section 19.4](decisions.md#194-cost-and-the-three-lifetimes). Neither is derivable from the other.

**`ckKid`** is the content key's id — a SHA-256 prefix of the CK (deterministic;
dedupes identical keys) or a random id. It must be unique within `(owner, ckNs)`
and is the CK cache key alongside them.

**Namespace resolution.** A sender walks the value's namespace **most-specific-first**
— `d.c.b.a`, `c.b.a`, `b.a`, `a` — and seals to the first published nskey it finds; the
namespace it lands on is `ckNs`, and cold start is the whole walk coming up empty. The
walk mirrors the atServer's own suffix authorisation, so the crypto gate never widens
past the transport gate, and it is what makes AtCollection viable: sub-collection
namespaces embed a per-**item** id, so an exact-match rule would need a keypair and a
per-enrollment conveyance per item. Senders remember which namespaces an owner holds
levels it has found **empty**, so a repeated write re-probes nothing; a namespace never seen
before still probes its own levels once, which is the irreducible cost. Remembering *hits*
instead is unsafe and was rejected: it lets a resolution skip the deeper probes entirely, so
a key at `medical.notes` goes unseen because some earlier write warmed `notes`. Full ruling,
its cost floor and its accepted exposure: [`decisions.md`](decisions.md) [section 19](decisions.md#19-nested-namespaces-the-nskey-is-resolved-by-walking-up-2026-08-03).

**CK cache.** Keyed by `(owner, ckNs, ckKid)` where `owner` is the **nskey
owner** — so a CK is scoped to the recipient it was cut for, not to the sender
([`decisions.md`](decisions.md) [section 14](decisions.md#14-content-keys-are-scoped-per-recipient-2026-08-02)). Populated by the `at/nskey` provider when a
`<ckKid>.__ck` record syncs (decapsulate-then-cache); read by the
`at/symmetric/AES/GCM` provider on each data value. Only the client that *cut* a CK
marks it **current**: an arriving conveyance is cached but never promoted, because
sync is unordered and an older record would otherwise roll new writes back onto a
superseded key.

**Key discovery, and how a sender learns of a rotation.** A sender obtains a
recipient's `public:__nskey.<ns>@<recipient>` via an exact `plookup` and verifies the
envelope against the publisher's `_apsk`. There is **no feedback path from a failed
decapsulation** — the sender never decapsulates, and the recipient's failure happens
on the recipient's device — so staleness cannot be detected reactively. Instead the
sender keeps a **TTL-bounded cache** of the recipient's advertisement, re-`plookup`s
it when stale, and compares the advertised `nskeyKid` against the one its current CK
was conveyed under; a mismatch forces a fresh CK sealed to the new generation. The
cache is what keeps this off the write path — `ensureCurrent` runs on every `put`, so
fetching each time would make a write depend on the recipient's atServer being
reachable and break offline writes. Exposure is **the TTL plus one CK lifetime**. Without this, a sender
keeps sealing to a pre-rotation generation that a revoked enrollment can still open,
and **B6 revocation silently fails for inbound cross-atSign data**; with it, exposure
is bounded by one CK lifetime. The owner's **own nskey is never looked up** for self
data — her clients hold it from the substrate
([§2](#2-subsystem-b--the-secret-sharing-substrate-wp-ss)).

### 1.6 The uniform data flow + cold-start + resolution/ordering

One write/read pattern, **identical for self (Alice→self) and cross-atSign
(Bob→Alice)** — only *whose* nskey is the target differs:

**Write** (sender = whoever owns the data). A **CK manager** sitting above both
providers owns steps 1–2; the data provider does step 3 and never touches asymmetric
crypto:
1. `ensureCurrent(destination, ns)` — re-`plookup` the destination's advertised nskey,
   and if there is no current CK for that destination, or the advertised `nskeyKid`
   has moved, cut a fresh **CK** (cadence is otherwise the sender's policy). A CK is
   **per recipient**, so writing to Bob and writing the self-copy use different keys
   ([`decisions.md`](decisions.md) [section 14](decisions.md#14-content-keys-are-scoped-per-recipient-2026-08-02)).
2. **Convey the CK once** (`at/nskey`): `X-Wing-seal(CK)` to that destination's
   nskey — the owner's **own** nskey for self data; the recipient's published nskey
   for shared — written as a `<ckKid>.__ck.<ns>@<owner>` record stamping `nskeyKid`.
   (Skip if the CK is already conveyed to that generation.)
3. **Write data** (`at/symmetric/AES/GCM`): AES-256-GCM under the CK; stamp
   `ckKid` (+ `iv`) in `appMetadata`.

A cross-atSign share runs this twice — once for the recipient, once for the sender's
own scope so her other clients can read what she sent — producing two conveyances and
two ciphertexts.

**Read** (recipient = an authorised client):
1. On syncing a `…__ck…` record, `at/nskey` **decapsulates the CK** with the private
   named by `nskeyKid` — always the reader's **own** nskey, never the record owner's —
   and caches it by `ckKid`. If the reader does not hold that generation it pulls it
   over the substrate (`requestSecret`) rather than failing
   ([§1.7](#17-forward-secrecy--rotation-levers-ck-rotation-vs-nskey-keypair-rotation)).
2. On a data value, `at/symmetric/AES/GCM` **resolves the CK by `ckKid`** (from
   cache) and AES-GCM-decrypts.

**Resolution & ordering.** Sync is not ordered, so a Layer-3 data value can arrive
**before** (or without) its CK conveyance. On a `ckKid` cache miss the
`at/symmetric/AES/GCM` reader (a) decapsulates the local `<ckKid>.__ck` record on
demand if present, else (b) yields a `Stream.error` / deferred state and re-attempts
when the conveyance syncs — mirroring `getItemsAsStream`'s per-key decode-failure
convention. A value whose CK was deleted for forward secrecy stays undecryptable,
by design.

**Cold-start.** When the sender finds no `public:__nskey.<ns>@<recipient>` — under
eager publication, exactly when the recipient has **never used or authorised that
namespace** — the write **fails**. There is nothing to seal to: the signing root
cannot receive an encapsulation ([§1.4](#14-the-nskey-and-the-signing-root)). The
refusal is `NamespaceKeyUnavailableException`, naming the atSign and the namespace,
raised by `CkManager.ensureCurrent` — the *pre-pass*, before anything is in flight,
which is what leaves the caller free to reroute. `CryptoRuntime.isReadyFor` asks the
same question in advance. The recipient's first use of the namespace mints and
publishes its nskey, and the sender's next re-`plookup` at `ensureCurrent` sees it. A
strict-mode seal-and-hold alternative was considered and **deferred, not built** —
it needs a durable outbox (where a pending write lives, when it retries, what a
rotation does to it), and no consumer has asked for more than the named refusal
plus the opt-in fallback
([`decisions.md` 36](decisions.md#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05)).

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
Take the `_nskeylock.<ns>@<atSign>` lock → mint a **new nskey keypair** →
**overwrite** `public:__nskey.<ns>@<atSign>` with the new advertisement
envelope → convey the new nskey private **per-APKAM over the substrate** (`__ssenv`
envelopes sealed to each authorised APKAM keypair's key package, pushed via
`enroll:listns` + the pull backstop —
[§2](#2-subsystem-b--the-secret-sharing-substrate-wp-ss)), **excluding** any revoked
keypairs (`excludeEnrollmentIds`) → release the lock.

**Earlier generations are retained, not discarded.** A client keeps every nskey
private it has held, keyed by `nskeyKid`, so retained `__ck` records sealed to a prior
generation still open. A *new* enrollment is pushed the **current** generation only —
join stays O(1) — and pulls an older one on demand via `requestSecret` when it meets a
`__ck` tagged with a kid it does not hold. History is therefore pay-as-you-go, and a
device that never reads back never pays.

**Senders must notice.** Rotation is the revocation lever, so a peer still sealing to
the superseded generation hands the revoked enrollment a key it can still open. There
is no failure signal back to a sender, so the sender re-`plookup`s at every
`ensureCurrent` and re-cuts its CK on an `nskeyKid` change
([§1.5](#15-the-ck-model-cache-ckkid--appmetadata-encoding)). Exposure is bounded by
one CK lifetime.

Rotation buys
namespace-granular **post-compromise security**; it is the per-APKAM revocation
lever. It does **not** give per-message FS or history re-encryption (the old nskey
private retained → history-on). Coarse FS comes from B5a, not from this.

**(B6) Revocation wiring.** Composes: (1) enrollment revocation (`enroll:revoke` —
APKAM, free, cuts future server access); (2) nskey-keypair rotation **excluding**
the revoked enrollment (`excludeEnrollmentIds`, B5b); (3) optional history
re-encrypt (expensive — D2). A revoked enrollment, excluded from a rotation, cannot
read post-rotation data.

> **As built (2026-08-06,
> [`decisions.md` 47](decisions.md#47-b-2-lands-two-levers-and-the-difference-between-excluding-and-revoking-2026-08-06)):
> the order of (1) and (2) is the enforcement, not a preference.** An
> `excludeEnrollmentIds` set stops the *rotating client* pushing; it cannot bind
> another holder, which honours only what the atServer tells it. A
> still-approved enrollment therefore pulls the successor from whichever holder
> answers first, and the exclusion is undone. Revoking first removes it from
> `enroll:listns` — approved enrollments only — so every roster and every serve
> refuses it at once, including on holders that never heard of the rotation.
> `NskeyRotation.revokeEnrollmentAndRotate` is that composition. Note also that
> the two halves need **different** privileges: rotating is gated on `rw` for
> the namespace (the atServer's own bar on the advertisement write), revoking on
> `__manage`.

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

> **Rewritten 2026-08-05.** The original C1/C2/C3 here specified a readiness
> marker, per-destination scheme negotiation and per-namespace strict-mode
> toggles. All three were removed by
> [`decisions.md` 36](decisions.md#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05)
> — the marker/negotiation half was **built, proven live, and then removed** when
> the three-scenario examination showed the model it served was wrong. This
> section now records the model that replaced it.

The nskey data path coexists with legacy and is adopted **per app, by the app's own
two releases** — no flag day, no negotiation, no readiness machinery. **The unit of
migration is the app, and an app is an enrollment**: its own AtKeys, its own APKAM
keypair, its own namespaces. Apps migrate independently and never have to agree.

**The two releases.**
1. **Capability (final 3.x).** Rebuild only → a **universal reader** + back-compat
   writer: reads anything ever written (legacy or nskey), upgrades its enrollment
   ([§2.5](#25-the-authenticated-self-retrofit-flow-fresh-auto-approved-enrollment)),
   mints/publishes its namespace keys or pulls their privates
   ([`decisions.md` 38](decisions.md#38-key-material-self-heals-mint-if-absent-else-pull-2026-08-05)),
   and **keeps writing legacy**. Upgrading only ever **adds** read capability — a
   rebuilt client never loses access. This build must be **rolled out before** the
   next one ships: that release-ordering discipline is the one thing the model asks
   of an app developer, and it replaces every piece of removed machinery.
2. **Active use (4.x, or an explicit opt-in today).** The app now writes the
   nskey data path. **The SDK never decides to write PQ — the app tells it
   to**, implicitly by riding the 4.x default, or explicitly by naming a
   `crypto` config — or, since
   [`decisions.md` 70](decisions.md#70-workstream-a-capstone-releaseposture-the-five-flags-as-one-value-2026-08-10),
   by building its preference with `ReleasePosture.postQuantum()`, which runs
   the 4.0 flag defaults (era config, `disallowLegacyEncryption`, pq enrollment
   key exchange, ML-DSA retrofits) on a 3.x build. It carried a fifth, the JWS
   envelope wrapper, until
   [`decisions.md` 95](decisions.md#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12)
   ruling 1 made one envelope shape unconditional and removed the axis; the
   field is still on the class until that lands.
   4.0 itself is that posture becoming the default — final-3.x code,
   different flag defaults
   ([`decisions.md` 56.4](decisions.md#564-from-the-pq-projects-view-40-is-final-3x-with-different-flag-defaults)).

`appMetadata.providerId` on each stored value **and** on the notification frame
tells the recipient which provider opens it; **reads are universal** regardless of
the writer's scheme. The only write-path gate is **cold start**
([§1.6](#16-the-uniform-data-flow--cold-start--resolutionordering)): a destination
with no published nskey for the namespace is refused by name, with
`allowLegacyCryptoFallback` as the explicit escape hatch.

**Mixed cases, settled** (full taxonomy:
[`decisions.md` 36](decisions.md#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05)–38):
- *Sibling apps* (`app1.my_apps` legacy, `app2.my_apps` active-PQ) coexist freely —
  atServer suffix authorisation means neither reads the other, and nskey resolution
  walking **up** only ever lands on ancestors whose holders could already read
  through the server. The crypto gate never widens past the transport gate.
- *A vendor app authorised at the parent* (`my_apps`) is a genuine reader of both
  children: if it is still legacy while a child goes active-PQ, it loses access to
  the child's new records. Same vendor, same release call — sequence the parent
  app's capability build first.
- *Mixed installs of one app* (one updated, one not) on the recipient side: the
  app developer's release discipline, explicitly not the SDK's to detect
  (ruled 2026-08-05).
- *Two apps sharing exactly one namespace*: that developer's problem, well upstream
  of encryption.

**Legacy key material is retained until the ecosystem is PQ, not the atSign**
([`decisions.md` 37](decisions.md#37-legacy-key-material-is-retained-until-the-ecosystem-is-pq-not-the-atsign-2026-08-05)).
Onboarding keeps cutting the legacy encryption keypair + self-encryption key;
`enroll:approve` keeps conveying both; an enrollment upgrade keeps the RSA APKAM
keypair alongside the new material (a shared keyfile whose APKAM was *swapped*
locks its co-tenant apps out of auth); and a new atSign publishes its RSA
`public:publickey` by default. A future release stops all of this by default,
unless asked.

**D1-D — the `disallowLegacyEncryption` flag** *(built, 2026-08-05 — the surviving
strict-mode control, and the app-decides model's own voice: it is how an app states
"never write legacy")*. A flag on `AtClientPreference`:
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
- The **cold-start legacy fallback** (`AtClientPreference.allowLegacyCryptoFallback`,
  [§1.4](#14-the-nskey-and-the-signing-root)) *is* a legacy write and **does** trip the
  `=true` refusal — that is the point of both switches: one says "reach this recipient
  however you can", the other says "never write legacy", and the second wins.

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

**Current state (2026-07-20).** The client substrate is **on trunk** — SS-0 merged
via PR #2037 on 2026-07-17 and shipped in `at_client 3.14.0` as an experimental
surface (`pairwise_secret_sharing.dart`, `secret_envelope.dart`,
`key_package.dart`, `secret_store.dart`, `enrollment_directory.dart`,
`mixins/envelope_signing.dart`), in the 1:1:1 / flat `listns` / no-write-path
shape (the retired nested `apkam[]` parse and the `enroll:metadata` registration
write were reworked out via #2043, per decision #F / OQ9). The **server verb has
landed** too (at_server #2685, merged 2026-07-07, plus #2687 / #2696 / #2698 /
#2710).

*(The "still absent" list that stood here dated 2026-07-20 is discharged: SS-2
wired the substrate into `AtClient`, `enroll:listns` is driven in production by
`VerbEnrollmentDirectory` and exercised live by both harness suites, and the
consumer layers — nskey minting/seeding, the `pq_signing_root` lifecycle with its
pull initiator, the key-material self-heal — are built
([`decisions.md` 38](decisions.md#38-key-material-self-heals-mint-if-absent-else-pull-2026-08-05)).
RF-2b and RF-2c's switch-over landed 2026-08-05 ([decisions 43](decisions.md#43-rf-2b-lands-and-what-the-first-genuine-ml-dsa-pkam-found-2026-08-05)–[44](decisions.md#44-rf-2c-the-switch-over-and-what-it-cost-to-make-a-client-pq-2026-08-05)). Still genuinely absent: RF-2c's UC-B1.x e2e rows.
The full built/gap inventory with `file:line` evidence is in
[§6](#6-implementation-notes--file-level-pointers-consolidated).)*

### 2.1 kpid addressing, __ssenv envelope, sign/verify

**Envelope key shape.** `<msgId>.<kpid>.__ssenv.<ns>@<owner>` — a self key,
`shouldEncrypt=false` (the value is already ciphertext). The body is raw `pqSeal`
bytes (versioned HPKE sealing — KEM and AEAD per the version byte, see
[seal-spec.md](seal-spec.md) — HKDF info domain-separation
`'at_client/secret_sharing/v1'`).
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

**Advertised-key authenticity (decision 2026-07-02, [`decisions.md`](decisions.md) [section 6](decisions.md#6-resolved--open-execution-decisions-af)).**
Every *advertised recipient key* — the per-enrollment **key package** (Layer 1) and the
published **`nskey`** public half — is itself
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
merely server-asserted. The signing root is not on this list, because nothing is encapsulated to it — it is
verified as a *signer*, and what anchors it is key transparency rather than an `_apsk`.
For a **keypair secret** conveyed over the substrate
(`nskey` / signing-root privates) the receiver additionally checks public/private
correspondence against the (signed) published public half — a useful secondary check,
subordinate to the signature.

**The `_apsk` two-stage ladder (2026-08-05,
[`decisions.md` 39](decisions.md#39-_apsk-rides-the-same-two-stage-ladder-2026-08-05)).**
"Self-describes enough to verify" is **live as of 2026-08-05**: `signEnvelope`
branches on `signingAlgo` and `wrapAndSign` passes the client's resolved
algorithm, while `verifyEnvelope` reads the published key's own declaration,
which is authoritative over the envelope's claim. And apps (NoPorts) sign and
verify with `_apsk` today, so the key itself migrates on the same two-release
ladder as everything else. There are exactly **two** published forms: the
**bare** RSA public key string exactly as now, and the **array**
(`{"v":1,"keys":[{kid,use,alg,pub}]}`) — see `apskAdvertisement` in at_auth,
which composes it, and `apskSigningKeys`, which reads it. A plain-legacy
enrollment publishes the bare form, everything else publishes the array; the
discriminator is the enrollment's own material, not the client's major version.
Both are composed **by the client** and carried on `EnrollParams.apskLegacy`
and `EnrollParams.apsk` respectively — since
[at_server#2744](https://github.com/atsign-foundation/at_server/pull/2744) the
atServer composes nothing and publishes only what a request sends it, so a new
signing-key shape needs no server release. (An earlier single-key **tagged**
form, `{v,signingAlgo,publicKey}`, was designed and built but never published
by anything; it was deleted 2026-08-12 rather than carried, since nothing
released emits it and the array supersedes it.) The array must be
unmistakable to an old bare-RSA parser — fail loudly, never mis-read — which is
exactly why a plain-legacy enrollment keeps publishing the bare form. In-place
rsa→mldsa65 upgrade of an existing enrollment's signing key is recommended against
(the enrollment-upgrade path reaches the same end state with mechanics that exist);
ratified 2026-08-05: [decisions 42](decisions.md#42-the-to-define-list-ruled-2026-08-05) item 8 ratifies the "no" on an in-place rsa→mldsa65 upgrade, and item 9 freezes the tagged format.

**Trust nuance.** The signature is verified against `_apsk`, which the atServer serves —
so it authenticates against a rogue *insider* enrollment (under an honest server) but
**not** against a malicious atServer *operator*, which controls both the signature key
and the `_apsk` it is checked against. This holds same-atSign and cross-atSign alike;
the operator of an atSign's atServer stays in the confidentiality TCB for data destined
to that atSign until the anchor is distributed independently. See
[§7 Trust boundary & residual threats](#7-trust-boundary--residual-threats) for the full
model and the mitigation ladder — do **not** describe signing as removing the atServer
from the TCB.
*(Status: **both advertised keys are signed and verified.** The published `nskey` —
`PublishedNskeyKeyRing.mintAndPublish` wraps its advertisement with `wrapAndSign` and
`ApkamSignedAdvertisedKeys` verifies a peer's, cross-atSign on the live wire. The **key
package** — `KeyPackageRegistration.signedKeyPackagePayload` produces the signed value
for `metadata.keyPackage`, and `VerbEnrollmentDirectory` verifies it against the
advertising enrollment's `_apsk` before sealing, rejecting a package that is unsigned,
tampered, signed by a different enrollment, or merely claiming to be that enrollment's.
Remaining gaps, updated 2026-08-05: none of the two that stood here — SS-2 wired
`enroll:request` (live coverage: `enrollment_key_package_live_test.dart` and the
signing-root pull pair), and the correspondence check is built
(`NskeyPrivateFiling._corresponds`, refusing a private that does not derive the
published public half).)*

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
  (sync-progress listener + periodic local sweep → `receivedSecrets`);
  **plus an optional wake-up `notify`**
  (default on) per put, so sync-less clients wake on their notification monitor
  and `get` the key (`useRemoteAtServer`). Applies to both request and response.
  The envelope put is **remote-first** (`useRemoteAtServer = true`): the wake-up
  is a direct remote call, so a local-first envelope would still be waiting on a
  sync cycle when a sync-less recipient remote-swept, and the wake-up is
  one-shot — that client would then fall back to the pull path. Remote-first
  costs the *sender's* offline tolerance on this write (an offline sender fails
  rather than queueing); delivery stays offline-tolerant for the **recipient**,
  which is what the property is for, and `requestSecret` remains the backstop.
  That trade exists only because nothing today preserves ordering across a
  keystore write and a notification —
  [#2116](https://github.com/atsign-foundation/at_client_sdk/issues/2116) would
  remove it and let this go back to a local-first put with both properties
  intact; [#2117](https://github.com/atsign-foundation/at_client_sdk/issues/2117)
  is the broader intent-based framing. Both are outside the D1 program.
  On the read side the mirror of this is `clientRunsSync` (default true): the
  periodic sweep reads the local store when sync fills it and the atServer when
  nothing does, so a sync-less client that misses a wake-up still picks the
  envelope up lazily rather than only via `requestSecret`. Missed wake-ups are
  already partly covered by the atServer's offline-notification replay, and the
  wake-up carries the **same expiry as the envelope**, so a replayed nudge can
  never point at a value that has already expired.
  (Future: the atServer auto-notifies on `__ssenv` puts — see DEP4 in
  [§6](#6-implementation-notes--file-level-pointers-consolidated); DEP4 is delivered
  inside SS-2 per the implementation plan — the auto-notify is additive and could ship
  independently, but the client default-flip is sequenced in SS-2.)
- **Responder authorisation = namespace authorisation.** Serve a namespaced secret
  to requester `R` only if `R`'s enrollment is authorised for that namespace; the
  authoritative source is the server-sourced discovery verb ([§2.3](#23-the-enrolllistns-verb--enrollparamsmetadata)), not a client
  self-claim. **Never serve to an `excludeEnrollmentIds` member** (revoked).
- **The signing root is the no-namespace exception** — it has no namespace to gate
  on. Unlike the legacy default encryption private key it is **not** served to every
  non-revoked enrollment: only fully privileged ones (`rw` on `*` **and** `__manage`)
  hold it, because only they may mint it. *(Built: `PqSigningRoot` mints, serves
  to privileged requesters, and pulls via `requestPrivateIfAbsent` at every
  start — [`decisions.md` 31](decisions.md#31-the-root-pull-initiator-and-what-it-did-not-settle-2026-08-04) and
  [38](decisions.md#38-key-material-self-heals-mint-if-absent-else-pull-2026-08-05).)*
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

**The start-time self-heal invariant (2026-08-05,
[`decisions.md` 38](decisions.md#38-key-material-self-heals-mint-if-absent-else-pull-2026-08-05)).**
What every enrollment does with these primitives at client start: for each
authorised namespace, **mint the nskey if none exists, else pull the private
parts** — from *any* current holder, not "the creator", who may be long gone
(current generation to write; older generations on demand for history). A fully
privileged enrollment does the same for the signing root. This is the ruling that
turns Decision #4 from prose into an invariant: as found on 2026-08-05, neither
approve-time push (`shareAllSecretsWithEnrollment`, `conveyHeldPrivatesTo`) had a
caller and the nskey privates had no pull initiator, so the *only* delivery was
the mint-time push and every enrollment created after a mint was stranded.

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
is **no `enroll:metadata` verb** and, as built, **no post-enrollment metadata
write** — the metadata is persisted by the branch that creates the record and
never afterwards.
Old clients tolerate an absent `metadata` (the discovery element simply omits it).

That freeze is no longer permanent by design. It was scope, not a security
property — a reader trusts a key package because its APKAM signature verifies
against that enrollment's `_apsk`, which is indifferent to whether the record can
be rewritten — and it costs a package that can never gain a key, an envelope-shape
ratchet that cannot be turned, and an unparseable package that ends an
enrollment's ability to receive a conveyance for good. `enroll:update` is
ruled in [decisions.md 68](decisions.md#68-the-enrollment-record-stops-being-a-one-way-door-enrollupdatemetadata-2026-08-10):
self-only, approved-state-only, per-key set rather than whole-map replace, with
the server keeping no opinion on the contents. Nothing of it is built; until it
ships, the paragraph above describes the behaviour.

The key package sits at a **singular `metadata.keyPackage`** (1:1:1 — one enrollment,
one key package; **no format-keyed `keyPackages` map** — key/suite agility already
lives inside the package via `keys[].alg`, `KeyPackage.suites` and `KeyPackage.v`). Its
value is the
**APKAM-signed envelope** wrapping the key-package payload (see *Advertised-key
authenticity*, [§2.1](#21-kpid-addressing-__ssenv-envelope-signverify)); the server
stores and returns it opaquely and has no opinion on its contents.

The payload is `{v, createdAt, keys: [{kid, use, alg, pub, status?}], suites: [...]}`.

**`status`** is `active` or `retired`, and it is **absent on every entry that is
active** — which is every entry a client that has never rotated writes, so the
four-field spelling above is what a reader sees in practice. It is the same field, with
the same two values and the same use-neutral meaning, on all three records that
advertise keys (`_apsk`, the key package, the nskey advertisement): *retained, not
offered for new operations*. A retired entry is skipped when choosing what to seal to
or sign with, and kept for everything already sealed to or signed by it — an envelope
lives seven days, so dropping a rotated key's entry would strand a week of traffic, and
dropping a rotated signing key's entry would retroactively unverify everything it ever
signed. A value a reader does not recognise reads as `retired`, never as `active`: an
unknown state is narrower than "offered for new operations", and the permissive reading
is the one that can make a build use a key its owner has withdrawn. The nskey
advertisement's writer never emits the field — a rotation there overwrites the record —
and its reader honours it anyway, so the vocabulary means one thing everywhere rather
than something per record ([`decisions.md` 95](decisions.md#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12)
rulings 6–9).

`keys[].alg` says which KEM key a sender encapsulates to; **`suites` says which sealing
constructions the holder can open**, which is a different question — an X-Wing private
unwraps both X-Wing constructions, since they differ in key schedule and AEAD and not
in decapsulation. `suites` is what makes moving the construction a **sender-side**
decision rather than a fleet-wide readers-upgrade-first migration: `sendEnvelope`
narrows the candidates to the chosen key's own KEM, intersects with the package's list,
and derives the `pqSeal` version from the winner. Three rules it obeys, each preventing
a named failure — the published list is derived from the package's **own keys** (a list
derived from what the build supports made a package advertising one KEM claim it could
open constructions built on the other); an **absent** list means exactly the one suite
that existed before the field and must never be widened; and on parse, entries this
build does not recognise are **kept**, because the field is the holder's statement about
itself. `metadata.keyPackage` is written by `enroll:request` and reachable
afterwards only by the enrollment's own self-only `enroll:update`
([plan 14.6](implementation-plan.md#146-the-enrollment-records-metadatakeypackage-is-a-one-way-door)),
which no client sends yet — so in practice whatever it claims is what peers seal
to, and nobody else can repair it. That is why an overstatement is a defect and
not a cosmetic one
([`decisions.md` 50.5](decisions.md#505-the-defect-a-widened-list-planted-before-anything-read-it)).

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
  (`algo_type.dart:10`); add the `mldsa65` branch in `_getVerificationAlgorithm`
  (`at_chops_impl.dart:284`) returning the existing `MlDsa65PureDartAlgo` /
  `MlDsa65FfiAlgo` ([§3](#3-subsystem-c--at_chops-pq-primitives)).
- **at_commons** — widen the pkam `signingAlgo` alternation for an ML-DSA literal
  (`syntax.dart:10`).
- **at_secondary_server** — `_getSigningAlgoType` (`pkam_verb_handler.dart:199-210`)
  gains an ML-DSA branch and must read the **RECORD's** `signingAlgo`
  (**record-authoritative**), **not** the client-supplied wire value (`:164`).
  This prevents algorithm-confusion: a forger cannot down/upgrade the verify path
  by lying on the wire.
- **at_client / at_lookup (the client-side signing swap — the piece the plan under-specified).**
  PKAM auth is a challenge-response: `from:@alice` returns a per-connection challenge, the
  client signs it (`PkamSigningAlgo`, RSA SHA-256 today — `at_lookup_impl.dart:454`), the
  server verifies. The client change is to sign that challenge with **ML-DSA-65** when the
  enrollment's APKAM key is ML-DSA — a one-line algorithm swap, selected off the same stored
  `signingAlgo`. Exercised by RF-2b (a retrofitted client PKAM-auths under its new ML-DSA key)
  and ON-1 (a PQ-native onboard authenticates ML-DSA from the start).

**Scope — a signature swap, not a KEM. Do not over-build.** Client PKAM auth is
**authentication, not key agreement**, exactly like the inter-server FROM/POL handshake
([§8](#8-subsystem-f--inter-server-pq-authentication-is-1)): the server-issued per-connection
challenge already provides freshness / anti-replay, and TLS already secures the channel. So the
whole PQ change is the RSA→ML-DSA-65 **signature** swap above — client-side sign, server-side
record-authoritative verify. There is **no KEM, no certificate, no per-connection key
lifecycle**, and none should be added. The 1:1:1 single-key record (decision #F) is the minimal
form; do not grow it into a keyring or a per-session negotiated handshake. **The one place a KEM
legitimately appears in the enrollment path is the `apkamSymmetricKey` conveyance at
enroll/approve (P-3): that is key *transport* of the approval bundle — genuine confidentiality —
not authentication, and must not be conflated with the auth swap or removed as "over-engineering".**

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
   `EnrollParams.metadata` — no post-enrollment write), then acquires the signing
   root — **minting it in-flow if fully privileged and the atSign publishes none,
   otherwise pulling it** — plus the namespace nskey privates over the substrate ([§2.2](#22-secretstore-push--pull-primitives)), **verifies
   correspondence**, and stores them in the local keystore (the extended `AtKeys`,
   via its injected `AtKeysIo`, [§4](#4-subsystem-d--structural-design-cryptoprovider-seam-atkeysatkeysio--key-stores-wasm-barrel)).
   The mint belongs to this flow and not to client start: the retrofit is
   auto-approved by the atServer with no approver client in the loop, so the
   approve-time conveyance that gives an ordinary new privileged enrollment its
   root never fires for a retrofitted one.

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

**`pq_signing_root` lifecycle.** **Mutable, minted under a lock**: the interlock is
`_rootlock@<atSign>`, a short-ttl immutable self key (`Metadata.immutable` — a
long-standing atServer feature, already live; no server change), and minting is
restricted to a fully privileged enrollment (`rw` on `*` **and** `__manage`). The
winner of the lock re-reads the record under it, generates the ML-DSA-65 keypair,
stores the private half in its own `.atKeys`, seeds it as the conveyable root secret,
and serves it on request **to the other fully privileged enrollments only**. A loser
of the lock mints nothing and files nothing → it **pulls** the private half
([§2.2](#22-secretstore-push--pull-primitives)), verifies public/private
correspondence, and stores. A lock is a protocol rather than the atServer's absolute
refusal, so what backs it is the reconciliation on every start: a held private that
corresponds to no advertised entry is retired, and the pull asks again. Two roots
would still be unrecoverable, since D1 builds no rotation able to reconcile a split. Two populations **never** run this
retrofit: a new atSign is PQ-native at onboarding; a new (post-PQ) privileged
enrollment receives the root *pushed* by the approver. F-section build detail (F1–F6) in [§6](#6-implementation-notes--file-level-pointers-consolidated).

**2026-08-05 additions
([`decisions.md` 40](decisions.md#40-rf-srv-is-the-mechanism-the-whole-model-stands-on-2026-08-05)).**
This flow is **on the D1 GA critical path**: it is the "upgrade the enrollment"
verb every migration scenario conjugates. Its server half is **built** on the
at_server spike (self-enroll + subset check + sliding expiry cap + tagged
`_apsk`); the revocation cascade is the piece still owed.

**As built, and where the code had drifted from this section
([`decisions.md` 45](decisions.md#45-the-retrofit-rows-and-the-five-defects-the-first-end-to-end-run-found-2026-08-05)).**
Three sentences above described behaviour that did not exist until the e2e rows
were written, which is worth recording because the design was right and the
implementation had quietly diverged from it:

- *"seeds it as the conveyable root secret, and serves it on request"* — the
  serving side had no seed. A holder answers out of an in-memory store a restart
  empties, and nothing re-primed it, so no holder could answer a pull. Now
  primed at start, and **before** the start-time sweep, because that sweep
  consumes the requests it would answer.
- *"to the other fully privileged enrollments only"* — the answer path checked
  namespace authorization only, which any enrollment approved for the namespace
  clears. The privilege gate is real now, and fails closed.
- *"verifies public/private correspondence, and stores"* — filing stored
  whatever arrived. It now signs a probe the published root must verify.

Also: a loser of the create **retires the pair it filed before publishing**.
Left active it satisfied the pull's "do I already hold it?" guard forever,
which is the one heal a loser has.
Constraints beyond the ruling above:

- **Revocation must cascade.** Self-enrollment makes enrollments a parent/child
  graph; a stolen keyfile can spawn a child before the theft is noticed, and a
  child that survives its parent's revocation defeats revocation. The new
  enrollment records its parent; revoking a parent revokes descendants.
- **Legacy material conveys client-side.** The requester generates its own new
  keypair, so it seals the legacy encryption keypair + self-encryption key to its
  own new key package — `encryptedDefaultSelfEncryptionKey` is satisfiable with no
  server involvement. The new enrollment id lands **in the keyfile that already
  holds the legacy material**, never a fresh file
  ([`decisions.md` 37](decisions.md#37-legacy-key-material-is-retained-until-the-ecosystem-is-pq-not-the-atsign-2026-08-05)).
- **Distinct `(appName, deviceName)` per device** — client-side discipline,
  not server-enforced: the duplicate refusal is deliberately skipped on the
  APKAM self-enrollment branch, since a retrofit legitimately keeps its own
  name ([`decisions.md` 42](decisions.md#42-the-to-define-list-ruled-2026-08-05)
  item 1). Distinctness is what lets an owner tell one device's enrollment
  from another's in `enroll:list`.
- **The expiry cap is ruled and landed**: it RE-ARMS on every sibling
  retrofit (one grace period after the *last* clone upgrades, never past the
  enrollment's own posture), grace ratified at 720h
  ([`decisions.md` 42](decisions.md#42-the-to-define-list-ruled-2026-08-05)
  item 3).
- **Step 4's pull is the *normal* path, not a backstop**, whenever the approver is
  the legacy parent enrollment (which holds nothing to push). Store-and-forward in
  both directions, so "heals when each device next runs" is latency, not
  availability
  ([`decisions.md` 38](decisions.md#38-key-material-self-heals-mint-if-absent-else-pull-2026-08-05)).

---

## 3. Subsystem C — at_chops PQ primitives

The providers and the substrate seal through one audited PQ primitive.

**X-Wing KEM** (IANA HPKE KEM id `0x647A`): ML-KEM-768 + X25519 with the
SHA3-256 combiner; 32-byte seed secret keys expanded via SHAKE-256.
Vector-verified byte-exact against the **IETF HPKE working group's** published
`0x647A` vectors, across all three operations — key generation, derandomised
encapsulation and decapsulation — in both the pure-Dart and OpenSSL FFI
backends. Go 1.26's `crypto/hpke.MLKEM768X25519()` vendors the same vector file,
so it is an independent oracle for these bytes.

The construction originates in `draft-connolly-cfrg-xwing-kem`, an Independent
Submission CFRG never adopted, which expires 2026-09-03 — cite it for history
only. `draft-irtf-cfrg-concrete-hybrid-kems` section 4.2 states that its
`MLKEM768-X25519` "is identical to the X-Wing construction". The IANA row still
reads *X-Wing*; the rename to `MLKEM768-X25519` is requested by
`draft-ietf-hpke-pq` and has not been effected.
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

**PQ enrollment conveyance.** Closing the last harvest-now-decrypt-later hole in
enrollment means not RSA-wrapping `apkamSymmetricKey`. As of the 2026-08-03 ruling the
direction reverses rather than adding an atSign-level KEM key: the **approver** seals
`apkamSymmetricKey` to the **enrollee's key package**, carried in the `enroll:request`
tail. There is no atSign-level encapsulation target — `public:pq_signing_root@alice`
signs only ([§1.4](#14-the-nskey-and-the-signing-root)). **No server change** beyond
ferrying the request tail.

### 3.1 What the standards check established

Established by a full check against primary sources on 2026-08-06, and recorded
here rather than in the decisions ledger because these are **standing facts
about the standards landscape**, not rulings — they constrain what any future
construction here may claim, and several of them corrected entries that had
been written from assumption. Re-derive none of this without a primary source:

- **No finalized standard specifies any PQ KEM inside HPKE.** Confirmed by a
  full RFC-index search with a positive control: one HPKE RFC (9180, DHKEM
  only), zero PQ ones. So no HPKE-based option — `0x0041`, `0x0042`, `0x0050`
  or `0x647A` — can be described as standards-finalized.
- **[`decisions.md` 48.4](decisions.md#484-not-switching-the-kem-and-the-fips-story-it-cannot-buy)
  is too strong and is corrected here.** X25519's absence from SP 800-56A does **not**
  by itself make the composite unapprovable: SP 800-227 §4.6.2 approves the
  combiner "if at least one shared secret is generated from... an approved KEM",
  and the other component may be "generated in some other (not necessarily
  approved) manner". What actually closes the FIPS door is **CMVP module
  validation**, which a pure-Dart implementation can never obtain.
- **SP 800-227 §4.6 names X-Wing** as its worked example of a PQ/T hybrid and
  cites the X-Wing paper as the authority for why naive combiners fail. The
  construction is not disreputable in NIST's eyes — it is simply not approved.
- **X-Wing's combiner is not SP 800-227's.** The approved `KeyCombineCCA_H`
  takes seven inputs (`K1, K2, c1, c2, ek1, ek2, domain_sep`); X-Wing supplies
  four, omitting `ct_M` and `ek_M`. Any claim that it is "a few bytes away" from
  approval is unsupported and must not be written into a specification —
  Appendix D records that the final SP deliberately moved away from prescribing
  concatenation at all.
- **`draft-irtf-cfrg-concrete-hybrid-kems` is CFRG-adopted**, not an individual
  submission. Its §4.2 states MLKEM768-X25519 "is identical to the X-Wing
  construction", which is the citation the hybrid should use rather than the
  expiring `draft-connolly-cfrg-xwing-kem`.
- **Consistency check on our own reasoning:** RFC 9180 was being marked down as
  "IRTF Informational" while RFC 9106 (Argon2id) was treated as a clean
  citation. They are the same status class. Apply one standard to both.
- **What reviewers actually score**, from reading published NCC Group, Cure53
  and Least Authority reports rather than assuming: in that corpus a
  non-standard algorithm was **never** a High or Critical. A missing
  *specification* scored Medium; self-produced test vectors were a finding
  (Cure53 MON-01-004); weak KDF parameters scored Low. That is the evidence
  behind spending the remaining weeks on specification, third-party vectors and
  the forgery rather than on further algorithm churn.

Two consequences the rest of this document depends on. **No HPKE-based option
can be described as standards-finalized**, so `pqSeal`'s `ver 0x02` and `0x03`
are "RFC 9180 Base mode at a suite whose KEM code point is registered but
draft-specified", never "standard HPKE". And **FIPS is closed to us by CMVP
rather than by algorithm choice**, so adopting ML-KEM-1024 alone buys an
approved-algorithms answer to a questionnaire, not a validated module — state it
that way or a reviewer will.

---

## 4. Subsystem D — structural design (CryptoProvider seam, AtKeys/AtKeysIo & key stores, WASM barrel)

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

### `AtKeys`/`AtKeysIo` extend-in-place + key stores

The existing **`AtKeys`** is **extended in place** — additive PQ-safe methods
(`addKey` / `retireKey`; material is **never removed** — `retireKey` moves status
forward-only, `active` → `retired` → `dead`, since retired bytes are still needed
to decrypt data they protected), with the legacy key fields/methods **deprecated**
but retained for back-compat so call sites migrate over time (ratified 2026-07-06,
#2045; the retire-never-remove and `flush()` shapes ratified 2026-07-17 — see
[`decisions.md`](decisions.md); supersedes the earlier `WritableAtKeys` holder
working name). It stays the single in-memory holder of every key the client knows
(per-enrollment *and* per-APKAM), which providers read keys from and mint/add/write
through. *(NOT a wrapper over `AtChops` — `AtKeys` already produces one via
`toAtChops()` and carries a `metadata` stash.)* The provider seam is injected an
**`AtKeysIo`** (the key source, extended with runtime persistence — one
whole-state `flush(atsign, atKeys)`: mutate in memory, then flush; on an existing
target the rewrite is safety-checked by `AtKeysAssurance.validateMapUpdate` and is
atomic, write-to-temp + rename, keeping the previous state as `<file>.bak`)
alongside `(AtClient, AtChops)`; `CryptoContext` carries the `AtKeysIo` —
**additive** (`CryptoContext` is `{atClient}`, with no `atChops` field). Convergence
(newest-wins / pull recovery) stays in the secret-sharing substrate; the stores are
**dumb** key-value backends.

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
self-enc key on rewrite; atomic write + backup). The extended `AtKeys` (with its
injected `AtKeysIo`) is born at AtClient construction and immutable after.

**Never-lose is a bootstrap-store property, not an `AtKeysIo`-wide invariant**
(ruling 2026-07-17, [`decisions.md`](decisions.md)). `flush`'s
nothing-may-be-lost contract binds the bootstrap stores (`.atKeys` file,
keychain). The distributed/rotating row above holds CK-class material whose
**deletion is the B5a coarse-FS lever** ([§1.7](#17-forward-secrecy--rotation-levers-ck-rotation-vs-nskey-keypair-rotation))
— whatever store ends up holding it must support eviction, not inherit the
flush contract. `LocalKeystoreAtKeysIo` is **not needed at this time**; its
routing (and whether it exists at all vs. the ordinary keystore + in-memory CK
cache) is decided when S-3/SS-4 execute.

### WASM barrel split (`at_auth 4.0.0`)

`at_auth`'s core must compile under `dart2wasm` (the running client, incl. web,
authenticates via at_auth; only onboarding/setup is desktop/CLI). `dart2wasm`
errors on any `dart:io` reachable from the entry point, so:

- **`at_auth.dart`** (main barrel, WASM-safe): `AtKeys` (extended in place), the
  `AtKeysIo` interfaces, `InMemoryAtKeysIo`, the auth core,
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
per-operation override from the M0 seam, [§4](#4-subsystem-d--structural-design-cryptoprovider-seam-atkeysatkeysio--key-stores-wasm-barrel)) is the per-destination gate.

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
(public half published as `public:__nskey.at_talk@alice` the moment she minted it),
and `@bob`'s likewise. **There is no group
and no epoch key.** Alice→Bob data is encrypted under a CK, conveyed once via
`at/nskey` sealed to **Bob's published nskey**; Bob→Alice
symmetrically. Alice's own clients read her sent CKs via a **second** CK in her own
scope, conveyed to the same `@alice` nskey — CKs are per recipient
([`decisions.md`](decisions.md) [section 14](decisions.md#14-content-keys-are-scoped-per-recipient-2026-08-02)). CKs are minted lazily.

**Whose nskey the CK is sealed to** is per recipient, not a group:

- Alice writing data **Bob should read** → seal the CK to `public:__nskey.at_talk@bob`.
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
| **Kb3** (@bob) | Receives the **current** `at_talk` nskey generation per-APKAM (push, or `requestSecret` pull), syncs the current `__ck` conveyances, decapsulates the live CK → reads all new data. No epoch rotation / `__ck` re-mint on join. | Reads whatever `__ck` conveyances are still **retained**, pulling any earlier nskey generation named by a record's `nskeyKid` on demand. **Retain** → opens past messages. **Delete-for-FS** → CKs whose conveyance was deleted on rotation stay opaque. |
| **Ka3** (@alice) | Symmetric: receives @alice's current `at_talk` nskey generation; reads current `__ck` conveyances → reads all new data. The same private also decapsulates @alice's own self CKs. | Reads retained `__ck` conveyances, pulling earlier generations as needed; same retain-vs-delete fork. |

**Caveats this example surfaces:**

- **History is a policy fork, not a mechanism gap.** The D1 artefact is the
  `at/nskey` CK-conveyance record, not a per-group epoch key. Retain → any
  `at_talk`-authorised keypair reads history; delete on CK rotation (+ evict the
  cached CK) → that era's data is undecryptable — D1's coarse FS ([§1.7](#17-forward-secrecy--rotation-levers-ck-rotation-vs-nskey-keypair-rotation)). D1 **does**
  have FS: coarse FS by CK rotation + conveyance deletion, plus PCS via the
  expensive nskey-keypair rotation lever.
- **A new APKAM keypair does NOT force a rotation.** Joining `at_talk` just conveys
  the current nskey generation to the new keypair and lets it read existing CKs
  (mandatory rotation on join is a D2 / MLS property, not D1).
- **Join cost is O(1) in rotations.** Only the current generation is pushed; earlier
  ones are pulled on demand, addressable because every `__ck` names its `nskeyKid`.
  Without that tag the reader would have to trial-decapsulate each generation it
  holds, paying an X-Wing operation per generation and degrading with every rotation.
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
core) **published 2026-06-23**; PR `#2035` (design fixes) **merged**. `at_commons 5.11.0`
(`appMetadata` wire) and the commit-log-free 5.x keystore are on trunk. As of the
**2026-07-17 release train**, `at_chops 3.4.0` (ML-DSA-65 verify dispatch, AES-GCM FFI,
`at_chops_ffi` barrel + `AtPqc`), `at_commons 5.13.0`, `at_client 3.14.0` (carrying the
SS-0 substrate) and `at_auth 3.3.0-rc1` (the extended `AtKeys` + `AtKeysIo.flush()`) are
all published.

### Client substrate — on trunk (SS-0, PR #2037, merged 2026-07-17)

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

**Known client gaps** (within the substrate): advertised-key signing + verify is **built**
for both the published `nskey` (`PublishedNskeyKeyRing` / `ApkamSignedAdvertisedKeys`,
proven cross-atSign live) and the key package
(`KeyPackageRegistration.signedKeyPackagePayload` / `VerbEnrollmentDirectory`), so the
authenticity decision of [§2.1](#21-kpid-addressing-__ssenv-envelope-signverify) holds —
and as of 2026-08-05 the key-package half is driven live too (SS-2 wired
`enroll:request`; `enrollment_key_package_live_test.dart` and the signing-root
pull pair exercise `enroll:listns` against a live atServer). Discharged since
this inventory was written: the public/private correspondence check
(`NskeyPrivateFiling._corresponds`), the signing root's no-namespace serve +
pull (`PqSigningRoot`), durable key material (`AtKeys` filing via
`collectConveyedKeyMaterial` + the store hydration of
[`decisions.md` 38](decisions.md#38-key-material-self-heals-mint-if-absent-else-pull-2026-08-05)),
and answer jitter (`requestAnswerJitter`). Still true: the `SecretStore` itself
is an in-memory transit buffer by design
([`decisions.md` 21](decisions.md#21-ss-3-where-key-material-lives-and-what-the-substrate-stops-storing-2026-08-03)).
`VerbEnrollmentDirectory` was reworked to the flat, single-key, `enroll:listns`,
no-write-path model (singular signed `metadata.keyPackage`, no format-keyed map) via
#2043 before SS-0 merged — the retired nested `apkam[]` parse and `enroll:metadata`
registration write are gone. Driving it against the **live** verb is SS-1c
([#2084](https://github.com/atsign-foundation/at_client_sdk/issues/2084)).

### atServer change lists (DEP1–DEP4)

`at_server` is a sibling repo present locally. **DEP1–DEP3 landed on 2026-07-07**
(at_server #2685, plus #2687 / #2696 / #2698 / #2710 — SS-1b); **DEP4 (the `__ssenv`
update-put auto-notify wake-up) remains unimplemented** and is owned by SS-2
([#2085](https://github.com/atsign-foundation/at_client_sdk/issues/2085)).

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
3. It serves an advertised recipient key (a `nskey` public / key package)
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
  sender signature — which for a [section 2.1](#21-kpid-addressing-__ssenv-envelope-signverify)-signed payload means substituting the *sender's*
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
  private), so a **self-audit** — fetch my own `_apsk` / `public:__nskey.<ns>@alice` as served and
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
   `_apsk` / `nskey` public / key package as a remote party would and compares to the
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
PKAM key in the `.atKeys`) — the stable anchor; the volatile `nskey` / key-package
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
overclaim [section 7](#7-trust-boundary--residual-threats) exists to avoid). The residual is "Atsign *and* a witness quorum collude, *or*
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

---

## 8. Subsystem F — inter-server PQ authentication (IS-1)

*The atServer↔atServer FROM/POL handshake, orthogonal to Subsystems A/B (which secure the
client↔server data path). Project [IS-1](implementation-plan.md); tracking PR #2683
(`at_server`, `pq/st/pq-interserver-comms`). Off the D1 GA critical path.*

### 8.1 What it replaces

Today the server-to-server FROM/POL handshake authenticates with a random per-session UUID
challenge signed by RSA-2048 — the same Shor-vulnerable primitive #1889 exists to retire. FROM/POL
is **authentication, not confidentiality**: it proves the peer holds a private key, and the TLS
session already secures the channel. So the only Shor-vulnerable part is the *signature*, and the
only change IS-1 needs is to swap the signing primitive:

- **ML-DSA-65** replaces RSA-2048 for signing the challenge.
- **Fallback to legacy UUID/RSA** for any peer that publishes no PQ signing key (mixed-fleet safe,
  no flag day).

Everything else in the existing handshake is retained unchanged — crucially the **per-session UUID
challenge**, which already provides the freshness / anti-replay property. A recorded ML-DSA
signature is worthless once its key is retired (signatures are not harvest-now-decrypt-later
material), so the adversary here is an *active* quantum computer forging a live authentication — a
KEM buys nothing against it, and the swap alone closes the hole.

### 8.2 The handshake

The FROM/POL flow, cookie handling, and UUID challenge are unchanged from today; only the signing
and verifying algorithm moves from RSA to ML-DSA. The signing public key is looked up **live every
handshake and never cached** (so a key change takes effect immediately):

```
Alice → Bob   from:@alice
Bob   → Alice <random UUID challenge>              (existing behaviour, unchanged)
Alice:  sign(challenge) with ML-DSA-65 instead of RSA — a one-line algorithm swap; save the cookie
Alice → Bob   pol
Bob   → Alice lookup:pq_signing_publickey@alice    (live, never cached)
Bob:  AtPqc.mlDsa65.verifyBytes(challenge, signature, publicKey) instead of
      RSAPublicKey.verifySHA256Signature(...) — a one-line swap ⇒ isPolAuthenticated = true
```

There is **no** KEM, no ciphertext exchange, no shared-secret derivation, and no key-confirmation
tag — the UUID cookie the two swapped lines already sign is the whole freshness mechanism.
`AT_DISABLE_PQ_AUTH=true` forces the legacy UUID/RSA path; self-auth is always UUID; a peer that
publishes no PQ signing key falls back to UUID/RSA.

### 8.3 The published signing key (`pq_signing_publickey`)

At boot a server generates an **ML-DSA-65 keypair** (the signing keypair it already needed — the
X-Wing keypair is gone) and publishes the public half as a protected `pq_signing_publickey@<atSign>`
record. For **crypto agility** the record is a JSON object rather than a bare key, initially with a
single field naming the algorithm:

```json
{ "ml-dsa-65": "<base64 ML-DSA-65 public key>" }
```

so a future primitive is added as another field without a wire-shape change. The ML-DSA secret key
joins the protected-key set (delete/update verb protection). That is the entire key story — **no
certificate, no expiry, no rotation grace window, no confirmation-tag derivation**, so the heavy
`PqKeyManager` lifecycle class the earlier design carried collapses to boot-time keygen plus a
publish. There is no key-lifecycle state to manage because a signing key needs none here: a change
is a re-publish, picked up live on the next handshake.

### 8.4 at_chops dependency (no longer a gate)

IS-1 needs only what **published `at_chops` 3.4.x already ships**: `AtPqc.mlDsa65.signBytes` /
`verifyBytes` (the ML-DSA-65 sign/verify branch, [P-2](implementation-plan.md)) and
`generateMlDsa65KeyPair`. The previously-required unpublished surface — `XWingCert`,
`resolveXWing` / `resolveMlDsa65`, the `at_algorithm.dart` resolver exports on branch
`pq/st/at-chops-pq-api` — is **dropped with the X-Wing KEM**. There is now **no cross-package
publish gate** for this track: IS-1 can land against the published at_chops with no workspace path
override.

### 8.5 Threat scope

IS-1 hardens the **inter-server channel** only; it is independent of the client-side `nskey` data
path (Subsystem A) — a compromised server-to-server link and a compromised client-to-server link
are different threats with different anchors. The pure-Dart fallback (ML-DSA resolves without
libcrypto when `AT_CHOPS_LIBCRYPTO_PATH` is unset) keeps the track deployable on hosts without an
OpenSSL build.

## 9. Subsystem G — signature agility (the auth/signing key split)

Ruled in [`decisions.md` 91](decisions.md#91-signature-agility-the-apkam-auth-key-stops-being-the-enrollments-signing-key-2026-08-11).
This section is the detail that ruling is written against; the acceptance rows
are [`acceptance.md` 16](acceptance.md#16-g1--signature-agility-and-the-rollout-matrix).

### 9.1 The two roles

| Role | Key | Where the private lives | Where the public is advertised | Lifecycle |
|------|-----|--------------------------|--------------------------------|-----------|
| Authentication | APKAM keypair | `auth:<algo>:<n>`, `privateAuthentication` | the enrollment record's `apkamPublicKey` | one active ever; rotated in place by `enroll:update` |
| Signing | one keypair per algorithm | `sign:<algo>:<n>`, `privateSigning` | `_apsk`'s `keys` array | several active at once; grows and retires by policy |

⚠️ Neither id carries the enrollment. It is stated once by the `enrollments[]`
entry the keys sit in ([`decisions.md` 99](decisions.md#99-the-keyfile-groups-by-enrollment-and-the-atsigns-own-keys-move-out-2026-08-14)
ruling 5), so identity is `(enrollment, keyId)` and two enrollments may each
hold `auth:mldsa65:1`.

PKAM verification is record-authoritative, so the atServer reads
`apkamPublicKey` off the enrollment record and has no use for `_apsk` at all.
`_apsk` is a client-side artefact that the server merely stores and writes,
which is why its format can change without a server release.

### 9.2 The keyfile

`CryptographicKeyType` gains `privateAuthentication` and
`publicAuthentication`. `KeyAlgorithmType` is unchanged — the algorithm tokens
already cover what is needed.

`AtKeys.fileApkamMaterial` files under the generation-suffixed id and tags the
pair `privateAuthentication` / `publicAuthentication`. A new sibling files a
signing keypair under `sign:<algo>:<n>` as
`privateSigning` / `publicVerification`. The generation is per
`(role, algorithm)`: an enrollment moving between algorithms holds both at
generation 1.

Reading them back is `AtKeys.signingKeysFor(enrollmentId)`, which selects on
that **keyId shape** rather than on the `privateSigning` role. The role is not
unique to an enrollment's signing keys. The atSign-wide signing root is filed
under it too, with no enrollment id — it now lives in the document's own
`atsignKeys[]`, which `signingKeysFor` never reads, so the confusion the shape
filter was written for is structural rather than a matter of prefix parsing.
The filter stays because the role is still shared within an enrollment, and a
signature made with a key whose public half is in no `_apsk` verifies against
nothing. Both halves must be present and active; an
algorithm this build does not know is skipped rather than refused, because the
rest of a keyfile written by a newer client is still usable.

`AtKeysAssurance.validateKeyMaterials` and `.validateAddKey` gain a status
filter, and `.refuseSecondLiveEnrollment` carries the
single-active-authentication rule. With one live enrollment per install, a
second active authentication key is a keyfile this build will not write,
whatever algorithm it names.

✅ **The refusal is on the WRITE path only, since 2026-08-14** — [`decisions.md` 99](decisions.md#99-the-keyfile-groups-by-enrollment-and-the-atsigns-own-keys-move-out-2026-08-14)
ruling 2, built as 14.20 row A2. `AtKeys.addKey` calls it; the parse files
through a private path that applies the structural invariants and not this
one. A reader that refused a second entry would make the plurality
unenableable — the first build to emit two would break every build that
predates it, so no build could ever start — and the whole file is somebody's
key material to lose. The ambiguity surfaces instead at
`resolveAuthenticatingEnrollment()`, where a caller is asking for the one
answer that does not exist.

Until then this rule ran on the read path too, and was described here as "what
makes the enrollment id derivable" — which `AtKeys.activeEnrollmentId` no
longer is.

**What replaces it: the caller supplies the enrollment id, and `AtKeys` offers
a derivation the caller can ask for** —
[`decisions.md` 100](decisions.md#100-the-seven-shapes-ruling-99-left-open-2026-08-14)
ruling 1. `activeEnrollmentId` has no production caller, and both live
resolvers already pass an explicit id; a cold start with no id to pass calls
`resolveAuthenticatingEnrollment()`, which answers when exactly one enrollment
holds active authentication material and throws rather than picking when
several do. A null id keeps meaning the flat block.
(This paragraph read "what replaces its side effect is an OPEN QUESTION …
settle this before building row A2" until 2026-08-14; the top-level
`enrollmentId` is still explicitly **not** the answer — 99 ruling 7, it belongs
to the legacy block.)

`AtKeys.replaceKey(enrollmentId, keyId, replacements)` retires the named
keyId's materials and files the replacements in one call. Rotation is never two
caller-sequenced mutations across a flush. It takes the enrollment because
identity is `(enrollment, keyId)`; `retireAtSignKey` is the atSign-scope
sibling. `retireSigningKeys(enrollmentId, algorithm)` withdraws an
enrollment's signing keypair for one algorithm — the caller names the
algorithm because that is the unit a signing key leaves service in, and the
`sign:<algo>:<generation>` grammar is `AtKeys`'s own. (This read `replaceKey(keyId, newMaterial)` until the 2026-08-14
sweep — the signature gained its enrollment in row A1.)

Reading, in order of what a file can contain:

1. no `version` — the legacy flat shape;
2. `version: 1` with `keys: []` — written by at_auth ≥ 3.3.0 on any flush,
   carrying nothing a legacy file does not;
3. `version: 1` with `enrollments[]` and/or `atsignKeys[]`.

Writing emits (1) when there is no typed material and (3) otherwise. Shape (2)
is never written again — and a `version: 1` document carrying a top-level
`keys` is now **refused by name**: `keys` is no longer reserved, so parsing it
would sweep the whole array into `metadata` as a legacy value and authenticate
from the flat block as the wrong enrollment.

### 9.3 `_apsk`

```json
{
  "v": 1,
  "keys": [
    {"kid": "…", "use": "sign", "alg": "mldsa65", "pub": "…"},
    {"kid": "…", "use": "sign", "alg": "rsa2048", "pub": "…",
     "status": "retired"}
  ]
}
```

⚠️ **Corrected 2026-08-13: `kid` was missing from this example**, and it is
required — `apskSigningKeys` skips any entry lacking one, so the document as
previously shown is one every reader treats as empty and then refuses outright.
`apskAdvertisement` has always written it. The example also showed
`"status": "active"` on the live entry; the field is **omitted** when a key is
active, because absent already reads as active and stating the default would
change the bytes of every advertisement in the protocol.

`kid`, `use`, `alg`, `pub` and `status` are `PackageKey`'s spellings
(`packages/at_client/lib/src/secret_sharing/key_package.dart` — grep the class,
not a line number), deliberately, so the design has one vocabulary for a list of
keys with algorithms. `status` is the shared
[`KeyEntryStatus`](../../../packages/at_auth/lib/src/enroll/key_entry_status.dart),
which lives in at_auth so that all three advertising records name one type:
at_client depends on at_auth and not the reverse, which is the only direction a
shared type can travel, and `publicKeyKid` sits there for the same reason.
Absent reads as `active`; a value this build does not know reads as `retired`.

A reader accepts this and the released bare string (an `rsa2048` key published
by at_client **3.13.0**'s `mixins/apkam_signing.dart`). A writer emits only
this. A **`retired` entry is kept by the reader**, not skipped: this list is
what verifies stored envelopes, and a retired key is precisely what signed the
older ones. It is a caller *choosing a key to sign with* that must exclude
them.

The value is composed client-side and travels on `EnrollParams.apsk`. The
atServer stores it verbatim on the enrollment record, writes its JSON encoding
unaltered at approval, and rewrites it when `enroll:update` carries a new one.
Absent means no `_apsk` is published at all. Capped by the atServer at 20KB
encoded; a longer value is refused rather than truncated.

### 9.4 The envelope

**RFC 7515 general JSON serialization** — ruled by
[`decisions.md` 95](decisions.md#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12)
ruling 1, superseding the bespoke container in
[`decisions.md` 91](decisions.md#91-signature-agility-the-apkam-auth-key-stops-being-the-enrollments-signing-key-2026-08-11)
ruling 12.

```json
{
  "payload": "<base64url(JSON)>",
  "signatures": [
    {"protected": "<base64url({\"alg\":\"ML-DSA-65\",\"kid\":\"<enrollmentId>\",\"v\":1})>",
     "signature": "<base64url>"},
    {"protected": "<base64url({\"alg\":\"RS256\",\"kid\":\"<enrollmentId>\",\"v\":1})>",
     "signature": "<base64url>"}
  ]
}
```

Signing input per entry is `ASCII(protected || '.' || payload)`, all encodings
unpadded base64url. `alg` uses the **JOSE** names — `RS256`, and ML-DSA-65 per
RFC 9964 — not the `_apsk` array's `mldsa65`/`rsa2048` spelling; the two
vocabularies meet in one mapping function, as at_chops' `SigningAlgoType`
already meets the keyfile's.

There is no top-level `v` or `enrollmentId`: both live **inside** each
`protected` header, as `v` and `kid`, where the signature covers them. A
version or signer claim outside the signature is one an attacker can edit.

There is no legacy branch: **nothing released reads or writes an envelope** (no
release ships `lib/src/signing/`; at_client 3.14.0, the latest, has no such
directory). The bare-string `_apsk` is
the released thing in this area, and it is a *record*, not an envelope — see
[`decisions.md` 95](decisions.md#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12)
ruling 3.

Signing: one signature per active signing key the enrollment holds, so the
envelope carries exactly what `_apsk` advertises as `active`.

Verifying: resolve the signer's `_apsk`, intersect its entries with the
algorithms this at_chops build implements, take the strongest by the at_chops
order, and verify that one signature. If it fails, **refuse** — do not try a
weaker one. Falling through to whichever signature happens to verify hands the
choice of algorithm to whoever tampered with the envelope, and it would read as
success in every log.

One algorithm can name **several** advertised keys, and every one of them is
tried before the refusal. An enrollment that mints its own signing key keeps
advertising the APKAM authentication key it used to sign with, and for a
post-quantum-native enrollment both are ML-DSA — so a verifier that took the
first entry for the algorithm would refuse every envelope signed before the
split. This is not the fallback the paragraph above forbids: that one is about
dropping to a weaker *algorithm*, which is already fixed here, and each key
tried is one this signer published under it.

An envelope naming an algorithm with no matching `_apsk` entry is refused for
that reason specifically, which is the failure a rollout-2 sender produces
against a fleet that has not reached rollout 1.

### 9.5 `enroll:update`

Renamed from section 68's `enroll:updateMetadata` and widened. One alternation
entry in `syntax.dart`'s `enroll` pattern, as section 68.4 established for the
original name.

Reaches `apkamPublicKey`, `signingAlgo`, `apsk` and `metadata`. Never
`namespaces` or the approval state.

`EnrollParams` gains `apkamPublicKeySignature`: base64 of a signature by the
**new** private key over `enrollmentId|apkamPublicKey|signingAlgo`, verified by
the handler against the `apkamPublicKey` in the same request before anything is
written. A request changing `apkamPublicKey` without it is refused.

The signature is produced and verified with **`AtSigningMode.pkam`** and
`HashingAlgoType.sha256`. Not `AtSigningMode.data`, which signs with the
*encryption* keypair and therefore cannot express possession of an APKAM
signing key — the first implementation chose it and failed with "Encryption
keypair required for signing". `pkam` is also the mode PKAM verification uses,
so the two paths frame the bytes the same way.

Section 68's rulings 2 through 7 apply unchanged: self-only, approved-state
only, per-key set rather than whole-map replace, the server keeps no opinion of
metadata contents, superseded material is not retired, and an old atServer
fails loudly because an unknown operation does not match the verb regex.

An enrollment whose authentication private is **lost** cannot rekey — self-only
means the proof of the current key is the authority. That case remains "a new
enrollment", as it is today.

### 9.6 Algorithm policy

Three separate things, deliberately in three places:

| Thing | Where | Why there |
|-------|-------|-----------|
| Strength order | at_chops, beside `SigningAlgoType` | A protocol fact every implementation must agree on, including the atServer |
| Verifiable set | derived from what the at_chops build implements | A build cannot claim an algorithm it cannot run |
| In-use-for-signing set | `AtClientPreference.inUseSigningAlgorithms`, defaulted by `ReleasePosture` | A rollout decision, which is what posture carries |

The in-use set is a `Set<SigningAlgoType>`, final at construction and
unmodifiable, defaulting to `{}` under `ReleasePosture.migration()` and
`{mldsa65}` under `ReleasePosture.postQuantum()`. Empty is not "unsigned": an
enrollment with no signing key of its own signs with its APKAM authentication
key, and that is the key `_apsk` advertises for exactly as long as it is the
signer. ⚠️ **Amended 2026-08-14 by [`decisions.md` 98](decisions.md#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14)
ruling 2**, which this sentence used to contradict: it said the auth key
"~~stays published afterwards~~", i.e. was retained once the enrollment held
signing keys. It is not — a key is retained for what it *signed*, and an
enrollment holding signing keys held them from birth. Naming an algorithm this build
produces no envelope signature for is refused at construction rather than
skipped. The reasoning for each of those is in
[`decisions.md` 91.3](decisions.md#913-the-rulings) ruling 16.

Order: `SigningAlgoType.strongestFirst` — `mldsa65` > `rsa4096` > `ed25519` >
`ecc_secp256r1` > `rsa2048`, pinned by a raw-literal tripwire test in the style
of `KeyAlgorithmType`'s. It is **total**, covering every member: a partial
order leaves the choice undefined for exactly the pair nobody thought about,
and the pin fails on a new member left unplaced.

When the in-use set names an algorithm the enrollment holds no key for, the
client mints one at start, **publishes the updated advertisement, and then
files it**. A signing keypair can be minted unilaterally because it needs no
server approval and no enrollment-record change — which is the practical payoff
of the split.

This start-time mint is the **heal path**, not the primary producer: an
enrollment created by a current build already holds its signing key before it
is approved. What reaches it is an enrollment created before that, or a client
whose in-use set has changed since its last start. It is also the second writer
of `_apsk`, so it obeys the same bare-versus-array rule as the enrolment
request — a single active `rsa2048` key travels as the bare string, in
`apskLegacy`, and anything else as the array. One definition,
`bareApskValueOf`, answers that for both.

The order is the design, and it is the opposite of the nskey path's. File first
and the client signs with a key its `_apsk` does not name; envelopes are stored
durably, so every one written before the publish lands is permanently
unverifiable, and nothing retries, because the next start finds the key already
held and mints nothing. Publish first and the advertisement names a key nobody
holds — nothing signs with it, no envelope refers to it, and it disappears at
the next publish, since the advertisement is composed from what the keyfile
holds. An nskey private is filed before its public half is published for the
mirror-image reason: an encapsulation key published without its private has
senders sealing data nobody can open.

Which writer depends on whether there is an enrollment record. An enrolled
client sends `enroll:update`, because the atServer is the only writer of an
enrollment's `_apsk`; a client with no enrollment publishes the record itself,
under `primary`.

When an algorithm leaves the in-use set, signing with it stops; the key and its
`_apsk` entry are retained indefinitely as `retired`. The same start does both
halves, in one order that matters: publish the post-move advertisement, file
the new key, then file the withdrawal. The publish is **handed** the keys being
retired rather than re-reading them, because the keyfile still holds them as
active at that point and a re-read would drop them from the advertisement
altogether instead of moving them to `retired`. Filing the withdrawal first
would leave a moment with no active signing key, where the client falls back to
signing with its APKAM authentication key — which the advertisement has by then
stopped naming.

An **empty** in-use set retires nothing. It is the released posture rather than
"every algorithm has left the set": a client there goes on signing with the key
it holds and advertising it bare, which is what that posture publishes.

### 9.7 Rollout gate

One `ReleasePosture` axis switches all three writer behaviours together: mint
separate signing keys, publish the array, emit multi-signature envelopes. A
build doing any one without the others emits something the fleet cannot handle,
so they do not get independent flags.

⛔ **FALSE since [`decisions.md` 98](decisions.md#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14),
and built out on 2026-08-14 (rows B1 and B3).** ~~Rollout 1 is the reader half
only, and is not gated — a reader that understands more shapes is always
safe.~~ Rollout 1 is a **writer** position: the enrollment authenticates with
ML-DSA-65 and owns a fresh RSA-2048 signing key from before it submits, which
is what `_apsk` advertises. The reader half needing no gate is still true and
is why the *advertisement* stays the bare string an un-upgraded peer parses —
but the key it names changes, and the stage carries an atServer dependency
(ML-DSA PKAM) that `now` does not.

⚠️ This sentence survived the 2026-08-14 banner two paragraphs below, which
corrected the same claim in its other form. Corrected in the sweep that
followed.

**The axis is `SigningRollout`,** on `ReleasePosture.signingRollout` and
overridable per `AtClientPreference`. It names a position — `now`, `rollout1`,
`rollout2` — rather than the mechanism it switches.

It turned out the three behaviours are inseparable *by construction*, which is
stronger than the paragraph above asked for. Only the first is a decision: the
array form and the second signature are both consequences of the enrollment
holding a second key (`apskValueOf` emits the bare string only for a single
active `rsa2048` entry, and `wrapAndSign` signs with every key the keyfile
holds). So the stage does not switch three flags — it names the position, and
supplies the default for the one piece of state all three read,
`AtClientPreference.inUseSigningAlgorithms`. The posture derives that set from
the stage rather than storing both, because two stored fields are two controls
over one behaviour.

⛔ **FALSE since [`decisions.md` 98](decisions.md#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14)
(2026-08-14), and still what the code does because 98 is unbuilt.** Under 98,
rollout 1 mints an **ML-DSA-65 authentication** keypair and a fresh **RSA-2048
signing** keypair, and `_apsk` advertises the *signing* key — so rollout 1
writes something `now` does not, and carries an atServer dependency (ML-DSA
PKAM) that `now` does not. The paragraph below describes the superseded design:

~~`rollout1` writes exactly what `now` writes, deliberately.~~ What it carries is
the *fleet's* position — the peers' readers have upgraded — which no client can
observe for itself and which is the precondition for anyone moving to
`rollout2`. It is reachable only through `AtClientPreference`, since there are
two postures and no general constructor.
