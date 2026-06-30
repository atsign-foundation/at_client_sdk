# PQ crypto — D1 data encryption (the nskey data path)

**Status:** working planning doc (not plan-of-record). Lives in `docs/`.
**Source of truth** for how D1 encrypts application data. Decision recorded in
[ADR 0002](adr/0002-d1-single-tier-nskey.md); per-APKAM key conveyance in
[`pq-secret-push.md`](pq-secret-push.md); named-secret pull in
[`pq-atsign-key-distribution.md`](pq-atsign-key-distribution.md).

**Conventions.** Notation per `pq-use-case-catalogue.md`. Worked examples are
**Given / When / Then**. Key names are shown **complete** (`@<owner>` suffix). "Working
name" marks an at-key/provider name not yet finalised. `aS = pq` unless stated.

**Locked decisions (this doc encodes them):**
- **Two `nskey` KEM keypairs per `(atSign, namespace)`** — a **self nskey** (not published) and
  a **public nskey** (published). `nskey` is asymmetric (X-Wing); it is what you *encapsulate
  symmetric content keys to*, never what encrypts data.
- **Three D1 providers:** `legacy`, `at/nskey`, `at/symmetric/AES/GCM` (the `at/` prefix is the
  first-party namespace; app authors write their own providers under their own prefixes).
- **(a) Decoupled content keys.** A symmetric content key (CK) is conveyed **once** via
  `at/nskey`; application-data values reference it by `kid` and are encrypted under it with
  `at/symmetric/AES/GCM`. CKs are **not** embedded per data value.
- **(ii) Substrate is plumbing.** The per-APKAM conveyance of `nskey` **privates** (push +
  `enroll:listfornamespace`, pull backstop) is transport *beneath* the provider seam; the
  value-level `at/nskey` provider tags the **CK-conveyance records** that ride ordinary sync.
- **Self and cross-atSign use the identical flow**, differing only in *which* nskey the CK is
  sealed to. Forward secrecy is a coarse, opt-in rotation policy; cross-atSign FS is bilateral.

## Table of contents

- [1. The three layers](#1-the-three-layers)
- [2. Keys and key shapes](#2-keys-and-key-shapes)
- [3. The three providers](#3-the-three-providers)
- [4. The uniform data flow](#4-the-uniform-data-flow)
- [5. Worked examples (given / when / then)](#5-worked-examples-given--when--then)
  - [5.1 Self put](#51-self-put)
  - [5.2 Self read (second client)](#52-self-read-second-client)
  - [5.3 Cross-atSign put + read](#53-cross-atsign-put--read)
  - [5.4 CK rotation = coarse forward secrecy](#54-ck-rotation--coarse-forward-secrecy)
  - [5.5 Bootstrap: a new APKAM keypair joins (the substrate, beneath the seam)](#55-bootstrap-a-new-apkam-keypair-joins-the-substrate-beneath-the-seam)
- [6. Forward secrecy](#6-forward-secrecy)
- [7. Implementation notes](#7-implementation-notes)
- [8. Relationship to the rest of the design](#8-relationship-to-the-rest-of-the-design)

# 1. The three layers

D1 data encryption is three layers; the seam routes each stored value to a provider by its
`appMetadata.providerId`:

```
LAYER 3  application data     ── AES-256-GCM under a symmetric CK ──▶  provider at/symmetric/AES/GCM
LAYER 2  content key (CK)     ── X-Wing-sealed to an nskey ──────────▶  provider at/nskey   (a discrete, once-delivered conveyance record)
LAYER 1  nskey PRIVATE        ── X-Wing-sealed to an APKAM key package ▶  the secret-sharing substrate  (plumbing, beneath the seam — decision (ii))
```

- **Layer 3 (data)** is pure symmetric: a value carries its AES-256-GCM ciphertext and *references*
  a CK by `kid`. It never touches asymmetric crypto.
- **Layer 2 (CK conveyance)** is the `at/nskey` provider: the CK is X-Wing-encapsulated to an
  nskey and written **once** as its own record; every Layer-3 value under that CK just cites the
  `kid`. This is decision **(a)**.
- **Layer 1 (nskey bootstrap)** gets the nskey *private* into each authorised APKAM keypair's
  keystore. It uses the same X-Wing sealing but is delivered **per-APKAM** by the secret-sharing
  substrate (`__ssenv` push + `enroll:listfornamespace`, pull backstop) — **transport, not a
  value-level provider** (decision **(ii)**). Once a client holds the nskey private, it can
  unwrap any Layer-2 CK with one sync, O(1).

Layer 1 happens rarely (a client joins/upgrades); Layer 2 happens per CK (per epoch); Layer 3
happens per data write.

# 2. Keys and key shapes

Concrete, `@alice` owner, namespace `app_1.my_apps` (reads right-to-left, DNS-style). `K1…` =
APKAM keypairs, `kp1…` their key-package kids, `ck7…` content-key kids. Working names marked.

| Object | Shape | Published? | Who holds the private | Role |
|---|---|---|---|---|
| **self nskey** | `nskey.app_1.my_apps@alice` (public half) | no — **self at-key**, synced to Alice's `<ns>` clients | Alice's authorised clients (private conveyed via substrate) | Alice encapsulates **her own** CKs to it |
| **public nskey** | `public:nskey.app_1.my_apps@alice` (public half) | **yes**, world-readable | Alice's authorised clients | external senders encapsulate CKs to it |
| **CK conveyance** *(working)* | `<ckKid>.__ck.app_1.my_apps@alice` (self key) | no | n/a (it *is* a sealed CK) | `at/nskey` value: `X-Wing-seal(ck)` to an nskey |
| **data value** | `<key>.app_1.my_apps@alice` | no | n/a | `at/symmetric/AES/GCM`: AES-GCM under a CK, cites `ckKid` |
| **substrate envelope** *(working)* | `<msgId>.<kpid>.__ssenv.app_1.my_apps@alice` (self key) | no | n/a | Layer-1 plumbing: `pqSeal(nskey private)` to key package `kp` |
| **APKAM key package** | per-`pq-secret-push.md` | (enrollment record) | the APKAM keypair | recipient unit for Layer-1 |

Cross-atSign mirrors this with `@bob` as owner of the values he writes for Alice — e.g. the data
value `@alice:<key>.app_1.my_apps@bob` and the CK conveyance `@alice:<ckKid>.__ck.app_1.my_apps@bob`,
both sealed/encrypted to Alice's **published public nskey** and synced to Alice as cached
replicas. (This ownership is why cross-atSign FS is bilateral — section [6](#6-forward-secrecy).)

**Both nskey privates** for a namespace live in an authorised client's keystore: the self-nskey
private (unwraps Alice's own CKs) and the public-nskey private (unwraps CKs external senders sent
her). Both are KEM privates — they **decapsulate CKs**, they do not decrypt application data.

**Where the self-nskey *public* half comes from.** The self-nskey public half is the **self
at-key** `nskey.app_1.my_apps@alice` — an ordinary self key, synced to every one of Alice's
clients authorised for the namespace, exactly as any self key is. It is not a `public:`
(world-readable) key, because only Alice's own clients ever encapsulate to it. The **private**
half is the sensitive part: it cannot ride the RSA-tainted self-encryption-key chain, so it is
conveyed PQ-safely per-APKAM over the secret-sharing substrate. So a client gets the public by
ordinary sync and the private from the substrate — precisely mirroring the public nskey, whose
public half is the world-readable `public:nskey.app_1.my_apps@alice` and whose private is likewise
substrate-conveyed.

**Multi-namespace keying.** nskey privates are keyed by `(owner atSign, namespace)`; the CK cache
by `(owner, namespace, ckKid)` — never `ckKid` alone, since kids are not unique across namespaces.
A value in a namespace for which the client holds no nskey private is left **undecryptable**
(yielded as an error), not silently skipped — mirroring the `(owner, id)` identity discipline used
elsewhere in the SDK.

# 3. The three providers

| `providerId` | Tags a value that is… | Mechanism | Recipient (kid in metadata) |
|---|---|---|---|
| `legacy` | legacy data + inline-wrapped key (the model (a) replaces — modern data values never inline a key) | RSA-2048 + AES (monolithic) | RSA keypair. Bare name (pre-convention default; existing data already tagged this) |
| `at/nskey` | a **CK-conveyance record** (a sealed content key, cited by `kid`) | `X-Wing-seal` (the content key encapsulated to an nskey public) | the nskey the CK was sealed to — **self nskey** (Alice's own) or a recipient's **public nskey** |
| `at/symmetric/AES/GCM` | **application data** | AES-256-GCM under a CK | n/a (symmetric); the CK is cited by `kid` and resolved from cache (populated by the `at/nskey` provider when its conveyance record synced) |

Notes:
- `at/nskey` is the value-level provider you see on stored CK records. The **same X-Wing sealing**
  also conveys nskey *privates* in Layer 1, but those ride the secret-sharing substrate as
  transport and are **not** value-level `at/nskey` records (decision (ii)).
- `at/symmetric/AES/GCM` names the **algorithm** deliberately — that is the layer needing
  crypto-agility (a future `at/symmetric/AES/SIV` coexists; old values keep their tag). `at/nskey`
  names the **role** — the nskey system is stable; its KEM (X-Wing) is versioned by the key's kid,
  not the providerId.
- **Legacy interop.** A value with **no** `appMetadata.providerId` defaults to `legacy`
  (pre-convention data). `legacy`, `at/nskey`, and `at/symmetric/AES/GCM` values coexist within a
  namespace and the seam routes per value. A writer emits the nskey data path's providers once the namespace
  has an nskey (else cold-start, section [4](#4-the-uniform-data-flow)); legacy data is read in
  place and re-encrypted only if rewritten.

# 4. The uniform data flow

One pattern, **identical for self (Alice→self) and cross-atSign (Bob→Alice)** — only the target
nskey differs:

**Write** (sender = whoever owns the data):
1. Choose/cut a symmetric **CK** (cadence is the sender's policy).
2. **Convey the CK once** (`at/nskey`): `X-Wing-seal(CK)` to the recipient's nskey — Alice's
   **self** nskey when writing self data; the recipient's **public** nskey when writing to a peer
   — and write it as a `<ckKid>.__ck.<ns>@<owner>` record. (Skip if the CK is already conveyed.)
3. **Write data** (`at/symmetric/AES/GCM`): AES-256-GCM under the CK; stamp `ckKid` (+ iv) in
   `appMetadata`.

**Read** (recipient = an authorised client):
1. On syncing a `…__ck…` record, the `at/nskey` provider **decapsulates the CK** with the matching
   nskey private and caches it by `kid`.
2. On a data value, the `at/symmetric/AES/GCM` provider **resolves the CK by `ckKid`** (from cache)
   and AES-GCM-decrypts.

The CK private-half conveyance for *new clients* (Layer 1) is the substrate's job and happens out
of band (section [5.5](#55-bootstrap-a-new-apkam-keypair-joins-the-substrate-beneath-the-seam)).

**Resolution & ordering.** Sync is not ordered, so a Layer-3 data value can arrive **before** (or
without) its CK conveyance. On a `ckKid` cache miss the `at/symmetric/AES/GCM` reader (a)
decapsulates the local `<ckKid>.__ck.<ns>@<owner>` record on demand if it is present, else (b)
yields a `Stream.error` / deferred state and re-attempts when the conveyance syncs — mirroring
`getItemsAsStream`'s per-key decode-failure convention. A value whose CK was deleted for forward
secrecy stays undecryptable, by design.

**Cold-start — no namespace public nskey yet.** When a sender has no
`public:nskey.<ns>@<recipient>` to seal to (namespace uninitialised / first contact), it falls
back to encapsulating the **CK** to the recipient's atSign-level `public:pqpublickey@<recipient>`
(root) as a bootstrap recipient (`recipientKind: "root-pqpublickey"`). **Only the CK is sealed to
the root key — application data is never encrypted directly to it**, so the nskey-never-encrypts-
data invariant holds (`pqpublickey` is just another KEM target for the CK). Once the namespace
publishes its public nskey, new CKs target the nskey; the root-keyed conveyance is the transient
cold-start bridge. (This is the roadmap's cold-start fallback, expressed in the CK→nskey model.)

# 5. Worked examples (given / when / then)

Cast: `@alice` with clients on APKAM keypairs `K1` (this writer) and `K2` (another client), both
authorised for `app_1.my_apps` and holding both nskey privates. `@bob` likewise for his namespace.

## 5.1 Self put

- **Given:** Alice (`K1`) wants to store a private note in `app_1.my_apps`; no current CK yet.
- **When:** `K1` writes the note.
- **Then:**
  - `K1` cuts CK `ck7`, writes the conveyance once:
    `ck7.__ck.app_1.my_apps@alice` — value = `X-Wing-seal(ck7)` to the **self nskey**;
    `appMetadata = { providerId: "at/nskey", recipientKind: "self-nskey", ckKid: "ck7" }`.
  - `K1` writes the data: `note1.app_1.my_apps@alice` — value = `AES-256-GCM(note1)` under `ck7`;
    `appMetadata = { providerId: "at/symmetric/AES/GCM", ckKid: "ck7", iv: … }`.
  - The data value contains **no** sealed key — only the `ck7` reference (decision (a)).

## 5.2 Self read (second client)

- **Given:** `K2` is online, holds the self-nskey private, has not yet seen `ck7`.
- **When:** `K2` syncs `ck7.__ck…` and `note1`.
- **Then:**
  - `at/nskey` decapsulates `ck7` from the conveyance record with the self-nskey private; caches
    `ck7` by kid.
  - `at/symmetric/AES/GCM` resolves `ck7` by `ckKid` and AES-GCM-decrypts `note1`.
  - A later `note2.app_1.my_apps@alice` under `ck7` needs **no** new conveyance — `K2` already
    holds `ck7`.

## 5.3 Cross-atSign put + read

- **Given:** `@bob` (client `Kb`) shares data with `@alice` in `app_1.my_apps`; Bob holds Alice's
  published `public:nskey.app_1.my_apps@alice`.
- **When:** Bob writes a shared value, then Alice reads it.
- **Then:**
  - Bob cuts CK `ckB3`, conveys it once: `@alice:ckB3.__ck.app_1.my_apps@bob` — value =
    `X-Wing-seal(ckB3)` to **Alice's published public nskey**;
    `appMetadata = { providerId: "at/nskey", recipientKind: "public-nskey", ckKid: "ckB3" }`. (Owned
    by `@bob`; Alice gets a cached replica.)
  - Bob writes data `@alice:msg1.app_1.my_apps@bob` — `AES-256-GCM(msg1)` under `ckB3`;
    `providerId: "at/symmetric/AES/GCM", ckKid: "ckB3"`.
  - Alice's clients sync both; `at/nskey` decapsulates `ckB3` with the **public-nskey private**;
    `at/symmetric/AES/GCM` decrypts `msg1`. **Byte-identical structure to the self path** — only
    the nskey targeted (public vs self) and the value owner (`@bob` vs `@alice`) differ.

## 5.4 CK rotation = coarse forward secrecy

- **Given:** Alice wants to forward-secure her `app_1.my_apps` self data; current CK is `ck7`.
- **When:** Alice rotates the content key.
- **Then:**
  - `K1` cuts `ck8`, writes `ck8.__ck.app_1.my_apps@alice` (sealed to the self nskey); new data
    uses `ck8`. Conveying `ck8` is **O(1)** — one record, every client unwraps with the shared
    self-nskey private.
  - **For FS:** delete the `ck7.__ck…` conveyance record **and** every client evicts cached `ck7`.
    `ck7`-era data is now undecryptable — the nskey private cannot help, because no sealed `ck7`
    survives (decision (a) is what makes this possible: the CK was never embedded in the data
    values). Retaining `ck7` instead = history access, no FS. This is the per-namespace retention
    knob.
  - **Not** to be confused with rotating the **nskey keypair** — that is the heavier per-APKAM
    *revocation* lever (exclude a keypair from the successor nskey), not the routine FS lever.

## 5.5 Bootstrap: a new APKAM keypair joins (the substrate, beneath the seam)

- **Given:** Alice approves a new client on APKAM keypair `K3` (key package `kp3`) for
  `app_1.my_apps`; `K3` holds neither nskey private yet.
- **When:** `K3` is approved / comes online.
- **Then:**
  - The secret-sharing **substrate** conveys the namespace's nskey **privates** to `kp3`:
    `pqSeal(nskey privates)` written to `<msgId>.kp3.__ssenv.app_1.my_apps@alice` (per-APKAM, via
    approval-time push / `enroll:listfornamespace` / pull backstop). **This is Layer-1 plumbing —
    not an `at/nskey` value-level record** (decision (ii)).
  - Once `K3` holds the nskey privates, it reads all current and future CK conveyances (Layer 2,
    O(1) sync) and decrypts data (Layer 3) — no per-APKAM step per CK.

# 6. Forward secrecy

- **The FS lever is CK rotation** (section [5.4](#54-ck-rotation--coarse-forward-secrecy)): rotate
  the symmetric content key and **delete** the old CK's `at/nskey` conveyance record + evict it
  from client caches. Decision (a) is what enables this — because the CK is a discrete deletable
  artifact, not embedded in every data value.
- **It is coarse**, bounded by the **stable nskey private** remaining a standing decapsulation
  capability for any CK conveyance that *persists*. Deletion discipline is the FS trusted-computing
  base; rotation cadence sets the granularity.
- **CK-conveyance lifecycle (the retention knob).** Default: **retain** — `__ck` records are
  permanent (no ttl), so a late-joining APKAM keypair can read history (legacy-like; no FS).
  FS-mode: **delete** the `__ck` record, and clients **evict the cached CK when they observe that
  record's deletion via sync** — that is the eviction trigger that makes section
  [5.4](#54-ck-rotation--coarse-forward-secrecy)'s FS claim implementable. An offline /
  never-resynced client that retains a cached CK is the residual: coarse FS is bounded by eviction
  *reachability*, not only by record deletion.
- **Cross-atSign FS is bilateral.** For self data Alice is both endpoints — she cuts the CK, owns
  the authoritative conveyance + cache, so she forward-secures unilaterally. For inbound, Bob cuts
  the CK on **his** cadence and the authoritative conveyance is **owned by `@bob` on bob's
  atServer**; Alice holds only a cached replica keyed to her stable public-nskey private. Alice can
  purge her cache but cannot delete Bob's authoritative copy — so closing inbound FS depends on
  Bob's cooperation (or the heavier public-nskey **keypair** rotation lever — the per-APKAM
  revocation lever of section [5.4](#54-ck-rotation--coarse-forward-secrecy), distinct from CK
  rotation). This is normal for any FS system
  (FS across two parties is bilateral), not an nskey deficiency.
- **What's out of scope (D2):** robust/per-message FS via ratcheted leaves (no standing master
  key), O(log n) large-group scale, and groups whose membership is decoupled from namespace
  authorisation. See ADR 0002.

# 7. Implementation notes

**`appMetadata` encoding.**
- On an `at/nskey` CK-conveyance record:
  `{ providerId: "at/nskey", recipientKind: "self-nskey" | "public-nskey" | "root-pqpublickey", ckKid }`.
  The record's `@<owner>` + key name identify *whose* nskey the CK was sealed to; `recipientKind`
  selects *which* of that owner's keys — and hence which private the reader decapsulates with. The
  `<ckKid>` in the key name equals `appMetadata.ckKid`.
- On an `at/symmetric/AES/GCM` data value:
  `{ providerId: "at/symmetric/AES/GCM", ckKid, iv }`. `iv` is the base64 12-byte GCM nonce, per
  value. No sealed key is present (decision (a)).
- **`ckKid`** is the content key's id — a SHA-256 prefix of the CK (deterministic; dedupes
  identical keys) or a random id. It must be unique within `(owner, namespace)` and is the CK
  cache key alongside them.

**Key discovery.** A sender obtains a recipient's `public:nskey.<ns>@<recipient>` via an ordinary
public-key `plookup`, and re-fetches on a decapsulation-failure / rotation signal (the recipient
may have rotated the public-nskey keypair). The self nskey is never looked up — Alice's clients
hold it from the substrate (section [5.5](#55-bootstrap-a-new-apkam-keypair-joins-the-substrate-beneath-the-seam)).

# 8. Relationship to the rest of the design

- **Decision:** [ADR 0002](adr/0002-d1-single-tier-nskey.md) — D1 is single-tier `nskey`; this doc
  is its data-encryption realisation.
- **Layer 1 conveyance:** [`pq-secret-push.md`](pq-secret-push.md) (proactive per-APKAM push +
  `enroll:listfornamespace`) and [`pq-atsign-key-distribution.md`](pq-atsign-key-distribution.md)
  (the `requestSecret` pull backstop) deliver the nskey privates that make Layer 2 work.
- **Supersedes the framing in:** `crypto-roadmap.md` ("encrypt to the namespace keypair"),
  `pq-flows-detailed.md` / `pq-use-case-catalogue.md` (the one-keypair legends and
  `providerId ∈ {legacy, nskey, group}`). That follow-up sweep has been applied;
  `crypto_impl_plan.md` task B2 now implements this model — a decoupled content key (the
  `<ckKid>.__ck` record cited by `ckKid`), not an inline per-value `env` envelope. This doc remains
  **authoritative** for D1 data encryption.
