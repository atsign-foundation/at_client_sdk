# decisions.md — the bodies

Every ruling's full text, live and superseded alike. **The ledger itself is
[`../decisions.md`](../decisions.md)** — a one-row-per-ruling index. This file
exists so that reading or grepping the ledger returns headlines rather than
several hundred lines of a decision you were not asking about.

**Ruling numbers are permanent.** They are cited from production dartdoc, from
the sibling docs and from `blockers.dart`, so a ruling is never renumbered and
never deleted — a superseded one keeps its body, because the reasoning is what
stops the rejected design being proposed again from scratch.

To add a ruling: append its body here **and** its row to the index. A guard
fails if either exists without the other.

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
- **One `nskey` keypair per (atSign, namespace)** — published **eagerly at mint**
  (the original lazy publication was superseded by
  [section 13](#13-the-nskey-is-published-eagerly-mutable-and-generation-addressed-2026-08-02));
  the former self/public nskey pair is collapsed to one ([section 11](#11-single-nskey-per-namespace-lazily-published-2026-06-30),
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
mint+request, RF-2c orchestration — *its former "readiness flip" deliverable was
removed with the readiness model,
[36](#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05)*) are in
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

- **Decision #1 — legacy-peer interop is opt-in.** ***Default REVERSED by
  [37](#37-legacy-key-material-is-retained-until-the-ecosystem-is-pq-not-the-atsign-2026-08-05)
  (2026-08-05):*** a new atSign now publishes its RSA `public:publickey` **by
  default**, and the `legacy-interop` flag is an early opt-*out*; a future release
  flips the default back. Original text: a new PQ-native atSign onboards PQ-only by
  default — no RSA `public:publickey` published; the flag (default OFF) opts in.
  (Drives ON-1, UC-B4.2.)
- **Decision #2 — PQ-readiness is marked per `(atSign, namespace)`.** ***SUPERSEDED
  by [36](#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05)
  (2026-08-05):*** there is no readiness marker and no flip — the rollout is the
  app's decision, made by which build it ships. Original text: the capability marker
  and the readiness flip are scoped to a namespace of an atSign, not the whole
  atSign; scheme selection is per-destination.
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
  facets of one substrate. (Drives UC-A2.x, UC-B5.1.) ***Status check 2026-08-05
  ([38](#38-key-material-self-heals-mint-if-absent-else-pull-2026-08-05)): the ruling
  stands, but neither the approve-time push nor the nskey pull had ever been wired to
  a caller — the self-heal work is what makes this decision true in code.***

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
  the field, and an atServer schema change (a separate repo per atServer implementation
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
- **#C — keep D1 GA off the auth retrofit (B-2 dep).** ***Partially INVERTED by
  [40](#40-rf-srv-is-the-mechanism-the-whole-model-stands-on-2026-08-05)
  (2026-08-05): RF-SRV — the retrofit's server half — is now ON the GA critical
  path, because "upgrade the enrollment" is the mechanism the app-decides model
  stands on. What survives of #C: B-2 still does not wait on the CLIENT
  retrofit orchestration (RF-2b/RF-2c).*** Original: B-2 needs RF-2 only for the
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
- **Readiness flip: operator-primary at GA, auto-detect fast-follow.**
  ***SUPERSEDED by
  [36](#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05)
  (2026-08-05): there is no readiness state, no flip and no auto-detect — the
  rollout is the app's decision, made by which build it ships.*** Original: R-1 ships
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
  Providers are injected **(`AtClient`, `AtKeysIo`)** — *corrected 2026-08-03: this line
  previously also listed `AtChops`, which never matched the code. `CryptoContext` is
  `{atClient, atKeysIo}` with no `atChops` field, and key state belongs in `AtKeys` held by
  an `AtKeysIo`; see [20.6](#206-atchops-is-not-a-key-holder).* There is
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
  ~~`KeyPartStatus` stays an enum (a closed state machine the format owns).~~
  **Reversed 2026-08-14 — see [97](#97-a-keyfile-status-a-build-has-never-seen-is-read-not-refused-2026-08-14).**
  It is an open `String` like the two above it. "A closed state machine the
  format owns" was true of the state machine and false of the *format*: the
  same paragraph requires unknown tokens to be re-emitted byte-identical, and
  an enum parsed through a throwing `expectEnum` cannot do that — it refused
  the whole document. The exception was carved for the field least able to
  afford it.
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
| **2026-07-06** | **Planning-day reconciliation rulings** (two): (1) **inter-server PQ authentication is IN D1 scope** as new project **IS-1** ([implementation-plan.md §13](../implementation-plan.md)) — the atServer FROM/POL X-Wing+ML-DSA-65 handshake (PR #2683), off the D1 GA critical path, gated on publishing the at_chops PQ-API surface (`XWingCert`/`resolveXWing`/`resolveMlDsa65`). (2) **P-2's `mldsa65` verify branch folds into the existing unpublished at_chops 3.4.0** (bumped on trunk by #2030) before it publishes — not a fresh minor. | Planning-day reconciliation of #1889 vs the plan vs merged/open PRs across at_client_sdk + at_server surfaced a whole untracked inter-server workstream and an at_chops 3.4.0 slot already opened on trunk; these two rulings place both in the record. |
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

**In brief:** *publication superseded by [13](#13-the-nskey-is-published-eagerly-mutable-and-generation-addressed-2026-08-02)*

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
[`design.md`](../design.md) → *Trust boundary & residual threats*.

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
   `{nskeyKid, publicKey}` — the shape as of this ruling; it became
   `{v, createdAt, keys:[…], suites}` under [section 94](#94-three-records-advertise-keys-and-only-one-of-them-speaks-the-vocabulary-2026-08-11)
   ruling 2, which changes nothing about the three points here — and is
   **overwritten** on rotation. Creation and rotation
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
  whenever they have never sent in it. *(Withdrawn by
  [18](#18-pqpublickey-becomes-the-user-owned-signing-root-2026-08-03): the root became
  a signing key, nothing encapsulates to it, and cold start now simply fails —
  `recipientKind` has exactly one member, `nskey`.)*
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

**Consequence for negotiation — the capability marker becomes a set.** ***REMOVED by
[36](#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05)
(2026-08-05): there is no capability marker — the rollout is the app's decision, and
the SDK never negotiates a scheme. The provider-id ruling in this entry stands in
full; only this marker consequence is dead.*** Original text: a boolean
"ready / not-ready" per `(atSign, namespace)` cannot express *which* schemes a fleet
supports, so it cannot survive a second PQ scheme. The B3 marker therefore advertises
the **set of provider ids** the fleet supports, and a writer picks the best id present
in **every** required reader's set. Ready/not-ready becomes the degenerate case —
"is the PQ pair in the set". This was R-1's to build — built 2026-08-05, examined
against the three-scenario model the same day, and removed.

**Timing.** Free now and expensive later: nothing has been written under the bare
`at/nskey`, so the rename costs a constant and a doc sweep. Once a record exists it
costs a migration.

**Implementation status.** The id and the family constant are **B-1b** (done). The
marker-as-a-set was **R-1**'s, and is removed with the marker
([36](#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05)).
Mechanics: `design.md` sections 1.2 and 1.5.


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

**In brief:** *supersedes the KEM role in [design.md](../design.md) section 1.4*

**Status:** accepted, supersedes the `pqpublickey`-as-KEM model throughout
[design.md](../design.md) section 1.4 and every site that describes a cold-start
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

> **Amended 2026-08-15 by
> [101](#101-the-signing-root-becomes-an-ordinary-signing-key-and-rotatable-2026-08-15).**
> The `keys` list stands and gets stronger — it becomes the `_apsk` entry shape,
> `{kid, use, alg, pub, status?}`, so the root is advertised in the same
> vocabulary as every other signing key. **`successor` is deleted rather than
> implemented:** stamped `null` at mint inside a record nothing rewrites, it
> could only ever have been a forward pointer writable when there was nothing to
> point at. What replaces it is the record becoming mutable, so a rotation adds
> an entry the way `_apsk` already does. The paragraph above also assumed the
> shape freezes fleet-wide at rollout; nothing is released, so it does not.

### 18.4 Cold-start, and the two-release upgrade path

With the root out of the key-transport business, cold-start has no PQ target. The ruling
is that it **fails**, and legacy RSA is reached only by explicit opt-in. Once an nskey is
available it is used from then on, forward-only; re-encrypting records already written
under the legacy fallback is an explicit migration (B-3's lazy re-encrypt — R-1
delivered no migration machinery,
[36](#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05))
and never a side effect of a `put`,
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
have never installed works only through the opt-in legacy fallback, which 4.x's
default (`disallowLegacyEncryption` true) disables — an app that deliberately
re-enables legacy writes re-opens it, per
[36](#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05)'s
app-decides rule. We should document that as a property rather than solve it by
reintroducing an atSign-level KEM under a different name.

---

## 19. Nested namespaces: the nskey is resolved by walking up (2026-08-03)

**In brief:** *adds `appMetadata.ns` / `ckNs`; supersedes the no-`ns` statement in [design.md](../design.md) section 1.5*

**Status:** accepted. Adds `appMetadata.ns` and `appMetadata.ckNs`, and moves the CK
conveyance record from the value's namespace to the resolved one. Supersedes the
"`appMetadata` carries no `ns` field" statement in
[design.md](../design.md) section 1.5.

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

---

## 20. SS-2: how the key package reaches an enrollment, and how conveyance fires (2026-08-03)

**In brief:** *resolves two blockers that made the SS-2 design unimplementable as written*

**Status:** accepted. Seven rulings scoping SS-2's client half. Two of them resolve blockers
that made the design as written **unimplementable**; both were found by reading the code, and
neither is visible to any test today because nothing yet joins the two ends.

### 20.1 Two blockers found before writing any code

**The signed key package claims an `enrollmentId` its signer cannot know.** `wrapAndSign`
stamps `envelope['enrollmentId'] = enrollmentId` (`envelope_signing.dart`), and that getter
falls back to `'primary'` when there is no enrollment. At `enroll:request` time there is
none — the **atServer** assigns it (`Uuid().v4()`, `enroll_verb_handler.dart`). The server
then stores the metadata **verbatim**, because it is opaque. So the stale `'primary'` claim
is frozen inside a signed blob that nobody can correct: not the enrollee (it signed too
early), not the server (correcting it breaks the signature), not the approver (it can only
verify). `VerbEnrollmentDirectory` rejects on claim ≠ record id — so **every** key package
riding `enroll:request` would be rejected, for every enrollment.

It is invisible today because the unit tests seed the directory with packages signed by an
*already-enrolled* sharer, where the claim always matches.

**The package must be signed by a key only at_auth holds, when no `AtClient` exists.** The
design has an at_client orchestrator building the package "above at_auth", with at_auth
ferrying it. But at `submit` time the enrollee has an `AtLookUp` and an `AtAuthSession` and
**no `AtClient`** — that is built afterwards, from the approved session. The APKAM keypair it
must sign with is generated *inside* at_auth (`at_enrollment_impl.dart`). `wrapAndSign` signs
via `atClient.atChops`, so there is neither a client to sign through nor a key to sign with at
the moment the package is needed.

### 20.2 The rulings

| # | Ruling |
|---|---|
| 1 | **Conveyance fires in at_client's `EnrollmentServiceImpl.approve`, and the other approve paths route through it.** `at_client_flutter` and `at_onboarding_cli` call at_auth's `approve` directly today; both already hold an `AtClient`. Leaving them would produce an enrollment that authenticates fine and can decrypt nothing, with nothing in the code saying so |
| 2 | **An absent key package is not an error; a rejected one is.** Absent is expected during rollout and for the self-retrofit path, which needs no conveyance. Rejected — wrong signer, bad signature, malformed — throws, so the approver learns the device cannot decrypt and can revoke. A *signed but unparseable* package is neither: the enrollee is running a newer client, the approver cannot fix it, and throwing would block approvals across a version skew |
| 3 | **`NamespaceMember` carries a four-way status: present / absent / rejected / unsupported.** `_verifiedKeyPackage` collapses five distinct outcomes into one `null`. The log severities already distinguish them; only the return type cannot. Ruling 2 is unimplementable without this |
| 4 | **The approver takes the key package from the request it is approving, not a `listns` re-fetch.** The atServer already returns `metadata` on `enroll:list`; at_client's `Enrollment.fromJSON` discards it. Reading it there removes a round trip *and* a real hole: conveyance discovery iterates the approved namespaces and skips `*`, so an enrollment granted `*` alone finds no key package and conveys nothing, warning only |
| 5 | **The `enrollmentId` claim is omitted when unknown, and an absent claim verifies.** Authority is the signature verifying against *that record's* `_apsk`, plus the server having bound the package to the record it created. A present-but-mismatched claim stays a hard rejection |
| 6 | **The `(AtClient, enrollmentId)` Expando re-key is deferred to RF-2b.** See [20.3](#203-what-the-expando-re-key-is-actually-worth) |
| 7 | **`AtEnrollmentRequest` gains a metadata-builder callback taking an `AtKeysIo`.** at_auth invokes it after generating the APKAM keypair and attaches the result to `EnrollVerbBuilder.metadata`, never inspecting it |

### 20.3 What the Expando re-key is actually worth

An `AtClient` is cached per atSign and reused (`AtClientImpl.create`), while
`AtLookupImpl.enrollmentId` is a public mutable field read live by `ApkamSigning`. So a
cached `AtClientSecretSharing` can outlive the enrollment it was built for, and
`myKeyPackage` then composes a **live** `enrollmentId` with a **cached** X-Wing public key.

This was first written up here as a cross-enrollment key confusion. **That was wrong**, and
the correction is worth recording so it is not re-argued: the instance still holds the seed
matching the key it advertises, so anything sealed to it opens, and nobody gains access they
did not already have. The seed is not bound to the enrollment at all.

What remains is **liveness**: the stale instance's `kpid` is the old one, so `startListening`
watches the old envelope addresses and the new enrollment silently receives nothing. And it
needs the enrollment to change under a live `AtClient` — not ordinary app behaviour, since an
app is one enrollment fixed by the `.atKeys` it authenticated with. The one flow that does it
is the **RF-2b self-retrofit**. Recorded against RF-2b rather than churning a published
experimental surface for a case SS-2 never reaches.

### 20.4 Consequences

- **Ruling 7 moves `AtKeys` construction earlier in at_auth.** Everything but `enrollmentId`
  is available before the request is sent; only that one field needs the response. The
  callback therefore receives keys with **no** `enrollmentId` — so ruling 5 is not merely the
  tidier option, it is forced by the order of operations. The two agree, which is
  corroboration rather than coincidence.
- **`enroll:listns` loses its production caller in SS-2** (ruling 4). Its first one becomes
  `pushSecretToNamespaceMembers` at nskey mint, in **SS-4**. The verify path stays
  unit-covered, and a live test can still drive the verb directly.
- **`EnrollVerbBuilder.metadata` already exists** and drops an empty map before the wire, so
  the passthrough is an attach, not a grammar change. There is **no atServer schema work in
  SS-2** — that watch-out was inherited from SS-1b, where it was true.
- **Rulings 1 and 4 touch published surfaces**: `Enrollment` gains `metadata`,
  `NamespaceMember` gains a status, `AtEnrollmentRequest` gains a callback. All additive; the
  at_auth one lands on its own publish gate.

### 20.5 Scope boundaries and versioning

| # | Ruling |
|---|---|
| 8 | **The atServer's `mldsa65` verify branch stays in SS-3, with its record-authoritative sibling.** `_getSigningAlgoType` branches on `ecc` and `rsa2048` and falls through to `rsa2048` for everything else, so a PQ APKAM would be verified as RSA and fail. But that method also reads the *client-supplied* algo rather than the stored one, and fixing both at once is one change to one method — splitting them means touching it twice and living with a window where a client selects its own verification algorithm. Nothing in SS-2's client half authenticates with an ML-DSA APKAM. Needs parity across every atServer implementation in the same sweep |
| 9 | **at_auth opens 3.4.0 before the work starts.** Verified against pub.dev 2026-08-03: at_auth 3.3.0 is **published**, so unlike at_commons, at_chops and at_client it has no in-progress heading to fold into. Ruling 7's callback is additive and optional, so a minor. at_client's floor rises to `^3.4.0` in the same commit as the first use |
| 10 | **The whole chain gets a live functional test with a real second enrollment.** Key package rides `enroll:request` → the server stores it → approve → `listns` returns it → the signature verifies against the server-published `_apsk` → conveyance seals to it. `at_functional_test`'s `enrollment_test.dart` already drives live `getOTP` / `submit` / `approve` against `apkamFirstAtSign`, so the harness exists. This is the test that would have caught [20.1](#201-two-blockers-found-before-writing-any-code)'s first blocker |

**Why ruling 10 is not optional.** Ruling 4 removes `enroll:listns` from the production
conveyance path, so its first production caller is now SS-4. Without a live test the verify
path would stay unit-only for another whole project — and its unit fixtures seed packages
signed by an already-enrolled sharer, which is precisely the shape that hides the blocker.

### 20.6 `AtChops` is not a key holder

**Status:** accepted 2026-08-03. `AtChops` is being reduced to a collection of **stateless**
functions; key state lives in `AtKeys`, held by an `AtKeysIo`. Anything that reaches into an
`AtChops` *object* for key material is on the wrong side of that line.

A sweep of this branch found the new code clean and the foundation it stands on not:

- **Nothing new reaches for `AtChops` in production.** Every added reference on the branch is
  in one test file's mock setup. `CryptoContext` is `{atClient, atKeysIo}` with **no**
  `atChops` field, so the D1 provider seam was already right.
- **Two mixins are the whole problem.** `ApkamSigning`'s `publicSigningKey` /
  `privateSigningKey` read `atClient.atChops!.atChopsKeys.atPkamKeyPair!` — pulling key state
  out of `AtChops` — and `EnvelopeSigning` signs and verifies through `atChops!.sign` /
  `.verify`. Five D1 features now depend on those four lines: `PublishedNskeyKeyRing`,
  `AtClientEnvelopeSigner`, `KeyPackageRegistration.signedKeyPackagePayload`,
  `VerbEnrollmentDirectory`, and `PairwiseSecretSharing`. The branch did not create the
  dependency, but it added five consumers to it.

**Ruling.** Signing and verification are factored to take key material directly, sourced from
`AtKeys` via `AtKeysIo`, and both mixins move onto it — migrating all five consumers in one
pass rather than leaving two shapes side by side.

**This is not optional for SS-2.** Ruling 7's callback takes an `AtKeysIo` and runs when there
is no `AtClient` at all, so it cannot use `wrapAndSign` as written. The extraction is the
first thing the callback needs; doing the mixins with it is what stops the old shape spreading.

**Out of scope:** `put_request_transformer` and `monitor` also sign through `atChops`. Both
predate D1 and neither is on this path; migrating them would put the put and monitor paths in
scope, which pulls the integration suite into every commit boundary for no D1 benefit.

---

## 21. SS-3: where key material lives, and what the substrate stops storing (2026-08-03)

**In brief:** *removes SS-3's durable `SecretStorePersistence` backend rather than building it*

**Status:** accepted. Six rulings. Between them they **remove SS-3's largest listed
deliverable** — a durable `SecretStorePersistence` backend — rather than build it.

### 21.1 What the plan asked for versus what is there

Three findings, all checked against the code rather than the docs:

- **"The enrollment record keeps a single `apkamPublicKey`" is already true.**
  `enroll_datastore_value.dart` declares `late String apkamPublicKey`, not a list, and
  `signingAlgo` already sits beside it carrying the dartdoc "Recorded so PKAM verification
  can be record-authoritative." Nothing to do.
- **`SecretStorePersistence` has no production implementation anywhere** — two test fakes
  and nothing else — and it appears **zero times** in both design.md and acceptance.md. The
  one-line plan entry was its entire specification.
- **Content keys are genuinely a cache.** `SymmetricAesGcmProvider.decrypt` falls back to
  re-fetching the `<ckKid>.__ck.<ckNs>@<owner>` conveyance record and re-opening it with the
  nskey private. Losing the CK cache costs a round trip, not data — so the owed-item claim
  that a restart leaves the owner unable to re-read her own records is **wrong for CKs**. It
  is right for the nskey private, which is what ruling 1 addresses.

### 21.2 The rulings

| # | Ruling |
|---|---|
| 1 | **An nskey private lives in `AtKeys`, filed on arrival.** "Conveyed as a Secret" says how it travels, not where it lives — the APKAM key package already arrives one way and is filed another. Losing an nskey private makes every conveyance record sealed to it unopenable, so it belongs under `AtKeysIo`'s never-lose contract, alongside durable at-rest-protected implementations that already exist |
| 2 | **The sender persists the current `ckKid`, never the key.** On a cold write it re-fetches that CK from its own conveyance record, exactly as the read path already does. A `ckKid` is not secret, so this needs no at-rest protection at all and sidesteps durable key storage entirely |
| 3 | **The crypto layer subscribes to `receivedSecrets` and files its own material; `SecretStore` stays in-memory.** The substrate keeps moving opaque secrets and `putIfNewer` stays the convergence point. No app-supplied backend then ever holds this atSign's namespace private keys — which it silently would have, with whatever at-rest properties that app happened to have |
| 4 | **The APKAM path reads the record's `signingAlgo`; legacy PKAM keeps the wire value; `mldsa65` gets its branch.** Legacy PKAM has no enrollment record to be authoritative about, and may legitimately present `ecc_secp256r1` |
| 5 | **Jitter, then suppress on any observed answer** ([21.4](#214-what-the-anti-storm-cap-actually-protects)) |
| 6 | **The current-`ckKid` pointer is an ordinary synced self key**, so an atSign's devices converge on one CK per `(recipient, namespace)` — which is what a CK is scoped to — instead of one per device. Concurrent mints are benign: both CKs are valid and readers open either |

### 21.3 Why record-authoritative verification is hardening, not a fix

Worth stating plainly so it is not oversold. The signature is checked against the **stored
public key** on both paths, so a client that lies about its algorithm only causes its own
verification to fail — claiming `rsa2048` against an ML-DSA key does not verify, so there is
no downgrade to be had. What it defends against is cross-algorithm confusion, where one key
blob parses under two algorithms. The functionally necessary half is the `mldsa65` branch:
without it `_getSigningAlgoType` falls through to `rsa2048` for every unrecognised value, so
a PQ APKAM cannot authenticate at all.

### 21.4 What the anti-storm cap actually protects

`requestAnswerMinInterval` is keyed `'<requesterKpid>:<secretName>'` in **each responder's
own** memory. It stops one responder repeating itself; it does nothing about N responders
answering the same request at once, which is the actual thundering herd. Of the design's
three mechanisms only `putIfNewer` dedup exists — making duplicates correct, but not cheap:
N holders means N seals and N writes per request.

Suppression can only ever be **coarse**: the envelope key is
`<msgId>.<requesterKpid>.__ssenv.<ns>`, carrying no secret name, and its payload is sealed to
the requester. A responder can see *that* someone answered, not *what* they answered.

That turns out to be sound rather than approximate, for a non-obvious reason: a responder
answers **every** matching secret in one pass, so any single answer is already complete for
that request. "Someone answered this requester in this namespace since the request" is
therefore a correct suppression signal.

### 21.5 Ruling 4, as built

Landed in `at_server` on `gkc-pq-ss3-signing-algo`: the `mldsa65` branch, and an
APKAM-authenticated connection taking its algorithm from the enrollment record rather than
from the wire. Legacy PKAM keeps the wire value — and that is not merely conservative. The
functional suite authenticates over the legacy path with an **`ecc_secp256r1`** key, so
pinning legacy to `rsa2048`, which is what I first recommended, would have broken working
behaviour rather than tightened anything.

**Parity is owed from the other atServer implementations before a PQ client can rely on
this.** At least one rejects `signingAlgo:mldsa65` while *parsing* the command, so a PQ
client meets an invalid-syntax error rather than an authentication failure — a confusing
failure mode for the thing hardest to debug. That implementation already stores `signingAlgo`
on its enrollment record but never reads it for verification, and carries no ML-DSA support
to add a branch to yet, so parity there is a dependency decision rather than an edit.

### 21.6 A defect found while reading

`putSecret` mutates the map and then `await persistence?.save(listSecrets())`, with nothing
serialising the saves. Two concurrent puts each snapshot and then land in either order, so
the store can persist an **older** snapshot after a newer one and silently lose a secret. In
-memory fakes never show it; any real async backend will. Ruling 3 means the SDK ships no
such backend, but the seam stays public, so the saves are serialised regardless.

---

## 22. SS-4: when a namespace key is minted, and what must be true first (2026-08-03)

**In brief:** *mint at init, publish once the private is durable; builds the signing chain but defers the APKAM keypair swap*

**Status:** accepted. Six rulings. One of them **defers the signing root out of SS-4**, which is
most of what made the project XL.

### 22.1 The rulings

| # | Ruling |
|---|---|
| 1 | **Publish the public half once the private is durable locally — not once it is conveyed.** The ledger's "publish-after-convey, never before" is unachievable as written: at mint there may be no other enrollment, and one enrolling later needs the private conveyed *then* anyway, so "conveyed to all" is never a stable state to gate on. Durability is the achievable invariant, and it is the one that matters: a crash after publishing must not strand a key nobody can open |
| 2 | **Take the mint lock with a remote-first immutable create.** Its atomicity is the atServer refusing a second write to an immutable record (`abstract_update_verb_handler`: *"Immutable records may not be updated"*), so a local-first put would let both enrollments believe they won and collide only at sync. The loser does **not** wait: it re-reads the advertisement and, if one now exists, adopts it and waits for the private over the substrate. Release by force-delete — deleting an immutable record needs `force:` — with the short ttl as the crash backstop |
| 3 | **The signing chain is built; only the APKAM keypair's *algorithm* is deferred.** The root and the chain are in scope; APKAM keypairs stay **RSA** for now, because migrating `_apsk` has complications that need thinking through first. See [22.2](#222-the-signing-root-chain-follows-the-approval-graph) |
| 4 | **Conveyance reads the filed privates from `AtKeys`, not the `SecretStore`.** Otherwise a real hole: `shareAllSecretsWith` iterates `secretStore.listSecrets()`, and [decisions.md 21](#21-ss-3-where-key-material-lives-and-what-the-substrate-stops-storing-2026-08-03) ruling 3 keeps that store in-memory — so after a restart an approver would convey **nothing** to a newly approved enrollment, including the nskey private without which it can read nothing at all. One durable home, and the sender reads from it |
| 5 | **Mint at client init, for every namespace the client is authorised for.** Not on first write: the 3.x rebuild-and-rollout mints and publishes *while still writing legacy*, so the fleet seeds before the PQ flag flips anywhere. It is also what makes the sender-side rule honest — if a recipient has ever run a PQ-capable client for a namespace, the key is there |
| 6 | **Legacy PKAM mints for `preference.namespace`; a `*` enrollment mints nothing at init.** Legacy clients hold no enrollment record and can name exactly one namespace — and they are most of the fleet during the rollout, so that is where seeding coverage actually comes from. `*` is not enumerable, so a wildcard enrollment mints on demand when it writes into a specific namespace instead; conveyance discovery already skips `*` for the same reason |

### 22.2 The signing root: chain follows the approval graph

The chain is **not** fixed-depth, and not "root signs every `_apsk`". It follows **who approved
whom**: the root signs enrollment E2's signing key; E2 holds `__manage` (but not `*`) so it may
approve enrollments; E2 then signs E3's signing key. The trust edge is the approval edge, which is
the relationship that already exists.

The signature rides **`_apsk`'s `appMetadata`**, so the record's value stays a bare key and every
existing verifier is undisturbed — the same additive shape used elsewhere.

**What is deferred is narrower than it first looks, and the distinction matters.** The chain is
built. What waits is changing the **APKAM keypair itself** from RSA to ML-DSA, because migrating
`_apsk` carries complications worth thinking through before committing to them.

The two are separable precisely because the root signs an enrollment's *public key* whatever
algorithm that key happens to be. So the chain can be built now over today's RSA APKAM keys, and
the APKAM algorithm swapped later without the chain changing at all. Note also that the root is
ML-DSA-65 regardless — it is a new key with no migration story of its own, which is why it does not
have to wait.

### 22.2b Publishing a chain signature: the parent signs, the child publishes

A conflict the chain model has to resolve, found by reading the two ends together. In the
approval-graph chain **E2 signs E3's key** — but `_apsk` writes are restricted to *the owning
enrollment's own* authenticated connection. The signer is the parent; the only permitted writer is
the child.

**Ruling 7: the parent conveys the signature and the child publishes it.** The approver signs the
child's APKAM public key and sends the signature over the substrate — the conveyance that already
fires at approval — and the child writes it onto its own `_apsk`'s `appMetadata` on first run. No
atServer change, and no widening of who may write a record whose entire purpose is to be one
enrollment's authenticated identity.

Until the child runs, verifiers see a bare key. The transition rule already tolerates exactly that:
an unsigned `_apsk` is accepted during the changeover.

Checked rather than assumed: the atServer writes `_apsk` in exactly two places — at first-enrollment
creation and on **approve** — not on every authenticated use, so it will not clobber the
`appMetadata` the child adds afterwards.

### 22.2c Revocation: the chain inherits what the atServer already does

**Ruling 8: a revoked signer breaks the chain below it, and the chain does not work around
that.**

This was ruled on a corrected reading. The first pass concluded revocation was non-retroactive,
because `revoke` appeared only to set the record's state and drop live connections. It does more:
`updateEnrollmentStatus` calls `movePerEnrollmentData(enId, to: perEnrollmentRevoked)`, which
rewrites **every** per-enrollment key from `<enId>.a.__e@` to `<enId>.r.__e@` — `_apsk` included.

So a verifier fetching `public:_apsk.<enId>.a.__e@alice` for a revoked enrollment finds *nothing*.
Verification already fails, not by policy but because the key moved out from under the address the
verifier looks up. The chain inherits that rather than inventing a second, conflicting meaning for
revocation — and it is reversible, since `unrevoke` moves the data back.

Consequences worth stating rather than discovering later:

- **Revoking an admin enrollment breaks the chain for everything it vouched for**, until those are
  re-vouched or it is unrevoked. That is a real cost, and it is the cost of revocation meaning one
  thing rather than two.
- Reading the revoked location to rescue past signatures was rejected: the atServer moved the key
  precisely to take it out of the approved set, and a verifier that looks there anyway is
  overriding the only revocation signal there is.

### 22.3 What this leaves SS-4

Mint (locked, init-triggered, durable-before-publish); convey the private per-APKAM as a `Secret` —
the producer for `NskeyPrivateFiling`'s `__nskey.<nskeyKid>` contract from
[21](#21-ss-3-where-key-material-lives-and-what-the-substrate-stops-storing-2026-08-03); the
public/private correspondence check; and the signing root with its approval-graph chain, published
into `_apsk`'s `appMetadata`.

Out of scope: changing APKAM keypairs to ML-DSA, and the key-transparency publication mechanics
(when a root is submitted, and what a client does if the log is unreachable at mint), which remain
un-grilled.

---

## 23. UC-A2.1: reversing the enrollment key exchange (2026-08-04)

**Status:** accepted and built. Removes the last RSA wrap from the enrollment path —
[at_server 0016b3e8](https://github.com/atsign-foundation/at_server), at_auth `84f93af70`,
at_client `910288065`.

> ⚠️ **"Built" is not "merged", re-derived 2026-08-15.** at_server `0016b3e8` is
> **not an ancestor of `origin/trunk`** — it sits on the branch
> `gkc-pq-ss3-signing-algo`. Its siblings in this same status line, `16dd457f`
> and `6a86fbcc`, both ARE merged, which is precisely why the row reads as
> though all three landed. Re-derive rather than trust:
> `git -C ~/dev/atsign/repos/at_server merge-base --is-ancestor 0016b3e8 origin/trunk`.

### 23.1 What A2.1 actually objected to

The enrollee generated `apkamSymmetricKey`, RSA-encrypted it to the atSign's long-lived
default encryption public key, and sent it on `enroll:request`
(`at_enrollment_impl.dart`). The approver unwrapped it and wrapped the encryption private
key and the self-encryption key under it. So one RSA wrap protects the whole enrollment,
and an adversary recording the request keeps it until a quantum computer opens it.

Reversing the direction — the approver mints the key and encapsulates it to the key
package the request advertised — is the fix. The corrected reading matters here: this is
a **key transport** problem, so it is the one place a KEM genuinely belongs, unlike the
FROM/POL and PKAM handshakes, which were pared back to a signature swap precisely because
they convey no secret.

### 23.2 The rulings

| # | Ruling |
|---|---|
| 1 | **Delivery rides the secret-sharing substrate**, not a new `enroll:approve` field. `shareSecretWith(KeyPackage, Secret)` already seals to an advertised package and writes a remote-first envelope; the enrollee opens it with the key package private half it minted *before* sending the request, so it depends on nothing it is still trying to obtain |
| 2 | **A direct per-enrollment write was rejected because the atServer forbids it.** `abstract_verb_handler.dart` `isForeignPerEnrollmentReservedKey` denies any enrollment writing a non-`public:` key into another enrollment's `<id>.a.__e` namespace, wildcard `*:rw` included. Only `public:` is exempt — which is how `public:_apsk.<id>.a.__e@` works, and is not a route for a KEM ciphertext we would rather not publish |
| 3 | **The atServer's mandatory `encryptedAPKAMSymmetricKey` yields only to an advertised key package.** It stays mandatory otherwise, so a client sending neither a wrapped key nor a package fails at validation rather than enrolling into a state it cannot decrypt |
| 4 | **Mode is explicit — `EnrollmentKeyExchangeMode {legacy, pq}` — and is *not* inferred from whether a key package is advertised.** SS-2 advertises a package in every mode, because a package is also how an approver seals this atSign's existing secrets to a new device. Inferring `pq` from its presence would have silently moved every existing SS-2 enrollment onto a path no published approver can complete |
| 5 | **Default stays `legacy`; it flips to `pq` in the next at_auth major.** Existing callers keep their wire bytes while the atServer relaxation is unpublished and parity outstanding |
| 6 | **A `pq` request missing its package or its resolver is refused before it reaches the atServer.** Both otherwise produce an enrollment that authenticates and then decrypts nothing — the failure mode with no diagnostic attached |
| 7 | **The approver decides from the record's *absent* wrapped key, read before approving.** That is the only unambiguous signal, and it is only visible while the record is still the one the enrollee wrote |
| 8 | **The enrollee verifies the envelope's APKAM signature against the signer's `_apsk` before opening it.** The key package is public, so anyone can seal to it; without the check an attacker injects a symmetric key of their choosing and the enrollment unwraps its own encryption private key into garbage. A revoked signer needs no separate case — [22's ruling 8](#22-ss-4-when-a-namespace-key-is-minted-and-what-must-be-true-first-2026-08-03) established that the atServer moves its `_apsk` out from under the address a verifier reads, so verification fails of its own accord |
| 9 | **The approver must already hold a key package; `approve` refuses rather than registering one for it.** Sealing stamps the approver's own kpid, so conveyance needs one — but registering *publishes* a package and, with no persistence wired, mints a fresh seed. An implicit call could therefore rotate the advertised package underneath the approver and orphan anything already sealed to the old one. When to mint is the caller's decision; `approve` only makes the requirement legible instead of letting a bare `Bad state` surface from three frames down |

### 23.3 Two traps found by reading the code

**`AtKeys.toAtChops` branches on the symmetric key to tell APKAM keys from PKAM keys.** A
`pq` enrollment holds none at `waitForApproval`, so it was read as PKAM and then asked for
the `defaultEncryptionPrivateKey` it is authenticating *in order to fetch* — an error
naming the wrong thing entirely. PKAM needs only the APKAM keypair, so those chops are now
built directly and the symmetric key filled in on arrival.

**The request leg, not just the return leg, had to change.** The first pass concluded the
whole reversal was client-only, having checked only how the approver's answer gets back.
The atServer's `_validateParams` makes `encryptedAPKAMSymmetricKey` mandatory on any
OTP-bearing `enroll:request`, so an enrollee that stops wrapping cannot send a valid
request at all. Recorded because the wrong conclusion was reached confidently and from
real evidence — the evidence was simply half the path.

### 23.4 What the live coverage does and does not prove

`enrollment_pq_key_exchange_e2e_test.dart` drives the whole chain against a live atServer:
the request reaches it with no RSA-wrapped key, approval mints one, and the enrollee
recovers it **over its own PKAM-authenticated connection**, scoped to the single namespace
it was granted. That last part matters — running the resolver from the approver's
connection would have proved the envelope authentic and openable while saying nothing
about whether the atServer lets the enrolling connection scan for and read it, which is
the link that would fail in production with the test still green.

Not covered: the approver's own key package registration is asserted by a guard rather
than exercised in both states by a unit test.

**The poll timeout is not a latency budget, and sizing it as one was a mistake worth
recording.** It never waits for the human — by the time the resolver runs, the PKAM loop
has already succeeded, so the approval has happened, however long that took. What is left
is a mechanical race inside the approver's single `approve()` call: the atServer marks the
enrollment approved, which is what lets PKAM start succeeding, a moment before at_client
finishes writing the envelope. 30s is headroom over one or two round trips. If nothing has
arrived by then the approver did not convey, and waiting longer recovers nothing.

**Still owed:** the functional rails point at a locally built image and must be reverted
before any client PR, and the new test cannot pass against `vip` until the atServer
relaxation is promoted.

---

## 24. How the approval chain terminates at the root (2026-08-04)

**Status:** accepted. Settles the question [22's owed list](#22-ss-4-when-a-namespace-key-is-minted-and-what-must-be-true-first-2026-08-03)
left open as *"what the signing root signs beyond `_apsk`"*. The enrollment-to-enrollment
link is built ([23](#23-uc-a21-reversing-the-enrollment-key-exchange-2026-08-04) is its
sibling ruling on conveyance); this is what the walk climbs *to*.

[18.1](#18-pqpublickey-becomes-the-user-owned-signing-root-2026-08-03) already states the
shape — *root → key package → `_apsk` → advertised keys* — but not how a verifier knows it
has arrived.

### 24.1 Two things the design does not get to choose

**The root link cannot be verified the way every other link is.** An enrollment link is an
RSA APKAM signature resolved from that enrollment's `_apsk`. The root is ML-DSA-65 resolved
from `public:pq_signing_root@<atSign>`. Different algorithm, different key source, different
lookup. It is not "another link with a different signer", and code that models it as one is
wrong before it is written.

**Chains deeper than one hop genuinely exist.** Approving needs `__manage`; holding the root
needs `rw` on `*` **and** `__manage` ([18.2](#18-pqpublickey-becomes-the-user-owned-signing-root-2026-08-03)).
So an approver that cannot produce a root signature is an ordinary configuration, not an
edge case, and the walk must climb.

### 24.2 The rulings

| # | Ruling |
|---|---|
| 1 | **A root link lives in its own `appMetadata` field** (`apskRootLink`), beside `apskChainLink`. A verifier looks for it first and never disambiguates: the field name already determines which algorithm to verify with and where the key comes from. A discriminator inside one field would make one shape mean two things, and the two are not variants of each other — see [24.1](#241-two-things-the-design-does-not-get-to-choose) |
| 2 | **The root signs every *fully privileged* enrollment's `_apsk`** — exactly the set that holds the root private, so exactly the set that could produce such a signature anyway. Not one anchor: [22's ruling 8](#22-ss-4-when-a-namespace-key-is-minted-and-what-must-be-true-first-2026-08-03) makes a revoked signer break the chain below it, so a single anchor means one revocation leaves every enrollment on the atSign unanchored until a holder re-signs. Redundancy here is cheap and the failure it prevents is total |
| 3 | **The walk returns a graded result, not a boolean:** anchored to root / chained but unanchored / unsigned. A bare `_apsk` is explicitly tolerated during the changeover, so a boolean forces every caller either to reject enrollments that are valid today or to lose the distinction that will matter once the changeover ends. The caller owns the policy; the walk reports what it found |
| 4 | **Root links are self-signed, never conveyed.** [18.2](#18-pqpublickey-becomes-the-user-owned-signing-root-2026-08-03) already puts the root *private* in every fully privileged enrollment, and by ruling 2 those are exactly the enrollments that get a root link — so each can sign its own, and `_apsk`'s writes-only-from-its-own-connection rule stops being an obstacle rather than needing to be worked around. **This corrects the ruling as first written**, which specified the parent-signs/child-publishes conveyance of [23](#23-uc-a21-reversing-the-enrollment-key-exchange-2026-08-04) for a case self-signing simply does not have |
| 5 | **A holder signs at mint, and every start re-checks.** The minter signs itself at mint, holding both the private and its own record at that moment. Every start then fills any gap, and that is what makes the retro case work without a migration: an enrollment that was privileged *before* the root existed anchors itself the next time it runs. One rule covers the minter, a privileged peer that predates the root, one approved after it, one approved by a non-root-holding approver, and a root minted late |

### 24.3 No atSign is bound into a link payload, and why that is safe

Considered and rejected as unnecessary rather than overlooked. A link lifted from alice and
stamped onto bob's record is verified against **bob's** `_apsk` or **bob's** root, so a
signature made under alice's keys fails there. Cross-atSign replay is already closed by
where the verifier looks, and a field asserting what the lookup already establishes would
be decoration that later reads as load-bearing.

### 24.4 Built since, and what is still owed

Both of the gaps this section first recorded are closed, and are kept here rather than
deleted because each was the reason a ruling above reads as it does.

~~*Self-signing reaches only the minter until the root private is conveyed.*~~ **Built.** A
fully privileged enrollment is conveyed the private at approval — under a per-enrollment name,
so `shareAllSecretsWith` cannot forward it to a namespace-scoped peer — and files it into
`AtKeys` at start. Live-covered, including the check that the atServer really grants
`*` + `__manage`, without which the privilege gate would have been tested against two
identical cases.

~~*A privilege re-check belongs on the self-sign path.*~~ **Built**, and the ordering turned
out to matter: possession is checked **before** privilege, because reading the private is a
local `AtKeys` read while establishing privilege costs a round trip. Checking privilege first
would make every client at every start pay for a question almost none of them can act on.
Holding the private is still not sufficient — the granted namespaces decide.

**Key-transparency publication mechanics remain un-grilled** (when a root is submitted, and
what a client does if the log is unreachable at mint). Out of scope here: it concerns what
the root *is*, not how a chain terminates at it. **Parked 2026-08-04 until D1 is complete**
— it is a design thread with no code and no D1 dependency, and the signing root already
carries `{v, keys[], successor}` so a log can anchor it later without a record change. It is
not on the critical path and should not be read as blocking SS-4.

---

## 25. The substrate's arrival path had never run (2026-08-04)

Filing a conveyed nskey private into `AtKeys` was on the ledger as one missing call:
`NskeyPrivateFiling.start` subscribes to `receivedSecrets`, and nothing subscribed it. The
prescribed fix was to give it the shape `PqSigningRoot.filePendingPrivate` already used — a
store check at client start, with no lifecycle to own.

That fix would have been inert, and the investigation is worth recording because the shape of
the mistake recurs: **the working model held up for copying was not working either.**

### 25.1 Three defects, each hiding the next

`SecretStore` is a plain in-memory map. Its only populator is `PairwiseSecretSharing.sweepOnce`,
and no production code in `at_client` called `sweepOnce` or `startListening` — the only
non-test callers were inside `pairwise_secret_sharing.dart` itself. `restore()` runs only
against an app-supplied persistence hook. So at client start that store is empty, and
`filePendingPrivate` had been filing nothing since it was written.

One layer lower: `KeyPackageRegistration.register()` generates a fresh X-Wing keypair unless
`loadApkamKeys` is supplied, and that hook was wired only in tests. A running client's `kpid`
was therefore a per-process value, while a sender addresses an envelope to the kpid it read
from the enrollment record. Sweeping would have scanned an address nobody writes to.

The private half of the advertised package was in `AtKeys` the whole time —
`enrollmentKeyPackageBuilder` files both halves there under `keyId == kpid` at enrollment. The
client simply never looked.

### 25.2 What was built

`collectConveyedKeyMaterial` runs at client start, gated on the client having an `AtKeysIo`
— without a keyfile there is nowhere to file anything, so a legacy client does none of this
work. It binds, sweeps, then files, in that order because each step depends on the one before.

`bindKeyPackageToAtKeys` distinguishes the key package from an nskey private by the matching
`publicEncapsulation` entry under the same `keyId`: both are X-Wing `privateDecapsulation`
material, and a client that adopted an nskey private as its recipient identity would lose the
ability to open anything addressed to it. Adoption only: a keyfile holding no package is left
untouched. Generating one and filing it was built first and then removed — a package is
discovered from the enrollment record, it rides `enroll:request`, and there is no
post-enrollment write path, so a locally generated one is an address no sender can learn. It
bought nothing and cost a startup write to the user's keyfile, which the functional pack caught
by showing a committed test keyfile as modified.

`NskeyPrivateFiling.start`/`stop` are deleted in favour of `filePending`. The correspondence
check the class describes is now wired for the first time, against the *current* advertised
generation only: an older conveyed generation reads as "no opinion" rather than a rejection,
which is the semantics the filer already had for an absent public half.

### 25.3 Two consequences, stated rather than discovered later

The sweep consumes and **deletes** the envelopes it finds, so an app subscribing to
`receivedSecrets` after constructing its client sees no arrival event for anything that was
waiting at start. The secret is in the store, which is where `waitForSecret` looks first, so
the pull flow is unaffected — but a listener-only app is not.

`register()` publishes `_apsk`, so this adds one publish and one remote scan to the start of
every client that carries an `AtKeysIo`. For an enrollment the atServer already publishes
`_apsk` on approval, so the write is redundant; for a legacy PKAM client it is how peers verify
its envelopes at all.

### 25.4 The rule this is an instance of

A ledger entry that names both the defect and its fix has already done the diagnosis, and
invites implementing the fix without redoing it. Here the diagnosis was right about the symptom
and wrong about the depth. The cheap check that caught it was asking what would actually be in
the store at the moment the prescribed code read it — a question the entry did not raise
because the model it cited appeared to answer it.

---

## 26. UC-A4.4: a conveyance that loses the race to its own announcement (2026-08-04)

The two-client harness of `ConcurrentClients` gave the notify **receive** path its first live
coverage, and the first thing it found is that the nskey notification path did not work end to
end — despite both halves being implemented and unit-covered. The diagnosis took three passes
and two of them were wrong, so the wrong turns are recorded with the answer: each was a
plausible reading of partial evidence, and each is the kind of mistake the next investigation
will be tempted to repeat.

### 26.1 What actually happens

Alice's notify is accepted, bob's atServer delivers it, and no subscriber ever sees it. At
`finest`, on a reproduction inside the full suite:

```
15:28:29.563688  bob's monitor: Received @bob:f605dd47a25a52b3.__ck…@alice
15:28:29.572715  server answers bob's CK lookup: AT0015 key not found       (9ms)
15:28:29.573931  Caught ContentKeyUnavailableException … while dispatching  ← logged at FINER
15:29:00.933728  the __ck record arrives via sync                           (31 SECONDS later)
```

The content-key conveyance is written **local-first**, so it reaches bob's atServer only when
alice's sync gets round to it. The notification goes out immediately, over a different
transport. The receive path resolves the CK inline, finds nothing, and raises
`ContentKeyUnavailableException` — correctly. That exception is then swallowed at `finer` by the
dispatch loop, so the notification is dropped with nothing said, and **nothing retries it** when
the conveyance lands half a minute later.

Two independent defects, and both are fixed:

1. **The conveyance must not lose the race.** Both notify entry points now pass
   `useRemoteAtServer: true` into `prepareForPut`, where a `put` passes its own routing through.
   A notification is remote-only by construction, so its conveyance has to be too. This is the
   same fix as the `__ssenv` wake-up ordering bug (section 17's sibling) and the same rule: any
   value another party must read *now* goes remote-first.
2. **A dropped notification must say so.** The dispatch `catch` logs at `warning` rather than
   `finer`, naming the key and the subscriber's regex. At `finer` a subscriber saw an absence
   indistinguishable from one that was never sent.

### 26.2 The two wrong answers, and why they were wrong

**"The atServer hangs on a cross-server lookup for a record that does not exist."** Recorded
first, from client-side evidence only: a probe either side of `AtLookupImpl._process` showed the
lookup sent with no matching completion. Disproved by asking the atServer directly — every
absent-key lookup, *including the exact failing shape*, answers in **12–24ms** with
`KeyNotFoundException`. The atServer was never implicated; it had answered in 9ms while the
client-side probe was being read as silence.

**"A remote read from inside notification dispatch deadlocks."** `monitor.dart` awaits
`handleNotification` on its socket read handler, so re-entrancy was a fair guess. Disproved by
measuring it: a remote lookup issued from inside a notification *listener* completes in **76ms**.

Both errors share one cause, and it is worth naming: **a conclusion drawn from truncated
output.** The "no completion" and "no exception logged" readings both came from
`grep … | head -12` output that was cut before the lines that would have contradicted them. The
`Caught … while dispatching` line was there the whole time. `read()` is a polling loop with a
90-second cap, so "it never returned" was never even the right shape of claim — and the elapsed
time in the failing test (60s) was shorter than that cap, which should have been the tell.

### 26.3 What this says about the design, independent of the bug

The notify path conveys a content key and announces the record needing it in the same instant,
over two transports with no ordering between them, and the receive path then resolves the key
inline. Routing the conveyance remote-first removes the race as it exists today. It does not make
the receive path tolerant of a conveyance that has not arrived for any other reason — a slow
recipient atServer, a rotation mid-flight — because there is still no retry: a notification whose
transform throws is gone. Closing that properly means either re-delivering when the conveyance
lands, or carrying enough with the notification that it does not need a second fetch at all.
Recorded as open; the warning-level log is what will make it visible next time.

### 26.4 Status

UC-A3.4 and UC-A4.4 are **met**, live-covered in `concurrent_notify_test.dart`, which asserts
that `providerId` travels on the notification frame and that bob decrypts by it. Verified by
reverting the fix: the test then fails, and passes with it.

---

## 27. The era default: read the new scheme everywhere, write it once (2026-08-04)

SS-4 owed "wire the nskey `CryptoConfig` at init". The obvious reading — make
`CryptoConfig.nskey` the default — would have been wrong, and the release sequence says why.

### 27.1 The asymmetry

`CryptoConfig.nskey` sets `defaultProviderId` to the AES-GCM data path, so adopting it wholesale
flips **writes** to PQ. That is the 4.x step. Final 3.x "reads PQ records, mints and publishes
its nskeys and its root, and **still writes legacy**" — so what init owes is the provider *set*,
not the write default. `CryptoConfig.readsNskeyWritesLegacy` is that sentence in code: same
providers, same shared `ContentKeyCache`, `defaultProviderId` left at `legacy`.

The asymmetry is structural rather than transitional caution:

- **Reading is additive.** A record arrives stamped with the provider that wrote it. A client
  that cannot resolve that id fails on data someone has *already sent it* — the failure is
  imposed from outside and cannot be avoided by not opting in.
- **Writing is a fleet-wide commitment.** The first client to write PQ produces records every
  other client must already be able to read.

So the read side must land everywhere *before* the write side flips anywhere, which is exactly
what makes the 3.x rollout a prerequisite for 4.x rather than a nicety.

### 27.2 Why it stopped being a constant

`CryptoConfig.forClient` returned `const CryptoConfig.legacy()`. It cannot return a shared nskey
set, because those providers hold **per-atSign state** — a `ContentKeyCache` and a key ring bound
to one client — so one instance would let two atSigns read each other's cached content keys. The
set is therefore built once per client at construction and `forClient` became a lookup.

Stored in an `Expando` keyed by `AtClient`, deliberately **not** written into
`AtClientPreference.crypto`: a preference object is routinely shared across atSigns, and the
moment this value stops being a const, resolving into it is a per-atSign leak. An app that named
its own config still wins, and `adoptEraDefault` leaves it untouched.

### 27.3 The part that only works because the arrival path landed

The era ring is given the client's `AtKeys` as its `privateFiling`. Without that,
`PublishedNskeyKeyRing` sees only what *this process* minted (`_ownPrivates`), so a conveyed
private — or any private at all after a restart — is invisible and the atSign reads as unable to
open its own namespace. The filing that makes it visible is the arrival path fixed earlier the
same day (section 25). A client with no `AtKeysIo` still gets the providers, since reading is
additive, but has no durable private source — the limitation it already had.

### 27.4 Closed the same day, and the "gap" was never real

This section first recorded an owed item: that the era ring was unreachable from a test, so a
live inbound read *through* the era default could not be driven. That was written without
checking, and it was wrong — `NskeyProvider.keyRing` is a public field and `NskeyProvider` is
exported, so the ring the read path will consult is reachable in two lines.

`era_default_read_test.dart` now drives the whole claim cross-atSign: **bob is given no
`CryptoConfig` at all**, mints through the ring the SDK built for him, and opens a record alice
sealed to his namespace key. Alice has to opt in to `CryptoConfig.nskey` to *write* PQ, which is
the asymmetry stated plainly in a test — the era default would have written legacy and there
would have been nothing to read. Two rig assertions guard it: that alice's record really carries
`at/symmetric/AES/GCM` (a legacy write would sail through the read and pass for the wrong
reason), and that bob's own default really registered the provider. Negative control: with
`_adoptEraCryptoDefault()` disabled the test fails on the second of those and nothing else in
the suite moves.

The lesson is the session's recurring one in a smaller key — an owed item asserted rather than
verified is a false entry on the ledger, and false entries cost the next reader more than a
missing one would.

## 28. The PQ performance budget, measured (2026-08-04)

`acceptance.md`'s cross-cutting row *"performance is measured, not assumed"* asks for a
measured ceiling rather than a guessed one. The harness (`packages/at_client/benchmark/crypto_bench.dart`)
landed with B-1; this is the first run recorded against it, so until now the row asked for a
budget that did not exist.

**Platform.** Dart 3.11.3 stable, macOS 26.5.2 arm64, 16 processors, 50 iterations, medians with
p90. Harness overhead measured at 0 µs, so nothing below is instrument.

**This is a desktop baseline, not the reference low-end device the row asks for.** The device
figure is still owed and is tracked as such — do not read the numbers below as the device budget.

### 28.1 Three bases, and they are not interchangeable

The single most misleading thing that can be done with these numbers is to compare across bases.
The PQ scheme deliberately moves cost from per-record to per-namespace, so a per-record
comparison against a per-recipient one flatters or damns it arbitrarily.

| Basis | What one unit is | How often it happens |
|---------------------|-------------------------------------|-----------------------------------------|
| per record | one value encrypted or decrypted | every put/get |
| per (owner, namespace) | one content-key conveyance | once per namespace, then cached |
| per authentication | one PKAM challenge signed/verified | once per connection |

### 28.2 Per record — AES-256-GCM vs legacy AES-256-CTR

| Size | GCM encrypt | CTR encrypt | GCM decrypt | CTR decrypt |
|---------|------------:|------------:|------------:|------------:|
| 256 B | 13 µs | 10 µs | 12 µs | 9 µs |
| 4096 B | 124 µs | 38 µs | 131 µs | 32 µs |
| 65536 B | 3055 µs | 724 µs | 2589 µs | 393 µs |

At the size that dominates real traffic the delta is **3 µs**, which is nothing. The ratio grows
with payload size — ~4× at 64 KB — because GCM computes an authentication tag over the whole
message where CTR does not. That is a real cost buying a real property (integrity), not overhead.

### 28.3 Per conveyance — X-Wing vs legacy RSA-2048

| Operation | PQ | Legacy | Note |
|-----------|-----:|-------:|------|
| seal / wrap | 1540 µs | 80 µs | different bases — see below |
| open / unwrap | 1484 µs | 1301 µs | 1.14× |
| X-Wing keygen | 729 µs | — | once per namespace key |

The seal ratio (19×) is the number most likely to be quoted and the most misleading one in this
document. The two sides are not the same unit: an X-Wing seal is **per (owner, namespace)** and
its result is cached, while an RSA wrap is **per (owner, recipient)**. A namespace shared with
many recipients pays the PQ cost once and the legacy cost per recipient. On the operation that
actually recurs — opening — PQ and legacy are within 14% of each other.

### 28.4 Per authentication — ML-DSA-65 vs RSA-2048

| Operation | PQ | Legacy | Who pays it |
|-----------|-----:|-------:|-------------|
| sign | 2711 µs (p90 6091) | 1301 µs | the client, once per connection |
| verify | 1003 µs | 70 µs | the atServer |

The client-side cost is the sign: **2.7 ms per authentication**, ~2× legacy, and imperceptible
against the network round trip it accompanies. Verify is 14× legacy and lands on the atServer,
which is where the fleet-scale question lives rather than the user-experience one.

ML-DSA-65 signing has a **wide distribution by construction** — p90 is more than double the
median because the algorithm uses rejection sampling and retries until a candidate signature is
in range. A single sample of this operation is not a measurement; that is a property of the
algorithm, not of the harness.

### 28.5 What is pinned

Nothing here is a regression gate yet — one desktop run is a baseline, not a threshold, and
pinning a ceiling to a number measured on one machine would fail on somebody else's laptop for
no defensible reason. What is pinned is the **harness**: it is the durable artefact, re-run on
every key-shape change, and `cross_cutting_test.dart` fails if it goes missing or if this section
stops recording a budget.

## 29. UC-A3.2 describes a mint trigger that was never built (2026-08-04)

Writing the owed functional scenarios surfaced a divergence between `acceptance.md` and the
code. It is recorded rather than fixed, because which side is wrong is a design call.

**What the catalogue says.** UC-A3.2's WHEN is *"alice1 does the first put
`<k>.app_1.my_apps@alice`"* and its THEN is *"alice1 takes the `_nskeylock` mint lock, and
`public:__nskey.app_1.my_apps@alice` is published immediately"*. Read plainly: a write to a
namespace with no key mints one on the way through.

**What is built.** Nothing mints on the write path. Minting happens at client construction, in
`AtClientImpl._init` → `_seedNamespaceKeys()` → `NskeySeeding.seed()`, and it is:

- **opt-in** — gated on `AtClientPreference.seedNamespaceKeys`, which defaults to **false**; and
- **fire-and-forget** — the call is `unawaited`, so construction does not wait for it and a
  failure only reaches a `warning` log.

A put to a namespace with no key does not mint; it **fails**, with
`NamespaceKeyUnavailableException` naming the atSign and namespace. That behaviour is deliberate
and is itself an acceptance row — UC-A3.3 — proven live in `nskey_data_path_e2e_test.dart`. So
the two rows as written contradict each other: A3.3 requires the cold-namespace write to fail,
while A3.2 requires it to mint and succeed.

**Why the built shape is probably the right one.** Minting inside a write means a put can
silently take a distributed lock, generate a keypair, publish a public record and convey a
private to every sibling enrollment — a lot of consequence hidden behind one `put`, and all of it
on the latency path of a user action. Doing it at start, once, keeps the write path honest about
what it can and cannot do.

**Ruled the same day: the code is right and the catalogue was wrong.** `acceptance.md` 4.2 has
been amended to describe start-time seeding, and carries a note saying so. The reasoning is the
one above — a `put` that mints would hide a distributed lock, a keypair generation, a public
record publish and a per-enrollment conveyance behind a single write, all on the latency path of
a user action, and it would contradict a proven row. Two clauses were added while the text was
open: that seeding is idempotent across starts (re-minting per launch would rotate the namespace
key out from under every peer that had already fetched it), and that a later `put` uses the
existing key rather than minting.

The row is now proven by `nskey_seeding_live_test.dart`, which asserts the outcome on the
atServer rather than that a method was called.

`nskey_seeding_live_test.dart` now covers what *does* exist, and it exists because seeding had
unit coverage only. The unit tests cannot see whether the path runs at all, and an `unawaited`
call behind a default-false flag is precisely the shape that passes every unit assertion while
never executing — the failure mode that has already bitten this branch twice.

## 30. UC-B5.1's pull backstop has no initiator (2026-08-04)

> **2026-08-05:** [38](#38-key-material-self-heals-mint-if-absent-else-pull-2026-08-05)
> found this was the general condition, not a root-specific gap — the nskey privates
> had no pull initiator either, and neither approve-time push had a caller.

Picking up UC-B5.1 — *"offline enrollment pulls the signing root later"* — found that the row
cannot be tested because half of what it describes is not built. Recorded here rather than
worked around, and the row is re-labelled from *owed a test* to *blocked*.

**What is built.** The substrate's request/answer round trip is complete and on by default:
`requestSecretsFromNamespace` broadcasts a `kind:'request'` envelope, `_handleRequestPayload`
resolves and authorizes the requester and shares the matching secrets, and an unset
`answerSecretRequests` means *answer* — the default policy admits any requester that resolves to
an authorized key package of the request's namespace. It is unit-covered directly
(`pairwise_secret_sharing_test.dart`: a holder answers a request and the requester receives the
secret; the `requestSecret` convenience; `namePrefix` pulls; the suppression case). The answer
loop does **not** exclude per-enrollment secret names, so a request naming the root would be
answerable.

**What is not.** Nothing ever asks. `requestSecret` and `requestSecretsFromNamespace` have
**zero call sites in `lib/`** — the only references outside their own file are tests. For the
signing root specifically, `PqSigningRoot.mintIfAbsent` says so in its own dartdoc: a loser of
the create *"must be given the private half by a privileged enrollment that already has it, over
the substrate. That pull is not built here yet."*

**So the row splits.** Its second sentence — namespaced nskey privates arriving by the push path
once a holder is online — **is** built, via `NskeySeeding`'s conveyance. Its first and headline
sentence — that `requestSecret` is the steady-state path for the root, "answered by any online
holder and persisting until one answers" — describes a mechanism whose initiator does not exist.
An enrollment that genuinely missed the approval-time conveyance would today sit without the
root and nothing would go and get it.

**Why this is not merely cosmetic.** The root is atSign-level and never rotates, so an
enrollment that misses it cannot be repaired by any later event that carries a namespace: it is
excluded from the `enroll:listns` fan-out by construction, because it has no namespace to fan
out over. The pull is not a convenience path, it is the only remaining route.

**What is owed:** an initiator — a client that finds itself without the root private, and
privileged enough to hold one, issuing the request and waiting. The primitive underneath it is
sound and tested, so this is wiring rather than design. Until then UC-B5.1 carries
`rootPullNotBuilt` rather than an `owed` label, because calling it "owed a test" would say the
code is finished when it is not — the same conflation the burn-down repair removed.

## 31. The root-pull initiator, and what it did not settle (2026-08-04)

[Section 30](#30-uc-b51s-pull-backstop-has-no-initiator-2026-08-04) recorded that the pull
backstop had no caller. `PqSigningRoot.requestPrivateIfAbsent` is that caller, wired into
`AtClientImpl` start between collecting conveyed material and anchoring — before anchoring
rather than after, because anchoring needs the private, so on the rare start where an answer is
already waiting both succeed in one pass.

### 31.1 Broadcast, not a wait

It does not block on an answer. This runs at every client start, so a timeout would be paid by
every launch including the overwhelming majority that need nothing, and a holder may not be
online at that instant regardless. The request persists as an envelope, any holder that comes
online answers it, and the answer is filed by the arrival path at this or a later start. That is
what "answered by any online holder and persisting until one answers" means in practice.

### 31.2 Three guards, in cost order

Cheapest first, because the common case must not pay for the rare one.

1. **Already holds it** → return. Settles the question with no round trip, and is true for every
   enrollment that was online when it was approved.
2. **No enrollment id** → return. Such a client authenticates with the atSign's own keys. It
   *cannot* ask — enumerating holders goes through `enroll:listns`, which the atServer refuses
   without APKAM authentication (observed, not inferred) — and has no reason to: it is the
   atSign, so its route to a missing root is to mint one. This guard was added after the first
   live run, where its absence made every legacy PKAM client broadcast and be refused.

   **The first version of this guard was dead code.** It tested
   `sharing.enrollmentId == null`, but `ApkamSigning.enrollmentId` is non-nullable and
   substitutes the sentinel `'primary'` when there is none — so the comparison was always false
   and the guard never fired. It now reads
   `atClient.getRemoteSecondary()?.atLookUp.enrollmentId`, the same source
   `AtClientImpl._resolveFullPrivilege` uses, which is genuinely null for a non-APKAM client.
   Caught because a unit test written against a `Fake` failed on the missing override; the
   analyzer had nothing to say, since a comparison that is always false is legal Dart. Worth
   remembering as a shape: a null-check against a getter that manufactures a sentinel is a guard
   that reads correct and does nothing.

   In the run carrying the dead guard, `at_lookup_race_test` failed and was green again with the
   guard working. That is consistent with the doomed per-start broadcast perturbing a
   timing-sensitive test, but it is one run each on a test built around a race, so it is recorded
   as consistent-with rather than as an established cause.
3. **Not fully privileged** → return. Only that class may hold the key that vouches for every
   enrollment on the atSign. Asking would be refused, and the asking itself announces to every
   holder that something unentitled is looking for it.

Ordering matters beyond tidiness: resolving privilege costs a round trip to the enrollment
record, and guard 1 avoids it on essentially every start of every client. There is a unit test
asserting the privilege callback is *not* consulted when the private is already held.

### 31.3 What is still unproven, stated as such

The full round trip is **not** demonstrated live, and UC-B5.1 stays blocked. Two observations,
both direct:

- `requestPrivateIfAbsent`'s enumeration fails in the functional harness with *"enroll:listns
  requires APKAM authentication"*, because that harness authenticates with the atSign's own keys.
- Addressing a request envelope straight at a holder, bypassing the enumeration, puts the
  envelope on the atServer — but the holder produces no answer and the seeker never receives the
  root. A plain envelope on the same wire between the same two parties sweeps normally, so the
  difference is the request payload, not the transport.

**Resolved the same day, with the transcript.** The cause was first written here as an open
question rather than a diagnosis, and then actually established. Under FINEST logging the
holder's sweep shows:

```
RECEIVED error:{"errorCode":"AT0401","errorDescription":
  "Client authentication failed : enroll:listns requires APKAM authentication"}
WARNING|AtClientSecretSharing|Failed to process envelope <…>.__ssenv.wavi@alice🛠:
  Exception: Client authentication failed …
```

So the holder **does** pick the request up. It then tries to authorize the requester — resolving
the sender's kpid against the key packages registered for the namespace — and that resolution
goes through `enroll:listns`, which the atServer refuses for a client authenticating with the
atSign's own keys. The envelope is left unconsumed and no answer is produced.

**The pull therefore requires APKAM on both sides:** the requester to enumerate holders, and the
responder to authorize the requester. That is a property of the design rather than a defect —
the authorization is deliberate defence in depth over the atServer's own delivery gate — but it
means no harness using the atSign's own keys can exercise this path at either end.

Two notes on how this was reached, both of which are the point. The first attempt concluded
nothing from an absence of log lines; that absence turned out to be an artefact of raising
`AtSignLogger.root_level` *after* the loggers were constructed, and a run with the level raised
beforehand — plus a plain envelope as a positive control, to prove the logging reached the region
at all — produced the transcript above immediately. And the failure is logged at **warning**,
naming the envelope, which is why it was findable at all; had it been `finer` this would have
presented as "the sender never sent".

**What UC-B5.1 now needs:** two APKAM enrollments of one atSign with genuinely distinct clients,
which the per-atSign client cache currently prevents in a single process (see section 32). With that in place the round trip should complete,
since the only thing observed blocking it is an authentication class the fixture would supply.
The blocker is re-labelled from *the initiator does not exist* to *the live round trip is
unproven* — the initiator now exists and its guards are unit-covered.

## 32. The two-enrollment fixture: what works and what does not (2026-08-04)

[Section 31](#31-the-root-pull-initiator-and-what-it-did-not-settle-2026-08-04) established that
the signing-root pull needs APKAM authentication on both sides, and that proving it needs a
fixture with two real enrollments. That fixture is started, not finished, and this records the
state precisely so the next attempt does not re-derive it.

**`tests/at_functional_test/lib/src/enrolled_client.dart`** runs the real flow — submit, approve,
`waitForApproval` — rather than assembling keys by hand, because `waitForApproval` is what
unwraps the enrollment's encryption keys with the `apkamSymmetricKey` the approver sealed to its
key package. Short-cutting it would produce a client whose keys never went through the conveyance
these tests exist to exercise. Each enrollment gets its own `AtClientManager(atSign)` instance,
since `getInstance()` is keyed by atSign and a second enrollment of the same atSign would evict
the first.

**What works.** Two enrollments are created and approved, with distinct enrollment ids and
distinct advertised kpids, and clients are constructed from their sessions.

**What does not, and neither is guessed at.**

1. **The constructed client is not treated as APKAM-authenticated — because it is not a new
   client at all.** Established, and the answer is structural. `AtClientImpl` caches instances
   **keyed by atSign alone**, so every enrolled client handed back is the *same object* as the
   approver's: `identical(enrolled.client, approver)` is `true`, and two enrollments of one
   atSign are `identical` to each other. `setCurrentAtSign` reuses that instance and
   `_remoteSecondary ??=` keeps the connection it was built with, so `enrollmentId` never reaches
   the `AtLookUp` — hence the refusal.

   The session itself was fine all along: `response.session` is non-null, carries the right
   `enrollmentId`, and carries an already-authenticated `AtLookUp`. `fromAuthSession(reuse: true)`
   asks for that connection and still changes nothing, because none of those arguments are
   applied to a cached instance.

   The "two paths behave differently" discrepancy dissolved too, and it was my own code:
   `requestPrivateIfAbsent` returned 0 rather than throwing because its own
   `atLookUp.enrollmentId == null` guard fired first and it never reached the enumeration. There
   was no discrepancy to explain — one path exited early. Worth recording as a reminder that a
   "mystery" is often a guard you wrote that morning.

   **This is the `(owner, id)` rule missing from the client cache.** Identity there is the atSign,
   not the atSign *and* the enrollment, and `ConcurrentClients` does not help: it solves two
   different atSigns, and a second `AtClientManager` still resolves to the same cached client for
   a matching atSign. Making the fixture work needs a cache scoped by `(atSign, enrollmentId)`,
   or driving the second enrollment through `AtLookUp` alone, or a second process — a decision
   about `AtClientImpl`, not a fixture detail. The earlier note here that "the pieces exist;
   assembling them is the work" was wrong, and is withdrawn.
2. **Key packages are not bound to their enrollments.** `register()` mints a fresh X-Wing keypair
   per process: a party's kpid came back `490de1fc0a10864e` where its enrollment had advertised
   `9520bb7abf3295ee`. A party in that state listens at an address no sender ever writes to.
   Production solves it with `bindKeyPackageToAtKeys` in `collectConveyedKeyMaterial`; the
   fixture must do the same. Understood and mechanical.

The test is committed **skipped**, carrying both points inline. A fixture that looks finished and
is not costs more than an absent one, which is the same reason UC-B5.1 is labelled blocked rather
than owed.

## 33. Keying the client cache by (atSign, enrollmentId) (2026-08-04)

[Section 32](#32-the-two-enrollment-fixture-what-works-and-what-does-not-2026-08-04) found that
two enrollments of one atSign could not have distinct clients in a process, because
`AtClientImpl` cached instances **keyed by the atSign alone**. `identical(second, first)` was
true, `_remoteSecondary ??=` kept whatever connection the first instance was built with, and the
enrollment id therefore never reached the `AtLookUp` — so the atServer refused `enroll:listns`
and the whole pull path was unreachable from a test.

**The cache is now keyed by `(atSign, enrollmentId)`.** That is the `(owner, id)` rule the rest
of this codebase already follows, applied to the one place that had missed it. A client
authenticated as one enrollment is a different principal from one authenticated as another, or
as the atSign's own keys: different APKAM keypair, different granted namespaces, and the atServer
answers different verbs for it.

**A null enrollment id keeps the bare atSign as the key.** That is the overwhelmingly common case
— a client using the atSign's own keys — and leaving its key untouched means no existing caller,
eviction path or termination test has to learn a new shape. The blast radius was checked before
the edit rather than after: five sites inside `at_client_impl.dart` and a set of tests that
`remove(atSign)` or `containsKey(atSign)`, all of which pass a null enrollment id and so are
unaffected by construction.

**UC-B5.1 is proven as a result** — the first row in this catalogue to need production code, not
just a test, and then a second fix underneath that. The sequence is worth keeping as a shape: the
row looked *owed a test*; writing the test showed the mechanism had **no initiator**
([30](#30-uc-b51s-pull-backstop-has-no-initiator-2026-08-04)); building the initiator showed the
path needed APKAM on both sides ([31](#31-the-root-pull-initiator-and-what-it-did-not-settle-2026-08-04));
building that fixture showed the client cache made it impossible
([32](#32-the-two-enrollment-fixture-what-works-and-what-does-not-2026-08-04)). Four layers, each
only visible once the one above it was cleared, and none of them visible from reading the code.

### 33.1 The test's own precondition

`signing_root_pull_two_enrollments_test.dart` passed on a fresh virtualenv and failed on the
re-run: the atServer refuses a second enrollment carrying an `(appName, deviceName)` pair that
already has one approved, and the device names were fixed strings. They are now unique per run.
Caught only because the result was re-checked rather than accepted — a single green run on a
one-shot-state test says nothing about the next one.

## 34. PKAM is record-authoritative, and the no-RSA row reads narrower than it looks (2026-08-04)

Two cross-cutting rows closed together, and both turned on reading the claim precisely.

### 34.1 The wire `signingAlgo` is a claim; the record decides

The client API cannot express the mismatch this needs:
`AtLookupImpl.signingAlgoType` drives *both* the signature at_chops produces and the value put on
the wire, so asking for `mldsa65` makes the client attempt an ML-DSA signature with an RSA key and
fail before the atServer sees anything. The `pkam:` command is therefore built by hand — always
signing RSA with the enrollment's real keypair, varying only the algorithm **claimed**.

The outcome is the discriminator, and it reads backwards until you see it: **a pass is both arms
succeeding.** If the atServer reads the record it verifies RSA and both authenticate; if it read
the wire, the second arm would attempt ML-DSA verification of an RSA signature and be refused.
Observed: `signingAlgo:rsa2048` → `data:success`, `signingAlgo:mldsa65` → `data:success`.

The rig is checked inside the test — the built command is asserted to contain the claimed
algorithm — because two arms that turned out to be the same command would be a comparison of a
case with itself, and would read green.

### 34.2 "No RSA in any confidentiality path" excludes auth by construction

The row lists auth among its paths, which reads as though a PQ interaction cannot authenticate
with RSA. It is titled *confidentiality*, and **auth has no confidentiality component to have**: a
prove-possession handshake needs a signature only, since the per-connection challenge supplies
freshness and TLS supplies the channel. RSA signing a PKAM challenge is therefore not an RSA
confidentiality path, and replacing it is RF-2b's PQ-APKAM mint rather than this row's business.

That is the same rule this tree already carries — *PQ auth is a signature swap, not a KEM* — and
applying it here is what let the row close honestly rather than sit blocked behind PQ APKAM. What
the row does assert is that the provider set carrying actual secrets contains nothing RSA: X-Wing
for the content-key conveyance (a KEM, where there is a secret to transport), AES-256-GCM for the
value, neither provider id naming RSA, and the PQ path being the *write* default rather than
merely registered. The self, shared, notification and enrollment-conveyance legs are cited to
live proofs, since a unit test cannot see which providers a real write reached.

## 35. The owed-a-test backlog reached zero (2026-08-04)

The 17 rows that SS-2, SS-4 and B-1 left *owed a test* are discharged. The suite reads **22 of 40**
green; every one of the remaining 18 skips names a project that has not landed, so `blockers.dart`
is now purely a project ledger — grep a project id and you get exactly the scenarios it will turn
green.

**Four of the 17 needed something other than a test**, which is the finding worth keeping. Two
were documentation problems in opposite directions: UC-A3.2 described a mint trigger that was
never built ([29](#29-uc-a32-describes-a-mint-trigger-that-was-never-built-2026-08-04)), and
UC-B5.1 described a pull mechanism that should exist and did not
([30](#30-uc-b51s-pull-backstop-has-no-initiator-2026-08-04)). One needed a measured budget
written down before it could assert anything ([28](#28-the-pq-performance-budget-measured-2026-08-04)).
And one needed a fix underneath the fix — UC-B5.1 could not be driven until the client cache was
keyed by `(atSign, enrollmentId)` ([33](#33-keying-the-client-cache-by-atsign-enrollmentid-2026-08-04)).

That is the argument for making a catalogue executable rather than reasoning about whether the
code satisfies it. None of those four was visible from reading the code; each surfaced only from
trying to write the assertion, and two of them were layers under another one.

### 35.1 The last two rows, and what they cost

UC-A4.2 needed a namespace unique to the run, so `@bob` has genuinely never enabled it — against
a shared namespace he already has a published key and the send simply succeeds. It asserts the
readiness query answers **false** before anything is composed *and* **true** for a namespace he
has enabled, because a query that always says no carries no information.

UC-A4.3 took four attempts, each a real defect in the test rather than the code, and each worth
noting for the next cross-atSign test:

1. the approver must `register()` a key package before it can approve, since it seals the
   enrollee's symmetric key to its own;
2. alice cannot `get()` the conveyance — it is sealed to **@bob's** namespace key, and her being
   unable to open it is the correct behaviour, not a bug;
3. `getMeta()` does not help, because it delegates to `get()` and therefore decrypts. The
   metadata is atServer-visible plaintext, so `llookup:meta:` reads it without decryption — and
   returns `appMetadata` already decoded, where the update fragment carries it base64-encoded;
4. bringing alice up through `AtClientManager.getInstance()` tore @bob's client down, unsetting
   his `syncService`. `ConcurrentClients` exists for exactly this and is the right tool whenever
   two atSigns must be live at once.

### 35.2 The catalogue guard has been re-pointed twice

It first tracked B-1's share of the rows, then the owed-a-test count. Both reached zero, and a
guard pinned to a number that can no longer change silently stops guarding. It now tracks the
rows blocked on a project, which is the figure that moves as projects land. Re-point it again
when that one bottoms out rather than deleting it.

---

## 36. The rollout is the app's decision: capability markers built, examined, and removed (2026-08-05)

**In brief:** *supersedes Decision #2 and §16's marker consequence; the migration is two app releases*

R-1 was built as designed — the per-`(atSign, namespace)` capability marker
(`public:__capability.<ns>@<atSign>`, an APKAM-signed envelope carrying the **set** of
provider ids, per [16](#16-a-provider-id-names-every-algorithm-a-reader-needs-code-for-2026-08-02)),
per-destination scheme negotiation ("write only what every required reader supports"),
an operator readiness flip, and marker publication wired into start-up seeding. It went
green at every layer: unit, functional against a live atServer, and a two-atSign e2e in
which a declared readiness flipped a real `put` from legacy to the nskey data path.
**It was then removed the same day, on a re-examination of the model it served.** This
entry records both the model and why working code lost the argument.

### 36.1 The model, from three scenarios

- **Scenario 1 — three apps, two atSigns, separate keyfiles.** The unit of migration is
  the **app**, and an app is an **enrollment**: its own AtKeys, its own APKAM keypair,
  its own namespaces. Apps upgrade independently and never have to agree. "Per
  `(atSign, namespace)`" therefore means *per app*, not a slice of an atSign-wide
  fleet — and there is no atSign-wide operator to flip anything, only each app's
  developer deciding when to ship.
- **Scenario 2 — several CLI apps sharing one AtKeys file (one enrollment).** Changes
  nothing about the model. It adds two operational requirements: the enrollment upgrade
  must be **additive including the APKAM keypair** (an ML-DSA swap would lock the
  co-tenant apps out of *auth* the moment the first app upgrades), and the keyfile
  needs an **inter-process lock** around read-modify-write
  ([38.4](#384-the-atkeys-file-needs-a-lock-not-just-a-detector)).
- **Scenario 3 — one keyfile cloned to several devices (one enrollment id).** Each
  device upgrades individually: enrollment 1 spawns enrollments 2, 3, 4. The problems
  this surfaces are catalogued in [38](#38-key-material-self-heals-mint-if-absent-else-pull-2026-08-05)
  and [40](#40-rf-srv-is-the-mechanism-the-whole-model-stands-on-2026-08-05); none of
  them is a readiness problem.

**The migration is two app releases.** (1) Rebuild on the final 3.x — the app is now
*capable*: reads every scheme, mints and publishes its namespace keys, still writes
legacy. (2) Rebuild on 4.x — the app now *uses* PQ. **The SDK never decides to write
PQ; the app tells it to** (explicitly via `AtClientPreference.crypto`, or implicitly by
riding the 4.x default). The one discipline the model asks of an app developer: roll
out the capability build before shipping the active build. That is a release-ordering
rule, not machinery.

### 36.2 Why the marker lost

1. **The release ladder is the readiness signal.** Within an app, "can my installs
   read PQ" is answered by which build they run, and the developer's own rollout data
   answers that better than a marker any single client publishes by assertion.
2. **The marker could not see the deciding fact anyway.** What makes a record readable
   to an enrollment is whether the substrate has delivered the nskey private to it —
   per enrollment, unobservable from any fleet-level record.
3. **Cross-atSign, cold start already gates.** A namespace never used by a PQ-capable
   client has no published nskey, so a PQ write toward it fails by name
   (`NamespaceKeyUnavailableException`). Within a namespace, cross-atSign traffic is
   between installs of the *same app* — there are no strangers who could see an
   advertised key and write PQ into someone else's namespace, so early nskey
   publication is harmless.
4. **The residue is the app's problem — ruled explicitly.** A recipient running mixed
   installs of one app (one updated, one not) can have its stale install locked out of
   *inbound* PQ data. A marker would not fix it: the stale install is already locked
   out of everything written since the nskey appeared, and the remedy — update the
   app — is the developer's either way.
5. **Since the SDK never chooses PQ, negotiation had no consumer.** Its cost was a
   permanent public API, a signed record per `(atSign, namespace)`, a fetch+cache on
   the write path, and a walk-up intersection that coupled apps the model holds
   independent.

**Removed, not kept inert:** the marker, `CryptoRollout`, `SchemeNegotiation`,
`CryptoConfig.preferredProviderId`, `RequiresReaderSupport`, and the seeding hook.
**Kept:** `disallowLegacyEncryption` (below) and the cold-start refusal with its
opt-in legacy fallback — now the only write-path gate, and the right one.
`disallowLegacyEncryption` survives because it serves the app-decides model directly:
it is how an app *states* "never write legacy", per client, checked at selection and
again at encryption, with legacy reads and `shouldEncrypt=false` untouched.

**Supersedes:** Decision #2 (readiness marked per `(atSign, namespace)`) and
[16](#16-a-provider-id-names-every-algorithm-a-reader-needs-code-for-2026-08-02)'s
"the capability marker becomes a set" consequence (the *provider-id* ruling in 16
stands — ids still name every algorithm a reader needs code for, and records still
route by their stamped id forever). Design.md §1.8's C1/C2/C3 are rewritten
accordingly; D1-D stands, built.

### 36.3 What the build was worth (kept as lessons, not code)

- A per-client cached object must not capture at construction a collaborator that an
  app or test can replace later — the negotiator pinned its capability view at first
  write (during start-up, before any test could inject one) and a declared readiness
  then moved nothing for a full cache window while every diagnostic said the marker
  was fresh. Cache the client-scoped object; resolve its collaborators per call.
- The ring that mints must be the ring the client's config resolves through, and
  seeding without durable filing publishes a key whose private only the seeding
  object holds — both hit live before any unit test could see them, twice.
- The two-atSign e2e asserted what the sender could *see* of the recipient, not only
  what it wrote — which is what made a one-run diagnosis of the Expando pinning
  possible. Assert the input to a decision, not just the decision.

## 37. Legacy key material is retained until the ecosystem is PQ, not the atSign (2026-08-05)

**In brief:** *reverses Decision #1's default; onboarding keeps cutting legacy keys; RSA APKAM kept on upgrade*

**Whether an atSign has legacy history is determined by whether the apps using it are
fully PQ — not by whether the atSign is new.** An atSign is shared by its apps; its
key material must serve the union of their needs; and that union is unknowable at
onboarding, because a still-legacy app may adopt the atSign tomorrow.

**Therefore, for an as-yet-undefined period:**

- **First-enrollment onboarding continues to cut the legacy encryption keypair and the
  symmetric self-encryption key** — even for an atSign that intends to be PQ-native.
- **`enroll:approve` continues to convey both to every new enrollment**, including
  PQ-only enrollments that may never use them.
- **An enrollment upgrade keeps the RSA APKAM keypair alongside the new material**
  (scenario 2: a shared keyfile whose APKAM was swapped rather than extended locks
  every co-tenant app out of authentication).
- **A new atSign publishes its RSA `public:publickey` by default**, so legacy peers
  can send inbound. The legacy-interop flag becomes an early **opt-out**. *This
  reverses Decision #1's default* (was: PQ-only by default, flag opts in). Ratified
  2026-08-05.

The asymmetry that justifies all four: an unused keypair costs a few hundred bytes in
a keyfile; a missing one is an app that cannot function on that atSign at all — or a
peer that cannot reach it.

**The exit is a future release that stops by default unless asked**, flipping these
defaults once the ecosystem has moved (this re-times R-2's "stop generating
`selfEncryptionKey`" and B-3 phase 3's approve-relaxation: the *server-side tolerance*
for absence can land early, but the *client-side stop* is gated on the ecosystem, not
on a version number). Noted for that release, not built now: stopping need not be a
one-way door — minting legacy material *late* is safe precisely when nothing was ever
written under it, and the substrate can convey a late-minted self key to existing
enrollments exactly as it conveys nskey privates. Stop-by-default plus
repair-on-first-demand beats waiting for a certainty that never arrives.

## 38. Key material self-heals: mint-if-absent, else pull (2026-08-05)

**In brief:** *Decision #4's push had no callers; the scenario-3 taxonomy; the AtKeys lock*

The ruling, stated as the invariant every enrollment follows at start:

1. **nskeys:** an upgraded enrollment **mints** the nskey for an authorised namespace
   if none exists (the `_nskeylock` immutable create already serialises racing
   enrollments); if one exists, it **requests the private parts** over the substrate.
   Not "from whoever created it": the request broadcasts to every key package
   registered for the namespace, and **any current holder answers** — the creator may
   be long gone. A joiner needs the **current generation** to write; older generations
   are pulled on demand for history (the request supports exact names and a prefix).
2. **Signing root:** a **fully privileged** enrollment mints it if absent, else pulls
   the private (`requestPrivateIfAbsent`, built). The create-once race self-heals with
   a one-launch delay: the loser's refused create is logged, and the every-start pull
   picks the private up next launch. A *scoped* enrollment neither mints nor pulls the
   root — correct, it is not entitled to hold it.
3. **The chain sweep:** every enrollment publishes its own `_apsk`, but the
   approval-chain **link** binding an `_apsk` to the signing root can only be signed
   by a fully-privileged holder — and in the cloned-keyfile world an enrollment's
   approver is often the legacy enrollment 1, which can never sign one. So a
   fully-privileged client **sweeps** enrollments lacking links and signs links for
   them. Until it runs, *chained-but-unanchored is a legitimate steady state*, costing
   defence-in-depth (verifiers tolerate an unsigned `_apsk`), not function.

### 38.1 The finding that forced this: Decision #4's push never ran

Decision #4 names `pushSecretToNamespaceMembers` at mint and
`shareAllSecretsWithEnrollment` at approve as the steady state, with `requestSecret`
as backstop. As of 2026-08-05, verified by grep: **`shareAllSecretsWithEnrollment` has
no callers. `conveyHeldPrivatesTo` (the nskey-specific approve-time push) has no
callers. `requestSecretsFromNamespace` has exactly one production caller — the signing
root's pull.** So the only route by which an nskey private ever reached an enrollment
was the mint-time push, to whoever held a key package at that instant. Any enrollment
created after the mint got nothing, and a PQ record met `no nskey private held for …`
with no request, no retry, no recovery. Not a scenario-3 exotic: this is the ordinary
second device. Same shape as [30](#30-uc-b51s-pull-backstop-has-no-initiator-2026-08-04) —
a mechanism with no initiator passing every unit test — one layer down and more
consequential, because this private reads the data.

### 38.2 The pull is safe by construction (verified before relying on it)

The substrate's answer path already resolves the requester's kpid to a key package
**authorised for the request's namespace** (defence in depth over the atServer's own
delivery gate), consults an app policy hook, rate-caps per (requester, name), and
jitters answers so N holders collapse to one. Both directions are store-and-forward
through the atServer — no two devices need be up at once, so "heals when each device
next runs" is latency, not availability.

### 38.3 Scenario 3's problem taxonomy (so nobody re-derives it)

- **Transient, self-healing:** late devices acquiring key material — and usually
  *invisible*, because at capability-upgrade time the app still writes legacy and the
  clone inherits the legacy keys, so there is nothing it cannot read. The window is
  real only for a device upgrading after the app went active-PQ: the standard E2EE
  new-device experience.
- **Must-dos, not problems:** each device presents a distinct `(appName, deviceName)`
  — client-side discipline, not server-enforced:
  [42](#42-the-to-define-list-ruled-2026-08-05) item 1 exempts the APKAM
  self-enrollment branch from the duplicate refusal, since a retrofit legitimately
  keeps its own name, so distinctness is what lets an owner tell one device's
  enrollment from another's in `enroll:list`; and the new enrollment id lands **in
  the keyfile that already holds the legacy material** — a fresh keyfile silently
  violates [37](#37-legacy-key-material-is-retained-until-the-ecosystem-is-pq-not-the-atsign-2026-08-05).
- **Largely moot:** pre-split conveyance exposure — enrollment 1 is legacy, so the PQ
  secrets conveyed to it before the split number zero. A keyfile cloned *after* an
  upgrade is a different act; unwinding what a clone holds is B-2 rotation's business.
- **Handled by judgement, not machinery:** retiring enrollment 1. A too-early
  retirement is a loud auth failure on the straggler, not silent data loss — the same
  reason [36](#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05)
  rejects mechanising readiness. Guidance belongs in the upgrade docs.

### 38.4 The AtKeys file needs a lock, not just a detector

`FileAtKeysIo.flush` is atomic (write-temp-then-rename) and *detects* regressions
(`validateMapUpdate` refuses a candidate that drops existing material) — but two
processes that both read before either writes both pass validation, and the second
rename silently discards the first's addition. The severe case is a conveyed nskey
private that appears filed and is not: records that can never be read, presenting
weeks later. Scenario 2 makes concurrent access the normal case, so the
read-validate-write gets an inter-process advisory lock.

## 39. `_apsk` rides the same two-stage ladder (2026-08-05)

**In brief:** *3.x publishes as today and learns the new form; 4.x new enrollments publish self-describing mldsa65*

Apps sign and verify with `_apsk` **today** — NoPorts most prominently — so the
per-enrollment signing key is itself a two-stage rollout, ruled 2026-08-05:

- **Final 3.x (capability): the published `_apsk` value stays exactly as it is now** —
  a bare RSA public key string — while the *code* learns to understand a new
  self-describing format when it meets one.
- **4.x: new enrollments publish the self-describing form** (ML-DSA-65).
- The new form must be **unmistakable to an old parser**: a consumer expecting a bare
  RSA key must fail loudly on it, never mis-read it.

The finding that makes stage one real work rather than a no-op: the envelope's
`signingAlgo`/`hashingAlgo` fields are **decorative today**. `signEnvelope` signs RSA
regardless of the `signingAlgo` it is handed, and `verifyEnvelope` never reads the
field at all — it always verifies RSA. Stage one is therefore: verify branches on the
recorded algorithm, and `_apsk` parsing accepts both forms.

**In-place rsa→mldsa65 upgrade of an existing enrollment's signing key: recommended
NO, on the to-define list pending ratification** ([41](#41-the-to-define-list-2026-08-05)).
It would rewrite approved enrollment state server-side and need a who-may rule,
while the enrollment-upgrade path ([40](#40-rf-srv-is-the-mechanism-the-whole-model-stands-on-2026-08-05))
reaches the same end state with mechanics that exist, and revocation of the old id as
cleanup. One mechanism, not two.

## 40. RF-SRV is the mechanism the whole model stands on (2026-08-05)

**In brief:** *moves onto the GA critical path; revocation must cascade*

**"Upgrade the enrollment" — the verb every scenario conjugates — does not exist in
the atServer.** [Section 5](#5-retrofit-ruling--fresh-self-spawned-auto-approved-enrollment)
ruled its shape in June (fresh, self-spawned, auto-approved enrollment; grants a
subset of the parent's; no OTP on an authenticated APKAM connection), and the plan
filed it off the GA path as "retrofit". The three scenarios invert that: without
self-enrollment, the only upgrade path is a human approving from another device,
which breaks "each app upgrades itself, on its own schedule" completely. **RF-SRV
moves onto the D1 GA critical path**, and every "transient, self-healing" claim in
[38](#38-key-material-self-heals-mint-if-absent-else-pull-2026-08-05) is conditional
on it existing.

Constraints beyond §5's ruling, from the scenario-3 examination:

- **Revocation must cascade.** Self-enrollment makes enrollments a parent/child
  graph. A stolen keyfile can spawn a child before the theft is noticed; if revoking
  the parent leaves the child alive, the feature defeats revocation. The child
  records its parent; revoking a parent revokes descendants. (The approval chain
  already models parenthood for signing; the server's revocation must honour it too.)
- **Legacy material conveys client-side.** The requester generates its own new
  keypair, so it seals the legacy encryption keypair + self key to its own new key
  package; `encryptedDefaultSelfEncryptionKey` is satisfiable without the server
  holding anything.
- **§5's expiry cap is in tension with scenario 3 and needs re-ratifying.** §5 caps
  the old enrollment to `min(now + grace, expiry)` on retrofit — but scenario 3's
  devices upgrade on schedules measured in whenever-they-next-run. A short grace
  strands laggard clones; an infinite one never retires the legacy credential. On
  the to-define list; not silently overridden in either direction.
- A protocol seam: client, commons, and every atServer implementation land together.

## 41. The to-define list (2026-08-05)

**In brief:** *the ruled/open boundary, 12 items with owners*

What the 2026-08-05 re-examination deliberately leaves **defined as needing
definition** — the boundary between ruled and open. Each item names its owner-project
where one exists.

**Ruled the same day** — [42](#42-the-to-define-list-ruled-2026-08-05) records the
ruling on every item; this list stays as the index of what each owner project owes.

1. **RF-SRV verb wire shape** (the ruling in [§5](#5-retrofit-ruling--fresh-self-spawned-auto-approved-enrollment)
   plus [40](#40-rf-srv-is-the-mechanism-the-whole-model-stands-on-2026-08-05)'s
   constraints, as protocol: request fields, response, error cases). → RF-SRV.
2. **The revocation-cascade mechanics** — where the parent link lives on the
   enrollment record, and how revoke walks it. → RF-SRV + atServer.
3. **§5's expiry cap vs scenario-3 laggards** — grace length, or cap-on-retrofit vs
   cap-on-operator-action. → RF-SRV.
4. **Who runs the chain sweep** for an atSign whose apps are all scoped enrollments —
   the atSign's own keys are privileged by construction, but that keyfile lives in a
   drawer. → chain-sweep work ([38](#38-key-material-self-heals-mint-if-absent-else-pull-2026-08-05).3).
5. **Last-holder-lost recovery** — the published nskey exists, no live enrollment
   holds the private, `mintIfAbsent` correctly refuses. Presumably: rotate and accept
   that history is unreadable; needs saying as a ruling. → B-2.
6. **Keyfile cloned after upgrade vs revocation** — what rotation must assume about
   clones sharing one enrollment id. → B-2.
7. **Enrollment-1 retirement guidance** (docs, not machinery). → upgrade guide.
8. **In-place rsa→mldsa65 `_apsk` upgrade: ratify the "no"** in
   [39](#39-_apsk-rides-the-same-two-stage-ladder-2026-08-05). → RF-2b.
9. **The exact self-describing `_apsk` format** (tagged JSON shape, field names,
   old-parser failure mode — coordinate with NoPorts before freezing). → RF-2b.
10. **The stop-minting-legacy release** — opt-out semantics, default-flip timing,
    and the optional late-mint repair path
    ([37](#37-legacy-key-material-is-retained-until-the-ecosystem-is-pq-not-the-atsign-2026-08-05)). → R-2/B-3 re-scope.
11. **nskey pull trigger points** — start-time sweep vs on-miss vs both, and the
    generation/rotation interplay (current-to-write, older-on-demand). → self-heal
    work; being prototyped 2026-08-05.
12. **AtKeys advisory-lock design** — lock file vs `flock`, staleness, scope of the
    critical section. → at_auth; being prototyped 2026-08-05.

## 42. The to-define list, ruled (2026-08-05)

**In brief:** *all 12 ruled; the 720h grace and the tagged `_apsk` format frozen*

Every item in [41](#41-the-to-define-list-2026-08-05) was ruled in one sitting, each
grounded first in the built code (read for the purpose, with file:line evidence) and
then in the rulings it descends from. Owner projects are unchanged — what follows is
what each project now implements rather than designs. The review also found three
defects the list didn't know about: the duplicate-enrollment check refuses every
scenario-3 retrofit (item 1); the AtKeys lock's stale-break can admit two holders,
and its release could evict a successor (item 12); and the built expiry cap wrote
its ttl against the wrong anchor, silently extending the grace by the enrollment's
age (item 3, found while landing the sliding ruling). All the fixes land with this
ruling, each with a differential test.

1. **Wire shape: frozen as built, plus two server deltas.** The verb stays
   `enroll:request:<json>`, discriminated solely by the connection's authType being
   APKAM — no new token. Mandatory: `appName`, `deviceName`, `apkamPublicKey`, and
   (new ruling) a non-empty `namespaces`. Optional: `signingAlgo`, `metadata`
   (carrying the key package), `apkamKeysExpiryDuration` (absent = inherit the
   parent's), `encryptedAPKAMSymmetricKey` (absent = legacy material conveys
   client-side per [40](#40-rf-srv-is-the-mechanism-the-whole-model-stands-on-2026-08-05)).
   Response `{enrollmentId, status:'approved'}`; the errors are the four
   UnAuthorizedException refusals (no connection enrollmentId; parent missing or
   expired; parent unapproved; escalation) plus the throttle. The second delta: the
   `(appName, deviceName)` duplicate check is skipped on the APKAM branch, since a
   retrofit keeps its own name and scenario-3 siblings share one — the uniqueness
   property among approved enrollments ends here by design. at_server_spec gets the
   three-branch table (unauthenticated+OTP → pending; CRAM → approved root;
   APKAM → approved subset child).

2. **Revocation cascades eagerly, and revocation has two modes.** The parent link
   lives where the spike put it: `parentEnrollmentId` on the enrollment record, set
   only by self-enrollment. `enroll:revoke` in its default (compromise) mode
   enumerates enrollments, collects descendants transitively, marks each revoked,
   and drops each one's live connections — the existing per-id mechanics, applied
   over the walk. A lazy ancestor check at authentication was ruled out
   structurally: expired enrollments are deleted on encounter, so a dangling parent
   link cannot distinguish benign expiry from revocation. Unrevoke restores only the
   named enrollment. Item 6 adds the second mode — **retire**, no cascade, for
   planned migration off a shared keyfile; without it, retiring a cloned parent
   would kill the legitimate children each clone spawned. No authorisation delta:
   subset grants mean the parent's revoker is authorised for every descendant
   (record that property in the implementing commit's body). `parentEnrollmentId`
   is also exposed in `enroll:fetch` and `enroll:list`, so an owner can see what a
   stolen keyfile spawned.

3. **The cap slides.** [§5](#5-retrofit-ruling--fresh-self-spawned-auto-approved-enrollment)'s
   formula — min(now + grace, the enrollment's own expiry) — is applied on every
   sibling retrofit against the enrollment's pre-cap expiry, not folded into the
   previously capped ttl. The built min-fold made the first retrofit fix the
   deadline forever, which is [40](#40-rf-srv-is-the-mechanism-the-whole-model-stands-on-2026-08-05)'s
   stranding case arriving on schedule for any fleet that trickles. Sliding, the
   legacy credential dies one grace period after the *last* clone upgrades — the
   only finite policy that tracks the observable signal, a sibling still existing
   and upgrading. `apkamSelfEnrollmentGraceHours` is ratified at 720. Stranding
   past the window costs one OTP re-enrollment and KF-1 already specifies detecting
   it; the theft remedy is revocation (item 2), never the cap. Landing the sliding
   change found a third defect: a written ttl anchors at the write
   (`expiresAt = now + ttl` in the metadata builder), so the built
   `(now − createdAt) + grace` formula extended the cap by the enrollment's whole
   age — invisible to the spike's unit test because its parent was seconds old.
   The re-arm writes the grace as-is and re-derives "its own expiry" from
   `apkamKeysExpiryDuration`, since the record's current ttl is the earlier cap,
   not the enrollment's own posture. Landed on the spike; the min-fold, the
   posture bound, and both item-1 deltas are each pinned by a test proven red
   against the pre-fix handler.

4. **The chain sweep's runner is whichever fully privileged client next starts** —
   exactly what is built — and there is deliberately no dedicated sweep actor. On
   an atSign where no privileged client ever appears again, chained-but-unanchored
   is the accepted steady state per
   [38.3](#383-scenario-3s-problem-taxonomy-so-nobody-re-derives-it):
   defence-in-depth the verifiers already tolerate, not function. No CLI mandate,
   no server nudge. RF-SRV gains a requirement instead: the spawn moment runs under
   the parent credential, so it signs and conveys the child's chain link whenever
   that credential can sign one — the mirror of the approve-time conveyance — and
   scoped enrollments are born anchored, leaving the sweep as a repair for links a
   legacy approver could never sign.

5. **Last-holder-lost recovery is explicit rotation, and history stays lost.**
   Never automatic: store-and-forward cannot distinguish "no holder exists" from
   "holder offline", so a failed pull must not trigger a re-mint. Privilege is rw
   on the namespace — the bar the atServer's write gate on `public:__nskey.<ns>`
   already enforces. Records whose CKs were sealed only to the lost generation stay
   unreadable (rotation replaces the key; it does not decrypt the past), except on
   clients whose persisted CK cache holds the unwrapped CK. The API is B-2's rotate
   lever — mintAndPublish on an existing namespace is already rotation — with no
   dedicated recovery surface. nskeys only: the signing root never rotates, so a
   lost root is permanent and the tolerance of unsigned `_apsk` is the designed
   degradation.

6. **Clones share fate.** B-2 rotation and revocation assume an enrollment id may
   have any number of live holders, cryptographically indistinguishable:
   `enroll:revoke` cuts every clone, and `excludeEnrollmentIds` excludes every
   clone or none. B-2 never promises to unwind what one clone holds — only what
   the enrollment id holds. Per-device revocability exists only where each device
   holds its own enrollment id; RF-SRV is the path there, and the compromise recipe
   is: each legitimate device self-enrols its own id, then the shared id is retired
   (item 2's non-cascading mode) and the nskey rotated excluding it.

7. **Enrollment 1 retires by ageing out; revoke is for compromise.** The upgrade
   guide's five points: retirement is of the enrollment-1 *id*, not the keyfile —
   retrofit adds the new enrollment to the same `.atKeys` file, which keeps the
   legacy material
   ([37](#37-legacy-key-material-is-retained-until-the-ecosystem-is-pq-not-the-atsign-2026-08-05)),
   and the upgraded file becomes the backup. Timing: nothing to do; the grace cap
   retires it one window after the last retrofit (item 3). Never `enroll:revoke`
   as cleanup, since revocation cascades to every retrofitted child — this narrows
   [§5](#5-retrofit-ruling--fresh-self-spawned-auto-approved-enrollment)'s "(or an
   explicit enroll:revoke)" aside to the compromise case, where cascading is the
   point. A straggler past the window gets a loud auth failure, not data loss;
   recovery is a copied upgraded keyfile or a fresh OTP enrollment. Once the
   upgraded keyfile is archived, destroy pre-PQ `.atKeys` copies — they hold the
   legacy encryption private (harvest-relevant) and, until the cap elapses, a live
   credential.

8. **The in-place rsa→mldsa65 `_apsk` upgrade: no, ratified.**
   [39](#39-_apsk-rides-the-same-two-stage-ladder-2026-08-05)'s reasoning stands,
   and the code adds one more: `_apsk` is a verbatim copy of the enrollment
   record's key and PKAM is record-authoritative
   ([34](#34-pkam-is-record-authoritative-and-the-no-rsa-row-reads-narrower-than-it-looks-2026-08-04)),
   so rewriting the published value alone desynchronises the verify key from the
   credential PKAM checks — the upgrade would have to rewrite the enrollment record
   too, strictly more state mutation under the same missing authorisation rule.
   RF-SRV reaches the identical end state with mechanics already ruled.

9. **The tagged `_apsk` format: frozen as built.** A bare value is an rsa2048 key
   exactly as published today; a value starting `{` is JSON with required string
   fields `signingAlgo` (a SigningAlgoType name) and `publicKey` (base64 of the raw
   key for mldsa65), optional informational `v: 1` (the parser never reads it; bump
   only on incompatible change), unknown fields tolerated, unknown algorithm
   refused loudly. The old-parser failure mode is fail-closed and proven: every
   pre-PQ verifier base64-decodes the value, which throws FormatException on JSON
   (asserted in apsk_formats_test.dart). *Amended 2026-08-12: this ruling said
   "the atServer composes the tagged form from the enrollment record's
   (apkamPublicKey, signingAlgo) at publish time, keeping the record PKAM reads
   the single source". The atServer composes nothing since
   [at_server#2744](https://github.com/atsign-foundation/at_server/pull/2744) —
   it publishes `EnrollParams.apsk` verbatim and publishes nothing when a
   request carries none, so the format moved to the side that parses it and a
   new signing-key shape needs no server release. An enrollment therefore
   publishes the **array** form (`apskAdvertisement` in at_auth); the tagged
   single-key form stays readable but is written by nothing.* NoPorts, before any of its
   enrollments publish tagged: srvd's two ESCR verify sites are hardwired to RSA
   and fail loudly on a tagged value — fail-closed but service-breaking, so relays
   adopt the two-format parser first, ecosystem-wide. No other NoPorts path parses
   the value (checked: the sk-URI plumbing and the namespace check are
   format-independent).

10. **Stop-minting: one tri-state flag, next-major-after-R-2 at the earliest,
    repair-on-first-demand.** The flag is `bool? mintLegacyMaterial` on
    AtOnboardingRequest in at_auth — minting happens at onboarding, before an
    AtClient exists, so AtClientPreference is the wrong home. null resolves to the
    release default: true through at_client 4.x, false from the stop release;
    explicit true/false is the app's call either way. ON-1 implements this flag as
    its legacy-interop deliverable. The stop release is the next major after R-2 —
    5.0.0 at the earliest — cut when the ecosystem criteria are met: every
    first-party downstream's last published major writes PQ by default, and B-3
    phase 3's server tolerance is deployed across atServer implementations. The
    criteria gate; the number does not. Repair is on-first-demand, scoped to
    app-initiated operations that cannot proceed without legacy material — never a
    background sweep — minting the legacy keypair and selfEncryptionKey, publishing
    `public:publickey`, and conveying the self key over the substrate exactly as
    nskey privates convey, serialised by an immutable-create lock mirroring
    `_nskeylock`. Safe precisely because nothing was written under it, and its
    existence is what makes stopping early recoverable rather than a one-way door.

11. **The self-heal's trigger points are the built four.** (1) The start-time
    sweep — hydrate the answering store from AtKeys, then pull the *current*
    generation only if its private is absent. (2) The read-path on-miss pull — an
    exact-kid broadcast for any own generation a decrypt names, once per generation
    per process; this is
    [38](#38-key-material-self-heals-mint-if-absent-else-pull-2026-08-05)'s "older
    on demand". (3) The approve-time push of all held generations for the approved
    namespaces. (4) The mint-time push. Live-proven in
    nskey_self_heal_live_test.dart, and 38.1's no-callers finding is discharged.
    Moved to B-2 explicitly: the rotation initiator (nothing in production calls
    mintAndPublish for an existing namespace), rotation-time conveyance of the new
    generation, and threading excludeEnrollmentIds into the nskey pull/answer paths
    after a revocation — the substrate parameter exists and neither nskey call site
    passes it. The substrate's namePrefix support stays capability, not a trigger.

12. **The AtKeys lock ratifies on all three axes, with one named fix.** O_EXCL
    sidecar lock-file over flock — it serialises intra-process too (fcntl locks are
    per-process), survives Dart re-opening fds inside the section, and stays
    breakable on Windows since no handle is held open. 30s mtime staleness with
    delete-and-recontend, plus the 10s loud timeout — no permanent wedge, tested.
    The critical section is write and the whole flush read-validate-write, reads
    unlocked — temp+rename means a reader never sees a torn file, and the lock
    incidentally serialises the fixed-name .tmp/.bak siblings. The fixes, a
    condition of this ratification and landed with it: (a) the stale-break's
    unconditional delete was a TOCTOU — a breaker could delete a *contender's*
    fresh lock, admitting two holders, exactly when contenders pile up at the
    staleness threshold after a crash. The break now claims the file by rename
    and re-checks the claimed file's age: the corpse is deleted, and a live lock
    claimed in a rare race with a faster breaker is put straight back. (b) Release
    had the same shape one step later: a holder whose lock was broken as stale
    deleted the *successor's* lock by bare path on exit. The lock file's content
    (pid + acquisition time) is now the holder's release token — release deletes
    only its own. Both carry tests (at_auth 153 green).

## 43. RF-2b lands, and what the first genuine ML-DSA PKAM found (2026-08-05)

**In brief:** *3 defects under machinery that had read as complete for weeks*

The client half of the self-retrofit is built, and the first live ML-DSA PKAM
authentication ever attempted found three defects underneath machinery that had
read as complete for weeks. Proven end-to-end on the wire the same day:
`self_enrollment_retrofit_live_test.dart` drives no-OTP auto-approve, one
keyfile carrying both enrollments, PKAM under the new id with a genuine
ML-DSA signature (record-authoritative, so the pass is proof), the tagged
`_apsk` published by the atServer, the client-signed key package verifying
against it, and mint-once reuse.

### 43.1 The built shape

- **`AtSelfEnrollmentRequest`** (at_auth): APKAM-authenticated no-OTP
  submission — mint ML-DSA-65 keypair → metadataBuilder (the key package,
  signed mldsa65 by the NEW keypair) → `enroll:request` with
  `signingAlgo:mldsa65` → on `approved`, persist into the SAME keyfile.
  The whole check → mint → submit → persist span is serialised per keyfile by
  its own advisory lock (`<keyfile>.retrofit.lock`, staleness sized for a
  network round trip — the keyfile lock's milliseconds-scale settings still
  guard the flush inside). Mint-once is the check inside that lock: an
  existing active ML-DSA signing material under any enrollment id is reused,
  never re-minted — [design.md's "if the keyfile already carries a PQ APKAM
  keypair use it"](../design.md), now code. Accepted crash window: dying between
  the server's approval and the flush leaves an orphan approved enrollment
  whose private nobody holds — unusable, revocable, and a rerun spawns a
  fresh one.
- **The keyfile**: the new enrollment's material lands as typed materials
  under keyId **`apkam:<enrollmentId>`** (privateSigning +
  publicVerification, mldsa65) plus the key package's X-Wing halves re-tagged
  with the new id; the legacy flat fields are byte-frozen by the never-lose
  contract, which is what forces — correctly — the two-enrollments-one-file
  shape. `AtKeys.toAtChopsForEnrollment` / `signingAlgorithmForEnrollment`
  resolve an enrollment's chops and algorithm from the typed section, and
  `AtAuthImpl.authenticate` threads them automatically: authenticating with
  the new id ML-DSA-signs with no caller-supplied algorithm anywhere.
- **at_chops 3.4.2**: `PkamMlDsa65SigningAlgo` (synchronous, keys ride the
  String-typed pkam slot as base64 raw) and the pkam sign dispatch honours
  `signingAlgoType: mldsa65`; `signEnvelope` gains the mldsa65 branch its
  verify half already had. **The atServer** composes the tagged `_apsk` from
  the enrollment record's `(apkamPublicKey, signingAlgo)` at publish time
  for any non-rsa2048 algorithm ([42](#42-the-to-define-list-ruled-2026-08-05)
  item 9's server clause), bare stays frozen for rsa2048.
- **Deferred to RF-2c**: Monitor `signingAlgoType` threading (the monitor
  connection still reads `AtClientPreference`), the `(AtClient,
  enrollmentId)` kpid staleness
  ([20.3](#20-ss-2-how-the-key-package-reaches-an-enrollment-and-how-conveyance-fires-2026-08-03)),
  and the orchestration that turns UC-B1.x's full scenarios green.

### 43.2 Three defects under a green surface

1. **The atServer had never actually verified an ML-DSA signature.** It
   resolves the published at_chops (3.3.0), whose verification dispatch has
   no mldsa65 branch at all — an mldsa65 input fell through to the RSA
   verifier, which died parsing the raw ML-DSA key as ASN.1, surfacing as
   AT0010. Every existing "mldsa65 verify" test asserted record storage or
   enum mapping; nothing had ever driven a genuine signature through
   `processVerb`, so the first real caller — the retrofit live test — found
   it. The fourth no-caller mechanism on this branch, hours after the rule
   about them entered CLAUDE.md. Fixed: at_server's `pubspec_overrides.yaml`
   paths at_chops to the workspace 3.4.2 (floor bumped; remove when it
   publishes — and note the melos-managed overrides file REPLACES pubspec
   `dependency_overrides` wholesale, which silently discarded the first
   attempt), and the VE build mounts both repos so the override resolves
   in-container. `apkam_self_enrollment_test.dart` now drives a genuine
   ML-DSA `processVerb` round trip with a tampered-signature control.
2. **at_chops' own mldsa verification branch was async-poisoned.** 3.4.1's
   dispatch returned `MlDsa65PureDartAlgo`, whose `Future<bool>` verify was
   stored unawaited in the bool-typed result. Fixed in 3.4.2: the
   synchronous class serves both the sign and verify dispatch.
3. **Record-authoritative had a hole exactly where it mattered.**
   `recordSigningAlgo ?? wireClaim` let the wire claim pick the verify
   routine for every enrollment predating the `signingAlgo` field — which is
   every legacy enrollment, the population record-authoritativeness exists to
   protect. The hole was invisible while at_chops had no mldsa routine to
   mis-pick: the claim fell through to RSA by accident, and the
   record-authoritative functional test passed on that accident. With a real
   mldsa routine wired, the lying claim started failing legitimate RSA
   enrollments — caught by the same live suite. Fixed: on the APKAM branch an
   absent record algorithm resolves to rsa2048 explicitly (the handler's own
   comment already claimed this); the wire fallback survives only for legacy
   no-enrollment PKAM, which may honestly present `ecc_secp256r1`. This
   closes the gap in [34](#34-pkam-is-record-authoritative-and-the-no-rsa-row-reads-narrower-than-it-looks-2026-08-04)'s
   hardening story, and the unit control is the legacy-claim test beside the
   ML-DSA round trip.

### 43.3 Proof inventory and one harness lesson

Rails after landing, all green: at_chops **219**, at_auth **160**, at_client
**896**, at_secondary_server **863**, functional **128** live. The harness
lesson, re-learned the expensive way: CRAM onboarding is one-shot **per
recycled virtualenv across the whole suite run**, not per file —
`enrollment_test.dart` already consumes both dedicated CRAM atSigns, so a
second file CRAM-onboarding either of them fails whichever runs later. The
retrofit test builds its pre-PQ precondition from an ordinary OTP enrollment
on firstAtSign instead (approve with the demo keys, write the keyfile
directly), which consumes no one-shot state at all.

## 44. RF-2c: the switch-over, and what it cost to make a client PQ (2026-08-05)

**In brief:** *5 places the enrollment's algorithm and identity failed to travel*

RF-2b proved a retrofitted enrollment could *authenticate*. RF-2c makes it a
working **client** — and the gap between those two was five separate places
where the enrollment's algorithm and identity failed to travel.

### 44.1 The five, and the one rule behind them

The algorithm is a property of the **enrollment record**, not of the
preference object: one process can hold clients on two enrollments of one
atSign with different algorithms, so anything reading
`AtClientPreference.signingAlgoType` for a per-enrollment decision is wrong
by construction. `AtClient.signingAlgoType` is now resolved once from the
keyfile's typed material (mirroring `AtAuthImpl.authenticate`) and threaded
outward:

1. **`_createAtChops`** built the LEGACY enrollment's chops from the flat
   fields for any client, including one created with the retrofitted id —
   so it would have signed PKAM with the wrong key under the right id, and
   the record-authoritative atServer refuses that. Now branches on
   `signingAlgorithmForEnrollment`.
2. **`RemoteSecondary`** stamped `preference.signingAlgoType` onto the
   AtLookUp *unconditionally*, clobbering even a correctly-configured
   injected one (which is what at_auth hands over on the reuse path). Now
   takes a resolved override.
3. **`Monitor`** read the preference directly and had no algorithm input at
   all. It re-authenticates on every reconnect, so this was a permanent
   failure, not a first-connect one. Now takes the client's resolved
   algorithm; `SyncServiceImpl`'s third connection likewise.
4. **`wrapAndSign`** never passed a `signingAlgo`, so every runtime envelope
   (key package, nskey advertisement, conveyance, chain link) went out
   RSA-signed while the enrollment's published `_apsk` was tagged mldsa65 —
   refused by every verifier, loudly. Now signs with the client's algorithm.
5. **Key-package adoption** was newest-wins across the whole keyfile,
   ignoring `enrollmentId`. A retrofitted keyfile serves two principals, so
   a legacy client restarting on it would have adopted the PQ enrollment's
   kpid — an address its own record never advertised. Now
   enrollment-scoped: own tagged package first, untagged pre-id-era one as
   fallback, never a co-tenant's.

### 44.2 The kpid staleness, discharged by construction

[20.3](#20-ss-2-how-the-key-package-reaches-an-enrollment-and-how-conveyance-fires-2026-08-03)'s
deferred item asked what happens to per-client caches when the enrollment
changes under a live client. The answer RF-2c adopts: **it never does.**
`selfRetrofit` switches by building a NEW client under the
`(atSign, enrollmentId)` cache key, so every per-client cache starts fresh
for the new identity and nothing is re-keyed in place. This is now the
documented invariant rather than a fix — the alternative (mutating
`atLookUp.enrollmentId` on a live client) is what 20.3 warned about and no
code path does it.

### 44.3 Two findings from the live run

- **A concrete member added to an abstract class is invisible to
  `Mock implements` — at compile time.** `AtClient.signingAlgoType` has a
  default in the spec, but `implements` erases bodies and mocktail satisfies
  the interface through `noSuchMethod`, so 14 mocks across the unit suite
  returned `null` into a non-nullable getter and failed only at RUNTIME.
  `dart analyze` was clean throughout. Grep for `Mock implements <Type>`
  when adding a member to `<Type>`, before running anything.
- **RESOLVED — it was my test, not the product. `subscribe()` returning is
  not the atServer knowing you are listening.** A `notify` from the owner
  client, for a key in the retrofitted enrollment's own namespace, never
  reached that enrollment's monitor. There is no delivery bug: the scoped
  ML-DSA enrollment receives self-notifications correctly, proven by
  re-running the identical test with the trigger deferred until the monitor
  reports `NotificationListenerState.listening` — the ping arrives, status
  `delivered`.

  The race, from the captured timeline: the test's `subscribe()` logged at
  `17:54:18.697970`; the monitor's own socket then had to connect and PKAM,
  so `monitor:selfNotifications` was not written until `17:54:18.750550`
  — **52.58 ms later**, and the notify was issued inside that window. The
  monitor also asks for no backlog (`monitor started, last notification
  time: null`, because the runner wipes local Hive), so
  `monitor_verb_handler.dart`'s replay is skipped and a notification created
  in that window is **unrecoverable on that socket**. The live test now
  waits on `Monitor.currentStateStream` before triggering.

  **Three things this cost, worth carrying:**
  1. The [[feedback_listener_before_trigger]] rule needs sharpening for the
     Atsign Protocol: registering the client-side stream is *not* the
     registration that matters. The monitor is a separate socket that must
     connect and authenticate first, and `subscribe()` gives no signal for
     it — `Monitor.currentStateStream` reaching `listening` is the real one.
  2. **`atClientException == null` does not mean delivered.**
     `_waitForAndHandleFinalNotificationSendStatus`'s switch has arms for
     `delivered` and `undelivered` and no default, while the atServer's
     vocabulary is `delivered|errored|queued|expired` — so an *errored*
     notification returns silently. The assertion I added to prove the
     sender had sent proved nothing; the test now asserts
     `notificationStatusEnum == delivered`.
  3. **statsNotifications arriving prove the monitor socket authenticated
     and nothing more.** Reading them as "the stream is healthy" is what
     made a receiver-side absence look like a sender-side failure.

  Two real defects surfaced on the way, both fixed and worth keeping:
  `MonitorVerbHandler._sendNotification` dropped an unauthorized
  notification by bare `return` with no log at any level (now `warning`,
  per the dropped-event rule — and its absence is exactly why this
  investigation had nothing to read); and the at_server probe
  `enrollment_notification_delivery_test.dart` pins the authorization gate
  permitting the enrollment's own namespace and refusing a foreign one.

  **Instrument caveat that nearly derailed this:** the notify verb appears
  nowhere in either captured log, and that carries NO information.
  `TestUtils.initAtClient` pins `AtSignLogger.root_level = 'shout'`, and
  `AtSignLogger` copies the level once into a *detached* logger at
  construction — so flipping the root level later is retroactively inert
  for every already-built object. Concluding "the owner never sent it" from
  that absence would have been wrong.

## 45. The retrofit rows, and the five defects the first end-to-end run found (2026-08-05)

**In brief:** *B1/B2 green; the pull had no answerer, no gate and no correspondence check*

UC-B1.1/B1.2/B1.3 and UC-B2.1/B2.2 are green, proven live in
`tests/at_end2end_test/test/pq/retrofit_e2e_test.dart` and
`retrofit_retirement_e2e_test.dart`. The burn-down reads **33 of 40**.

The rows are what RF-2c owed. Writing them found **five defects**, none of which
any unit suite could have shown, because each is about what two enrollments and
a live atServer do to each other in sequence.

### 45.1 The signing-root step now runs in the retrofit flow

`PqSigningRoot.mintIfAbsent` had **no production caller** — only tests. The
retrofit is auto-approved by the atServer with no approver client in the loop,
so the approve-time conveyance that gives an ordinary new enrollment its root
never fires for it. A privileged retrofit could therefore complete, look
entirely healthy, and leave the atSign with no root at all.

`selfRetrofit` now resolves privilege from the atServer's enrollment record
after the switch-over and mints if the atSign publishes none. Inside its own
guard: the retrofit has already succeeded by then and the client is returned
either way.

### 45.2 The pull had nobody who could answer it

`requestPrivateIfAbsent` broadcasts to the namespace's key packages, and a
holder answers **out of its in-memory secret store** — which a restart empties.
Nothing ever re-primed that store with the root private a holder had filed
durably, so after any restart every holder was deaf and the request went out
to a world that could not reply. `PqSigningRoot.hydrateStore` is the supply
side, wired at start.

### 45.3 And the one sweep every client performs destroyed the requests

Worse, and only visible once 45.2 was fixed: client start swept **before** it
hydrated. A sweep consumes and *deletes* the envelopes it finds — pull requests
included — and answers them from the store. A holder that hydrated afterwards
was therefore guaranteed to destroy precisely the requests it was meant to
serve, and the requester, having spent its broadcast, waited for an answer that
no longer had anything to arrive from. The same ordering applied to the nskey
self-heal, whose `hydrateStoreFromFiling` sat after the same sweep.

Both supply sides now run first, in `_hydrateHeldSecretsForAnswering`, before
anything sweeps.

This is the sharpest lesson of the day, and it is a **generalisation of the
listener-before-trigger rule to store-and-forward**: when a request and the
material that answers it arrive through the same consuming sweep, the order
of *preparation* against *consumption* is a correctness property, not a
detail. It cost two e2e runs to find, and the tell was that the mechanism
worked perfectly when driven by hand in a different order.

### 45.4 Nothing stopped a scoped enrollment being handed the root

The answer path authorized requesters at **namespace** level only — the bar any
enrollment approved for the namespace clears. The signing-root private travels
as an ordinary secret under a reserved `__en.` name, so a namespace-scoped
enrollment could ask for the key that vouches for every enrollment on the
atSign and be served it. The requester-side guard that refuses to *ask* is a
courtesy; a modified client omits it.

`PairwiseSecretSharing.perEnrollmentSecretRequestGate` now decides. It **fails
closed** when unset, and `AtClientSecretSharing` wires the production resolver,
which reads the requester's enrollment record off the atServer and requires
full privilege. The pre-existing functional pull test was conveying the root to
a scoped enrollment and passing; it now uses privileged enrollments and carries
a scoped-refusal arm.

### 45.5 A conveyed root private was filed without being checked

`PqSigningRoot.file` stored whatever bytes arrived. A 32-byte buffer was filed
byte-for-byte and read back as "the root private" — and with the record
immutable and the root never rotating, that sticks. Filing now signs a probe
with the arriving private and verifies it against the published root, and
refuses on mismatch (safe: the keyfile stays empty, so the next start asks
again and a correct answer heals it). Two shapes of wrong key are covered — a
garbage buffer and a well-formed ML-DSA key that simply is not this one.

⚠️ **Amended 2026-08-15 by [101](#101-the-signing-root-becomes-an-ordinary-signing-key-and-rotatable-2026-08-15)
row 4: "the published root" is now "any root the record advertises".** The
check itself is unchanged and so is its purpose; what changed is the set it
checks against, because a record mid-rotation advertises a retired predecessor
beside the active successor and both are the atSign's own key. Judging against
the single active entry made a legitimate predecessor indistinguishable from
the garbage this ruling was written to refuse.

### 45.6 A create-race loser kept a private that corresponded to nothing

The mint files its private *before* publishing, deliberately. But the loser of
the immutable create was leaving that private filed and **active**, so the
pull's cheapest guard — "do I already hold it?" — answered yes forever and the
one heal a loser has could never fire. `mintIfAbsent` now retires the losing
pair (dead, not removed: `AtKeys` never removes material), and reconciles a
held private that does not correspond to a published root the same way. Two
more shapes fell out of writing it: a crash between filing and publishing now
republishes the **held** pair rather than minting a fresh one over a private
nobody could match, and both halves are filed so that recovery is possible at
all.

### 45.6b A failed publish is not evidence of a lost create

Also from the adversarial review, and the most dangerous thing it found. The
loser-retirement of 45.6 hung off the publish call's exception — but a throw
there says the *call* failed, not what the atServer did. The refusal of a second
create and a dropped connection on a write that **landed** throw identically,
and they need opposite handling. Retiring the pair in the second case leaves the
atSign with an immutable, non-rotating record whose private nobody holds:
unrecoverable, and caused by the recovery code.

The catch now asks the record instead of guessing. Published key equals this
client's → the write landed, keep the pair and anchor. Somebody else's, or none
→ genuinely lost, retire. **Cannot read it → keep the pair and say so at
`severe`**, because a later start can reconcile a held pair against the record
while a retired private cannot be un-retired.

This is the "never widen a `try` across an operation boundary" rule in its
sharpest form: the failure of the *report* was being read as the failure of the
*operation*, and the handler for one destroyed the other's state.

### 45.6c The pull could never cross an app namespace

The signing root is atSign-level and carries no namespace — the design says so
in three places — but a holder can only file it in its store *under* some
namespace, and the answer path listed the store filtered by the requester's app
namespace. So two privileged enrollments of one atSign belonging to different
apps never matched: the holder primed under its namespace, the requester asked
in its own, and the pull that is the only route to an unrotatable key was
silently never answered. (Every test had both sides in one namespace, which is
why nothing caught it.)

Explicitly **named** per-enrollment secrets are now answerable from any
namespace the holder holds them in. Named only: a prefix or bare request still
cannot reach another app's material, and *who* is served is unchanged — the
privilege gate above decides that, and it is stricter for exactly these names.

### 45.7 Server: a retrofitted child inherited an expiry it never enforced

The APKAM self-enrollment branch stored `apkamKeysExpiryDuration` in the
enrollment's JSON while writing **no ttl on the record**, so a child inheriting
a one-hour key-expiry posture never physically expired. A deployment's expiry
policy silently became immortality at the moment of upgrade. Fixed to mirror the
ordinary approve path, red-first.

### 45.7b And a child could state an expiry that outlived its parent

Found by the adversarial review over the diff, and the sharpest thing in this
section: `verifyNoEscalation` guards **namespaces**, and nothing guarded
**time**. `apkamKeysExpiryInMillis` came off the wire and was honoured verbatim,
so on the one enrollment path with no human in the loop, a stolen keyfile whose
enrollment was deliberately bound to an hour could self-enroll a child stating
`0` — the keystore's *never expires* — and walk away with a permanent
credential. A negative value did the same by a different route: the metadata
builder skips a negative ttl entirely, leaving `expiresAt` null. And the
immortal child, its own recorded posture now zero, would never re-enter
`_capEnrollmentExpiry`'s `ownMs > 0` branch when it later became a parent, so
the whole lineage escaped the bound the original credential was issued under.

A stated posture may now only **narrow** the parent's. Clamped rather than
refused, so a client asking for longer without knowing is corrected instead of
broken, and logged at `warning` because it is a request that was not honoured.

Worth stating plainly: writing the child's ttl (45.7) is what made expiry
*enforced* rather than merely recorded, and enforcing a requester-controlled
value is what turned a dormant gap into a live one. The fix belongs with it.

### 45.8 The harness: watching a cap age out

UC-B2's rows need a capped enrollment to actually elapse, and the ratified grace
is 720 hours. `runLocal.sh` now gives **one atSign** — `fourthAtSign` — a
zero-hour `apkamSelfEnrollmentGraceHours` by replacing its secondary's shared
`config` symlink with a private copy and restarting that one program. Per
secondary rather than the container-wide env var, because at grace 0 a retrofit
kills its parent within a millisecond and the B1 clone rows need a parent that
survives its sibling's retrofit.

The row is a **differential on both axes**: a sibling legacy enrollment that
never retrofits still authenticates in the same run (so the lockout is the cap,
not the environment), and the same test against the default grace shows the
un-upgraded copy authenticating normally (so the window is what decides). The
refusal is asserted as `AT0028 … expired or invalid` by name rather than as any
throw.

### 45.6d "A later start reconciles it" was a promise nothing kept

The completeness critic's finding, and the one that closes 45.6b's loop. All
three recovery arms lived inside `mintIfAbsent`, whose only production caller
is the retrofit — a once-per-keyfile flow. So the severe log that says *"a
later start reconciles it against the record"* named a start path that did no
such thing, and the state it describes is self-entrenching: a private
corresponding to nothing published satisfies the pull's cheapest guard so the
enrollment never asks; `store` treats it as already-held and drops a correct
private conveyed to it; the chain link gets signed with it; and — once
hydration landed — it is *offered to other enrollments*, spending their
broadcast on bytes their own check then rejects.

`reconcileHeldPrivate` now runs on the ordinary start path, before hydration.
A mint happens once per keyfile; a start happens every time, which is where a
heal belongs.

### 45.6e The keyfile, not the enrollment record, decides what a holder primes

Fixing 45.3 broke it in a way only the review caught: the reorder put
hydration *before* `AtClientManager` wires `enrollmentService`, whose getter
**throws** until then. `authorisedNamespaces` swallows that and reports "no
authorised namespaces", so for every APKAM-enrolled client the nskey supply
side primed nothing — silently, on every start — and the sweep that followed
went straight back to destroying requests it could not answer. The fix that
had just landed was inert for the population it mattered most to.

Priming now reads the **keyfile** (`NskeyPrivateFiling.readAll`, parsing the
`nskey.<namespace>.<kid>` key id). No round trip, no service dependency, no
ordering to get wrong — and it is the more correct question anyway: what a
holder can answer with is what it *holds*, not what it is *authorised for*.

Two lessons worth keeping. **A getter that throws is a control-flow edge**,
and one swallowed two layers up is invisible: this failed silently in exactly
the population it was written for. And **fixing an ordering bug is itself an
ordering change** — the fix inherited the class of problem it removed.

### 45.9 The review found five of the ten

Five defects came out of writing the rows; **five more came out of an
adversarial review over the finished diff** — the expiry escalation (45.7b),
the publish-ambiguity brick (45.6b), the cross-namespace pull (45.6c), the
unreachable reconciliation (45.6d) and the inert hydration (45.6e). All five
are in code written that same day, all five were reachable in production, and
none was a style note.

Three of the five are in **recovery** paths, which is the pattern worth
carrying: code that runs only when something has already gone wrong gets the
least exercise and does the most damage. Two more, 45.6d and 45.6e, are the
same shape one level up — *the fix for a defect carried the defect's own
class*: a heal with no caller, and an ordering fix with an ordering bug.

The review also caught two **tests that proved nothing**. The first
cross-namespace test reused a secret name the group's `setUp` had already
seeded under the requester's namespace, so the ordinary lookup answered and it
passed with the fix reverted. The negative-expiry server test read a missing
ttl as `?? 0` and so passed for the absence it was pinning against. Both were
caught only because the red proof was actually *run* rather than assumed —
which is the whole value of the rule.

### 45.10 What is still owed

**UC-B0.1** — a PQ-capable client aborting cleanly against a *legacy* atServer —
remains the one skipped retrofit row, and it is blocked on the **harness**, not
on RF-SRV: no suite here can produce an atServer image without the retrofit
verbs. Re-scope or waive it, the way UC-A3.2 was; leaving it labelled `RF-SRV`
reads as waiting on code that already exists.

## 46. RFC 9180, and where the design's version hatches are (2026-08-05)

**In brief:** *pqSeal stays custom until D2; two signed payloads carry no version, and the signing root is unrewritable*

Writing the at_java hand-off deck put a sentence on a slide — `pqSeal` is not
RFC 9180 HPKE, it is an Atsign-internal envelope with a custom key schedule —
and that raised two questions. Should we move to RFC 9180 now, and is anything
else here homegrown where a standard exists? For the constructions the answer is
that they can wait. For the *versioning around them* it is that two signed
payloads carry no version at all, and one record can never be rewritten.

This entry records the analysis. No code changed.

### 46.1 pqSeal stays custom, and D2 is when we revisit it

> **AMENDED 2026-08-06.** This entry asked for its own homework — *"I have not
> verified the current CFRG and IANA position; check it before D2"* — and the
> check was done. **Three of the four premises below are false**, and the
> "same bespoke code with a specification attached" line does not survive being
> tested. The paragraphs are left as written, because a ledger that quietly
> rewrites itself is worth less than one that shows its corrections; read
> [48](#48-the-standards-question-reopened-and-what-the-check-found-2026-08-06)
> for what is actually true, and do not re-derive a conclusion from the reasons
> below. The one thing this entry got right and acted on is at the end of it:
> the missing cross-language vector file, now built.

Two escape hatches exist and both are real. `ver` is the envelope's first byte,
checked before anything else, and an unknown value raises a typed
`versionMismatch` rather than a garbled decrypt; `_suiteLabelFor(version)` then
domain-separates the key schedule per version, so a `0x02` construction cannot
be confused with a `0x01` one even if the dispatch were wrong. Above that,
`appMetadata.providerId` names every algorithm a reader needs code for
([16](#16-a-provider-id-names-every-algorithm-a-reader-needs-code-for-2026-08-02)),
so a different construction can arrive as a different provider id and coexist
per value, with reads staying universal.

Against moving now: the prize is interop with off-the-shelf HPKE, and it does
not exist for this ciphersuite yet. X-Wing needs an HPKE KEM id *and* library
support in both Dart and Java, and without both, "use the standard" means
hand-writing HPKE's key schedule in two languages, which is the same bespoke
code with a specification attached. (I have not verified the current CFRG and
IANA position; check it before D2 rather than assuming either way.) We also use
exactly one mode — Base, single-shot, a fresh encapsulation per message — so
HPKE's psk modes, sequence numbers, `base_nonce ^ seq`, exporter secrets and
multi-message contexts buy nothing here. And X-Wing's own combiner is
`SHA3-256(ss_M || ss_X || ct_X || pk_X || label)`
(`x_wing_pure_dart.dart:172`), so `ct` and `pk` are already bound, which is what
DHKEM's `kem_context` gives HPKE.

For moving eventually: reviewability. "RFC 9180 Base mode, KEM=X-Wing,
KDF=HKDF-SHA256, AEAD=AES-256-GCM" is a sentence an auditor checks, where an
HPKE-shaped custom schedule is one they have to read line by line. **D2 forces
the question anyway**, since MLS uses HPKE natively and `at/pqmls` brings an
HPKE implementation into the tree regardless. Aligning D1's seal to it at that
point is consolidation rather than migration, which is why D2 is the trigger.

D1 therefore keeps `pqSeal`, and `ver = 0x02` is reserved for an RFC 9180
encoding.

One thing a standard would have given us free, and has not: a committed
cross-language test-vector file that at_java conforms to. Not built.

> **BUILT 2026-08-06** (`4ae02e319`) — `docs/projects/pq/seal-spec.md` and
> `packages/at_chops/test/vectors/pq_seal_v1.json`. This sentence was the most
> useful thing in the entry, and [48.5](#485-the-vectors-are-the-deliverable-not-the-migration)
> argues it should have been the conclusion rather than a closing aside.

### 46.2 The versioning audit

| Structure | Carries a version? | Replaceable later? |
|---|---|---|
| `pqSeal` envelope | `ver` byte + a per-version suite label | yes, as `0x02` |
| `SecretEnvelope` | `v` and `suite` | yes, but see [46.4](#464-the-sealing-suite-is-stamped-not-negotiated) |
| `KeyPackage` payload | `v`, plus `keys[].alg` | yes |
| Approval-chain link payload | `v` | yes |
| Tagged `_apsk` value | `v` | yes |
| A value's `appMetadata` | `providerId` names the algorithms | yes, per value |
| **Signed-envelope wrapper** | **none** | see [46.3](#463-the-signed-envelope-signs-re-encoded-json) |
| **nskey advertisement payload** | **none** | see [46.3](#463-the-signed-envelope-signs-re-encoded-json) |
| `pq_signing_root` record | `v` and a reserved `successor` | **no** — see [46.5](#465-the-signing-root-is-the-only-one-way-door) |

### 46.3 The signed envelope signs re-encoded JSON

`signEnvelope` returns `{payload, signature, hashingAlgo, signingAlgo,
enrollmentId?}`, and `verifyEnvelope` re-derives the signed bytes with
`signableTextOf(envelope['payload'])`, which is `jsonEncode` of the *decoded*
payload. So the signature covers non-canonical JSON, and it holds only while one
serialiser sits on both ends. The code says as much itself: stable "because Dart
maps preserve insertion order through a `jsonEncode`/`jsonDecode` round trip".
Java offers no such guarantee across libraries — Gson HTML-escapes `<`, `>`,
`&`, `=` and `'` by default, and number formatting and non-ASCII escaping vary
by library and configuration. This is the class of defect that passes every Dart
test and fails on the first cross-language envelope.

Two things soften it. `signableTextOf` already signs a `String` payload as-is,
so a JWS-shaped payload (base64url of the canonical bytes) would verify under
today's verifier with no change to the signing code; and the two-release model
already carries a shape change of this kind. What it does not carry is the
consumers: `ApkamSignedAdvertisedKeys.verify` requires `envelope['payload']` to
be a `Map` and rejects a `String`, so an old reader fails at the parse rather
than at the signature.

The standard answers are **JWS (RFC 7515)**, which removes canonicalisation from
the problem by signing the encoded bytes, and **JCS (RFC 8785)** where the JSON
has to stay readable.

The defect underneath is narrower than the canonicalisation question, and worse:
neither the wrapper nor the nskey advertisement payload carries a version, so a
reader has nothing to dispatch on if the construction changes. Every other
signed payload in the design carries one. Adding `v` costs one line today and a
coordinated two-SDK release once at_java is in the field.

### 46.4 The sealing suite is stamped, not negotiated

The sender always stamps `SecretSharingAlgos.xWingHpke`
(`pairwise_secret_sharing.dart:255`) and a receiver checks membership and skips
with a `warning` when it cannot open the suite (`:454`). A key package
advertises `keys[].alg` but not which *suites* its holder can open, so a sender
has no way to discover that. A second suite therefore needs every reader
upgraded first, which the two-release model handles, so suite agility here is a
release-ordering property rather than a negotiated one. Worth knowing, because
the presence of a `suite` field reads like more agility than there is. If we
want it negotiated, the place is a `suites` list beside `keys[]` in the key
package, and the key-package format is what at_java is about to fix in a second
implementation.

### 46.5 The signing root is the only one-way door

> **SUPERSEDED 2026-08-15 by
> [101](#101-the-signing-root-becomes-an-ordinary-signing-key-and-rotatable-2026-08-15)
> — the door gets a hinge.** The record becomes mutable behind an explicit mint
> lock, exactly as [13](#13-the-nskey-is-published-eagerly-mutable-and-generation-addressed-2026-08-02)
> did for the nskey, and `successor` is deleted rather than implemented. Two
> claims below are worth keeping as the record of how they were reached and are
> no longer true: that `successor` is the only migration path, and that nobody
> can replace a published root. The second also overstated the constraint —
> `Metadata.immutable`'s own dartdoc permits a delete with `force:`, and more
> to the point nothing is released, so every atSign carrying a root is ours.

`public:pq_signing_root@<atSign>` is immutable and never rotates. Its value
carries `v: 1` and a reserved `successor`, but the record cannot be rewritten,
so the version field cannot save it: a later reader can *detect* a v1 root, and
nobody can *replace* one. `successor` is the only migration path and it is
unimplemented ([18](#18-pqpublickey-becomes-the-user-owned-signing-root-2026-08-03)).

The format also disagrees with its own documentation. The code publishes
`{"v":1,"keys":["<base64>"],"successor":null}` (`pq_signing_root.dart:208-211`)
and reads it back as `base64Decode((record['keys'] as List).first as String)`
(`:108`), while `acceptance.md`'s key-objects section documents `keys` as
`[{"alg":"ml-dsa-65","pub":"<base64>"}]`. The one structure that can never be
rewritten is the one whose shape the docs and the code disagree about.

Recycled virtualenv roots are disposable, so nothing is lost yet. The moment a
root is published on an atSign we do not recycle, the shape is permanent.
Settling which of the two forms is correct is the only item here with a
deadline.

### 46.6 The rest of the sweep, homegrown against standardised

Read rather than assumed:

- **HKDF-SHA256** (`hkdf.dart`) is RFC 5869 extract-then-expand, and its
  empty-salt shortcut is genuinely HMAC-equivalent to the RFC's zero-filled
  default.
- **X-Wing** follows `draft-connolly-cfrg-xwing-kem-10`, combiner and SHAKE-256
  seed expansion included. It is a CFRG draft rather than an RFC, and drafts
  have changed the combiner between versions, so interop is pinned to draft-10
  and a draft advance is a `ver = 0x02` event. X-Wing is also not a
  NIST-approved construction, which would matter to a FIPS requirement; recorded
  so it is a known choice rather than a later discovery.
- **ML-KEM-768** (FIPS 203), **ML-DSA-65** (FIPS 204), **X25519** (RFC 7748),
  **AES-256-GCM** (SP 800-38D), **SHA-3 / SHAKE-256** (FIPS 202) and
  **Argon2id** (RFC 9106) are all standard.
- **Legacy AES-256-CTR falls back to a 16-byte zero IV** when none is supplied
  (`encryption_util.dart:15-22`, and `aes.dart`'s `_getIVFromBytes`, both
  carrying the same "from the bad old days when we weren't setting IVs"
  comment). Under a long-lived `selfEncryptionKey`, two records sharing that IV
  share a keystream. It is legacy and being retired, and how much live data
  still carries a null `ivNonce` is worth measuring, since for some audiences it
  is a stronger argument for the D1 migration than the quantum one. PKCS7
  padding on a stream cipher is pointless and leaks length granularity.
- **MD5** survives as the `pubKeyCS` checksum
  (`legacy_encryption.dart:70-72`), already paralleled by a SHA-512
  `pubKeyHash`. It retires with the legacy provider.
- **Base2e15** is a homegrown binary-to-text encoding rather than crypto, and
  at_java has to reproduce it byte-exactly.
- **The kid derivations** are truncated SHA-256, a convention rather than a
  standard, and sound as used: collisions are refused rather than overwritten
  (`content_key.dart`). The defect there is consistency, not strength —
  `ckKid` and `nskeyKid` hash raw bytes while `kpid` hashes the base64 *string*
  (`key_package.dart:29`).

### 46.7 What this entry does not rule

Per the rule that a ledger ruling names a mechanism only once its differential
test is green, the above records defects and intent, not fixes. Four items are
open with no code written, and they are **tracked in
[`implementation-plan.md` §14](implementation-plan.md#14-backlog--carried-items-with-no-owning-project)**
so they are visible from the plan rather than only from here:

1. the signing root's `keys[]` shape, the only one with a deadline — and the
   deadline is a *state*, not a date: the shape freezes the first time a root
   lands on an atSign nobody recycles;
2. a `v` on the signed-envelope wrapper and on the nskey advertisement payload;
3. whether the envelope construction moves to JWS or JCS, which can wait behind
   (2), since the version field is what makes that choice reversible;
4. a `suites` list on the key package, cheap now for the same reason as (2) and
   safe to defer if we accept release-ordering agility.

## 47. B-2 lands: two levers, and the difference between excluding and revoking (2026-08-06)

**In brief:** *nskey-keypair rotation vs content-key rotation; an exclusion is a courtesy and the revoke is the enforcement*

The rotation slice is built. Both levers existed on paper and one of them
existed in code as an accident — calling `mintAndPublish` twice on a namespace
IS a rotation — but nothing in production ever called it that way, nothing
carried the successor to the surviving enrollments, and no caller could say
which enrollment to leave out. The forward-secrecy lever did not exist at all.

### 47.1 The two levers, kept apart on purpose

`design.md` §1.7 spends its first paragraph insisting B5a and B5b are not
substitutes, and the code now says so in two class names rather than one.

**`NskeyRotation` (B5b)** mints the next nskey keypair, overwrites
`public:__nskey.<ns>`, and pushes the successor private to the namespace's
other enrollments minus an excluded set. It denies an enrollment the keys
protecting data written from now on. It costs one conveyance per enrollment and
it reaches nothing already written: every earlier private is retained by
construction — privates are filed per `nskeyKid` and nothing removes them — so
retained `__ck` records sealed to a superseded generation still open.

**`CkManager.rotateContentKey` (B5a)** cuts a fresh content key and, with
`deleteSuperseded`, deletes the conveyance record carrying the old one. That is
the only operation in the system that makes already-written data unreadable:
the nskey private cannot help once no sealed copy of that CK survives. O(1),
one record, on ordinary sync rather than the substrate.

Two orderings carry B5a's correctness, and both were red-proven. The delete
happens **after** the successor is durable — deleting first and then failing the
conveyance write would leave the destination with no readable past AND no key
to write the next value under, the one state worse than not rotating. And the
superseded `ckKid` is read from the **current-CK pointer** as well as the cache,
because the process that cut it may not be this one; without that a rotation
from a freshly started client supersedes nothing, leaves the old conveyance
live, and reports a forward secrecy it did not deliver.

A delete that fails is `severe` and does not roll back the rotation. Writes are
correct from there on; what was lost is the forward secrecy, and a caller that
believes it rotated for FS has to hear that it did not.

### 47.2 Deleting the record is half of it; eviction is the other half

Deleting the conveyance stops anyone unwrapping that CK *again*. It says nothing
about the clients that already did: they hold the plaintext key in their own
caches and would go on reading the very data the deletion was meant to close
off. Sync is what carries the deletion to them, so `ContentKeyEviction` turns a
`remoteToLocal` DELETE of a conveyance record into a cache eviction, and
`AtClientImpl` registers it on every sync service it is given.

That is what makes coarse forward secrecy a fleet-wide property rather than a
property of the deleting client alone — bounded, exactly as the design says, by
eviction **reachability**: a device that never resyncs keeps its copy. That
residual is named, not solved.

One parsing note worth keeping: the conveyance key is split on its `.__ck.`
marker, never through `AtKey.fromString`, which cuts at the **last** dot.
`abc.__ck.app_1.my_apps@alice` parses back with namespace `my_apps`, and
evicting under that would miss the entry and leave the CK live — a silent
failure of the security property, with the delete looking successful.

### 47.3 Losing the mint lock fails a rotation; it resolves a mint

`PublishedNskeyKeyRing.rotate` differs from `mintAndPublish` in one way and it
is the way that matters. A cold-start mint that loses the race adopts the
winner's key and is done: the atSign has a key, which is all that was wanted. A
rotation that adopts what it finds has rotated **nothing** while reporting
success — and since rotation is the revocation lever, the enrollment it was
excluding is left holding the live generation. Rotating a namespace with no
published key is refused for the same reason: that is a cold-start mint wearing
a rotation's name.

### 47.4 An exclusion is a courtesy; the revoke is the enforcement

This is the ruling the live run forced, and it corrects an assumption the first
version of the e2e test was written on.

`excludeEnrollmentIds` stops **this** client pushing to the named enrollments.
It cannot stop another holder answering their pull, because a holder honours
only what the atServer tells it, and the atServer's signal for "this enrollment
gets nothing" is revocation — not a list one client happens to be holding. A
still-approved enrollment is still a member of the namespace, so it asks any
holder for the generation it can see published and is answered. Exclusion alone
is a courtesy in exactly the sense `shareAllSecretsWith`'s namespace filter is.

So `revokeEnrollmentAndRotate` revokes **first**, and the ordering is the
enforcement rather than a preference. Revoking drops the enrollment out of
`enroll:listns` — `getEnrollmentsForNamespace` returns approved enrollments only
— so by the time any rotation runs it is absent from every roster and refused at
every serve, including pulls answered by holders that never heard of the
operation. Rotate first and the same enrollment can request the successor from
another holder in the gap, undoing the rotation it was the point of.

A namespace that fails to rotate is `severe` and the rest are still attempted:
the revoke has already landed by then, and abandoning the remainder leaves the
atSign in the worst of both states — an enrollment cut off from the server but
still holding every live namespace key it had.

This implements [42](#42-the-to-define-list-ruled-2026-08-05) items 5
(last-holder-lost recovery is an explicit rotation, history stays lost) and 6
(clones share fate: an enrollment id may have any number of cryptographically
indistinguishable holders, so revoke cuts every clone and exclude excludes every
clone or none), plus the three pieces item 11 moved here — the rotation
initiator, rotation-time conveyance, and `excludeEnrollmentIds` reaching the
nskey paths.

### 47.5 The two privileges are different, and the failure said the wrong thing

Found by the first live run, not by any unit test. **Rotating** needs `rw` on
the namespace — the bar the atServer already enforces on the advertisement
write, and a scoped device enrollment clears it. **Revoking** needs `__manage`,
and a client without `__manage` also cannot *enumerate* enrollments:
`enroll:list` returns it only its own record.

So a scoped caller's `revokeEnrollmentAndRotate` failed with *"no enrollment
&lt;id&gt; to revoke"* — which reads as a wrong id and sends the caller looking
in entirely the wrong place. The composition now names the missing privilege
before it attempts anything, and reports that nothing was revoked and nothing
rotated.

### 47.6 Two defects in the enrollment path, both from the same shape

`_openIfSymmetricKey` documents that "every rejection is a skip rather than a
throw", and its `_verifyAgainstApsk` doc says a revoked enrollment's missing
`_apsk` is the intended skip. Neither was true. The skip caught only
`AtSigningVerificationException`, and:

1. an **absent** `_apsk` comes back as a thrown AT0015, not as null — so the
   revoked-enrollment case the doc describes killed the whole approval instead
   of skipping one envelope;
2. a **malformed** `_apsk` throws `FormatException` out of `base64Decode`, with
   the same result.

Both escaped to fail `waitForApproval` outright. Since a revoked enrollment
produces the first, one stale envelope of its making could fail every later
enrollment that scanned past it — a failure that only appears on an atSign where
something has been revoked, which is why it survived until B-2 revoked anything.
The skip now catches everything from that one operation, and the second defect
was found by the *control arm* of the test written for the first.

### 47.7 What the live run cost, and the two tests that were lying

Three findings, all from running rather than reading.

**The suite failures were the tests polluting a shared identity.** The rotation
file created eight enrollments on `@alice🛠` and revoked one. Every
`enroll:listns` walks the whole roster, and a revoked enrollment's `_apsk` is
deleted for good — so the file passed alone and took two unrelated files down
inside the full run, one of them by timeout. Moved to `@bob🛠`, which is what
the package's own rule about one-shot server-side state already says.

**Two assertions were asserting a race.** The first version claimed the excluded
enrollment got nothing and passed once; the second claimed it got the successor
and passed once. Both were true only on timing, because whether a background
self-heal pull completes inside a test is not a property. The exclusion is now
asserted where it is deterministic — the roster the push enumerates, with the
unexcluded control arm — and the serve side is pinned at unit level, where a
holder demonstrably refuses a requester the roster no longer lists and serves
the same request while it is still listed.

**And the roster is polled, with a bound.** `enroll:listns` is served through the
atServer's enrollment cache, and a roster read taken *before* the revoke — which
the control arm deliberately takes — was observed still stale on the first read
after it. The poll is bounded so this stays an assertion: if the roster never
catches up, the test is red and names a real defect, because a revoked
enrollment other holders still see is one they will still push secrets to.

### 47.8 Proof inventory

Twenty-one red proofs run against the pre-fix code, not assumed: the lock-loss
adoption, the cold-start guard, the exclusion reaching the roster query, the
revoke-before-rotate ordering, conveying without reading the durable copy back,
revoking an unknown enrollment, abandoning the remaining namespaces after one
fails, falling back to in-memory key storage, the `__manage` guard, deleting
before the successor is durable, deleting without evicting, a failed delete
rolling back the rotation, the missing pointer fallback, the eviction listener's
direction and `commitOp` guards, the last-dot key split, the listener never
being registered, and the narrow catch in the enrollment path.

Rails: at_client **967** unit, functional **137**, e2e **50**.

One test outside B-2 had to change. `switch_atsign_test` asserted the sync
service held exactly **one** progress listener after an atSign switch, using the
count as a proxy for "the previous atSign's listeners were cleared". The SDK now
registers one of its own, so the count stopped meaning that; the test names the
listeners it expects and the one it does not.

## 48. The standards question reopened, and what the check found (2026-08-06)

**In brief:** *3 of 46.1's 4 premises are false; the vectors are the deliverable, not the migration; `.atKeys` salted its derivation with the passphrase*

Gary reopened [46](#46-rfc-9180-and-where-the-designs-version-hatches-are-2026-08-05)
with a framing that changes the objective function rather than the facts:

> ANYTHING non-standard that a bunch of non-cryptographers like me do will be
> regarded dubiously; but at least if we're just implementing a standard, it can
> be verified correct or not.

So the test is not "is this secure" — assume competent review says it is — but
"can somebody who does not trust us check it". Everything below is scored on
that. The ruling is to move on all three of RFC 9180, the KEM citation and JWS,
and to fix the `.atKeys` derivation ahead of GA.

### 48.1 Three of 46.1's four premises are false

46.1 asked for this check explicitly and it was overdue.

| Premise in 46.1 | What the check found |
|---|---|
| "X-Wing needs an HPKE KEM id" | **False.** IANA registers it at `0x647A`, and has since draft-06. |
| "…*and* library support in both Dart and Java" | **Half false.** at_java already pins Bouncy Castle 1.84, whose jar carries `org/bouncycastle/pqc/crypto/xwing/` *and* `org/bouncycastle/crypto/hpke/` with a pluggable-KEM constructor. Java writes no primitive code. Dart genuinely has nothing — that leg stands. |
| "…hand-writing HPKE's key schedule in two languages" | **False.** One language, and about 70 lines. |
| "D2 forces the question anyway" | **False as scoped.** D2-1 is the v1 epoch engine and explicitly not MLS; HPKE arrives at M6, behind M4 and M5, with no design written. "Wait for D2" is an indefinite deferral, not a short one. |

The conclusion (defer the seal) may still stand on scheduling grounds. The
stated reasons do not, which is worse than no entry — a future reader
re-derives the wrong conclusion from them.

### 48.2 "The same bespoke code with a specification attached" does not survive testing

That line is 46.1's argument against moving, and it treats "code we wrote" as
the unit of trust. The unit is the triple of *specification, vectors,
implementation*, and adopting a standard replaces two of the three with
somebody else's.

Tested rather than argued, twice independently: RFC 9180 base mode written from
the spec in about 70 lines reproduced the IETF HPKE working group's published
`key`, `base_nonce` and `exporter_secret` on the first run, and a deliberate
one-byte error in the mode field turned it red. Against that, both `pqSeal`
"known-answer vectors" in `pq_hpke_test.dart` are goldens this implementation
produced — the file says so at `:172-177` — so they can only ever prove we have
not drifted from ourselves.

The part of the original phrasing worth keeping: a specification **without**
vectors really is close to nothing. The thing to buy is the vectors.

### 48.3 The KEM was already conformant; the citation was the problem

`draft-connolly-cfrg-xwing-kem` is an unadopted Independent Submission that
**expires 2026-09-03**, and its Appendix C is titled "Test vectors # TODO:
replace with test vectors that re-use ML-KEM, X25519 values". It was the
weakest citation available for the construction, and OpenJDK has already
refused an X-Wing contribution on exactly that ground.

The bytes were never in doubt. Three independent IETF work streams — CFRG's
hybrid-KEM drafts, the HPKE working group, and LAMPS composite KEM — converged
on the same combiner shape, `draft-irtf-cfrg-concrete-hybrid-kems` section 4.2
says its `MLKEM768-X25519` "is identical to the X-Wing construction", and the
combiner has not changed since draft-05. at_chops' **unchanged** X-Wing
reproduces the working group's published `0x647A` vectors across all three
operations, in both backends. Landed in `24b997224`.

Two things that must never be written down wrongly:

- **The IANA row still reads "X-Wing"**, referencing draft-06. The rename to
  `MLKEM768-X25519` is *requested* by `draft-ietf-hpke-pq` and has not been
  effected. Claiming the registered name is `MLKEM768-X25519` is falsifiable in
  one click by exactly the reviewer this exercise targets.
- **Bouncy Castle 1.81 is a hard floor.** Releases 1.78 to 1.80 carry X-Wing but
  feed the combiner label first rather than last, deriving a different shared
  secret. Because X-Wing rejects implicitly, the symptom is an opaque AEAD
  failure, not a key error.

### 48.4 Not switching the KEM, and the FIPS story it cannot buy

The enrollment key package is write-once, so old enrollments' advertised keys
are frozen and senders must keep X-Wing whatever we choose. "Switch to
X25519MLKEM768" and "switch to plain ML-KEM-768" are both really "support a
second KEM", at the price of a migration that retires nothing.

And migrating the seal to RFC 9180 does **not** open a FIPS gate: X25519 key
agreement has no approved path in the SP 800-56 series, so X-Wing is
unclaimable under FIPS whatever sits on top of it. If a FIPS-facing buyer ever
appears the answer is a second suite selected by provider id, and
`MLKEM768-P256` is already registered at HPKE `0x0050`. Do not let the RFC 9180
question be sold on a story it cannot deliver.

CNSA 2.0 is deliberately absent from this entry. `media.defense.gov` returns
HTTP 403 to automated fetching for both the FAQ and the algorithms PDF, so
every CNSA claim available is secondary. Recorded so nobody re-burns the
attempt, and so no CNSA sentence goes into this ledger as a quotation.

### 48.5 The vectors are the deliverable, not the migration

A migration buys a standard's *name*; a vector file buys a runnable *check*.
The asymmetry is decisive here because our own tree has already run the
experiment. The tagged `_apsk` shape **carried a version field** — it did
everything [46.2](#462-the-versioning-audit)'s table asks for — and it still
forked across two atServer implementations inside a week, with the divergent
side's own documentation asserting a conformance that was false. A version
field did not catch it. A specification would not have, since the specification
was a Dart function. An audit is structurally silent on it, because an audit
attests one implementation at one point in time. A vector file turns red on the
next build.

So the evidence layer went first, and all of it is landed:

| What | Where |
|---|---|
| X-Wing against the HPKE WG's `0x647A` vectors, 3 operations, both backends | `24b997224` |
| ML-DSA-65 against 70 NIST ACVP vectors, including NIST's own negative cases | `e11585254` |
| X25519 against RFC 7748 sections 5.2 and 6.1 | `e11585254` |
| `atPQv1-base` byte-level spec + 95 conformance rows | `4ae02e319` |

ML-DSA-65 is worth calling out: it authenticates every PQ enrollment and had
**no** conformance evidence at all, only length and round-trip assertions.

`seal-spec.md` closes the gap 46.1 named and left open. It was validated the
only way a specification can be — reimplementing its key schedule from the
document text alone, with a different HMAC, matching all 15 vectors. A
specification nobody has built from is a claim, not a document.

### 48.6 The `.atKeys` derivation was worse than anything in the question

Nobody in the original three-way question was looking at the file that holds
every key. `Argon2idHashingAlgo` passed `nonce: password.codeUnits` — **the
passphrase was its own salt**. Derivation was deterministic, so two users who
chose the same passphrase got the same AES key and one precomputation table
served all of them. Around it: parameters below the OWASP floor, a UTF-16 salt
where every other hashing arm encodes UTF-8, an unauthenticated CTR cipher, and
a reader that took its KDF from the file and accepted `md5`.

Ruled urgent and landed ahead of GA in `cc4ac7026`. Version 1 envelopes carry
`v`, a random salt and a `kdfParams` object at OWASP's floor; envelopes without
`v` keep the old derivation exactly, including the UTF-16 salt, because the
passphrase belongs to the user and nothing here can rewrite those files. The
converse is a real break and is called out: a file written now does not open in
an older client.

Measured, warmed to exclude JIT: 68.5ms against the old configuration's 18.4ms,
about 3.7x the work per guess. The first measurement said the change was free
and was wrong — an unwarmed run reads 74ms old against 70ms new.

### 48.7 Two corrections to findings, both mine

Both are recorded because the failure mode is the point of the whole exercise.

**The `hashingAlgo` hole was overstated.** It was reported, and I repeated it,
as algorithm-confusion letting an unsigned field select MD5. `RsaSigningAlgo`
implements sha256 and sha512 only and refuses everything else at *both* ends,
so an MD5-signed envelope was never constructible. The real defect is narrower:
`byName` threw `ArgumentError` for an unknown name and a type error for a
missing field, so malformed envelopes escaped past every
`on AtSigningVerificationException` guard. Fixed in `3bba6142a`; the allowlist
is defence in depth, and the commit says so.

**Two of my own tests had collapsed arms.** The first `.atKeys` suite passed
all 15 with the salt entirely ignored — the envelope writes a `salt` field that
does nothing and every round trip agrees, because both sides ignore it equally.
Only a derivation-level test sees through it. And the first `hashingAlgo` tests
passed before *and* after the fix, because relabelling a sha256 envelope as md5
fails on signature mismatch either way. Reading `rsa.dart` to build a real
differential is what surfaced the overstatement above.

Settled while there, because it decides the JWS `alg` mapping: **no producer
anywhere passes a non-default `hashingAlgo`**. Every envelope in the system is
RSA+SHA-256, which is JOSE `RS256` exactly.

### 48.8 What this entry does not rule

Per the rule that a ledger ruling names a mechanism only once its differential
test is green, the JWS and RFC 9180 migrations are **decided but not landed**,
and this entry records the decision and the constraints rather than a
mechanism:

- **JWS Flattened JSON Serialization, `b64=true`** — plan written
  (`untracked/2026-08-06-JWS-MIGRATION-PLAN.md`), implementation deferred.
 RFC 9964 (Proposed
  Standard, May 2026) registers `ML-DSA-65` as a JOSE `alg`, and our signature
  is already conformant to it — pure ML-DSA, empty context, now pinned by test.
  The RSA arm already emits exactly the `RS256` bytes. JCS is **rejected**:
  there is no RFC 8785 package on pub.dev, so it means hand-writing an
  ECMAScript-number-formatting canonicaliser, which is the thing we are trying
  to remove. `canonical_json` on pub.dev is a trap — it is OLPC Canonical JSON,
  Google-published, and silently divergent. `b64=false` is rejected too: it
  does not deliver the readability that is its only appeal, and its mandatory
  `crit` forfeits off-the-shelf verification.
- **RFC 9180 as `ver = 0x02`, at ChaCha20-Poly1305** — **LANDED** `f3cfda4d4`;
  see [48.9](#489-rfc-9180-landed-and-what-it-settled). Ruled by Gary over
  AES-256-GCM because the HPKE WG's published `0x647A` vectors are
  ChaCha-only — there is no AES-GCM row at this KEM — so ChaCha gives an exact
  published KAT with no audit footnote. `aad` is unused at every production
  call site and both AEADs are Nk=32/Nn=12, so it was a free parameter.
- Two blockers must clear first: `_envelopeVersion` is a global const with **no
  write-side version selector**, and `suites` on the key package
  ([plan 14.4](implementation-plan.md#144-a-suites-list-on-the-key-package--done)) is
  what makes the move a sender-side decision rather than a fleet-wide
  readers-first migration.
- The **enrollment record's `metadata.keyPackage` is a signed envelope written
  only by `enroll:request` and never afterwards**, so its wrapper shape is a
  one-way door alongside the signing root. 46 does not list it; it should.
- NoPorts carries its own copy of the envelope shape in
  `noports_core/lib/src/common/validation_utils.dart`. It does not import
  at_client's functions, so a migration here does not break it — but "nobody
  has this shape deployed" is wrong, and it is a separately-owned second
  migration to name rather than discover.

### 48.9 RFC 9180 landed, and what it settled

`f3cfda4d4`. The suite is

> RFC 9180 Base mode, KEM `0x647A` (X-Wing / MLKEM768-X25519), KDF `0x0001`
> (HKDF-SHA256), AEAD `0x0003` (ChaCha20-Poly1305).

Version `0x01` is unchanged and remains the default, so nothing on the wire
moves until a caller asks for `0x02` — which is what the write-side selector
(`1688ed69d`) exists for.

**The schedule matched the working group's published bytes on the first run**,
written from the specification: `key`, `base_nonce`, `exporter_secret`, and all
10 published encryptions. That is the direct answer to
[46.1](#461-pqseal-stays-custom-and-d2-is-when-we-revisit-it)'s "the same
bespoke code with a specification attached". The code is about the same size
either way. Only one version has a referee, and three red proofs show the
referee bites: perturbing the mode byte, the `psk_id_hash` label, or one byte of
`suite_id` each turns the vector tests red.

Two things worth keeping:

- **The versions are separated, not merely labelled.** Relabelling a `0x02`
  envelope as `0x01` fails to open, and so does the reverse — asserted rather
  than assumed. `0x01`'s domain separation is its `atPQv1-base` suite label;
  `0x02`'s is the `suite_id` inside every labelled derivation, so
  `_suiteLabelFor` does not apply to it and raises if asked.
- **Three tests that used `0x02` as their stand-in for "unsupported" had to
  move to `0xff`.** Their failures were the new code behaving correctly, not a
  regression — worth naming because a version-number placeholder is exactly the
  kind of test fixture that silently stops testing what it says.

The framing is shared, so everything after the 3-byte header is exactly RFC
9180's `enc || ct`. The Atsign part is a frame around a conformant payload,
which is the relationship TLS and MLS have to the constructions they carry, and
it is worth describing that way rather than claiming bare RFC 9180 on the wire.

## 49. Two KEMs by configuration, and the downgrade gap that stays open (2026-08-06)

**In brief:** *the second option answers a FIPS questionnaire; configuration rather than negotiation, because per-message choice is a downgrade surface*

The ruling is **two KEMs, selected by deployment configuration**, across both
the secret-sharing substrate and the nskey encapsulations:

| Option | Components | Citation |
|---|---|---|
| Hybrid, as today | ML-KEM-768 (FIPS 203) + X25519 (RFC 7748) | combiner in `draft-irtf-cfrg-concrete-hybrid-kems`, CFRG-**adopted** |
| Pure **ML-KEM-1024** | FIPS 203 only, no combiner | FIPS 203 + SP 800-227 §4.3 + SP 800-56C — **no draft at all** |

The second exists to answer a "FIPS-approved algorithms only" questionnaire and
CNSA 2.0, which per NSA's own IETF profile drafts mandates ML-KEM-1024 and makes
hybrids **non-compliant** in TLS. The first keeps the classical hedge, which
covers exactly one scenario: ML-KEM falling to *classical* cryptanalysis before
a quantum computer exists. X25519 contributes nothing against a quantum
adversary, since it is Shor-broken — state that correctly or a reviewer will.

**MLKEM768-P256 was considered and rejected on implementability.**
`package:cryptography`'s `DartEcdh` throws `UnimplementedError` — there is no
pure-Dart P-256 ECDH. Choosing it would mean hand-writing constant-time ECDH on
a general-purpose curve library, adding rolled-our-own key agreement in order to
remove a draft citation. Its combiner also lives in the same CFRG draft as the
hybrid's, so it buys approved *components* and not an approved *construction*.

**Configuration, not negotiation, and the reason is NIST's.** SP 800-227 §4.6.3
warns that composite schemes "introduce additional choices in protocols, which
could also introduce vulnerabilities (e.g., in the form of *downgrade
attacks*)". So each atSign advertises one KEM and senders use what the recipient
advertises. There is no per-message negotiation to attack.

**The gap this leaves, recorded because it was accepted rather than missed.**
Configuration-not-negotiation removes the *protocol* downgrade surface, but it
relocates the question rather than closing it: the advertisement is what carries
the algorithm, so the property now rests entirely on an advertisement being
authentic. [Section 51](#51-the-from-challenge-and-a-signed-envelope-must-never-share-a-shape-2026-08-08)
is what closes the remaining path to presenting a client with an advertisement
of someone else's choosing. Until it lands, the downgrade SP 800-227 names is
not fully out of reach. Accepted for now, and it is the reason that item stops
being deferrable before release rather than after.

**Landed** as KE-1 on 2026-08-07 — see
[section 50](#50-two-kems-by-configuration-one-construction-by-negotiation-2026-08-07),
which records what building it settled and where this entry's expectations held
or moved. This section is the ruling; 50 is the landing.

## 50. Two KEMs by configuration, one construction by negotiation (2026-08-07)

**In brief:** *the knob is a preference not a `CryptoConfig` field; the sender follows the recipient; `suites` is what moves the wire without a flag day*

The two-KEM option ruled on 2026-08-06 is built and wired, across `at_chops`,
`at_client` and `at_auth`, in `6a85fad05`…`f3e5b3686`. This entry records what
building it settled — the rulings that were only reachable once there were two
KEMs in the tree rather than one.

The shape, stated once:

| | |
|---|---|
| Hybrid, the default | X-Wing (ML-KEM-768 + X25519), IANA HPKE KEM `0x647A` |
| No-hybrid option | ML-KEM-1024 (FIPS 203), IANA HPKE KEM `0x0042` |
| Constructions on the hybrid | `x-wing-hpke-v1` (`ver 0x01`), `x-wing-rfc9180-v1` (`ver 0x02`) |
| Construction on ML-KEM-1024 | `ml-kem-1024-rfc9180-v1` (`ver 0x03`, HKDF-SHA384 + AES-256-GCM) |

`0x03`'s parameters are not a free choice. KEM `0x0042` has exactly two
published HPKE rows and only one at a 256-bit AEAD, so HKDF-SHA384 is what buys
a third-party end-to-end vector instead of a self-generated one — and it is the
combination CNSA 2.0 names, which is the market the no-hybrid option exists
for. `MLKEM768-P256` was the other candidate and was rejected on
implementability: `package:cryptography`'s `DartEcdh` throws
`UnimplementedError`, so choosing it meant hand-writing constant-time key
agreement on a general-purpose curve library in order to remove a draft
citation.

### 50.1 The knob is `AtClientPreference.keyEstablishmentAlgo`, not a `CryptoConfig` field

The obvious home for "which KEM does this atSign use" is the pluggable-crypto
config, beside the providers it parameterises. It cannot live there, and the
reason is ordering rather than taste.

- **An app cannot build the nskey `CryptoConfig` before its client exists.**
  `PublishedNskeyKeyRing` takes the `AtClient`, and production constructs one in
  seven places — `AtClientImpl` (four), `NskeyRotation`,
  `EnrollmentServiceImpl`, `ConveyedKeyCollection`. A knob an app must set
  *before* `AtClientImpl` finishes initialising cannot be carried by an object
  that needs the finished client to exist.
- **The KEM has to reach a top-level function with no client at all.**
  `enrollmentKeyPackageBuilder` runs during `enroll:request`, before the
  enrollment it is minting for exists, so it takes the algorithm as an explicit
  parameter. Nothing resolvable from a client is reachable there.

So it sits on `AtClientPreference`, beside `seedNamespaceKeys`, for the same
reason that one does: it is a **rollout** choice, not a crypto-path one. What
routes a *record* is still `appMetadata.providerId`
([16](#16-a-provider-id-names-every-algorithm-a-reader-needs-code-for-2026-08-02)),
and that is unchanged — the preference decides what this deployment *mints*,
never what it can read.

**A key that already exists keeps its own algorithm, whatever the preference
later says.** The kpid is the address peers seal to and it is frozen in an
enrollment record that is never rewritten
([14.6](implementation-plan.md#146-the-enrollment-records-metadatakeypackage-is-a-one-way-door)),
so re-minting under a newly configured KEM would move the client to an address
nobody writes to — it would scan for envelopes being sent somewhere else.
Changing the preference takes effect on the next enrollment, and the mismatch
is logged rather than silently resolved.

### 50.2 The sender follows the recipient, so configuring a KEM restricts nobody

An atSign configured for ML-KEM-1024 still seals to a hybrid peer, and the
reverse. Every build produces and opens both, and the recipient's advertised
`alg` is what decides — so the configuration says what *this* atSign is a
recipient for, and nothing about who it can talk to.

Refusing the other option would leave two atSigns unable to communicate while
protecting nothing: the peer's key is the peer's decision, and a sender that
declined to encapsulate to it would not make that key any stronger.

This is why `sendEnvelope` had to change at all. It already selected the
recipient's key **by** algorithm and then discarded the algorithm, stamping
`x-wing-hpke-v1` at the default version whatever the key package said — the
decision existed and was thrown away.

### 50.3 The KEM is configured; the *construction* is negotiated

These are different questions and they get different mechanisms. Collapsing
them — "the peer tells us what it wants and we do that" — is what SP 800-227
warns against, and keeping them apart is what makes the wire movable:

- **Which KEM** is configuration. SP 800-227 section 4.6.3 warns that composite
  schemes "introduce additional choices in protocols, which could also
  introduce vulnerabilities (e.g. in the form of downgrade attacks)". Each
  atSign advertises one KEM, per generation, and there is no per-message
  negotiation of it to attack.
- **Which construction over that KEM** is negotiated, because it has to be. A
  KEM key opens every construction built on that KEM — an X-Wing private
  unwraps both `0x01` and `0x02`, since the difference is the key schedule and
  the AEAD, not the decapsulation — so the holder's capability genuinely varies
  with its build, and only the holder can state it.

The statement is a `suites` list, on both advertised-key surfaces:
`KeyPackage.suites` for the secret-sharing envelope, and the nskey
advertisement's own for the CK conveyance. A sender takes the strongest entry
both sides list and derives the `pqSeal` version from it. That is what let the
wire move from `0x01` to `0x02` between modern peers **without a flag day** —
which is the whole reason
[14.4](implementation-plan.md#144-a-suites-list-on-the-key-package--done) was on
the backlog.

Three rules the lists obey, each preventing a specific failure:

- **An absent list means exactly the one construction that existed when such a
  record was written**, and that constant must never grow. Widening it would
  claim, on behalf of holders that never said so, that they can open something
  they cannot. The nskey advertisement's copy is the sharper case: a key
  package is read by the *owner's* own enrollments, an advertisement is fetched
  by **senders**, who act on the claim immediately.
- **The published list is derived from the key, not stated from this build's
  supported set.** What a key can open is fixed by the key. Defaulting to
  `SecretSharingAlgos.suites` is what produced the defect in
  [50.5](#505-the-defect-a-widened-list-planted-before-anything-read-it).
- **On parse, entries this build does not know are kept.** The list is the
  holder's statement about itself, and a newer holder may name a construction
  we do not implement yet.

**No mutually supported construction is a refusal, not a guess.** Sealing under
the sender's own preference would hand the recipient an envelope it cannot
unwrap, and the failure would land on *their* side as an opaque AEAD error with
nothing to point at — the same asymmetry that makes an overstated `suites` list
dangerous.

### 50.4 One seed contract, and why at_chops 3.5.0 is a minor

`generateKeyPair`'s `secretKey` does not mean the same thing on every backend
and nothing in the type system says so. X-Wing's **is** its 32-byte seed.
ML-KEM-1024's is the 3168-byte expanded decapsulation key, which no seeded call
reproduces and which cannot be fed back as a seed. The FFI backends' is an
opaque handle into an OpenSSL registry that does not outlive the process.

The consequence is that code written against X-Wing persists recoverable bytes
**by accident**, and the identical code persists unrecoverable ones for ML-KEM
— with no compile error and no failure until a restart, at which point every
record sealed to that key is unopenable. That is the exact hazard a
configuration-selected KEM creates: the source no longer names which backend it
is holding.

So `AtKemAlgorithm` gains `newSeed()` and `keyPairFromSeed()`, and every
persisted key in at_client is filed as its **seed** with the algorithm
alongside — `PersistedEncKey.encSeed` + `keyAlgo` (spelled
`PersistedApkamKeys.encSeed` + `keyAlgo` until 2026-08-13, when the holding
became a list — [95](#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12)
ruling 9), and the nskey private likewise. 32 and 64 bytes are both valid seeds for *some* backend, so the bytes
alone cannot say which. `NskeyKeyRing.privateHalf` now returns the decapsulation
key — what `pqOpen` takes, which is what it always meant — and expands on the
way out. Byte-identical for X-Wing, so existing keyfiles are untouched.

The seed *length* deliberately stays off the interface: it is backend-specific,
and a caller has no use for it once `newSeed` produces a valid one and
`keyPairFromSeed` rejects an invalid one.

**3.5.0 rather than 3.4.2, and the reason is the interface, not the size of the
change.** These are abstract members on an exported interface, so any external
`implements AtKemAlgorithm` must add them. All six implementations in this
repository are `final class … implements`, so every one was a compile error
rather than a silent runtime hole — but nothing outside gets that treatment,
which is what makes it a minor.

### 50.5 The defect: a widened list, planted before anything read it

`KeyPackage.suites` defaulted to `SecretSharingAlgos.suites`, which was correct
while that list held exactly one entry. `80b6f9e13` widened it to three and
swept only `algo_ids.dart`, so from that commit a package advertising a single
X-Wing key also declared it could open `ml-kem-1024-rfc9180-v1` — a
construction nothing it holds can decapsulate.

Nothing acted on the claim at the time: `bestSuiteFor` had no production caller
and the sender still stamped one suite unconditionally. It mattered because the
**next** commit made the sender honour it, and because `metadata.keyPackage` is
written by `enroll:request` and never again — the claim freezes for the life of
an enrollment, so any key package minted in that window carries it permanently.

Worth keeping as a shape rather than an incident: a default that is correct for
a single-element list becomes a lie the moment the list grows, and the
blast-radius sweep for "widen an enum/list" has to include every **default**
that reads it, not only every `switch`.

### 50.6 An atServer revocation-visibility lag, found by bounding an assertion

The roster half of the revocation test already polled, because `enroll:listns`
is served through an enrollment cache observed stale on the first read after a
revoke. The credential half asserted the refusal was immediate. It is not.

On 2026-08-07 it failed once in three consecutive full-suite runs: a fresh
connection PKAM-authenticating with the revoked enrollment's **own** keypair was
accepted after `revoke()` had returned, while the runs either side refused it.
Same mechanism as the roster — the control arm above deliberately authenticates
that enrollment beforehand, which is what populates the cache the PKAM path
then reads.

So the credential is polled with the same bound, and the bound is what keeps it
an assertion: if the keypair never stops working, the test stays red. **The
property is the atServer's, not this client's** — a holder of a revoked keyfile
can still authenticate for a short window after `enroll:revoke` returns, and
that is worth a look on the server side rather than only a poll on ours. It
does not weaken [47](#47-b-2-lands-two-levers-and-the-difference-between-excluding-and-revoking-2026-08-06)'s
ruling that the revoke is the enforcement; it bounds how quickly that
enforcement becomes visible.

> **Resolved 2026-08-12, and this section called it correctly.** "The property
> is the atServer's" was right, and the look on the server side found an
> `EnrollmentManager` cache invalidated *before* the write rather than after —
> fixed in at_server `16dd457f`. Noted here because 93 ruling 5 later closed
> the same question the other way, on a serial test; the amendment sits there.

### 50.7 What this cost, and what it did not

Landed with rails green at every commit boundary: at_client **1012** unit,
at_chops **465**, functional **138**, e2e **50**.

Two things it deliberately did not do. It did **not** re-key anything already
published — keys are minted per generation, so an atSign moves to the other
option by rotating, which is the only moment an advertised algorithm can
change. And it did **not** make the KEM a per-message choice: the version byte
names the whole suite precisely because the KEM is already fixed by the
recipient's advertised key, so an opener needs no input beyond the byte it
already reads first.

## 51. The `from:` challenge and a signed envelope must never share a shape (2026-08-08)

**In brief:** *both are signed by the enrollment's signing key, so their shapes must stay disjoint*

Per-enrollment PQC key packages are signed by the enrollment's signing key —
the same key that signs the atServer's `from:` challenge. So the challenge and
any to-be-signed envelope have to be shaped differently, always, or one can be
presented in place of the other.

That is the current state: a challenge is `_<uuid><atSign>:<uuid>`, and an
envelope payload is `jsonEncode` of a map, so it ends `}`. Nothing can be both.

But it holds by coincidence of two formats rather than by construction, so it
needs assertions to keep holding. The first landed in `at_lookup` **3.6.1**
([PR #2127](https://github.com/atsign-foundation/at_client_sdk/pull/2127)): a
client asserts the challenge's shape before signing it, on both signing paths.
Domain separation on the envelope side would make the two disjoint by
construction; it needs the `signedEnvelopeVersion` hatch, so it lands with the
PQ work rather than on trunk.

⚠️ **BUILT 2026-08-15 as [ruling 103](#103-an-envelope-says-what-it-is-for-and-a-verifier-says-what-it-wants-2026-08-15),
and this section's premise was re-measured first rather than inherited.** It
still holds: the challenge and an envelope are signed by one key at the default
posture, because `signingKeys` falls back to the APKAM authentication keypair
whenever the enrollment holds no signing material of its own. What building it
found is that the nearer confusion was not challenge-versus-envelope at all —
it was envelope-versus-envelope, five production uses of one shape signed by
one key and told apart only by their payload's field names. The last sentence
above is also stale twice over: `signedEnvelopeVersion` was deleted by
[ruling 95](#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12)
ruling 1, and no hatch was needed.

## 52. ON-1: a greenfield atSign starts where a retrofit ends (2026-08-08)

**In brief:** *typed-only keyfile, the signing root names its algorithm, and the PQ mint is opt-in at the at_auth layer*

ON-1's client half is built. `pqNativeOnboard` CRAM-activates a brand-new
atSign directly into the shape a retrofit would have produced, with no legacy
generation in between — and [UC-A1.1](../acceptance.md) is green against a live
atServer on two independent fresh-virtualenv runs, taking the acceptance suite
to **43 of 45**.

### 52.1 The keyfile shape: typed-only, and the flat fields stay empty

A retrofit freezes the flat `apkamPublicKey`/`apkamPrivateKey` fields because a
legacy enrollment owns them ([43](#43-rf-2b-lands-and-what-the-first-genuine-ml-dsa-pkam-found-2026-08-05)).
Greenfield has no such owner, so the question was open: put the ML-DSA APKAM in
the flat fields, or leave them empty and file it only as typed material?

**Typed-only.** One shape for every PQ enrollment however it was reached, so
`signingAlgorithmForEnrollment` always answers and `AtAuthImpl.authenticate`
resolves the algorithm from the keyfile with nothing caller-supplied anywhere.
The alternative writes a keyfile whose flat fields hold ML-DSA bytes while every
reader's default `signingAlgoType` is `rsa2048` — so a consumer that does not
explicitly set the algorithm signs with the wrong routine, silently. Empty flat
fields make that same consumer fail loudly instead, which is the point rather
than a cost.

That is also why the PQ mint is **opt-in at the at_auth layer**
(`AtOnboardingRequest.signingAlgoType = mldsa65`) rather than the default: empty
flat fields are a behaviour change no minor may impose on existing consumers,
and at_auth 3.4.0 is a minor. The SDK's own onboarding path is what opts in, so
UC-A1.1's "a CRAM onboard is PQ-native" is true of the entry point applications
actually use.

### 52.2 Legacy material is an opt-OUT, and null means true

`AtOnboardingRequest.mintLegacyMaterial` resolves null to **true**, per
[37](#37-legacy-key-material-is-retained-until-the-ecosystem-is-pq-not-the-atsign-2026-08-05):
whether a brand-new atSign will ever need a legacy peer is decided by the apps
that adopt it, which is unknowable at activation. Setting it false withholds
`public:publickey` rather than publishing an absent key — a legacy peer would
otherwise encrypt to it and produce ciphertext nobody can read. The CRAM secret
is deleted either way, since it is a live path back into the atSign whatever was
minted.

The false arm also turns out to need no new at-rest machinery: `FileAtKeysIo`
only reaches for the `selfEncryptionKey` when a legacy flat field is actually
present, so a keyfile with none simply never asks for one.

### 52.3 The signing root's shape, ruled — [14.1](implementation-plan.md#141-the-signing-roots-keys-shape--deadline-the-first-root-we-keep) closed

14.1 said the deadline was "a state, not a date: before the next long-lived
atSign runs a privileged PQ client". ON-1 **is** that state — every atSign
activated from here keeps a root — and the live test walked straight into it,
failing on the first run with the code publishing `keys: ["<base64>"]` where
acceptance.md and [46.5](#465-the-signing-root-is-the-only-one-way-door) both
specify `[{"alg":"ml-dsa-65","pub":"<base64>"}]`.

**Tagged wins; the code moved and both documents stood.** It is the form every
other advertised key here uses (`_apsk`, the key package) and the only one that
can ever carry a second algorithm — an argument
[50](#50-two-kems-by-configuration-one-construction-by-negotiation-2026-08-07)
strengthened by making the KEM a configuration choice. The record is immutable
create-once and `successor` is unimplemented, so this is permanent.

The reader still accepts bare base64. Roots in that form were published before
the shape was settled and **can never be rewritten**, so a reader that refused
them would lock those atSigns out of their own root permanently. Nothing writes
the bare form any more, and the tagged reader skips an entry naming an algorithm
this build cannot verify with rather than handing back bytes that will be
verified under the wrong routine.

### 52.4 What the live run cost

Three failures, each one assertion further in, and none of them a defect in the
onboarding path itself — it worked on the first run. The root shape was
[14.1](implementation-plan.md#141-the-signing-roots-keys-shape--deadline-the-first-root-we-keep)
coming due. The other two were the test's own instrument: the atServer *throws*
on a second immutable create rather than returning an error string, and
`enroll:listns` requires its namespace argument and does not return
`signingAlgo` at all — the flat response is
`{enrollmentId, access, apkamPubKey, metadata}`, so the ML-DSA property is
proven by the re-authentication rather than by a field.

**And it needed its own atSign.** `apkamFirstAtSign` and `apkamSecondAtSign` are
both already spent by `enrollment_test.dart`, so the first full-suite run failed
on `cram auth failed` while the file passed alone — the one-shot-state trap
exactly as the package's own guidance describes it. `apkamThirdAtSign`
(`@colin`) exists for this test and is gitignored alongside the other two.

Rails: at_client **1019** unit, at_auth **180**, at_chops **465**, functional
**139**, e2e **50**.

---

## 53. UC-B4.2, and what asking for no legacy material actually costs (2026-08-08)

**In brief:** *the row was labelled for a layer that cannot CRAM-activate; the opt-out is honoured and unusable; a pre-seeded harness key was letting two assertions pass for the wrong reason*

UC-B4.2 — a legacy peer and a PQ-native atSign interoperating in **both**
directions — is green live, taking the acceptance suite to **44 of 45** and
discharging ON-1's last row. Three things came out of building it, and each is
worth more than the row itself.

### 53.1 The row was labelled for a layer that cannot do the thing

It had been sitting as `blocked: ON-1 · layer: tests/at_end2end_test` on the
reasoning that only two atSigns can show the inbound direction. The reasoning is
right and the conclusion was wrong, for two reasons that a glance at the harness
would have shown at any point in the last month:

- `tests/at_end2end_test` runs in CI against **long-lived cicd atSigns**
  (`@ce2e1`…`@ce2e4` on `root.atsign.wtf`), not against a container. A CRAM
  secret is spent at first activation, so that pack can never activate anything
  — and a PQ-native atSign can only be *created* by activation.
- Its `TestSuiteInitializer` dereferences `apkamPublicKey!` and
  `apkamSymmetricKey!`, both of which are null in every PQ-native keyfile by
  [52.1](#521-the-keyfile-shape-typed-only-and-the-flat-fields-stay-empty). The
  pack is structurally unable to bring a PQ-native atSign up.

`tests/at_functional_test` runs against the virtualenv container in CI as well
as locally, already holds UC-A1.1, and drives two atSigns in one file in half a
dozen places. The row went there. **The general lesson: "which layer" is a claim
about the harness, and a blocker constant that names one is asserting something
checkable.** Ours had never been checked.

### 53.2 The test mints all three atSigns it needs

The obvious move was to borrow a demo atSign for the legacy side. Both candidates
fail: `@alice🛠` is retrofitted, rooted and nskey-minted by four other files in
the functional pack, and `@bob🛠` gets a signing root from
`signing_root_pull_two_enrollments_test` and nskeys from
`nskey_rotation_live_test`. Whether either is "pre-PQ" at the moment this row
ran would depend on file order, which `dart test` does not promise.

So the file CRAM-activates its own three: one with the default signing algorithm
(pre-PQ), one PQ-native, one PQ-native with `mintLegacyMaterial: false`. The
premise is then *asserted* — the pre-PQ atSign has no `pq_signing_root` and its
keyfile fills the flat APKAM fields, against the PQ-native one as a control —
rather than assumed. Three more one-shot CRAM atSigns are allocated to it in
`config.yaml`, named by role rather than by position because what distinguishes
them is what they were activated *as*.

### 53.3 The opt-out is honoured, and unusable

`mintLegacyMaterial: false` does exactly what it says: no RSA keypair, no
`selfEncryptionKey`, and `completeActivation` publishes no `public:publickey`,
logging why. Then the resulting atSign cannot publish **anything**, because every
public write is signed with the legacy encryption private key. The `_apsk`
anchor to the signing root and the nskey advertisement are both public writes, so
the post-quantum path's own records are the first casualties; sync fails
alongside them for want of a `selfEncryptionKey`.

Recorded as
[plan 14.12](../implementation-plan.md#1412-a-mintlegacymaterialfalse-atsign-cannot-write-a-public-record)
and asserted in the test, so whichever project moves public-record signing onto
the ML-DSA root gets a red test naming this. It matters because
[42](#42-the-to-define-list-ruled-2026-08-05) item 10 has the release default
resolving null→false in the major after R-2: that release cannot ship until
public-record signing and self data are both off legacy material.

### 53.4 A pre-seeded harness key was letting assertions pass for the wrong reason

The virtualenv image ships **every** demo atSign with a `public:publickey`
already installed — an untouched `@denise` has one. So `plookup:publickey@X`
returning `data:` proves nothing about what an activation did, and two
assertions were resting on it: the opt-out arm as first written, and UC-A1.1's
own "a legacy peer must be able to send to a brand-new atSign out of the box",
which would have passed even if the activation had published nothing at all.

Both now assert by **value** — the published key must equal the one in the
keyfile — which is the only form that distinguishes an activation's write from
provisioning state. The opt-out arm additionally deletes the image's leftover
before testing unreachability, with the reason written down: a genuinely new
atSign has no such record, so removing it restores the condition under test
rather than shaping it.

Rails after: acceptance **44 of 45** (1 skipped, UC-B0.1, a harness gap).

---

## 54. S-3: the two things an updatable key store turned out to be (2026-08-08)

**In brief:** *read-mutate-flush loses material at every client start; the keychain could not be written to at all; the self-enc-key re-wrap has no operator and is KF-1's*

S-3 reads as a storage-plumbing project — make the `.atKeys` file and the
keychain updatable. Most of the plumbing was already there: the atomic
temp+rename write, the `.bak` backup and the inter-process lock all landed with
the lock work. What was left was not plumbing at all. It was two ways of losing
key material and one mechanism nobody operates.

### 54.1 Read-mutate-flush is the bug, and it fires at every client start

`flush` takes a whole `AtKeys` and refuses a candidate that has lost anything
the store already holds. That contract is right. What defeats it is the shape
every consumer used around it: `read` → mutate → `flush`, with the read outside
the write's critical section. Two of those overlapping both read the same state;
the second presents a candidate without the first's addition; assurance refuses
it — correctly — and one addition is gone, with an exception logged somewhere
far from the key that vanished.

The overlap is not hypothetical or rare. `AtClientImpl`'s start fires
`_seedNamespaceKeys()` and `_fileConveyedKeysAndAnchor()` as **sibling
unawaited tasks**, deliberately, because neither should block startup. One files
nskey privates, the other files the signing root's private — both through their
own read-mutate-flush on one keyfile. The material at stake is exactly the
material whose loss is unrecoverable: a published nskey whose private did not
survive leaves every sender sealing to something nobody can open.

The fix is to make the operation the interface offers match the operation
callers need: `WrittenAtKeysIo.update(atsign, mutate)`, with `FileAtKeysIo`
holding the keyfile lock across the read as well as the write. Because the lock
is a lock file, it serialises coroutines inside one process as well as separate
processes — which is the case that bites here.

Two details worth keeping. The mutation **returns whether anything changed**, so
a caller that finds the material already there — re-delivery is how the
substrate converges, so this is the common case — writes nothing rather than
rewriting the store to say the same thing. And `update` must never be called
from inside another `update`, or from a `flush` inside one: the lock is not
reentrant, and the natural mistake is reaching for `flush` in a mutation. There
is a test pinning that failure so it is discovered in a second rather than in
production ten seconds later.

### 54.2 The keychain was a store that could not be written to

`KeychainAtKeysIo` implemented `read` and `write`, and inherited `flush` from
the interface — where the default **throws**. On Flutter that store is the
default, so both of the filing paths above hit `UnimplementedError` on the
platform where they matter most. `NskeyPrivateFiling` did not even catch it.

Fixing `flush` surfaced two more losses in the same class. `write` appended
unconditionally to a list `read` scans front-to-back, so writing an atSign twice
left the newer keys permanently unreachable behind the older ones — a silent
loss presenting as a successful write. And an entry written by an older release
carries its atSign under a `name` metadata key rather than `atsign`:
`getAllAtsigns` threw a `TypeError` on one (a `String` used as a condition) and
`removeAtsignFromKeychain` silently kept it. All three come from the same root —
the class was written as a place to put keys once, not as a store.

### 54.3 The self-encryption-key re-wrap is not built, and that is the ruling

The plan's watch-out is accurate: `flush` compares the four self-encrypted
legacy fields as **ciphertext**, because both sides of `validateMapUpdate` are
the at-rest document. It works at all only because `generateIVLegacy()` is
sixteen zero bytes, so re-encrypting an unchanged field under an unchanged key
is byte-identical. Re-wrapping under a new self-encryption key changes five
compared values at once and fails assurance.

It is still not built, deliberately. **No code path anywhere changes
`defaultSelfEncryptionKey` on an existing keyfile** — the only mutator sets it
during enrollment approval, on a file that does not yet exist. A re-wrap today
would be a mechanism with no party that operates it, and the rule about naming
the operator before building the mechanism applies exactly as written. It
belongs to the first project that needs one, which is **KF-1**: at-rest
protection of the PQ privates, whose restore flow already needs an assurance
override for the inverse case (an older backup over a newer keyfile). Building
both escape hatches together, once, beats building one now on speculation.

---

## 55. ON-1's consumer half: what "the CLI can do it too" actually cost (2026-08-08)

**In brief:** *export the steps rather than describing them; "not rsa2048" is not "mldsa65"; the live run found what unit tests structurally could not*

`at_onboarding_cli` can now activate an atSign PQ-native
(`--signingAlgoType mldsa65`), which is what turns ON-1 from a capability into
an activation an end user can reach. Three things are worth keeping from doing
it.

### 55.1 The definition of "PQ-native" lives in one place, or it drifts

The obvious implementation was to set the three fields on the CLI's own
`AtOnboardingRequest`. That is a second copy of a definition whose parts are
**all-or-nothing**: an ML-DSA APKAM without a key package is not a partial
success, because `metadata.keyPackage` is written by the `enroll:request` that
creates the enrollment record and never again — so an atSign minted that way
can never be repaired, only abandoned. A copy that falls one field behind
produces exactly that.

So `pqNativeOnboard` was split into `makeActivationPqNative` (stamp a request)
and `mintSigningRootAfterActivation` (the guarded root step), both exported, and
it is now those two plus the CRAM onboard. The CLI calls the same two against
its own flow. **The general rule: when a second caller needs "the same thing" and
the thing is a set of steps that must all happen, export the steps, don't
describe them.**

### 55.2 "Not the old one" is not the same as "the new one"

The first cut tested `signingAlgoType != rsa2048` to decide whether to go
post-quantum. This package supports a *third* value — `ecc_secp256r1`, which one
of its own tests configures — and that predicate would have silently minted an
ML-DSA APKAM for a caller who asked for elliptic curve. Matching `== mldsa65`
is the whole fix, and the reason it was nearly wrong is that the enum had two
members in mind and three in fact. Sibling of the
[widening-a-list](../implementation-plan.md#1412-a-mintlegacymaterialfalse-atsign-cannot-write-a-public-record)
hazard: a predicate written as a negation goes wrong the moment the set grows,
with no site having changed.

### 55.3 The live run found what unit tests structurally could not

`authenticate()` threw `Null check operator used on a null value` from
`_persistKeysLocalSecondary`, a legacy back-up step that dereferences the flat
`apkamPublicKey`/`apkamPrivateKey` fields — which a PQ enrollment deliberately
leaves empty ([52.1](#521-the-keyfile-shape-typed-only-and-the-flat-fields-stay-empty)),
and which an atSign activated without legacy material lacks entirely. It now
persists whatever the keyfile holds.

Note where that landed: *after* a successful authentication, from a back-up
step, with a message naming nothing. Only driving a real PQ keyfile through the
real `authenticate()` finds it — which is the argument for the live test being
the deliverable rather than its evidence.

## 56. The "make it right" quality pass, and the design goals it settled (2026-08-09)

D1 development is complete (acceptance 45/45); the branch works. A structural
quality refactor — readability, maintainability, explainability — was audited
(every changed production file read in full) and planned phase by phase. The
plan review grilled out several design questions the spike had left implicit,
and settled them. This section records the **decisions**; per §46.7 the ledger
names a mechanism only once its differential test is green, so what follows is
the intent and the shape, and the build names the mechanism as each lands. The
full plan lives outside the tree (it is scaffolding, not design of record); its
durable rulings are here.

### 56.1 The signing chain is root-anchored; chain links are provisional

`verifyChain` has no production consumer today — it is exercised only by tests,
and every one asserts `anchored`. Nothing consumes the `chained` intermediate.
So the trust model is free to be settled rather than inherited, and it is:
**every enrollment ends up directly anchored to the signing root.** A chain
link is a provisional fast-path, not a durable trust edge; the privileged sweep
is changed to *upgrade* chain→root (it anchors an enrollment that lacks a root
link, rather than skipping one that already carries a chain link). `verifyChain`
keeps its multi-hop walk dormant, so a future decentralised model — enrollments
vouching for each other while the root is offline — remains open without being
built now.

The consequence that made this the right call: with no durable parent→child
signatures, replacing any non-root enrollment's key orphans nobody, because it
has no signed children. The cascade a key rotation would otherwise trigger
(§56.3) dissolves into the sweep.

### 56.2 A root-holder conveys root links, not chain links attributed to itself

Today `sweepUnanchoredEnrollments` signs a chain link with the *sweeper's* own
APKAM key and conveys it. For a client authenticating with the atSign's own root
keys (no enrollment id, the sentinel `primary`), that is an RSA link attributed
to `primary` — a fragile two-hop path. The ruling: **a signer that holds the
root private conveys a *root* link** (root-private ML-DSA signature over
`{childEnrollmentId, apkamPublicKey}`), which the child publishes into its own
`_apsk`. `_checkRootLink` already verifies the root signature and does not care
who published the link, so a conveyed root link is safe and anchors in one hop.

The owner-keys `primary` client therefore **publishes and self-root-anchors its
own `_apsk.primary`** (this already happens) but **never signs anyone else's
chain link** — when it anchors others it uses the root key. Accepted residual:
an RSA-signing enrollment (owner-keys, or a type-1 retrofit) is *root-endorsed*
— the ML-DSA root link vouches for its RSA key — but its own leaf signatures
stay classical; RSA-only peers trust it via the atServer's `_apsk` guarantee,
PQ peers additionally verify the root link. This does not resolve whether an
owner-keys client belongs in the trust chain at all (backlog 14.14); it makes
`primary` a coherent leaf rather than a phantom intermediate.

### 56.3 Three retrofit modes, and the signing-algorithm selector

Retrofit is not one operation. Three modes, distinguished by whether the id is
new and which signing algorithm the enrollment gets:

- **Type-1 — new id, fresh RSA signing key.** The rollout-window mode: it gains
  the 1:1:1 / key-package / nskey data-path structure while its signatures stay
  RSA-verifiable, so peers that cannot yet read ML-DSA cope, and no atServer
  ML-DSA-PKAM support is required. "The same RSA key" means the same
  *algorithm*, not the same key object — a fresh RSA key under the new id keeps
  1:1:1 intact and PKAM binding unambiguous.
- **Mode B — new id, fresh ML-DSA signing key.** What `self_retrofit` does
  today. The full PQ retrofit.
- **Type-2 — same id, replace the RSA signing key with ML-DSA.** Not built;
  needs atServer support; **seam only, no live path** — it has no operator yet.
  Keeping the id is justified by *data-path continuity*: replacing only the
  signing key leaves the KEM key package (kpid, nskey privates) untouched, so
  the enrollment survives while its signing key rotates. Its repair falls out of
  §56.1: replace the key, re-anchor that one enrollment with a new root link,
  and let a sweep upgrade any provisional chain-linked children — no bespoke
  walk-and-re-sign of a subtree.

The SDK therefore needs a **per-retrofit signing-algorithm selector** (RSA vs
ML-DSA), built now as an operation parameter, not a preference — a preference
would reintroduce the disagrees-with-reality bug class §56.6 designs out. Built
alongside it: the fix for `self_retrofit` hardcoding ML-DSA (which blocks
type-1) and ignoring `keyEstablishmentAlgo` (the KEM axis). The selector is one
of the rollout flags in §56.4.

### 56.4 From the PQ project's view, 4.0 is final-3.x with different flag defaults

Every rollout stage is a flag; **all the code ships in final 3.x, and 4.0 flips
only the defaults.** (4.0 also does ordinary major-version cleanup — deprecation
and dead-code removal — which is orthogonal to the PQ rollout; the deprecations
this pass *adds*, §56.6 and the in-place-deprecated enrollment-model fields, are
the 3.x→4.0 bridge that cleanup removes.) This is the correct deployment
architecture, not merely a testing convenience: it auto-honours the
`keyPackage`-write-once freeze (the JWS producer defaults on only in 4.0, by
which point every 3.x client already *reads* the new shape — §56.5), and it
makes the entire multi-stage rollout testable from one codebase by setting
flags.

Five rollout axes, each an independent flag in its natural home, plus a
convenience posture helper that sets them as a group (applied at construction;
per-operation flags still override per call):

| Axis | home | 3.x default | 4.0 default |
|---|---|---|---|
| Crypto era default | `Expando` keyed by `AtClient` (§27.2 — never the shared preference) | reads-nskey, writes-legacy | writes-PQ |
| `disallowLegacyEncryption` | `AtClientPreference`, final at construction | false | true |
| Signing rollout position | `ReleasePosture.signingRollout`, overridable per `AtClientPreference`; the in-use signing set derives from it (§91.3 rulings 16–17) | `now` (set `{}`) | `rollout2` (set `{mldsa65}`) |
| `EnrollmentKeyExchangeMode` | `AtEnrollmentRequest` | legacy | pq |
| Retrofit signing algorithm | per-retrofit parameter (§56.3) | RSA | ML-DSA |

*Table amended 2026-08-13 during implementation. It carried a **Signed-envelope
version** axis — signer config, v1 in 3.x and v2 in 4.0 — and that axis no
longer exists: [§95](#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12)
ruling 1 collapsed the envelope to one shape, so there is nothing for a posture
to choose between, and `envelopeVersion` is a plain constant. The in-use signing
set took the fifth slot when it landed. **The count is five by coincidence, not
because the same five axes stand** — an amended count is exactly the kind of
number a later reader takes as evidence that nothing moved.*

`EnrollmentKeyExchangeMode.pq` — the KEM-based `apkamSymmetricKey` conveyance,
the one legitimate KEM in the enrollment path — is built and functionally
tested but ships dark (production entry points default to `legacy`). It is
wired into the production flows as a selectable option, not held back: it is the
key-exchange axis of this same table.

### 56.5 JWS ships both stages in 3.x; the producer is a flag, not a 4.x fork

Backlog 14.3 (JWS Flattened JSON, ruled in §48.8) is implemented in **both**
stages in final 3.x. Stage one — readers accept both the current and the JWS
shape, dispatching on the wrapper's `v` field rather than on
`payload is String`, with base64url normalisation at every decode site — is
always on. Stage two — the producer emitting the JWS shape — ships behind the
signed-envelope-version flag of §56.4, defaulting to v1. There is no 4.x code
fork; 4.0 flips the default to v2. The measured base64 padding trap stands: a
naive decode throws on every RSA signature and succeeds on every ML-DSA one, so
the RSA arm must be tested specifically.

### 56.6 `signingAlgoType` is a fact about the key material, not a preference

The branch added `signingAlgoType` to the published `AtClient` interface, which
breaks every external `implements`. It is removed from the interface (nothing
published reads it — the addition was this branch's). The signing algorithm is
resolved authoritatively from the enrollment's APKAM key material, via
`AtKeys.signingAlgorithmForEnrollment` through `AtKeysIo` — not from `AtChops`
(§20.6 forbids a new AtChops-as-source consumer) and not from a preference: you
cannot sign ML-DSA with an RSA key, so the algorithm is a property of the key
you hold. This also fixes a live bug where the value was set only as a
side-effect of `_createAtChops`, so an injected-`AtChops` client signed rsa2048
under an ML-DSA enrollment. The published `AtClientPreference.signingAlgoType`
field stays (it predates the branch) but is deprecated and demoted to a
legacy-only fallback.

### 56.7 The two published-API breaks are repaired, not shipped

Published at_client is **3.14.0** (not 3.13.0). The branch introduced exactly
two breaks of its non-experimental surface, and both are repaired rather than
shipped. `AtClientPreference.crypto` went non-nullable → nullable so the SDK
could tell "app named a config" from "app did not"; it is restored to
non-nullable with a distinguished `CryptoConfig.eraDefault()` sentinel that
`forClient` dereferences through the `Expando` — preserving the era-default
design and §27.2. `signingAlgoType` is handled per §56.6. Every other
branch-added surface across all packages is unpublished and freely reshapeable,
which is the window this pass uses to draw the deliberate public surface before
publication.

## 57. The wire vocabulary gets one home per family (2026-08-09)

The Phase-0 pins made every wire literal safe to relocate: each emitted form
is asserted as a raw string, so a centralisation that changed a byte would go
red rather than silently changing the wire. This section records the
centralisation rulings as they land. The emitted bytes never change — each
entry names what moved and what stayed deliberately put.

### 57.1 nskey record names live in nskey_records.dart

The nskey subsystem's reserved record names were authored independently across
five files: `__nskey` in the published ring, `_nskeylock` in the mint lock,
`__ckcur` in the CK pointer, `pq_signing_root` in the root class, and the
`nskey.<ns>.<kid>` / `__nskey.<kid>` at-rest ids in the private filing — which
spelled its own `nskey.` prefix a second time in `readAll`. They now live in
`lib/src/crypto/nskey/nskey_records.dart`: one registry of names plus the
AtKey builders that emit them, a leaf file importing only at_commons, so any
layer can read it without a cycle. The classes keep their public members
(`NskeyMintLock.keyFor`, `PqSigningRoot.recordName`,
`NskeyPrivateFiling.keyIdFor`, …) as one-line reads of the canonical
definitions, so no call site and no pin moved.

> ⚠️ **`NskeyMintLock.keyFor` no longer exists (2026-08-15).** Ruling 101 row 6
> generalised the class into `MintLock`, which takes the lock's `AtKey` rather
> than composing one, so the composer is `nskeyMintLockKey(owner, namespace)`
> in `nskey_records.dart` and the wire pin calls it directly. The sentence
> above is left as it was ruled; only this note is new.

Surface ruling: of the vocabulary, only `nskeyAdvertisementKey` is exported —
readers and tests address the published record — while the name constants and
the other builders stay internal. Payload version constants deliberately stay
beside their codecs: the formats version independently, and a shared constant
would move them in lockstep.

The `__ck` conveyance pair is deliberately **not** here yet: its builder and
parser meet in a known defect (the eviction scope), so it moves under its own
flagged entry rather than inside a pure-motion commit.

### 57.2 The provider ids join the registry; `legacy` stays with CryptoConfig

The three `at/*` provider ids — `at/nskey/XWING/AES/GCM`,
`at/nskey/MLKEM1024/AES/GCM`, `at/symmetric/AES/GCM` — and the `at/nskey`
family prefix move from the two provider files into `nskey_records.dart`,
each keeping its rationale dartdoc. They are `appMetadata.providerId` wire
vocabulary: a stored record cites its id forever, which is the same freeze
the record names carry. `legacyCryptoProviderId` deliberately does not move —
it names the pre-pluggable default scheme, not nskey vocabulary, and lives
beside `CryptoConfig`, its consumer. `nskeyProviderIdFor` also stays put: it
is keyAlgo→provider *routing*, not a name, and belongs with the provider it
routes to. Both ids and the barrel surface are unchanged; the ids are now
exported from the registry file instead of the provider files.

### 57.3 EnvelopeAddressing owns the `__ssenv` address

The substrate's envelope address —
`<msgId>.<recipientKpid>.__ssenv.<appNamespace>@<atSign>` — was hand-built and
hand-parsed at seven sites (the key builder, a substring fragment, three
subtly different regexes, the namespace parse with its magic `+2`, and a scan
regex in the enrollment-symmetric-key collector). All of it now lives on
`EnvelopeAddressing` (`src/secret_sharing/envelope_addressing.dart`), a
static namespace over the one format. `PairwiseSecretSharing.envelopeKeyMarker`
stays public and pinned, now reading the canonical constant. The type is
deliberately not exported: apps address envelopes through `sendEnvelope`, not
by spelling keys. Emitted bytes unchanged; the pairwise suite passing
untouched is the fidelity check. This extraction is the addressing slice of
the god-mixin split the audit proposed — the transport/responder/fan-out
slices stay put for the later structural phase.

### 57.4 One builder for the `_apsk` address

Four sites built `public:_apsk.<enrollmentId>.a.__e@<atSign>` independently —
`PqSigningChain.apskUri`, `ApkamSigning.publicSigningKeyUri`,
`EnvelopeSigning.getApkamPublicKey`, and a fully hardcoded `llookup` command
string in the enrollment-symmetric-key collector that spelled `a.__e` without
even the constant. The one builder is now `apskUri()` in
`src/signing/envelope_signature.dart` — the signing leaf every consumer
already imports, which is what lets the secret-sharing substrate reach it
without importing `crypto/` (the layering the substrate keeps clean).
`PqSigningChain.apskUri` stays as the public, pinned symbol and delegates.
One deliberate hardening rides the move: `ApkamSigning.publicSigningKeyUri`
now requires a current atSign (`getCurrentAtSign()!`) where it previously
interpolated a null into the URI text — unreachable for any constructed
client, and failing loudly beats publishing a record addressed to the text
"null".

### 57.5 The `__ck` builder and parser meet in the registry

The conveyance name was the one split-brain pair in the vocabulary: the
builder (`SymmetricAesGcmProvider.conveyanceKeyFor`) spelled `'$ckKid.__ck'`
in one file while the eviction listener parsed on an independent
`'.__ck.'` literal in another, with nothing binding the two bytes together.
Both now live in `nskey_records.dart` as `ckConveyanceKey` /
`parseCkConveyanceKey`, and the parse marker is *derived from* the record-name
constant the builder uses, so they cannot disagree by a byte.
`conveyanceKeyFor` and `ContentKeyEviction.parse` stay as the public/test
symbols and delegate. Pure motion — the known eviction-scope defect between
the pair is deliberately preserved here and fixed in the next entry, so the
behaviour change is its own reviewable diff.

### 57.6 Eviction scope comes from the conveyance key, not the observing client (BEHAVIOURAL)

The one deliberate behaviour change of the vocabulary pass. The eviction
listener hard-wired this client's own atSign as the cache scope for every
deleted conveyance it observed, while every *writer* of the CK cache scopes
an entry to `sharedWith ?? sharedBy`. The two rules agree for self and
inbound conveyances — which is why the unit suite was green — and disagree
exactly on an outbound share observed by the deleting client's sibling
device: `@bob:<ckKid>.__ck.<ns>@alice` is cached under bob, the eviction
targeted alice, and the (bob, ns, ckKid) entry survived. Coarse forward
secrecy, whose whole job is fleet-wide eviction, silently missed shared
data. `parseCkConveyanceKey` now returns the nskey owner derived from the
key (recipient prefix if present, else record owner) and the listener evicts
under it; `ContentKeyEviction` loses its atSign parameter. Differentially
tested — the outbound arm was run red against the old code first.

No stored record changes shape and no read-both window exists: the record
format is untouched, and the CK cache is in-memory per process, so there are
no entries under the old rule to migrate — the divergence was between two
in-process rules, not two at-rest formats.

### 57.7 The algorithm-spelling registry: three vocabularies, all string values frozen

Ruled rather than "fixed", because the fix that suggests itself — one spelling
— is impossible: records already published carry every form, several
immutably. The vocabularies and where each applies:

- **Wire / advertised-key ids** (hyphenated): `x-wing`, `ml-kem-1024` — nskey
  advertisements' `alg`, key-package `keys[].alg`, suite ids. ⚠️ **Amended
  2026-08-15 by [101](#101-the-signing-root-becomes-an-ordinary-signing-key-and-rotatable-2026-08-15)
  row 1: `ml-dsa-65` is no longer on this list, and the root record is no
  longer on it either.** This entry read "…`ml-dsa-65` — … and the immutable
  root record's `keys[].alg` (`PqSigningRoot.rootKeyAlgo`)". The root became
  an ordinary signing key advertised in the `_apsk` vocabulary, so it spells
  its algorithm the compact way every other signing key does; `rootKeyAlgo` is
  `SigningAlgoType.mldsa65`. ML-DSA-65 now has ONE spelling on the wire, and
  `wire_literal_pins_test.dart` pins that rather than the split.
- **Keyfile / pkam tokens** (compact): `xwing`, `mlkem1024`, `mldsa65`,
  `rsa2048` — `AtKeysMaterial.keyAlgorithmType`, the signed-envelope
  `signingAlgo` field, the tagged `_apsk` value, and root links
  (`PqSigningChain.rootLinkAlgo`).
- **Dart identifiers**: `SigningAlgoType.mldsa65` (at_chops),
  `KeyAlgorithmType.mlDsa65` (at_auth) — code names whose *values* feed the
  compact vocabulary.

The two vocabularies meet in exactly one declared junction per axis:
`SecretSharingAlgos.materialAlgoFor` / `keyAlgoForMaterial` for the KEMs, and
the root record/link pair for signing — both constants now cross-reference
each other in their dartdoc, and the pins hold every string apart on purpose.
Identifier-level cleanups (the Dart names, at_chops barrel spellings) are
deliberately deferred to the at_chops naming decisions and the at_auth model
reshape. One more spelling family arrives later by design: the JWS wrapper
brings its own registered names (`RS256`, `ML-DSA-65`) confined to the
protected header (§56.5) — it replaces the envelope's `signingAlgo` spelling,
never the keyfile's or the records'.

### 57.8 `SecretSharingAlgos` stays as functions, not a suite table

The audit proposed collapsing the file's seven switch-shaped lookups into one
const `_SuiteSpec` row table, and the plan made the collapse conditional on
the per-row rationale surviving. It would not survive: the rationale in that
file attaches to the *questions*, not the rows — each lookup documents its own
null-contract and failure direction ("null rather than defaulting, because
sealing under a guessed construction produces a record the recipient cannot
open"; "an unknown keyfile token means 'not mine', not 'malformed'") — and the
per-row facts (KEM id, KDF, AEAD, version byte) already live on the suite
constants' own dartdoc. A table would keep needing every one of those
function docs on its derived lookups while moving the row facts away from
the constants. The drift hazard the table was meant to fix — parallel
switches disagreeing — is fenced instead by the wire pins, which assert every
mapping with literals on both sides. Skipped, deliberately.

## 58. The two published-API breaks are repaired in place (2026-08-09)

The §56.7 ruling, landed. Each entry records the mechanism as built, after its
tests went green.

### 58.1 `AtClientPreference.crypto` is non-nullable again; the marker carries "app named nothing"

The field's published 3.14.0 type — non-nullable `CryptoConfig` — is restored.
The nullable branch shape existed to distinguish "app named a config" from
"app did not"; that distinction now travels as the field's new default value,
`const CryptoConfig.eraDefault()`, a distinguished const the SDK recognises by
its private subtype. `forClient` and `adoptEraDefault` treat it exactly as
they treated null: resolve the per-client era default through the `Expando`
(§27.2 intact — the marker is a signal, never per-atSign provider state, and
nothing is resolved into the shared preference object). Assigning any real
config, including `CryptoConfig.legacy()`, is an explicit opt-out, and the two
legacy-shaped values being distinct is covered by test.

The marker deliberately *behaves* as `CryptoConfig.legacy()` when read as a
config: the published default was `const CryptoConfig.legacy()`, so external
code that reads `preference.crypto` directly — the readers `forClient` exists
to replace but cannot retroactively rewrite — sees byte-identical behaviour to
3.14.0. Degrading to the published default was chosen over throwing because a
missed dereference should reproduce the old era, not crash the app that never
opted into the new one.

### 58.2 `signingAlgoType` comes off the interface; the key material answers

The §56.6 ruling, landed in two commits. First the behaviour: resolution from
the enrollment's key material is an explicit `_init` step
(`_resolveSigningAlgoFromKeyMaterial`, via `AtKeysIo` →
`AtKeys.signingAlgorithmForEnrollment`, never `AtChops` — §20.6), running
whether or not an `AtChops` was injected. It had been a side effect of
`_createAtChops`, which an injected-`AtChops` client never runs, so that
client signed the preference's rsa2048 default under an ML-DSA enrollment —
differentially tested red-first on the injected arm
(`signing_algo_resolution_test.dart`).

Then the surface: the branch-added `AtClient.signingAlgoType` getter is
removed from the interface — the published interface has no such member, and
an interface addition breaks every external `implements AtClient`.
`AtClientImpl` keeps the resolved getter, and interface-typed callers (the
envelope-signing mixin, the notification and sync services) resolve through
`AtClientImpl.signingAlgoOf(atClient)`, which answers with the key-material
resolution for a real client and with the preference for anything else.
`AtClientPreference.signingAlgoType` (pre-branch published, so it stays) is
`@Deprecated` and demoted to the legacy fallback, consulted only when the
keyfile has no typed signing material — you cannot sign ML-DSA with an RSA
key, so a preference was never the right home. The onboarding CLI's reads
keep deliberate ignores: at activation time there is no key material yet, so
the preference remains the mint-time input there.

## 59. Phase-3 at_chops surface rulings (2026-08-09)

### 59.1 `pqSeal`/`pqOpen` name their KEM parameter `kem`

[seal-spec.md](../seal-spec.md) says "the KEM is a parameter of `pqSeal`" and
version `0x03` passes ML-KEM-1024 through it, so a parameter named `xwing` was
describing one argument it takes, not the parameter. Renamed. Both parameters
are positional and nothing anywhere bound them by name, so no call site moved.
`0x01` remains X-Wing's alone — the rename widens the parameter's name to
match its type, not v1's contract.

### 59.2 The barrel exports the seal surface only

`labeledExtract`, `labeledExpand`, `hpkeKeyScheduleBase`, `HpkeSuite` and
`pqSealDeriveKeyAndNonce` had zero consumers outside at_chops — only the
package's own tests, which now import the src files directly. The
`rfc9180_hpke.dart` export is dropped and `pqSealDeriveKeyAndNonce` hidden:
the public seal surface is `pqSeal`/`pqOpen`, their exceptions, and the
version constants. Everything exported freezes when 3.5.0 publishes (the
post-3.4.0 stability ruling), and an export added later is a minor while one
removed later is a major — so the internals stay internal until a consumer
exists. This also frees `HpkeSuite` to be reshaped by the same phase's
suite-table work without publishing the intermediate shapes. External
implementations conform against `test/vectors/pq_seal_v1.json` and
[seal-spec.md](../seal-spec.md), never against these internals.

### 59.3 `PkamMlDsa65SigningAlgo` stays deprecated, re-pointed at a replacement that works

The class was born `@Deprecated` pointing at `AtPqc.mlDsa65` — an
`AtSignatureAlgorithm` whose Future-returning verify is the exact defect the
class was created to fix, so the deprecation named a replacement that cannot
serve the class's only production caller (`AtChopsImpl`'s synchronous
dispatch). Of the candidate resolutions — un-deprecate as the durable sync
adapter, add a sync seam to `AtSignatureAlgorithm`, or delete it — the ruling
is none of them: the deprecation is correct, only its pointer was wrong. The
class exists solely to serve the deprecated `AtChopsImpl` dispatch and its
lifespan is tied to it; direct callers already have a working synchronous
route in `MlDsa65PureDartAlgo.signBytesSync`/`verifyBytesSync`, which is what
the message now names. A sync seam on `AtSignatureAlgorithm` was rejected
because it would break external implementers of the published 3.4.1 interface
and force synchronous members onto backends that are inherently asynchronous.
The dartdoc also now records that data-mode ML-DSA verification resolves here
(the dispatch checks `signingAlgoType` before the pkam-mode branch), since
'Pkam' in the name only describes the key-material slot.

### 59.4 `KemSeedMixin` — one implementation of the seed contract

[§50.4](#504-one-seed-contract-and-why-at_chops-350-is-a-minor) put
`newSeed`/`keyPairFromSeed` on the interface; the five backends then each
carried their own copy of the same two bodies, and the copies had begun to
drift — `MlKem768FfiAlgo` validated against a hardcoded `64` rather than its
own `seedLength`. The mixin holds the single implementation: draw
`kemSeedLength` secure-random bytes, reject any other length with a
diagnostic that names the backend, delegate to the backend's deterministic
keygen through a protected member. Per §50.4 the length stays off
`AtKemAlgorithm`; on the mixin it is `@protected`, so it is not caller-facing
surface, and the concrete classes keep their public `static const seedLength`
(which the in-tree 3.5.0 changelog already promises). Landed before the
3.5.0 publish because the mixin and its protected members are exported,
interface-adjacent surface that could not be reshaped afterwards.

### 59.5 One HKDF, parameterised by hash

`hkdf.dart` carried three copies of the RFC 5869 expand loop (one inlined in
`HkdfSha256.deriveKey`, which did not compose its own extract and expand),
three length guards and two HMAC wrappers, differing only by hash. The
construction now has one implementation — `Hkdf`, package-internal in
`hkdf_core.dart`, instances by hash — and the published facade names
(`HmacSha256`, `HkdfSha256`, `HmacSha384`, `HkdfSha384`) stay as one-line
delegates, because the hash-pinned names ARE the public API and the 3.4.1
surface is frozen. `HkdfSha384.deriveKey` now exists for free. Attestation
unchanged and green over the unified core: the RFC 4231/5869 KATs at SHA-256,
the HPKE WG `0x0042` key-schedule vector as SHA-384's only oracle, and the v1
schedule/golden-envelope pins.

### 59.6 One pure-Dart ML-KEM, parameterised by level

`ml_kem_768_pure_dart.dart` and `ml_kem_1024_pure_dart.dart` were the same
class twice, and the copies had drifted — 1024 grew four public size
constants 768 never got. The implementation now lives once in the
package-internal `abstract base class MlKemPureDart` (level via constructor;
one `KyberKem` per level), and the published leaf names stay as level-pinned
`final class ... extends` shells carrying their own docs, `seedLength`, and
diagnostics. `MlKem768PureDartAlgo`'s public shape (3.4.1, including the
seeded `generateKeyPair`/`encapsulate` overloads) is byte-compatible;
`MlKem1024PureDartAlgo` keeps its constants. The `instance` singletons remain
`const`, so at_client's `same()`-identity resolution pins hold unchanged.

### 59.7 `XWingCore` — the construction's pure computation lives once

The pure-Dart and FFI X-Wing backends each carried the combiner, the
SHAKE-256 seed expansion, the byte layouts and their validations — justified
at the time as keeping the FFI backend checkable "in its own right". That was
an argument for independent VECTORS, which the working group's published
`0x647A` JSON already supplies, not for independently maintained code. The
shared bytes now live in the package-internal `XWingCore` (free of
`dart:ffi`, so the pure backend stays out of the ffi import graph); each
backend keeps its own orchestration — component materialisation, OpenSSL
handle release, the pure-only derandomised path — and BOTH keep their own
vector rows, because the published JSON is the oracle that catches a
shared-core defect where interop tests would pass with both backends wrong in
the same way. The FFI class doc and the changelog's second-copy rationale
were rewritten in the same commit.

### 59.8 pq_hpke: a version table, and the AEAD rides the suite

Version dispatch was smeared across ten sites — a label switch, two suite
consts, two AEAD ternaries re-deriving the cipher from the version byte, two
membership checks, borrowed AES-GCM length constants. `HpkeSuite` was a
half-suite: it named its AEAD by IANA id but did not carry it. Now `HpkeSuite`
resolves `kdf` and `aead` from its own ids (one mapping each — the two
labeled operations' duplicated KDF switches collapse into `suite.kdf`, and
the AEAD adapters live behind the package-internal `AtAeadAlgorithm` face),
and pq_hpke.dart holds one `_versions` table, one row per wire version. Each
row is either an RFC 9180 suite (domain separation: the `suite_id` inside
every label) or the custom `atPQv1-base` label (v1's domain separation) — by
construction an RFC row has no label and the custom row no suite, so
relabelling an envelope across versions keeps failing in both directions.
Per [§57.8](#578-secretsharingalgos-stays-as-functions-not-a-suite-table)'s
burden the per-version rationale rides the rows. `pqSealSupportedVersions` stays the
public const (raw-literal-pinned); a 256-value behavioural probe pins the
table's key set equal to it. The file header was rewritten — it described
only v1 and called the file's contents not-RFC-9180 while two versions are
§5.1 verbatim — and the envelope vocabulary now matches
[seal-spec.md](../seal-spec.md) (`aeadCiphertext || tag`, not `gcm*`).

### 59.9 Derandomised encapsulation is a testing hook, not public API

[seal-spec.md](../seal-spec.md): "There is no derandomised variant in the public
API" — the concrete ML-KEM classes' optional-seed `encapsulate` overloads
contradicted that sentence. The pure-Dart classes now expose
`@visibleForTesting encapsulateDerand` (matching X-Wing's compliant shape)
and their public `encapsulate` always draws fresh randomness.
`MlKem768PureDartAlgo`'s overload is published 3.4.1 surface, so it stays
callable with the parameter `@Deprecated` and delegates to the hook;
`MlKem1024PureDartAlgo`'s was branch-added and is gone. The vector tests
still reach the derandomised path — the `0x0042` published-ciphertext row
calls the hook by name, and X-Wing's internal derand route branches to it
explicitly under its own `@visibleForTesting` entry point.

## 60. JWS stage one lands: readers always-on, producer behind the version flag (2026-08-09)

Backlog 14.3, ruled in
[48.8](#488-what-this-entry-does-not-rule) and staged in
[56.5](#565-jws-ships-both-stages-in-3x-the-producer-is-a-flag-not-a-4x-fork):
the signed envelope gains its RFC 7515 shape. This section records the
implementation rulings as the commits land.

The re-grep of the 2026-08-06 migration plan's site table (the plan's own
instruction — audits go stale) found all 8 sites alive at shifted lines, and
three corrections worth recording:

- **The root link is not a signed envelope.** `PqSigningChain.anchorSelf`
  builds its own `{v, alg, payload, signature}` wrapper signed by the *root*
  key, not by `signEnvelope` with APKAM keys; `_checkRootLink` verifies it
  directly. The plan's table listed it as consumer #5, but it is a separate
  format family with its own version field, and this migration does not touch
  it. If root links ever move to JWS, that is that format's own decision.
- **The signer claim is a second migration axis the table missed.** Seven
  production sites read `enrollmentId` off the wrapper (the verify mixin, both
  secret-sharing consumers and their cross-checks, the enrollment directory,
  the chain walk and its logging); in the JWS shape that claim lives in the
  protected header as `kid`, so every one of them needs the shape-agnostic
  read, not just the payload consumers.
- One test-side consumer had appeared since the audit
  (`secret_sharing_delivery_test.dart`), confirming the re-grep rule.

### 60.1 The wrapper's second shape: RFC 7515 Flattened JSON at `v: 2`

`signEnvelope` gains a `version` parameter defaulting to
`signedEnvelopeVersion` (1); nothing on the wire moves. At
`jwsEnvelopeVersion` (2) it emits
`{"v": 2, "payload": ..., "protected": ..., "signature": ...}` — all three
members unpadded base64url, signing input the ASCII of
`protected || '.' || payload`, protected header
`{"alg": ..., "kid": <enrollmentId>, "v": 2}` with `kid` omitted exactly when
version 1 omits `enrollmentId` (nothing truthful to stamp at
`enroll:request`). The top-level `v` is the same unauthenticated parsing hint
version 1 carries; RFC 7515 requires unrecognised members to be ignored, so
off-the-shelf verifiers are undisturbed. Readers dispatch on it and the
verifier then requires the *signed* header `v` to agree — the signed claim is
the one that counts.

The `alg` mapping is deliberately minimal per
[48.7](#487-two-corrections-to-findings-both-mine)'s finding that every RSA
envelope in the system is SHA-256: `rsa2048` ↔ `RS256`, `mldsa65` ↔
`ML-DSA-65` (RFC 9964), and a version-2 signing request under `sha512` is
refused until a producer exists to need it. Verification keeps the
record-authoritative rule: the published `_apsk`'s declaration picks the
routine and the envelope's `alg` must agree, so a lie can never select a
weaker algorithm — same as version 1's `signingAlgo`, except now the claim is
also under the signature, which the tests prove by tampering `kid` (signature
fails: the header is covered) separately from mismatching `alg` (typed
refusal: the key decides).

`envelopePayloadOf` and `envelopeSignerOf` are the shape-agnostic reads the
consumer sites migrate to; `envelopeVersionOf` refuses versions this build
has no code for rather than guessing. A version-2 payload is always the JSON
encoding of the payload — including a String, which version 1 signs verbatim
— so decode is unconditional. In passing, the version-1 verifier's
missing-signature path became a typed refusal instead of a cast error, the
same fix family as 48.7's `hashingAlgo` repair.

Every decode normalises first: `base64Decode(base64.normalize(s))`. The
migration plan measured the trap at signature lengths (RSA-2048's 342 chars
throws, ML-DSA-65's 4412 decodes), and the red proof found it is **broader
than the plan's table**: the protected header itself is a mod-4-remainder
length, so dropping the normalisation turned *both* arms red, not just RSA.
The unit suite pins the RSA arm anyway (`base64Decode(signature)` must throw,
length pinned 342) so the covering test can never silently stop covering the
throwing case. Red proofs run and reverted: dispatch disabled → the six
version-2 verifies red, all version-1 arms green; normalisation dropped →
eight red across both arms as above.

The version-2 emitted form is pinned FROZEN in `wire_literal_pins_test.dart`
(wrapper field order, unpadded members, protected-header bytes for both
algorithms — the header bytes are under the signature, so member order is
cryptographically bound). The version-1 pins group stays binding: it is
retired by the 4.0 default flip, not by this migration.

### 60.2 Every consumer reads through the shape-agnostic helpers

The seven payload consumers and seven signer-claim reads move onto
`envelopePayloadOf` / `envelopeSignerOf`, each keeping its own refusal
semantics: the secret-sharing consumers still *skip* (one envelope this
enrollment cannot use says nothing about the one it is waiting for), the
nskey key ring still *throws* its typed refusal, and the chain walk still
returns verdicts. Three sites needed more than substitution:

- **The key ring's up-front field check is now shape-aware.** It required
  `signingAlgo`/`hashingAlgo`/`enrollmentId` as wrapper fields, which would
  have refused every version-2 envelope before verification ran; the JWS arm
  checks `protected`/`payload`/`signature` instead.
- **The enrollment directory distinguishes novelty from malformation.** An
  unknown wrapper version maps to `KeyPackageStatus.unsupported` (a newer
  client's package — same outcome as an unreadable payload, nobody here can
  fix it), while a known-version envelope whose signer claim cannot be read
  maps to `rejected`. The helper split supports exactly that:
  `envelopeVersionOf` throws only on unknown versions, `envelopeSignerOf`
  only on malformation.
- **`publishLink` resolves the signer before the write**, so a link so
  malformed its signer cannot be read is refused rather than published and
  then logged broken — consistent with the file's own "a bad link on this
  record is worse than no link".

The version-2 flow arms ride the existing consumer rigs rather than new
ones: a JWS-wrapped key package is read and sealed to (and rejected when its
kid names another signer; `unsupported` at wrapper v3; `rejected` on an
unreadable header), a JWS-wrapped nskey advertisement resolves the same key,
the chain walk climbs a JWS-wrapped link, and the symmetric-key resolver
skips a revoked signer named only by `kid`. The root-link sites are
deliberately untouched per this section's scope note.

### 60.3 The version flag lives on the signer, defaulting v1

`EnvelopeSigning.envelopeVersion` — the signed-envelope axis of
[56.4](#564-from-the-pq-projects-view-40-is-final-3x-with-different-flag-defaults)'s
rollout table, in the "signer config" home that table names. `wrapAndSign`
passes it through; the default is `signedEnvelopeVersion` for all of 3.x and
4.0 flips it, no code fork. The Workstream A posture helper bundles this flag
with the others when it lands.

The key-package signer at `enroll:request` time
(`enrollment_key_package.dart`) does not read the flag: it runs before any
client exists, and it writes the one record whose shape is frozen for the
enrollment's life, so it stays at the `signEnvelope` default until the flip
itself decides otherwise. Threading a posture through it is the capstone's
business, not this commit's.

### 60.4 Two verifiers that are not ours say the envelope is RFC 7515

Per [48.5](#485-the-vectors-are-the-deliverable-not-the-migration), the
deliverable is a committed vector plus a runnable third-party check.
`test/vectors/jws_envelope_v2.json` holds one envelope per algorithm over a
fixed payload (fixture keys, privates included so the deterministic arm can
re-sign); `tool/verify_jws_vectors.mjs` hands them to panva's `jose`;
`test/jws_vector_test.dart` holds our own verifier to the same fixed bytes —
a sign→verify round trip agrees with itself about any drift, a committed
vector does not — and re-signs the RS256 arm expecting the byte-identical
envelope (PKCS#1 v1.5 is deterministic; ML-DSA is hedged, so that arm
verifies only).

Adjudicated 2026-08-09, two independent implementations:

- **RS256 — jose 6.2.8 on Node 24.2.0**: verifies, refuses the tampered
  payload, and ignores the wrapper's extra `v` member as RFC 7515 §7.2.2
  requires (the script deliberately hands jose the whole envelope, never a
  cleaned-up copy).
- **ML-DSA-65 — OpenSSL 3.6.3 CLI**: `openssl pkeyutl -verify -rawin` over
  the ASCII of `protected || '.' || payload`, public key wrapped as SPKI
  (OID 2.16.840.1.101.3.4.3.18), verifies and refuses a one-bit tamper.
  This is also the direct third-party proof of the RFC 9964 claim: pure
  ML-DSA, empty context, over the JWS signing input.
- jose's ML-DSA arm could not run locally: Node 24.2 bundles OpenSSL
  3.0.16, which cannot even import the key — the runtime, not the vector.
  The script says so in its header and stays committed for a Node whose
  OpenSSL is ≥ 3.5.

### 60.5 One live arm, and the docs reconciled

The functional pack's retrofit test (`self_enrollment_retrofit_live_test`,
the rf2c client test) gained the flipped world in miniature: set
`envelopeVersion` to 2, `wrapAndSign`, verify against the real tagged
`_apsk` the atServer composed at approval — ML-DSA under
`protected.payload` against a served key, not a mock. Green on the landing
run. Nothing else in either test pack needed changing: readers only widened,
producers are unchanged, so every existing pack test exercises the
version-1 arm exactly as before.

Reconciled in the same commit: implementation-plan 14.3 marked DONE
(producer behind the flag), the untracked staged plan's "nothing here is
implemented" header replaced with a pointer to this section and the two
re-grep corrections, and the three future-tense "the JWS migration will…"
comments in at_client's tests rewritten in present tense.

## 61. The barrel cycle is cut: no src file imports a public barrel (2026-08-10)

Phase 4a of the refactor plan. The named cycle was
`pq_signing_root.dart` importing `package:at_client/at_client.dart` while
the barrel exports the impl layer that imports the nskey subsystem — but
the survey showed the minimal set of files that would make the PQ
subsystem's import closure barrel-free pulled in nearly the whole package
(the spec needs `RemoteSecondary`, which reaches `AtClientManager`, which
constructs `AtClientImpl`, which imports everything). So the cut landed as
the package-wide invariant instead of a patchwork clean-list:

**No file under `lib/src` imports `at_client.dart` or
`at_client_mixins.dart` — the public barrels are export surface only.**
49 files moved from a barrel import to concrete
`package:at_client/src/...` imports of what each actually uses; all 126
`lib/src` files now have barrel-free transitive import closures (verified
by walking every file's import graph, not by the edit list).
`test/import_topology_test.dart` pins the invariant — red-proofed by
injecting a barrel import and watching it name the file.

### 61.1 The resolved-signing-algo record moved below the impl layer first

`EnvelopeSigning.wrapAndSign` resolved its algorithm through
`AtClientImpl.signingAlgoOf` — the one dependency that dragged the impl
layer (and through it the barrel) into the signing mixins' closure. The
resolution state (section 58's key-material-authoritative record) now
lives in `src/signing/resolved_signing_algo.dart` as an Expando keyed by
the client — the same client-associated-state pattern the crypto config
uses (section 27.2) — with `recordResolvedSigningAlgo` /
`resolvedSigningAlgoFor` / `signingAlgoOf`.
`AtClientImpl.signingAlgoType` and the static `signingAlgoOf` delegate to
it, so the section-58 public surface is byte-identical; the mixin and the
sync/notification service impls consume the low-level function directly.
For a non-`AtClientImpl` client the answer is unchanged too: nothing
records into the Expando, so the preference fallback answers, exactly as
the old `is AtClientImpl` branch did.

### 61.2 What 4a deliberately did not cut

Structural cycles among concrete src files remain and are later phases'
work, now visible instead of hidden behind the barrel:

- `at_client_secret_sharing.dart` imports `enrollment_service_impl.dart`
  (and the service impl imports the secret-sharing machinery for
  approve-time conveyance) — the secret_sharing↔service cycle, cut in 4g
  by consuming the 4d privilege-resolver seam.
- `AtClientImpl` ↔ `EnrollmentServiceImpl` — subsumed by 4d's bootstrap.

The plan's optional `src/signing/` file move (relocating the chain/root
files with re-export shims) was skipped: the cycle cut needed import
narrowing, not motion, and the nskey files' home is not what any later
phase depends on.

## 62. PqClientBootstrap: one owner for the PQ startup (2026-08-10)

Phase 4d, the keystone. Before it, `AtClientImpl` built a fresh
`PublishedNskeyKeyRing` inside each startup action — five constructions
per client (the era crypto config's, seeding's, hydration's,
missing-private request's, and the mint path's), plus four
`NskeyPrivateFiling`s and two `PqSigningRoot`s — so a private held in one
instance's memory was invisible to every other, and the whole startup ran
as two *racing* unawaited tasks (`_seedNamespaceKeys` and
`_fileConveyedKeysAndAnchor`).

`src/client/pq_client_bootstrap.dart` now owns ONE ring, filing, sharing
(`AtClientSecretSharing.forClient`, which was already per-client cached —
the bootstrap holds that instance rather than a rival), seeding and root
per client, and runs the startup as one ordered fire-and-forget task of
NAMED steps — the names are 14.13's gate-site list, each classified
active-write vs read-precondition in the dartdoc:

1. `hydrateHeldSecrets` (read-precondition), 2. `collectConveyedKeys`
(read-precondition, the only route conveyed material reaches the
keyfile), 3. `seedNamespaceKeys` (active, keeps its own
`AtClientPreference.seedNamespaceKeys` knob), 4. `requestRootPrivate`,
5. `requestMissingPrivates`, 6. `publishRootLink`, 7. `publishChainLink`,
8. `sweepUnanchoredEnrollments` (all active, each behind a
`PqStartupGates` bool defaulting ON). The gates object is the *seam* for
14.13's passive-by-default posture — building the flag later is config,
not a re-survey. The two read-preconditions have no gate field at all:
ungateable by construction. 14.13's remaining active sites live outside
the startup and outside this object: `register()`'s
`publishPublicSigningKey`, and the read-path conveyance hook, which IS
gated here (`askOnReadMiss` controls whether the ring gets the hook).

Deliberate structural change, not just motion: the two racing tasks are
now one serial sequence (seed placed between collect and the asks), which
eliminates the seeding-vs-filing interleaving class outright — the
2026-08-08 lost-update was one member of it. And the era config's ring IS
the bootstrap's ring, so a private the seeding step just minted is
visible to the very next read even for a client with no durable filing.

`startupComplete` is awaitable (tests may; `_init` never does — it fires
`startup()` unawaited, preserving fire-and-forget). No live-test timing
updates were needed: the functional pack's PQ tests drive the steps
directly with their own instances rather than waiting on the client's
startup tail. Loggers: the bootstrap logs per-instance, and
`AtClientImpl`'s `static late _logger` — which let a second client
re-point the first client's log name — became per-instance, with a small
static logger kept for the service `Finalizer`'s static context.

### 62.1 One privilege-resolver seam

`EnrollmentPrivilegeResolver` (`src/enroll/privilege_resolver.dart`, a
leaf interface) is the ONE injected seam for "is this enrollment fully
privileged" — consumed by the root-private request and the unanchored
sweep, and intended (4g) to replace the secret-sharing request gate's own
copy of the same question. The production implementation,
`EnrollmentRecordPrivilegeResolver` (in `src/service/`), is the old
`AtClientImpl._resolveFullPrivilege` moved verbatim: it answers from the
enrollment record, never from the client's own claims, and a client with
no enrollment id is fully privileged by construction (14.14's posture,
carried as-is). The sweep itself is injected as a callback, so the
bootstrap imports no service code.

### 62.2 The impl↔service cycle is gone (4d-0)

`EnrollmentServiceImpl`'s import closure reached back to `AtClientImpl`
through three incidental edges, each cut in the preparatory commit:
dartdoc-only imports of the impl/manager in `at_client_preference`,
`local_secondary` and `at_client_spec` (now plain-code references), a
deprecated ignored `AtClientManager` parameter on
`NotificationServiceImpl.create` (removed — internal signature), and
`RemoteSecondary`'s `AtClientManager.getInstance().secondaryAddressFinder`
reach-up, now behind `secondary_address_finder_source.dart`: the
manager's constructors register a source reading the singleton's field,
the read stays lazy and per-call, so the semantics — including the quirk
that per-atSign managers' own finder fields are never consulted — are
preserved exactly. `import_topology_test.dart` pins the cut (red-proofed
before the edits): the service impl's closure contains neither the client
impl nor the manager. The impl still calls the service — one-directional,
by design.

### 62.3 Cancellable stop, and the registry out of the value type

Two adjacent commits on the keystone. **Stop:** `AtClient.stop()` now
reaches the bootstrap, which checks between steps — a running step
finishes (steps are atomic), no further step starts. Before this a
stopped client's fire-and-forget startup kept publishing. Test-first with
a parked-startup arrangement (the keyfile read blocked under test
control); red-proofed by neutering the boundary check and watching the
sweep run after stop.

**EraDefaults:** the per-client era-default registry moved out of
`CryptoConfig` — which was carrying a static `Expando` registry inside
the value type it stores — into `src/crypto/era_defaults.dart`, a small
generic `EraDefaults<T>` (of / adoptIfAbsent / clear, Expando-backed).
`CryptoConfig.forClient` / `adoptEraDefault` / `eraDefaultFor` delegate,
so the public surface is unchanged (one addition:
`@visibleForTesting clearEraDefault`). The
don't-resolve-into-the-shared-preference property is now the registry
type's documented contract rather than a comment on a private field.

### 62.4 The `_apsk` publishes read one snapshot (the 3-read race)

`publishOwnRootLink` and `publishPendingLink` each read the enrollment's
own `_apsk` **three** times per operation — once for the key the link
vouches for, once for the already-published check, and once inside
`_publishInto` for the value the put re-sends. Three reads of one record
mean the key vouched for, the check and the republished value could each
come from a *different* state of the record: anything writing between
them (another device of the same enrollment starting, a registration
re-put) made the published link vouch for a key that was no longer the
record's value, or resurrected state the check had ruled out.

Now each operation reads the record once and every check and the write
use that snapshot: `_publishInto` and `publishLink` take an optional
pre-read `current`, and the field checks have an in-hand flavour
(`_fieldFrom`) beside the fetching one. Test-first: the new
read-count pins in `pq_signing_chain_test` asserted 1 and measured 3
before the fix, on both paths. Cross-process writers still exist —
read-merge-write against a shared record remains the pattern until the
store grows an atomic verb — but one operation is no longer a race with
itself, and in-process the bootstrap already serialised the writers.

### 62.5 NskeySeed vs NskeyDecapsulationKey — and the two conveyances the types caught

The nskey path carried two different byte meanings through one bare
`Uint8List`: the **seed** (compact, re-derivable — what is filed and what
conveyance must send) and the **expanded decapsulation key** (what
`pqOpen` takes — for ML-KEM it cannot be turned back into a public half).
X-Wing's seed and secretKey are the same bytes, so any confusion between
the two was invisible until ML-KEM — the exact accident class the
2026-08-07 at_chops seed lesson named, one layer up. They are now
distinct extension types in `nskey_key_ring.dart` (zero runtime cost;
the swap is a compile error): `NskeyKeyRing.privateHalf` returns
`NskeyDecapsulationKey`, `NskeyPrivateFiling.store` takes an `NskeySeed`,
`read()` expands, the new `readSeed()` answers with the durable form,
and the bulk reads (`readAll`/`readAllFor`) are typed as the seeds they
return.

**Retyping the flow immediately surfaced two real data-loss bugs**, both
fixed test-first in this commit: `NskeySeeding._convey` (the mint-time
push) and `NskeyRotation.rotateNamespaceKey`'s successor fan-out both
conveyed `filing.read(...)` — the EXPANDED key — as the "seed". The
receiver validates an arrival by re-deriving the advertised public half
(`keyPairFromSeed`), so an ML-KEM private conveyed this way is refused
on arrival and the other enrollments simply never get the generation:
under 1:1:1 that is every other device unable to open the namespace.
Both sites now convey `readSeed()`. The rotation test's old conveyed-
value assertion had compared against the same wrong source
(`filer.read`) — a self-consistent pin, collapsed arms — and was
corrected in the same commit; the new ML-KEM arms (rotation fan-out,
mint-time push, and the filing seed/expanded meaning-pin) each went red
against the old code with the fix reverted. The plan's survey line
("mint files the SEED but caches the expanded key") described a
consistent pair — mint's cache and `read()` both carry the expanded
form deliberately; the real defect was in the conveyances, and only the
types found it.

### 62.6 PqSigningChain gets a constructor

The chain was a bag of statics each threading `AtClient` (and often the
same derived state) through every call. It is now an instance per
client — `PqSigningChain(atClient)` — with the client-bound operations
(`signLinkFor`, `publishLink`, `readLink`, `readRootLink`,
`publishOwnRootLink`, `publishPendingLink`, `verifyChain`) as instance
methods and a per-instance logger that names its atSign. The wire
vocabulary stays static where it was: the field names, the secret name,
`apskUri`, `linkPayload` and the codecs belong to the protocol, not to
any client, and the raw-literal pins in `wire_literal_pins_test`
continue to address them unchanged. The bootstrap now owns one chain
beside its one ring/filing/sharing/root; the enrollment service's sweep
builds one per sweep. Pure motion — behaviour identical, all three test
packages swept in the same commit.

## 63. Phase 4e: EnrollmentConveyance out of EnrollmentServiceImpl (2026-08-10)

**Status:** accepted. The approval-time sealing (the old private
`_shareSecretsWith`, 134 lines carrying five conveyances with five
failure policies as prose) and the fleet-repair sweep move out of
`EnrollmentServiceImpl` behind a new injected seam:
`EnrollmentConveyance` (`src/enroll/enrollment_conveyance.dart`, a leaf
interface beside the privilege resolver) with the production
`EnvelopeEnrollmentConveyance` in `src/service/`. The service keeps its
original verb-wrapper job — fetch/approve/deny/revoke — plus a
delegating `sweepUnanchoredEnrollments()`, so every call site (the
bootstrap wiring included) is unchanged. The published `approve()`
signature is byte-identical, and both external approve paths
(at_client_flutter's `FlutterEnrollmentService.approve` and
at_onboarding_cli's `auth_cli`) were re-verified to route through
`atClient.enrollmentService.approve` — ruling [20.2](#202-the-rulings)
#1 survives the extraction untouched.

**The seam reports; the caller enforces.** `conveySecretsTo` returns
the four-way `KeyPackageStatus` (20.2 #3) instead of throwing on a
rejected package: what to convey is substrate policy, but whether a
just-approved device that cannot decrypt should fail the approval is
the approver's policy, so the throw (same exception type, same message)
now lives in `approve()` where the party who can revoke is listening.
The register()-precondition throw stays inside the conveyance — it is a
conveyance precondition, not approval policy. Seam pins in
`enrollment_conveyance_seam_test.dart` cover all four status arms, the
minted-key pass-through, the no-record guard and the sweep delegation;
the rejected-arm pin was red-proofed by neutering the status check. The
pure privilege classifier moved from the service's static to a
top-level `isFullyPrivileged` in `src/enroll/privilege_resolver.dart`
(the static delegates, so `EnrollmentServiceImpl.isFullyPrivileged`
callers — the functional pack included — are unchanged); the classifier
had to leave the service because the conveyance impl consults it and
importing the service back would have opened a new in-package cycle.
Log messages moved verbatim; the logger name follows the class, as with
the 4d moves.

### 63.1 A conveyance refusal no longer discards the approval it follows

The audit defect: `approve()` could throw **after** the server-side
approval had succeeded, losing the `AtEnrollmentResponse` — a caller
saw "the approval failed" for an enrollment that was in fact live, and
the natural reaction (retry, or report failure upstream) is wrong both
ways. Fixed within the byte-identical-signature constraint by making
the rejected-package throw a carrying subtype:
`EnrollmentConveyanceException extends AtEnrollmentException`, holding
the successful `response` and the four-way `keyPackageStatus`. Existing
catch sites keep working (subtype, pinned by test); new callers can
tell "approved but cannot decrypt — consider revoking" from "the
approval failed". Exported from the main barrel `show`-narrowed to the
exception alone — the seam interface stays internal, consistent with
the minimal-surface rulings. Red-first: the seam test's rejected arm
demanded the carrying type before it existed.

### 63.2 at_client_flutter reports approved-but-cannot-decrypt truthfully

The remaining half of the Phase-1 flutter approve fix, deferred to here
because 4e sets the contract it needs. `FlutterEnrollmentService
.approve`'s generic catch wrapped *everything* in
`Exception('Enrollment failed: …')` — including the refusal at_client's
`approve()` throws **after** a successful server-side approval. Same
misreporting class as the null-bang: a live enrollment presented as a
failed one, inviting a retry of an approval that already went through.
Now that the refusal is the carrying `EnrollmentConveyanceException`
(63.1), the wrapper catches it by type, finishes the approval
bookkeeping (the pending-enrollment delete — the approval *did*
happen), closes the lookup, and rethrows it unwrapped so the caller
sees the true state: approved, cannot decrypt, consider revoking.
First cross-package use of an unpublished at_client 3.14.1 API, so
at_client_flutter's floor rises to `^3.14.1` in the same commit, with
the why recorded beside it in the pubspec as the at_auth floor's
comment already does.

### 63.3 The adversarial review's harvest, and what it cost to learn

A 19-agent find-and-refute pass over the three 4e commits confirmed two
defects and sharpened one contract. Confirmed: (1) the barrel export in
63.1 landed without its golden-set edit, so
`public_api_surface_test.dart` — whose own dartdoc demands the edit in
the same commit — was red from that commit until the paperwork commit;
the miss survived because only the seam/guard/topology tests were run
after the export, and the full-suite number reported at the time was
arithmetic, not a measurement. The full unit suite is the per-commit
rail; a projected count is not a rail. (2) The at_client CHANGELOG
entry existed only in the working tree while the flutter commit had
carried its own — both now committed. Sharpened: the refuted-but-
accurate findings showed the no-lost-response contract covered only the
rejected-package arm — the unregistered-approver guard and the
no-ordinary-namespace refusal still escaped `approve()` as plain
`AtEnrollmentException` after a successful server-side approval. Now
every post-approval conveyance refusal is wrapped into the carrying
exception (test-first; the package's own status rides as `present`
when the package was not the refusal), and a composition pin drives a
tampered package through the *real* conveyance — red under exactly the
status-flip mutation a review agent probed with. Deferred to the
backlog, deliberately: the enrollment-list widget's generic
"Failed to approve" snackbar for a post-approval refusal (needs the
widget to take an injectable service before it is testable, the
`ApkamDialog` pattern) and its `encryptedAPKAMSymmetricKey!` null-bang
on pq-mode requests that wrapped no key. Process ruling: review
workflows get worktree isolation from here on — one finder
mutation-probed the shared working tree (it restored the file itself,
and the mutation post-dated the functional run by two minutes, so the
143/143 stood — but only the timestamps proved that).

## 64. Phase 4f: one CryptoRuntime.prepareWrite() (2026-08-10)

**Status:** accepted. The resolve/stamp/prepare block that the notify
transformer, the text-notification path and the put pre-pass each
carried — with the same rationale comment duplicated word-for-word at
the two notification sites — is one runtime entry point:
`CryptoRuntime.prepareWrite(atKey, {requestedProviderId,
useRemoteAtServer, stampProviderId})`, returning the resolved id.
Additive on the concrete runtime, as ruled: capability dispatch stays
is-checks and `CryptoProvider` gains no member. The one real asymmetry
between the sites is now a *documented parameter* instead of a shape
difference: the put pre-pass must not stamp early, because its
`NamespaceKeyUnavailableException` catch may re-route the write to
legacy, and a key already stamped with the provider that declined would
claim a scheme its value was never sealed under — permanently, since
the record's metadata rides the write. Test-first pins in
`crypto_runtime_test.dart`: stamp-when-absent, keep-existing-stamp
(`??=`), the unstamped arm with that rationale, and the
non-PreparesWrites skip. The duplicated prose lives once, on the
method's dartdoc; MetadataWireCodec stays deferred as the plan ruled —
nothing new justified touching every record's metadata.

## 65. Phase 4g: the secret-sharing seam work (2026-08-10)

### 65.1 sweepOnce's catch no longer spans the emission boundary

The sweep's single `catch` covered consume, emit and the two payload
handlers, and its recovery — release the claim, retry next sweep — was
correct only for the consume half. A handler failing *after*
`_receivedController.add` (a thrown privilege gate, a store write)
released the claim too, so the next sweep re-consumed and re-emitted
the same envelope: the method's own dartdoc promises "the same payload
is never emitted twice", and the wide try broke it. The house rule in
its literal shape — a catch that names one cause (transient consume
failure) mis-reporting everything else that lands inside it. Now each
operation has its own guard: a consume failure releases the claim and
retries in-process (nothing was emitted, a retry repeats nothing); a
handler failure keeps the claim and the envelope, logged at warning,
for a fresh process — whose stream has no listeners yet — to retry
whole. Test-first with the gate as the injection point (it runs inside
the request handler, strictly after emission): red showed exactly two
emissions of one envelope, green shows one emission and one gate call.

### 65.2 The substrate answers privilege through the one seam

The last genuine cycle the audit named: `at_client_secret_sharing`'s
ctor self-wired the per-enrollment request gate by constructing
`EnrollmentServiceImpl` — substrate reaching up into the service layer
that composes it. Cut by widening the 4d seam rather than growing a
second one: `EnrollmentPrivilegeResolver` gains
`isEnrollmentFullyPrivileged(enrollmentId)` — the requester-flavoured
question the gate actually asks, where `isFullyPrivileged()` asks it
about this client — and the record-backed implementation carries the
substrate's old fetch-and-classify body verbatim (the self flavour now
delegates to it). The production wiring lives in `PqClientBootstrap`'s
constructor, beside the rest of the per-client composition, and
deliberately NOT in a startup step: a request can arrive as soon as
the client listens, so the gate must exist the moment the client does,
and it is composition, not a gateable action. A directly constructed
sharing instance now has a null gate — fail closed, exactly what the
pairwise suite already pins for the unwired case. Pinned three ways:
the topology test's new closure exclusion (red before the cut, green
after), the bootstrap composition test (gate non-null, consults the
seam with the requester's id, never the self flavour), and a
record-backed resolver test including the no-record-is-no-privilege
arm. The interface widening swept the one `implements` fake in the
same edit, per the Mock-implements rule. The PairwiseSecretSharing
mixin split stays elective, not taken — nothing here needed it.

## 66. The approval list's last hop tells the truth (2026-08-10)

**Status:** accepted. The two items 63.3 deferred, done now at Gary's
direction. `EnrollmentRequestList._handleApprove` null-banged
`encryptedAPKAMSymmetricKey` — null on every pq-mode request, whose
whole signal is that the approver mints the key — so every such
approval crashed before `FlutterEnrollmentService.approve` was even
called, and the generic catch dressed the crash as `Failed to
approve`. Fixed to pass empty (the mint signal the approve path
expects). And the widget now catches `EnrollmentConveyanceException`:
the row leaves the list (the request is no longer pending — the
approval *happened*) and the refusal's own prose is shown unwrapped.
To make any of it testable the widget gained an injectable
`enrollmentService` (the `ApkamActivationDialog` pattern, the third
use of it in the package) and resolves its `AtClient` through the
service's existing seam instead of reaching for the
`AtClientManager` singleton at four sites — production-identical, and
the whole flow now drives through one injected mock. Widget tests
red-proofed with a single-token flip of the null-bang, which sends
both arms through the old path; restored by inverse edit, not
`git checkout`, because the file was uncommitted — the lesson of this
morning's self-inflicted rewrite applied.

## 67. Workstream B(i): the sweep anchors to the root (2026-08-10)

**Status:** accepted; design change, ruled during the 2026-08-09 plan
grilling and sharpened by Gary 2026-08-10: **the class that signs root
links is ANY fully privileged enrollment** — `rw` on `*` and `__manage`,
the class entitled to hold the signing root — **and that class signs
root links INSTEAD OF chain links.** Privilege decides; possession is
the signer's responsibility: a fully privileged sweeper that has not
yet received the root private conveys *nothing* (the every-start pull
heals possession), because a chain link from the entitled class would
demote the design rather than bridge it. Chain links remain what a
non-fully-privileged approver produces — a provisional fast-path — and
the sweep now UPGRADES them: only a published *root* link skips an
enrollment, where the old sweep skipped chain-linked ones and made
chained-but-unanchored a terminal state.

Mechanics: `PqSigningChain.signRootLinkFor(child, rootPrivate:)` signs
the same link payload with the root ML-DSA key in the same shape
`publishOwnRootLink` publishes and `_checkRootLink` verifies — one
codec (`_rootLinkOver`), shared by all three. The conveyance rides a
new reserved secret name `__en.apskRootLink` (raw-literal pinned),
distinct from the chain flavour for the same reason `rootLinkField` is
its own field: the name settles which validation runs before anything
is decoded. `publishPendingLink` now stamps both flavours; a conveyed
root link is stamped ONLY after verifying against the published
signing root — the substrate authenticates the sender, and the sender
is not the root — plus the names-this-enrollment and
covers-the-published-key checks every link gets.

Differential proof: the three sweep arms (anchor, upgrade, no-private)
went red against the old code for exactly the ruled reasons — no root
link stamped, upgrade skipped, a chain link conveyed by a keyless
sweeper — and the receiver refuses a forged root link with a genuine
root published, so the refusal is attributable to the signature. The
anchor arm asserts `ChainVerdict.anchored` through real ML-DSA
verification, not link presence. Two startup rigs were re-sentineled
in the same commit: the inertness rig grepped the renamed skip line,
and the call-order rig's orphaned-private arm awaited the roster fetch
that a possession-gated sweep correctly never issues — it now awaits
`startupComplete`, the completion future built in 4d (the rig's "no
completion future" comment predated it). The unit fixture builds the
entitled state directly rather than through `mintIfAbsent`, whose
publish rides `executeVerb` — a verb the remote-backed mock does not
model; its lost-create reconciliation silently retires the pair there,
which the probe test established before the fixture was redesigned.

---

## 68. The enrollment record stops being a one-way door: `enroll:updateMetadata` (2026-08-10)

**Status:** accepted as a design ruling. Nothing is built; this section is the
specification the work is written against, and the mechanism is named here
because no defect is being fixed — this reverses a scope decision.

It reverses one half of [section 12](#12-advertised-recipient-keys-are-signed-against-_apsk-2026-07-02)
and [section 20](#20-ss-2-how-the-key-package-reaches-an-enrollment-and-how-conveyance-fires-2026-08-03):
the "no post-enrollment metadata write, **ever**". It does not reverse the other
half, and the difference matters.

### 68.1 What is not changing: one key package, many keys

The 1:1:1 cardinality and the **singular** `metadata.keyPackage` stand. A
format-keyed `keyPackages` map was rejected in section 12 as redundant with the
agility already inside the package, and that reasoning survives intact:

- `KeyPackage.keys` is a **list** of `{kid, use, alg, pub}`, and a sender picks
  across it — `bestKeyFor(SecretSharingAlgos.keyAlgos)`
  (`pairwise_secret_sharing.dart:234`);
- `KeyPackage.suites` is a **list** of constructions the holder can open, and the
  sender intersects it — `bestSuiteFor` (`:253`), mapped to a `pqSeal` version by
  `sealVersionFor`;
- `openableSuitesForAll` already derives the suite list from an arbitrary set of
  advertised key algorithms.

So an enrollment that must offer two KEMs advertises **two keys in its one
package**, never two packages. Nothing about that needs a protocol change; the
minting side is what is singular, not the schema — `enrollmentKeyPackageBuilder`
takes one `keyEstablishmentAlgo` and emits one `PackageKey`.

What was wrong was never the cardinality. It was the **freeze**.

### 68.2 What the freeze costs, and what it never bought

Three costs, all present in the tree today:

1. **A package can never gain a key.** `keyEstablishmentAlgo` is frozen at
   `enroll:request`; a client that later needs the other KEM cannot add it, and
   `register()` deliberately keeps the loaded key's algorithm over a changed
   preference (`key_package_registration.dart:180`) because the kpid is the
   address peers seal to. The preference takes effect on the *next enrollment*.
2. **The envelope-shape ratchet is frozen with it.** `jwsEnvelopeVersion`'s
   producer stays behind a flag because "an envelope emitted in a shape the fleet
   cannot read yet is frozen unreadable for that enrollment's life"
   (`envelope_signature.dart:87`). The version hatch exists and cannot be used.
3. **An unparseable package is terminal.** `KeyPackageStatus.unsupported` ends
   that enrollment's ability to receive a sealed conveyance for good; the only
   remedy is delete-and-re-enrol
   ([implementation-plan 14.6](implementation-plan.md#146-the-enrollment-records-metadatakeypackage-is-a-one-way-door)).

Against that, note what the freeze never bought. **It is not a security
property.** Nothing trusts a key package because the record is immutable — a
reader trusts it because the APKAM signature verifies against *that enrollment's*
`_apsk` (section 12), and that check is indifferent to whether the record can be
rewritten. The "ever" was scope: SS-2 wanted zero grammar change, and the
sentence outlived the reason for it.

### 68.3 The rulings

| # | Ruling |
|---|--------|
| 1 | **A new `enroll:updateMetadata` sub-command** sets named top-level metadata keys on an existing enrollment. Not a general enrollment-update verb: it reaches `metadata` and nothing else. `apkamPublicKey`, `signingAlgo`, `namespaces` and the approval state stay out of reach — an enrollment that wants a different APKAM keypair is a different enrollment |
| 2 | **Self-only.** The connection's `enrollmentId` must equal `enrollParams.enrollmentId`. This is an explicit **exception to the "no enrollmentId ⇒ full permissions" default** in `isAuthorized` (`abstract_verb_handler.dart:218`) — an owner or legacy-PKAM connection is refused, not waved through. Two reasons, and the second is the one that carries the design: an owner cannot sign a package with that enrollment's APKAM private, so anything it wrote would fail every reader's verification and buys only a denial-of-service; and self-only is precisely what makes replace-semantics safe, because the only party who can reinstate a stale package is the holder of the key it was signed with, which makes rollback self-harm rather than an attack |
| 3 | **Approved state only.** Pending, denied, revoked and expired are refused, mirroring `_verifyEnrollmentStateBeforeAction`. A revoked enrollment must not be able to re-advertise |
| 4 | **Per-key set, never whole-map replace.** The request names the keys to set; keys it does not name survive untouched. Whole-map replace is read-mutate-write against shared durable state — a client that does not know about a future sibling field clobbers it, and two processes of one device are concurrent by construction |
| 5 | **The server keeps no opinion.** Metadata stays opaque: no parsing, no signature check, no ordering of successive packages. The consequence is stated rather than mitigated — the server cannot detect a downgrade to an older validly-signed package, which is why ruling 2 carries the weight it does |
| 6 | **A replaced kpid is not retired.** The client keeps the superseded private half and keeps answering at the old address. An envelope written before the update is addressed to the old kpid and must still open; the alternative is silent, unattributable loss of a secret that was correctly sent |
| 7 | **A server without the sub-command must fail loudly**, and does: an unknown operation does not match the verb regex. This is strictly better than the `EnrollParams.metadata` passthrough it complements, which an old atServer drops silently — the gap recorded at [implementation-plan §14 backlog](implementation-plan.md#14-backlog--carried-items-with-no-owning-project) ("a PQ-capable client cannot tell a legacy atServer from an old peer") |
| 8 | **No peer invalidation is owed today, and the reason is checkable.** `VerbEnrollmentDirectory.listForNamespace` executes `enroll:listns` against the atServer on every call (`enrollment_directory.dart:141`) and caches nothing, so a sender reads the current package at seal time. Any future cache inherits an invalidation obligation from this ruling |

### 68.4 The verb

**Grammar.** One alternation entry in `syntax.dart`'s `enroll` pattern. Verified
against the existing regex rather than assumed:
`enroll:updateMetadata:{"enrollmentId":…,"metadata":{…}}` parses to
`operation=updateMetadata` plus the JSON in `enrollParams`, with `force` and
`listNamespace` unmatched (the `listNamespace` group excludes `{`, so it cannot
swallow the payload), and `enroll:request` / `enroll:listns` keep their current
captures.

**Params.** No new fields. `EnrollParams.enrollmentId` names the target and
`EnrollParams.metadata` carries the keys to set (ruling 4), which is the same
field `enroll:request` already uses — so a client builds the value through the
path it already has.

**Handler.** A `case 'updateMetadata'` beside the existing operations.
Authentication is already required for every operation but `request`
(`enroll_verb_handler.dart:65`), so the net-new checks are the self-only identity
test (ruling 2), the approved-state test (ruling 3), and a `_validateParams` arm
requiring a non-empty `enrollmentId` and `metadata`. The write is the same
`enMgr.put` the approve path uses, with the enrollment's state and TTL untouched.

**Response.** `{enrollmentId, status}`, matching the approve/revoke shape.

**Reach.** at_commons (grammar, `EnrollVerbBuilder`), the server spec, **every
atServer implementation**, and at_client's caller — one coordinated sweep, per
the multi-repo protocol-seam rule. The grammar and the client half are useless
alone.

### 68.5 The receiver becomes multi-kpid

This is the larger half of the work, and it is client-side only. Today a client
holds exactly one KEM keypair and one kpid, and that singleton is threaded
through the receive path. Every site, verified by enumeration:

| Site | What it assumes | What it becomes |
|------|-----------------|-----------------|
| `key_package_registration.dart:67-105` (`_encSeed` / `_encPublicKey` / `_encSecretKey` / `_encKeyAlgo`) | one keypair per client | a set, keyed by kid |
| `key_package_registration.dart:130` (`kpid`) | one address | `kpids` — a set; the scalar survives only as "the one this client would advertise first" |
| `key_package_registration.dart:136` (`myKeyPackage`) | a one-element `keys` list | one entry per held key; `suites` still derives itself |
| `key_package_persistence.dart:98` (`keyPackageMaterial`) | returns one material, newest-wins | returns every material for this enrollment; newest-wins survives only as *ordering*, not as *selection* |
| `key_package_registration.dart:31` (`PersistedApkamKeys`) | one `(encSeed, keyAlgo)` | a list |
| `envelope_addressing.dart:38-49` (`fragmentFor` / `regexFor` / `sweepRegexFor` / `namespaceSweepRegexFor`) | one kpid per regex | an any-of form over a set |
| `pairwise_secret_sharing.dart:368,379,415` (sync marker, wake-up subscription, sweep scan) | one address to watch | watches every held address |
| `pairwise_secret_sharing.dart:483,506` (`toKpid` / `kid` checks in `_consume`) | equality with the one kpid | membership in the held set |
| `pairwise_secret_sharing.dart:525` (`encSecretKey` passed to `pqOpen`) | the only secret | **the secret selected by `envelope.kid`** — the substantive change; handing `pqOpen` the wrong key fails as an indistinguishable AEAD error |
| `pairwise_secret_sharing.dart:725,761` (`_envelopeKeysFor` / `_answerAlreadySent`) | one address decides whether an answer is already waiting | any held address does |
| `enrollment_symmetric_key.dart:64,107` (`_keyPackageHalves`) | one `(kpid, secretKey, keyAlgo)` triple, pre-client | tries each held key |

One defect that multi-key **forces into the open**: the self-identification checks
at `pairwise_secret_sharing.dart:575` and `:910` skip a member by comparing
`to.kpid != kpid` — a peer's *sender-preference-derived* kid against this
client's own. Once a package advertises more than one key, `KeyPackage.kpid`
returns whichever key the reading build prefers, so two clients with different
`keyAlgos` orderings disagree about a package's kid and a client can fail to
recognise itself. The check should compare `enrollmentId`, which is what it
actually means and what `NamespaceMember` already carries.

⚠️ **Amended 2026-08-13 — most of this table is now built, and two of its rows
were wrong.** [14.18](../implementation-plan.md#1418-the-remaining-d1-initial-development-sequence)
step 5 landed the receiver-multi-kpid work as
[95](#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12)
rulings 6–9, in `6a5eac838`, `f956b2146` and `f6fc3796e`. Everything above is
done except as noted. Grep for the symbol rather than trusting a line number:
every file in the table has moved since it was written.

- **The `_envelopeKeysFor` / `_answerAlreadySent` row is wrong.** Its address is
  the **requester's** (`_answerAlreadySent(received.fromKpid, …)`), not one this
  client holds, so "any held address does" names the wrong party. Both the
  suppression check and the answers that would trip it use the requester's
  active key, so they agree and nothing changes. Unchanged, deliberately.
- **The `_keyPackageHalves` row is the one site left singular**, and step 5 does
  not need it: it runs at enrollment time on a keyfile that holds exactly the
  package `enrollmentKeyPackageBuilder` has just filed. Two can only appear on a
  **retrofitted** keyfile, and there the real defect is a different one —
  `_keyPackageHalves` scopes by neither enrollment id nor recency, where
  `keyPackageMaterials` does both, so it can pick a co-tenant's package and then
  poll for envelopes at an address nobody is writing to until it times out. That
  is pre-existing and unrelated to plurality; it wants its own fix.
- **The self-identification defect described below the table is already fixed.**
  `_isSelf` compares `member.enrollmentId == selfEnrollmentId` today.

### 68.6 What this does not do

- **It re-seals nothing.** Material already sealed to the old key stays sealed to
  it. That costs nothing here, because ruling 2 makes the updater an enrollment
  that already holds the plaintext — it re-files locally under the new key. No
  conveyance, no peer involvement, no approver.
- **It does not make an approval bind to a target.** An approver that inspected a
  key package at approve time is not told when it changes. That is not privilege
  escalation — the principal is unchanged — but any interface that says "you
  approved this key" stops being true, and that is a UX claim to fix, not a
  protocol one.
- **It does not rotate an APKAM keypair.** `apkamPublicKey` is not metadata
  (ruling 1).
- **It does not retire the dartdoc that states the freeze.** Roughly a dozen
  comments across `at_client` correctly describe today's behaviour — in
  `key_package.dart`, `enrollment_key_package.dart`, `envelope_signature.dart`,
  `key_package_persistence.dart`, `pq_native_onboard.dart`,
  `key_package_registration.dart`, `envelope_signing.dart` and
  `response/enrollment.dart`. They stay accurate until the verb ships and are the
  sweep list for the commit that lands it.

## 68b. Workstream B(ii): approvals anchor to the root (2026-08-10)

**Status:** accepted; Option-B of backlog 14.14, under the same class
ruling as [67](#67-workstream-bi-the-sweep-anchors-to-the-root-2026-08-10):
any fully privileged enrollment signs root links instead of chain
links. The approve-path conveyance now decides the link flavour by the
APPROVER's own privilege, resolved through the one injected seam: fully
privileged and holding the root private → `signRootLinkFor`, conveyed
under `__en.apskRootLink`, so the enrollment is *born anchored*; not
fully privileged (approval takes `__manage`, not necessarily `*`) →
today's provisional chain link, which the sweep later upgrades; fully
privileged without the private → no link at all, with the sweep as the
heal — the same no-demotion rule as the sweep's. The root private is
read once and shared with the root-private conveyance block that
follows it.

Wiring: `EnvelopeEnrollmentConveyance` takes an
`EnrollmentPrivilegeResolver` — the 4d seam, its third consumer — and
`EnrollmentRecordPrivilegeResolver` now takes its enrollment lister
injected instead of constructing `EnrollmentServiceImpl`, which both
removes the resolver↔service edge and lets the service compose the
default conveyance without opening a cycle. The self-privilege check
costs one roster fetch per approval, beside the two reads approval
already makes. Differential proof: the privileged and
privileged-without-possession arms went red against the old code (a
chain link conveyed in both), the non-privileged arm stayed green, and
the privileged arm asserts `ChainVerdict.anchored` through real ML-DSA
verification plus root-INSTEAD-OF-chain (no chain-flavoured secret
arrives). The functional pack's approve-row prose was swept in the
same commit — its live approver authenticates with the atSign's own
keys and is fully privileged by construction (14.14's posture), so its
conveyed link is root-flavoured now; the row's count assertions were
already flavour-agnostic. Boundary note: the full-suite run at this
commit carries one red owned by the PARALLEL agent on this branch
(their `6cfca51d4` added the UC-A2.5/UC-A2.6 catalogue rows ahead of
their scenarios, so `catalogue_test`'s completeness pin is red on
their in-flight state, verified by input mtimes and their edit set —
not by this change).

## 69. Workstream B(iii): the retrofit selector, and the KEM the retrofit froze wrong (2026-08-10)

**Status:** accepted. The retrofit signing algorithm is a per-operation
PARAMETER (never a preference), the last of the five rollout axes to
gain its flag. *Amended 2026-08-13: "the last" was true when written and is
not now — the in-use signing set ([§91.3](#913-the-rulings) ruling 16) became
an axis later, taking the slot the deleted signed-envelope-version axis left.* `AtSelfEnrollmentRequest.signingAlgo` (at_auth 3.4.0,
additive, default `mldsa65` — the mechanism keeps its old behaviour)
selects what the self-enrollment mints: `rsa2048` is type-1, the
rollout-window mode — a FRESH RSA keypair under a new enrollment id,
'same RSA' meaning same ALGORITHM never same key object, so
one-enrollment-one-keypair and the PKAM binding stay unambiguous — and
anything outside the two retrofit algorithms is refused before minting.
The keyfile idempotence check became per-requested-algorithm: the old
all-ML-DSA filter would have handed a type-1 caller the PQ enrollment
(red-proofed by restoring it), while per-algo lets one keyfile hold
both modes and makes reruns of each reuse its own.
`selfRetrofit` carries the POLICY default: `rsa2048` in 3.x per the
rollout-posture table, flipped by the 4.0 posture; the seven e2e mode-B
call sites pass `mldsa65` explicitly now. And the audit's HIGH finding
is fixed in the same motion: `selfRetrofit` now threads
`preference.keyEstablishmentAlgo` into `enrollmentKeyPackageBuilder`,
where it previously ignored the knob and every retrofitted enrollment
froze X-Wing into its write-once key package whatever the deployment
had configured. Live proof: a new functional arm drives the rsa2048
self-enroll against the real atServer — auto-approve, fresh-RSA
keyfile material, and RSA PKAM under the new id — beside the existing
ML-DSA row, which also exercises per-algo idempotence live since both
rows share one keyfile.

## 70. Workstream A capstone: ReleasePosture, the five flags as one value (2026-08-10)

**Status:** accepted and landed. The convenience posture helper the 56.4
ruling promised — the five rollout axes, each still an independent flag in
its natural home, settable as a group.

*Amended 2026-08-13 during implementation: two of the axes this entry describes
have moved. The signed-envelope version stopped being an axis
([§95](#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12)
ruling 1) — the paragraph below still describes `EnvelopeSigning.envelopeVersion`
resolving per-signer → posture → v1, and none of that mechanism exists; there is
one shape and a constant. The in-use signing set ([§91.3](#913-the-rulings)
ruling 16) took the vacated fifth slot, so the heading's count is right again by
coincidence rather than because these five stand.* `ReleasePosture` (at_client, main
barrel) has exactly two constructors and no general one: `migration()` is
the 3.x column of the 56.4 table, `postQuantum()` the 4.0 column, and a
deployment wanting a mixture sets the individual flag beside the posture
rather than minting a hybrid no release ever shipped. It rides
`AtClientPreference(posture:)` — final at construction, like
`disallowLegacyEncryption` and for the same reason — and is consulted at
each axis's home: the era adoption site picks `CryptoConfig.nskey` vs
`readsNskeyWritesLegacy` (still built per-client from the bootstrap's
ring, preserving 27.2); the preference derives `disallowLegacyEncryption`
when the app passed none; `EnvelopeSigning.envelopeVersion` became a
getter that falls back per-signer-override → posture → v1, which is the
only mechanism that reaches the signers the SDK constructs out of a
caller's reach (four sites — assignment never could); `selfRetrofit`'s
`signingAlgo` went nullable and resolves against the posture (the "policy
default" 69 promised the posture would flip). Every consult is
red-proofed by a mutation probe.

**60.3's open item is resolved: the key-package signer now takes the
version.** `enrollmentKeyPackageBuilder` (and `makeActivationPqNative`
above it) gained `envelopeVersion`, default v1, threaded from
`preference.posture` by `selfRetrofit` and `pqNativeOnboard`. Emitting v2
into the write-once `metadata.keyPackage` under an early-adopter posture
is safe by the 56.5 sequencing: every 3.x reader already accepts both
shapes.

**The key-exchange axis stays caller-composed.** Submission goes through
at_auth, which cannot see a preference (dependency direction), and pq
mode needs the builder and resolver only at_client can supply — so the
posture CARRIES `keyExchangeMode` and whoever builds the
`AtEnrollmentRequest` applies it, with the request's own hard `legacy`
default untouched (the at_auth major flips that, per its dartdoc).
`EnrollmentKeyExchangeMode` is re-exported show-narrowed on the at_client
barrel so the override is nameable without importing at_auth — the same
discoverability argument as `SecretSharingAlgos`.

**Deliberately NOT axes:** `allowLegacyCryptoFallback` (an app's knowing
per-app exception, meaningful in both eras — a posture flipping it would
turn an explicit opt-in into an ambient one), `keyEstablishmentAlgo` (a
deployment's choice between two live options, not an era — neither
column of the table could name a "right" value), and `seedNamespaceKeys`
(its false default guards "experimental", not "3.x"; whether the 4.0
release flips it is a separate ruling this entry deliberately does not
make).

**Acceptance Part C** (`acceptance.md` section 15, UC-C1.1–C1.6) is the
"drive the full rollout by flags" family: each axis in isolation plus the
grouped posture, all proven-in against the differential tests (the
retrofit axis live: an argless `selfRetrofit` under the postQuantum
posture resolves into the ML-DSA idempotence pool, where the migration
posture resolves RSA). The catalogue guard's `UC-[AB]` regexes widened to
`UC-[ABC]` in the same commit — both of them, doc-side and test-side.

**Housekeeping note, not a renumber:** the ledger carries TWO sections
numbered 68 (`enroll:updateMetadata`, and Workstream B(ii) approvals —
a parallel-edit interleave). Renumbering would break inbound anchors, so
this entry records the collision and leaves both standing; cite them by
title.

### 70.1 The review harvest: the posture's claims corrected, two consults get their reds (2026-08-10)

An adversarial review (4 finders → 2 refuters per finding, all in worktrees)
confirmed 7 of 15 findings against the capstone commits; the refuted 8 were
mostly the key-exchange "no apply site" family, which is the ruled
caller-composed design working as intended. What changed:

- **postQuantum()'s "Safe to adopt early" was false and is rewritten.** Under
  the posture the era default declines local and namespace-less keys, the
  fallback is legacy, and the posture's own `disallowLegacyEncryption`
  refuses it — so the SDK's internal watermarks (sync, notification) throw
  on every write, which is exactly the open R-2 decision this tree already
  records. Confirmed empirically by both refuters' probes. The dartdoc now
  states the two eyes-open consequences and cites R-2; the SHOUT recommends
  the flag alone again, not the posture; the CHANGELOG carries the caveat.
  Also false: "every 3.x client already reads all of it" — published 3.14.0
  reads none of it. The readers ship in the same release line as the
  posture, and the prose (here and on `enrollmentKeyPackageBuilder`) now
  says that instead.
- **70's "every consult is red-proofed" overclaimed by three.** The retrofit
  consult's migration direction, `selfRetrofit`'s envelopeVersion threading,
  and `pqNativeOnboard`'s posture consult all survived deletion or constant
  mutations with the whole corpus green. Now: a live argless-migration arm
  pins rsa2048 (a `mldsa65` constant lands the call in the ML-DSA
  idempotence pool — red); the live posture arm mints on its OWN fresh
  keyfile — removing the reuse ambiguity the review flagged — and asserts
  the record's frozen `keyPackage` envelope is v2 (deleting the threading
  emits v1 — red); and `makeActivationPqNative`'s version plumbing is
  unit-pinned in both directions, verified against the tagged ML-DSA _apsk
  form. **Still open, recorded rather than hidden:** `pqNativeOnboard`'s own
  posture consult is pinned at the parameter level only — observing it end
  to end needs a live postured CRAM onboard (one-shot state), which belongs
  to R-2's acceptance work.
- **crypto.dart's era dartdoc** no longer claims `readsNskeyWritesLegacy` is
  "the" era default with the edit living "here and nowhere else": the
  chooser is the client's posture at the adoption site, and moving the fleet
  default is an edit to the default posture.
- The barrel and surface-test comments no longer imply the
  `EnrollmentKeyExchangeMode` re-export makes the override *writable* from
  at_client (it makes the value readable and comparable; composition still
  goes through at_auth), and the design/plan section refs became clickable
  links per the docs convention.

## 71. Phase 5 begins: the CLI's handshake copy is deleted (2026-08-10)

**Status:** accepted and landed. `AtOnboardingServiceImpl.awaitApproval` now
delegates the approval handshake to at_auth's `waitForApproval` — the
~170-line copy (the PKAM-until-approved loop, the two `keys:get` fetches,
the AES decryption) is deleted. What the extraction surfaced, fixed on the
canonical side first:

- **at_auth could not open a legacy key record.** Its decrypt passed
  `keyResponse['iv']` into a non-nullable `generateIVFromBase64String`,
  so a record written by a legacy approver — no `iv` field, zero-IV
  encryption, exactly the case the CLI copy's own comment preserved —
  crashed with a Null type error. Red-proofed by a two-arm unit
  differential (no-iv / with-iv) before the fix; the absent field now
  selects `generateIVLegacy()`.
- **`atLookup` was an implementation-only parameter.** The `AtEnrollment`
  interface did not declare it, so a caller holding the interface type —
  the CLI does — could not pass the connection the handshake must run on.
  Hoisted to the interface, typed `AtLookUp` (the impl had over-typed it
  `AtLookupImpl`; the handshake uses only `AtLookUp` members). The
  interface/impl DEFAULT mismatch (48×1min vs 15×2s) is pre-existing and
  deliberately untouched.
- **The checkpoint strips the atSign; the delegate validates it.** The
  enrollment checkpoint deliberately omits the atSign from the persisted
  response, and `waitForApproval` refuses a response with none — so
  `awaitApproval` restores atSign and root domain from the service's own
  state before delegating, or every resumed enrollment would throw. The
  CLI's denied-resume test now runs through at_auth's REAL handshake and
  proves both the fill and the denial contract.

The CLI keeps what is genuinely its own: the proxy `from:` pre-step,
stamping `enrollmentId` on its lookup for the later re-auths, and
forwarding at_auth's progress events to its subscribers for the duration
of the call. Its unit tests that merely rode the copy now stub the
handshake at the seam; the handshake itself is live-proven where it lives
(the functional pack drives at_auth's `waitForApproval` on the real wire —
the CLI layer had no live tier before this change either).
`at_onboarding_cli`'s at_auth floor rises to `^3.4.0` in the same commit:
the delegation depends on this at_auth's null-IV fix and interface
parameter, and workspace resolution would mask a stale floor.

## 72. Phase 5: the keyfile store's double stops lying, and the lock's three races close (2026-08-10)

**Status:** accepted and landed. Two hardenings from the Phase 5 list, both
derived freshly from the code (the audit digests that named them are gone
with their session — the items were re-grounded, not taken on faith):

- **`InMemoryAtKeysIo.write` is create-only now.** The interface documents
  `write` as "create-only initial persist; implementations throw if the
  target already exists", `FileAtKeysIo` enforces it, and the in-memory
  double silently replaced — the exact second-implementation accident
  class: code correct against the double, throwing against the store.
  It now throws `AtKeysFileOverwriteException` like the file store; the
  test that pinned the wrong behaviour ("write replaces") is flipped to
  pin the contract, and the whole workspace ran green over the change —
  no double-writer existed.
- **`AtKeysFileLock`'s three raceable paths:** (i) an exclusive create
  whose token write then fails (disk full) left an empty lock the holder
  could never token-match at release — a guaranteed stall for every
  contender until staleness; now the lock is taken back down and the IO
  failure propagates instead of being retried as contention. (ii)
  `_breakStale`'s rename crashing the acquire when the corpse vanished
  between the staleness check and the rename (a release raced it); now
  it contends. (iii) `_release`'s read-then-delete could evict a LIVE
  holder that replaced a stale-broken lock between the two steps; release
  now claims by rename — the same discipline `_breakStale` already used —
  and puts a foreign lock straight back. Paths (i) and (ii) are
  fault-injection paths with no test seam; the existing lock arms (stale
  break, foreign-content release, no residue) pin the observable
  semantics and stayed green.

**Deferred, with the reason on record:** the `withExclusiveAccess<T>` seam
on `WrittenAtKeysIo`. `AtKeysFileLock` is not reentrant, so a caller
invoking `flush` inside the seam would deadlock on its own lock — the seam
needs a reentrancy design (or a lock-free inner flush contract) before it
can be offered, and it has no production consumer yet to shape it.

## 73. Phase 5: `AtEnrollmentImpl` splits into submitter, approver, handshake (2026-08-10)

**Status:** accepted and landed. The 927-line class was three jobs that
shared nothing but a progress stream, and the three are separated by
*which authority they hold*, which is why they were never one thing:

- **`EnrollmentSubmitter`** asks. Its three paths differ only in the
  authority they carry — a CRAM connection for the first enrollment, an
  OTP for a new device, an already-enrolled APKAM connection for the
  retrofit — and none of them may decide their own request.
- **`EnrollmentApprover`** decides, and issues the passcodes a request
  has to quote. `approve`/`deny`/`revoke`/`list`/`generateOtp`/`setSpp`
  are one family because they need one thing: a connection authenticated
  as an enrollment holding `__manage`. The passcode verbs sit here rather
  than with submission because an OTP is minted by the app that will
  approve and handed to the app that will request.
- **`EnrollmentHandshake`** waits out somebody else's decision. PKAM
  authentication is retried until it succeeds, which is both the approval
  signal and the earliest moment the enrollment may read anything; what
  approval released is then collected, decrypted and persisted.
- **`EnrollmentProgress`** owns the one broadcast stream. A caller listens
  to `progressStream` once, across a submission and the wait that follows
  it, so the stream has to outlive whichever collaborator is running.

The only cross-family edge is the submitter holding the approver for the
self-enrollment's best-effort `deny` cleanup — the same coupling the code
already had as a self-call, now visible.

**Defaults belong to the class that implements the published interface.**
`AtEnrollmentImpl` keeps every default (`retryInterval`, `logProgress`,
`maxRetries`, the OTP `expiry`); the collaborators take those values as
required parameters. A caller's unstated retry interval is therefore
decided in exactly one place instead of two.

**Pure motion, and checked as such:** 839 of the 850 non-blank original
lines moved verbatim. The 11 that did not are the seam and were
enumerated before the commit — per-class loggers, `_addProgress` →
`_progress.add`, `deny` → `_approver.deny`, the duplicate logger the PKAM
loop constructed locally, and the two OTP default signatures. The
`AtEnrollment` interface is untouched (seven `Mock implements` of it
across three packages make it the safe seam), `AtEnrollmentImpl` keeps
every member it implements, and the single member it loses is
`waitBriefly`, which no caller anywhere had.

**Found while mapping, NOT fixed here** (each is its own decision, and
fusing either into a motion commit would hide it):

- `waitForApproval`'s defaults differ between the interface (48 retries,
  1 minute apart, `logProgress` false) and the implementation (15
  retries, 2 seconds apart, `logProgress` true), so the polling regime a
  caller gets depends on whether it holds `AtEnrollment` or
  `AtEnrollmentImpl` — 48 minutes of patience versus 30 seconds. Legal
  Dart, silent, and it pre-dates this branch (`9e87a9a04`). Phase 6
  surface work.
- Both post-approval key fetches log their `keys:get` command at
  `shout`. Phase 7 hygiene.

Older entries in this ledger cite `at_enrollment_impl.dart` with line
numbers (§ entries at lines 1448, 1807, 2095 of this file); that code now
lives in `enrollment_submitter.dart` and `enrollment_approver.dart`.

## 74. Phase 5: enrollment material gets one filing path (2026-08-10)

**Status:** accepted and landed. Two writer sites — the first enrollment of
an onboard (`AtAuthImpl._fileFirstEnrollmentMaterial`) and the
self-enrollment retrofit (`EnrollmentSubmitter`) — each hand-built the same
`AtKeysMaterial` shapes: an APKAM keypair filed under `apkam:<enrollmentId>`
with both halves sharing one timestamp, then every material the request's
metadataBuilder minted re-tagged with the enrollment id the atServer just
assigned. Two chances to disagree about an at-rest shape that no compiler
and no test would have caught disagreeing, since each site is exercised by
its own flow.

They are now `AtKeys.fileApkamMaterial` and `AtKeys.adoptMaterials`, on the
class that already owns `addKey`/`retireKey`/`keysForEnrollment` and runs
the assurance validation. Both are red-proofed: dropping the re-tag reddens
three adoption arms, and changing the id prefix reddens the shape arm (but
not the "resolves its own signing algorithm" arm, which reads by enrollment
id — the two properties are pinned separately, as they should be).

**No interpretation moved with the plumbing.** `adoptMaterials` copies
`bytes`, `operations`, `createdAt` and `status` across untouched and changes
only whose enrollment the material belongs to. at_auth still carries key
material without understanding it; the key package's meaning stays in
at_client.

Two consequences worth recording:

- The wire pin for `apkam:<enrollmentId>` claimed "three writer sites
  today" and there were two. The comment is now a checkable claim again —
  one writer — and the pin still freezes the shape independently of it,
  because every PQ keyfile already written carries these ids.
- `onboarding_mint.dart` moved from `keys/` to `auth/` in its own commit.
  `keys/` is where material is held, persisted and serialized; minting what
  a fresh activation starts from is an onboarding step, and its only caller
  is the onboard path that sits beside `AtOnboardingRequest` in
  `auth/models/`.

## 75. Phase 5: the enrolment request's mode is a constructor, not a field (2026-08-10)

**Status:** accepted and landed (Gary's call, 2026-08-10: named constructors,
not sealed subtypes). `AtEnrollmentRequest` carried `keyExchangeMode`,
`metadataBuilder` and `apkamSymmetricKeyResolver` as three independently
settable fields, of which only some combinations are a real request — so
`EnrollmentSubmitter` refused two of them at submission time, after the
caller had already built the thing. `AtEnrollmentRequest.pq(...)` requires
the builder and the resolver; the default constructor takes no resolver and
is legacy mode. All three fields are branch-added (trunk is at_auth 3.3.0),
so nothing published moved.

One refusal survives and should: a `metadataBuilder` that returns no
`keyPackage` is a property of the builder's *output*, which no constructor
can promise. The other — a pq request with no resolver — is no longer a
reachable state, and its test is now a constructor-semantics pin rather than
a submit-time expectation.

**A claim I wrote and the code refuted:** the first cut of `.pq` required a
`session`, on the reasoning that nothing predating the session hand-off can
speak pq. Four functional tests submit a pq request with the deprecated loose
`atSign` and never wait for approval — they inspect what was advertised and
the record it produced, so they have nothing to persist and need no session.
The constructor sources the atSign exactly as the legacy one does now, and
the shared rule lives in one private helper.

**Not reshaped, deliberately:**

- `AtEnrollmentResponse` — its newer field (`apkamSymmetricKeyResolver`) is
  carried over from the request by at_auth itself, not chosen by a caller, so
  a variant would encode an invariant nobody can violate.
- `EnrollmentRequestDecision` already has the named factories this ruling
  asks for (`approved` / `approvedWithMintedKey` / `denied` / `revoked`).
  Its remaining defect needs the sealed subtypes Gary declined for now:
  `_encryptedAPKAMSymmetricKey` is `late final` and never assigned on the
  deny and revoke paths, so reading `decision.encryptedAPKAMSymmetricKey` on
  one of those throws `LateInitializationError`. Nothing reads it there
  today. A 4.0 job, recorded here so it is not rediscovered as a surprise.

## 76. The nskey advertises one KEM key, and §50's premise is a release property (2026-08-10)

**Status:** open, tracked as
[#2135](https://github.com/atsign-foundation/at_client_sdk/issues/2135) under
the [#1889](https://github.com/atsign-foundation/at_client_sdk/issues/1889)
tree. Recorded as a defect and an intent, not as a mechanism. Nothing is
built, and the shape below is where the reasoning points rather than a ruling
on how it lands.

**What [§50](#50-two-kems-by-configuration-one-construction-by-negotiation-2026-08-07)
settled, and why it held.** An nskey advertisement carries exactly one key:
`publicKey` and `alg` are both singular, and a sender gets no choice about
either — `NskeyProvider.encrypt` throws when the advertised `alg` is not the
KEM its provider handles, because encapsulating under the wrong KEM produces
a conveyance the owner could never open. §50.2 says that restricts nobody,
and gives the reason: *"every build produces and opens both, and the
recipient's advertised `alg` is what decides"*. That is exactly right, and
the single-key record is the simplest thing that works under it.

**The premise is a property of this release, not an invariant.** Both KEMs
shipped in one codebase, so today every sender does carry both. Two things
break that, and neither is exotic: a **third** KEM added later, which no
build predating it can seal to; and a consumer **pinning** an older
`at_client` than the recipient's. From that moment a recipient who rotates
to the newer algorithm stops every sender that has not shipped it, and those
senders recover only when *they* upgrade. That is worse than cold start,
which heals when the recipient acts. It is a flag day imposed on senders by
a recipient, and it is the one failure the rollout model in
[§1.8](../design.md#18-migration-rollout--the-disallowlegacyencryption-flag-d1-c--d1-d)
exists to prevent. `suites` gives agility over the construction; nothing
gives it over the KEM.

So §50 is not being overturned. What is being removed is its precondition:
that the KEM set is frozen and every client carries all of it.

**Why now.** No atSign has published an nskey advertisement, since PQ is
unreleased. Widening the record today is a shape change; later it is a
migration of live records, and the cost only grows.

**Where the reasoning points.** Mirror the key package, which faced the same
question and is the precedent worth copying:

- `keys: [{kid, alg, pub}]` on the advertisement payload, **additive at
  `v: 1`**. `publicKey` and `alg` stay populated with the entry the oldest
  readers can use, so a reader predating the field ignores `keys` and still
  works. An absent `keys` means the singleton those two fields describe, and
  that default must never grow, for the same reason `legacyNskeySuites`
  must not.
- Sender selection copies `pairwise_secret_sharing.dart` exactly: choose the
  key first by the *sender's* own preference order, then narrow the candidate
  suites to `openableSuitesFor(chosenKey.alg)` before intersecting with what
  the recipient advertised. Choosing a suite from the union across keys would
  let a sender pick the X-Wing key and an ML-KEM construction.
- `keys` is derived from what the holder **actually minted and can
  decapsulate**, never from the build's supported list. Widening a supported
  list is what made every key package claim a construction its key could not
  open, and this is the same field shape, so it is the same trap.
- Mint becomes a **union under `_nskeylock`**: add this enrollment's
  algorithm if absent, never replace the record. That also fixes an existing
  wart, since today's mint is a race whose loser silently inherits the
  winner's algorithm.

**This does not soften [§50.3](#503-the-kem-is-configured-the-construction-is-negotiated).**
The KEM stays configured and the construction stays negotiated. A recipient
still declares what it is a recipient *for*; it may now declare more than one
thing. The sender chooses among keys the recipient actually holds, by its own
fixed preference order, which is the opposite of the peer dictating the
sender's algorithm downward.

**What a set does not buy.** It does not remove the cutover. Senders choose
by their own preference order, so an atSign advertising both algorithms keeps
being sealed to under the old one until it **drops** the old entry. The set
separates "can seal with the new" from "must seal with the new", which is the
same asymmetry the provider seam gives on the data path: add, wait, drop.

**Who operates it.** The nskey belongs to the `(atSign, namespace)`, not to
an app, and several enrollments share one. An app chooses what it *adds* and
what it *prefers as a sender*. **Dropping** an algorithm is an atSign-level
decision, because dropping is the step that breaks senders, and no single app
is entitled to take it on the atSign's behalf.

**Blast radius, if built.** Everything beneath the advertisement is already
keyed by `nskeyKid` — `privateHalf(owner, ns, kid)`, the keyfile id
`nskey.<ns>.<kid>`, the secret name `__nskey.<kid>`, the conveyance's
`appMetadata.nskeyKid`, `__ckcur`, and the ring's retention of superseded
generations. Five places assume singularity: the record shape,
`NskeyKeyRing.currentPublic`, `NskeyProvider.encrypt`'s algorithm guard,
`CkManager`'s routing by `advertised.alg`, and mint/rotate. The conveyance
cost scales by the size of the set on push, pull and approve-time sharing, so
a set is a migration window rather than a permanent posture.

## 77. Phase 5: the CLI stops hand-building its keyfile (2026-08-10)

**Status:** accepted, ruled before the change (Gary, 2026-08-10). The ruling
is written first because this one moves an at-rest shape that real users
already hold.

`AtOnboardingServiceImpl` reads its keyfile through `FileAtKeysIo` — that is
what `authenticate()` has always done — and writes it by hand, assembling a
flat map, self-encrypting four values and encoding a passphrase envelope of
its own. So the CLI is the second writer of a format at_auth owns, and the
one that cannot file typed PQ material at all.

**The diff was captured, not reasoned about.** A throwaway probe wrote one
`AtKeys` both ways and compared the documents:

- The four self-encrypted legacy values (`aesPkamPublicKey`,
  `aesPkamPrivateKey`, `aesEncryptPublicKey`, `aesEncryptPrivateKey`) are
  **byte-identical** — same AES-256 under the self-encryption key, same
  legacy IV. `selfEncryptionKey`, `apkamSymmetricKey` and `enrollmentId`
  match too.
- The store adds three top-level fields: `version`, `atsign`, `keys` (an
  empty array when there is no typed material). Additive; `AtKeys.fromJson`
  accepts documents with and without them.
- The store drops one: the **atSign-keyed duplicate of the self-encryption
  key** (`"@alice": "<selfEncryptionKey>"`). It survives a read — the store
  parks unknown top-level keys in `AtKeys.metadata` and re-emits them — but
  a freshly built `AtKeys` has no metadata to emit it from. The CLI puts it
  there explicitly before writing. Nothing in this repo reads it; it is in
  every `.atKeys` file in existence, which is reason enough.
- The store reads a CLI-written file correctly, with the atSign-keyed entry
  landing in `metadata`.

**The passphrase envelope is a one-way door, and Gary took it knowingly.**
The store's v1 envelope decodes the CLI's current one (that is the
documented no-`v` legacy path), but at_chops' `AtKeysCrypto` **cannot**
decode a v1 envelope — the probe fails with `Invalid or corrupted pad
block`. So a passphrase-protected keyfile written after this change needs
at_auth 3.4.0 or newer to open, and `AtOnboardingPreference.hashingAlgoType`
becomes inert, v1 being argon2id-only. What is bought is the reason v1
exists: v1 salts per file, where the legacy derivation used the passphrase
itself as the salt, so two users who chose the same passphrase derived the
same AES key and one precomputation served both. `AtKeysCrypto` is already
`@Deprecated('This will be moved to at_auth')` — this is the move.
Passphrase files are opt-in, so the blast radius is the users who set one.

**Two mechanics worth recording:**

- `write` is create-only by contract and `flush` is never-lose, so neither
  means "replace". `allowOverwrite: true` is exactly a replace, so the CLI
  deletes the old file first — deliberately, at the caller's request, rather
  than by weakening a store verb. `allowOverwrite: false` keeps refusing.
- The APKAM private key stays out of the file in any auth mode other than
  `PkamAuthMode.keysFile`, as before: in a SIM or another secure element the
  private half is not the file's to hold.

This also retires a latent fault, stated precisely because the live version
of it is somebody else's: the hand-built map dereferences `apkamPublicKey!`,
`apkamPrivateKey!` and `defaultSelfEncryptionKey!` unconditionally. That
holds only while every enrollment mints an RSA APKAM into the flat fields and
every atSign has legacy material — true of the CLI's enrollment path today,
which is why no test caught it, and false for an ML-DSA enrollment or an
atSign minted with `mintLegacyMaterial: false`. The same assumption in its
live form did break `_persistKeysLocalSecondary`, with a null-check error
after a *successful* authentication. The store treats every one of those
fields as optional, which is the shape the keyfile actually has.

## 78. Phase 5: the keychain is reachable, flushable, and no longer closes someone else's service (2026-08-10)

**Status:** accepted (2026-08-10). Three defects, all introduced on this
branch, all found by auditing the branch's own diff against trunk in
`at_client_flutter`, and all fixed test-first — each test was run red before
the fix existed.

### 78.1 An atSign is one entry however the caller spells it

`KeychainStorage` matched a lookup against the stored label as a raw string.
The branch gave `AtKeys` a typed `atsign` field, `AtKeys.fromJson`
normalizes it through `toAtsign()`, and `_atSignOf` prefers it — so the
stored label became the *canonical* spelling while lookups still arrived in
whatever spelling the caller held.

Nothing normalizes on the way in: `AuthRequest.atSign` is a plain mutable
`String`, and at_auth hands this layer that string verbatim to `read`/`write`
while passing `toAtsign()` to `flush`, on one keyset in one flow.

Captured, not reasoned about — `write('@Alice', …)` succeeded and the very
next `read('@Alice')` threw `AtsignKey not found in keychain for atSign:
@Alice`. Trunk had no such gap: it stamped and compared the same raw string.
The sharper half is `flush`: an entry stored as `@colin.constable` (dots in
the right-hand side are decoration, so it normalizes to `@colinconstable`)
was not found by the index, so the flush **appended** — leaving the newer
keys unreachable behind the older ones, which is exactly the loss the
branch's own create-only `write` guard exists to prevent.

**Mechanism:** `KeychainStorage` compares normalized (`_normalized`), in
`_indexOf` and in `removeAtsignFromKeychain`, and keeps returning the stored
spelling. A value `toAtsign()` rejects is compared as it stands, so a
malformed entry stays readable and removable rather than becoming
unreachable. `_stampAtSign` no longer overwrites a label that is already
there (see 78.2).

### 78.2 A legacy keychain entry could never be flushed

Found by 78.1's test walking into it, then isolated with a throwaway probe
using a plain `@alice` — so it is not about spelling at all.

`AtKeysAssurance.validateMapUpdate` compares the two documents' legacy
portions. `_legacyJsonOf` strips the reserved top-level keys
(`version`/`atsign`/`keys`) from a *typed* document but not from a legacy
one, which has no reserved names. A keychain entry written by any published
`at_client_flutter` carries the owner under a top-level `atsign` — that is
where the keychain has always recorded it, predating the typed shape
reserving the name. So on the first flush the existing side offered `atsign`
as a legacy entry, the candidate's typed side had stripped it, and the
assurance refused with `map.legacy.atsign is not preserved`.

The blast radius is every device already in the field: the first flush onto
any pre-existing keychain entry — nskey filing, the signing-root store, key
package filing, the paths the branch added `flush` for — threw.

`validateMapUpdate` already carried a carve-out for this upgrade ("a legacy
-> typed-keys upgrade legitimately introduces the atsign and version"), but
only for *introducing* them; the case where the legacy side already had one
was missed.

**Mechanism:** on a legacy → typed upgrade the owner is checked against the
reserved field and taken out of the legacy comparison, because the upgrade
re-homes that value rather than dropping it. Compared normalized on both
sides, since `AtKeys.fromJson` has already normalized the reserved one. A
candidate naming a *different* atSign is still refused, and its test pins the
message path (`map.atsign`) so it cannot pass for the wrong reason. `version`
and `keys` get no such treatment: neither is re-homed, so a legacy document
carrying those names would genuinely lose them.

Note the shape — this is the reserved-name collision between two formats that
share a top level, and it was invisible because the file store never hits it:
a legacy `.atKeys` file names its atSign as *the key itself* (`"@alice":
"<selfEncryptionKey>"`, see §77), not as a literal `atsign`.

### 78.3 The list widget closed a service it did not own

The branch gave `EnrollmentRequestList` an injectable `enrollmentService`
(the seam its tests need) but left `dispose()` calling `_service.dispose()`
unconditionally. `FlutterEnrollmentService.dispose()` closes the broadcast
controller and drops it, so routing away from the widget left a caller's
shared service with every later `getEnrollments()` throwing on a null
controller.

**Mechanism:** the state records whether it made the service and closes it
only then. Pinned by `verifyNever(() => service.dispose())` after the widget
is disposed.

### What this says about the audit

All three are the same class: a *second* implementation or a *second* caller
arriving behind an existing shape, and the first one's incidental properties
quietly becoming load-bearing — the raw-string label, the legacy top level
with no reserved names, the widget as sole owner of its service. None was
reachable by reading the new code alone; each needed the diff against trunk
and a run.

## 79. Phase 6: `maxRetries` becomes a budget for the thing it is named after (2026-08-10)

**Status:** accepted (2026-08-10). Gary ruled it after the two probes below
put the actual behaviour on the record; the mechanism is named here only
because its differential is green.

### What `maxRetries` did

`EnrollmentHandshake._waitForPkamAuthSuccess` polls PKAM until the
enrollment is approved. It took a `maxRetries`, the published dartdoc said
the polling "continues until a final status is received or the maximum
number of retries is reached", and the CLI's `--max-retries` help said
"Number of times to check for approval before giving up". None of that was
true, in two separate ways, and both were captured by a throwaway probe
rather than argued from the source:

- **It never bounded the wait for approval.** With `maxRetries: 2` against an
  enrollment answering `error:AT0401`, the handshake made **21** PKAM
  attempts, returning only when the mock relented and approved. The loop is
  `while (true)`; the budget is consulted in the generic `catch` alone. That
  much is deliberate and the code says so — a decision belongs to a person,
  who takes as long as they take.
- **It counted total polls, not failures.** `retryAttempt` incremented at the
  top of every iteration and was never reset, so the budget measured how long
  the wait had been running. Five pending polls then a single network blip,
  with `maxRetries: 2`, and the blip was fatal. The practical shape: a wait is
  tolerant of connection trouble for its first `maxRetries` polls and then
  fragile to one blip, forever — the opposite of what a retry budget is for,
  and the opposite of what the code's own comment intended ("The check ...
  should only occur when the secondary server is unreachable due to network
  issues").

### The ruling

The budget counts **consecutive failures to reach the atServer**, and
nothing else. An answer from the atServer — including a refusal, which is an
answer about the enrollment — costs nothing and restores what earlier
failures spent. The unbounded wait for a pending decision stays exactly as
it was; what the budget buys is the exit from an atServer that is genuinely
gone.

**Mechanism:** `consecutiveUnreachable`, incremented only in the generic
`catch` and reset on any poll that reached the atServer. The exhaustion
count is unchanged — `maxRetries` failures are tolerated and the next one
propagates — so an atServer that is down from the first poll behaves as
before, down to the number of attempts.

**The differential** is `test/enrollment_handshake_test.dart`, three arms,
and its middle arm was run red before the fix existed: six unreachable polls
against a budget of two, spread so that no three are consecutive, must
complete. The arms on either side of it were green before the fix and stayed
green — the unbounded pending wait, and the escape hatch exhausting at
exactly three consecutive failures — so the change is pinned as narrowly as
the ruling describes it.

### Recorded, not fixed

Two findings from the same reading, both ruled out of Phase 6 and into
Phase 7 / 4.0:

- An `UnAuthenticatedException` whose message matches none of `AT0401`,
  `AT0026` or `AT0025` is swallowed and retried forever. A permanently
  wrong key polls for the life of the process.
- There is no way to stop a wait. A user who backs out of the Flutter APKAM
  dialog leaves the loop polling until the process ends; a caller can race
  it with its own timer but cannot cancel it. A deadline or a cancellation
  token is new machinery with its own design questions, so it waits.

## 80. Phase 6: one set of enrollment defaults, and the divergence that never was (2026-08-10)

**Status:** accepted (2026-08-10). Zero behaviour change; the values that
land here are the values that were already being applied.

### The recorded premise was wrong

Section 73 recorded, and the refactor plan carried, that `waitForApproval`'s
defaults diverge between the `AtEnrollment` interface (48 retries, a minute
apart, `logProgress` false) and `AtEnrollmentImpl` (15, two seconds, true),
so that "which regime a caller gets depends on the static type it holds: 48
minutes of patience or 30 seconds". The two declarations do differ. The
consequence does not follow, and it took a red proof that refused to go red
to notice: reintroducing the divergence deliberately left the pin green.

**Dart resolves a default parameter value in the method that runs, not from
the static type at the call site.** Six lines settle it — an interface
declaring `{int x = 1}`, an implementation declaring `{int x = 2}`, and an
interface-typed reference prints 2. So `AtEnrollmentImpl`'s list has always
won for every caller, including every `AtEnrollment.create()` in production,
and the interface's 48-and-a-minute was never applied to anything.

What the divergence actually was, then, is a **published interface
advertising a polling regime that nothing implements** — a documentation
defect, and one that had already misled this project's own plan.

### The ruling

The four defaults become constants on `AtEnrollment` —
`defaultRetryInterval` (2 seconds), `defaultMaxRetries` (15),
`defaultLogProgress` (true) and `defaultOtpExpiry` (5 minutes) — and both
the interface and the implementation state those constants rather than
literals. Gary chose the applied values over any adjustment once the true
baseline was on the record: at two seconds an enrollee learns of an approval
almost at once, and the alternative on the table (ten seconds, an 80% cut in
`from:`/`pkam:` round trips) traded that away for traffic nobody had
measured a problem with.

Because a default is resolved in the callee, the constants do not *enforce*
agreement — nothing can, short of the interface declining to declare
defaults at all. What they do is make the interface's documentation and the
implementation's behaviour the same edit.

### The prose that was wrong with it

- The interface dartdoc said polling "continues until a final status is
  received or the maximum number of retries is reached" and that
  `maxRetries` "specifies the maximum number of polling attempts before
  giving up". Section 79 proved both false. It now states that the wait for
  a decision is unbounded and that `maxRetries` budgets consecutive failures
  to reach the atServer.
- `AtOnboardingService.awaitApproval`'s dartdoc said an exception is thrown
  if the request "was denied, or times out". It cannot time out.
- The CLI's `--max-retries` help on the enroll path said "Number of times to
  check for approval before giving up", describing a give-up that does not
  exist. The onboard path's identically-named option is untouched: it feeds
  a `RetryOptions` on the activation check, which really is a bounded retry,
  so its help was already true.
- `AtEnrollmentImpl`'s class dartdoc claimed the class owns the published
  API's defaults. It now points at the constants.

### Pins

`test/enrollment_handshake_test.dart` pins the four constants as raw
literals — asserting them against the constants that declare them would
follow a change silently — and one behavioural arm observes the *applied*
default that has a visible effect on a single successful poll. Both were run
red: flipping `defaultLogProgress` fails the behavioural arm and the literal
pin together.

## 81. Phase 6: the key-exchange mode is wired, and there is nothing left to wire it to (2026-08-10)

**Status:** accepted (2026-08-10). Plan decision #7 — "`EnrollmentKeyExchangeMode.pq`:
wire it or ship dark" — resolves as *neither*, because the question
presupposed a wiring target that does not exist.

### What the code says

`keyExchangeMode` is declared on `AtEnrollmentRequest` alone, not on the
`EnrollmentRequest` base, and that is correct rather than an oversight: the
mode describes how an `apkamSymmetricKey` travels **from an approver to an
enrollee**, and only that request type has an approver. The other two have
nothing to exchange —

- `FirstEnrollmentRequest` is the atSign's own first enrollment, submitted
  over a CRAM-authenticated connection and auto-approved;
- `AtSelfEnrollmentRequest` is auto-approved on a connection whose APKAM
  privilege already authorizes it, and ships no `encryptedAPKAMSymmetricKey`
  at all. The client is retrofitting itself: it already holds the atSign's
  keys, mints the new material locally and files it in the same process.

The plan carried a consequence out of the capstone: *the posture carries
`keyExchangeMode` but nothing in at_client applies it, so if Phase 6 adds an
at_client-side submission entry point, that is what must consult
`preference.posture.keyExchangeMode`.* at_client has exactly one submission
entry point — `selfRetrofit`, at `src/enroll/self_retrofit.dart` — and it
submits `AtSelfEnrollmentRequest`, the type with nothing to exchange. So the
consequence has no target, and manufacturing one would mean adding an
app-enrollment entry point to at_client for no caller, which is the
mechanism-with-no-operator shape.

### The ruling

Nothing to build. pq mode is not dark: it is selectable through
`AtEnrollmentRequest.pq(...)`, which requires the two companions it cannot
work without, and it is exercised live by the functional pack's
`enrollment_pq_key_exchange_e2e_test.dart`. `ReleasePosture.keyExchangeMode`
carries the release default for the app that builds the request — `legacy`
in 3.x, `pq` under `postQuantum()` — which is exactly the Workstream A
table, and exactly what the field's own dartdoc already described.

One imprecision fixed with it: `ReleasePosture.postQuantum()`'s summary read
"enrollments exchange their symmetric key post-quantum" alongside four
things the posture really does apply by itself. It now says that this one
takes effect when the app builds its request from the value — the same
correction §70.1 made to that constructor's "safe to adopt early".

## 82. Phase 7: an approval finishes its own bookkeeping, and every decision closes its connection (2026-08-11)

**Status:** accepted (2026-08-11). Both defects predate this branch; the
at_client_flutter audit (§78) found the first, ruled it out of scope there
because it was not the branch's doing, and recorded it for closing hygiene.
The second was found by sweeping the file for the same shape and is fixed
here with it.

### The unawaited delete

`FlutterEnrollmentService.approve` ended its bookkeeping with

```dart
keychainStorage.deleteEnrollmentData(request.atSign);
```

in both arms — the success arm and the `EnrollmentConveyanceException` arm.
No `await`. The delete therefore outlives the call that started it, and the
enclosing `try` has already been left by the time it can fail, so a keychain
failure reaches no caller at all: it surfaces as an unhandled async error,
attributed to nothing, in a path whose other arm is already throwing.

The reason this survived a test that verifies the call is worth recording.
`verify(() => mockKeychainStorage.deleteEnrollmentData(atSign)).called(1)`
passes just as well unawaited — the mock records the invocation
synchronously. Only *ordering* separates the two, so the new pin makes the
stub take 20ms and sets a flag when it finishes, then asserts the flag is
set once `approve` has returned. Unfixed, that reads `false`.

### Why awaiting it is not enough on its own

Awaiting it inside the existing `try` puts a keychain failure into the
generic `catch`, which rewrites everything it sees as
`Exception('Enrollment failed: $e')`. That is a widened guard across an
operation boundary: by the time the delete runs, the atServer has recorded
the decision, so reporting the approval as failed is the exact mis-report
§78's own test file was written to prevent — the red proof produced
`Enrollment failed: Exception: keychain unavailable` after a successful
approval.

So the delete gets its own guard, `_forgetPendingRequest`, which logs at
warning and returns. What a failure costs is a pending row that lingers
until `KeychainStorage.validateEnrollment` expires it, which it does on the
next read; what it must not cost is a live enrollment reported as a failed
one.

### The leaked connections

`approve`, `deny` and `revoke` each closed the caller's `AtLookUp` on the
line *after* their `try`, so every throwing path skipped the close. 1.1.4
fixed exactly this in `enroll` by moving the close into a `finally` and said
so in its changelog; the other three kept the shape. All three now close in
a `finally`. `approve`'s conveyance arm loses its explicit close with it, so
the connection is still closed exactly once on that path — pinned, since a
double close is the obvious way to get this wrong.

The sweep matters more than the fix here: the audit recorded `approve`
because it was reading `approve`. Two siblings three lines away had the same
defect and nothing had looked.

## 83. Phase 7: one home for the shared mocks, and the four families that could not move (2026-08-11)

**Status:** accepted (2026-08-11). Relocation only: every collapse below was
verified byte-identical before the local copy was deleted, and the suite
returned the same 1183 pass / 2 skip on either side of it.

### What was actually duplicated

`test/test_utils/mocks.dart` already existed and 48 files already imported it,
which is what made the duplication invisible: **a locally declared class wins
over an imported one of the same name, silently, with nothing for the analyzer
to say.** So a file could import the shared mocks, declare its own
`MockRemoteSecondary`, and use the local one forever while reading as though it
used the shared one.

Twelve families were collapsed. Three already had a canonical version and
twelve copies between them (`MockRemoteSecondary`, `MockSecondaryAddressFinder`,
`MockAtClientManager`); eight were identical in every copy but had no canonical
home and were promoted (`FakeAtKey`, `FakeLocalLookUpVerbBuilder`,
`FakeDeleteVerbBuilder`, `FakeUpdateVerbBuilder`, `FakeAtSigningInput`,
`MockSyncService`, `MockNotificationService`, `MockEnrollmentService`). 47
declarations went; the two shared files gained none.

### The one that was not duplication at all

`MockAtLookupImpl` was declared in ten files. In **eight** of them it was
`extends Mock implements AtLookUp` — the interface, not the impl. The name had
been wrong for so long that it had been copied into every new file that needed
an `AtLookUp` mock. Meanwhile `mocks.dart` carried `MockAtLookup` for the
interface and `MockAtLookUpImpl` for the impl, so between the two spellings and
the two supertypes there were four names for two things.

There is now one name per mocked type, each matching that type's own casing:
`MockAtLookUp` for `AtLookUp`, `MockAtLookupImpl` for `AtLookupImpl`. This is a
rename rather than a pure relocation, taken deliberately — a name that says
"Impl" while mocking the interface will keep being copied, and the analyzer
verifies every site of a rename.

### The four that must stay local, and why

This is the part worth keeping, because the obvious next tidy-up would break
things:

- **`MockAtClient`** — 16 sites. The canonical one bakes in a mutable
  `AtClientPreference` via a **concrete** `getPreferences()` override. Mocktail
  cannot intercept a concrete method, so adopting it would silently disable the
  `when(() => ...getPreferences())` stubs in the thirteen files that set them.
  Collapsing it is a behaviour change wearing a relocation's clothes.
- **`MockAtClientImpl`** and **`MockLocalSecondary`** in
  `notification_service_test` — carry a keystore and several overrides the
  shared versions do not.
- **`MockSecondaryKeyStore`** in `local_secondary_test` — carries its own
  fixture keys.

The reasoning is recorded in `mocks.dart`'s own library dartdoc, not only here,
because that is where someone will be standing when they consider finishing the
job.

## 84. Phase 7: the functional pack's live tests stop claiming to be the e2e pack (2026-08-11)

**Status:** accepted (2026-08-11).

Four files in `tests/at_functional_test/test/` were named `*_e2e_test.dart`:
`enrollment_chain_link`, `enrollment_key_package`, `enrollment_pq_key_exchange`
and `nskey_data_path`. They are not in the e2e pack and never were. The suffix
named a *different package* — one with its own CI job, its own long-lived cicd
atSigns and its own initializer — so anyone reading a citation had to open the
path to find out which harness the proof actually ran in. That confusion has
already cost this project once, when a row was labelled for the e2e pack for a
month before anyone checked that the pack could not CRAM-activate anything.

The pack's other seven live tests were already `*_live_test.dart`, so this was
four outliers against an established local convention rather than a new one
being invented. They are now `enrollment_chain_link_live_test.dart`,
`enrollment_key_package_live_test.dart`,
`enrollment_pq_key_exchange_live_test.dart` and
`nskey_data_path_live_test.dart`.

### The citations rode with it

`provenIn` asserts the cited file exists and still contains the cited test
name, precisely so a rename cannot quietly strand a row's evidence. Fourteen
citations moved in the same commit: seven in the acceptance suite's `provenIn`
calls and prose, and seven across `implementation-plan.md`, `design.md` and
`acceptance.md`. The guard was confirmed to work rather than assumed — reverting
one citation turned `a3_self_data_test` red with "that file is gone", and it was
restored.

**`decisions.md` was deliberately left alone.** Two earlier rulings cite the old
filenames. Rulings are append-only: they record what was true when they were
made, and rewriting one to match a later tree turns the ledger into a moving
account of the present rather than a record of decisions. This section is the
mapping a reader needs.

The runner globs (`dart test --concurrency=1 -r expanded`), so nothing
enumerates these files by name and no harness config changed.

## 85. Phase 7: the ledger's own index, and what the citation audit measured (2026-08-11)

**Status:** accepted (2026-08-11).

### Two protocol traces stop shouting

`EnrollmentHandshake` fetched the encryption private key and the self-encryption
key after an approval, and logged each command at `shout` — the highest level
the logging package has, above `severe`. So every approval, in every
deployment, printed

```
SHOUT|...|EnrollmentHandshake|cmd: keys:get:keyName:<enrollmentId>.default_enc_private_key.__manage@<atSign>
```

unconditionally. That is a routine protocol trace wearing an emergency's
severity, and it names the enrollment id, the atSign and which private-key
record is being fetched. Both are `finer` now, which is what the rest of the
file uses for detail of this kind. The remaining `shout` calls in at_auth are
all in `registrar_service.dart` failure paths, where the level is right.

No key material was ever in these lines — only record names — so this is
noise and disclosure of structure, not a leak.

### The index caught up

The table of contents stopped at 55 while the ledger had reached 84. Thirty
rows were added, covering 56 through 84, including both sections numbered 68
(their titles differ, so their anchors differ and the duplicate number is
harmless). The numbering itself is still not renumbered: inbound anchors point
at it.

### What the audit actually measured

The audit that rides with this is worth stating as a number rather than a
claim. Across all six documents in `docs/projects/pq/`:

- **352 relative markdown links** — every one resolves, both the file and, where
  present, the heading anchor.
- **86 table-of-contents anchors** — every one resolves.
- **54 backticked repository paths** — 50 resolve; the four that do not are
  correct as written: `adr/0001-…` and `adr/0002-…` were folded into this
  document on 2026-06-30 and are cited here as history, and two
  `noports_core` paths live in another repository.

The checker was wrong twice before it was right — first assuming every path was
repo-relative, then missing `lib/src/`, each time reporting citations as broken
that were not. Both were caught by opening the "missing" files and finding them.
A citation audit whose failures are its own path assumptions measures the
checker, so the count above is the one taken after the instrument was corrected.

## 86. Phase 7: the acceptance ledger reads a declaration instead of inferring one (2026-08-11)

**Status:** accepted (2026-08-11).

The burn-down's guards worked by regex over prose and over a directory
listing. Both inferences could be fooled with nothing going red, and one of
them made the directory unable to grow a guard.

### What the row count was actually counting

A row was any `test(` in any `*_test.dart` in
`packages/at_client/test/acceptance/` except `catalogue_test.dart`. So the set
of burn-down rows was "whatever files happen to be here", and **adding any
non-scenario file to the directory silently inflated the count the README is
pinned to.** The only way to add a guard without breaking the README was not to
add one — which is a fair description of why the source-text greps had ended up
inside acceptance rows in the first place.

`manifest.dart` now declares `scenarioFiles` and `guardFiles`, the counts come
from the scenario list alone, and a `*_test.dart` in neither list fails a guard
that names both lists in its message. Proven by adding a stray file and watching
it go red.

### What "the catalogue's use cases" was actually matching

Every `UC-…`-shaped string anywhere in `acceptance.md` — definitions and
cross-references alike. Today that gives the right answer: 43 defined by a
heading, 43 mentioned, 43 with a scenario. That is luck, not construction. One
typo'd cross-reference invents a use case that can never have a scenario, and
the guard would demand one forever.

Use cases now come from headings (`### … UC-x.y — Title`, all 43 matching one
shape), and a new guard asserts every id the catalogue *mentions* is one it
*defines*. Proven by appending a reference to `UC-A9.9` and watching the guard
name it.

### The source-text greps have their own home

`architecture_guard_test.dart` holds the checks asserted against the source tree
rather than against behaviour — currently that neither `sync_service_impl` nor
`notification_service_impl` has grown a private metadata serializer again, which
is the regression that once stopped `appMetadata` reaching the atServer with no
error anywhere. It cannot be a runtime assertion: no run can observe the absence
of a rival serializer.

The reason to separate it is that it fails for a different reason from
everything around it. A rename breaks the grep while the behaviour is intact,
and when the grep lives inside an acceptance row, the suite reports that the
*scenario* failed. It did not.

**One source-text check deliberately stayed put.** `performance is measured, not
assumed` is itself a catalogue row, and its subject genuinely is the instrument
and the record — that a bench harness exists, still reports a distribution, and
that the measured budget is written down with its basis. Moving it would have
taken a real row out of the burn-down to satisfy a tidiness rule. It is a
scenario that happens to read files, not a guard that wandered into a scenario.

### Also folded

`repoRoot()` existed twice, in `catalogue_test.dart` and `proven_elsewhere.dart`,
the second carrying a comment explaining that it matched the first so the two
would behave the same. One copy now.

## 87. Phase 7: the revocation row stops tolerating what it exists to forbid (2026-08-11)

**Status:** accepted (2026-08-11). The root cause of the intermittency is NOT
established — see the end of this section. What is fixed is a test that could
not say what it had seen, and that passed on the very thing it was written to
deny.

### The atServer settles the question this row was guessing at

`nskey_rotation_live_test.dart`'s UC-A5.2/A5.3 carried a recorded explanation:
that the atServer resolves an enrollment's PKAM state through the same cache
`enroll:listns` is served from, so revocation reaches both on an eventual
schedule and a revoked keyfile authenticates for a short window afterwards.
That was inferred from this test, never confirmed on the atServer.

at_server commit `244bb6f0` (2026-08-08), "test: assert a normally-revoked
enrollment cannot APKAM authenticate", tests the same property from the other
side: enrol via OTP, approve, assert APKAM returns `data:success` **before** the
revoke, revoke **without** the force flag, then assert two attempts **on fresh
connections** both return `error:AT0027 … is revoked`. The refusal is immediate.

Two probe runs here agree — one standalone, one inside the full suite. In both,
the first poll after the revoke ACK returned
`error:AT0027:enrollment_id: … is revoked`. There is no window and nothing to
wait for.

### What the test was actually asserting

Two defects, and they compound:

- **`authenticatesAs` collapsed every failure into `false`.** A refusal for the
  revoke, a dropped socket, a signature the atServer would not verify and a
  connect timeout were the same value. The assertion therefore passed for the
  ABSENCE of the mechanism as readily as for its presence, and on the runs where
  it failed it reported a bare `true` — no atServer sentence, nothing to
  diagnose. This row's diagnosis has moved three times, and each time the
  evidence that would have settled it had been discarded here.
- **The poll tolerated ten seconds of acceptance.** It looped twenty times at
  500ms and passed as soon as any attempt stopped succeeding, so a build where
  revocation took nine seconds to bind passed silently — while nine seconds is
  precisely the lost-laptop window the row exists to deny.

### What it asserts now

The outcome is the atServer's answer rather than a boolean. An acceptance fails
**immediately**, naming it. A refusal passes only when it is `AT0027 … is
revoked`; any other refusal is retried a few times for transport noise and then
fails quoting what it kept getting. The three enrollments are asserted distinct,
a control UC-A5.1(b) already had and this row lacked.

Proven by mutation: pointing the poll at the unrevoked sibling fails on the
first attempt with `Actual: 'accepted'`.

The roster half of the test keeps its bounded poll. `enroll:listns` visibility
is a different claim from PKAM refusal, with its own recorded observation that
a read taken before the revoke populates a cache.

### What is NOT established

**The intermittency was not reproduced.** Four observations today were clean
(two ordinary runs, two probe runs), so no failing run was captured with the
instrumentation in place, and no mechanism is named here. The strictness is what
will produce one: if a revoked credential is ever accepted again, the test now
fails on the first attempt and prints the atServer's own sentence, instead of
spinning for ten seconds and reporting a boolean.

## 88. Phase 7: mintAndPublish is the cold-start mint, and stops calling itself the rotation (2026-08-11)

**Status:** accepted (2026-08-11). Closes the last open question carried out of
the refactor's decision list.

### The question, and where it actually came from

The open question was whether the live tests reaching a second nskey generation
by calling `mintAndPublish` twice should be re-expressed through the real
rotation lever, or kept as a test convenience. Reading the code first turned up
a cause neither option named: **the two dartdocs in
`published_nskey_key_ring.dart` contradicted each other.**

`mintAndPublish` said: *"Called again for the same namespace this is a
**rotation**."* Forty lines below, `rotate` said it "differs from
[mintAndPublish] in one way, and it is the way that matters" — because on a lost
mint lock `mintAndPublish` **adopts the winner's advertisement and returns
success**, so a second call can rotate nothing and report that it did. For a
cold start that is correct: the atSign has a key, which is all that was wanted.
For a rotation it is the one failure that costs exactly what the operation was
for, since rotation is the revocation lever and adopting silently leaves the
enrollment being rotated away from holding the live generation.

So the tests were not freelancing. They were following the sentence above them.
That sentence is now corrected, and `mintAndPublish` says plainly that it is the
cold-start mint and must not be used as the rotation lever.

### The scope was two sites, not the suite

`mintAndPublish` appears in sixteen test files, but almost all of them are
seeding a namespace, which is exactly what it is for. The rotation live test
already drives the real lever (`rotateNamespaceKey` → `ring.rotate`) and uses
`mintAndPublish` only to seed. Only two live sites called it twice:

- `nskey_published_ring_test.dart` — a test named *"a rotation publishes a new
  generation and keeps the old private"*, asserting rotation's whole contract
  without ever calling `rotate`.
- `pq_signing_root_create_once_test.dart` — the deliberate control for the
  create-once row, proving the published nskey record is mutable. ⚠️ **That
  file is now `pq_signing_root_mint_lock_test.dart`** (renamed 2026-08-15 by
  ruling 101 row 6, which made the root record mutable too, so the contrast
  the control drew no longer exists); the nskey row survives the rename
  unchanged.

Both now seed with `mintAndPublish` and take the second generation from
`ring.rotate`, which is the sequence production runs.

### What this does and does not buy

Honestly stated, because the distinction matters for anyone reading the tests
later: **this adds no assertion that fails today.** On the happy path the two
methods are indistinguishable, and both files passed before and after (7/7).
What changes is *which contract is under test* — a regression in `rotate` now
turns red a test that claims to be about rotation, where before it could not.
`rotate`'s distinguishing failure semantics — a lost lock and an unpublished
namespace both throwing — stay covered by unit tests, which can drive the race
that a live test cannot.

## 89. Phase 7: the section symbol keeps the two jobs it is good at (2026-08-11)

**Status:** accepted (2026-08-11).

Gary's standing preference is that a section reference reads "section N" and is
a clickable link to the heading. The pq docs used `§` 187 times, which looked
like a wholesale conflict. Counting them first showed it is not one symbol doing
one job, and the ruling follows the split rather than the total.

### What the 187 actually were

- **74 in `decisions.md`.** Rulings are append-only; their text is a record of
  what was written when it was written. Left alone.
- **68 outline labels.** `design.md`'s table of contents reads
  `**[Subsystem A — …](#1-subsystem-a-…)** (§1) — the three layers`. The `(§1)`
  is a label beside a link to that exact heading. Converting it produces a
  second, identical link touching the first. Left alone.
- **7 citations of external standards** — `SP 800-227 §4.6.2`, `§4.3`,
  `§4.6.3`, and RFC 9180 `§5.1`. That is those documents' own notation and
  there is nothing in this repository to link to. Left alone, and this is the
  class the preference was never about.
- **38 genuine internal cross-references.** These are the ones a reader wants
  to follow and could not. Converted to `[section N](target#anchor)`.

### The audit gap this turned up

Section 85 reported "352 relative markdown links — every one resolves". True,
and narrower than it sounded: that checker's pattern required a `.md` before the
`#`, so **every same-document anchor link was outside the set it examined** —
416 of them, more than the number it did check. They were verified afterwards
and all 416 resolved, so nothing was broken, but the number in section 85
described the search rather than the docs.

The check now covers both forms: **806 links, 0 broken**, after the conversion.

### Two instrument errors on the way

Recorded because the pattern is becoming familiar. A classifier reported 30 of
39 references as unresolvable — its heading-number regex did not allow the
trailing dot in `## 1. Subsystem A`, so it saw no numbered headings at all. And
the "positive control" grep written to check that claim was itself broken and
printed nothing, which briefly looked like confirmation. The conversion also ran
with a 90-character look-back that was shorter than some anchors, so one outline
label was converted into a duplicate link; a check for a converted label
adjacent to a link with the same anchor found it, and it was reverted.

## 90. Phase 7: a refusal the approval wait cannot resolve stops being silent (2026-08-11)

**Status:** accepted (2026-08-11). This was the last genuinely open item on the
refactor plan; it had been recorded as "Phase 7 / 4.0" and the choice between
the two was never made. Ruled Phase 7, because the defect is a missing branch
rather than the sealed-subtype machinery 4.0 carries.

### The missing else

`EnrollmentHandshake`'s approval poll handles a refusal by matching codes:

- `AT0401` / `AT0026` — not yet decided. Keep waiting, indefinitely and by
  design, because the decision is a person's.
- `AT0025` — denied. Throw.

There was no third branch. An `UnAuthenticatedException` matching none of the
three left the `catch` having done **nothing at all**: not logged, not thrown,
and not counted, since the atServer had been reached so the unreachable budget
reset. The loop then polled every `retryInterval` for the life of the process,
in silence.

The case that makes this concrete is an enrollment **revoked while its own
approval wait is running**, which answers `error:AT0027 … is revoked`. Nothing
about that resolves by waiting. A key the atServer will not verify lands here
too.

### What it does now

Such a refusal is logged at `warning` naming the atServer's message, tolerated
for a short unbroken run in case it is transient, and once that run exceeds
`maxRetries` it ends the wait with an `AtEnrollmentException` carrying the
message. It gets its own counter rather than sharing the unreachable one:
reaching the atServer and understanding what it said are different questions,
and section 79 defined that budget as being for the first only. A pending answer
resets it, so an isolated oddity between ordinary polls costs nothing.

Two arms, both proven. The failing one is red without the fix for the reason
that matters: the wait **completes normally** after nine `AT0027` refusals,
`emitted <null>` where an exception was expected — the defect exactly. The
control arm, a refusal surrounded by pending answers still reaching approval,
is green on both sides.

### Why it was still open

Worth recording, because the mechanism that lost it is ordinary. The item was
written down accurately, tagged with two possible homes, and then quoted in
every later summary in its tagged form — including by me, hours before this,
while listing what Phase 7 contained. A label naming two options reads as
decided to everyone who passes it, because the decision looks like it happened
somewhere else. Nothing catches that except re-reading the source list, which is
how this surfaced: Gary asked whether the plan was complete, and the answer from
memory was wrong.

## 91. Signature agility: the APKAM auth key stops being the enrollment's signing key (2026-08-11)

**Status:** accepted as a design ruling. Nothing is built; this section is the
specification the work is written against, and the mechanism is named here
because no defect is being fixed — this reverses a scope decision, the same way
[section 68](#68-the-enrollment-record-stops-being-a-one-way-door-enrollupdatemetadata-2026-08-10)
did.

Settled by interview on 2026-08-11 against `gkc-pq-d1-spike` at `ee7f85b7a`.

### 91.1 What is wrong today

The APKAM keypair does two jobs. It authenticates a connection (PKAM), and it
signs everything an enrollment attests to — signed envelopes, key packages,
chain links. `ApkamSigning.signingKeys` (`apkam_signing.dart:56`) reads the one
PKAM keypair out of `atChops` and hands it to both.

*This describes the tree on 2026-08-11 and no longer describes it: on
2026-08-13 `signingKeys` became a `Future<List<ApkamSigningKeys>>` sourced from
`AtKeys.signingKeysFor`, one entry per algorithm. It still answers with the
authentication keypair where an enrollment holds no signing material — which
is every keyfile until something files some — so the first cost below is the
one that has moved and the third is unchanged in practice.*

Three costs follow, and all three are present in the tree:

1. **No agility.** `_apsk` is published as a bare public-key string with no
   algorithm beside it, so a verifier infers the algorithm from the envelope
   rather than from what the enrollment advertised. Adding a second algorithm
   has nowhere to go.
2. **It is written once, ever.** `publishPublicSigningKey`
   (`apkam_signing.dart:29`) reads the record first and logs "have already
   published" if it exists. A rotated key would never reach the atServer.
   *Fixed 2026-08-13 by [14.18](../implementation-plan.md#1418-the-remaining-d1-initial-development-sequence)
   step 13: it compares what is published against what the client holds and
   republishes on a difference, still writing nothing when the two agree.*
3. **Key reuse across protocols.** An authentication signature proves liveness
   on a connection; an envelope signature is a durable attestation. One key
   serving both is a cross-protocol surface with no reason to exist.

### 91.2 What is not changing

The 1:1:1 cardinality and singular `metadata.keyPackage` from
[section 12](#12-advertised-recipient-keys-are-signed-against-_apsk-2026-07-02)
stand, as does everything in section 68 other than its ruling 1. Rulings 2
through 7 of section 68 carry into `enroll:update` unchanged, and ruling 6 (a
superseded kpid is not retired) is the same shape as ruling 9 below.

### 91.3 The rulings

| #  | Ruling |
|----|--------|
| 1  | **The APKAM authentication key authenticates and nothing else.** An enrollment's signing keys are separate material from the start, with their own lifecycle |
| 2  | **`AtKeys` gains `privateAuthentication` / `publicAuthentication`** as `CryptographicKeyType` tokens. Role is what that enum is for, and it is what `validateAddKey` and `validateKeyMaterials` group on, so the uniqueness rules come from machinery that already exists |
| 3  | **keyIds are `apkam:<enrollmentId>:<n>` for authentication and `sign:<enrollmentId>:<algo>:<n>` for signing.** **A keyfile is retrofitted once**, so retrofit idempotency is no longer per algorithm: a request naming a *different* algorithm than the enrollment already held **throws**, because quietly returning an `mldsa65` enrollment to a caller that asked for `rsa2048` would have it believe it holds a mode it does not. A re-run naming the *same* algorithm still reuses — `selfRetrofit` documents itself as idempotent and recovers a failed signing-root step by running again, so that arm must not throw. *Added 2026-08-11 during implementation, on Gary's ruling that there is never a second retrofit; the code previously scoped idempotency per algorithm precisely to allow one.* The auth counter keeps retired generations distinguishable; algorithm leads the signing shape because that is what a verifier selects on. The generation-less `apkam:<enrollmentId>` needs no read compatibility — `fileApkamMaterial` is not on trunk, so no released build has ever written one |
| 4  | **The assurance invariants count only `active` material, and uniqueness is per `(enrollment, role, algorithm)`.** At most one active `privateAuthentication` **file-wide** — not per algorithm, since one live enrollment per install is the model — and at most one active `privateSigning` per algorithm, which is what lets an enrollment hold the whole signing array at once. *Amended 2026-08-11 during implementation: this ruling first said one active material per `(enrollment, keyPartType)`, which contradicted ruling 16 — every signing key shares the `privateSigning` role, so that rule permitted exactly one signing algorithm. Caught by a test asserting several active signing keys are fine, not by review.* Today they are status-blind, so retiring a key does not free its slot — confirmed by probe: retire `gen1`, add `gen2` under the same enrollment, and `addKey` throws while the same add under a different enrollment is allowed |
| 5  | **"Which enrollment do I authenticate as" is derived, never stored.** It is the enrollment id of the unique active `privateAuthentication` material. No `activeEnrollmentId` field is added: a pointer duplicating a fact already in the file is a second writer waiting to disagree with the first |
| 6  | **`AtKeys.replaceKey(keyId, newMaterial)`** performs retire-and-add in one call. Leaving callers to sequence two mutations across a keyfile flush is how one generation goes missing. *⚠️ Signature updated by [99](#99-the-keyfile-groups-by-enrollment-and-the-atsigns-own-keys-move-out-2026-08-14) row A1: it is now `replaceKey(enrollmentId, keyId, replacements)`, because identity became `(enrollment, keyId)`. The ruling — one call, never two — is unchanged.* |
| 7  | **All key material becomes typed.** The flat `apkamPublicKey`/`apkamPrivateKey` stay as a compatibility projection, read in exactly one place. `rsa2048` exists only as a retrofit's legacy APKAM keypair. *Amended 2026-08-13 during implementation: this ruling first said the flat fields become a **write-only** projection over the typed materials, "never read as the source of truth", and the projection cannot be materialised — two probes refused it. Filing a projected material makes `toJson` emit `version`/`atsign`/`keys`, because its guard is `keys.isEmpty` and both stores stamp `atsign` first (`file_io.dart:113`, `keychain_io_impl.dart:89`), which breaks the byte-identical legacy round-trip [§91.4](#914-what-is-released-and-therefore-what-must-still-be-read) promises; and on a retrofitted keyfile the one-active-`privateAuthentication`-per-document rule in `assurance.dart` refuses the add outright. There is also nothing to project from on four shipping shapes — a keyfile written before the typed section existed, an `rsa2048` first onboard, an OTP enrollment, and an onboard handed its keys by the caller. So "never read" narrows to "read in one place": `AtKeys.authenticationFor` / `authenticationAlgorithmFor` is the single resolver every caller goes through, typed material winning wherever the keyfile holds it for that enrollment and the flat fields answering only where it holds none.* |
| 8  | **`_apsk` becomes `{"v":1,"keys":[{"use","alg","pub","status"}]}`,** reusing `PackageKey`'s vocabulary so the design has one spelling for "a list of keys with algorithms". `status` is `active` or `verifyOnly`; absent reads as `active`. Written by the atServer verbatim from `EnrollParams.apsk`, at approval and on `enroll:update` — one writer for the record's whole life, which makes a rotation atomic from the client's view |
| 9  | **The array is append-mostly.** An algorithm leaving the in-use set stops signing; its key and its published entry are retained indefinitely as `verifyOnly`. Key packages and chain links are stored durably, so withdrawing an entry retroactively unverifies everything ever signed with it |
| 10 | ⚠️ **SUPERSEDED 2026-08-14 by [98](#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14) ruling 2 — the auth key is never retained in `_apsk`.** What it said, and why it stood until then, is kept below because the reasoning is still correct *given its premise*: the premise was that the auth key had signed durable envelopes worth verifying. gkc ruled 2026-08-14 that **no long-lived signatures exist**, so it protects nothing; and under 98 an enrollment holds a signing key from birth, so its auth key never signs at all. ~~**The APKAM auth key is in the array permanently, as `verifyOnly`.** Everything signed before rollout 2 was signed by it; the array replacing the bare-string record would otherwise unverify all of it.~~ This is ruling 9 applied at the rollout boundary rather than at an algorithm retirement. *Amended 2026-08-13 during implementation: as written this ruling could not do its job, because the reader took **one key per algorithm** — `ParsedApsk.keyFor` was `where(alg).firstOrNull` and `verifyEnvelope` checked that one. Retaining the auth key works only where its algorithm differs from the minted key's, which is the **legacy** enrollment. A post-quantum-native enrollment holds an ML-DSA auth key and mints an ML-DSA signing key, so both entries name `mldsa65`, the active one is found first, and every envelope signed before the split fails to verify — the exact outcome this ruling exists to prevent, in what will be the ordinary 4.0 case. The reader now resolves the algorithm first and tries **every** key advertised under it, refusing only when none verifies. That is not the fallback ruling 11 forbids: 11 is about dropping to a weaker algorithm after a failure, and the algorithm here is already fixed by the strongest-shared rule, with every key tried one this signer published under it.* |
| 11 | **A signer emits one signature per active signing key it holds.** A verifier picks the strongest algorithm it understands from those present, verifies that one, and **refuses outright** on failure — never falling back to a weaker signature, which would be a downgrade attack with an attacker-chosen algorithm |
| 12 | **The envelope collapses to one versioned shape,** `{"v":1,"signatures":[{"alg","sig"}],"enrollmentId":…}`. The entries use `alg` to match the `_apsk` array's spelling, so one vocabulary covers both halves of a verification — the algorithm named in the signature against the algorithm named in the published entry. `signedEnvelopeVersion = 1` (tagged) and `jwsEnvelopeVersion = 2` (JWS) are both unreleased and are removed rather than carried. **Superseded 2026-08-12 by [95](#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12) ruling 1** — "removed rather than carried" stands; the replacement is RFC 7515 general serialization rather than this bespoke container, which was chosen when the standards argument had only been weighed against the *flattened* JWS shape |
| 13 | **Section 68's `enroll:updateMetadata` is renamed `enroll:update`** and widened to reach `apkamPublicKey`, `signingAlgo`, `apsk` and `metadata`. Nothing is built, so the wire token is still free and never will be again; a name saying "metadata" while reaching `apkamPublicKey` generates wrong assumptions for years. **`namespaces` and the approval state stay out of reach permanently** — the operation is self-only, so reaching namespaces would let an enrollment grant itself scope |
| 14 | **`EnrollParams.apkamPublicKeySignature`** carries a signature by the **new** private key over `enrollmentId\|apkamPublicKey\|signingAlgo`, verified against the new public key in the same request. Without it a compromised-but-authenticated client can install a public key whose private half it does not hold, locking out the legitimate holder while the record looks valid. No nonce: the operation is self-only and the old key stops authenticating after the rotation, so a replay can only be sent by the current holder — section 68 ruling 2's own argument that rollback is self-harm rather than an attack. **The signature is `AtSigningMode.pkam` with `HashingAlgoType.sha256`**, not `AtSigningMode.data`: `data` mode signs with the *encryption* keypair, so it cannot express possession of an APKAM signing key at all, and `pkam` is the mode PKAM verification already uses, so both sides frame the bytes identically. Learned from a red test rather than from reading — the first implementation chose `data` and failed with "Encryption keypair required for signing" |
| 15 | **The strength order is an explicit ordered list beside `SigningAlgoType` in at_chops** — `mldsa65` > `ecc_secp256r1` > `rsa2048` — pinned by a raw-literal tripwire test in the style of `KeyAlgorithmType`'s. *Amended 2026-08-13 during implementation: the order shipped **total**, over all five members — `mldsa65` > `rsa4096` > `ed25519` > `ecc_secp256r1` > `rsa2048` — because a partial order leaves the choice undefined for exactly the pair nobody thought about, and the tripwire fails on a new member left unplaced.* It is a protocol fact every implementation must agree on. The **verifiable** set is derived from what the at_chops build implements, so a build cannot claim an algorithm it cannot run |
| 16 | **The in-use-for-signing set is app-settable on `AtClientPreference`, defaulted by `ReleasePosture`,** and SDK releases move that default. When the in-use set names an algorithm the enrollment holds no key for, the client mints one locally at start, files it and publishes it — which a signing keypair can do precisely because it needs no server approval, unlike the auth key. *Four things this ruling left open were settled on gkc's ruling 2026-08-13, when `AtClientPreference.inUseSigningAlgorithms` landed. **The defaults are `{}` in 3.x and `{mldsa65}` in 4.0.** Empty in 3.x because an enrollment holding a signing key of its own holds **two** keys — that one and the APKAM authentication key, which ruling 10 keeps published for as long as the envelopes it signed must verify — and two keys cannot be advertised as the bare public-key string every deployed reader understands, so a non-empty 3.x default would publish an array at clients whose peers refuse it. ⚠️ **That clause was overtaken 2026-08-14 by [98](#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14) ruling 2**: the auth key is no longer retained, so an enrollment holding one signing key advertises **one** entry, not two. The `{}` 3.x default outlives the reason given for it — 98 ruling 6 sets the stage defaults to `{}` / `{rsa2048}` / `{mldsa65}`, and what keeps rollout 1's single entry deployed-readable is that the entry is `rsa2048` and active, which is the bare form. ML-DSA **alone** in 4.0, with no RSA beside it: ruling 11 has the verifier take the strongest algorithm the envelope and the advertisement share, so a second, weaker signature is only ever the one passed over — it would cost a key, an advertisement entry and a signature per envelope to be ignored, and what keeps older envelopes verifiable is ruling 10's retained auth key rather than a weaker key in this set. ⚠️ **Also overtaken by [98](#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14) ruling 2**: nothing retains the auth key now. What keeps an older envelope verifiable is the **retired signing key** that signed it, which stays advertised under 98 exactly as ruling 9 always required — the ML-DSA-alone conclusion is unchanged, only the mechanism named for it. **A `Set`, not a list**, because membership is the whole meaning: signatures are emitted in the strongest-first order the keyfile is read in, never in the preference's order. **Final at construction and unmodifiable**, like `disallowLegacyEncryption` and for the same reason — and unmodifiable specifically because a caller retaining the set it passed could otherwise add to it after the check. **An algorithm this build cannot sign an envelope under is refused at construction** (`ArgumentError`), not skipped: skipping quietly leaves an app that asked for a post-quantum signature believing it has one while every signature it produced was classical, which is ruling 15's "a build cannot claim an algorithm it cannot run" from the app's side.* *A fifth thing was settled when the minting landed: **the client publishes the advertisement BEFORE filing the key**, which is the reverse of the nskey rule and the reverse of the obvious order. Filing first makes the client sign under a key its `_apsk` does not name, and since envelopes are stored durably and verified on every read, each one written before the publish lands is unverifiable for good — with nothing to retry it, because the next start finds the key held and mints nothing. Publishing first leaves an advertised key nobody holds, which nothing signs with and which disappears at the next publish, the advertisement being composed from what the keyfile holds. `NskeyPrivateFiling.store` files before publishing for the mirror-image reason: an encapsulation key published without its private has senders sealing data nobody can open.* |
| 17 | **The rollout position is a named axis, `SigningRollout` (`now` / `rollout1` / `rollout2`),** on `ReleasePosture.signingRollout` and overridable per `AtClientPreference`. *Ruled by gkc 2026-08-13 and built the same day, after the alternative — folding the axis away — was put and declined. The finding that prompted the question stands and is recorded here because it shapes what the axis is: the three rollout-2 writer behaviours are inseparable **by construction**, not by three flags agreeing. Only minting is a decision; the array form and the multi-signature envelope are consequences of the enrollment holding a second key. So the axis names a position and supplies the default for the one piece of state all three read (ruling 16's set) — and `ReleasePosture` **derives** that set from the stage rather than storing both, since two stored fields are two controls over one behaviour and the day they disagree one is a lie with no way to tell which. Where an app names both explicitly the **set** is what the client obeys, which is the same contract every other axis has. ~~`rollout1` writes exactly what `now` writes, deliberately: the reader half needs no gate, so what that value carries is the fleet's position — the peers have upgraded — which no client can observe for itself.~~ ⚠️ **That clause was REVERSED 2026-08-14 by [98](#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14) and built out the same day (rows B1 and B3): rollout 1 authenticates with ML-DSA-65 and advertises a fresh RSA-2048 signing key of its own, so it writes something `now` does not.** What survives is the *reason* the advertisement stays readable — a single active `rsa2048` entry is still the bare string — and the fleet-position point, which is why the stage is an operator's value rather than one the SDK derives. It is reachable only through the preference, because there are two postures and no general constructor, and an unreachable enum value would be a rollout position nothing could ever be in.* |

**Renamed 2026-08-12:** the `status` value spelled `verifyOnly` in rulings 8, 9
and 10 above is **`retired`** — use-neutral, because `use` already names the
operation and the same value has to serve encapsulation keys
([95](#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12)
ruling 6). Nothing composes an `apsk` yet, so no record carries either
spelling.

### 91.4 What is released, and therefore what must still be read

Checked against pub.dev rather than in-tree precedent, because the answer
changed two rulings:

| Surface | Released | Consequence |
|---------|----------|-------------|
| Bare-string `_apsk` | **Yes** — `mixins/apkam_signing.dart` ships in at_client **3.13.0** | Read as legacy, never emitted again |
| Unversioned envelope | **No** — `lib/src/signing/` ships in no release; at_client 3.14.0, the latest on pub.dev, has no such directory and no `parseApskValue` | Nothing to honour on read; the shape is deleted rather than versioned ([95](#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12) ruling 3) |
| Versioned typed-keys document; `flush` upgrading a legacy file in place | **Yes** — at_auth **3.3.0**, 10 days ago | `version: 1` keyfiles with an empty `keys` array exist in the wild and must be read |
| `apkam:<enrollmentId>` keyIds | **No** — `fileApkamMaterial` is not on trunk | No read compatibility (ruling 3) |
| Tagged single-key `_apsk`, `signedEnvelopeVersion`, `jwsEnvelopeVersion` | **No** — all D1-only | Removed, not versioned (rulings 8, 12) |

**Settled, and not to be re-opened: the secret-sharing substrate is
`@experimental`, so it is free to change outright.** Yes, at_client **3.14.0 is
published on pub.dev and is not retracted**, and it ships `lib/src/secret_sharing/`
and `lib/src/mixins/` — 9 of those 12 files carry the marker, which is precisely
the mechanism that makes them changeable. Nobody has built on them; they are the
first early iteration of the design this project has been re-deriving for three
months. **Publication status is therefore immaterial to what we may change**,
and a check against pub.dev is not a reason to revisit this. Recorded this
plainly because the opposite conclusion has been re-derived from pub.dev more
than once, each time costing a round of re-litigating a settled licence.

The genuinely frozen surfaces are the two below that say **Yes** *and* predate
the PQ work: the bare-string `_apsk`, and the typed-keys document at_auth 3.3.0
shipped. Those are honoured on read. Everything else in this table is ours.

`toJson()` stops emitting `version: 1` for a keyfile holding no typed material,
so a legacy file round-trips byte-identically through a new build. A
v1-with-empty-keys file carries nothing a legacy file does not, so writing it
back as legacy loses nothing and stops the marker spreading to files nobody
meant to change.

### 91.5 Rollout

**Rollout 1 is capability only.** Readers accept the new `_apsk` array and the
new envelope; key packages are published. Nothing is minted, signed or
published differently — envelopes keep being signed by the auth key and
verified against the bare-string record, and no separate signing keys are
minted yet. Every verifier in the fleet gains the ability to read what rollout
2 will emit, before anything emits it.

**Rollout 2 is active,** gated by a single new `ReleasePosture` axis switching
all three writer behaviours together: mint separate signing keys, publish the
array, emit multi-signature envelopes. One flag rather than three, because a
build doing any one without the others emits something the fleet cannot
handle.

Auth-key rotation lands in this work as a coordinated sweep across at_commons,
the atServer and the client, and becomes usable once the atServer carries
`enroll:update`.

The decision surface is `--posture` on `at_activate`, alongside the existing
`--signingAlgoType`, with the specific flag winning — the resolution rule
`at_client_preference.dart:52` already documents. There is no "app" in the CLI
case: the carriers that tell at_auth what to do are at_onboarding_cli /
at_cli_commons and at_client_flutter.

### 91.6 Delivery

Everything is built on `gkc-pq-d1-spike` so it can be proven end to end
locally. **The spike never merges**; it is broken into stacked PRs afterwards.

1. at_commons `EnrollParams` extension, on `gkc-apsk-auto-publish`. PR to
   trunk, published.
2. The spike merges the **published** at_commons rather than the branch, which
   is also what proves the spike builds against what consumers will resolve.
3. at_server's own `gkc-apsk-auto-publish` resumes against that published
   at_commons.
4. `at_virtual_env:local` is rebuilt from it, giving the harness something to
   run against.
5. The atServer PR goes for publication in parallel.

The Dart atServer carries the verb now; every other atServer implementation is
a tracked parity follow-up with its own issue, so it cannot silently diverge.

## 92. The spike takes trunk, and two published version numbers move underneath it (2026-08-11)

`gkc-pq-d1-spike` merged `origin/trunk` (87 commits, merge `95584f818`) once
at_commons 5.14.0 published. Four rulings came out of doing it.

**1. The version collision is silent, so it is checked first.** trunk published
`at_chops 3.5.0` and `at_commons 5.14.0` the same day. The spike had been
claiming *both of those numbers* for entirely different, unreleased content —
KE-1's seed API and `Metadata.copy()`. Because both sides wrote the same
`version:` string, `pubspec.yaml` **auto-merged with no conflict at all**;
only the CHANGELOGs raised a marker. Nothing in git's output says a published
number has been attached to unreleased work.

The spike's content moved to **at_chops 3.6.0** and **at_commons 5.15.0**, with
at_client's floors following, and each published heading kept what actually
shipped. The standing rule this adds: **before merging trunk here, diff every
touched package's `version:` line against pub.dev.** A merge that reports no
conflict has not told you the version line is right.

The sharpest consequence is for anyone reading the plan: "at_chops 3.5.0 is
unpublished" was true for weeks and is now false in the most misleading
possible way — 3.5.0 is live, and it does not contain KE-1.

**2. Validation follows the work, not the file.** Both semantic conflicts had
one shape: trunk added length checks to method bodies the spike had already
refactored out from under it. Taking either side alone loses something real,
and neither loss shows up as a conflict.

- **ML-KEM** — trunk validated inside `MlKem768PureDartAlgo`; the spike had
  moved the implementation to a level-parameterised `MlKemPureDart` base. The
  checks went into the base, expressed against abstract per-level size getters.
  Pasting 768's constants into a base that also serves ML-KEM-1024 would have
  rejected every well-formed 1024 key — the enum-widening trap in size form.
- **ML-DSA-65** — trunk validated inside the async `signBytes`/`verifyBytes`;
  the spike had made those thin wrappers over sync statics that the PKAM
  dispatch and envelope signing call directly. The checks went into the
  **sync** statics, because validating the wrapper would have guarded only the
  callers that were never the risk.

**3. Widening an enum reddens pins in files the change never touched.** trunk
arrived with a new `at_auth/test/atkey_material_test.dart` pinning both
`KeyAlgorithmType.known` and `CryptographicKeyType.known` *exactly*, and the
spike had widened both (`mlkem1024`, `privateAuthentication`,
`publicAuthentication`). Git merged that file cleanly and it failed only on a
test run. The pin now carries the three tokens; that edit is the review.

**4. Two red tests predated the merge, and saying so required running both
arms.** `at_client`'s `signing_algo_resolution_test.dart` and
`at_onboarding_cli`'s `keyfile_literal_pins_test.dart` were red after the
merge. Both were re-run at the pre-merge head in a throwaway worktree and
failed **identically**, so neither was merge-caused. Both were stale tests
rather than product defects: the first built its fixture from `privateSigning`,
which predates [91](#91-signature-agility-the-apkam-auth-key-stops-being-the-enrollments-signing-key-2026-08-11)'s
auth/signing split, so `signingAlgorithmForEnrollment` correctly found no
authentication material; the second still expected `version`/`atsign`/`keys`
from a keyset with no typed material, guarding an at_auth behaviour from one
package away — which is why nothing went red where that change landed.

They were also invisible in the previous status line, which reported
`at_onboarding_cli` as *analyze* clean and said nothing about `at_client`'s unit
suite. **A rails claim names its rail**: analyze and test are different
assertions, and the shorter one reads as the stronger.

## 93. The D1 remaining-work sequence, and the rollout axis becomes real (2026-08-11)

A walk through every remaining D1 item, ruling each. Recorded because the
sequence itself is a decision — several of these were ordered wrongly, and one
was carried as an open server defect it had already been proven not to be.

**1. `now|rollout1|rollout2` is ONE NEW AXIS on `ReleasePosture`,** alongside
the five [70](#70-workstream-a-capstone-releaseposture-the-five-flags-as-one-value-2026-08-10)
established. Not a harness-only construct and not a fourth dimension.

The consequence worth stating separately: **[14.13](implementation-plan.md#1413-a-passive-by-default-flag-surveyed-not-built)'s
passive-by-default IS what `now` means.** That entry stops being a separate
item and becomes the definition of the axis's first position — a client at
`now` reads and routes post-quantum records and never writes one on its own
initiative, which is exactly the passive default 14.13 asked for. One axis
position, not two flags that have to agree.

**2. A reader that understands no entry in an `_apsk` array refuses outright.**
No downgrade, no fallback to a derivable legacy key. Consistent with
[91](#91-signature-agility-the-apkam-auth-key-stops-being-the-enrollments-signing-key-2026-08-11)'s
refusal rule: the point of publishing an array is that a reader picks the
strongest it understands, and a reader that understands none of them has no
business guessing.

**3. The sender/receiver pair exercises the whole story, not the shapes.** Its
scope is: the signed-envelope exchange; a real notification and data path;
**multiple puts and gets**, not a single notification; and enrollment followed
by an `enroll:update` APKAM rotation mid-run, so the record-authoritative path
is proven to survive a rotation in every posture.

**4. A fourth arm runs the last PUBLISHED at_client, and it closes the known
limit.** [`acceptance.md` 16.1](../acceptance.md#161-the-harness) recorded that one
build simulating `now` exercises the stage logic rather than cross-version
compatibility, and that running the published client is "the version of this
that would test that, and it is not what is built here." It is now in scope, so
**the matrix is 4×4, not 3×3.**

The reason this matters more than an extra row: without it, "`now` behaves
identically to current legacy" is a claim about code we wrote, checked against
other code we wrote. The published arm is the only thing that measures it. It
is the same lesson as a differential test having to prove its two arms differ —
here the two arms are two *builds*, and simulating both in one build proves
nothing about the one we did not write.

**5. [14.9](implementation-plan.md#149-a-revoked-enrollment-can-still-authenticate-briefly)
is CLOSED — a test-instrument failure, proven, not an atServer defect.** The
record had softened only as far as "the attribution was never established,
OPEN, not a known server defect." That understates it: the instrument was the
cause. The test discarded the revoke ACK and left the revoked client running
through the poll; both were fixed and the suite went green. Carrying it as an
open unknown invited someone to go looking for a server bug that is not there.

> **OVERTURNED 2026-08-12 — the server bug was there, and this ruling told
> people not to look for it.** `EnrollmentManager` invalidated its read-through
> `atDataCache` **before** writing the record: `remove(ek)` →
> `await movePerEnrollmentData(...)` (a whole-keystore walk, many suspension
> points) → `await keyStore.put(...)`. Any other connection reaching
> `getEnrollmentByFullKey` inside that window missed, read the **pre-revoke**
> record and re-cached `approved` permanently, because nothing invalidated
> after the write — and that cache is what
> `PkamVerbHandler.verifyEnrollmentIsActive` reads. Fixed in at_server
> `16dd457f`: mutate first, invalidate second, with no `await` between the
> write landing and the eviction. 12 of 12 clean full-suite runs after, against
> 5 failures in 13 before — a rate, not a proof of kind.
>
> **Why the conclusion did not follow from its evidence.** The test it rested
> on is serial — one client, no competing reader — so it never opens the
> window, and a passing serial test cannot exclude a concurrency race. The
> harness faults it found were real and worth fixing; fixing an instrument does
> not establish that the instrument was the cause. The tell was in the data and
> was read as noise: the row failed only inside the **full suite**, never
> standalone. "Passes alone, fails in the suite" was attributed to leftover
> state; it was concurrency, which is the other thing that phrase means.
>
> The ruling is kept above verbatim as the record of what was believed. Its
> closing sentence is the part worth remembering: a wrongly closed ruling does
> not merely record the wrong answer, it withdraws the question.
>
> ⚠️ **This amendment is three days late.** The root cause was established
> 2026-08-12 and reached
> [14.9](implementation-plan.md#149-a-revoked-enrollment-can-still-authenticate-briefly),
> but no ruling here was amended, so the ledger asserted the opposite of a
> measured fix until 2026-08-15. A root cause that lands in the plan and not in
> the ledger leaves the ledger arguing against it.

**6. D1 initial development ends when the PRs are carved and merged** — not at
a green matrix, and not at R-2. Publishing (at_chops 3.6.0 → at_commons 5.15.0
→ at_auth 3.4.0 → at_client) and the 4.0.0 posture flip are the release
programme that follows it. **The spike branch still never merges**; everything
in it reaches trunk as stacked PRs.

**7. Everything open is in D1.** No deferrals: 14.7, 14.8, 14.11, 14.12, 14.14
and 14.16's four residuals are all in scope, as are S-3's completion, B-3
(#2128), KF-1 (#2129), IS-1, and merging at_lookup 3.6.1 (PR #2127).

> **Amended 2026-08-13.** The ruling stands; one of its items was already done
> when it was written down and stayed on the list. **at_lookup 3.6.1 needs no
> merging** — PR #2127 merged 2026-08-08 and 3.6.1 is published on pub.dev.
> The rest of the item list is unchanged.

> **Amended again 2026-08-15 — the enumeration, re-derived.** The principle
> stands; its list of backlog items was a snapshot of 2026-08-11 and stopped
> tracking the backlog that day. Reading each subsection's own state marker
> gives **thirteen** live items where this ruling names six: 14.6 (both halves
> of `enroll:update` are built; what is owed is a caller that re-advertises a
> key package), 14.7, 14.8, 14.11, 14.12, 14.14, 14.15, 14.16, 14.17, 14.18,
> 14.19, 14.20 and 14.21. Eight are closed — 14.1, 14.2, 14.3, 14.4, 14.5, 14.9
> with 14.9a, 14.10 and 14.13. The split and its re-derivation date now live at
> the head of
> [`implementation-plan.md` §14](implementation-plan.md#14-backlog--carried-items-with-no-owning-project),
> which is the copy to read; repeating it here is what produced two stale lists.
>
> ⚠️ **One item is deliberately outside this ruling's scope claim.** 14.21 (the
> signing root cannot be rotated) was raised 2026-08-15, after "everything open
> is in D1" was written, and its own entry does **not** claim D1 — only its
> obstacle 2 carries a release-ordering argument, and that is an argument, not a
> ruling. Whether the no-deferrals principle extends to it is unruled.

The ordered sequence these rulings produce is
[14.18](../implementation-plan.md#1418-the-remaining-d1-initial-development-sequence).

## 94. Three records advertise keys, and only one of them speaks the vocabulary (2026-08-11)

**In brief:** *sub-ruling 4 amended 2026-08-12: the licence is `@experimental`, not a version baseline*

From a question about whether the enrollment key package and the nskey
advertisement publish the same structure. They do not, and the difference is
not principled — it is two designs that grew a month apart and never met.

**1. There are three of these, not two.** All three are an APKAM-signed
envelope wrapping a list of keys with algorithms:

| Record | Entries today |
|--------|---------------|
| `public:_apsk.<enrollmentId>.a.__e@<atSign>` | `{use, alg, pub, status}` |
| `metadata.keyPackage` (a field *inside* the enrollment record) | `{kid, use, alg, pub}` |
| `public:__nskey.<ns>@<owner>` | flat `{nskeyKid, publicKey, alg}` — no list |

> ⚠️ **Corrected 2026-08-13, while implementing ruling 2.** Two of those three
> rows were wrong when written. `apskAdvertisement`
> (`at_auth/lib/src/enroll/apsk_advertisement.dart`) composes
> `{kid, use, alg, pub}` — **no `status`** — and **no record carried `status`
> at all**, so ruling 2's `status?` was introducing a field rather than
> adopting one. The nskey row omitted `suites`, which it did carry. The table
> was read as an observation and was a description; the codecs were one grep
> away. See also ruling 2's own amendment below.

`EnrollParams.apsk`'s own dartdoc says its entries are "spelled as
`KeyPackage`'s keys are so that one vocabulary covers every 'list of keys with
algorithms' in the protocol". That ruling already exists and already has two
adopters. **The nskey advertisement is the sole outlier**, which makes this a
question about why one record opted out rather than whether two can converge.

**2. One key-entry vocabulary — `{use, alg, pub, kid, status?}` inside
`{v, keys:[…], suites}`.** The nskey advertisement converges onto it:
`nskeyKid` becomes the entry's `kid`, `publicKey` becomes `pub`, `alg` stays,
and the advertisement gains a `keys` list. The list is a capability rather
than ceremony — an atSign cannot advertise both X-Wing and ML-KEM for a
namespace today, because the advertisement holds exactly one key by
construction.

> **LANDED 2026-08-13**, in `6462ae786`, `d28ef48a9` and `69449603e`, and it
> did not land as written. Four amendments:
>
> - **`status` is not part of it.** Nothing carried one (see the table
>   correction above) and `KeyEntryStatus` did not exist, so shipping the field
>   here would have put a value on the wire that no writer sets. Gary's call:
>   it belongs entirely to ruling 95.6–9's retired-key path. The vocabulary as
>   landed is `{use, alg, pub, kid}`.
> - **The container is `{v, createdAt, keys:[…], suites}`** — `createdAt` was
>   added for symmetry with `KeyPackage`, which requires one. `v` stays **1**:
>   nothing is released, so no advertisement in the old shape exists anywhere
>   for a version 2 to distinguish this from.
> - **"One vocabulary" cannot mean one Dart type** *for the entry*. at_client
>   depends on at_auth, so at_auth cannot reach `PackageKey` and `_apsk` keeps
>   its own `ApskSigningKey`. It is one **wire spelling** across two types, by
>   construction; only the kid derivation is genuinely shared, and ruling 3
>   already unified that.
>
>   ⚠️ **Narrowed 2026-08-13.** True of the entry *class*, and it was applied
>   too widely: it says a shared type is impossible, when what is impossible is
>   sharing one that lives in at_client. at_auth is the **lower** package, so a
>   type placed *there* is reachable by both — which is exactly where
>   `publicKeyKid` already sits, cited two lines above as the thing that IS
>   shared. `KeyEntryStatus` was landed in at_client on 2026-08-13 under this
>   reasoning and moved to at_auth the same day, so `status` is now one type as
>   well as one spelling. `PackageKey` itself could follow if a second reason
>   ever appears; nothing needs it today. **The lesson is the direction:** ask
>   whether a type can move DOWN before concluding it cannot be shared.
> - **The reader had to grow before the writer.** `nskeyKid`, `publicKey` and
>   `alg` survive as getters reading the strongest usable entry rather than
>   `keys.single`, and `verify` skips entries whose algorithm this build has no
>   KEM for. Without both, the first advertisement carrying two keys would have
>   thrown, so the capability could never have been switched on.
>
> Found en route and fixed in `d28ef48a9`: `ApkamSignedAdvertisedKeys.verify`
> checked that the kid was the digest of the key it carried but never the
> key's **length**. A kid is the digest of whatever bytes are present, so a
> forged advertisement carries a matching one for free; the wrong-length key
> reached `pqSeal`, and the first sign of trouble was inside the KEM one seal
> later. `SecretSharingAlgos.publicKeyLengthFor` now answers from each KEM's
> own constant — `AtKemAlgorithm` deliberately keeps lengths off itself, so
> putting one there would be another breaking at_chops change.

**3. One kid function, over the raw key bytes.** `nskeyKidOf` is right;
`PackageKey.computeKid` hashes the base64 **text** of the key rather than the
key, which was an accident and not a decision. Two ids that both mean "SHA-256
prefix of a public key" are either the same function or one of them is a trap
for whoever assumes they are.

**4. Nothing is released, so this is an edit and not a migration.** No
both-spellings reader, no kid-preimage migration, no keyfile re-key, no
TTL-drain window for in-flight envelopes. The absent-field hatches go with it:
`published_nskey_key_ring.dart`'s three (`v`, `alg` and `suites` each treated
as "the pre-<date> shape") and `KeyPackage.fromPayload`'s one, along with the
two constants that name what those absences meant — `KeyPackage.legacySuites`
and `legacyNskeySuites`, identical values in different files. Every one of them
defends against a predecessor that never shipped. `v`, `alg` and `suites`
become required.

The exception, and it is a real one: the **bare-string** `_apsk` spelling *is*
released — at_client 3.13.0's `apkam_signing.dart` publishes and fetches one.
It predates this work and keeps its compatibility path.

**Amended 2026-08-12 — the licence is `@experimental`, not a version
baseline.** This amendment first read "the baseline is at_client 3.13.0, which
contains no `secret_sharing/` directory". That framing is what keeps inviting a
pub.dev check, and the check keeps coming back the other way: **3.14.0 is
published, is not retracted, and does ship `secret_sharing/`** — every file of
it marked `@experimental`, unused by anyone, and therefore free to change. The
sub-ruling holds for both records on the marker, which is the durable reason.
The released-surface table is
[§91.4](#914-what-is-released-and-therefore-what-must-still-be-read).

**5. The suite-negotiation loop is written twice and becomes one function.**
`KeyPackage.bestSuiteFor` plus `sendEnvelope`'s narrowing, versus
`NskeyCryptoProvider._sealVersionFor`: the same walk of the sender's
KEM-narrowed openable list against the recipient's declared `suites`, picking
the first in common.

**6. The seal/open helper takes `info` as a parameter, and the two values stay
different.** `at_client/secret_sharing/v1` versus
`at/nskey/…:<owner>:<namespace>`. Domain separation is what stops an envelope
from one substrate being replayed into the other, so a *shared* `info` would be
the one bug this consolidation could plausibly introduce. Shared code, distinct
binding.

**LANDED 2026-08-12, and the ruling's premise was half wrong in two ways worth
recording.**

*First, the exposure predated the consolidation.* This ruling reads as "be
careful not to introduce a shared binding". The pairwise substrate had **no
test that could fail on one already**: `wire_literal_pins_test.dart`'s
`expect(utf8.decode(sealInfo), 'at_client/secret_sharing/v1')` compares a
constant against its own expected text and never touches a ciphertext, and
every other pairwise test seals and opens through the same production path —
symmetric in `info` by construction, so green under *any* shared value.
Measured: dropping the label from the pairwise seal, the pairwise open and the
enrollment open, leaving the constant itself untouched, left the whole suite
green at **1180/1180**. The nskey substrate was covered; pairwise and
enrollment were not. So the differential came **first**, as its own commit, and
that same symmetric mutation now turns exactly one test red. A mutation that
moves only the seal is not the proof — it goes red through every ordinary
round-trip test and so discriminates nothing.

*Second, `required` at the at_client layer would not have been enough.*
at_chops declared `Uint8List? info` and coalesced `info ?? Uint8List(0)`, so
omitting the argument derived the **same key schedule as passing an empty
one** — two callers that each said nothing shared a binding, silently. A
helper requiring `info` from its callers still passed it on across that
boundary, where dropping one argument compiled clean. Closed by making
at_chops' `pqSeal`/`pqOpen` require `info` as well (at_chops 3.6.0,
`breaking:`), which turns a shared binding into a **compile error** rather
than a convention. Every in-tree caller already supplied one, so no behaviour
and no wire byte changed. The pins also exercise **0x02**, the version
production negotiates, rather than 0x01 — the two take structurally different
key-schedule paths, so a differential written at 0x01 pins the branch nothing
emits.

Landed as `a8db79bcc` (the differential), `26705b6a0` (at_chops) and
`7b1488a48` (`pq_envelope.dart`, five call sites routed through it).

**7. The carriers stay different, and that is correct.** `SecretEnvelope`'s
JSON carries `from.kpid` because the recipient must be able to seal a reply
back to the sender; an nskey conveyance carries its routing in `appMetadata`
and its sender is the record's own owner. What converges is the
**advertisement**, not the transport.

**8. It lands before the `_apsk` array parser, or it is rework.**
[14.18](../implementation-plan.md#1418-the-remaining-d1-initial-development-sequence)'s
stage 1 opens with that parser; written bespoke it becomes the third
hand-rolled codec for one shape, and the consolidation then has to unpick
freshly written code. It becomes the new step 3 and the sequence renumbers to
32 steps.

**9. Three dartdocs still assert the write-once premise `enroll:update`
removed, and one of them is holding a rollout decision.**
`key_package.dart:198`, `enrollment_key_package.dart:53` and `:60`, and
`envelope_signing.dart:48`. The last is the stated reason the JWS envelope
shape is a 4.0 default: "the enrollment record's `keyPackage` is write-once —
an envelope frozen there in a shape the fleet cannot read is unreadable for
that enrollment's life." With
[91](#91-signature-agility-the-apkam-auth-key-stops-being-the-enrollments-signing-key-2026-08-11)'s
`enroll:update` reaching `metadata`, that reads "unreadable until the
enrollment republishes". The fleet-readiness argument survives on its own
merits — a reader that cannot parse still cannot parse — but its **severity**
drops from unrecoverable to recoverable, and that is an input to when the
default flips. Re-decided on the facts rather than inherited.

## 95. The envelope keeps one shape, and a retained key says so (2026-08-12)

**In brief:** *rulings 2 and 3 amended 2026-08-14: a published envelope reader does exist, and reachability rather than absence carries the decision*

Two items [94](#94-three-records-advertise-keys-and-only-one-of-them-speaks-the-vocabulary-2026-08-11)
left open, ruled together because both turn on the same premise: **the baseline
is at_client 3.13.0**, which ships no `secret_sharing/` and no envelope code at
all.

### The envelope

**1. One envelope shape, and it is RFC 7515 general serialization.**
`{payload, signatures:[{protected, signature}]}`, one entry per active signing
key, each `protected` header carrying `{alg, kid, v}` — `kid` being the signing
enrollment id. (⚠️ **`typ` joined them 2026-08-15**,
[ruling 103](#103-an-envelope-says-what-it-is-for-and-a-verifier-says-what-it-wants-2026-08-15);
this paragraph records what 95 ruled, so it is annotated rather than rewritten.) Everything else goes: `signedEnvelopeVersion` (the tagged v1
shape), `jwsEnvelopeVersion` (RFC 7515 **Flattened**), `envelopeVersionOf`'s
dispatch, the `wrapperFields` ternary in `ApkamSignedAdvertisedKeys.verify`, and
`envelopeVersion` as a `ReleasePosture` axis.

**This supersedes [91](#91-signature-agility-the-apkam-auth-key-stops-being-the-enrollments-signing-key-2026-08-11)
ruling 12**, which collapsed the envelope to a bespoke
`{"v":1,"signatures":[{"alg","sig"}],"enrollmentId":…}`. Ruling 12 was right
that both existing shapes are removed rather than carried; it chose a
hand-rolled multi-signature container at a moment when the standards argument
had only ever been weighed against the *flattened* JWS shape, not against the
multi-signature one. Weighed directly, the bespoke container has no advantage
left: it is the same structure without the citation.

The move is small because the flattened arm already does the work —
`_signJwsEnvelope` maps `RS256`/ML-DSA-65 (RFC 9964), emits unpadded base64url,
and builds a `protected` header with `alg`/`kid`/`v` over the signing input
`protected || '.' || payload`. General serialization is that entry wrapped in a
`signatures` array.

Two fields from ruling 12's shape disappear rather than move: top-level `v` and
`enrollmentId` are already `v` and `kid` **inside** `protected`, where the
signature covers them. `_verifyJws` already prefers the signed copy — "the
signed claim is the one that" — so this makes the existing preference the only
option instead of a tie-break.

**2. Nothing gates it, and each reason that once did was eliminated
separately.**

| Reason | Killed by |
|--------|-----------|
| The enrollment record's `keyPackage` is write-once, so a bad envelope is frozen for that enrollment's life | `enroll:update` reaches `metadata` ([91](#91-signature-agility-the-apkam-auth-key-stops-being-the-enrollments-signing-key-2026-08-11) ruling 13) |
| A published reader crashes on a null cast rather than refusing | ~~nothing released reads an envelope — see ruling 3~~ **NOT killed** — amended 2026-08-14, see ruling 3. A published reader exists and the crash is real; what carries the decision is who can reach it, not that nobody reads |
| Recovery needs an `enroll:update` no client sends yet | only bites if a bad envelope can exist, and none can when one shape is the only shape |

**3. Nothing released reads or writes an envelope.** ⚠️ **This was wrong, and
is amended in place 2026-08-14** — the ruling stands, its stated evidence does
not. What it said: "No release ships `lib/src/signing/` — at_client **3.14.0**,
the latest on pub.dev, has no such directory, and `wrapAndSign` /
`verifyEnvelope` / `parseApskValue` appear nowhere in it. The released thing in
this area is the **bare-string `_apsk`**, from `mixins/apkam_signing.dart`, and
that is a *record* rather than an envelope. So there is no legacy envelope to
honour on read, which is why ruling 1 deletes rather than versions."

Two of those are true and one is not. 3.14.0 ships no `lib/src/signing/`, and
`verifyEnvelope` (the free function) and `parseApskValue` are genuinely absent.
But **`wrapAndSign` and `verifyEnvelopeSignature` are both in 3.14.0**, in
`lib/src/mixins/envelope_signing.dart`, and `secret_sharing/pairwise_secret_sharing.dart`
calls each of them. The released envelope is a flat
`{payload, signature, hashingAlgo, signingAlgo, enrollmentId}` map. So there
*is* a legacy envelope, and ruling 1 deletes rather than versions it knowingly.

Measured 2026-08-14 by cross-feeding each build's shape to the other's reader:
this tree → 3.14.0 gives `_TypeError: type 'Null' is not a subtype of type
'String' in type cast` — the null-cast crash the table above claimed could not
happen — and 3.14.0 → this tree gives `AtSigningVerificationException: an
envelope must carry its payload as a string`. Neither direction works, under
every stage, because the envelope stopped being a posture axis at ruling 1.

**What carries the decision now is reachability, not absence.** The released
reader is same-atSign only — both call sites pass
`signerAtSign: getCurrentAtSign()` — and hangs off
`AtClientSecretSharing.forClient`, which nothing inside at_client 3.14.0
constructs, which is `@experimental`, and whose dartdoc opens "⚠ Not yet
suitable for production secrets". 3.14.0's `AtClientImpl.start()` is a two-line
no-op, so nothing post-quantum starts there by itself. The exposed consumer is
an app that reached for an API documenting itself as unusable for the purpose.

gkc ruled 2026-08-14: **accept the break, pin both errors, do not restore an
envelope axis and do not teach this tree's reader the released shape.** The
matrix in [`acceptance.md` 16.5](../acceptance.md#165-the-rollout-matrix) is
corrected accordingly — it becomes a data-path matrix, with the envelope
exchange a `now`/`rollout1`/`rollout2` question.

The lesson is the one [§14.19.1](../implementation-plan.md#14191-things-that-look-like-defects-and-are-not)
keeps relearning from the other side: this claim was checked by grepping the
released tree for `lib/src/signing/`, which is where *this* tree keeps the
code. The released build kept it somewhere else. A search for the directory
answered a question about the directory, and got read as an answer about the
capability. (The rest of what 3.14.0 ships in this area — `secret_sharing/`,
the signing mixins — is `@experimental` and free to change; see
[§91.4](#914-what-is-released-and-therefore-what-must-still-be-read).)

**4. The reversibility hatch is spent, not lost.** `nskeyAdvertisementVersion`'s
doc calls the version field "the hatch that makes moving the envelope to JWS
reversible". That hatch protected *already-written* records; there are none, so
reversibility before GA is editing a constant. The payload `v` on the
advertisement stays — it versions the payload, not the wrapper.

**5. NoPorts is unaffected and stays out of scope.** It produces the same
`{payload, signature, hashingAlgo, signingAlgo}` shape from its own copy in
`noports_core`, signs with the encryption keypair and fetches `getRemotePK`
rather than `_apsk`, so it consumes nothing this deletes — as
[14.7](../implementation-plan.md#147-noports-carries-its-own-copy-of-the-envelope-shape)
already established. The atServer is unaffected for a different reason: it
stores `metadata` and `apsk` verbatim and has no opinion on either.

### The retained key

**6. `status` is `{active, retired}`, use-neutral, and `retired` replaces the
documented `verifyOnly`.** `EnrollParams.apsk`'s dartdoc specifies
`status: "verifyOnly"`, which names the wrong operation for a decapsulation key.
The `use` field already says which operation a key is for, so one neutral value
covers both: **retained, not for new operations**. For `use: "sign"` that means
old signatures still verify; for `use: "enc"`, records already sealed to it
still open. Absent still reads as `active`. The dartdoc is unbuilt and the
atServer stores the value verbatim, so nothing on the wire has committed to
`verifyOnly`.

**7. `retired` is meaningful for KEM entries in the key package, and
`enroll:update` is what created the need.** Before it, an enrollment's enc key
never changed and the state could not arise. Now it can, and the gap is
concrete: `sendEnvelope` puts `<kpid>` in the envelope's key name, `_consume`
skips any envelope whose `toKpid` or `kid` is not the current `kpid`, and
`envelopeTtl` is seven days — so rotating an enc key silently strands a week of
in-flight envelopes. Advertising both keys, new `active` and old `retired`,
makes that rotation non-lossy.

**8. It is NOT emitted on the nskey advertisement.** Rotation there already
expresses the same state by overwriting the record while retaining privates
filed per `nskeyKid`. A sender must never encapsulate to a superseded
generation, so listing one buys nothing and adds a key that must be trusted to
be ignored — in the one record whose entire audience is senders acting
immediately. The writer omits the field; the reader tolerates it.

**9. Building it fully reaches past the codec, and the plural key holding is
the part that matters.** Four consequences, all owed in the same step:

- `bestKeyFor` returns the first algorithm match regardless of status, so it
  must skip `retired` entries;
- `kpid` is `bestKeyFor(...)?.kid`, so it becomes *the active enc key's* kid,
  with a defined outcome when a package advertises more than one — the
  ambiguity `PairwiseSecretSharing._isSelf`'s doc already warns about;
- `_consume`'s two equality checks become "is one of the keys I hold";
- **`KeyPackageRegistration` holds one `_encSeed`/`_encSecretKey` and
  `PersistedApkamKeys` persists one `encSeed` + `keyAlgo`; both become plural.**
  `PersistedApkamKeys` is the shape apps construct in their own
  `loadApkamKeys`/`saveApkamKeys` callbacks, so this is an app-facing contract
  change — free on the 3.13.0 baseline, and the reason this is a change to the
  substrate rather than to a codec.

Without the last one the field is decorative: senders would correctly avoid the
retired key, and the receiver still could not open anything sealed to it.

### Rulings 6–9 landed 2026-08-13

Three commits: `6a5eac838` (the vocabulary gains `status`), `f956b2146` (the
plural holding), `f6fc3796e` (answering at every held address). Rails: at_client
1210/1210, functional pack against `at_virtual_env:local`. Five things differ
from the rulings as written.

**A fifth consequence was missing from ruling 9, and it is the one that makes
the other four reachable.** The **sweep filter** watches one address. An
envelope sealed to a superseded key is never scanned for, so `_consume` never
sees it and the widened equality checks never run — the same "decorative"
failure the ruling warns about for the plural holding, one layer out.
`EnvelopeAddressing` gained `regexForAny`/`sweepRegexForAny`, and the sweep, the
wake-up subscription and the sync listener all cover every held address.

**The keyfile already records the status, which ruling 9 did not know.**
`AtKeysMaterial` carries a `KeyPartStatus` of `active`/`retired`/`dead`,
`AtKeys.retireKey` is how a rotation records the transition, and
`AtKeysAssurance` enforces at most one **active** `publicEncapsulation` material
per (enrollment, algorithm) — the same invariant `_activeEncKey` needs, already
enforced one layer down. The first implementation derived the status from
`createdAt` instead and was corrected when the assurance rule refused the test
fixture. `dead` material is not adopted at all: retirement is as close to
deletion as a keyfile gets and dead is the end of that road.

**An unrecognised `status` reads as `retired`, not as `active`.** Ruling 6 fixes
absent and the two known values and says nothing about a third. A value written
by a newer client says something narrower than "offered for new operations", so
reading it as active is the one answer that can make a build use a key its owner
has withdrawn.

**`status` is emitted only when a key is retired.** Absent already reads as
active, so emitting the default would change the bytes of every advertisement in
the protocol to state what their silence states — and would make ruling 8's "the
writer omits the field" a special case rather than the ordinary behaviour.

**Nothing rotates yet.** Rulings 6–9 build the holding and the receive path a
rotation will need; the rotation itself is step 16's `enroll:update` caller. The
reader shipping first is the same ordering the multi-key advertisement reader
took in ruling 2, and for the same reason.

Recorded and *not* done, with the reason: a guard for an envelope whose suite
and whose named key belong to different KEMs — newly possible now that a client
can hold keys under more than one. It was written, and removing it turned
nothing red. at_chops maps the wrong-length secret key to a `PqOpenException`
that the open already catches and skips, and the message names the mismatch
("ML-KEM-1024 secret key must be 3168 bytes: 32"). A check that changes no
outcome and reads like a security check it is not. Belongs beside
[14.19.1](../implementation-plan.md#14191-things-that-look-like-defects-and-are-not).

## 96. The programme pair gets a home outside the workspace (2026-08-14)

Steps 20–22 of [`implementation-plan.md` 14.18](../implementation-plan.md#1418-the-remaining-d1-initial-development-sequence)
specify a sender and a receiver taking `--stage published|now|rollout1|rollout2`,
plus a driver running the matrix. [`acceptance.md` 16.1](../acceptance.md#161-the-harness)
says what the pair must exercise and says the `published` arm runs the last
released at_client. It does not say where any of it lives, and that turned out
to be the thing blocking the first line of code rather than a detail to settle
while writing it. Two facts, verified before asking:

- **There is no home to extend.** No `bin/` anywhere in the workspace holds
  anything resembling the pair, and `--stage` matches nothing under `packages/`
  or `tests/`. Wholly greenfield.
- **The `published` arm cannot live in the workspace.** `packages/at_client` is
  a member of the root `pubspec.yaml` `workspace:` list, so every workspace
  member resolves at_client by path. A package inside the workspace cannot
  depend on the hosted 3.14.0 at all.

gkc ruled all three, 2026-08-14.

**1. `tests/pq_matrix/`, three standalone packages, driver in the existing
functional pack.** `scenario/` holds the exchange, `current/` and `published/`
hold a `bin/sender.dart` and `bin/receiver.dart` each, and none of the three is
listed in the root `workspace:`. The driver is an ordinary test file in
`tests/at_functional_test`, so `runLocal.sh` stays the one entry point and the
matrix recycles the virtualenv exactly as every other live row does.

Nesting a standalone package inside this repo is established rather than novel:
`packages/at_client/example` is one already — no `resolution: workspace`, its
own `pubspec.lock` and `.dart_tool` — and it sits *inside* a workspace member.

**2. The published arm pins 3.14.0 exactly, with its lockfile committed.** A
plain hosted `at_client: 3.14.0`, no `dependency_overrides`, and
`pubspec.lock` in git so the control arm resolves the same transitive set on
every machine and every run. The alternatives were a package generated into a
temp directory at run time — nothing committed, resolution free to drift
between runs, so a changed result could not be attributed — and a git worktree
of the `v3.14.0` tag, which proves what the tag contains rather than what
pub.dev ships. A `dependency_overrides` bodge to reach a hosted version from
inside the workspace is the documented way to break resolution silently, and is
not on the table.

**3. One shared scenario library; only client construction differs per arm.**
The exchange is written once, against the API surface both versions have, and
each arm supplies nothing but its own preference construction — `current/`
naming a `SigningRollout`, `published/` unable to name one because 3.14.0 has
no such type. Resolution reaches the shared package transitively, so `current/`
compiles it against the workspace at_client and `published/` against hosted
3.14.0, from one source file.

That is what makes a divergence attributable. Two hand-written programs differ
for two possible reasons — at_client changed, or the programs did — and the
matrix cannot tell them apart. The rejected middle option was two mirrored
copies with a test diffing them, where the guard is the part that rots: it
passes for as long as both copies drift the same way, which is exactly what a
shared scenario makes impossible rather than merely detectable.

**What this cost on day one, and why it is recorded here.** The pair's first
finding contradicted the document specifying it — see
[95](#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12)
rulings 2 and 3, amended the same day. The published arm's value is not that it
runs old code; it is that questions about a released build stop being answered
from memory of what was in it.

## 97. A keyfile status a build has never seen is read, not refused (2026-08-14)

Settling [14.19 item 11](../implementation-plan.md#1419-small-items-raised-2026-08-12-and-not-yet-acted-on)
— where a rotated APKAM keypair is persisted — needed a way to mark a keypair
as *staged*: filed, but not yet the one that authenticates. gkc ruled the
**two-phase** shape, staged then promoted on the atServer's acceptance. That
needs a new status value, and asking for one exposed why none could be added.

**1. `KeyPartStatus` becomes an open `String`, and `AtKeysMaterial.status` with
it.** `AtKeysMaterial`'s two neighbouring fields, `keyAlgorithmType` and
`keyPartType`, are open Strings, and `keyAlgorithmType`'s dartdoc states the
rule for the whole document: *"a reader must accept — and round-trip unmodified
on flush — values it does not recognise, so a keyfile written by a newer client
stays readable and losslessly flushable by an older one."* `status` was an
`enum` parsed through a throwing `expectEnum`, so it was the one field that
made that sentence false.

The cost was not theoretical. **at_auth 3.3.0 is on pub.dev and ships the same
three-value enum**, so a keyfile carrying a fourth value is refused *in its
entirety* by every released build — not the entry, the whole document, and the
document is the user's key material. Any new status was a breaking at-rest
change, permanently.

⚠️ **A skip would have been worse than a refusal.** The first design was "skip
entries whose status is unknown". `AtKeys.toJson` re-encodes from the parsed
materials, so a skipped entry is *dropped on the next flush*: silently
destroying key material rather than merely failing to read it. Tolerance on the
read is only half the promise, and it is the dangerous half on its own.

**2. The forward order becomes a stated ranking.** `retireKey` and the
assurance rule both enforced "status only moves forward" with `status.index`,
which an open String does not have — so this was never a mechanical type swap,
and the audit is what caught it. `KeyPartStatus.rankOf` states the order
instead. That is the better position regardless: reordering the enum's
declarations used to silently redefine every transition check in the package.

**3. An unrecognised status has no rank, and that gap is deliberate.** A build
cannot know whether a token it has never seen sits before or after `retired`,
so it is never selected as active, and any transition involving one is refused
rather than assigned a direction. Guessing "newest is furthest forward" would
let a future value silently reactivate a key its owner withdrew. The assurance
rule takes the strictest reading available for the same pair: where either side
is unknown it cannot ask "did this move backward", so it requires the value to
be *unchanged*, which is exactly the round-trip promise.

**4. This is the reader half, and it ships alone.** gkc chose reader-first over
accepting the break or overloading `dead`. So `pending` is **not** added here
and the rotation arm is still unbuilt: a writer may emit a new status only once
a build carrying this reader is what the fleet is running. What landed is the
tolerance and its ranking, nothing that uses them.

The consumer sweep found this is source-breaking for nobody: no sibling repo
under `~/dev/atsign` and no package in `~/.pub-cache` references
`KeyPartStatus` outside at_auth itself. ⚠️ It is still a **published-surface
break** — at_auth joins at_chops in owing a major-version decision
([92](#92-the-spike-takes-trunk-and-two-published-version-numbers-move-underneath-it-2026-08-11));
the bump is not taken here.

## 98. Rollout 1 moves the authentication key, not the signing key (2026-08-14)

**In brief:** *supersedes [91.3](#913-the-rulings) ruling 10; the auth key is never retained in `_apsk`*

Ruled by gkc over a fourteen-question walk, prompted by generating a keyfile's
evolution through the stages and finding that the stages as built did not say
what they were for. (The generator that produced those keyfiles lived in
`untracked/scratchpad/atkeys_structure/`, which is **machine-local and not in a
fresh clone** — nothing below depends on it. The shapes this ruling and
[99](#99-the-keyfile-groups-by-enrollment-and-the-atsigns-own-keys-move-out-2026-08-14)
specify are tracked, as `keyfile-target-rollout1.json` and
`keyfile-target-rollout2.json` beside this file.)

**The insight the whole section rests on: the two keys have different
audiences.** Only the **atServer** verifies the APKAM authentication key, and
it is the operator's own infrastructure. **Every peer** verifies the signing
key, and the fleet is not the operator's to upgrade. So the authentication key
can go post-quantum immediately while the signing key must stay classical until
readers move — which is the reverse of what the stages did, and it is the whole
point of having separated the two keys in the first place.

### 98.1 The stages

| | auth key | signing key | `_apsk` published |
|---|---|---|---|
| `now` | `rsa2048` | none — the auth key signs by fallback | bare RSA (**the auth key**) |
| `rollout1` | **`mldsa65`** | **`rsa2048`**, minted at enrollment-request time | bare RSA (**the signing key**) |
| `rollout2` | `mldsa65` | `mldsa65` active, `rsa2048` retired | the array |

**1. Rollout 1 mints an ML-DSA-65 authentication keypair and a fresh RSA-2048
signing keypair.** The quantum-forgeable credential moves first. An APKAM
public key sits on the enrollment record where anyone can harvest it, so an
adversary who breaks RSA later can forge authentication for any enrollment that
never moved — and unlike encryption there is no "harvest now" caveat to argue
about, the exposure is simply the key's published lifetime. Meanwhile the
signing key stays RSA because `apskValueOf` emits the deployed-readable bare
string only for a single active `rsa2048` entry, and every un-upgraded peer
parses `_apsk` by base64-decoding it as an RSA key.

⚠️ **This reverses `SigningRollout.rollout1`'s "deliberately identical to
[now] in what this client writes".** That sentence, and UC-G1.14's
byte-identity claim, are both false under this ruling and are rewritten with
it.

### 98.2 What `_apsk` advertises

**2. `_apsk` advertises the keys that currently sign, plus signing keys that
have been retired. The authentication key is advertised only while it *is* the
signer, and is never retained after.**

- At `now` the enrollment holds no signing key, `signingKeys` falls back to the
  auth key, and that key signs everything — so advertising it is advertising
  the signer, not making an exception.
- At `rollout1` and beyond the enrollment holds a signing key from birth, so
  the auth key never signs and never appears.
- A **signing** key whose algorithm leaves the in-use set is retained as
  `retired`, because it signed durable envelopes — [91.3](#913-the-rulings)
  ruling 9, preserved.

The asymmetry is principled rather than convenient: a key is retained because
of **what it signed**, and an auth key under this design signs nothing that
outlives the transition. [91.3](#913-the-rulings) ruling 10 is superseded and
amended in place.

⚠️ **The deletion rests on a premise gkc supplied and this project has not
measured: there are no long-lived signatures extant today.** It is a deployment
fact rather than a code fact, which is why it is recorded as a premise and not
as a finding. Should any long-lived atSign turn out to hold auth-key-signed
material, this ruling needs reopening rather than patching — the retention it
deletes is the only thing that would have kept that material verifiable.

**3. An earlier draft of ruling 2 said "never advertise the auth key at all"
and was wrong.** Taken literally it empties `_apsk` at `now`, where the auth
key is the only signer, and every envelope a released-posture client produces
becomes unverifiable. Recorded because the wrong version is the one that reads
as simpler, and a later reader reaching for it would break the default posture.

### 98.3 Where the signing key comes from

**4. The retrofit and the greenfield onboard mint the signing keypair *before*
submitting, and the enrollment request advertises it as `apskLegacy`.**

`_apskFor` composes `_apsk` from `apkamPublicKey` today, and its own comment
states the assumption this ruling breaks: *"at request time the enrollment has
just been minted and holds nothing but this APKAM keypair."* Under rollout 1
that keypair is ML-DSA, so the existing code would publish an **array
containing the ML-DSA auth key** at the moment of enrollment — the precise
breakage rollout 1 exists to prevent, arriving before any client has started,
and landing on peers who cannot fix it and would not know why.

So `_apskFor` stops reading `apkamPublicKey` and takes the signing key's public
half instead. The record is correct from its first byte. The cost, accepted:
signing keys are minted at two sites, and `SigningKeyMinting` at client start
becomes the **heal path** for enrollments that predate this rather than the
only producer.

⚠️ **The cost was larger than "two sites": it was two writers of one record,
and only one of them obeyed [98.1](#981-the-stages).** Measured while building
row B4, 2026-08-14: the heal path published the **array** unconditionally,
because it sends `EnrollmentUpdateRequest(signingKeys: …)` with no branch and
the updater prefers that field over `apskLegacy`. So a rollout-1 client healing
an enrollment created before this ruling advertised JSON on the one record
un-upgraded peers base64-decode as an RSA key. Fixed by giving the
bare-versus-array rule a single definition, `bareApskValueOf`, which both
publishers consult — the enrolment request already had its own copy in
`_apskFor`, and a third was what let the two disagree. Whether the atServer
honours `apskLegacy` on an `enroll:update` at all was a claim about the server
rather than the client, since it had only ever been sent on an enrolment
request; it is now measured live in `apsk_server_side_test.dart`.

⚠️ **AMENDED 2026-08-14, before B3 was built: ruling 4 as written breaks key
conveyance, because `_apsk` has a second consumer this ruling did not
account for.** The paragraph above stands; what follows is what it was
missing.

`_apsk` is not only what verifies an enrollment's envelopes. It is also what
verifies its **key package** — `verifyAdvertisedKeyPackage`
(`enrollment_directory.dart:216`) calls
`verifyEnvelopeSignature(..., signerEnrollmentId: enrollmentId)`, which
resolves that enrollment's `_apsk` and checks the package against it. And the
package is signed with the **APKAM keypair**
(`enrollment_key_package.dart:133`, which hands `signEnvelope` the
`apkamPublicKey`/`apkamPrivateKey` the construction keys carry).

So swapping `_apsk` to the signing key while the package is still signed by the
APKAM key makes every party that seals to this enrollment fetch `_apsk`, fail
the verification, log *"does not verify against its `_apsk`, so the key it
offers is only as trustworthy as whatever served it; not sealing to it"* and
return `rejected`. That is not an approve-time-only failure: the same path runs
whenever anyone seals a secret to the enrollment, so the enrollment would be
created and then never receive any conveyed key material.

⛔ **The obvious smaller fix was PUT AND REJECTED, and it is the one to reach
for, so it is recorded here.** The alternative was to apply ruling 4 *only*
where no key package rides the request — leaving `_apsk` naming the APKAM key
whenever one does. Nothing breaks, and the diff is a one-line condition. It was
rejected because **the retrofit always sends a key package**, so the exception
swallows the rule: rollout 1 would keep advertising its ML-DSA authentication
key on the only path that creates a rollout-1 enrollment, which is the precise
breakage this whole ruling exists to prevent. A future reader hitting this
tension will find that condition attractive; it guts the stage silently, and
every rail stays green while it does.

**Ruled by gkc 2026-08-14: the key package is signed with the SIGNING key.**
`enrollmentKeyPackageBuilder` hands `signEnvelope` the minted RSA-2048 signing
keypair rather than the APKAM keypair, so the record and the package agree
again. This is the coherent reading of the split rather than a patch around it:
the signing key signs what the enrollment *attests to*, a key package is
exactly such an attestation, and the APKAM key's job is proving possession on a
connection. A key package signed by the authentication key **is** the
conflation this whole ruling exists to remove — `enrollment_key_package.dart`'s
own dartdoc states it plainly today, that `signingAlgo` "names the algorithm of
the APKAM keypair the handed `AtKeys` carries, and therefore how the envelope
is signed".

✅ **Built and differentially proven the same day (row B3, retrofit half).**
Both questions this entry left open are answered:

- **`_apskFor`'s "a key package forces the array" rule now yields to the bare
  form** when an advertised signing key is present. The rule existed because
  the package's signer was the APKAM key, whose algorithm is whatever the
  enrollment authenticates with — and a bare value can only say `rsa2048`. A
  package signed by an rsa2048 *signing* key is exactly what the bare form
  states, so the two constraints stopped competing.
- **`signingAlgo` on the builder keeps naming the APKAM key's algorithm**, and
  is used only when no signing key is supplied. It did not need to change
  meaning; it needed to stop being the only answer.

The seam is an explicit `EnrollmentRequest.advertisedSigningKey`, supplied by
the caller rather than minted in at_auth, because whether to hold a signing key
is a rollout position and at_auth cannot see a preference. Absent, every path
behaves exactly as before, which is what keeps `now` unmoved.

**Proven by three mutations, each reddening exactly one test**: ignoring the
advertised key in `_apskFor` reddens the advertisement pin; dropping the filing
reddens the keyfile pin; and signing the package with the APKAM key again
reddens the signer pin — the last being the one this amendment exists for,
since a package signed by the wrong key still verifies against *that* key and
fails only against the record.

✅ **The greenfield-onboard half followed the same day.**
`makeActivationPqNative` mints the rsa2048 signing keypair, sets it on the
onboarding request **and** hands the same pair to the key-package builder — the
second being the failure this ruling is about, and now the one its dartdoc
names explicitly as the way to get the call wrong.

**5. Rollout 1 is entered only by a new enrollment.** An existing `now`
enrollment does not rotate into it; it stays at `now` until it retrofits, and
the retrofit mints a new enrollment id with both keys. This is what keeps
rollout 1 free of an APKAM rotation — so it depends on neither step 20's
unbuilt rotation arm nor the at_auth release that arm waits on. **Rollout 1 is
buildable today.**

### 98.4 Where the stage lives

**6. Both halves derive from `SigningRollout`.** It gains
`defaultRetrofitAuthenticationAlgo` beside `defaultInUseSigningAlgorithms`
(`now` → `rsa2048`, `rollout1`/`rollout2` → `mldsa65`), and the in-use set
becomes `{}` / `{rsa2048}` / `{mldsa65}`. This is step 19's reasoning applied to
the other half: two stored fields would be two controls over one position, and
an operator who set the stage but forgot the algorithm would land in a state no
release defines with nothing to tell them.

**7. `ReleasePosture.retrofitSigningAlgo` is renamed
`retrofitAuthenticationAlgo`.** It selects the algorithm of the key that
*authenticates*, in the one subsystem whose entire premise is that
authenticating and signing are different keys. The rename is free —
`ReleasePosture` does not exist in at_client 3.14.0, verified.

**8. The wire field `EnrollParams.signingAlgo` keeps its name; its dartdoc is
corrected.** It is documented as "the signing algorithm of `apkamPublicKey`" —
i.e. it has always named the *authentication* key's algorithm, from before an
enrollment had signing keys of its own. Renaming it is a multi-repo protocol
seam against a released atServer, and a stale reader seeing an absent field
falls back to `rsa2048`, which is a silent wrong-algorithm PKAM. Not worth it
for a naming fix; the dartdoc says plainly what the name does not.

### 98.5 Two findings from the same session, unrelated to the stages

**9. A cached client silently keeps its original preference, and it must throw
instead.** `AtClientImpl.create` caches by `(atSign, enrollmentId)` and on a
cache hit adopts **only** `preferences.crypto`, with a comment asserting "there
is nothing else to reconcile" — true when written, false since `posture`,
`signingRollout`, `inUseSigningAlgorithms` and `disallowLegacyEncryption`
became final-at-construction fields. Measured: a client asked for
`signingRollout: rollout2` reported `now` and an empty in-use set, and minted
nothing while every other diagnostic looked healthy.

It throws rather than warns, over the final-at-construction fields only.
Reconciling them instead was rejected: they are final precisely because the
substrate reads them once, so a client whose bootstrap already ran under the
old value would be a worse lie than the current one. A warning was rejected
because a silently-wrong posture is exactly the failure the dropped-event rule
says goes unnoticed. `namespace` and `rootDomain` stay out of the comparison —
re-scoping a client is an existing pattern.

✅ **BUILT 2026-08-14 (row C1), and the ruling named one site where there are
two.** `AtClientManager.setCurrentAtSign` short-circuits a same-atSign call
carrying no override argument and **returns without calling
`AtClientImpl.create` at all** — it is the ordinary path, and the one an app
switching stage takes, so a guard on the cache alone would have been loud only
where a caller happens to pass an `atKeysIo`/`atLookUp`/`enrollmentId` and
silent everywhere else. Both sites now call one static
`AtClientImpl.refuseChangedRolloutAxes`. Proven by two mutations: removing
either guard reddens only its own row, so neither is standing in for the other.

Two shapes the build settled that the ruling did not state:

- **The comparison is by VALUE, never identity.** Callers hand over a fresh
  preference object on every call — the e2e pack builds one per
  `setCurrentAtSign` — so an identity test would refuse every one of them and
  this would be a break rather than a check.
- **The posture is compared by what it MEANS**, not as an object.
  `ReleasePosture` declares no `==`, so comparing two of them is an identity
  test, and only `const` instances are canonicalized: a caller writing
  `ReleasePosture.migration()` without `const` would be refused over a
  difference that does not exist. What is compared is the two posture fields
  nothing else carries — `writesPqByDefault` and `keyExchangeMode` — beside the
  three effective axes, which is the whole of what a posture can change.

The diagnostic names **every** differing axis rather than the first, because
naming a stage moves the set it derives: asking for `signingRollout: rollout1`
against a `now` client differs on two axes, and reporting one would send a
reader looking for a setting nobody wrote.

⚠️ **A third door, found while building and ruled shut by gkc the same day:**
`AtClient.setPreferences` replaces the whole preference on a running client, so
leaving it unchecked would have made the other two a check in appearance only.
Naming the replacement does not make the change possible — these axes are read
at a startup that has already run by the time anyone can call it, so accepting
them would leave the client *reporting* a stage it never applied, which is
worse than the silent drop it replaces: there the caller at least kept the
stage it was running under. Everything outside the rollout axes is still
replaced, `crypto` included.

**10. `selfRetrofit`'s "no ML-DSA anywhere" is wrong and the doc is fixed, not
the gate.** A fully privileged `rsa2048` retrofit files an ML-DSA-65
`pq_signing_root`, because `mintIfAbsent` gates on privilege and never on the
retrofit algorithm — observed in a generated keyfile. The root is the
**atSign's**, not the enrollment's, and gating it on a per-enrollment algorithm
choice would let the first privileged retrofit's mode decide whether the atSign
ever gets a root at all. The sentence is scoped to the enrollment's own keys.

**11. The legacy flat block is permanent.** `aesPkamPrivateKey` and its
siblings survive every stage verbatim, and nothing will remove them. It is the
legacy round-trip contract, and a scheme to retire them would need a party to
run it and a definition of "proven" — the shape this project has built and
removed before.

### 98.6 What this replaces in acceptance

**12. UC-G1.14 stops asserting byte-identity and asserts that a released reader
can parse a rollout-1 sender's `_apsk`.** Byte-identity is false now (rollout 1
publishes a different key from `now`) and was always a claim about our own
writer. The property worth protecting is that a deployed peer is unaffected,
and the published arm can measure exactly that — an at_client 3.14.0 client
fetching the record and base64-decoding it as an RSA key, the same as it does
for a `now` sender.

## 99. The keyfile groups by enrollment, and the atSign's own keys move out (2026-08-14)

**In brief:** *the at-rest shape; nothing released has ever written a typed keyfile, so there is nothing to migrate*

The at-rest `.atKeys` shape, ruled by gkc over a grilling session against a
target document he wrote. Prompted by generating a real keyfile's evolution
through the stages and reading what it actually contains. Builds on
[98](#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14),
which changed *which* keys exist; this changes *how they are arranged*.

### 99.1 The measurement that makes this cheap

**Nothing released has ever written a typed keyfile — not even an empty one.**
Measured 2026-08-14 with a positive control (40 `AtKeys` hits in at_auth
3.3.0's `at_keys.dart`; 1 for `class AtClientImpl` in at_client 3.14.0):

| Checked | Result |
|---------|--------|
| Callers of `addKey` / `file*Material` / `replaceKey` in at_auth 3.3.0 | none outside the declarations |
| Same in at_client 3.14.0 | none |
| Same across every package in `~/.pub-cache` | none (one hit, `analyzer`'s unrelated `_errorsRequestedFiles.addKey`) |
| Anywhere released code sets `AtKeys.atsign` outside `fromJson` | none |

The last row decides it. `atsign` is public and settable, but every released
construction site is a bare `AtKeys()` — including `at_enrollment_impl.dart:121`,
which builds the keys an enrollment response persists. With `atsign` null,
`toJson` returns `_toLegacyJson()`: flat fields only, no `version`, no `keys`.

⚠️ **It nearly went the other way.** Released `toJson` emits
`version`/`atsign`/`keys` whenever `atsign` is set, **even for an empty
`keys`** — the `keys.isEmpty` short-circuit that avoids stamping a version
marker onto a legacy file is a spike change, absent from 3.3.0. Had any
released writer set `atsign`, the field would hold `{"version":1,"keys":[]}`
documents and every ruling below would need a migration.

So: **there is nothing at rest to migrate**, and the shape is free to change.

### 99.2 The shape

**1. `keys[]` becomes `enrollments[]`** — an array of enrollment objects, each
carrying `enrollmentId`, the record snapshot, and its own `keys[]`. Key entries
no longer carry an `enrollmentId`; the container states it once.

**2. One entry today, plural by design, and the READER ships tolerant first.**
Writers emit exactly one and an assurance rule refuses a second. The *reader*
accepts many from day one and selects the enrollment it is authenticating as,
skipping the rest. This is the rule this tree wrote after a `.single` shipped
on a widened collection: a reader that refuses a second entry makes the feature
unenableable, because the first writer to emit one breaks every build that
predates it.

> **Renamed 2026-08-15 — the at-rest field is `atsignKeys`, not `atSignKeys`.**
> gkc's call, to match its sibling `atsign` in the same document. **Every
> ruling in this ledger that says `atSignKeys` — this one, 100, and 101 — is
> left saying it, because that is what was ruled**; only the spelling of the
> persisted key changed, and nothing else about them. ⚠️ **101 is the one to
> watch**: it was written the same day but a few hours *before* the rename, so
> unlike 99 and 100 it is a **currently-active** ruling carrying the old
> spelling, and `implementation-plan.md` 14.21/14.22 describe the same field as
> `atsignKeys`. They are the same field. (This note originally scoped itself to
> "this ruling and the two below it", which left 101 outside it — found by a
> cold reader the same day.) **The Dart members keep their casing** — `atSignKeys`,
> `atSignKeysForKeyId`, `getAtSignKey`, `retireAtSignKey` — because the tree's
> naming rule is to preserve `atSign` capitalisation in code, and the lowercase
> form exists only to match a legacy field name in the document. Measured
> before renaming: **no released at_auth ships `atSignKeys` at all** (zero
> matches across all ten versions in the pub cache, with `class AtKeys` as the
> positive control), so nothing outside this tree reads either spelling.

**3. Material that belongs to the atSign moves to a top-level `atSignKeys[]`.**
The signing root is the atSign's, not the enrollment's — the document already
said so by *omitting* `enrollmentId` from that entry, and nesting it inside an
enrollment would override that signal with a structural claim that it belongs
there. It also retires a workaround: `signingKeysFor` selects on the `sign:`
keyId prefix rather than the `privateSigning` role **specifically because** the
root shares that role. At atSign scope the two cannot be confused by
construction. `atSignKeys` is genuinely plural — a losing pair from a mint race
is retired to `dead` and kept.

**4. Structured keyIds normalise to `<role>:<algo>:<generation>`** —
`auth:mldsa65:1`, `sign:mldsa65:1`, `root:mldsa65:1`. Three grammars become
one, and the algorithm is visible in every id, which matters now that an
enrollment holds keys of two algorithms at once. The kid-addressed KEM entry
(`cb84bc741ec5b268`) is unchanged: a kid is a digest of the key and is
addressed by value rather than by name.

**5. The enrollment id leaves the keyId.** The container states it; two stored
copies of one fact can disagree with nothing to arbitrate. ⚠️ **The
consequence is that keyIds are unique per enrollment, not per document** —
identity becomes `(enrollment, keyId)`, the same lesson as `(owner, id)`
elsewhere in this tree, and any code holding a bare keyId now needs the
enrollment beside it.

**6. `version` stays 1.** No `version: 1` typed document has ever been written,
so redefining what it names costs nothing observable. ⚠️ The cost that *is*
real: the spike's own dev keyfiles and virtualenv fixtures are version-1
old-typed and become unreadable, so they need regenerating. A bump to 2 was
recommended and declined.

### 99.3 What each field means

**7. The top-level `enrollmentId` belongs to the legacy block.** It names the
enrollment `aesPkamPrivateKey` authenticates as — frozen when typed material
appears, exactly as the key material beside it is. It is not the document's
enrollment id and never was. It is still needed: the legacy APKAM key keeps
authenticating until the atServer's expiry cap retires it, and a client using
it has to know as whom. Together with [98](#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14)'s
ruling that the flat block is permanent, this makes the whole flat group one
coherent thing — legacy key material and the id it belongs to.

**8. `namespaces`, `appName` and `deviceName` are a snapshot, reconciled on
every start.** They exist so an app can say which device a keyfile is for
*before* authenticating, which the atServer cannot answer. On authentication
the record is fetched and the copy refreshed; a changed `namespaces` is logged,
because that is a grant change the user may care about. ⚠️ **That writer must
go through `WrittenAtKeysIo.update`** — this tree has already lost key material
to two unawaited start-time writers doing read-mutate-write on this file.

**9. `status` stays explicit at rest, on every part, including `active`.** The
keyfile is the store of record and has no byte-identity constraint; `_apsk`
omits it when active only so a never-rotated advertisement stays byte-identical
to what the pre-split composer wrote. The parse still tolerates its absence, so
the rule is "write it, tolerate its absence".

**10. `AtKeysMaterial` keeps `enrollmentId` in memory and never serializes
it.** It already works this way and the question of removing it dissolved on
inspection: `AtKeysMaterial.toJson()` emits neither `keyId` nor
`enrollmentId` — `encodeAtKeysDocument` hoists them to the entry level, and
`fromJson` takes them as named parameters from the enclosing scope. So the
field is already container-derived rather than stored, and the duplication that
prompted the question lives only in the *entry-level* output, which ruling 1
removes. Keeping it becomes more necessary under ruling 5, not less: with
keyIds unique only within an enrollment, a bare material without it is an
incomplete address. It also makes gkc's intended guard possible —
`material.enrollmentId` against the client's, checkable at any boundary.

### 99.4 Released readers, and a gap this exposes

**11. A released build handed a new-shape keyfile refuses it, and that is the
right failure.** `expectList(json['keys'], 'keys')` throws when `keys` is
absent, so the document is rejected loudly rather than parsed as legacy-only.
The alternative is worse: authenticating from the flat block as the *legacy*
enrollment while the typed one it cannot see is the current identity. Since no
released writer produces typed material, this can only arise from a downgrade
on a machine a new build already touched. Emitting a vestigial `keys: []` to
keep old readers parsing was rejected for exactly that reason.

⚠️ **12. Nothing retires a superseded signing key** — found while projecting
the target. `SigningKeyMinting.mintMissing` computes only *wanted − held*,
mints that, and republishes **all held keys as active**; `retireKey`'s sole
production caller is the signing root's losing-pair path. So the rollout-1→2
transition as coded would leave `rsa2048` active and sign every envelope twice,
where [91.3](#913-the-rulings) ruling 9 says it stops signing and is retained as
`retired`. Latent under the old stages (rollout 1 held no signing key, so there
was nothing to retire); **required** under
[98](#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14),
which makes that transition a real algorithm retirement.

✅ **BUILT 2026-08-14** (this paragraph read "Owed, unbuilt" until then).
`mintMissing` is now `reconcileSigningKeys`, which computes *held − wanted*
beside *wanted − held* and returns both. New
`AtKeys.retireSigningKeys(enrollmentId, algorithm)` moves both halves to
`retired`, selected on the `sign:<algo>:<n>` shape rather than the
`privateSigning` role. Three things the build settled that this ruling did not
say:

- **The publish is handed the keys it is about to retire**, rather than
  re-reading them. The keyfile still holds them as *active* at that point,
  because the publish comes first, so a re-read returns the record's history
  and misses this withdrawal — and the key would then vanish from the
  advertisement rather than move to `retired`, unverifying everything it
  signed. Measured: reverting that one argument turns the advertisement pin
  red and makes an envelope signed before the move fail with *"the envelope is
  signed under `RS256` and the published `_apsk` advertises `mldsa65` — no
  algorithm in common"*.
- **The withdrawal is filed after the addition.** Filing it first leaves a
  moment with no active signing key, where `signingKeys` falls back to the
  APKAM authentication key — which the advertisement has by then stopped
  naming, so anything signed in that window would never verify.
- **An empty in-use set retires nothing**, which is deliberately not read as
  "every algorithm has left the set". It is the released posture, where a
  client holding a signing key goes on signing with it and advertising it
  bare; retiring there would drop it to its authentication key and publish an
  array, on the one stage that must never see one.

## 100. The seven shapes ruling 99 left open (2026-08-14)

**In brief:** *what 98 and 99 left unstated, and what row A1 encodes*

[`implementation-plan.md` 14.20](implementation-plan.md#1420-building-rulings-98-and-99--the-sequence)
listed six questions its build sequence does not answer and said to ask rather
than guess, because each decides a shape and guessing wrong builds the wrong
thing silently. A seventh surfaced while checking the six against the tree. All
seven ruled by gkc, each against the measurement named with it.

Nothing here changes
[98](#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14)
or [99](#99-the-keyfile-groups-by-enrollment-and-the-atsigns-own-keys-move-out-2026-08-14).
This is what those two left unstated, and it is what row A1 encodes.

**1. The caller supplies the enrollment a keyfile authenticates as, and
`AtKeys` stops deriving it.** Measured: `activeEnrollmentId` has no production
caller — every hit outside its own declaration is a test — and both live
resolvers already take an explicit id, `AtAuthImpl.authenticate` passing
`AtAuthRequest.enrollmentId` and `AtClientImpl._createAtChops` passing its own.
So the derivation 99 ruling 2 breaks was answering a question nothing asks. The
reader selects the `enrollments[]` entry matching the id it was handed and
throws when none matches. A null id keeps meaning the flat block, which on a
retrofitted keyfile is deliberately the legacy enrollment.

A stored pointer field was rejected for the reason `activeEnrollmentId`'s own
dartdoc gives: a second writer able to disagree with the key material, where
disagreeing means authenticating as the wrong enrollment.

⚠️ **Amended within the hour, by gkc: "the caller supplies it" alone is a
chicken and egg.** A cold start holds nothing but the keyfile — the first
caller has no id to supply, and 99 ruling 7 rules out taking the top-level
`enrollmentId`, which belongs to the legacy block. So the ruling is *the caller
supplies the id, and `AtKeys` offers a derivation the caller can ask for*:

- `enrollmentIds` — every enrollment the file holds.
- `authenticatableEnrollmentIds` — those holding active authentication
  material, whatever algorithm it names.
- `resolveAuthenticatingEnrollment()` — the one when there is exactly one,
  null when there is none, and a **throw naming them all** when there are
  several.

The difference from what was removed is the difference that matters.
`activeEnrollmentId` was consulted implicitly and answered `firstOrNull`, so a
file with two live enrollments picked one silently. This is invoked by name,
returns an id the caller then passes back in, and refuses to guess. The
selection stays the caller's, and the file supplies the candidates rather than
the verdict.

**2. The accessors split by scope.** `getKey`, `keysForKeyId`, `retireKey` and
`replaceKey` become enrollment-scoped and take the enrollment beside the keyId;
a separate family addresses `atSignKeys[]`. Measured: outside at_auth there are
six production call sites and **every one is atSign-scope** — `PqSigningRoot`
(`getKey`, `keysForKeyId` twice, `retireKey`) and nskey filing (`getKey` three
times) — while `replaceKey` has no production caller at all. The split moves
each of them to the atSign family, where a bare keyId is still unique, and none
can reach an enrollment's keys by accident.

An optional `enrollmentId` parameter and a purely internal composite index were
both rejected on the same failure: each leaves an atSign-scope caller
compiling, and searching the wrong container, with nothing red.

**3. `apkam:<enrollmentId>:<n>` becomes `auth:<algo>:<gen>`, with no tolerance
for the old spelling.** [99.1](#991-the-measurement-that-makes-this-cheap)
measured that nothing released has ever written a typed keyfile, and 14.20 row
A3 deletes the ones this spike's live runs generated. A parser accepting
`apkam:` would therefore be code no file can reach — and dead tolerance reads
as a supported path.

**4. The generation is the slot.** The signing root is `root:<algo>:<n>`, its
free slot found by walking generations, its next generation computed
highest-plus-one exactly as the other roles compute theirs; a dead losing pair
from a mint race keeps generation 1 and the next mint takes 2. The `.2`/`.3`
overflow grammar goes, and `_isRootSlot`'s regex with it.

⚠️ The at-rest keyId is free to change and the **record name is not**:
`public:pq_signing_root@<atSign>` is the wire value, pinned as a raw literal in
`wire_literal_pins_test.dart`, and it does not move. The pin on
`PqSigningRoot.keyId` follows the id, because that one is at-rest.

**5. An nskey private lives in `atSignKeys[]`.** It is filed today with no
enrollment id at all, which is [99](#99-the-keyfile-groups-by-enrollment-and-the-atsigns-own-keys-move-out-2026-08-14)
ruling 3's own signal for material that belongs to the atSign — and a namespace
key is the atSign's. One entry serves every enrollment holding the grant,
rather than the same seed stored once per enrollment with each copy waiting on
its own conveyance.

⚠️ **This is not a general rule about KEM material.** The enrollment's key
package keypair — the bare-kid entry in both target files — stays inside the
enrollment, because that one really is per-enrollment. Neither target file
shows an nskey private for the plainest of reasons: the atSign that generated
them never received one.

**6. `namespaces`, `appName` and `deviceName` are written from the enrollment
request where one exists, and omitted where none does.**
`AtEnrollmentRequest` carries all three, so an enrollment-creation writer holds
them and the keyfile can answer "which device is this?" from birth — which is
what [99.3](#993-what-each-field-means) ruling 8 says the fields are for. A
retrofit, or an onboard handed its keys by the caller, has no request: it omits
the fields, the parse tolerates their absence, and row C2 fills them at the
first authenticated start.

Placeholders were rejected. An empty `namespaces` map states "no grants", and
a reader cannot tell that from "not yet known".

**7. `operations` is unchanged** — parsed, round-tripped, and emitted only when
non-empty. Measured: nothing in production sets it, the only writers being
at_auth's own copy paths, so its absence from both target files is a missing
producer rather than a removal. Dropping it would break the lossless-flush
promise that `KeyAlgorithmType`, `CryptographicKeyType` and `KeyPartStatus`
each state in their own dartdoc.

## 101. The signing root becomes an ordinary signing key, and rotatable (2026-08-15)

**In brief:** *the root adopts the `_apsk` vocabulary and the record becomes mutable; D1 builds rotatability, not rotation*

From a question gkc asked while reading the at-rest shape: what is persisted for
the atSign's root signing key, and can it be rotated later. The answer was no —
for four reasons beyond the record's immutability, stated at
[`implementation-plan.md` 14.21](implementation-plan.md#1421-the-signing-root-cannot-be-rotated--raised-2026-08-15).
gkc set two requirements, and between them they settle it: the root is
persisted like every other signing key, and D1 does everything that makes
rotation possible **without building the rotation**.

**The premise that shortens all of it.** Nothing is released, so no client
outside this tree mints a root — every atSign carrying one is ours, to delete
or recycle. *Immutable*, *frozen* and *one-way door* describe a constraint on
rewriting **one record**; none of them constrains the shape we choose. This is
the licence [100](#100-the-seven-shapes-ruling-99-left-open-2026-08-14) ruling
3 used to refuse a parser for the old `apkam:` spelling, and it applies here
for the same reason. ⚠️ It was re-litigated once on the way to this ruling, in
a new costume — "records already published on live atSigns" rather than "the
package is published" — and cost a round trip.

**1. The record adopts the `_apsk` advertisement vocabulary, verbatim.**
`{v: 1, keys: [{kid, use: 'sign', alg, pub, status?}]}` — the shape
`apskAdvertisement` emits and `apskSigningKeys` reads. Measured gap: the root
publishes `{alg, pub}`, and spells its algorithm `ml-dsa-65` where `_apsk` uses
`SigningAlgoType.name`, `mldsa65`. That difference *is* requirement 1, and
there is no argument left for it: two records advertising signing keys in two
vocabularies is
[94](#94-three-records-advertise-keys-and-only-one-of-them-speaks-the-vocabulary-2026-08-11)'s
finding, not a design.

None of the fields is decoration:

- **`kid`**, derived by the existing `publicKeyKidOfBase64`, is the key
  identifier a root link lacks today. It turns "try every published root" into
  a selection.
- **`status`** is what lets a rotated-out root stay advertised. That is
  [98](#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14)'s
  `_apsk` rule — a key is retained for what it signed — and the root needs it
  more than any enrollment key does, because every root link ever issued was
  signed with it.
- **`use: 'sign'`** is accurate rather than ceremonial: nothing is ever
  encapsulated to the root.

**2. `successor` and the bare-base64 reader are deleted.** Both exist only to
accommodate records already written, which under the premise above are ours
alone. `successor` could not have worked in any case: it is stamped `null` at
mint inside a record nothing rewrites, so it is a forward pointer writable only
at a moment when there is nothing to point at. Dead tolerance reads as a
supported path.

**3. The record becomes mutable, and the interlock moves to an explicit mint
lock.** [13](#13-the-nskey-is-published-eagerly-mutable-and-generation-addressed-2026-08-02)
already made this exact move for `public:__nskey.<ns>@<owner>`, on the finding
that immutability there was "a concurrency control, not a confidentiality one"
and that it made rotation unimplementable as specified. The root is the record
that never got the treatment. `NskeyMintLock` is built — a short-ttl immutable
self key, written remote-first because the atomicity has to be the atServer's
and a local-first put would let both enrollments believe they had won.

⚠️ **What this gives up, stated rather than glossed.** A refused second create
is an absolute guarantee from the atServer; a lock is a protocol, and a
protocol has a window. What covers it is the mint path's existing
reconciliation, which stays: read the published record, compare what is held
against it, retire a pair that corresponds to nothing. It was written for a
lost immutable create and answers the same question here.

> ✅ **BUILT 2026-08-15 by [14.22](implementation-plan.md#1422-making-the-signing-root-rotatable--decisions-101)
> row 6, with three amendments this ruling did not anticipate.**
> (1) `NskeyMintLock` is now **`MintLock`** and takes the lock's `AtKey`, so
> one implementation serves `_nskeylock.<ns>@<owner>` and the new
> `_rootlock@<atSign>`; this ruling's "`NskeyMintLock` is built" named the
> class as it stood.
> (2) The window is **two** windows, not one: the ttl can expire while the
> holder is still inside the critical section, and `_release` force-deletes
> without checking it still owns the lock, so a late holder can delete a
> successor's. The second is pre-existing and applies to the nskey path too;
> it is [`implementation-plan.md` 14.19](../implementation-plan.md#1419-small-items-raised-2026-08-12-and-not-yet-acted-on)
> item 18. The reconciliation this paragraph names covers both **for the
> root**; whether the nskey path has an equivalent is not measured.
> (3) The mint reads the record **twice** — the second read under the lock —
> which this ruling does not mention and without which the lock closes
> nothing: the first read happens before the lock is taken, so a winner that
> published in between is invisible to it, and a mutable record would then be
> overwritten.
> ⚠️ And one fact about the atServer that changes the scope of "the record
> becomes mutable": `immutable` is **sticky** at rest. `at_metadata_builder`
> preserves `immutable == true` from stored metadata whatever an update asks,
> so this makes roots minted from here on mutable and leaves any root already
> written with the flag permanently unrewritable. Immaterial under the
> greenfield premise above — every atSign carrying one is ours — but it is the
> reason the change cannot be described as "existing roots become mutable".

**4. At rest, `root:<algo>:<n>` in `atSignKeys[]` — already ruled, and only
partly built.** ✅ **BUILT 2026-08-15 by 14.22 row 2.** This paragraph read
"The code pins the algorithm anyway: `PqSigningRoot.keyIdPrefix` is
`'root:${KeyAlgorithmType.mlDsa65}:'` and `_isRootSlot` requires that exact
prefix, so a root under any other algorithm has no slot and no reader" — that
is no longer the code. The role is `PqSigningRoot.keyIdRole`, composition is
`keyIdPrefixFor(algorithm)`, and the parse moved down to
`AtKeys.isRoleKeyId(keyId, role)`, which is algorithm-blind and is the same
one `signingKeysFor` uses to select `sign:<algo>:<n>` — one grammar with one
home rather than a parse in at_client that had to agree with a writer in
at_auth. [100](#100-the-seven-shapes-ruling-99-left-open-2026-08-14)
ruling 4 ruled that the generation is the slot and the algorithm is part of the
id. The container does **not** move:
the root is the atSign's own key, and `atSignKeys[]` is where
[99](#99-the-keyfile-groups-by-enrollment-and-the-atsigns-own-keys-move-out-2026-08-14)
ruling 3 puts the atSign's material.

**5. D1 builds rotatability; D1 does not build rotation.** In scope: the record
shape, the readers, the writers, the verifiers and the signers, such that a
second root is representable, publishable and verifiable end to end. Out of
scope: the rotation operation itself — mint a successor, publish it, retire the
predecessor, re-anchor — and revocation.

The boundary is testable, which is what makes it real rather than an intention:
**a keyfile and a record each carrying two root entries, one active and one
retired, with a root link signed under the retired one still verifying.** That
is buildable with no rotation machinery anywhere, and once it passes, rotation
is a later operation over a structure that already holds.

**6. The reader lands before the writer, and the reason is prospective.** No
client in the field reads these records today, so this is not the usual
ships-first compatibility ordering. It is that after the GA minor ships,
readers *are* in the field, and a reader that takes the first entry is what
would stop a second one from ever being adopted. Building it in D1 is what
keeps rotation a decision later rather than a release-train problem, and that
is the whole of requirement 2.

## 102. An `_apsk` fallback value never replaces a real advertisement (2026-08-15)

**In brief:** *the publish-before-file window, three refused guards, and why the rule has no meaning on `primary`*

From the examination
[`implementation-plan.md` 14.19 item 15](../implementation-plan.md#1419-small-items-raised-2026-08-12-and-not-yet-acted-on)
asked for: can the record's several writers publish different compositions?
Measured answer — at rest they agree, and inside one window they do not.

**The window, and what it actually costs.** `SigningKeyMinting` publishes
before it files, deliberately: *"a minter publishes first precisely so that no
envelope is ever signed under a key the advertisement does not name"*. Between
that publish and the last file, the keyfile does not yet hold what was
advertised — so `ApkamSigning.publicSigningKeyValue`, which composes from the
keyfile, sees `heldSigningKeys` empty and takes `apskEntries`' authentication-key
fallback. `publishPublicSigningKey` then compares, finds a difference, and
**overwrites**: measured, a PQ-native enrollment's ML-DSA array replaced by a
bare RSA string. That also inverts the bare-versus-array form rule
`bareApskValueOf` exists to protect.

**gkc ruled: the fallback stops being able to do that.** A value composed from
the authentication key is what a client publishes when it has no signing key of
its own; it is not a statement that a signing key it can see has gone away. So
`publishPublicSigningKey` should refuse to replace a record that already
advertises a real signing key with one that advertises only the authentication
key.

⛔ **NOT BUILT, and deliberately so.** Three implementations were attempted on
2026-08-15 and the live pack refused all three, each for a different and
instructive reason. gkc then ruled the window **accepted and documented**
rather than guarded — see the end of this entry. The refusal is recorded
because the shape of each failure is what makes the acceptance an informed
choice rather than a shrug.

1. **Guard on what this client HOLDS** — refuse when the composed value is the
   authentication-key fallback. Too wide by one case: an enrollment whose
   `_apsk` the atServer wrote **at approval** also holds no signing key of its
   own and must republish with what it does hold. Measured: 160/165, with the
   approval conveyance timing out (*"the enrollment is approved but cannot
   decrypt anything without it"*) and UC-G1.14's control failing.
2. **Guard on the published SHAPE** — refuse only when the published value is
   the array form. Still too wide: a PQ-native enrollment's authentication key
   is ML-DSA, so its ordinary fallback is *also* an array. Measured: 162/165,
   the same conveyance failures.
3. **Guard on CONTENT** — refuse a write that would drop a kid the published
   record advertises. The most defensible statement of the rule, and it fails
   on the record the rule cannot be stated over: `public:_apsk.primary.a.__e`.
   A `primary` record belongs to no single client — every non-enrolled client
   of the atSign publishes its own key there and overwriting is the norm — so
   "never drop an advertised key" makes the *first* client to be refused leave
   another client's key standing. Measured: 160/165, and the guard fired
   exactly **once** in the whole run to do it.

⚠️ **What that last one actually establishes, and it is worth more than the
guard would have been: the demotion rule has no meaning on a record with no
single owner.** It could be stated for an *enrollment's* `_apsk`, which one
enrollment writes; it cannot be stated for `primary`. Any re-scoping starts
there.

⚠️ **A control arm was run**, per the both-arms rule: the same tree with the
guard stashed is **165/165**. So the guard is the cause, not the environment.
And the first diagnosis of run 2 — "the guard never fired, so it is not the
cause" — was wrong for a reason worth recording: `logger.warning` sits below
what the functional log surfaces, so the absence was a claim about the log
LEVEL, not about the code. Run 3 raised it to `severe` and the line appeared.

**Why not the alternatives.** Reversing the publish/file ordering trades a
window where the advertisement is stale for one where it is ahead of the
keyfile, which is the failure publish-before-file was chosen to avoid.
Serialising the writers closes the window only inside one process, and both
triggers are publicly exported, so it would read as a guarantee it could not
give. Accepting it was available all along, and after three failed attempts **gkc
ruled it 2026-08-15**: the window is accepted and documented rather than
guarded. The state heals at the next start — `publishPublicSigningKey`
composes from the keyfile, which by then holds the post-mint state, and
`register()` runs on every start — and verification reads the record live, so
envelopes signed during the window verify again once it heals. The cost is one
process lifetime of refused envelopes and refused key-package verification, on
a race that is itself unmeasured.

**What "documented" means concretely**, since a window nobody can find again is
not documented: the mechanism is written into `SigningKeyMinting._publish`'s
dartdoc where the publish-before-file ordering is chosen, and this ruling is
the reference. The three refused implementations stay recorded above, because
the next person to notice the window will reach for the first of them.

⚠️ **What this does NOT do.** It does not close the window: a concurrent writer
can still publish a *different real* composition, and the order-only at-rest
divergence between the two composers stays (benign — same kids, same pubs, same
statuses, and readers select by algorithm). Nor is the race itself measured;
the bootstrap awaits its steps in order and cannot interleave them, so reaching
it needs an application call racing the unawaited `startup()`.

## 103. An envelope says what it is for, and a verifier says what it wants (2026-08-15)

**In brief:** *per-use `typ` in the protected header; a verifier is handed the type it expects*

Step 27, [`implementation-plan.md` 14.8](implementation-plan.md#148-domain-separation-on-the-signed-envelope).
[Ruling 51](#51-the-from-challenge-and-a-signed-envelope-must-never-share-a-shape-2026-08-08)
asked for domain separation between the `from:` challenge and a signed
envelope. Building it turned up a second, nearer confusion, and the ruling
below closes both.

### 103.1 Ruling 51's premise was re-measured before anything was built

It says the challenge and the envelope are signed by the same key, which
[ruling 98](#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14)'s
authentication/signing split could have made stale. It has not.
`ApkamSigning.signingKeys` returns `[authenticationSigningKey!]` whenever the
enrollment holds no signing material, and that key is
`atChops.atChopsKeys.atPkamKeyPair` — the keypair PKAM signs the challenge
with. At the default posture the two are one key, and they separate only once
an enrollment mints signing material. So ruling 51 describes the majority case,
not a legacy one.

Three things that one key signs today: the challenge `_<uuid><atSign>:<uuid>`,
the `enroll:update` possession proof
`<enrollmentId>|<apkamPublicKey>|<signingAlgo>`, and an envelope's
`<protectedB64>.<payloadB64>`. They are disjoint by character set, which is
what "by coincidence of two formats" meant.

### 103.2 The confusion that was nearer, and reachable

The envelope had **five** production uses — a chain link, an nskey
advertisement, a key package (signed at `enroll:request` and again when
registered), a sealed pairwise secret — plus whatever an application passes to
`wrapAndSign`. All signed by one key, and told apart only by which field names
their payload happened to carry.

`PqSigningChain._checkChainLink` accepts a link on three checks: the signature
verifies against the signer's `_apsk`, the payload names this enrollment, and
it names the published key. Nothing asserted the envelope was signed **as a
link**. So an envelope from any other use, over a payload carrying
`childEnrollmentId` and `apkamPublicKey`, was a valid chain link from that
signer — and `wrapAndSign` is the application-facing verb, whose payload is the
application's input. An enrollment that got a privileged client's app to sign
attacker-shaped data could have had itself vouched for.

**Stated plainly: this was a shape, not a live exploit.** `verifyChain` has no
production consumer — only tests, as
[ruling 96](#96-the-programme-pair-gets-a-home-outside-the-workspace-2026-08-14)'s
neighbourhood already recorded — so nothing acted on the verdict. It is closed before
something does.

### 103.3 What was built

**gkc ruled: a per-use `typ`, and the reserved default for applications.**

1. `EnvelopeType` — `at-app+jws`, `at-chain-link+jws`, `at-key-package+jws`,
   `at-nskey-ring+jws`, `at-secret-envelope+jws` — stamped into the protected
   header, where the signature covers it. JOSE's convention (a media type with
   `application/` dropped) and what RFC 8725 §3.11 asks explicit typing to look
   like.
2. `signEnvelope` **requires** the type. A default would be whichever use was
   written first, and every other use would sign under it silently — the state
   this replaces. The required parameter is also what swept the tree: 60
   call sites, every one an analyzer error.
3. `verifyEnvelope` and `verifyEnvelopeSignature` take `expecting`, and refuse
   an envelope typed anything else **before** checking the signature.
   Dispatching on the envelope's own `typ` instead would let the document
   choose which checks run, which is the confusion rather than a cure for it.
4. `wrapAndSign` defaults to `EnvelopeType.app` — a type no verifier inside the
   library accepts. An application that signs data someone else influenced
   cannot be walked into producing any of the four internal documents.
5. `SignedEnvelope.fromJson` refuses entries that disagree about the type, for
   the reason it already refuses entries that disagree about `kid`: the entry a
   verifier resolves is chosen by **algorithm**, so entries that disagree would
   let the checked entry and the declared purpose be different entries.

**The shape stays RFC 7515.** That was the argument for `typ` over a prefix on
the signing input, and it is checked rather than claimed: the regenerated
vectors verify under panva's `jose` (RS256, with its tamper arm) and under
OpenSSL 3.6.3 for ML-DSA-65, the latter with a negative control that fails.

### 103.4 The root link is not a JWS, so it gets a prefix

`PqSigningChain.rootLinkDomain` — `at-root-link:` — ahead of the payload in the
bytes the signature covers, via one codec, `rootLinkSignableBytes`, used by the
signer and both verifiers.

**A prefix rather than a field in `payload`, and that is forced.** The payload
is shared verbatim with the chain link, which is what lets one signer vouch for
the same fact either way; the `kid` field's own dartdoc had already recorded
why a root-only member cannot go in there. So a field naming the flavour would
either change what a chain link signs or make the two payloads differ. The
prefix leaves the document alone.

### 103.5 The re-anchor this forced, which the row did not name

`publishOwnRootLink` skipped on **presence** — `_fieldFrom(current,
rootLinkField) != null`. Changing the bytes a root link signs would therefore
have stranded every root link already published, permanently: nothing else can
replace one, because the conveyance path publishes what an approver sends and
no approver sends a root link to an enrollment that already holds the private.

It now asks whether the link still **holds** — describes the key the record
publishes, and verifies under a root the atSign still advertises — and
re-anchors when it definitely does not. An unreadable root record answers
"holds": that is a fact about the read, not about the link, and rewriting a
good link on a transient failure would replace one valid anchor with another
for nothing.

### 103.6 Proven by mutation, because all of it passed first run

- Remove the `typ` check from `verifyEnvelope` → **3 red**, the three tests
  that exist for it, nothing else.
- Drop the domain tag from `rootLinkSignableBytes` → **4 red**: the two new
  root-link tests, the re-anchor (its old-shape signature becomes valid again),
  and the pre-existing anchoring test, which now spells the prefix literally.
- Restore the presence check in `publishOwnRootLink` → **1 red**, the re-anchor
  test alone.

at_client 1327 → **1336** (2 skipped): 2 pins, 4 envelope, 3 chain.

### 103.7 What was considered and rejected

Recorded because nothing in the code says a thing was weighed, and each of
these is a simplification the next reader would otherwise propose as an
improvement.

- **One blanket `typ` meaning "an envelope this build signed", rather than one
  per use.** Smaller diff, no per-caller argument, and it would still stop a
  foreign JWS being replayed as ours. **Rejected because it does not close the
  gap that was actually measured**: the five uses stay mutually substitutable
  under a single value, so the chain-link confusion of 103.2 survives it
  untouched and step 27 would have needed a successor row. A `typ` that every
  document shares distinguishes nothing.
- **Requiring every caller — applications included — to name the type.** Most
  explicit, and it would make a signer who never considered domain separation
  stop and choose. **Rejected** because it is a source break on a public
  `@experimental` API that hands application authors a decision they have no
  basis to make; the reserved default is refused by every internal verifier,
  which is the protection they actually need.
- **A domain prefix on the envelope's signing input**, as the root link got.
  Structurally stronger — the signed bytes could then be nothing else.
  **Rejected because it leaves RFC 7515**, so an off-the-shelf JWS verifier
  could no longer check our envelopes, and that adjudication by two outside
  implementations is a property this shape was deliberately chosen for.

⚠️ **What this does NOT do.** The possession proof and the `from:` challenge are
untouched — they are not JWS and carry no room for a type, and their
disjointness from each other and from the envelope is still the character-set
argument of 103.1. Nothing here makes the challenge self-describing;
`at_lookup` 3.6.1's `validatedFromChallenge` remains the assertion on that side.

---

## 104. The nskey mint stops needing a winner (2026-08-16)

**In brief:** ⛔ *HELD, superseded the same day by [105](#105-the-nskey-mint-elects-a-winner-and-an-atserver-defect-blocks-the-clean-shape-2026-08-16); the log model is a candidate in reserve, and 104.1–104.3 and 104.9 are measurement that stands*

⛔⛔ **HELD — NOT THE DECISION. Read
[ruling 105](#105-the-nskey-mint-elects-a-winner-and-an-atserver-defect-blocks-the-clean-shape-2026-08-16)
first.** This ruling was made and then superseded **the same day**, by a
measurement taken hours after it was written. It said, in this paragraph,
"gkc ruled that an nskey generation is minted without coordination", and that
was true when written: it is what 104.4 records, and 14.23's seven rows were
sequenced against it.

What changed is that gkc then stated the requirement directly — *if enrollments
A, B and C all decide they need to mint, only one of them eventually does* —
and proposed an election protocol that satisfies it without a log. Ruling 105
records that protocol and the order of work. **The log model here is a
candidate held in reserve, to be chosen or discarded once the lock-only design
has been built and measured**, not work in flight.

Everything below stays, because none of it is wrong and most of it is
measurement rather than design: 104.1–104.3 and 104.9 are what the lock
actually buys, how both paths heal, two claims of mine that were corrected, and
the atServer probe. 104.4–104.8 describe the log model as designed, which is
exactly what a later reader will need if it is taken up.

**gkc ruled that an nskey generation is minted without coordination.** Each
generation gets its own record; the published advertisement becomes a *summary*
healed from those records; and the mint lock survives on this path only as an
advisory hint that can never stop a client making progress. The signing root is
untouched and keeps its dispositive interlock.

The route here was
[`implementation-plan.md` 14.19](../implementation-plan.md#1419-small-items-raised-2026-08-12-and-not-yet-acted-on)
item 18 — `MintLock._release` force-deletes a lock it may no longer own.
Answering "is that worth fixing" meant measuring what the lock was buying, and
the measurement is what moved the design.

### 104.1 What the lock buys, measured

`MintLock` takes an interlock by writing a short-ttl **immutable** record and
relies on the atServer refusing a second create; the refusal *is* the lock.
Nothing reads the record — `_take` writes a timestamp and every other reference
in the tree is a write, a delete, a key composer, a pin on the key string, or
prose. It is write-only.

Two windows follow, and only one of them is item 18.

| | window | what happens |
|---|---|---|
| 1 | **ttl overrun** | A is still inside `mint()` when the ttl elapses; B takes the lock legitimately and mints alongside A. Inherent to any lease without a fence at the resource, and no change to `_release` touches it |
| 2 | **stolen release** | A finishes late and force-deletes what is now **B's** lock; C takes it and mints alongside B. This is item 18 |

Window 2 is the worse one, and not because it adds a third minter: it is
**self-sustaining**. Every late release re-opens the door for the next caller,
so one chronically slow client degrades the lock to no lock rather than to an
occasionally-leaky one.

### 104.2 Both paths already heal a loser — by different moves

Item 18 asked for exactly this measurement before any fix, because the argument
that made it tolerable was about the root and the nskey path was untested.

| | signing root | nskey |
|---|---|---|
| start-time step | `reconcileHeldPrivate` → `_retireUnadvertised` | `NskeySeeding.requestMissingPrivates` |
| what it does | **retires** an active private the record does not advertise | **requests** the private for the kid the record *does* advertise |
| why that shape | an active-but-unadvertised root private is *actively wrong* — `_activePrivates(keys).firstOrNull` selects it and signs with it | an nskey private is only ever selected by the kid in the envelope being opened, so a losing generation is **inert** |

So the answer is *yes, and not by the same move*. The nskey path needs no
retire and should not have one: retention is the design
([ruling 13](#13-the-nskey-is-published-eagerly-mutable-and-generation-addressed-2026-08-02)),
since rotation deliberately keeps old privates so `__ck` records sealed to
earlier generations still open.

### 104.3 Two claims corrected in the course of measuring

Both were mine, and the second is the one that changed the ruling.

1. **"A stranded generation is one nobody holds" — wrong.** The minting
   enrollment holds it. The accurate statement is nobody *reachable* holds it:
   the device is revoked or gone, its `_apsk` deleted, so it cannot answer a
   pull.
2. **"The log makes stranding worse, because today a later mint overwrites the
   advertisement and garbage-collects it" — wrong.** That overwrite never
   fires. `NskeySeeding.seed` is `if (await ring.currentPublic(owner,
   namespace) != null) continue;` — **nothing mints while an advertisement
   exists.** So an atSign whose advertised generation has no reachable holder
   is stuck *today*: `currentPublic` returns it, no mint happens,
   `requestMissingPrivates` asks and nobody answers.

Also confirmed while checking: there **is** a mint-time push — `seed` calls
`mintAndPublish` and then `_convey`, so stranding needs the minter to die
between publishing and conveying, or to be the atSign's only enrollment and be
revoked before a second one ever starts.

The consequence for this ruling: the log model does not introduce that hole. It
is the first thing that makes it **fixable**, because retirement gains a writer
and minting stops costing a lock.

### 104.4 The ruling

1. **A generation is minted into its own record.** Two concurrent minters write
   two different records and neither overwrites the other, so the mint needs no
   winner.
2. **The published advertisement becomes a summary healed from those records.**
   Senders keep reading one well-known name. Coordination is therefore not
   removed but **demoted** — from a lock before the mint to a shared write
   after it, on a value that converges because the summary is a pure function
   of the log.
3. **A sender may seal to any active entry.** List order carries no meaning.
4. **Retirement lives in the generation's own record**, as `status: retired`.
   The transition is monotone — active → retired, never back — so concurrent
   retires converge and no healer can re-activate a withdrawn generation.
5. **The mint lock becomes advisory.** A loser re-reads, adopts a usable
   generation if one is published, and **mints anyway if nothing is there**.
6. **The heal takes no lock**, reads the log **remotely**, and is **additive
   plus proven retirements**.
7. **`rotate` = mint + retire.** `mintAndPublish` only adds.
8. **An enrollment that cannot obtain an advertised generation's private, and
   finds no key package to ask, retires that generation and mints a fresh
   one** — on the first observation.
9. **The signing root is out of scope** and keeps its dispositive interlock.

### 104.5 The record shapes

**Summary — `public:__nskey.<ns>@<owner>`. The address and the wire format are
entirely unchanged**, which is worth stating because it is surprising: `keys`
is already a list, `NskeyAdvertisement` already defaults `suites` to
`openableSuitesForAll(keys.map((k) => k.alg))` — the union across generations —
and a sender already intersects that union with its own algorithm's suites, so
a union is safe by construction. `status` is already parsed and honoured by
`bestKeyFor`. What changes is who writes the record and that its list finally
has more than one entry.

**Generation — `public:__<kid>.__nskeys.<ns>@<owner>`, new.** One per
generation, signed by its minter under its own
[`EnvelopeType`](#103-an-envelope-says-what-it-is-for-and-a-verifier-says-what-it-wants-2026-08-15).
Id first, reserved marker in the middle, namespace last — the same shape a
`__ck` conveyance uses — parsed by splitting on the **first** occurrence of the
marker, so a multi-segment namespace survives where `AtKey.fromString`'s
last-dot cut would not. The leading `__` keeps it invisible to an
unauthenticated scan, which is the property that forces the summary to exist at
all: a peer structurally cannot enumerate these, and exposing them so it could
would leak which namespaces — which apps — an atSign uses.

The marker carries **double** underscores because a namespace segment could
legitimately be the word `nskeys`, and because every other reserved token in
this subsystem says "protocol vocabulary, not your data" the same way.

### 104.6 Advisory has to be structural, not documented

The lock stays because duplicate minting is not a coincidence here. The heal in
ruling 8 above has a **correlated trigger**: several enrollments starting after
a revocation all discover the same unanswerable pull at the same moment, so
they all retire and all re-mint. That is a thundering herd by construction, and
it scales with the number of devices.

What makes keeping it safe is that its correctness stops mattering. The stolen
release of 104.1, the ttl question of 104.9, a network blip on `_take` that is
not contention at all — each degrades to *one extra generation* rather than to
broken exclusion or an atSign that cannot mint.

⚠️ **But "helpful, not dispositive" decays unless the shape enforces it.**
Today's call site is `if (!await _take(lockKey)) return null;`, which reads
identically whichever it is, and `mintAndPublish` currently **throws** when it
loses the lock and finds nothing published — dispositive behaviour inside a
method whose own doc calls losing the race a resolution. The
lost-it-and-still-nothing-there-so-mint-anyway path must exist and must have
its own test, or the next reader reasons from the call site and it becomes a
hard lock again.

`MintLock` therefore serves **two policies from one mechanism**: it reports one
fact — somebody else holds it — and what that means is the caller's. The root
reads it as "do not mint"; the nskey reads it as "mint anyway if nothing is
there". That is the separation, and the class doc has to say so, because it is
also why item 18 still has to be fixed: one of the two callers is still
dispositive.

### 104.7 The heal is additive, and that is a correctness property

A healer that scans the log, gets nothing back — a failed scan, a partial
result, a namespace it lacks access to — and then writes what it found would
**destroy a working advertisement**. The heal would break the thing it exists
to repair.

So the healer may **add** any generation it finds, and may **drop** an entry
only when it has positively read that generation's record carrying
`status: retired`. It can never drop for absence. A failed or partial scan then
degrades to "no change" by construction rather than by a guard someone has to
remember to write, and both operations stay monotone, which is what keeps
concurrent healers convergent.

It reads the log from the **atServer**, not the local store: that is the only
place all enrollments' generation records are certainly present, and a heal
computed from a stale local view is how a just-minted generation gets left out
of the summary it was minted for.

### 104.8 Considered and rejected

- **Senders enumerate the generation records directly, and no summary exists.**
  Genuinely removes the shared write. **Rejected** because a `public:__` key is
  revealed only by `showhidden`, so a peer cannot enumerate them — and changing
  that leaks the atSign's namespace inventory, which is the property the
  double-underscore naming was chosen for.
- **At most one active entry per `(alg, use)`, with the healer picking a
  winner.** **Rejected**: choosing a winner under contention is the
  coordination this ruling removes, wearing the heal's clothes.
- **An explicit "current" marker in the summary.** Same objection, plus a field
  in a record whose format otherwise does not change at all.
- **Retirement recorded only in the summary.** **Rejected** because it breaks
  convergence: the summary would stop being a pure function of the log, so two
  healers with different views of it write different bytes.
- **Deleting a generation's record to retire it.** **Rejected**: it loses the
  *fact* of the retirement, so a healer holding a cached view can re-add it,
  and it loses the record of which generations ever existed.
- **A healer that advertises only generations it can itself open.** The obvious
  answer to the advertised-versus-held gap, and it is **disqualified rather
  than merely worse**: every healer would then write a different summary, which
  destroys the convergence the whole model rests on.
- **A lock on the heal.** **Rejected**: the value converges, so racing healers
  cost redundant writes and nothing durable.

### 104.9 Measured — the ttl does not free the lock, and gkc ruled that an atServer defect

**Measured live against `at_virtual_env:local` on 2026-08-16**, because this
started as a hypothesis read off at_server source and the local at_server tree
is not the build the virtualenv ships.

The probe: create an immutable record with a 20s ttl; attempt the same create
five times while it is live; attempt once more 1ms past the expiry instant. The
expiry instant is computed from when the FIRST create's response *returned* —
the atServer committed at or before that moment, so `returnedAt + ttl + 1ms` is
guaranteed past the true expiry rather than merely near it.

```
t=0.000s   create #1              -> ACCEPTED
t=1.016s   create (live)          -> refused: Immutable records may not be updated
t=5.013s   create (live)          -> refused    <- five independent positive
t=10.015s  create (live)          -> refused       controls, each naming the
t=15.016s  create (live)          -> refused       interlock rather than an
t=19.016s  create (live)          -> refused       unrelated failure
llookup:meta: while live -> {"expiresAt":"…11:08:47.456Z","status":"active","ttl":20000,"immutable":true}

t=20.017s  create (expiry+1ms)    -> refused: Immutable records may not be updated
llookup:meta: after expiry -> data:null
+5s … +150s past expiry           -> refused, every 5s, all 30 attempts
```

⚠️ **The record is simultaneously GONE and BLOCKING.** `llookup` says
`data:null` — to every reader it does not exist — while the immutability check
still refuses a create. The two answers disagree about whether the record is
there.

That is the source asymmetry confirmed on the wire.
`AbstractUpdateVerbHandler` refuses on `keyStore.getMeta(atKey)?.immutable ==
true`; `HiveAtKeyValueStore.getMeta` delegates to `get`; and `get` has **no
expiry filter** — a comment describing one sits there with no code under it,
while `_isKeyAvailable` guards the lookup and enumeration paths.

⚠️ **What the number bounds.** 150s past a 20s expiry is 7.5× the ttl, and it
bounds the cooldown at **more than 150s**. It does *not* establish that the
record blocks forever — nothing was measured past that point, and a sweep may
free it later. A floor was measured, not a kind.

**gkc ruled this an atServer defect (2026-08-16), not a constraint to design
around.** A ttl on an immutable record has no purpose other than making it
re-creatable; `llookup` already agrees the record is gone; and the fix is
small — the update handler's existing-metadata read needs the same availability
check the lookup path already applies.

**What it cost.** A design where the winner never deletes the lock and lets the
ttl release it — otherwise the best shape available, because no release means
no *stolen* release and
[14.19](../implementation-plan.md#1419-small-items-raised-2026-08-12-and-not-yet-acted-on)
item 18 ceases to exist rather than being fixed — did not work on this
atServer. The release was mandatory, and item 18 came back with it.

### 104.10 FIXED in at_server the same day, and re-measured on the wire

Branch `gkc-expired-immutable-blocks-create`, cut from `origin/trunk`.

**gkc ruled the shape, and it is better than the three that were offered:
an update that finds an expired record DELETES it (`skipCommit: true`) before
proceeding.** Not "teach each reader to look past it" — the store genuinely
ends up empty, so the cache-metadata validation, the immutability check and the
keystore's own merge all see the absence a reader already saw.

⚠️ **Deleting turned out to be necessary rather than merely tidier.** Nulling
the metadata inside the verb handler was tried first and was **not enough**:
`HiveAtKeyValueStore.putAll` re-reads the record for itself
(`if (await exists(key)) existingData = await get(key)`) and merges it through
`AtMetadataBuilder`, so an expired record still supplied `immutable`,
`createdAt` and `version` to the record replacing it. A unit test caught it —
the re-created record came back `immutable: true` without asking.

⚠️ **And `AtMetadataBuilder` carried a comment the fix falsified**: *"Note:
this condition never occurs right now but we will leave it here for safety's
sake"*, above the immutable-stickiness branch. It never occurred **because the
update handler refused every such update**. The fix makes it reachable.

`skipCommit` because nothing observable changes — the record stopped being
visible when its ttl elapsed, so a commit entry would sync the deletion of
something no peer ever saw.

**Expiry only, deliberately not the server's general is-this-active test**,
which also answers false inside a record's ttb. A not-yet-born record has not
stopped existing and must still refuse a second create.

**Measured, at_server:** `update_verb_test.dart` 74/74; the whole
at_secondary_server unit suite **958/958**; the functional pack **221/221**
`EXIT=0`; `dart analyze lib test` exit 0. Isolated by mutation — removing the
delete gives exactly **2** failures, both expired-record tests, while the
not-yet-born test stays green.

**Re-measured on the wire**, same probe as above against a rebuilt
`at_virtual_env:local`:

```
t=1s … 19s  create (live)       -> refused, five times   (the interlock intact)
t=20.019s   create (expiry+1ms) -> ACCEPTED              (was refused, >150s)
llookup before -> createdAt 11:42:10.879, version 0
llookup after  -> createdAt 11:42:30.909, version 0
```

The fresh `createdAt` and `version: 0` are what prove the *delete* rather than
just a relaxed check: the replacement is a new record, not a merge with a
corpse.

⚠️ **An observation recorded here as undiagnosed, and diagnosed later the same
day.** The first functional run failed one unrelated test —
`create_update_key_test.dart`, on `updatedAt >= keyUpdateDateTime` — and the
second run passed it: 1 failure in 2 runs. A clock-skew explanation was
proposed and **disproven by measurement**: the container runs ~317ms *ahead* of
the host (bounded by `docker exec` latency), and that assertion needs the
server to be *behind*.

✅ **Resolved 2026-08-16, after this ruling was written.** The assertion
compared a client-captured timestamp against a server-generated one with zero
tolerance — two clocks, so it measured the environment rather than the product.
Measuring the margin rather than re-running the outcome is what settled it: 60
iterations put the gap at **0–6ms, with 8 of 60 landing on exactly zero**. It
was rewritten to compare the second update's `updatedAt` against the **first
update's**, both produced by the server, which is what `AtMetadataBuilder`
actually guarantees and leaves a full round trip of headroom. The rewrite rode
in at_server `77091f98` on
[PR #2751](https://github.com/atsign-foundation/at_server/pull/2751), committed
1h38m after this ruling — so anything citing "cause unknown" from this section
is reading a snapshot, not the state.

---

## 105. The nskey mint elects a winner, and an atServer defect blocks the clean shape (2026-08-16)

**In brief:** *the election protocol, the expired-immutable-record defect, and the order of work*

Supersedes [ruling 104](#104-the-nskey-mint-stops-needing-a-winner-2026-08-16),
made the same day. 104 removed the *need* to coordinate; this one satisfies the
coordination requirement directly and keeps a single nskey record. **The log
model is held in reserve, not discarded** — the decision between them is
deferred until the design below is built and measured.

### 105.1 The requirement, stated

**If enrollments A, B and C all decide they need to mint, only one of them
eventually does.**

Worth writing down because it had never been stated. Every earlier discussion
argued about mechanisms — the lock, its ttl, its release — without an agreed
property to hold them to, which is how "is item 18 worth fixing" stayed
unanswerable for two sessions.

⚠️ **It is a requirement only under the single-record model.** Under the log,
two mints are two records and nothing is lost, so the same sentence would be an
optimisation. Stating it *is* therefore a lean toward keeping one record, and
that is what makes ruling 104 held rather than in flight.

### 105.2 The protocol gkc specified

1. A, B and C each decide they need to mint.
2. Each **reads**, and stops if it turns out it does not need to mint.
3. Each attempts the lock — possibly at different times, but within a bounded
   window.
4. Only the winner proceeds. The losers do **not** mint.
5. The winner **re-checks under the lock** that it still needs to mint, because
   somebody may have finished between step 2 and step 3.
6. The winner **does not delete the lock**; the ttl releases it.

The reframing that makes step 6 right rather than wasteful: **this is not a
mutex, it is an election token with a cooldown.** Holding it for the whole ttl
means "an election happened recently, do not hold another one". The only case
where a second election is wanted inside the window is *the winner failed*,
which is exactly what the ttl exists to bound — so in the success case the
cooldown costs nothing. And it makes 14.19 item 18 **cease to exist** rather
than be fixed: no release, no stolen release.

**gkc ruled the loser's behaviour:** re-read once, adopt a key if one is there,
otherwise **fail**. A waiting `put` fails loudly rather than hanging on another
device's crash, and the retry is the next client start, which is where minting
is triggered from anyway.

### 105.3 Step 6 does not work on today's atServer, and that is a defect

[104.9](#1049-measured--the-ttl-does-not-free-the-lock-and-gkc-ruled-that-an-atserver-defect)
has the probe. An expired immutable record keeps refusing a create for **more
than 150s past a 20s ttl**, while `llookup` reports it `data:null` — the record
is simultaneously gone and blocking.

**gkc ruled this an atServer defect, and ruled the fix belongs in
`AbstractUpdateVerbHandler`** rather than at the store — making `get` filter
expiry is what its own comment says was intended and would make lookup and
update agree everywhere, but the internals that legitimately need to *see*
expired records (`deleteExpiredKeys`, compaction, migration) were never
enumerated, and that is wider than this needs.

**gkc ruled the client waits for it.** Building the release-based version first
would work today and be thrown away; building the never-delete version against
an unfixed atServer cannot be tested at all. So the order is: fix at_server,
rebuild `at_virtual_env:local`, then build the client.

✅ **The first two are DONE** — see
[104.10](#10410-fixed-in-at_server-the-same-day-and-re-measured-on-the-wire).
The fix is on `gkc-expired-immutable-blocks-create` off `origin/trunk`, the
image is rebuilt, and expiry+1ms is accepted on the wire. **Step 6 of the
protocol is therefore available**: the winner never deletes the lock, the ttl
releases it, and item 18 ceases to exist on any path that uses it that way.
⚠️ It is not merged — an unfixed atServer still behaves the old way, so a
client built on ttl-only release is correct only against a server carrying
this.

### 105.4 Three client-side things the protocol needs, none of which exist

Found while checking whether the protocol holds against the tree as it stands.

1. **Both reads must be remote, and the one that matters is not.** Every read
   in the nskey subsystem that must see another party's write passes
   `useRemoteAtServer = true` — **eight** sites in `pq_signing_chain.dart`,
   plus the root's `publishedRoots` — and `current_ck_pointer.dart` passes
   `false` *explicitly*, because that one is the client's own pointer.
   `published_nskey_key_ring.dart:450`, the advertisement read behind
   `currentPublic`, carries no options at all, so it is local-first and lags
   sync.
   ⚠️ **Two numbers here were wrong when first written, and a cold read caught
   both.** It said "ten sites" (there are eight — ten was the total across the
   whole subsystem, which double-counts `publishedRoots` and includes the
   `= false` site the same sentence lists separately), and it called `:450`
   **"the only read with no options at all"**, which is false:
   `ck_manager.dart:248` and `symmetric_aes_gcm_provider.dart:250` are
   optionless too. Those two are content-key conveyance reads rather than
   advertisement reads and are plausibly right as local-first — but they are
   out of scope **by argument, not by absence**, and the original sentence
   would have had someone stop one file early.
   ⚠️ **This is not an oversight.** `currentPublic` deliberately serves two
   callers through one read — a sender fetching a *peer's* advertisement, where
   local-first plus the 15-minute `advertisementTtl` cache is right, and a
   minter asking whether its *own* atSign already has a key, where it is wrong.
   Its dartdoc celebrates that unification as what makes "one verify path,
   same-atSign and cross-atSign" true rather than aspirational. The elegance
   and the defect are the same line.
2. **Step 5 does not exist for the nskey.** `_mintUnderLock` re-reads the
   record under the lock; `_mint` does not. The root has the winner's re-check
   and the nskey has never had one.
3. **The requirement still fails on a ttl overrun, and the bounded window in
   step 3 does not cover it.** A takes the lock at T0, is still minting at
   T0+ttl, the lock expires, B wins the next election, re-checks, A has not
   published yet, B mints too. The window bounds when the three *attempt*, not
   how long the winner *takes*. The fix is for the holder to carry its lease
   and refuse to publish once it is spent, so a slow A abandons rather than
   racing B — which turns "two mints" into "one mint, by B", the requirement.

### 105.5 What is held, and what would revive it

Ruling 104's log model stays written up in full. It is revived if the lock-only
design, once built, fails to hold the requirement in practice — the residual
risks being a suspend landing between the lease check and the publish, and the
cooldown a crashed winner imposes on an atSign. Neither is measurable until the
client exists, which is why the decision is deferred rather than argued.

⚠️ **`mintLockTtl`'s dartdoc is false as written** — "a crash backstop, not a
budget" — and is corrected in whichever commit first touches this path,
regardless of which model wins.
