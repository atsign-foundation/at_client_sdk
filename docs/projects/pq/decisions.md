# Key decisions & timeline — D1 nskey data path

**Status:** decision record (binding). The WHY + decision-timeline lane for the
D1 post-quantum work.
**Scope:** the governing ADRs (0001 superseded, 0002 accepted), the ratified
OQ1–OQ9 working-design table, the resolved/open execution decisions #A–#F, the
verb-wire-shape and 1:1:1 cardinality rulings, and a dated decision log.
**Companions (each in its own lane — this doc cross-references, never restates):**
`roadmap.md` (the high-level WHY/WHAT and phase trajectory),
`implementation-plan.md` (the project sequence + dependency graph),
`design.md` (per-subsystem mechanics with file:line),
`acceptance.md` (the given/when/then UC catalogue).

## Table of contents

- [0. Scope & how to read this doc](#0-scope--how-to-read-this-doc)
- [1. ADR 0001 — D1 as two tiers (SUPERSEDED)](#1-adr-0001--d1-as-two-tiers-superseded)
- [2. ADR 0002 — D1 is single-tier nskey; at/pqmls is D2 (ACCEPTED)](#2-adr-0002--d1-is-single-tier-nskey-atpqmls-is-d2-accepted)
- [3. The OQ1–9 ratified design-decisions table](#3-the-oq19-ratified-design-decisions-table)
- [4. The verb-wire-shape & 1:1:1 cardinality rulings](#4-the-verb-wire-shape--111-cardinality-rulings)
- [5. Retrofit ruling — fresh, self-spawned, auto-approved enrollment](#5-retrofit-ruling--fresh-self-spawned-auto-approved-enrollment)
- [6. Resolved & open execution decisions (#A–#F)](#6-resolved--open-execution-decisions-af)
- [7. Decision log / timeline (dated)](#7-decision-log--timeline-dated)
- [8. Stale-source reconciliation note](#8-stale-source-reconciliation-note)
- [9. APKAM keypair as key package: considered and rejected (2026-06-30)](#9-apkam-keypair-as-key-package-considered-and-rejected-2026-06-30)
- [10. nskey derivation from a shared master seed: rejected (2026-06-30)](#10-nskey-derivation-from-a-shared-master-seed-rejected-2026-06-30)
- [11. Single nskey per namespace, lazily published (2026-06-30)](#11-single-nskey-per-namespace-lazily-published-2026-06-30) — *publication superseded by [13](#13-the-nskey-is-published-eagerly-mutable-and-generation-addressed-2026-08-02)*
- [12. Advertised recipient keys are signed against `_apsk` (2026-07-02)](#12-advertised-recipient-keys-are-signed-against-_apsk-2026-07-02)
- [13. The nskey is published eagerly, mutable, and generation-addressed (2026-08-02)](#13-the-nskey-is-published-eagerly-mutable-and-generation-addressed-2026-08-02)
- [14. Content keys are scoped per recipient (2026-08-02)](#14-content-keys-are-scoped-per-recipient-2026-08-02)
- [15. The record owner and the nskey owner are different atSigns (2026-08-02)](#15-the-record-owner-and-the-nskey-owner-are-different-atsigns-2026-08-02)
- [16. A provider id names every algorithm a reader needs code for (2026-08-02)](#16-a-provider-id-names-every-algorithm-a-reader-needs-code-for-2026-08-02)
- [17. The sync push dropped `appMetadata` (2026-08-02, fixed)](#17-the-sync-push-dropped-appmetadata-2026-08-02-fixed)
- [18. `pqpublickey` becomes the user-owned signing root (2026-08-03)](#18-pqpublickey-becomes-the-user-owned-signing-root-2026-08-03) — *supersedes the KEM role in [design.md](design.md) section 1.4*
- [19. Nested namespaces: the nskey is resolved by walking up (2026-08-03)](#19-nested-namespaces-the-nskey-is-resolved-by-walking-up-2026-08-03) — *adds `appMetadata.ns` / `ckNs`; supersedes the no-`ns` statement in [design.md](design.md) section 1.5*

---

## 0. Scope & how to read this doc

This is the **decision-and-timeline** lane of the D1 doc set. It records *why*
each choice was made and *when*, not *how* the mechanism works or *which project*
ships it. Concretely it holds: (a) the two ADRs — 0001 (superseded) folded in as
history, 0002 (accepted) as the governing ruling; (b) the ratified OQ1–OQ9
working-design table; (c) the resolved/open execution decisions #A–#F; (d) the
verb-wire-shape and 1:1:1 cardinality rulings; and (e) a dated decision log.

The **current model**, stated up front so nothing below is read against the older
framing:

- **D1 is single-tier `nskey`** ([ADR 0002](#2-adr-0002--d1-is-single-tier-nskey-atpqmls-is-d2-accepted)).
  The forward-secure `at/pqmls` group model is **D2**, not a D1 tier.
- **Enrollment cardinality is 1:1:1** — `enrollmentId ↔ APKAM keypair ↔ key
  package`, never more than one keypair per enrollment ([decision #F](#6-resolved--open-execution-decisions-af),
  2026-06-30).
- **Retrofit is a fresh, self-spawned, auto-approved enrollment** — not a
  mutation of the existing one ([section 5](#5-retrofit-ruling--fresh-self-spawned-auto-approved-enrollment)).
- **One `nskey` keypair per (atSign, namespace)** — lazily published; the former
  self/public nskey pair is collapsed to one ([section 11](#11-single-nskey-per-namespace-lazily-published-2026-06-30),
  2026-06-30).

**Lane boundaries (do not restate here):**

| Topic | Lives in |
|---|---|
| High-level WHY/WHAT, conceptual nskey shape, phase trajectory M0–M6 | `roadmap.md` |
| Project sequence (P-1…D2-1, SS-*, RF-*), dependency graph, waves, effort, publish gates, critical path | `implementation-plan.md` |
| Per-subsystem mechanics (key shapes, `__ssenv`, `enroll:listns`, the enrollment record, providers) with file:line | `design.md` |
| The given/when/then UC catalogue (A1.x–A5.x, B0.x–B5.x) | `acceptance.md` |

This doc does **not** restate concrete key shapes, project lists, or tests — it
cross-references those docs by filename.

---

## 1. ADR 0001 — D1 as two tiers (SUPERSEDED)

> **Superseded by [ADR 0002](#2-adr-0002--d1-is-single-tier-nskey-atpqmls-is-d2-accepted).**
> Retained for history. The "no forward secrecy", "copyable shared key vs
> non-copyable per-device key — you cannot have both", and two-tier claims below
> are **history-only**; ADR 0002 dissolved them (see [section 2](#2-adr-0002--d1-is-single-tier-nskey-atpqmls-is-d2-accepted)).

- **Status:** Superseded by ADR 0002 (2026-06-25) — was Accepted (2026-06-20).
- **Source:** `adr/0001-d1-simplicity-tiers.md` (folded into this doc 2026-06-30; the standalone ADR file was deleted in the consolidation).

**The original decision.** Deliver D1 in **two tiers** over the M0 pluggable
`CryptoProvider` seam (the seam itself is in `design.md`):

- **D1 Tier1 — `nskey` (default).** A per-`(atSign, namespace)` X-Wing keypair
  replacing the atSign-wide RSA key, `selfEncryptionKey`, and `shared_key.*`.
  Enrollment-granular and **copyable**, distributed at enrollment approval, so a
  future client reads instantly/offline with full history (byte-for-byte legacy
  semantics, now PQ-safe and namespace-scoped). No `SecureGroup`/`KeyPackage`/
  single-owner lock in the app's face. Rotation opt-in, doubling as the
  revocation primitive.
- **D1 Tier2 — `group` (opt-in).** The per-APKAM group provider, declared by a
  namespace needing per-device revocation or forward secrecy. Also the substrate
  D2/MLS swaps its engine into.

**The premise it rested on (since dissolved).** Two claims drove the split:

- *"Instant, offline access for a future device fundamentally requires a*
  ***copyable shared key***. *Non-copyable per-device keys force re-encryption to
  each new device. You cannot have both."*
- *Forward secrecy and per-device revocation* **require** *the group (MLS-style)
  model.*

Making per-APKAM groups mandatory for all of D1 would therefore tax every app
with identity/membership machinery and regress "future device just works".

**Alternatives it rejected** (still valid as rejections):

| Alternative | Why rejected |
|---|---|
| Per-APKAM groups mandatory for all of D1 (the prior framing) | Taxes every app, regresses instant future-client access, over-buys per-device security for the common case. |
| Server-stored per-APKAM leaf secrets (to recover convenience) | Makes cloning the default, opens a PQ harvest-now-decrypt-later hole, couples key/data blast radii. |
| Keep one atSign-wide PQ keypair (simplest) | Leaves the crypto-broader-than-transport weakness (a `chess`-only enrollment would hold `banking` keys). Per-namespace is the minimum scope that mirrors enrollment authorization. |

The *live* reasoning that replaced this is [section 2](#2-adr-0002--d1-is-single-tier-nskey-atpqmls-is-d2-accepted).

---

## 2. ADR 0002 — D1 is single-tier nskey; at/pqmls is D2 (ACCEPTED)

- **Status:** **Accepted (2026-06-25). Supersedes [ADR 0001](#1-adr-0001--d1-as-two-tiers-superseded).**
- **Source:** `adr/0002-d1-single-tier-nskey.md` (folded into this doc 2026-06-30; the standalone ADR file was deleted in the consolidation).

This is the governing ADR for the shape of D1.

**The context that dissolved 0001's premise.** Two decisions taken since 0001
turned its two-tier rationale into a false dichotomy:

- **Per-APKAM delivery + push** (the `enroll:listns` verb): a secret is
  delivered to every authorised APKAM keypair, definitively and proactively. A
  *future* device gets the key **pushed** to it — instant, offline — regardless
  of tier. So "future device just works" no longer argues for a
  copyable-shared-key tier.
- **`nskey` is a KEM wrapper, not the data key.** Data is encrypted under a
  symmetric content/epoch key (CK); the CK is X-Wing-encapsulated to an `nskey`.
  *Neither* model encrypts data per-device — both use symmetric data keys
  delivered per-APKAM. So 0001's "copyable shared key vs per-device keys" was a
  **false dichotomy**.

With those corrected, `nskey` already gives D1 **coarse forward secrecy** (CK
rotation) and **post-compromise security** (nskey-keypair rotation). The genuine
`at/pqmls`/MLS delta — robust/per-message FS, O(log n) scale, and membership
decoupled from namespace authorisation — is entirely D2. **There is no
D1-internal Tier-1/Tier-2 boundary left.**

**The corrected key model** (stated explicitly so it is not re-derived wrongly;
the concrete at-key strings live in `design.md`):

- **`nskey` is an asymmetric X-Wing KEM keypair** — the thing we *encapsulate
  symmetric keys to*, not the thing that encrypts data. Per namespace there are
  **two**:
  - a **self nskey** — *not published*; Alice encapsulates her *own* content keys
    to it. It **is a self at-key**, `nskey.<ns>@alice`: the public half is synced
    to Alice's clients that have `<ns>` access (it is *not* a `public:` key), and
    its **private half is conveyed as a Secret over the substrate** ([section 4](#4-the-verb-wire-shape--111-cardinality-rulings)).
  - a **public nskey** — *published world-readable*, `public:nskey.<ns>@alice`;
    external senders encapsulate content keys to it. Alice's authorised clients
    hold its private.
  Both convey symmetric CKs; neither encrypts application data directly.

> **Revised 2026-06-30 (see [section 11](#11-single-nskey-per-namespace-lazily-published-2026-06-30)):** collapsed to ONE X-Wing `nskey` keypair per (atSign, namespace), lazily published (owner-only self at-key → `public:` on first cross-atSign share). The two-nskey text below is retained as ADR history — the single-nskey model governs.

- **Data is encrypted under a symmetric content/epoch key (CK)** with
  AES-256-GCM. The CK is X-Wing-encapsulated to an `nskey`; holders of the nskey
  private unwrap the CK.
- **Two delivery levels, very different costs** (this difference *is* the FS
  lever):
  - *Convey the nskey private* to each authorised APKAM keypair — **per-APKAM,
    O(n), rare** (the push + `enroll:listns` substrate; pull as
    backstop).
  - *Rotate the symmetric CK* — wrap the new CK **once** to the shared nskey;
    every authorised client unwraps with the shared private — **O(1),
    frequent.**

**The decision.** **D1 ships as a single tier: `nskey`.** Forward secrecy is **in
scope for D1 as a *policy*, not a tier**:

- **Coarse FS = rotate + delete the symmetric content/epoch keys** over the
  stable nskey KEMs. Routine rotation is cheap (O(1) wrap to the shared nskey).
  FS strength is **coarse** and bounded by the stable shared nskey private
  remaining a standing decryption capability for any wrapped-CK that persists —
  so **deletion discipline is the FS TCB**.
- **Per-APKAM future-data revocation = rotate excluding the revoked keypair**
  (the expensive lever: a fresh nskey conveyed per-APKAM, since the shared-nskey
  O(1) path can't exclude a holder of that private).

**`at/pqmls` is D2, not a D1 tier.** Ratcheted per-APKAM leaves (no standing
master key → robust/per-message FS), TreeKEM (O(log n) churn), and groups whose
membership is decoupled from namespace authorisation are the MLS engine's job.
The **same per-APKAM secret-sharing substrate** underpins both `nskey` (now) and
MLS (later); only the labelling changes — what 0001 called "D1 Tier 2" is **D2's
first increment**.

**Consequences.**

- *Positive.* One D1 data path — the `nskey` data path (`at/nskey` conveys the
  CK, `at/symmetric/AES/GCM` encrypts the data) — plus `legacy`; no `SecureGroup`/
  `KeyPackage`/membership commits/single-owner lock in the app's face for D1.
  Legacy developer experience preserved (a future device "just works" via push;
  PQ + namespace scoping + per-namespace blast radius by default). FS is
  *available* in D1 (coarse, cheap) rather than withheld to D2 — a strict
  improvement over legacy's none, for namespaces that opt into rotation.
- *Negative / accepted.* D1 FS is **coarse** and rests on deletion discipline
  over **all** CK conveyances (self and inbound alike) plus the stable shared
  nskey private being a standing capability. Robust/per-message FS, large-group
  O(log n) scale, and decoupled-membership groups require D2.
- *Inbound (cross-atSign) FS is structurally identical to self but only
  achievable **bilaterally**.* Inbound uses the same flow as self: the sender
  (`@bob`) cuts a CK, delivers it once as a discrete `at/nskey` conveyance
  (encapsulated to Alice's published public nskey), and writes data under
  `at/symmetric/AES/GCM` by kid — there is no per-message inline-wrapped CK that
  "persists with the message". The residual bilaterality: (1) the inbound CK is
  cut by `@bob` on **his** cadence, so Alice cannot force an FS cut finer than the
  sender's rotation; (2) the authoritative `at/nskey` conveyance lives in a record
  **owned by `@bob` on bob's atServer** — Alice holds only a synced cached
  replica, so she can purge her cache but **cannot unilaterally delete bob's
  copy**, which her stable published-nskey private re-decapsulates. For **self**,
  Alice is both endpoints, so FS is unilateral and complete. (This bilaterality
  is normal for any FS system, not specific to nskey.)

**Alternatives rejected.**

| Alternative | Why rejected |
|---|---|
| Keep the two D1 tiers (ADR 0001) | The distinguishing property (FS) is a rotation *policy* of the single `nskey` data path, not a separate provider; the only genuine delta (fine FS, scale, decoupled membership) is D2. Two D1 tiers split on the wrong axis. |
| Withhold forward secrecy entirely to D2 | `nskey` gives coarse FS cheaply (O(1) epoch-key rotation); no reason to deny D1 a strict improvement over legacy. |
| The 0001 "copyable shared key vs per-device keys" framing | False dichotomy: data is encrypted under symmetric keys delivered per-APKAM; there are no per-device data keys, and a future device is served by push, so instant/offline access and per-APKAM revocation coexist. |

**Cross-refs:** the conceptual two-layer nskey shape and mixed-scheme philosophy
are in `roadmap.md`; the 3-layer/3-provider mechanics, concrete key shapes, and
the forward-secrecy/rotation levers are in `design.md`; the A5.x
rotation/revocation tests are in `acceptance.md`.

---

## 3. The OQ1–9 ratified design-decisions table

The binding working-design record, pulled from the WP-SS rework audit (ratified
**2026-06-25**) so it lives in the tracked corpus. OQ4 and OQ7 are **RATIFIED**;
the rest were recommended answers adopted as the working design. On **2026-06-30**,
the 1:1:1 ruling ([decision #F](#6-resolved--open-execution-decisions-af))
revised OQ2/OQ3 and the verb wire shape and added OQ8/OQ9. The table below is the
**current** form — it absorbs the 1:1:1 ruling, the wire-shape flattening, and
the `enroll:metadata` removal directly, and does **not** restate the retired
multi-APKAM forms.

| # | Question | Decision |
|---|---|---|
| OQ1 | `to`/`toKpid` vs `kid` on the envelope redundant? | Keep `toKpid` as the routing token + a `sealKid` for which advertised key was sealed to (crypto-agility if a KeyPackage advertises >1 enc key); they coincide today. Collapse to one only if multi-enc-key KeyPackages are ruled out. |
| OQ2 | Cardinality of enrollment ↔ APKAM keypair ↔ key package? | **RATIFIED 1:1:1.** Exactly one APKAM keypair + one key package per `enrollmentId`; never >1 keypair per enrollment. The record stores a **single** `apkamPublicKey` + a `signingAlgo` (`rsa2048` \| `mldsa65`) so PKAM verify selects RSA vs ML-DSA for that one key; multi-keypair verify-against-any is removed. (Supersedes the original OQ2 "multiple APKAM keypairs per enrollment" premise, which is moot once an enrollment holds exactly one keypair.) |
| OQ3 | How does a client learn its own `kpid` + X-Wing private at runtime? | Generate **one** X-Wing keypair per enrollment/keyfile at enrollment, stored in the keyfile alongside the APKAM keypair; `kpid = computeKid(pub)`. Each cloned pre-PQ keyfile retrofits to its **own distinct enrollmentId** (per-keyfile == per-enrollment under 1:1:1). |
| OQ4 | Key package generated at enrollment-**request** time or lazily? | **RATIFIED: request time** — public half in the record the approver reads (no-verb approve). *(The constraint behind D1 decision #B → Option A.)* |
| OQ5 | `putIfNewer` ordering source — explicit version int or kid-in-name? | Explicit monotonic `version` orders rotations of the same logical secret; the kid identifies the key generation (different kid ≠ "newer"); `createdAt` is a tiebreak only. |
| OQ6 | Facade Expando keyed on `AtClient` or `(AtClient, enrollmentId)`? | `(AtClient, enrollmentId)` — identity is the enrollment's APKAM keypair, not the process. |
| OQ7 | Barrel: hard-break the replaced names or `@Deprecated` shims? | **RATIFIED: hard break** — WP-SS is pre-publication (not on trunk, not published), so the consumer sweep is clean; no shims. |
| OQ8 | Legacy-enrollment retirement mechanism? | **RATIFIED 2026-06-30: enrollment-expiry timer + `enroll:revoke`.** There is **no per-APKAM-key delete** (a record holds one key). A self-retrofit creates a fresh **auto-approved** enrollment (authenticated `enroll:request`, requester-subset namespaces, expiry copied from the authenticating enrollment); the OLD enrollment is **capped** to `min(now + grace, its expiry)` and ages out — not deleted-by-key, not revoked-with-teardown. Sibling clones may still retrofit until the cap elapses. |
| OQ9 | Post-enrollment metadata writes? | **RATIFIED 2026-06-30: NONE.** The `enroll:metadata` verb is **removed**; the key package rides `EnrollParams.metadata` (opaque map) on `enroll:request`, and the server stores/returns it. No post-approval metadata round-trip ever. |

**Cross-refs:** the substrate mechanics each OQ rides (kpid addressing, the
`__ssenv` envelope, `SecretStore`, the `enroll:listns` verb,
`EnrollParams.metadata`, the enrollment record) are in `design.md`; *which*
projects implement each (SS-1a/b/c, SS-3, RF-SRV) is in
`implementation-plan.md`.

---

## 4. The verb-wire-shape & 1:1:1 cardinality rulings

The authoritative wire-and-cardinality ruling, dated **2026-06-30**
([decision #F](#6-resolved--open-execution-decisions-af)). This section is the
rewrite target for the stale multi-APKAM sources ([section 8](#8-stale-source-reconciliation-note)).

**Cardinality is 1:1:1.** `enrollmentId ↔ APKAM keypair ↔ key package`, **never
more than one keypair per enrollment.** The enrollment record stores a **single**
`apkamPublicKey` + a `signingAlgo` (`rsa2048` | `mldsa65`). PKAM verify selects
RSA vs ML-DSA from the **record's** `signingAlgo` — **record-authoritative**, not
the client-supplied wire value (`_validateSignature` must read the *stored* algo,
not `verbParams[atPkamSigningAlgo]`; legacy null → `rsa2048`).

**Verb wire shape** (ratified 2026-06-25; flattened 2026-06-30 for 1:1:1):

- The key package rides an **opaque `Map<String,dynamic>` `EnrollParams.metadata`**
  carried on `enroll:request` (JSON tail; **no grammar change**). **The
  `enroll:metadata` verb is removed.** The server stores it on the enrollment
  record and returns it verbatim, with **no opinion** on the contents. The
  enrollment's single key package lives at a **singular `metadata.keyPackage`**
  (1:1:1 — **no format-keyed `keyPackages` map**; suite/schema agility lives
  *inside* the package via `keys[].alg` + `KeyPackage.v`). Its value is the
  **APKAM-signed envelope** wrapping the key-package payload (see the
  advertised-key-signing ruling in [section 6](#6-resolved--open-execution-decisions-af)).
  **No post-enrollment metadata write ever.**
- Because cardinality is 1:1:1, the discovery response is **flat** — no nested
  `apkam[]` array:
  `enroll:listns:<ns>` → `[{enrollmentId, access, apkamPubKey, metadata}]`,
  gated `≥r`. The receiver decodes the one `metadata.keyPackage` and verifies its
  APKAM signature against the enrolling atSign's `_apsk` before trusting it.

**ML-DSA APKAM auth is retained** — at_chops `mldsa65` verify branch + at_commons
pkam `signingAlgo` literal + server `_getSigningAlgoType` branch reading the
**record's** `signingAlgo`.

**Where `appMetadata` is mentioned:** it carried **no `ns` field** — a ruling
[section 19](#19-nested-namespaces-the-nskey-is-resolved-by-walking-up-2026-08-03)
reversed on 2026-08-03, once it turned out the namespace it was supposed to be
redundant with cannot be recovered from the wire string. (Full field definitions are
in `design.md`.)

**Cross-refs:** the `enroll:listns` verb mechanics,
`EnrollParams.metadata`, and the enrollment record + authenticated self-retrofit
flow + expiry copy/cap are in `design.md`; the projects (SS-1a/b/c, SS-3, RF-SRV,
RF-2b/c) are in `implementation-plan.md`; the A2.x discovery, A3.x, and retrofit
B-tests are in `acceptance.md`.

**Retires (see [section 8](#8-stale-source-reconciliation-note)):** "multiple
APKAM keypairs per enrollment" / verify-against-any / `ApkamPublicKey`-list
(crypto_impl_plan D1-F, wp-ss P9/P12, pq-secret-push); per-APKAM-key delete
(legacy retirement is the enrollment-expiry timer + `enroll:revoke`); the nested
`apkam[]` array (now flat); the `enroll:metadata` verb (now `EnrollParams.metadata`).

---

## 5. Retrofit ruling — fresh, self-spawned, auto-approved enrollment

Decision #F, 2026-06-30. **Retrofit is NOT a mutation of the existing
enrollment** — it is a **fresh, self-spawned, auto-approved enrollment.**

**The flow.** An authenticated pre-PQ client submits `enroll:request` with a
**new `enrollmentId`** on its already-authenticated connection
(`authType==apkam`, **no OTP**, not CRAM, not legacy PKAM). The server:

1. validates the requested namespaces are a **subset** of the authenticating
   enrollment's (reject escalation);
2. **auto-approves** — modelled on the CRAM approved-state mechanics but
   **without** the `__manage` + `*`:rw grant;
3. **copies** the old enrollment's expiry (or `null` = never) to the new one;
4. **caps** the old enrollment to `min(now + server-config grace, its existing
   expiry)` **without removing it** (sibling clones may still retrofit until the
   cap elapses).

Each cloned pre-PQ keyfile retrofits to its **own distinct `enrollmentId`**
(per-keyfile == per-enrollment under 1:1:1).

**Why a fresh auto-approved enrollment, not a mutation.**

- A *pending* enrollment cannot authenticate, so a key package **cannot be
  written post-hoc**. The `enroll:request` payload is the only pre-approval
  channel — this is exactly what forces [decision #B → Option A](#6-resolved--open-execution-decisions-af).
- Under 1:1:1 there is **no "second keypair under the enrollment"** and **no
  delete-after-ML-DSA-verifies ordering**. The old enrollment simply ages out via
  the expiry cap (or an explicit `enroll:revoke`). The legacy **encryption** key
  is kept for reads.

**Cross-refs:** the authenticated self-retrofit flow + expiry copy/cap and the
at_chops ML-DSA mint are in `design.md`; the projects (RF-SRV server half, RF-2b
mint+request, RF-2c orchestration + readiness flip) are in
`implementation-plan.md`; the retrofit e2e is in `acceptance.md`.

**Rewrite target (see [section 8](#8-stale-source-reconciliation-note)):** the
crypto-roadmap "Upgrading an existing client — the sequence" (step 4 "delete the
legacy RSA APKAM public key after step 3 confirms PQ auth"), the
"mint a SECOND keypair under the enrollment" / "atServer allows multiple APKAM
keypairs per enrollment with auth against any" / "deletion of a specific public
key" / "TTL/usage-based eviction" notes, and the wp-ss P12c "8-step upgrade +
delete legacy RSA key after ML-DSA verifies" are **stale** — superseded by the
fresh-auto-approved-enrollment model above.

---

## 6. Resolved & open execution decisions (#A–#F)

The execution-decision ledger. This section is the authoritative execution-decision ledger; the
WP-SS Open decisions 1–4 are folded in where they overlap.

### Numbered rulings (#1–#4)

The four numbered rulings referenced across the UC catalogue and project sequence,
formalised here as binding entries (they already existed as scattered asides and
timeline rows).

- **Decision #1 — legacy-peer interop is opt-in.** A new PQ-native atSign onboards
  PQ-only by default: no RSA `public:publickey` is published. A `legacy-interop`
  config flag (default OFF) publishes the RSA pubkey so legacy peers can send
  inbound. (Drives ON-1, UC-B4.2.)
- **Decision #2 — PQ-readiness is marked per `(atSign, namespace)`.** The
  capability marker and the readiness flip are scoped to a namespace of an atSign,
  not the whole atSign; scheme selection is per-destination. (Drives R-1, UC-B3.2.)
- **Decision #3 — PQ-APKAM keyfile storage: copyable AtKeys file by default
  (2026-06-24).** The PQ APKAM signing keypair + X-Wing key-package private are
  stored in the copyable `.atKeys` file by default (portable, dev/test-clean — a
  reused keyfile does not re-mint); OS-keychain / hardware storage is opt-in
  hardening (off by default). Revocation is per-keyfile-key; the atServer prunes
  keys unused for N days via TTL/usage eviction. A labelled per-APKAM record
  (hostname / install-UUID) drives a per-APKAM revocation UI (an administration
  aid, not a security boundary). (Drives UC-B1.2, RF-2b.)
- **Decision #4 — convergence is push-at-approve + pull backstop.** Steady-state
  secret delivery is `pushSecretToNamespaceMembers` at mint/rotation and
  `shareAllSecretsWithEnrollment` at approve time; `requestSecret` (pull) is the
  correctness backstop for a client that missed a push. Push and pull are dual
  facets of one substrate. (Drives UC-A2.x, UC-B5.1.)

### Resolved

- **#B — `register()` call-site / key-package conveyance — RESOLVED 2026-06-30:
  Option A.** The new enrollment's X-Wing key package rides into `enroll:request`
  as an **opaque blob** built by an at_client orchestrator *above* at_auth
  (at_auth ferries it, **never interprets** it); the atServer stores it on the
  enrollment record and returns it, so the approver reads it at approve time —
  satisfying OQ4 with no dependency cycle. This is *forced* by the timing fact
  that a pending enrollment cannot authenticate, so the key package cannot be
  written via a post-approval verb; the `enroll:request` payload is the only
  pre-approval channel.
  **`approvedNamespaces`:** add the field to `EnrollmentRequestDecision.approved`
  (self-describing) and have an at_client approve-wrapper fire
  `shareAllSecretsWithEnrollment(enrollmentId, approvedNamespaces)` after
  at_auth's `approve` returns.
  **1:1:1 refinement (2026-06-30):** the `enroll:metadata` verb is **removed
  entirely** — the key package rides `EnrollParams.metadata` on `enroll:request`,
  and there is **no** post-enrollment metadata write (retrofit = a fresh
  auto-approved enrollment, not a mutation; see #F). Cost: a new typed field on
  `EnrollParams`/`EnrollVerbBuilder` (+ regen), the `Enrollment` read model gains
  the field, and an atServer schema change (separate `at_server`/`java_at_server`
  repos) to store/return it — must land in the same release or OQ4 isn't met.
- **#F — Enrollment cardinality + retrofit shape — RESOLVED 2026-06-30: 1:1:1,
  fresh-enrollment retrofit.** The master ruling above (sections [4](#4-the-verb-wire-shape--111-cardinality-rulings)
  and [5](#5-retrofit-ruling--fresh-self-spawned-auto-approved-enrollment)).
  `enrollmentId ↔ APKAM keypair ↔ key package` is **1:1:1** (never >1 keypair per
  enrollment) — this **retires the prior "multiple APKAM keypairs per enrollment"
  (DEP3) decision.** Retrofit = a fresh, self-spawned, auto-approved enrollment on
  the pre-PQ-authenticated connection (RF-SRV), inheriting the old enrollment's
  expiry; the old enrollment is capped to `min(now + grace, old expiry)` and ages
  out — never deleted-by-key. **Cascade:** `enroll:metadata` verb **removed** (→
  `EnrollParams.metadata`); `listns` **flattened**
  (`[{enrollmentId, access, apkamPubKey, metadata}]`, no `apkam[]`); DEP3/P9
  multi-APKAM list + verify-against-any **removed** (single `apkamPublicKey` +
  `signingAlgo`); per-APKAM-key delete (RF-2a/P12b) **removed**. ML-DSA APKAM auth
  and `enroll:listns` are otherwise unchanged.

### Open / standing

- **#A — signing-root interface freeze (P-3 vs SS-4).** ~~P-3 publishes/prefers
  `pqpublickey` in Wave 2~~ — withdrawn by
  [section 18](#18-pqpublickey-becomes-the-user-owned-signing-root-2026-08-03): there is
  no atSign-level KEM key for P-3 to prefer, and enrollment conveyance seals to the
  enrollee's key package instead. What survives is the freeze itself, now over
  `public:pq_signing_root@<atSign>`: its **name + create-once contract** ahead of SS-4's
  create/seed/serve/pull lifecycle. (Lifecycle mechanics → `design.md`; project
  gating → `implementation-plan.md`.)
- **#C — keep D1 GA off the auth retrofit (B-2 dep).** B-2 needs RF-2 only for the
  per-APKAM revocation/exclude fan-out — satisfy that with **RF-1 + SS-3**, not
  the full RF-2c upgrade orchestration, or D1 GA waits on the retrofit
  (contradicting the design). Confirm B6's fan-out is satisfiable from RF-1+SS-3
  alone.
- **#D — inherited WP-SS decisions** (the WP-SS Open decisions 1–4, folded here):
  (1) fold the pkam ML-DSA literal into SS-1a's at_commons publish — **one publish,
  not two**; (3) keep ML-DSA verify **algo-level** (P-2), revisiting the async
  `AtChops.verify` path only if a high-level caller needs it; (4) re-confirm the
  at_commons version floor at SS-1a (pub.dev / last release tag is authoritative,
  not in-tree precedent); plus the at_auth version question in S-1 — **resolved
  2026-07-17: 3.1.1 published, 3.2.0 taken by the network-timeout release, S-1
  ships as 3.3.0** (see the 2026-07-17 rulings). (The WP-SS "where does
  `register()` get called?" decision is resolved by #B above.)
- **#E — S-2 scope / SoT conflict.** `crypto_impl_plan` §3-S5 ("migrate legacy to
  `context.keys`") vs §7-WP3 ("legacy unchanged for now") conflict. This plan
  takes the **additive-field-only** reading — add `CryptoContext.keys` but do not
  migrate `LegacyCryptoProvider` to read from it (legacy pulls remote `plookup`s +
  `atChops` cipher ops that the field's static keys can't supply). (The
  `CryptoContext.keys` seam → `design.md`.)

**Cross-refs:** the open-decisions pointer and which project each decision gates
are in `implementation-plan.md`; the `pqpublickey` lifecycle and the
`CryptoContext.keys` seam (#E) are in `design.md`.

### Rulings — 2026-07-02

Execution rulings from the plan-vs-code review (post-review); each is binding.

- **Verb name: `enroll:listns`.** The gated enrollment-discovery verb's wire token
  is `enroll:listns` (superseding the `listfornamespace` working name), matching the
  in-flight at_commons (PR #2040) and at_server (PR #2685) work. The Dart client
  method stays `listForNamespace`.
- **D1 surface scope.** IN D1: `.atKeys`-at-rest protection (encrypt the PQ private
  material in the keyfile; define backup/restore incl. the stale-backup-after-retrofit
  case) — sequenced as KF-1. NON-GOALS for D1: the TLS session to the
  atServer/atDirectory (post-D1 the payload is already E2E PQ-safe; residual
  exposure is verb-level metadata the atServer sees anyway) and the atDirectory
  itself (holds no ciphertext). Both may be revisited separately; neither gates D1.
- **Readiness flip: operator-primary at GA, auto-detect fast-follow.** R-1 ships
  operator-declared readiness as the primary lever (a recorded usability-bar
  exemption: it is a one-time migration action, not a steady-state per-use task).
  Auto-detect is a scheduled fast-follow with pinned criteria: readiness auto-flips
  for an `(atSign, namespace)` when no legacy-client PKAM authentication has been
  observed on any of that atSign's namespace-authorised enrollments for a configured
  window (default N days), read from the atServer's APKAM auth records; the operator
  can always flip manually.
- **R-2 ecosystem-floor gate.** The floor is the set of downstream packages that
  must have shipped a PQ-reading release before at_client 4.0 flips
  `disallowLegacyEncryption` to true: `at_onboarding_cli`, `at_client_flutter`,
  `at_cli_commons`, the NoPorts clients (`sshnoports`), and `at_talk`. The concrete
  floor VERSION for each is pinned at R-2 execution time against pub.dev / release
  tags (not now); the observable signal is that each has published a release that
  reads `nskey`-path values.
- **Crypto backend policy: FFI auto-resolve default.** Where a native crypto
  library is present, at_chops' `AtPqc` auto-resolver selects the FFI backend as
  the default (faster on mobile/desktop); the pure-Dart backend is the fallback and
  the forced choice under WASM. PRs #2030 (`at_chops_ffi` barrel + auto-resolver)
  and #2039 (AES-GCM FFI) are IN D1 scope on the at_chops 3.4.0 slot alongside P-2.
  **Status (2026-07-20): closed.** #2030 merged to trunk 2026-07-03 (+ #2046
  review-fixes), opening the at_chops 3.4.0 slot; #2039 merged 2026-07-09 and P-2's
  `mldsa65` verify branch (#2056) merged 2026-07-06, both folded into that same slot
  rather than a fresh minor; **at_chops 3.4.0 published 2026-07-17**. (Scope note → the 2026-07-03 rulings below: auto-resolve
  applies to the `AtPqc` accessors; key generation through the web-safe barrel's
  key pair classes is pure-Dart by construction.)
- **`_apsk` is a pinned cross-tier property — present and write-restricted.** Envelope
  sender-authentication and advertised-key authenticity (below) both depend on the
  enrollment's `_apsk` published signing key. The atServer (1) **keeps `_apsk` present**,
  populating `public:_apsk.<enrollmentId>.<perEnrollmentApproved>@<atSign>` from the
  enrollment record's `apkamPublicKey` rather than relying on the client-side
  `ApkamSigning.publishPublicSigningKey` (removes a race + a missing-key failure mode),
  and (2) **restricts writes** to that key to the owning enrollment's own authenticated
  connection. Recorded in design.md §2.4 and the atServer DEP list; e2e tests (an
  approved enrollment's `_apsk` is fetchable without a client publish; a cross-enrollment
  overwrite is refused) are required before WP-SS ships.
- **Advertised recipient keys are signed against `_apsk` — the full ruling is
  [section 12](#12-advertised-recipient-keys-are-signed-against-_apsk-2026-07-02).**
  Every advertised recipient/encapsulation key (the per-enrollment key package and the
  published `nskey` public half — the signing root is not one, per
  [section 18](#18-pqpublickey-becomes-the-user-owned-signing-root-2026-08-03))
  is APKAM-signed by its generating enrollment and verified against that enrollment's `_apsk` — the same
  way same-atSign and cross-atSign — superseding the "atServer vouches" stance. The
  atServer keeps `_apsk` present **and** write-restricted. See section 12 for the
  mechanism, the self-describing signature, the trust model, and the SS-1b/1c/2/4
  implementation split.

### Rulings — 2026-07-03 (PR #2030 review)

Rulings from the two-pass review of PR #2030 (`at_chops_ffi` barrel + `AtPqc`);
each is binding. The code-side alignment landed via #2046 (merged 2026-07-03 into
#2030's `st/at_chops_ffi` branch, then folded to trunk when #2030 merged).

- **`AtPqc` supersedes the `PqcFfi` working name.** The auto-resolver ships as
  `abstract final class AtPqc`, exported from `at_chops_ffi.dart`; the PR's
  public API, README, CHANGELOG, and tests all use `AtPqc`, and `PqcFfi` appears
  nowhere in code. All doc mentions are updated in place (same supersession
  pattern as `enroll:listns` over `listfornamespace`).
- **`AtSignatureAlgorithm` recorded; `AtSigningAlgorithm` deprecation is staged,
  not immediate.** at_chops 3.4.0 adds `AtSignatureAlgorithm` — a stateless
  signing interface (`generateKeyPair`/`signBytes`/`verifyBytes`; `message` is
  positional, key material is required-named so same-typed byte arguments cannot
  be silently transposed). `AtSigningAlgorithm` is `@Deprecated` + `@sealed`
  (package:meta — no new external subtypes) but **stays implemented** by
  `MlDsa65PureDartAlgo`/`MlDsa65FfiAlgo` and every existing signing algo:
  P-2's `_getVerificationAlgorithm` branch and the section-12
  `wrapAndSign`/`AtSigningMode.pkam` machinery are typed against it, so P-2 and
  SS-1c/SS-2/SS-4 proceed exactly as specified. Its removal is deferred to a
  future at_chops major that is **not** in the D1 release ladder and requires a
  successor ruling for the `wrapAndSign` path first.
- **at_chops 3.4.0 semver exemption (one-time).** The coordinated 3.4.0 slot
  stays a **minor** despite three technically-breaking changes to the 3.3.0
  surface: (1) the FFI algorithm exports move from `at_chops.dart` to the new
  `at_chops_ffi.dart` — required for the web-safe main barrel; no shim can keep
  a `dart:ffi` export web-safe; (2) `AtKemAlgorithm` gains an abstract seedless
  `generateKeyPair()`; (3) the ML-DSA-65 signing methods become instance methods
  with named key-material parameters. Rationale mirrors OQ7's: 3.3.0 published
  2026-06-23, the affected surface is days old, and the consumer sweep (this
  workspace, sibling repos, pub-cache) found no external users. Every break is
  declared under a `breaking:` label in the CHANGELOG. This exemption does not
  set precedent — post-3.4.0 the surface is treated as stable and breaking
  changes require a major.
- **Conformance coverage for the FFI PRs.** #2030 and #2039 are covered under
  P-2's coordinated 3.4.0 slot for the purposes of implementation-plan §10(e):
  their PR descriptions cite "P-2 (coordinated 3.4.0 slot)"; no separate project
  id is minted.
- **Auto-resolve scope: accessors, not keygen helpers.** The FFI-auto-resolve
  default applies to the `AtPqc` accessors (`AtPqc.xWing`, `AtPqc.mlDsa65`),
  including their `generateKeyPair()`. Key generation through the web-safe
  barrel's key pair classes (`XWingKeyPair.generate`, `MlDsa65KeyPair.generate`,
  `AtChopsUtil.generate*KeyPair`) is **pure-Dart by construction** — those
  exports must stay out of the `dart:ffi` import graph or `dart compile js`/wasm
  breaks for web consumers. Both backends stay wire-compatible (pinned by
  cross-backend interop tests), so keys generated pure-Dart are usable by the
  FFI backends and vice versa.

### Rulings — 2026-07-06 (planning day)

- **AtKeys: extend in place, deprecate legacy — supersedes the `WritableAtKeys`
  holder** ([#2045](https://github.com/atsign-foundation/at_client_sdk/issues/2045)).
  Keep the existing `AtKeys` class hierarchy **as-is** and extend it
  **additively** with PQ-safe methods; **deprecate** the legacy key
  fields/methods (they stay for back-compat, so call sites migrate to the
  PQ-safe methods over time). `AtKeysIo` is extended with **runtime
  persistence** (`append()`, `save()`, … — method names superseded 2026-07-17
  by the single `flush()`) and remains the single contact point
  that keeps runtime `AtKeys` objects and the persisted keyfile in-line.
  Providers are injected **(`AtClient`, `AtKeysIo`, `AtChops`)**. There is
  **no** new `WritableAtKeys` holder class and **no** separate `WrittenAtKeysIo`
  widening — `AtKeysIo` itself is widened. *Rationale:* much simpler migration —
  the code contract stays the same (deprecated fields/methods remain), the
  deprecation path is clear-cut, and the churn is far smaller than carving a new
  holder hierarchy. *Affects:* **S-1** (reframed from "new `WritableAtKeys`
  holder" to "extend `AtKeys`/`AtKeysIo` in place"), **S-2**, **S-3**, and
  design §4. *Open question (not decided):* whether `AtClient` needs any concept
  of `AtKeys` outside the provider seam at all (encrypt/decrypt and auth already
  reach keys via the injected `AtKeysIo`).

### Rulings — 2026-07-17 (PR #2047 / S-1 conformance review)

Five rulings from the review of PR #2047 (the S-1 implementation) against this
record:

- **`flush()` supersedes the `append()`/`save()` working names.** `AtKeysIo`'s
  runtime persistence is one whole-state operation: mutate the in-memory
  `AtKeys` (`addKey`, `retireKey`, …), then `flush(atsign, atKeys)`. On an
  existing target the flush is safety-checked by
  `AtKeysAssurance.validateMapUpdate` (nothing lost; statuses forward-only;
  additions fine) and is atomic (write-to-temp + rename) with the previous
  state kept as `<file>.bak`. The default implementation throws
  (compile-compat for pre-existing implementers; there are no runtime callers
  of the new surface yet).
- **Retire, never remove.** `AtKeys` has no key-removal operation:
  `retireKey(keyId, {to})` moves status forward-only
  (`active` → `retired` → `dead`) and material bytes are never deleted —
  retired bytes are still needed to decrypt data they protected. Consistent
  with OQ8's no-per-APKAM-key-delete ruling. (Supersedes the
  `add`/`remove`/`write` working names in design §4 and S-1's
  "add→read→remove" acceptance line.)
- **The never-lose contract is scoped to bootstrap key stores.**
  `WrittenAtKeysIo.flush`'s nothing-may-be-lost contract applies to stores of
  bootstrap key material (the `.atKeys` file, keychain). It is **not** an
  `AtKeysIo`-wide invariant: a store holding rotating/evictable material
  defines its own retention — CK-class deletion is the B5a coarse-FS lever
  (design §1.7), a feature, not data loss. Corollary: **`LocalKeystoreAtKeysIo`
  is not needed at this time** — nskey-private / CK-class storage routing is
  decided when S-3/SS-4 execute, and whatever store holds CK-class material
  must support eviction rather than inherit the flush contract.
- **`keyPartType` / `keyAlgorithmType` are open String tokens, not enums.**
  Enums make every unknown value a whole-file parse failure, forcing lockstep
  reader upgrades and breaking flush's round-trip-what-you-don't-understand
  requirement. Known tokens live as static consts: `KeyAlgorithmType`
  (`aes256`, `rsa2048`, `ecc_secp256r1`, `ed25519`, `x25519`, `mlkem768`,
  `mldsa65`, `xwing` — parameter set in the token, matching the
  pkam/enrollment `signingAlgo` literals) and `CryptographicKeyType`
  (mechanical roles only: symmetric encryption/authentication and the
  public/private halves of encryption, verification/signing,
  encapsulation/decapsulation, key agreement). The classical/post-quantum/
  hybrid axis is a property of the algorithm token (X-Wing material is
  `xwing` + encapsulation/decapsulation), never a second role axis.
  `KeyPartStatus` stays an enum (a closed state machine the format owns).
  Unknown tokens are accepted, held, and re-emitted byte-identical.
- **S-1 ships as at_auth 3.3.0.** The 3.2.0 slot was consumed by the
  validateAtServer network-timeout release (published from trunk 2026-07-17),
  resolving Open decision #D's at_auth version question: 3.1.1 published
  first, then 3.2.0 (timeouts), and the `AtKeys`/`AtKeysIo` extension opens
  3.3.0. S-5's breaking cut is unchanged (3.x → 4.0.0).

---

## 7. Decision log / timeline (dated)

Chronological, **oldest-first**. Each entry gives the one-line *why*.

| Date | Decision / event | Why |
|---|---|---|
| **2026-06-17** | **Known shape-risk assessment.** Cardinality and the connection model flagged as the hardest open shapes. | Surface the risks before committing to a key/connection design — they drove the eventual 1:1:1 ruling. |
| **2026-06-20** | **ADR 0001 Accepted — two tiers** (`nskey` default + `group` opt-in). Structural target / component-responsibilities for the crypto layer settled. | Preserve the legacy developer experience while adding PQ; confine per-device machinery to an opt-in tier. *(Superseded 5 days later.)* |
| **2026-06-22** | **Wave-0 baseline landed (merged to trunk).** #1930 — the M0 pluggable-crypto seam (`at_client`); #1993 — `pqSeal`/`pqOpen` HPKE primitive on at_chops in-tree **3.3.0**; PR #2035 — design fixes. | The seam routes put/get/notify/sync by `appMetadata.providerId`; `pqSeal`/`pqOpen` give X-Wing + HKDF + AES-256-GCM. Everything downstream pins these. (Wave-0 detail → `implementation-plan.md`.) |
| **2026-06-24** | **Keyfile-storage decision (Decision #3).** PQ-APKAM material stored in the copyable `.atKeys` file by default; OS-keychain/hardware opt-in; revocation per-keyfile-key; server TTL/usage eviction. | Portability + dev/test-clean reuse; hardware storage is opt-in hardening, not the default. |
| **2026-06-25** | **ADR 0002 Accepted — single-tier `nskey` supersedes 0001.** WP-SS rework audit ratified (OQ1–OQ7). Verb wire shape ratified. | Per-APKAM push + the KEM-wrapper realisation dissolved 0001's two claims (the false dichotomy); the only genuine MLS delta is D2. FS becomes a rotation *policy*, not a tier. |
| **2026-06-30** | **Decision #F ratified — 1:1:1 + fresh-enrollment retrofit.** Decision #B resolved (Option A). OQ2/OQ3 revised, OQ8/OQ9 added. `listns` flattened. `enroll:metadata` verb removed (→ `EnrollParams.metadata`). Per-APKAM-key delete removed. The d1-execution-plan revision folded a 15-delta workflow (verified against the live `at_server`/at_commons/at_client trees). | One keypair per enrollment removes verify-against-any, the multi-key record reshape, and the delete-after-ML-DSA ordering; retrofit becomes a clean fresh auto-approved enrollment that ages the old one out. Simpler, smaller blast radius, no escalation path. |
| **2026-06-30** | **APKAM keypair ≠ key package — kept two keypairs per enrollment.** Considered collapsing the enrollment's ML-DSA APKAM keypair and X-Wing key package into one (and single-seed derivation of the pair); both rejected. | ML-DSA (signature) and X-Wing (KEM) are distinct PQ primitives — one keypair can't both sign/auth and be encapsulated to. Two keypairs is the floor; single-seed derivation saves only keyfile bytes and adds a re-derivation-stability risk. See [9](#9-apkam-keypair-as-key-package-considered-and-rejected-2026-06-30). |
| **2026-06-30** | **Shared-master-seed nskey derivation rejected; the `design.md` §1.3 derivation paragraph was removed.** nskey privates are minted as fresh random keypairs and conveyed per-APKAM over the substrate — never HKDF-derived from a shared seed. | A seed shared across an atSign's enrollments (required for the whole atSign to share one nskey per namespace) breaks post-compromise security, namespace compartmentalization, and rotation forward-secrecy; the namespace/epoch HKDF labels are public and don't gate who can derive. A full-corpus sweep confirmed this was the only insecure derivation. See [10](#10-nskey-derivation-from-a-shared-master-seed-rejected-2026-06-30). |
| **2026-06-30** | **Single nskey per namespace, lazily published — collapses the former self/public nskey pair.** One X-Wing keypair serves both self data and inbound shares; the public half is published lazily (owner-only self at-key → `public:` on first cross-atSign use). | Peer review: the two nskeys did the same KEM job with the same private-holders, so the split bought no real compartmentalization or authenticity, and one key simplifies the read path and rotation. Lazy publication preserves namespace-existence privacy for self-only namespaces. See [11](#11-single-nskey-per-namespace-lazily-published-2026-06-30) — the one-keypair half stands; **lazy publication superseded 2026-08-02** by [13](#13-the-nskey-is-published-eagerly-mutable-and-generation-addressed-2026-08-02). |
| **2026-07-02** | **Six execution rulings** (post-review): verb name `enroll:listns`; D1 surface scope (`.atKeys`-at-rest IN via KF-1; TLS + atDirectory non-goals); readiness operator-primary + auto-detect fast-follow; R-2 ecosystem-floor package set named; FFI auto-resolve default; `_apsk` write-restriction pinned + e2e-test-required. | Landed from the plan-vs-code review that found in-flight PRs implementing superseded rulings; the rulings + a conformance gate keep execution aligned to the record. |
| **2026-07-02** | **Advertised-key signing + `_apsk` always-present** ([section 12](#12-advertised-recipient-keys-are-signed-against-_apsk-2026-07-02)). Advertised recipient keys (key package, `nskey` public, `pqpublickey`) are APKAM-signed by the generating enrollment and verified against its `_apsk` — same path same-atSign and cross-atSign; the atServer keeps `_apsk` present (populated from the record) as well as write-restricted. Supersedes "atServer vouches". Also: the key package is a **singular signed `metadata.keyPackage`** (no format-keyed map). | Authenticates the encapsulation target against a rogue *insider* enrollment under an honest server (not server-asserted); reuses the existing `wrapAndSign`/`_apsk` machinery. Does **not** remove a malicious atServer *operator* from the TCB — the operator is the `_apsk` anchor (see section 12 + design.md *Trust boundary*). The format-map was redundant with in-package `keys[].alg` + `v` agility. |

| **2026-07-03** | **PR #2030 review rulings** (five, → [section 6](#6-resolved--open-execution-decisions-af)): `AtPqc` supersedes the `PqcFfi` working name; `AtSignatureAlgorithm` recorded with a **staged** `AtSigningAlgorithm` deprecation (stays implemented through D1 — P-2 and the section-12 `wrapAndSign` path are typed against it; removal deferred past the D1 ladder); at_chops 3.4.0 stays a minor under a recorded one-time semver exemption for the barrel-split breaks; #2030/#2039 conformance-covered under P-2's coordinated slot; auto-resolve scoped to the `AtPqc` accessors (web-safe-barrel keygen is pure-Dart by construction). | The two-pass review of #2030 found the PR shipping designs the record didn't yet name (`AtPqc`, `AtSignatureAlgorithm`) and removals the ladder didn't authorize; these rulings plus the stacked review-fixes PR align code and record. |
| **2026-07-06** | **Planning-day reconciliation rulings** (two): (1) **inter-server PQ authentication is IN D1 scope** as new project **IS-1** ([implementation-plan.md §13](implementation-plan.md)) — the atServer FROM/POL X-Wing+ML-DSA-65 handshake (PR #2683), off the D1 GA critical path, gated on publishing the at_chops PQ-API surface (`XWingCert`/`resolveXWing`/`resolveMlDsa65`). (2) **P-2's `mldsa65` verify branch folds into the existing unpublished at_chops 3.4.0** (bumped on trunk by #2030) before it publishes — not a fresh minor. | Planning-day reconciliation of #1889 vs the plan vs merged/open PRs across at_client_sdk + at_server surfaced a whole untracked inter-server workstream and an at_chops 3.4.0 slot already opened on trunk; these two rulings place both in the record. |
| **2026-07-06** | **P-2 satisfied on trunk** — the `mldsa65` `_getVerificationAlgorithm` branch merged (issue #2050 / PR #2056), folded into the unpublished at_chops 3.4.x slot per the ruling above; #2039 (AES-GCM FFI) merged into the same slot. | The one missing ML-DSA verify branch is now in the tree; P-2's residual is the 3.4.x publish itself. |
| **2026-07-17** | **PR #2047 / S-1 conformance rulings** (five, → [section 6](#6-resolved--open-execution-decisions-af)): `flush()` supersedes `append()`/`save()`; retire-never-remove (`retireKey`, forward-only status); the never-lose flush contract scoped to bootstrap stores (`LocalKeystoreAtKeysIo` not needed at this time; CK-class stores must support eviction for B5a); `keyPartType`/`keyAlgorithmType` as open String tokens with known-token consts (X-Wing = `xwing` + encapsulation/decapsulation); S-1 ships as at_auth **3.3.0** (3.2.0 consumed by the network-timeout release). | The S-1 implementation review found the built shape better than the recorded working names in three places and a version-slot collision; these rulings align the record with the code before at_auth 3.3.0 publishes. |
| **2026-07-17** | **Release train published:** `at_commons 5.13.0`, `at_chops 3.4.0`, `at_client 3.13.0` then `3.14.0`, `at_auth 3.3.0-rc1`, `at_lookup 3.6.0`, `at_onboarding_cli 1.16.0`. Same day, **SS-0 merged** (#2037) and **S-2 completed** (#2076, `AtKeysIo` threaded through `CryptoContext`). | Closes P-2's 3.4.x publish residual and the at_chops prerequisite for both S-1 and IS-1; `at_client 3.14.0` now carries the SS-0 substrate as an experimental surface, moving the D1 GA version slot off 3.14.x. |
| **2026-07-20** | **Planning-day reconciliation** (#1889 vs the doc set vs merged/open PRs and branches). Recorded: SS-0, SS-1b, S-1 and S-2 are **satisfied**; P-2 is fully closed by the 3.4.0 publish; `SS-1c` is the next actionable critical-path project. Issues cut for the previously-untracked substrate tail — SS-1c [#2084](https://github.com/atsign-foundation/at_client_sdk/issues/2084), SS-2 [#2085](https://github.com/atsign-foundation/at_client_sdk/issues/2085), SS-3 [#2086](https://github.com/atsign-foundation/at_client_sdk/issues/2086), SS-4 [#2087](https://github.com/atsign-foundation/at_client_sdk/issues/2087) — and **two merged-but-unpublished residuals recorded as open gates**: the at_auth rc1 → stable 3.3.0 promotion (blocking S-6 and SS-2), and S-2's `CryptoContext.keys` (#2076), which merged at 18:20Z on 2026-07-17 — after `at_client 3.14.0` published at 16:02Z — so it awaits the next at_client release. IS-1 (at_server #2683) restated as in progress and off the critical path. | #2008 had been closed on the SS-0 merge, leaving `SS-1c → SS-2 → SS-3 → SS-4` — the whole run-up to the D1 GA gate — with no tracking issue; and the 2026-07-17 release train had closed several publish gates the docs still carried as open. |
| **2026-07-21** | **Client PKAM auth is a signature swap only (guardrail + the under-specified client piece named).** PKAM PQ-safety = sign the server-issued per-connection `from:` challenge with ML-DSA-65 instead of RSA (`PkamSigningAlgo` → ML-DSA in at_lookup, selected off the stored `signingAlgo`), verified record-authoritatively server-side. **No KEM, no certificate, no per-connection key lifecycle; the 1:1:1 single-key record stays the minimal form.** The one legitimate KEM in the enrollment path is the `apkamSymmetricKey` conveyance at enroll/approve (P-3) — key *transport*, not auth. The client-side signing swap was previously unnamed in the plan; it now has a home (design.md §2.4), exercised by RF-2b + ON-1. | Same principle as the IS-1 pare-back: PKAM is authentication, not key agreement — the per-connection challenge gives freshness and TLS secures the channel, so only the signature is Shor-vulnerable. Recorded to pre-empt the same over-build (a KEM/cert/keyring on client auth) that IS-1 had carried, and to close the plan gap the client swap left. |
| **2026-07-21** | **IS-1 pared back to a signature swap; X-Wing KEM + cert machinery dropped.** IS-1 becomes: publish an ML-DSA-65 `pq_signing_publickey` (JSON, one field, for agility), sign the existing FROM/POL UUID challenge with ML-DSA instead of RSA, verify with `AtPqc.mlDsa65.verifyBytes` instead of the RSA path — two one-line algorithm swaps in the existing branch. **Removed:** the X-Wing KEM, the inter-server certificate, expiry / 30-day rotation grace, the HKDF confirmation tag, the `PqKeyManager` lifecycle class, and the unpublished at_chops `XWingCert`/`resolveXWing` surface (so IS-1's cross-package publish gate **dissolves** — it builds on published at_chops 3.4.x only). Effort L→M. PR #2683 is over-built against this scope and is to be pared back. | FROM/POL is **authentication, not key agreement**: the per-session UUID challenge already gives freshness/anti-replay and TLS already secures the channel, so the only Shor-vulnerable element is the signature. A KEM establishes a shared secret nothing in the handshake needs; a signing key needs no cert/rotation lifecycle (a change is a re-publish, read live). Same PQ guarantee at a fraction of the surface — the "don't over-engineer PQ safety" principle applied. See design.md §8. |

| **2026-08-02** | **Seven nskey data-path rulings** from walking an Alice↔Bob message end to end against the built providers ([13](#13-the-nskey-is-published-eagerly-mutable-and-generation-addressed-2026-08-02), [14](#14-content-keys-are-scoped-per-recipient-2026-08-02), [15](#15-the-record-owner-and-the-nskey-owner-are-different-atsigns-2026-08-02)): the nskey is published **eagerly** to `public:__nskey.<ns>@<owner>` (mutable, lock-serialised, generation-tagged), superseding lazy publication; content keys are scoped **per recipient**; and the record owner (`sharedBy`, for `info`) is separated from the nskey owner (`sharedWith ?? sharedBy`, for key selection). | The walk surfaced three defects the doc set had not caught: cross-atSign reads could not work, because the key ring was looked up under the sender's atSign; the promotion trigger fired on *sending* while the key a sender needs is the *recipient's*, so a receive-only atSign cold-started forever; and `design.md` called the published half immutable while B5b required re-publishing it, leaving the revocation lever unimplementable. Rotation additionally had no signal reaching senders — a silent B6 revocation failure — and a post-rotation joiner could not open retained history. |
| **2026-08-02** | **The sync push dropped `appMetadata`, and the fix deletes the duplicate serializer that dropped it** ([17](#17-the-sync-push-dropped-appmetadata-2026-08-02-fixed)). `SyncServiceImpl` now delegates to `Metadata.toAtProtocolFragment` instead of hand-rolling the metadata fragment, and a guard parses a fully-populated fragment with `VerbSyntax.update`. Cross-atSign reads work; the e2e test is un-skipped. | This was first recorded as an atServer defect — that attribution was wrong, and the correction is the durable lesson: **an absent field indicts the writer before the reader.** The wire observation (a `lookup` returning no `appMetadata`) was accurate, but *absent from the response* was read as *withheld by the responder* when the field had never been stored. The probe that separates them is an authenticated `llookup:all:` against the **writer's own** atServer after sync. Blast radius was every provider's synced writes, including shipped 3.14 — not PQ-specific — because a duplicated wire serializer had silently lagged the canonical one. |

| **2026-08-03** | **`pqpublickey` stops being a KEM and becomes `public:pq_signing_root@<atSign>`, the user-owned signing root** ([18](#18-pqpublickey-becomes-the-user-owned-signing-root-2026-08-03)). Cold-start has no PQ target and therefore **fails**, with legacy RSA reachable only by explicit opt-in; the release sequence makes that safe, since a final 3.x rebuild-and-rollout seeds the fleet with nskeys and roots before 4.x turns PQ on by default. SS-4 gates that 3.x release, `AtClientPreference.crypto` becomes nullable so the SDK owns the era default, and the root is written immutable with a `{v, keys[], successor}` payload. | A prove-possession step needs a signature, not a KEM, and one key doing both was the conflation to remove. Handing the root to the atServer was rejected: key transparency over an operator-held key records the operator's own signatures, so an auditor has nothing to catch, and the anchoring gap [12](#12-advertised-recipient-keys-are-signed-against-_apsk-2026-07-02) records would become structural. Publishing a key whose private is not durably conveyed is worse than not publishing, because the far end gets undecryptable data instead of a fast sender-side failure — hence publish-after-convey and SS-4 as a 3.x blocker. `keys[]` and `successor` ship on day one because the record is immutable and the whole fleet mints during the rollout, so mint time is the only chance to allow a second algorithm or any revocation at all. |
| **2026-08-03** | **Nested-namespace nskey resolution walks up, most-specific-first** ([19](#19-nested-namespaces-the-nskey-is-resolved-by-walking-up-2026-08-03)). A sender writing to `someid.d.c.b.a@alice` tries `d.c.b.a` … `a` and seals to the first nskey found; the CK is scoped to *that* namespace, so one conveyance serves every namespace beneath it. `appMetadata` gains `ns` (the record's own namespace) on every nskey-path record and `ckNs` (where the CK lives) on data values. Senders remember which namespaces an owner holds keys at, and that memo inherits `advertisementTtl` rather than adding a lifetime. | `AtKey.fromString` splits at the **last** dot, so a multi-segment namespace cannot be recovered from the wire string — measured, not inferred. It never mattered because the legacy provider references `namespace` zero times; the nskey path references it 56, which is what makes the ambiguity newly critical. Exact-match was unavailable: AtCollection composes `<subName>.<parentId>.<ns>` per **item**, so it would need a keypair, an advertisement and a per-enrollment conveyance per item. Walking up is safe because it mirrors the atServer's own suffix authorisation, so the crypto gate never widens past the transport gate. `ckNs` is not redundant with `ns`: in the stale-sender window the reader would otherwise hunt for the conveyance in the wrong namespace and report "not yet synced" for an intact record, forever. |

**Cross-refs:** the Wave-0 "already landed" detail and the project that follows
each decision are in `implementation-plan.md`; the phase trajectory this timeline
tracks is in `roadmap.md`.

---

## 8. Stale-source reconciliation note

The earlier source/working docs (`crypto-roadmap.md`, `crypto_impl_plan.md`,
`wp-ss-execution-plan.md`, `pq-secret-push.md`, …) were **consolidated away on
2026-06-30**; they encoded the **retired** multi-APKAM / `enroll:metadata` model, and
sections [4](#4-the-verb-wire-shape--111-cardinality-rulings) and
[5](#5-retrofit-ruling--fresh-self-spawned-auto-approved-enrollment) of this doc are
the authority that retired them. This table records what each encoded and the
authority that superseded it — for anyone reading their **git history**:

| Stale source section | Encodes (retired) | Authority |
|---|---|---|
| `wp-ss-execution-plan.md` P0 | `enroll:metadata` grammar (op + `metadataEnrollmentId`/`metadataJson` groups) | SS-1a (`EnrollParams.metadata`, no `metadata` op) |
| `wp-ss-execution-plan.md` P5 | client `registerKeyPackage` → `enroll:metadata` write | SS-1c (write path removed; package rides `enroll:request`) |
| `wp-ss-execution-plan.md` P9 | multi-APKAM `ApkamPublicKey` list + verify-against-any + plural `apkam[]` | SS-3 (single `apkamPublicKey` + `signingAlgo`); flat `listns` |
| `wp-ss-execution-plan.md` P12a/b/c | "second keypair under the enrollment" (P12a), per-APKAM-key delete (P12b), 8-step delete-after-ML-DSA (P12c) | RF-2b/RF-2c + RF-SRV (fresh auto-approved enrollment; old one ages out) |
| `crypto_impl_plan.md` D1-F F3/F4/F5 | multi-APKAM auth, per-APKAM-key delete, TTL/usage eviction | sections 4–5 here; SS-3, RF-SRV |
| `crypto-roadmap.md` "Cardinality, legacy-key deletion, and revocation" | "atServer allows multiple APKAM keypairs per enrollment", "delete a specific public key", "TTL/usage-based eviction", "auth against any" | section 4 here (1:1:1, record-authoritative `signingAlgo`) |
| `crypto-roadmap.md` "Upgrading an existing client — the sequence" + "atServer support this requires (four new capabilities)" | step-4 legacy-RSA delete after PQ auth; "four new" capabilities incl. multi-key + per-key delete | section 5 here (fresh auto-approved enrollment) |
| `pq-secret-push.md` P9/P12 | multi-APKAM list + per-APKAM delete | sections 4–5 here |

All the files named above were **deleted** in the 2026-06-30 consolidation — none
of them is a live document, and nothing in this table is an outstanding edit. At the
point of deletion, `wp-ss-execution-plan.md`'s OQ table had been brought up to date
(OQ2/OQ8/OQ9) while its project bodies (P0/P5/P9/P12) still lagged; that mismatch is
recorded here only so anyone reading the file's **git history** knows which parts of
it were already stale when it was removed.

**Cross-ref:** the corrected mechanics live in `design.md`.

---

## 9. APKAM keypair as key package: considered and rejected (2026-06-30)

**Question.** Each enrollment carries two PQ keypairs: the **ML-DSA APKAM keypair**
(uses: PKAM auth to the atServer + envelope signing, its public published as `_apsk`)
and the **X-Wing key package** (use: secret-sharing recipient — a sender encapsulates a
CK to it). Could one keypair serve all three uses, collapsing the two into one?

**Ruling — no. They are different primitives, not one key with two roles.** ML-DSA
(FIPS 204) is a **signature** scheme; the key package is **X-Wing** (ML-KEM-768 + X25519,
FIPS 203 + a classical KEM) — a **KEM**. You cannot encapsulate a secret to an ML-DSA
public key (it has no KEM operation), and X-Wing cannot sign. The three uses split
exactly along that line: *auth* and *envelope signing* need a signature; being a
*secret-sharing recipient* needs a KEM. Key-separation hygiene independently forbids
reusing one keypair across sign + KEM even where a dual-use primitive exists.

**The signing side is already unified.** Both signature uses — PKAM auth and envelope
signing — are served by the **single** ML-DSA APKAM keypair (its public is published as
`_apsk` for envelope verification). So each enrollment is already at the floor a PQ
design allows: **one signature keypair + one KEM keypair**, managed as a single bundled
credential — minted, registered, rotated, and revoked together under the 1:1:1 model
(section [4](#4-the-verb-wire-shape--111-cardinality-rulings)).

**Single-seed derivation — considered, rejected.** Deriving *both* keypairs from one
per-enrollment seed (`HKDF(seed, label) → {ML-DSA, X-Wing}`) was weighed as a further
simplification. Rejected:

- It saves only **keyfile bytes** (~6 KB of privates → a 32-byte seed) and changes
  **nothing** else — still two keypairs, two published keys, the same enrollment record,
  the same wire shapes, the same two crypto operations.
- It is plausibly **net-negative**: it adds seeded-keygen code for two PQ primitives plus
  a **re-derivation-stability dependency** — the derived keypairs must reproduce
  byte-identically *forever*, across at_chops/OpenSSL versions and platforms, or a client
  loses access to its own keys. Storing the privates directly avoids that risk entirely.
- A `HKDF(seed, namespace) → nskey` derivation was *also* floated for the nskey keypairs
  and **rejected outright** for an independent, more serious reason ([§10](#10-nskey-derivation-from-a-shared-master-seed-rejected-2026-06-30)):
  there the seed would be **shared across the atSign's enrollments**, which breaks
  post-compromise security, namespace compartmentalization, and rotation forward-secrecy.
  The **per-enrollment** seed considered here does **not** share that flaw — it is local
  to one enrollment and never distributed — but it also yields no distribution saving
  (the APKAM + key-package privates never leave the keyfile), so the only benefit on offer
  was the keyfile bytes already discounted above.

**Decision.** Leave it as-is. **Two keypairs per enrollment — one signature, one KEM — is
the irreducible floor** for a PQ design that needs both authenticated/signed messaging and
secret-sharing *to* a specific enrollment. No single-seed derivation for the enrollment
keypairs.

---

## 10. nskey derivation from a shared master seed: rejected (2026-06-30)

**Proposed (and briefly written into `design.md` §1.3).** Derive both nskey X-Wing KEM
privates per namespace as `HKDF(master-seed, namespace [, epoch]) → X-Wing seed`, with the
master seed held in `.atKeys`, so that "any client of the atSign derives both privates with
no distribution." The pitch was eliminating the per-APKAM substrate conveyance of the nskey
privates.

**Rejected — it is a post-compromise security hole, and worse.** For the whole atSign to
share one nskey per namespace, every authorised client must derive the **same** keypair, so
the master seed must be **shared across all of the atSign's enrollments**. That shared,
long-term secret breaks the three properties the nskey design exists to provide:

1. **Post-compromise security / self-healing.** Exfiltrating one device's master seed yields
   every nskey private the atSign will *ever* have. Revoking that enrollment doesn't heal —
   the attacker keeps deriving future namespace keys offline. The only remediation is a
   fleet-wide master-seed re-key (re-derive + republish every namespace's public nskey,
   re-convey every CK), the exact event per-enrollment revocation exists to avoid.
2. **Namespace compartmentalization / cryptographic access control.** The namespace is only a
   **public** HKDF label, so a seed-holder can derive nskey privates for namespaces it was
   never authorised for — authorization stops being cryptographically enforced. Under
   conveyance, an enrollment only ever receives the privates sealed to it, for the namespaces
   it was granted.
3. **Forward secrecy of rotation.** The `epoch` term is likewise a public label, so every
   epoch is derivable from the one seed — epoch rotation buys **zero** FS against a seed leak.
   The `epoch` lever (`design.md` §1.7) only works when the underlying private is random per
   epoch.

The shared seed is **intrinsic** to the derivation: a per-enrollment seed would derive
*different* keys and so couldn't produce the shared namespace nskey at all. There is no safe
scoping — the optimization is rejected outright, not demoted to optional. It was also
internally inconsistent: `design.md` §4's `.atKeys` store taxonomy holds no master seed.

**Accepted model (already used everywhere else in the corpus).** nskey privates are **minted
as fresh random keypairs and conveyed per-APKAM over the substrate** (sealed to each
authorised enrollment's key package); rotation mints a fresh keypair and distributes it to
the surviving enrollments, **excluding the revoked one** (`implementation-plan.md` B5b). The
public nskey's public half is still published (a sender has no other way to obtain a peer's
per-namespace public key — ML-KEM has no public child-derivation). Compromise is then bounded
to what one enrollment holds; the system heals on revocation + rotation; a client holds keys
only for the namespaces granted to it.

**Scope of the ruling.** A full-corpus derivation sweep (all five docs, finder + independent
adversarial verifier per doc) found this to be the **only** insecure key-derivation site —
present only here (`design.md` §1.3) and in the [§9](#9-apkam-keypair-as-key-package-considered-and-rejected-2026-06-30)
cross-reference that mis-framed it as a "win"; both are now corrected. Every other derivation
in the design is secure by construction: the X-Wing/HPKE key schedule (ephemeral per-op
shared secret), the MLS/D2 ratchet (epoch secrets advance and are deleted), CK/nskey rotation
(fresh independent material), and `kid`/`kpid` identifiers (a hash of a *public* key, not a
secret). This is **distinct** from §9's **per-enrollment** single-seed idea, which is
*per-principal* and local-only — it lacks this flaw and was rejected on the separate ground
that it saves only keyfile bytes.

---

## 11. Single nskey per namespace, lazily published (2026-06-30)

> **Partly superseded (2026-08-02).** The *one keypair per `(atSign, namespace)`* ruling
> below stands and is load-bearing. Its **publication** half — lazy publication as the
> mitigation for namespace-existence leakage — is superseded by
> [section 13](#13-the-nskey-is-published-eagerly-mutable-and-generation-addressed-2026-08-02),
> which keeps the goal and changes the mechanism.

**Decision.** Each `(atSign, namespace)` has **one** X-Wing KEM nskey keypair, not two. The
single nskey is the recipient key for **both** directions — the owner encapsulates her own
content keys (CKs) to it for self data, and external senders encapsulate CKs to it when sharing
with her. Its public half is **published lazily**: it lives as the self at-key
`nskey.<ns>@<owner>` (owner-only, synced to the owner's authorised clients) until the namespace
is first used cross-atSign, at which point the *same* public half is promoted to the
world-readable `public:nskey.<ns>@<owner>`. The private half is minted fresh and conveyed
per-APKAM over the substrate ([§10](#10-nskey-derivation-from-a-shared-master-seed-rejected-2026-06-30)),
never derived. This came from peer review, which observed that a separate "self nskey" and
"public nskey" were doing the same cryptographic job (X-Wing KEM wrapping a CK) for the same
private-holders.

**Why it is sound — no security loss.**

1. **Confidentiality.** A KEM public key is meant to be public; the private is the secret. A
   world-readable encapsulation target lets anyone *create* sealed CKs (useless without the
   private) but exposes nothing. Self-encapsulation is just one more encapsulator against a key
   built for many.
2. **Compartmentalization was illusory.** Two keypairs appear to isolate self data from
   inbound-shared data, but both privates were held by the same clients and conveyed over the
   same substrate to the same key packages — never separable in practice. Compromise blast
   radius is identical for one key or two.
3. **Authenticity is independent of the split.** A KEM gives confidentiality, not
   sender-authenticity. Provenance is carried by record ownership + write-authorisation
   (`…__ck.<ns>@alice` written by an authorised Alice client vs `…__ck.<ns>@bob` cached from
   Bob), unchanged by collapsing the keys.
4. **Revocation simplifies.** Evicting a compromised client rotates every nskey private it
   held — both, anyway. One key is one rotation, and the read path loses the self-vs-inbound
   branch.

**The one weakness, and the mitigation taken.** A single key whose public half is published
advertises the *existence* of the namespace to anyone doing a public `plookup`/scan, and makes
namespace usage correlatable across atSigns. For a namespace used purely for the owner's own
data — which under two keys had only an owner-only self nskey — this would be a new metadata
leak (existence only; no CK, content, or key material). **Mitigation, adopted: lazy
publication.** The public half stays an owner-only self at-key until the namespace is first
shared cross-atSign; a purely-self namespace therefore never advertises itself. Inbound that
arrives before promotion was to be bridged by cold-start to the atSign-level root (a bridge
[section 18](#18-pqpublickey-becomes-the-user-owned-signing-root-2026-08-03) withdrew, along
with lazy publication itself — see section 13). This keeps the one-keypair simplification (one private, one
rotation, one decapsulation path) while preserving namespace-existence privacy.

**Foreclosed capability — accepted.** Two keypairs could have granted a client read access to
inbound-shared data but not the owner's own self data (convey only one private). The single-key
model cannot draw that boundary — a client either holds the nskey private (reads both) or does
not. The design does not use this asymmetric access today, so nothing is lost now; the option
is foreclosed going forward.

**Consequences for the model.**

- `appMetadata.recipientKind` on an `at/nskey` CK-conveyance record is `nskey`, for self and
  inbound alike — the former self-nskey/public-nskey distinction is gone. (The cold-start
  `root-pqpublickey` variant this once also listed went with
  [section 18](#18-pqpublickey-becomes-the-user-owned-signing-root-2026-08-03).)
- The reader decapsulates every `__ck` record with the one nskey private.
- HPKE `info` binds `(namespace, owner)` so self and inbound flows stay domain-separated under
  the shared key.
- The detailed mechanics live in `design.md` (key shapes, the data flow, rotation), the build
  steps in `implementation-plan.md`, and the acceptance cases in `acceptance.md`.

---

## 12. Advertised recipient keys are signed against `_apsk` (2026-07-02)

**Decision.** Every *advertised recipient/encapsulation key* is **signed by the
generating enrollment's APKAM key** and verified by the fetcher against that
enrollment's published `_apsk` — **the same way for a same-atSign and a
cross-atSign verifier**. This **supersedes** the earlier "key packages are unsigned;
the atServer vouches" stance ([section 4](#4-the-verb-wire-shape--111-cardinality-rulings),
the substrate's original design): the encapsulation target is now
**authenticated**, not merely server-asserted.

**What is covered.** The keys a party fetches in order to seal *to* someone:

- the per-enrollment **key package** (the X-Wing recipient key at the singular
  `metadata.keyPackage`, Layer 1 of the substrate);
- the published **`nskey`** public half (`public:__nskey.<ns>@<atSign>`, written at
  mint — [section 13](#13-the-nskey-is-published-eagerly-mutable-and-generation-addressed-2026-08-02)).
  **Built as of 2026-08-03**: `PublishedNskeyKeyRing` signs its own advertisement and
  `ApkamSignedAdvertisedKeys` verifies a peer's, cross-atSign on the live wire. The key
  package is still advertised unsigned.

*(This list once carried a third entry, the atSign-level root as a KEM target.
[Section 18](#18-pqpublickey-becomes-the-user-owned-signing-root-2026-08-03) withdrew it:
the root is a signing key, so there is nothing to seal to it and nothing for a sender to
authenticate before doing so. What anchors the root is key transparency, not an `_apsk`.)*

**Mechanism.** The generating enrollment wraps the advertised key in an
**APKAM-signed envelope** — the *same* `wrapAndSign` / `AtSigningMode.pkam`
construction already used for `__ssenv` messages (`envelope_signing.dart`). A
verifier fetches the generating enrollment's `_apsk` public key from
`public:_apsk.<enrollmentId>.<perEnrollmentApproved>@<atSign>` — the location the
at_client **`ApkamSigning`** mixin defines — and verifies the signature. There is
**one** verify path: a same-atSign client (another of the owner's enrollments) and a
cross-atSign client (a peer atSign's enrollment) both do exactly this.

**The signature self-describes enough to verify.** The signed envelope carries the
**`signingAlgo`** (which implies *what sort of key* `_apsk` holds — RSA / ML-DSA /
ECC) and the **`hashingAlgo`**, so the verifier selects the correct verification
routine. Authenticity anchors on the `_apsk` key itself: a lie about `signingAlgo`
simply fails the verify against the real key.

**`_apsk` is a cross-tier property the atServer guarantees — present *and*
write-restricted.** Because verification depends entirely on `_apsk`, the atServer:

1. **keeps `_apsk` present** — it populates
   `public:_apsk.<enrollmentId>.<perEnrollmentApproved>@<atSign>` from the enrollment
   record's stored `apkamPublicKey` (on approval / first authenticated use), rather
   than leaving it to the client-side `ApkamSigning.publishPublicSigningKey`
   get-then-put (which races and can be absent when a verifier looks). A verifier can
   always resolve a generator's `_apsk`.
2. **write-restricts `_apsk`** — only the owning enrollment's own authenticated
   connection may write it (verified empirically against the released atServer, June
   2026).

Both properties MUST be asserted by e2e tests (an approved enrollment's `_apsk` is
fetchable without a client publish; a cross-enrollment overwrite is refused).

**Trust model — what this does and does not remove from the confidentiality TCB.**
The verification chain is only as strong as its anchor, and the anchor for `_apsk` is
the atServer that serves it. So the signing separates two adversaries sharply:

- **Against a malicious *insider* under an honest server** — a legitimately-enrolled
  but rogue or lower-privileged client trying to inject a poisoned key package / secret
  as if from another enrollment — signing **works**: the honest server serves each
  enrollment's *real* `_apsk`, and the signature lets the receiver distinguish an
  authorised minter from a rogue enrollment. This is the concrete win, and it holds
  same-atSign **and** cross-atSign.
- **Against a malicious atServer *operator*** — one that generates its own keypair,
  serves the public half as the enrollment's `_apsk`, and serves a self-generated
  advertised key signed by the matching private — signing gives **nothing**: the
  operator controls both the signature key and the `_apsk` it is verified against, so
  the chain is internally consistent but rooted in a key the operator chose. This is
  true **same-atSign and cross-atSign alike** — do **not** claim signing removes the
  operator from the TCB in either case.

So the operator of an atSign's atServer is in the **confidentiality TCB for all data
destined to that atSign** (inbound cross-atSign shares, and self-data where the client
relies on server-served keys) — a transparent, split-view MITM that this signing does
not, by itself, prevent. That is **not new** and **not introduced by the substrate**:
classical Atsign has the same property (a sender fetches `public:publickey@alice` from
@alice's atServer). Signing is *necessary infrastructure* toward operator-resistance —
it chains advertised keys to `_apsk` — but becomes *sufficient* only once the anchor
(the atSign's identity→key binding) is distributed through a channel the operator does
not control. The full threat model, why it is undetectable to a targeted victim today,
and the mitigation ladder (self-hosting, client self-audit, out-of-band fingerprints,
atDirectory key transparency, root-anchored signatures, attestation) are in
[`design.md`](design.md) → *Trust boundary & residual threats*.

The public/private **correspondence check** for a conveyed keypair secret (`nskey` /
`pqpublickey` privates) remains a useful **secondary** check, subordinate to the
signature.

**Why.** It reuses machinery that already exists (`wrapAndSign` + the `_apsk`
resolution in `ApkamSigning` / `EnvelopeSigning`), needs no new key type (the ML-DSA
APKAM signing key and the X-Wing encapsulation key are correctly distinct —
[section 9](#9-apkam-keypair-as-key-package-considered-and-rejected-2026-06-30)), and
raises the substrate's floor from "the atServer vouches" to "a non-operator adversary
cannot forge advertised keys" — the remaining operator trust is addressed by the
separate transparency work above, not by the substrate.

**Implementation status.** Target, not yet built: sign in the mint paths
(**SS-2** key package, **SS-4** nskey / pqpublickey), verify on read (**SS-1c**); the
atServer `_apsk`-always-present + write-restriction is **SS-1b**. The current
substrate advertises the key package **unsigned** — tracked as a gap in `design.md`
§6. Mechanics: `design.md` §2.1 (*Advertised-key authenticity*) and §2.4; sequencing:
`implementation-plan.md` SS-1b/SS-1c/SS-2/SS-4; acceptance: `acceptance.md` §13.

---

## 13. The nskey is published eagerly, mutable, and generation-addressed (2026-08-02)

**Decision.** Three parts, together replacing the lazy-publication half of
[section 11](#11-single-nskey-per-namespace-lazily-published-2026-06-30):

1. **Eager publication.** The nskey public half is written **at mint time, always**, to
   `public:__nskey.<ns>@<owner>`. There is no owner-only self at-key stage, no promotion
   step, and no first-cross-atSign-share trigger.
2. **The advertisement is mutable.** That one record holds an APKAM-signed
   `{nskeyKid, publicKey}` and is **overwritten** on rotation. Creation and rotation
   serialise behind a short-TTL **immutable lock key** — a self key, since only the
   owner's own enrollments can race for it.
3. **Generations are addressed by `nskeyKid`.** Every `at/nskey` CK-conveyance record
   carries the kid of the nskey it was sealed to, so a reader holding several
   generations indexes straight to the right private.

**Why eager — the promotion trigger was unsound.** Promotion fired on a namespace's first
*outbound* share, but the key a sender needs is the **recipient's**. An atSign that only
ever receives in a namespace therefore never published, so every sender cold-started to
`public:pqpublickey@<recipient>` **forever** — permanently concentrating traffic on the
one atSign-level root key that namespace scoping exists to avoid. Fixing the trigger
(promote on first inbound too) would have kept a two-stage lifecycle whose only remaining
job was privacy — which part 1's naming achieves outright.

**Why the underscore — the privacy goal is kept, the mechanism changes.**
[Section 11](#11-single-nskey-per-namespace-lazily-published-2026-06-30) adopted lazy
publication to stop a published key advertising the *existence* of a namespace, since
namespaces are app names and the set of them profiles an atSign. A `public:__` key is
revealed only *by* `showhidden`, and an **unauthenticated scan ignores `showhidden`** —
so the only scan an outsider can issue never returns it — while `plookup` still serves
it on an exact name, cross-atSign. Fetchable by anyone who already knows the namespace;
enumerable by nobody who matters. This is the same shape `_apsk` already relies on
([section 12](#12-advertised-recipient-keys-are-signed-against-_apsk-2026-07-02)).

**Why double and not single (2026-08-02, measured).** A *single*-underscore public key
is hidden from every scan, the owner's own with `showhidden` included — strictly
stronger, and the first choice. It is unusable: such a key is written with **commit id
-1**, sits outside the commit log, and **sync can never push it**. An advertisement that
cannot leave the device is no advertisement. Double underscore carries a real commit id
and syncs. The advertisement is additionally written **direct to the atServer**, since
it is only useful once a peer can fetch it and the local-first path would leave it
unpublished until the next sync. Established against a live atServer after three
successive attempts to verify it through client machinery each measured something other
than what they claimed.
The leak section 11 mitigated is closed at least as tightly, without the two-stage.

**Why mutable — immutability was race control, and it made rotation impossible.**
`design.md` simultaneously called the published half *immutable create-if-absent* and
required B5b to *re-publish* it on rotation; those cannot both hold, so nskey-keypair
rotation — the post-compromise-security and per-enrollment revocation lever — was
unimplementable as specified. Immutability there is a **concurrency** control, not a
confidentiality one: substitution is prevented by the APKAM signature verified against
`_apsk` (section 12), which is unaffected. Taking the lock explicitly restores the race
safety and leaves the record writable, which is what rotation needs. The root
`public:pqpublickey@<atSign>` is **unchanged** — it never rotates, so it stays immutable
create-if-absent.

**Rotation signal — the sender re-fetches; there is no failure path back to it.**
The design previously said a sender "re-fetches on a decapsulation-failure / rotation
signal". No such signal can exist: the sender never decapsulates, and the recipient's
failure is on the recipient's device. Left unfixed this is a **silent revocation
failure** — a sender still holding a pre-rotation public half keeps sealing new content
keys to a generation the revoked enrollment can still open, so B6 revocation does not
hold for inbound cross-atSign data. The rule is therefore: the sender re-`plookup`s
`public:__nskey.<ns>@<recipient>` whenever it mints or reuses a CK for that destination,
and a `nskeyKid` mismatch forces a fresh CK conveyed to the new generation. Exposure is
bounded by one CK lifetime rather than being unbounded.

**Amended (2026-08-02, on building it).** "Re-`plookup` whenever it mints or reuses a
CK" is a round trip to the recipient's atServer **on every `put`** — `ensureCurrent`
runs per write, because comparing the advertised kid against the cached one is how
rotation is detected at all. That is unusable, and it would break offline writes,
which the SDK supports. The rule is therefore: the sender caches a fetched
advertisement for a bounded **TTL** and re-fetches when it is stale. Total exposure is
**TTL + one CK lifetime**, still statable and now tunable, and the steady-state write
path costs no network. The original wording chose the tightest bound without costing
it; this is the same mechanism with a lever on it.

**Generation retention — current on join, older pulled on demand.** A new enrollment is
pushed the **current** generation only, so join cost stays O(1). When a reader meets a
`__ck` tagged with an `nskeyKid` it does not hold, it issues `requestSecret` for that
generation over the substrate's existing pull backstop. History becomes pay-as-you-go and
a device that never reads old data never pays. This is only possible *because* part 3
tags the record; without the tag the alternative is trial decapsulation, which costs an
X-Wing operation per generation and degrades silently with every rotation.

**Consequences.**

- `nskey.<ns>@<owner>` (the owner-only self at-key form) **no longer exists**. The key
  shape is `public:__nskey.<ns>@<owner>` from mint onward.
- `appMetadata` on an `at/nskey` record becomes
  `{providerId, recipientKind, ckKid, nskeyKid}`.
- The nskey key ring is keyed `(owner, namespace, nskeyKid)` with a current pointer —
  structurally identical to the CK cache, and for the same reason.
- **Cold-start survives but narrows sharply**: `recipientKind: root-pqpublickey` is now
  reached only when the recipient has never used the namespace *at all*, rather than
  whenever they have never sent in it.
- Namespace-existence privacy rests on the `public:_` scan-hiding rule. That is a
  **core, guaranteed property of the Atsign Protocol**, not an assumption this design
  makes — `_apsk` already depends on it. A **functional**-suite regression test covers it
  (`tests/at_functional_test/test/underscore_public_key_hiding_test.dart`) so a server
  change cannot quietly retire it under us. Note the layer: that suite runs against
  `at_virtual_env:local`, not the `vip` image CI drives, so it is not a CI gate.

**Implementation status.** Eager publish itself **is built** as of the
`gkc-pq-d1-spike` branch (`PublishedNskeyKeyRing`), the sender-side re-`plookup`
(**B-1d**) with it, and **advertisements are signed and verified**: the ring signs its
own with `wrapAndSign`, and `ApkamSignedAdvertisedKeys` checks a peer's against the
`_apsk` the signing enrollment published, cross-atSign on the live wire. Still missing is
the other safety mechanism — there is no `_nskeylock` serialising mint/rotate, which with
real minting is **SS-4**. Rotation and the generation pull
are **B-2** + the substrate. The `nskeyKid` tag on the conveyance is
**B-1b** — a wire-shape addition that is free before any record exists and expensive
after. Mechanics: `design.md` sections 1.3–1.5 and 1.7; acceptance: `acceptance.md`
sections 4, 5 and 6.

---

## 14. Content keys are scoped per recipient (2026-08-02)

**Decision.** A content key belongs to a `(recipient, namespace)` pair, not to a
`(sender, namespace)` pair. The CK cache and its *current* pointer are keyed by the
**nskey owner** — the atSign whose nskey the CK is sealed to. Alice writing to Bob and
Alice writing her own self-copy use **different** CKs, and therefore different
ciphertexts.

**Why.** Under a per-namespace CK, one key is conveyed to every recipient of that
namespace, so any recipient who obtains the bytes of a message meant for another can
decrypt it — separation would rest entirely on the atServer's `sharedWith` gate. Scoping
per recipient puts that separation in the crypto, where a compromised or hostile
recipient cannot reach it, and matches `design.md`'s own statement that whose nskey a CK
is sealed to is "per recipient, not a group". It also makes the FS and PCS levers
independent per destination: rotating for Bob leaves Carol's traffic untouched.

**What it costs.** The message body is encrypted once per recipient. The number of
conveyance records is unchanged — a CK has to be sealed separately to each recipient's
nskey either way — so the cost is N ciphertexts rather than N conveyances, and it is
paid only by a genuine multi-recipient write.

**Consequences.**

- `acceptance.md` UC-A4.1's self-copy step is **correct and stays**, but it conveys a
  *second* CK from the sender's own scope, not the same CK sealed twice.
- A CK is long-lived **per destination** and rotates on the forward-secrecy lever, not
  per message.
- Something above both providers must mint and convey a CK the first time a destination
  is written to — see [section 15](#15-the-record-owner-and-the-nskey-owner-are-different-atsigns-2026-08-02)
  for why the data provider cannot do it itself.

**Implementation status.** The cache re-scope is **B-1a**; the per-destination mint
trigger is **B-1**'s routing work.

---

## 15. The record owner and the nskey owner are different atSigns (2026-08-02)

**Decision.** Every `at/nskey` and `at/symmetric/AES/GCM` operation resolves **two**
distinct atSigns from the `AtKey`, and they must not be conflated:

| Purpose | atSign | Derivation |
|---|---|---|
| HPKE `info` domain separation | the **record owner** | `sharedBy` |
| Which nskey seals or opens it; CK cache scope | the **nskey owner** | `sharedWith ?? sharedBy` |

**Why they differ.** On any inbound record — `@bob:<ckKid>.__ck.<ns>@alice` — the record
is owned by the sender but the envelope is sealed to the **recipient's** nskey. Deriving
the key from `sharedBy` makes Bob's client ask its ring for *Alice's* namespace private,
which it will never hold, so cross-atSign reads fail with a misleading "not authorised
for the namespace". `decisions.md`
[section 11](#11-single-nskey-per-namespace-lazily-published-2026-06-30) is unambiguous
that "the reader decapsulates every `__ck` record with the one nskey private" — its own.

**Why `info` stays on the record owner.** The binding exists so that self and inbound
flows stay domain-separated under one shared key. That separation only works if the bound
value is what *differs* between them — the record owner. Binding the recipient instead
would give `@bob` for both and separate nothing.

**Consequences.**

- `sharedWith` survives the `cached:` prefix, so the derivation is available on a
  received record without consulting client identity.
- Because the CK cache scope is the nskey owner
  ([section 14](#14-content-keys-are-scoped-per-recipient-2026-08-02)), one derivation
  serves both the key ring and the cache; `sharedBy` is used *only* for `info`.
- The mistake is easy to reintroduce, so the two derivations are named separately in code
  rather than sharing an `_ownerOf` helper.

**Implementation status.** **B-1a**/**B-1b**. Behaviour-preserving for self data, where
the two derivations coincide; it is what makes **B-1d** possible at all.


---

## 16. A provider id names every algorithm a reader needs code for (2026-08-02)

**Decision.** A `providerId` is `at/<role>/<algorithms…>`. It names the role, then
**every algorithm a reader needs an implementation of**. Anything a reader can
discover from the value itself — the `pqSeal` envelope version, `iv`, `ckKid`,
`nskeyKid` — stays out of the id.

Concretely the CK-conveyance provider becomes **`at/nskey/XWING/AES/GCM`**, not the
bare `at/nskey`. `at/symmetric/AES/GCM` was already compliant and is unchanged.
`at/nskey` survives as the **family prefix**, so prose about "an `at/nskey` record"
still means the family and `at/nskey/*` is the set.

**Why the old form failed the test it set itself.** `design.md` justified the
asymmetry — the data provider names its algorithm "because that is the layer that
needs crypto-agility", while `at/nskey` named a role and deferred versioning to
"the key's kid". But a kid is a hash of the public key: it identifies **which key**,
not **which algorithm**. So layer 2 had no agility at the routing level at all. The
only versioning was `pqSeal`'s envelope byte, which a reader cannot act on until it
already has the code to parse the envelope — too late to be a routing decision.

**What the rule buys.** Reads stay universal: a reader registers every scheme it has
ever supported and values route by their own id, so records written under a retired
scheme keep opening forever. What the id adds is that a **writer can decide** whether
a recipient can read a scheme rather than guessing — which is what turns an algorithm
change from a flag day into a rollable migration. `at/nskey/MLKEM1024/AES/GCM` can
coexist with `at/nskey/XWING/AES/GCM` indefinitely.

**Granularity, and why it is deliberately slightly over-specified.** `pqSeal` versions
KEM, KDF and AEAD together as one suite, so naming both the KEM and the envelope AEAD
says more than today's code can vary independently. That is the safe direction: if
they ever decouple, the id already distinguishes them, whereas a suite-level token
(`at/nskey/atPQv1`) would have to be re-cut. The cost is a longer string.

**Consequence for negotiation — the capability marker becomes a set.** A boolean
"ready / not-ready" per `(atSign, namespace)` cannot express *which* schemes a fleet
supports, so it cannot survive a second PQ scheme. The B3 marker therefore advertises
the **set of provider ids** the fleet supports, and a writer picks the best id present
in **every** required reader's set. Ready/not-ready becomes the degenerate case —
"is the PQ pair in the set". This is **R-1**'s to build; recorded here so it is not
re-derived later.

**Timing.** Free now and expensive later: nothing has been written under the bare
`at/nskey`, so the rename costs a constant and a doc sweep. Once a record exists it
costs a migration.

**Implementation status.** The id and the family constant are **B-1b** (done). The
marker-as-a-set is **R-1**. Mechanics: `design.md` sections 1.2 and 1.5.


---

## 17. The sync push dropped `appMetadata` (2026-08-02, fixed)

**The defect is in this package, not the atServer.** `SyncServiceImpl._metadataToString`
— a hand-rolled metadata serializer that builds the `update:` command for the sync
**push** — never emitted `appMetadata`. So a record carried its `providerId` in local
storage, sync stripped it on the way up, and the atServer stored the record without it.
A recipient's `lookup` then returned exactly what the server held: nothing. Since
`CryptoRuntime` routes every read by `appMetadata.providerId`, the recipient saw `null`
and fell back to `legacy`, which hunted for a `shared_key` a PQ write never created.

**This is not specific to the nskey path.** Any provider's stamp was dropped on any
synced write, including those shipped in `at_client` 3.14. Same-atSign reads were
unaffected, because they never leave local storage.

**How this was first recorded wrongly, and the probe that settles it.** This section
previously asserted, as a *measured* finding, that the atServer does not return
`appMetadata` on `lookup`. The wire observation behind it was accurate — `@bob`'s
`lookup:all:` genuinely came back with `sharedKeyEnc`, `pubKeyCS`, `ivNonce`,
`pubKeyHash` and no `appMetadata`. The **attribution** was not: *absent from the
response* was read as *dropped by the responder*, when the record had never carried the
field into the server at all. One probe separates the two, and it was never run — an
authenticated `llookup:all:` against the **writer's own** atServer after sync, which
distinguishes *not returned* from *never stored*. The superseded text also claimed
`appMetadata` "survives `sync`"; the push direction is precisely where it died.

The general rule: **an absent field indicts the writer before the reader.** Confirm the
data reached the store before concluding the store withheld it.

**Root cause was a duplicated serializer, and the fix deletes it.**
`Metadata.toAtProtocolFragment` (`at_commons`) is the canonical builder of this wire
fragment; `_metadataToString` was a second, hand-rolled copy that existed only because
sync holds the persistence type `AtMetaData` rather than the commons type `Metadata`.
The copy silently lagged the original — it had also fallen behind on **`immutable`**.
It is now gone: the sync push calls
`metadata.toCommonsMetadata().toAtProtocolFragment()`, so the two cannot drift again.
(This needs `at_persistence_secondary_server` ≥ 5.1.0, where `toCommonsMetadata` carries
`appMetadata`; the pubspec floor is already `^5.1.0`.)

**Field order is not free.** `VerbSyntax.metadataFragment` is a sequence of optional
groups, so a field emitted out of order silently fails to match and is dropped without
an error — the same failure mode, one step later. Delegating to the canonical builder
gets the order right by construction, and a guard now parses a fully-populated fragment
with `VerbSyntax.update` itself, asserting through to the tail groups. It was checked
against a deliberate mis-ordering rather than only observed to pass: moving
`appMetadata` ahead of `immutable` makes the regex fail to match the command outright.
Asserting a field is `contains`ed cannot catch this, and neither can comparing against
`toAtProtocolFragment` — the two agree even when the canonical builder is itself the one
out of order.

**Consequence for the `_nskeylock`** (specified in
[section 13](#13-the-nskey-is-published-eagerly-mutable-and-generation-addressed-2026-08-02),
owed by SS-4): a short-TTL **immutable** key used as a mutex must be written
**direct-to-remote**, never via sync. Until this fix the sync push could not convey
`immutable` at all; that is now repaired, but the requirement stands for a stronger
reason that no serializer fix touches — **a mutex needs the atServer to arbitrate at the
moment of acquisition.** A synced write is local-first and asynchronous, so two
contending writers would each succeed locally and discover the conflict only at the next
sync, long after both had acted as lock-holder. `AtRpc._tryAcquireSessionMutex` is the
precedent to copy (`PutRequestOptions..useRemoteAtServer = true`); it is the same reason
the nskey advertisement is written direct-to-remote.

**Why it went unnoticed.** [Section 12](#12-advertised-recipient-keys-are-signed-against-_apsk-2026-07-02)
and the cross-cutting invariants assert that `providerId` is present on *stored keys and
notification frames*. Nobody wrote down the **sync push** path, and no test crossed two
atSigns — so a hole in a shipped seam sat open. The unit tests could not have found it:
they mock the wire.

**Rejected: inferring the provider client-side** when `appMetadata` is absent — by key
shape, or by trying providers in turn. It guesses which scheme opened a record, and a
wrong guess is a silent mis-decrypt or a misleading error. Failing loudly is better than
guessing at cryptography. (This stands on its own merits, and is unaffected by the
misattribution above.)

---

## 18. `pqpublickey` becomes the user-owned signing root (2026-08-03)

**Status:** accepted, supersedes the `pqpublickey`-as-KEM model throughout
[design.md](design.md) section 1.4 and every site that describes a cold-start
encapsulation to it.

`public:pqpublickey@<atSign>` was the atSign-level root **KEM** target: the universal
cold-start recipient a sender encapsulated a content key to when the recipient's
namespace had no published nskey. That role is withdrawn. The key is now
`public:pq_signing_root@<atSign>`, it signs and verifies only, and it never appears in
a key-transport path.

This follows the rule the inter-server work already settled: a prove-possession step
needs a PQ **signature**, and a KEM belongs only where there is a secret to convey.
Giving one key both jobs is the conflation this removes.

### 18.1 What the root is for

The root is the **user-owned** anchor of the trust chain, and the intent is for the SDK
to publish it to a key transparency system at mint.

Everything advertised by an atSign is verified against a per-enrollment `_apsk`
([section 12](#12-advertised-recipient-keys-are-signed-against-_apsk-2026-07-02)), and
`_apsk` is served by the atServer, so an operator who can rewrite it can substitute any
advertised key. That is recorded there as a known limit. The root closes it: approvers
sign enrollees' key packages, so the chain runs root → key package → `_apsk` →
advertised keys, and the anchor is something the operator cannot produce.

Handing the root to the atServer was considered and rejected. Key transparency over an
operator-held key records the operator's own signatures, correctly signed, so an auditor
has nothing to catch. It would make the operator's position structural rather than a gap
to close. Self-hosting makes operator and user the same party for some deployments, and
the design should not assume it for the rest.

`public:signing_publickey@<atSign>` is atServer-to-atServer auth and unrelated to
clients; the `public:pq_signing_publickey@<atSign>` that joins it is the atServer's, not
the user's.

### 18.2 Custody

Only an enrollment with full privileges (`rw` on `*` and `__manage`) may create the root.
That app writes the private into its own `.atKeys` and conveys it to the other fully
privileged enrollments over the secret-sharing substrate. Namespace-scoped enrollments
never hold it; they get `_apsk` and nskey privates. There is precedent for the class:
`default_enc_private_key.__manage` and `default_self_enc_key.__manage` already travel
this way (`at_auth/lib/src/enroll/at_enrollment_impl.dart:427,442`).

The record is written **immutable**, which is what prevents a split root. Several
`__manage` apps updating on independent schedules could each find no root and each mint
one, and because the root never rotates there would be no way to reconcile two chains or
two transparency-log entries. The first create wins and later creates are refused. The
atServer guard restricting namespace-less-key writes to fully privileged enrollments
covers the same record from the other side.

### 18.3 Shape

Named `public:pq_signing_root@<atSign>`, plain `public:` rather than `_` or `__`.
Namespace hiding exists to stop outsiders enumerating which apps an atSign uses; an
identity root published to a transparency log wants the opposite, since being found and
audited is the mechanism.

The payload mirrors the key package's ratified agility shape
([section 12](#12-advertised-recipient-keys-are-signed-against-_apsk-2026-07-02)):

```json
{ "v": 1,
  "keys": [ { "alg": "ml-dsa-65", "pub": "<base64>" } ],
  "successor": null }
```

`keys` is a list rather than a single algorithm because the record is immutable, so mint
time is the only moment a root can be made verifiable under more than one algorithm; a
single-algorithm shape would foreclose hybrid or transitional verification permanently,
for every atSign, at rollout. Readers skip entries whose `alg` they have no code for, as
they already do for key packages.

`successor` reserves the revocation chain. Revocation is not implemented in D1, and the
slot ships anyway: the whole fleet mints roots during the 3.x rollout and publishes them,
so the shape is fixed for every atSign from that moment. A root that can neither rotate
nor be revoked has no answer to compromise at all, and transparency gives detection
rather than recovery.

### 18.4 Cold-start, and the two-release upgrade path

With the root out of the key-transport business, cold-start has no PQ target. The ruling
is that it **fails**, and legacy RSA is reached only by explicit opt-in. Once an nskey is
available it is used from then on, forward-only; re-encrypting records already written
under the legacy fallback is R-1's explicit migration and never a side effect of a `put`,
which would put an unbounded scan-and-rewrite inside a write pre-pass.

The hard failure is safe because of the release sequence, which is the point of the whole
design:

1. **Final 3.x** is a rebuild and rollout with no app code changes. The client reads PQ
   records, mints and publishes its nskeys and its root, and still writes legacy.
2. **4.x** makes PQ the default, and cold-start always throws.

Step 2 is only tolerable because step 1 has already seeded the fleet. That places two
constraints on the final 3.x release.

**SS-4 gates it.** Privates are held in memory today
(`published_nskey_key_ring.dart:106-107`), so a key minted in 3.x evaporates on restart
and leaves a published public half nobody holds. A 4.x sender would encapsulate to it and
the recipient could never decrypt, which is worse than not publishing at all, since that
case at least fails fast at the sender. The ordering is publish-after-convey, never
before: nothing advertises a key it cannot open.

**Apps do not choose providers.** Most apps never name a `CryptoConfig`, so the era
default has to be the SDK's, not a factory an app remembers to call.
`AtClientPreference.crypto` becomes nullable, where null means SDK-managed and a value
means the app has overridden it, and `AtClientImpl` resolves the effective config at init
by constructing the key ring itself. Today that wiring exists only in the e2e test, by
hand, after client creation, which is the boilerplate this removes.

An atSign whose `__manage` app never ran a final 3.x build cannot be shared with from a
4.x client. That surfaces as a distinct exception naming the recipient and namespace, plus
a pre-flight capability query, so an app can say that a peer has not upgraded rather than
reporting a generic encryption failure after the user has already done the work.

### 18.5 Enrollment approval no longer needs an atSign-level KEM

A joining enrollment used to encapsulate its `apkamSymmetricKey` to `pqpublickey`, since
at that moment it has no `_apsk` and no registered key package and the root was the only
thing it could reach. That is a real secret conveyance, so removing the KEM leaves a hole.

The direction reverses instead. `enroll:request` already carries the enrollee's X-Wing
key-package public half on its tail, so the **approver** generates `apkamSymmetricKey` and
encapsulates to that. No atSign-level KEM key needs to exist for enrollment either, which
is the point of the ruling rather than an exception to it.

The approver is encapsulating to a key that arrived on an unauthenticated request. That is
trust-on-first-use gated by a person approving a named device, which is what enrollment
already is, and it is no weaker than the flow it replaces.

### 18.6 Signing `_apsk` without changing who writes it

The atServer authors the `_apsk` record, populating
`public:_apsk.<enrollmentId>.<perEnrollmentApproved>@<atSign>` from the enrollment record
([section 12](#12-advertised-recipient-keys-are-signed-against-_apsk-2026-07-02)). A client
holding the root cannot attach a signature to a record it does not write, and the key
package is enrollment-internal and never published, so a cross-atSign verifier cannot
reach a signature parked there.

So the **value** changes rather than the authorship: `_apsk` becomes a root-signed envelope
instead of a bare key, and the approver puts that envelope in the enrollment record the
atServer already copies verbatim. No new server logic, no second record to fetch, and the
signature is produced at the one moment the root is already in use.

Every `_apsk` in the field today is a bare key, so a verifier accepts both shapes and reads
a bare one as unsigned, the same skip-what-you-cannot-verify posture `keys[].alg` uses.

### 18.7 When minting happens

**At client init, non-blocking, and resumable.** Minting cannot hang off a namespace's
first write: that is the promotion trigger
[section 13](#13-the-nskey-is-published-eagerly-mutable-and-generation-addressed-2026-08-02)
removed, because the key a sender needs is the recipient's and an atSign that only ever
receives in a namespace would never publish.

Publish-after-convey makes minting a short sequence rather than a single write: mint,
convey the private to the other privileged enrollments, then advertise. None of it can
complete offline, so the client checks persisted local state first, only touches the
network on the first launch, and never blocks startup. The in-progress state is persisted
so an interrupted attempt **resumes rather than re-generating** — a re-mint after a partial
publish is the split-key case, and for the immutable root it is unrecoverable.

An ordinary app that finds no root proceeds silently. It cannot create one, since only a
fully privileged enrollment may, and blocking would strand the user behind an app they may
not control. Data flows without a root; what an unanchored atSign lacks is a peer's ability
to verify whose key it is encapsulating to, which is SS-1c's concern and unimplemented
either way.

Privileged apps also mint when an app is **authorised** for a namespace, not only when one
runs, which closes the installed-but-never-launched gap.

**Which namespaces a client mints for** is the union of two sets: the namespace in
`AtClientPreference`, and the namespaces its enrollment holds **`rw`** on. The `rw`
condition is an authorisation constraint rather than a policy choice — the advertisement
is `public:__nskey.<ns>@<owner>`, a namespace-scoped public key, so only an enrollment
allowed to write that namespace can publish it. An enrollment with read access still needs
the nskey *private* to open inbound content keys, but it has no business minting the key
itself; another enrollment will.

A fully privileged enrollment holds `rw` on `*`, which is not an enumerable set, so it
resolves the wildcard through `enroll:listns` to the namespaces the atSign's enrollments
actually hold. It sweeps that list at init **and** mints on approval: the sweep catches
namespaces authorised before the upgrade, and the approval hook catches the ones granted
after. That is what makes a single `__manage` upgrade seed the whole atSign rather than
only the apps that happen to have been rebuilt, which is the property the 3.x rollout
depends on.

### 18.8 The limit this accepts

PQ sharing requires the recipient to have used or authorised the namespace. There is no
longer any way to seal to an atSign that has never touched it, because that is exactly what
the cold-start KEM did.

The invitation case therefore has no PQ answer: sending someone something in an app they
have never installed works in final 3.x only through the opt-in legacy fallback, and stops
working at 4.x. We should document that as a property rather than solve it by
reintroducing an atSign-level KEM under a different name.

---

## 19. Nested namespaces: the nskey is resolved by walking up (2026-08-03)

**Status:** accepted. Adds `appMetadata.ns` and `appMetadata.ckNs`, and moves the CK
conveyance record from the value's namespace to the resolved one. Supersedes the
"`appMetadata` carries no `ns` field" statement in
[design.md](design.md) section 1.5.

A namespace can nest — `d.c.b.a` — and the nskey data path scopes its keys, its content-key
cache, its HPKE `info` and its AAD by namespace. So a sender writing to
`someid.d.c.b.a@alice` has to decide *which* namespace's nskey to seal to, and both ends
have to agree on the answer. This section is that ruling.

### 19.1 The finding that reframed the question

`AtKey.fromString` splits a key at the **last** dot. `someid.d.c.b.a@alice` parses back as
`key = someid.d.c.b`, `namespace = a`: **a multi-segment namespace does not survive the
round trip.** The wire string is genuinely ambiguous about where the identifier ends and the
namespace begins, and nothing in it resolves that.

This was measured, not inferred — encrypting under `d.c.b.a` and reading with the key
re-parsed from its own wire string fails at the CK lookup (`content key … not yet available
for @alice:a`), and the AAD and HPKE `info` would disagree too.

**It has never mattered before.** `legacy_crypto_provider.dart` and
`legacy_encryption.dart` reference `namespace` **zero** times; the nskey providers reference
it 56 times. That is why AtCollection has composed nested namespaces for sub-collections all
along without trouble: nothing downstream of the split ever depended on it. The nskey data
path is the first thing that does, which makes the ambiguity newly critical rather than
newly introduced.

Every re-parsing path inherits it: sync pull, both notify directions,
`notification_service_impl`, and AtCollection's own key composition.

### 19.2 Exact-match resolution is not available

`AtCollection` composes a sub-collection's namespace as `<subName>.<parentId>.<namespace>`,
and `parentId` is a **per-item** id — so the namespace space below an app namespace is
unbounded and grows with every item, and sub-collections nest. Requiring an exact-match
nskey would mean an X-Wing keypair, a published advertisement and a private conveyed to
every enrollment **per item**. That is not a trade-off, it is a wall, and it would exclude
the SDK's flagship API from ever being post-quantum.

### 19.3 The ruling

**Resolution walks up, most-specific-first.** A sender writing to `someid.d.c.b.a@alice`
tries `d.c.b.a`, then `c.b.a`, then `b.a`, then `a`, and seals to the first nskey it finds.
If none exists that is cold start, and it fails as
[section 18](#18-pqpublickey-becomes-the-user-owned-signing-root-2026-08-03) requires.

The walk is safe because it mirrors the atServer's own authorisation rule — an enrollment
approved for `a` may access `d.c.b.a` (`SecretStore.namespaceAuthorizes`, and the server
rule it mirrors). Sealing to a *broader* key therefore cannot let an enrollment read
something the atServer would have withheld: the crypto gate never widens past the transport
gate. In the ordinary case the first hit **is** the app-namespace boundary, and the walk is
how a sender finds it — the only thing that tells an app namespace apart from an item id in
a composed key.

**The CK is scoped to the namespace where the nskey was found**, not to the value's own
namespace. One content key, and one `<ckKid>.__ck.<resolvedNs>@<owner>` conveyance record,
serves every item beneath it. This is what keeps AtCollection viable.

**Deeper keys are allowed.** An atSign may mint at `medical.notes` while holding a key at
`notes`, and most-specific-first means the deeper key wins. This is a real capability rather
than a hypothetical: authorisation is suffix-based, so an enrollment approved for `notes`
can already *fetch* `medical.notes` records — a tighter nskey is the only way to say
"authorised, but still cannot decrypt", with the server gate saying yes while the crypto
gate says no.

### 19.4 Cost, and the three lifetimes

`ensureCurrent` runs on every put, and each new AtCollection item produces a namespace
string never seen before, so a naive walk costs one round trip per level **per item,
forever** — the cache never warms, because the misses never repeat.

**A sender therefore remembers the levels it has found *empty*, and only those.**
A repeated write to the same namespace re-probes nothing; a namespace never seen before
still probes its own levels once.

**Remembering *hits* was tried first and is unsafe** — recorded here because it is the
obvious design and it is wrong. If a sender remembers "alice holds a key at `notes`", then
a later `y.medical.notes` matches that suffix and resolves straight to `notes` **without
ever probing `medical.notes`** — so a deeper key that existed all along is invisible, on a
cold path, permanently. That is not the bounded window
[19.4](#194-cost-and-the-three-lifetimes) accepts; it defeats most-specific-wins outright.
The asymmetry is the point: skipping a probe for a level we were just told is empty cannot
lose a key, while skipping one for a level we never asked about can. Caught by
`nskey_resolver_test`'s "a deeper key is never skipped because a broader one was seen".

**The real cost floor**, therefore: one probe per level of a namespace never seen before,
paid **once per namespace** rather than once per write. For an AtCollection sub-collection
that is two extra round trips the first time an item is written, and none thereafter. Zero
is not reachable while deeper keys are permitted
([19.3](#193-the-ruling)) — the probes that cost are exactly the probes that find them.

Stating the lifetimes once, because they are easy to conflate:

| # | What | Where | Bound |
|---|------|-------|-------|
| 1 | `advertisementTtl` — how long a fetched advertisement is reused before re-fetching | sender's memory | 15 min default |
| 2 | `advertisementStaleGrace` — how long past (1) a *failed* re-fetch may keep serving what it has | sender's memory | 15 min default |
| 3 | `missMemory` — how long a level found **empty** is not re-probed | sender's memory | 15 min, matching (1) |

There is **no TTL on the published record**: `nskeyAdvertisementKey` sets only
`isPublic = true`, so `public:__nskey.<ns>@<owner>` lives on the atServer until overwritten.
The only record-level ttl in the design is on `_nskeylock`, a different key.

**The accepted exposure.** A level probed and found empty stays empty to that sender for one
`missMemory` window, so a key minted at that level inside the window is missed and the write
seals to the broader one — letting exactly the enrollments the deeper key was minted to
exclude read it. This is *not* the same risk as rotation staleness: there a revocation event
lies behind it, whereas here the sender's own memory causes it. Accepted knowingly, without
a signalling flag on the parent advertisement, on the grounds that deeper keys are rare and
the window is short. Note this is strictly narrower than the exposure the rejected
remember-hits design carried, which had no bound at all for a namespace whose deeper level
was never probed.

### 19.5 The wire

`appMetadata` gains **`ns`** on every record of the nskey path: **the record's own full
namespace**. This is what makes a multi-segment namespace work at all — a reader can never
recover it from the key string ([section 19.1](#191-the-finding-that-reframed-the-question)),
so the record has to say. It is not a new disclosure: the namespace is already plaintext in
the key name. This supersedes design.md section 1.5's "carries no `ns` field", whose reason
was redundancy with the key name — a redundancy that never actually held.

A **data value** additionally carries **`ckNs`**: the namespace its content key and
conveyance live at. On a conveyance record the two are always equal, so they diverge only on
a data value, and only in two situations:

| Value | nskey at | `ns` | `ckNs` | |
|---|---|---|---|---|
| `phone.wavi@alice` | `wavi` | `wavi` | `wavi` | same |
| `phone.app_1.my_apps@alice` | `app_1.my_apps` | `app_1.my_apps` | `app_1.my_apps` | same |
| `x.medical.notes@alice` | `medical.notes` | `medical.notes` | `medical.notes` | same |
| `someid.__rr.item123.todos@alice` | `todos` | `__rr.item123.todos` | `todos` | **differ** |
| `x.medical.notes@alice`, stale sender | `medical.notes` | `medical.notes` | `notes` | **differ** |

So: every AtCollection sub-collection item, and the [19.4](#194-cost-and-the-three-lifetimes)
window.

**Neither field is derivable from the other.** `ns` cannot be recovered from `ckNs` plus the
key string — knowing the namespace ends in `todos` still leaves `todos`, `item123.todos` and
`__rr.item123.todos` as candidates. And `ckNs` cannot be re-derived by the reader walking its
own ring, because in the stale row the sender's view (the owner's *published* advertisements,
cached) and the reader's view (the owner's *held* privates) disagree: the reader would look
under `medical.notes`, the CK is under `notes`, and a perfectly intact record reports
"conveyance not yet synced" forever. Carrying `ckNs` is what degrades that case to "a broader
key was used" instead of "undecryptable".

**The AAD keeps binding the value's own namespace** (`ns`, not `ckNs`). Binding the resolved
namespace instead would give `someid` under `__rr.item1.todos` and `someid` under
`__rr.item999.todos` an identical AAD, reopening the record-relocation attack the AAD exists
to close.

### 19.6 Consequences

- `CryptoRuntime.isReadyFor` inherits the walk, so a recipient holding `todos` correctly
  reports ready for `x.y.todos`.
- A rotation of the `todos` nskey covers every namespace beneath it automatically, since
  they all resolve to `todos`.
- `NamespaceKeyUnavailableException` is raised only when the **whole walk** is exhausted.
- **This is a wire-format change, free only until a fleet seeds** — the same argument that
  applied to the AAD addition and the signed advertisement.
- **The functional and e2e suites use single-segment namespaces** (`wavi`, `e2e_test`),
  which is exactly why none of this surfaced. A multi-segment case belongs in both, or the
  design stays unit-only.
