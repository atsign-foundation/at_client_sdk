# ADR 0002 — D1 is single-tier `nskey`; `at/pqmls` is D2

- **Status:** Accepted (2026-06-25). **Supersedes [ADR 0001](0001-d1-simplicity-tiers.md)**.
- **Context docs:** [`docs/crypto-roadmap.md`](../crypto-roadmap.md),
  [`docs/pq-secret-push.md`](../pq-secret-push.md),
  [`docs/pq-atsign-key-distribution.md`](../pq-atsign-key-distribution.md).

## Table of contents

- [Context](#context)
- [The corrected key model](#the-corrected-key-model)
- [Decision](#decision)
- [Consequences](#consequences)
- [Alternatives considered](#alternatives-considered)

## Context

[ADR 0001](0001-d1-simplicity-tiers.md) split D1 into two tiers — `nskey` (default) and an
`at/pqmls` provider (opt-in) — on the premise that **forward secrecy / per-device revocation
require the group (MLS-style) model**, and that a copyable shared key and per-device keys are
mutually exclusive ("instant offline access for a future device requires a copyable shared
key… you cannot have both").

Decisions taken **since** 0001 dissolve that premise:

- **Per-APKAM delivery + push** (the `enroll:listfornamespace` verb): a secret is delivered to
  every authorised APKAM keypair, definitively and proactively. A *future* device gets the key
  **pushed** to it — instant, offline — regardless of tier. So "future device just works" no
  longer argues for a copyable-shared-key tier. (See `pq-secret-push.md`.)
- **`nskey` is a KEM wrapper, not the data key.** Data is encrypted under a symmetric
  **content/epoch key (CK)**; the CK is X-Wing-encapsulated to a per-`(atSign, namespace)`
  `nskey`. **Neither model encrypts data per-device** — both use symmetric data keys delivered
  per-APKAM. So 0001's "copyable shared key vs per-device keys" was a **false dichotomy**.

With those corrected, `nskey` already gives D1 **coarse forward secrecy** (content-key rotation)
and **post-compromise security** (nskey-keypair rotation); what `at/pqmls` adds is *stronger* FS,
not FS itself. The genuine `at/pqmls`/MLS delta is **robust/per-message FS, O(log n) scale, and
membership decoupled from namespace authorisation** — all D2 concerns. **There is no D1-internal
Tier-1/Tier-2 boundary left.**

## The corrected key model

Stated explicitly so it is not re-derived wrongly (it was, repeatedly, while reaching this
ADR):

- **`nskey` is an asymmetric X-Wing KEM keypair** — the thing we *encapsulate symmetric keys
  to*, not the thing that encrypts data. Per namespace there are **two**: a **self nskey**
  (**not published**; Alice encapsulates her *own* content keys to it; her authorised clients
  hold its private) and a **public nskey** (**published world-readable**; external senders
  encapsulate content keys to it; Alice's authorised clients hold its private). Both convey
  symmetric CKs; neither encrypts application data directly.
- **Data is encrypted under a symmetric content/epoch key (CK)** with AES-256-GCM. The CK is
  X-Wing-encapsulated to an `nskey`; holders of the nskey private unwrap the CK.
- **Two delivery levels, very different costs:**
  - *Convey the nskey private* to each authorised APKAM keypair — **per-APKAM, O(n), rare**
    (the push + `enroll:listfornamespace` substrate; pull as backstop).
  - *Rotate the symmetric CK* — wrap the new CK **once** to the shared nskey; every authorised
    client unwraps with the shared private — **O(1), frequent.** This is the FS lever.

## Decision

**D1 ships as a single tier: `nskey`.** Forward secrecy is **in scope for D1** as a *policy*,
not a separate tier:

- Coarse FS = **rotate + delete the symmetric content/epoch keys** over the stable nskey
  KEMs. Routine rotation is cheap (O(1) wrap to the shared nskey). FS strength is **coarse**
  and bounded by the stable shared nskey private remaining a standing decryption capability
  for any wrapped-CK that persists — so **deletion discipline is the FS TCB**.
- Per-APKAM **future-data revocation** = rotate excluding the revoked keypair (the expensive
  lever: a fresh nskey conveyed per-APKAM, since the shared-nskey O(1) path can't exclude a
  holder of that private).

**The forward-secure `at/pqmls` provider is D2, not a D1 tier.** Ratcheted per-APKAM leaves (no
standing master key → robust/per-message FS), TreeKEM (O(log n) churn), and groups whose
membership is decoupled from namespace authorisation are the MLS engine's job. The **same
per-APKAM secret-sharing substrate** underpins both `nskey` (now) and MLS (later); only the
labelling changes — what 0001 called "D1 Tier 2" is **D2's first increment**.

## Consequences

**Positive**
- One D1 data path — the **`nskey` data path** (`at/nskey` conveys the content key,
  `at/symmetric/AES/GCM` encrypts the data) — plus `legacy`; no `SecureGroup`, `KeyPackage`,
  membership commits, or single-owner lock in the app's face for D1.
- Legacy developer experience preserved — a future device "just works" via push; PQ +
  namespace scoping + per-namespace blast radius by default.
- Forward secrecy is **available** in D1 (coarse, cheap) rather than withheld to D2 — a strict
  improvement over legacy's none, for namespaces that opt into rotation.

**Negative / accepted**
- D1 FS is **coarse** and rests on deletion discipline over **all** CK conveyances (self and
  inbound alike) + the stable shared nskey private being a standing capability. The uniform
  cut-CK → `at/nskey` → `at/symmetric/AES/GCM` flow makes self and inbound conveyances the same
  kind of deletable artifact. Robust/per-message FS, large-group O(log n) scale, and
  decoupled-membership groups require D2.
- **Inbound (cross-atSign) data flow is structurally identical to self, but inbound FS is
  harder to *achieve unilaterally*.** Inbound uses the SAME flow as self: the sender (`@bob`)
  cuts a CK, delivers it **once** as a discrete `at/nskey` conveyance (encapsulated to Alice's
  published public nskey), and writes data under `at/symmetric/AES/GCM` by kid — there is **no**
  per-message inline-wrapped CK that "persists with the message." The same coarse-FS lever
  (rotate + delete CKs and their `at/nskey` conveyances, bounded by the standing nskey private
  as the TCB) applies to inbound. The residual is that forward secrecy across two atSigns is
  inherently **bilateral**: (1) the inbound CK is cut by `@bob` on **his** cadence, so Alice
  cannot force an FS cut finer than the sender's rotation; (2) the authoritative `at/nskey`
  conveyance lives in a record **owned by `@bob` on bob's atServer** — Alice holds only a
  synced cached replica, so she can purge her cache but cannot unilaterally delete bob's copy,
  which her stable published-nskey private re-decapsulates. For **self**, Alice is both
  endpoints — she cuts the CK and owns the authoritative conveyance + cache — so FS is
  unilateral and complete. Closing inbound FS depends on the sender's cooperation, or the
  heavier published-nskey rotation lever, or D2 (this bilaterality is normal for any FS system,
  not specific to nskey).
- **Doc cascade (completed in this change):** `crypto-roadmap.md`'s "D1 — two tiers" framing and
  the milestone reframing were rewritten single-tier; the catalogue/flows "nskey shapes" were
  corrected to "`nskey` is a KEM wrapping symmetric content keys" (they previously read as if
  data were encrypted directly to the nskey).

## Alternatives considered

- **Keep the two D1 tiers (ADR 0001)** — rejected: the distinguishing property (FS) is a
  rotation *policy* of the single `nskey` data path, not a separate provider; the only genuine
  delta (fine FS, scale, decoupled membership) is D2. Two D1 tiers split on the wrong axis.
- **Withhold forward secrecy entirely to D2** — rejected: `nskey` gives coarse FS cheaply
  (O(1) epoch-key rotation); no reason to deny D1 a strict improvement over legacy.
- **The 0001 "copyable shared key vs per-device keys" framing** — rejected as a false
  dichotomy: data is encrypted under symmetric keys delivered per-APKAM; there are no
  per-device data keys, and a future device is served by push, so instant/offline access and
  per-APKAM revocation coexist.
