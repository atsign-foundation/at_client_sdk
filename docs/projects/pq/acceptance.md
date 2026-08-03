# acceptance.md — Acceptance tests (given / when / then) + impl/verify steps

**Status:** acceptance catalogue (current). Lives in `docs/`.
**Purpose:** the single ordered, testable burn-down target for the D1
post-quantum work — the full use-case list **A1.x–A5.x** (PQ-native greenfield)
and **B0.x–B5.x** (retrofit / mixed), each as **Given / When / Then** with
concrete at-keys, the protocol **Steps**, and the **impl/verify** harness.

> **Reconciled with the 2026-08-03 ruling.** `pqpublickey` is gone: the
> atSign-level key is `public:pq_signing_root@<atSign>`, it signs and verifies
> only, and no scenario encapsulates to it. Cold-start has no PQ target and fails,
> so PQ sharing requires the recipient to have used or authorised the namespace.
> See [decisions.md section 18](decisions.md#18-pqpublickey-becomes-the-user-owned-signing-root-2026-08-03).

## Table of contents

- [0. Purpose, scope & how to read this doc](#0-purpose-scope--how-to-read-this-doc)
- [1. Notation, state model & key objects (test vocabulary)](#1-notation-state-model--key-objects-test-vocabulary)
- [2. A1 · Onboard a new atSign (PQ-native)](#2-a1--onboard-a-new-atsign-pq-native)
- [3. A2 · Enrollments (a new enrollment joins)](#3-a2--enrollments-a-new-enrollment-joins)
- [4. A3 · E2EE within one atSign (self data) + self notification](#4-a3--e2ee-within-one-atsign-self-data--self-notification)
- [5. A4 · E2EE across atSigns (shared data) + cross-atSign notification](#5-a4--e2ee-across-atsigns-shared-data--cross-atsign-notification)
- [6. A5 · Rotation & revocation (new world)](#6-a5--rotation--revocation-new-world)
- [7. B0 · Prerequisite — atServer upgrade](#7-b0--prerequisite--atserver-upgrade)
- [8. B1 · Upgrade an existing (pre-PQ) atSign — the retrofit scenarios](#8-b1--upgrade-an-existing-pre-pq-atsign--the-retrofit-scenarios)
- [9. B2 · Legacy retirement & lockout](#9-b2--legacy-retirement--lockout)
- [10. B3 · Mixed-PQ within one atSign](#10-b3--mixed-pq-within-one-atsign)
- [11. B4 · Mixed-PQ across atSigns](#11-b4--mixed-pq-across-atsigns)
- [12. B5 · Retrofit edge cases](#12-b5--retrofit-edge-cases)
- [13. Cross-cutting acceptance (applies to all flows)](#13-cross-cutting-acceptance-applies-to-all-flows)
- [14. Test harness & impl/verify mapping](#14-test-harness--implverify-mapping)

---

## 0. Purpose, scope & how to read this doc

Each use case carries **both** the given/when/then acceptance rows **and** the
step-sequence that produces them.

**Read order.** Part A (PQ-native greenfield, sections [2](#2-a1--onboard-a-new-atsign-pq-native)–[6](#6-a5--rotation--revocation-new-world))
is specified and built **before** Part B (retrofit / mixed,
sections [7](#7-b0--prerequisite--atserver-upgrade)–[12](#12-b5--retrofit-edge-cases)). [Section 13](#13-cross-cutting-acceptance-applies-to-all-flows)
states invariants that hold across every flow; [section 14](#14-test-harness--implverify-mapping)
maps each UC cluster to its test layer and owning project.

**Lane discipline — what this doc does NOT do.** This doc states *what must be
true* and *how to test it*; it does not re-explain *how the mechanism works*.

| For…                                              | See…                                  |
|---------------------------------------------------|---------------------------------------|
| Mechanics (key shapes, providers, substrate, verbs, at_chops primitives) | `design.md` — "do NOT re-explain the design here; reference it" |
| Which project ships each UC, sequencing, effort   | `implementation-plan.md`              |
| The WHY behind a ruling, the decisions, and timeline | `decisions.md`                        |
| The high-level WHAT (D1/D2, migration philosophy) | `roadmap.md`                          |

Substrate mechanics are cited to `design.md`; substrate-related rulings to
`decisions.md`.

## 1. Notation, state model & key objects (test vocabulary)

This is the shared vocabulary every UC below draws on. It is deliberately thin —
for the authoritative key-shape / provider / substrate mechanics see `design.md`;
here these objects exist only as test vocabulary.

**Actors.** `@alice`, `@bob` are atSigns. `alice1`, `alice2`, `alice3` are
**APKAM keypairs** of `@alice` (one per keyfile/install) — the recipient/identity
unit is the **APKAM keypair**, not a running client process: every process that
shares a keyfile/keychain shares that one APKAM keypair. Likewise `bob1`, `bob2`.
`aliceS` / `bobS` are the atServers.

**1:1:1 cardinality** (decision #F — see `decisions.md`): each **enrollmentId**
binds to exactly **one** APKAM keypair and exactly **one** key package; there is
**never** more than one keypair under an enrollment. The atServer enrollment
record stores a **single** `apkamPublicKey` + a `signingAlgo` (`rsa2048` |
`mldsa65`). A separate install is its **own distinct enrollment**, not a second
keypair under an existing one. A *copied keyfile* shares the one keypair (one
recipient); it does not create a second.

**Per-enrollment state** — the row unit is one enrollment (= one APKAM keypair,
per keyfile/install):

| Col       | Meaning                                                                                                   |
|-----------|-----------------------------------------------------------------------------------------------------------|
| `enr`     | the enrollment id (`E1`, `E2`, …) — one APKAM keypair                                                      |
| `APKAM`   | auth keypair held: `rsa` (legacy) · `pq` (ML-DSA / `mldsa65`) · `both`                                     |
| `root⁻¹`  | holds the atSign-level **signing root** private half? Only fully privileged (`rw *` + `__manage`) enrollments do |
| `nskey⁻¹` | holds the namespace's **one** nskey private; it **decapsulates content keys (CKs)** for both the owner's own data and inbound shares — it does not decrypt application data |
| `KP`      | its X-Wing **key package** (`kid` = `kpid`) is registered in the enrollment record? (**one key package per enrollment**, never published) |

**Per-atSign / server state:**

| Col           | Meaning                                                                                              |
|---------------|------------------------------------------------------------------------------------------------------|
| atSign        | `legacy` · `pq-native` · `mixed`                                                                      |
| `aS`          | atServer: `pq` (new verbs) · `legacy`                                                                 |
| `publickey`   | legacy RSA encryption pubkey published?                                                               |
| `pq_signing_root` | atSign-level user-owned **signing** root published (immutable)?                                   |
| `nskey.ns`    | namespace `ns` nskey state: `—` (never used, so no nskey) · `<kid>` (minted and published at `public:__nskey.<ns>@owner`; the kid names the current generation) |
| `ready`       | PQ-readiness marker, **per (atSign, namespace)** (+ an atSign-level marker for the signing root): `n-r` · `ready` |

**Key objects** (shapes defined in `design.md`; named here for test wiring):

- `public:pq_signing_root@alice` — the atSign-level, **user-owned signing root**
  (ML-DSA-65); no namespace; **immutable** once written, which is what stops two
  privileged enrollments minting two roots. It signs and verifies only, and never
  appears in a key-transport path. Value is
  `{"v": 1, "keys": [{"alg": "ml-dsa-65", "pub": "<base64>"}], "successor": null}`;
  `keys` is a list because the record cannot be updated, and `successor` reserves a
  revocation chain that D1 does not implement. Only an enrollment with `rw` on `*`
  and `__manage` may create it; the private rides that app's `.atKeys` and is
  conveyed to the other fully privileged enrollments over the substrate. Published
  plain (not `_`-hidden) because it is meant to be found and audited. See
  [`decisions.md` section 18](decisions.md#18-pqpublickey-becomes-the-user-owned-signing-root-2026-08-03).
- **PQ APKAM keypair** — ML-DSA (`mldsa65`) signing key for auth; one per
  enrollment; its public half is the enrollment record's single `apkamPublicKey`.
- **Namespace key (`nskey`)** — **one** X-Wing KEM keypair per
  `(atSign, namespace)`, wrapping symmetric content keys (never encrypting
  application data directly). It is the recipient key for **both** directions:
  Alice encapsulates her **own** CKs to it for self data, **and** external senders
  encapsulate CKs to it when sharing with her. Its private half is minted fresh
  and conveyed to each authorised enrollment as a Secret over the substrate (never
  derived). The public half is **published eagerly** — written at mint, always:
  - `public:__nskey.<ns>@alice`, an APKAM-signed envelope carrying
    `{nskeyKid, publicKey}`. The leading underscore keeps it out of every scan
    (`showhidden` reveals only `public:__`, and an unauthenticated scan ignores it
    altogether) while `plookup` still serves it on an exact name, cross-atSign — so
    the namespace's *existence* is not enumerable.
  - The record is **mutable**: rotation overwrites it. Create and rotate serialise
    behind the short-ttl immutable lock `_nskeylock.<ns>@alice`. Earlier generations
    stay live on the private side, named by `nskeyKid` on each conveyance.
  - There is no owner-only stage and no promotion step
    ([`decisions.md`](decisions.md) section 13).
- **X-Wing key package** — the per-enrollment X-Wing recipient keypair a sender
  `pqSeal`s to (`kpid` = the kid of its X-Wing public half). Registered in the
  enrollment record alongside the ML-DSA public key; **never published**;
  discovered only via `enroll:listns`. Private half never leaves the
  keyfile.
- **`appMetadata.providerId`** routes a reader to a provider; a value with **no**
  `providerId` defaults to **legacy**. `appMetadata` carries **no `ns` field**:
  - `at/nskey/XWING/AES/GCM` → `{providerId, recipientKind, ckKid, nskeyKid}` — a
    CK-conveyance record: a CK X-Wing-sealed to the nskey. `recipientKind` is
    `nskey` and nothing else; self and inbound both seal to the one nskey. The
    `root-pqpublickey` variant is withdrawn along with the cold-start KEM.
  - `at/symmetric/AES/GCM` → `{providerId, ckKid, iv}` — application data
    AES-256-GCM under a CK, cited by `ckKid`.
  The umbrella for `at/nskey` + `at/symmetric/AES/GCM` is the **nskey data path**.

**atServer PQ capabilities** (Part A and B both assume `aS = pq` unless stated):
the **existing** immutable write (`Metadata.immutable`) for mint-once, plus —

- **PQ (ML-DSA) APKAM auth** — verify against the **single** `apkamPublicKey`
  recorded for the enrollment, using a **record-authoritative** `signingAlgo`
  (`rsa2048` | `mldsa65`): the server's `_getSigningAlgoType` reads the **record**
  `signingAlgo`, **not** the client-supplied wire value.
- **`enroll:listns:<ns>`** — the gated discovery verb (requester must
  hold ≥`r` on `<ns>`), returning a **flattened**
  `[{enrollmentId, access, apkamPubKey, metadata}]` list — **no** nested
  `apkam[]` array.
- **`EnrollParams.metadata`** — an opaque `Map<String,dynamic>` riding the
  `enroll:request` JSON tail (no grammar change); the server stores and returns
  it. There is **no** `enroll:metadata` verb and no post-enrollment metadata write.
- **Retirement** — `enroll:revoke` + the enrollment-**expiry timer**. There is
  **no** per-APKAM-key delete and no TTL/usage eviction of APKAM keys.

The substrate's `<msgId>.<kpid>.__ssenv.<ns>@owner` delivery envelope, its
`pqSeal`/verify-before-decrypt safety, and the push/pull primitives are defined
once in `design.md`; UCs below reference them by name.

---

# Part A — The new world (PQ-native, PQ-capable atServer)

## 2. A1 · Onboard a new atSign (PQ-native)

### UC-A1.1 — First-enrollment CRAM onboard is PQ-native

- **Given:** `@alice` unactivated; `aliceS = pq`; CRAM activation secret in hand; no keys exist.
- **When:** `alice1` runs CRAM onboarding.
- **Steps:**
  1. CRAM-authenticate with the activation secret.
  2. Mint the **PQ APKAM** keypair (ML-DSA / `mldsa65`); register its public half
     as enrollment E1's single `apkamPublicKey` + `signingAlgo = mldsa65`.
  3. Mint the atSign-level **ML-DSA-65 signing root**; **immutable-create**
     `public:pq_signing_root@alice` carrying
     `{"v": 1, "keys": [{"alg": "ml-dsa-65", "pub": "…"}], "successor": null}`;
     hold the private half locally. E1 is a first enrollment and so fully
     privileged, which is what entitles it to create the root at all.
  4. Mint E1's **X-Wing key package** and register it in E1's enrollment record
     (private half stays in the keyfile; **not** published).
  5. Persist AtKeys (PQ APKAM private + signing-root private + key-package private).
  6. **Verify**: re-authenticate using the PQ APKAM key (proves the server accepts PQ auth).
  7. Legacy interop (config flag, **default off**): publish `public:publickey@alice`
     (RSA) **only if enabled**, for legacy-peer inbound.
- **Then:**
  - `alice1.APKAM = pq` and it authenticates via PQ APKAM; no RSA APKAM key required.
  - `public:pq_signing_root@alice` exists, is immutable (a second create is
    **rejected**, which is what prevents two privileged enrollments minting two
    roots), and `alice1.root⁻¹ = ✓`.
  - The root is a **signing** key. Nothing encapsulates to it, at onboarding or
    ever.
  - `alice1.KP = ✓`, registered in E1's record (not published; discoverable only via
    `enroll:listns`).
  - **No `selfEncryptionKey` minted** — self data uses the nskey data path. There is
    no cold-start fallback to an atSign-level key; a namespace with no nskey simply
    has no PQ path.
  - Readiness may be `ready` (no legacy enrollments exist).
  - **Legacy `publickey@alice` is absent by default** (flag off → a legacy peer's
    send is unsupported, see [UC-B4.2](#112-uc-b42--legacy-alice-receives-from-pq-bob-the-interop-question)).
    With the flag on it is present.

| enr | APKAM | root⁻¹ | nskey⁻¹ | KP |
|-----|-------|--------|---------|----|
| E1  | pq    | ✓      | —       | ✓  |

- **Cross-ref:** [`decisions.md` section 18](decisions.md#18-pqpublickey-becomes-the-user-owned-signing-root-2026-08-03)
  (the signing root, and why there is no cold-start KEM);
  `decisions.md` ([Decision #1](decisions.md#numbered-rulings-14), legacy-peer interop flag).
- **Impl/verify:** project **ON-1** (see `implementation-plan.md`); harness
  `tests/at_functional_test` runLocal.sh (live CRAM onboard).

## 3. A2 · Enrollments (a new enrollment joins)

Start state for A2: `@alice` pq-native; `pq_signing_root` published; `alice1` (E1) online and fully privileged.

### 3.1 UC-A2.1 — New enrollment, approved by an online enrollment (PQ-safe enroll/approve)

- **Given:** `@alice` pq-native; `pq_signing_root` published; `alice1` enrolled (E1), fully privileged & online.
- **When:** `alice2` requests a new enrollment (E2) for namespaces `[app_1.my_apps]`; `alice1` approves.
- **Steps:**
  1. `alice2` mints its own **PQ APKAM** keypair; it puts its X-Wing
     **key-package** public half and any descriptive `EnrollParams.metadata` on the
     `enroll:request` JSON tail (single keypair, single key package), and sends
     `enroll:request`.
  2. `alice1` (approver) generates the `apkamSymmetricKey` and **encapsulates it to
     `alice2`'s key-package public half** taken from the request tail (X-Wing) —
     **not** RSA, and **not** to any atSign-level key. The direction is
     approver → enrollee precisely so that no atSign-level KEM has to exist; the
     approver is encapsulating to a key that arrived unauthenticated, which is
     trust-on-first-use gated by a person approving a named device.
  3. `alice1` approves E2; the server records `alice2`'s single `apkamPublicKey` +
     `signingAlgo` + key package + metadata for E2, and populates E2's `_apsk` from
     the enrollment record — where the value is a **root-signed envelope** rather
     than a bare key, signed by `alice1` with the signing root at approval time.
  4. `alice1` conveys the secrets E2 is authorised for:
     - the **signing-root private** rides the approval bundle (wrapped under
       `apkamSymmetricKey`) **only if E2 is itself fully privileged**; a
       namespace-scoped enrollment never receives it;
     - `nskey.app_1.my_apps@alice⁻¹` (authorised namespace only) is delivered by the
       **substrate push** — sealed (`pqSeal`) to E2's key package and put to
       `<msgId>.<kpid>.__ssenv.app_1.my_apps@alice`
       (`shareAllSecretsWithEnrollment(E2, approvedNamespaces)`).
  5. `alice2` consumes the envelope + bundle, decapsulates, verifies, persists AtKeys.
  6. `alice2` verifies PQ APKAM auth.
- **Then:**
  - Nothing in the conveyance path is RSA-wrapped (`apkamSymmetricKey` rides X-Wing),
    so the enrollment conveyance is not harvestable-now.
  - `alice2.APKAM = pq`, `nskey.app_1.my_apps@alice⁻¹ = ✓`,
    `nskey.app_2.my_apps@alice⁻¹ = ✗`, key package registered. `root⁻¹ = ✗` for a
    namespace-scoped E2 — the root is held only by fully privileged enrollments.
  - E2's `_apsk` value verifies against the signing root, so a reader can chain an
    advertised key back to the atSign's own anchor rather than to whatever the
    atServer served.
  - `alice2` authenticates PQ and decrypts `@alice`'s `app_1.my_apps` self data; an
    `app_2.my_apps` key request is refused.
  - E2's APKAM key is a distinct, individually-revocable record.

### 3.2 UC-A2.2 — Second host using the *same* keyfile (copied keyfile, E1)

- **Given:** `@alice` pq-native; `alice1` on E1; a second host runs against a *copy* of E1's keyfile (`alice1b`).
- **When:** the copy first runs.
- **Steps:**
  1. `alice1b` authenticates with E1's existing APKAM private (from the copied keyfile).
  2. It **reuses** the copied keyfile's PQ APKAM keypair and key package — it does
     **not** mint its own.
  3. Obtain `pq_signing_root@alice⁻¹` — present in the copied keyfile, else `requestSecret`.
- **Then:**
  - A copied keyfile **shares** its one APKAM keypair (and the key package's private
    half); the two hosts are the **same** enrollment = **one** recipient. Secrets
    already sealed to that key package are openable on both. (Never two keypairs
    under one enrollment — a *separate install* would be a distinct enrollment, not a
    second keypair under E1.)
  - Both hosts share `pq_signing_root@alice⁻¹` and E1's namespace authorisations.
  - Revocation is per-enrollment (`enroll:revoke`), so revoking E1 cuts every host
    sharing the copy at once.
- **Cross-ref:** `decisions.md` ([Decision #3](decisions.md#numbered-rulings-14) PQ-APKAM copyable-keyfile placement,
  Decision #F 1:1:1).

### 3.3 UC-A2.3 — Namespace-restricted enrollment

- **Given:** `@alice` pq-native; `alice1` (E1, `*`) approves `alice3` for namespace `app_1.my_apps` only (E3).
- **When:** `alice3` enrolls (as A2.1).
- **Then:** `alice3` gets `pq_signing_root@alice⁻¹` (root — universal) and, by
  **approval-time push** (sealed to E3's key package via `__ssenv`), only `nskey⁻¹`
  for the granted `app_1.my_apps`; the `app_2.my_apps` nskey is never delivered. The
  boundary is enforced at the atServer `__ssenv` namespace-delivery gate (it will not
  deliver an `…__ssenv.app_2.my_apps` key to an enrollment lacking `r` on it), not by
  a client-side refusal alone. `alice3` can read/write `app_1.my_apps` but not `app_2.my_apps`.
- **Cross-ref:** `decisions.md` ([Decision #4](decisions.md#numbered-rulings-14) push-at-approve + pull backstop);
  `design.md` (the substrate enroll flow, `__ssenv` envelope, `shareAllSecretsWithEnrollment`).
- **Impl/verify (A2.x):** projects **SS-2 / SS-4** + **RF-2b**; harness
  `tests/at_functional_test` runLocal.sh (enroll/approve round-trip, `__ssenv` delivery).

## 4. A3 · E2EE within one atSign (self data) + self notification

### 4.1 UC-A3.1 — Self write/read, namespace key already exists

- **Given:** `@alice` pq-native; the `app_1.my_apps` nskey exists and is published at
  `public:__nskey.app_1.my_apps@alice`; `alice1`, `alice2` hold its private.
- **When:** `alice1` does `put <k>.app_1.my_apps@alice` (shouldEncrypt).
- **Steps:**
  1. Cut a symmetric **content key (CK)**; encrypt the value with it (AES-256-GCM under the CK).
  2. **Convey the CK once** (`at/nskey`): X-Wing-seal the CK to @alice's **nskey**
     and write it as its own CK-conveyance record, stamping
     `appMetadata = {providerId: at/nskey/XWING/AES/GCM, recipientKind: nskey, ckKid, nskeyKid}`.
     (Skip if the CK is already conveyed to that generation.)
  3. Write the **data** value (`at/symmetric/AES/GCM`): stamp
     `appMetadata = {providerId: at/symmetric/AES/GCM, ckKid, iv}`; the value carries
     **no** inline sealed CK. Write; sync.
- **Then:**
  - `alice2` syncs both records: the `at/nskey` provider decapsulates the CK with the
    nskey private and caches it by `ckKid`; the `at/symmetric/AES/GCM` provider
    resolves the CK by `ckKid` and AES-GCM-decrypts the value.
  - Round-trip equals plaintext; the data value's `providerId = at/symmetric/AES/GCM`
    cites `ckKid`; a client lacking the nskey private cannot decapsulate the CK
    and so cannot read. No legacy provider, no `selfEncryptionKey`.

### 4.2 UC-A3.2 — First self write in a namespace mints and publishes the nskey

- **Given:** `@alice` pq-native; no `app_1.my_apps` nskey exists;
  `alice1`, `alice2` PQ, both with registered key packages.
- **When:** `alice1` does the first `put <k>.app_1.my_apps@alice`.
- **Steps:**
  1. `alice1` takes the `_nskeylock.app_1.my_apps@alice` lock (short-ttl, immutable
     create — so a concurrent enrollment loses and re-reads), mints the **one**
     `app_1.my_apps` nskey X-Wing keypair, publishes its public half **immediately**
     as the APKAM-signed `public:__nskey.app_1.my_apps@alice` carrying
     `{nskeyKid, publicKey}`, holds the private, and releases.
  2. Convey the CK once via the nskey data path (as A3.1): seal the CK to the nskey
     (`recipientKind: nskey`) in an `at/nskey` record; write the data under
     `at/symmetric/AES/GCM`.
  3. **Push** the nskey private per-enrollment to every ≥`r` member: call
     `enroll:listns:app_1.my_apps`, verify each member's advertised key package's
     APKAM signature against its `_apsk` (§13), `pqSeal` the private to each member's
     key package (addressed by `kpid`), put on
     `<msgId>.<kpid>.__ssenv.app_1.my_apps@alice`. `alice2` verifies the envelope
     signature, then correspondence against the published
     `public:__nskey.app_1.my_apps@alice`, and `putIfNewer`s.
- **Then:**
  - `public:__nskey.app_1.my_apps@alice` exists and resolves on a `plookup`, and
    `alice2` obtains the nskey private and reads.
  - **The namespace is not enumerable**: an unauthenticated `scan` of `@alice`, with
    and without `showhidden`, returns no `public:__nskey.…` key. A guaranteed protocol
    property, covered here as a regression guard.
  - An `app_2.my_apps`-only client is refused the `app_1.my_apps` nskey private
    (server-gated on the `__ssenv` channel).
  - `requestSecret` is the pull backstop for an enrollment offline during the push.

### 4.3 UC-A3.3 — Self fallback to the atSign-level PQ key (no namespace key)

- **Given:** `@alice` pq-native; `alice1` wants self data but no `app_1.my_apps` nskey
  has been minted and "seal-and-hold" not chosen (send-now default).
- **When:** `alice1` writes self data.
- **Then:** the write **fails**. There is no atSign-level KEM to fall back on: the
  signing root signs and never receives an encapsulation, so a namespace with no
  nskey has no PQ path at all. The failure is a distinct exception naming the
  namespace, not a generic encryption error.
  - With the legacy fallback opted in (final 3.x only), the write proceeds under
    `legacy` instead, and once the namespace's nskey exists every **subsequent**
    write uses it. Records already written under the fallback stay legacy; re-encrypting
    them is R-1's explicit migration, never a side effect of a `put`.
  - In practice this case is rare, because a client mints for its preference namespace
    and its `rw` namespaces at init — so a namespace it writes to normally has a key
    before the first write.

| enr | APKAM | root⁻¹ | nskey⁻¹ | KP |
|-----|-------|--------|---------|----|
| E1  | pq    | ✓      | ✓       | ✓  |
| E2  | pq    | ✓      | ✓       | ✓  |

### 4.4 UC-A3.4 — Self notification (encrypted value)

- **Given:** `@alice` pq-native; `alice1`, `alice2` PQ; `alice2` running a monitor.
- **When:** `alice1` does `notify` to `@alice` (self) carrying an encrypted value.
- **Steps:**
  1. Encrypt the notification value exactly as a self put: AES-256-GCM under a CK
     (`at/symmetric/AES/GCM`, cited by `ckKid`); convey the CK once via an `at/nskey`
     record sealed to the nskey (`recipientKind: nskey`, the only kind).
  2. Stamp `appMetadata.providerId` on the **notification** payload; send `notify:`.
  3. atServer queues/delivers; `alice2`'s monitor receives the notification frame.
  4. `alice2` reads `providerId` from the notification, decapsulates, decrypts.
- **Then:**
  - The notification value decrypts on `alice2` with the same provider routing as a put.
  - `providerId` travels **on the notification frame**, not only on stored keys.
  - Offline `alice2`: the queued notification still decrypts on later delivery (key still held).
  - A signal-only notification (no value) needs no decryption and is unaffected.

- **Cross-ref:** `design.md` (nskey data path: 3 layers / 3 providers, CK model, the
  nskey + its eager publication).
- **Impl/verify (A3.x):** **SS-4** (mints) + **B-1** (data path); harness at_chops
  vectors (KEM/seal) + at_client `dart test` round-trip for the data path, **plus**
  `tests/at_functional_test` runLocal.sh for UC-A3.2's per-enrollment nskey push and
  its server-gated `__ssenv` refusal ("an `app_2.my_apps`-only client is refused the
  `app_1.my_apps` nskey private" is a live-atServer assertion, not a client-only one).

## 5. A4 · E2EE across atSigns (shared data) + cross-atSign notification

### 5.1 UC-A4.1 — alice → bob, both PQ-native, bob has the namespace key

- **Given:** `@alice`, `@bob` pq-native; `@bob` published
  `public:__nskey.app_1.my_apps@bob` when he first used the namespace;
  `bob1`, `bob2` hold its private; `@bob` readiness `ready`.
- **When:** `alice1` does `put @bob:<k>.app_1.my_apps@alice` (shouldEncrypt).
- **Steps:**
  1. `plookup` `public:__nskey.app_1.my_apps@bob`, verify its APKAM signature, and note
     the advertised `nskeyKid`. Cut a symmetric **CK for @bob** — CKs are per
     recipient — or reuse the current one if it was conveyed to that same generation.
     Encrypt the value with it (AES-256-GCM under the CK).
  2. **Convey the CK once** (`at/nskey`, `recipientKind: nskey`): X-Wing-seal it to
     **bob's published nskey**, as a discrete CK-conveyance record stamping `ckKid`
     and the `nskeyKid` it was sealed to.
  3. Write the **data** value (`at/symmetric/AES/GCM`, citing `ckKid`); sync (delivered to `@bob`).
  4. Write the **self-copy** for alice's own clients, in her **own** scope: a
     **second** CK, conveyed via an `at/nskey` record sealed to alice's own
     `app_1.my_apps` nskey (`recipientKind: nskey`), plus its own data value under
     `at/symmetric/AES/GCM`. It is a different CK and therefore a different
     ciphertext — bob's CK never enters alice's own scope
     ([`decisions.md`](decisions.md) section 14).
- **Then:**
  - `bob1`, `bob2` decapsulate bob's CK record with bob's nskey private and read;
    alice's clients decapsulate the self-copy's CK with alice's nskey private and read.
    The same nskey private opens every CK record sealed to that nskey — the two reads
    differ by record-owner, not by key.
  - PQ end to end; data values `providerId = at/symmetric/AES/GCM`, CK conveyances
    `at/nskey`; no RSA on any path.
  - Every authorised reader on both atSigns decrypts; an unauthorised `@bob`
    enrollment cannot fetch the ciphertext (server-gated) nor decrypt.

### 5.2 UC-A4.2 — alice → bob where bob has no namespace key → the share fails

- **Given:** `@alice`, `@bob` pq-native; `@bob` has `public:pq_signing_root@bob` but **no** `public:__nskey.app_1.my_apps@bob` — he has never used or authorised that namespace.
- **When:** `alice1` shares `@bob:<k>.app_1.my_apps@alice`.
- **Then:** the share **fails**, with an exception naming `@bob` and the namespace so
  the app can say that the recipient has not enabled it rather than reporting an
  encryption error. Bob's signing root is not a KEM target and cannot stand in.
  - A **pre-flight capability query** answers the same question before the user
    composes anything, so an app need not discover this at write time.
  - With the legacy fallback opted in (final 3.x only), the share proceeds under
    `legacy`. That is the invitation path, and it ends at 4.x.
  - Once bob uses or authorises the namespace, his nskey is published and alice's next
    `ensureCurrent` picks it up by `plookup`; from then on the share is PQ.

### 5.3 UC-A4.3 — Multi-enrollment both ends

- **Given:** alice (E:aE1, aE2) and bob (E:bE1, bE2) all PQ; bob has `public:__nskey.app_1.my_apps@bob`.
- **When:** `alice2` shares with `@bob`.
- **Then:** all of bob's authorised enrollments read; all of alice's authorised
  enrollments read the self-copy; no authorised enrollment is left unable to decrypt.

| enr | APKAM | root⁻¹ | nskey⁻¹ | KP |
|-----|-------|--------|---------|----|
| aE1 | pq    | ✓      | ✓       | ✓  |
| aE2 | pq    | ✓      | ✓       | ✓  |
| bE1 | pq    | ✓      | ✓       | ✓  |
| bE2 | pq    | ✓      | ✓       | ✓  |

### 5.4 UC-A4.4 — Cross-atSign notification (encrypted value)

- **Given:** `@alice`, `@bob` pq-native; `@bob` published `public:__nskey.app_1.my_apps@bob`
  (or `public:pq_signing_root@bob` fallback); `@bob` readiness `ready`; `bob1` running a monitor.
- **When:** `alice1` `notify`s `@bob` with an encrypted value.
- **Steps:**
  1. Encrypt the value under a CK (`at/symmetric/AES/GCM`, cited by `ckKid`); convey
     the CK once via an `at/nskey` record sealed to bob's published nskey
     (`recipientKind: nskey`) — same CK→nskey
     conveyance as A4.1/A4.2.
  2. Stamp `appMetadata.providerId` on the notification; `notify:@bob…`.
  3. `bobS` queues; on `bob1` reconnect the monitor delivers the notification frame.
  4. `bob1` routes by `providerId`, decapsulates, decrypts; `bob2` likewise.
- **Then:**
  - The value decrypts on every authorised bob enrollment with the same routing as a shared put.
  - Negotiation gates the notification scheme on **bob's** readiness (a legacy bob →
    legacy notification — UC-B4.1).
  - Offline-then-online bob still decrypts the queued notification (key held, or
    pulled if it arrived meanwhile).
  - `appMetadata` is present on the notification frame; signal-only notifications are unaffected.

- **Cross-ref:** `design.md` (the nskey + its eager publication, bilateral
  inbound forward-secrecy); `decisions.md` (forward-secrecy rationale).
- **Impl/verify (A4.x):** **B-1** + **SS-4**; harness `tests/at_end2end_test` (cross-atSign).

## 6. A5 · Rotation & revocation (new world)

### 6.1 UC-A5.1 — Rotate a namespace key (post-compromise)

- **Given:** the `app_1.my_apps@alice` nskey exists; `alice1` wants to rotate. **Two
  distinct levers — do not conflate.**
- **When (a) — coarse forward secrecy = rotate the symmetric CK:** `alice1` cuts a new
  CK, conveys it once (sealed to the nskey), and points new writes at it. For FS
  it then **deletes the old CK's `at/nskey` conveyance record** and every enrollment
  evicts the cached old CK. This is the cheap, O(1) coarse-FS lever.
- **Then (a):** old-CK-era data becomes undecryptable (the nskey private cannot help —
  no sealed copy of the old CK survives). Retaining the old conveyance instead =
  history access. This is the per-namespace FS retention knob.
- **When (b) — revocation + PCS = rotate the nskey *keypair*:** `alice1` takes the
  `_nskeylock.app_1.my_apps@alice` lock, mints the next nskey keypair **excluding the
  revoked enrollment**, **overwrites** `public:__nskey.app_1.my_apps@alice` with the new
  APKAM-signed `{nskeyKid, publicKey}`, pushes the successor private to the surviving
  enrollments — seal to each surviving key package via `__ssenv`, dropping the revoked
  one — and releases the lock.
- **Then (b):** new CKs are sealed to the successor nskey and their conveyances carry
  the new `nskeyKid`; each surviving enrollment **retains** the prior private, so
  retained history still opens. A peer notices at its next `ensureCurrent`: it
  re-`plookup`s, sees the changed `nskeyKid`, and cuts a fresh CK to the successor.
  **Without that re-fetch the revocation does not hold** — a peer still sealing to the
  superseded generation hands the revoked enrollment a key it can open, so the
  bounded-exposure assertion is part of this case, not an optimisation. This is the
  heavier, O(n)-per-enrollment revocation + post-compromise-security lever — **not
  cheap**, and **distinct** from CK rotation.
- **Then (b), late joiner:** an enrollment approved *after* the rotation is pushed the
  current generation only; on meeting a retained `__ck` naming an earlier `nskeyKid` it
  pulls that generation via `requestSecret` and opens it.

### 6.2 UC-A5.2 — Per-enrollment auth revocation

- **Given:** `@alice` pq-native; the keyfile holding E2's APKAM keypair is lost.
- **When:** operator runs `enroll:revoke` on E2.
- **Then:** E2's one APKAM keypair can no longer authenticate; `alice1` unaffected; E2
  gets no new secrets — excluded at **both** discovery+push (`excludeEnrollmentIds` on
  `enroll:listns`/serve) **and** the `requestSecret` pull serve (the
  revocation guard). (Under 1:1:1 "revoke E2's APKAM key" == revoke its enrollment;
  there is no per-pubkey delete.)

### 6.3 UC-A5.3 — Enrollment revocation

- **Given:** enrollment E2 compromised (it holds exactly one APKAM keypair).
- **When:** operator revokes E2.
- **Then:** E2's APKAM keypair is cut at auth; pair with `nskey`-keypair rotation
  excluding E2 (UC-A5.1(b)) to deny new-data keys.

- **Cross-ref:** `decisions.md` (FS levers, Decision #F); `design.md`
  (forward-secrecy / rotation levers, nskey-keypair rotation).
- **Impl/verify (A5.x):** **B-2**.

---

# Part B — Retrofit / upgrade (mixtures of pre-PQ and post-PQ)

## 7. B0 · Prerequisite — atServer upgrade

### UC-B0.1 — A PQ-capable client cannot PQ-upgrade against a legacy atServer

- **Given:** `aliceS = legacy` (no PQ verbs); `alice1` is a PQ-capable build.
- **When:** `alice1` attempts the upgrade sequence.
- **Then:** the new PQ surface — PQ-APKAM (ML-DSA) auth, the flattened
  `enroll:listns`, `EnrollParams.metadata` on `enroll:request`, the
  authenticated self-retrofit auto-approve — is unavailable → `alice1` **aborts
  cleanly, stays legacy**, mints no PQ keys, logs why. No partial state on the server.
  (The atServer's immutable write is long-standing and present even here — it is
  **not** a PQ-only verb.) atServer upgrade is a hard prerequisite for Part B.
- **Cross-ref:** `implementation-plan.md` (B0 depends on server projects SS-1b / RF-SRV).
- **Impl/verify:** `tests/at_end2end_test`.

## 8. B1 · Upgrade an existing (pre-PQ) atSign — the retrofit scenarios

Start state for B1: `@alice = legacy` (RSA `publickey`, RSA APKAM per enrollment),
`aliceS = pq`, no `pq_signing_root`.

| enr | APKAM | root⁻¹ | KP | note                              |
|-----|-------|--------|----|-----------------------------------|
| E1  | rsa   | —      | —  | first to retrofit (B1.1)          |
| E1c | rsa   | —      | —  | copied keyfile, separate retrofit (B1.2) |
| E2  | rsa   | —      | —  | different enrollment (B1.3)       |

**The retrofit model (applies to all three).** Retrofit is **not** a mutation of the
existing enrollment. The authenticated pre-PQ client submits `enroll:request` with a
**NEW enrollmentId** on its **already-authenticated connection** (no OTP). The server
(RF-SRV) validates the requested namespaces are a **subset** of the authenticating
enrollment's, **auto-approves**, **copies** the old enrollment's expiry (or `null`) to
the new one, and **caps** the old enrollment to `min(now + server-config grace, its
existing expiry)` **without removing it**. There is **no per-APKAM-key delete**; legacy
retirement is the expiry cap + `enroll:revoke`. Each cloned pre-PQ keyfile retrofits to
its **own distinct enrollmentId** — never a second keypair under an existing enrollment.
ML-DSA APKAM auth is verified after the new keypair is recorded (see `design.md` for the
authenticated self-retrofit flow + expiry copy/cap and the `enroll:request` metadata tail).

### 8.1 UC-B1.1 — First client retrofit (`alice1`)

- **Given:** above; `pq_signing_root` absent.
- **When:** `alice1` runs the retrofit.
- **Steps:**
  1. Authenticate legacy (RSA APKAM).
  2. Mint its PQ APKAM keypair + X-Wing key package locally (both privates stay in the keyfile).
  3. Submit `enroll:request` with a **new enrollmentId**, its single
     `apkamPublicKey` + `signingAlgo = mldsa65` + key package + `EnrollParams.metadata`,
     on the authenticated connection. The server validates the namespace subset,
     **auto-approves**, copies the old expiry, and caps the old (legacy) enrollment.
  4. **Verify** PQ APKAM auth succeeds (record-authoritative `signingAlgo`).
  5. If this enrollment is **fully privileged** (`rw` on `*` and `__manage`),
     generate the ML-DSA-65 root keypair and **immutable-create**
     `public:pq_signing_root@alice` → **wins** → hold the private and convey it to the
     other fully privileged enrollments. A namespace-scoped enrollment skips this step
     entirely and proceeds without a root ([UC-B5.3](#123-uc-b53--two-enrollments-race-to-create-pq_signing_root)).
  6. When the roster holds the key, flip readiness (or leave `n-r` until siblings retrofit).
- **Then:**
  - `alice1.APKAM = pq` on the fresh auto-approved enrollment; PQ auth works.
  - `public:pq_signing_root@alice` created; `alice1.root⁻¹ = ✓`; `alice1` serves the private to other fully privileged enrollments on request.
  - The legacy enrollment is **capped** to `min(now + grace, expiry)` and ages out — **not** deleted-by-key.
  - Legacy *encryption* key retained (history still readable). No re-onboarding.

### 8.2 UC-B1.2 — Second install on a copied keyfile (`alice1c`)

- **Given:** after B1.1; `pq_signing_root` exists. `alice1c` is a clone of E1's pre-PQ keyfile.
- **When:** `alice1c` runs the retrofit.
- **Then:** identical to B1.1 except step 5 is **request**, not create: it mints its
  **own** PQ APKAM keypair + key package and self-spawns its **own distinct fresh
  auto-approved enrollment** (never a second keypair under E1); then **requests**
  `pq_signing_root@alice⁻¹` (exists → does not create), verifies public/private
  correspondence, stores. Each cloned pre-PQ keyfile thus becomes its own enrollment.

### 8.3 UC-B1.3 — Third client, different enrollment (`alice3`, E2)

- **Given:** after B1.1; `alice3` on E2 (its own legacy RSA APKAM); `pq_signing_root` exists.
- **When:** `alice3` runs the retrofit.
- **Then:** identical to B1.2 for the bootstrap (mints its own PQ APKAM keypair + key
  package, self-spawns a fresh auto-approved enrollment, requests root
  `pq_signing_root@alice⁻¹`). The distinction appears only for **namespaced** secrets — a
  restricted E2 receives only its authorised subset of `nskey` keys.

- **Cross-ref:** `design.md` (authenticated self-retrofit flow + expiry copy/cap,
  `enroll:request` metadata tail); `decisions.md` (Decision #F 1:1:1, the retrofit
  ruling).
- **Impl/verify (B1.x):** **RF-SRV** (server auto-approve), **RF-2b** (client
  mint+request), **RF-2c** (orchestration); harness `tests/at_end2end_test` runLocal.sh.

## 9. B2 · Legacy retirement & lockout

### 9.1 UC-B2.1 — Un-upgraded copy is locked out after retirement

- **Given:** E1's pre-PQ keyfile was copied to a second host `alice1b` (against advice) —
  the **same** legacy APKAM keypair on two hosts; `alice1` retrofitted (which **capped**
  E1's legacy enrollment to `min(now + grace, expiry)`); `alice1b` has not retrofitted.
- **When:** `alice1b` tries to authenticate (legacy) after the cap elapses.
- **Then:** auth **fails** — the legacy enrollment's expiry cap has elapsed (or it was
  explicitly `enroll:revoke`d), and `alice1b` never minted its own PQ keypair; `alice1b`
  must re-enroll. The lockout is the **old enrollment's expiry cap**, **not** an explicit
  per-pubkey delete.

### 9.2 UC-B2.2 — Grace-period variant

- **Given:** deployment configured a server-config grace; the cap **is** the grace window.
- **When:** `alice1` retrofits.
- **Then:** legacy auth survives until `min(now + grace, expiry)`; sibling clones may
  still retrofit (each to its own fresh enrollment) until the cap elapses; after the cap,
  UC-B2.1 applies. (Bypass open during the window — explicit trade-off.)

- **Cross-ref:** `decisions.md` (retirement ruling); `design.md` (expiry copy/cap).
- **Impl/verify:** **RF-SRV** + **RF-2c**.

## 10. B3 · Mixed-PQ within one atSign

### 10.1 UC-B3.1 — Upgraded enrollment must still write legacy for an un-upgraded sibling

- **Given:** `alice1` is PQ (`APKAM = pq`, holds the nskey/`pq_signing_root` privates),
  `alice2` still legacy-only; `@alice` readiness `n-r`.
- **When:** `alice1` puts or notifies a self key both must read.
- **Then:** `alice1` writes/notifies **legacy** (the scheme `alice2` can read) until
  readiness flips — migration invariant "write only what every reader supports"; no
  self data/notification is unreadable by `alice2`. (Applies to **put and notify** alike.)

### 10.2 UC-B3.2 — Readiness flips once all `@alice` enrollments are PQ

- **Given:** all `@alice` enrollments now PQ; operator (or auto-detect) flips readiness `ready`.
- **When:** `alice1` writes/notifies self data.
- **Then:** self data goes via the **nskey data path** — `at/nskey` conveys the CK
  sealed to the nskey (`recipientKind: nskey`) and `at/symmetric/AES/GCM` encrypts the
  data; the data is never encapsulated directly to the nskey. No `@alice` enrollment
  loses access.

| enr | APKAM | data-reads                 | data-writes                            |
|-----|-------|----------------------------|----------------------------------------|
| E1  | pq    | legacy + nskey data path   | legacy (until ready) → nskey data path |
| E2  | rsa   | legacy                     | legacy                                 |

- **Cross-ref:** `decisions.md` ([Decision #2](decisions.md#numbered-rulings-14) readiness per `(atSign, namespace)`);
  `design.md` (migration philosophy, capability negotiation).
- **Impl/verify:** **R-1** (scheme negotiation) + **RF-2c**.

## 11. B4 · Mixed-PQ across atSigns

### 11.1 UC-B4.1 — PQ-ready `@alice` shares with legacy `@bob`

- **Given:** `@alice` PQ-ready; `@bob` legacy (only `publickey` RSA), bob readiness `n-r`.
- **When:** `alice1` shares or notifies `@bob:<k>.app_1.my_apps@alice`.
- **Then:** alice writes **legacy** to bob — a per-value symmetric key RSA-wrapped
  inline onto the data, AES-256 under it (the monolithic legacy model) — to bob's
  `publickey`, gated by bob's `n-r` readiness. A PQ self-copy via the nskey data path
  for alice's own authorised enrollments is allowed **independently**. No write/
  notification bob can't read.

### 11.2 UC-B4.2 — Legacy `@alice` receives from PQ `@bob` (the interop question)

- **Given:** `@alice` legacy (no `pq_signing_root`); `@bob` PQ-native.
- **When:** `bob1` shares with `@alice`.
- **Then:** bob must encapsulate in a scheme alice can read → **legacy RSA to alice's
  `public:publickey@alice`**, which exists only if alice enabled the legacy-interop
  flag (default off). **Test outcome:** a PQ-native atSign is PQ-only by default, so a
  legacy-peer send to it is **unsupported unless** that flag is on.
- **Cross-ref:** `decisions.md` ([Decision #1](decisions.md#numbered-rulings-14) legacy interop ruling).

### 11.3 UC-B4.3 — Partially-upgraded `@alice` (alice1 PQ, alice2 legacy) shares with `@bob`

- **Given:** `@alice` mixed; `@bob` PQ-ready.
- **When:** `alice1` shares/notifies `@bob`.
- **Then:** the write toward `@bob` may take the **nskey data path** (bob is ready),
  but alice's **self-copy** must be legacy (alice2 can't read PQ) until `@alice`
  readiness flips. Two directions, two schemes, one `put`/`notify`.

### 11.4 UC-B4.4 — `@bob` finishes upgrading → shared flips to PQ

- **Given:** `@bob` was legacy; now all bob enrollments PQ and bob readiness `ready`.
- **When:** `alice1` next shares/notifies `@bob`.
- **Then:** alice writes via the **nskey data path** to bob — `at/nskey` conveys the CK
  sealed to bob's published nskey (`recipientKind: nskey`) and `at/symmetric/AES/GCM`
  encrypts the data; the legacy path is no longer used toward bob.

- **Cross-ref:** `decisions.md` ([Decision #1](decisions.md#numbered-rulings-14) legacy interop); `roadmap.md`
  (mixed-scheme + migration philosophy).
- **Impl/verify:** **R-1** + **RF-2c**; harness `tests/at_end2end_test`.

## 12. B5 · Retrofit edge cases

### 12.1 UC-B5.1 — Offline enrollment pulls `pq_signing_root` later

- **Given:** `alice2` (an enrollment) was offline during the retrofit wave;
  `pq_signing_root` created by `alice1`.
- **When:** `alice2` next comes online and retrofits.
- **Then:** `pq_signing_root` is root (no namespace), so it has **no**
  `enroll:listns` push — its `requestSecret` for `pq_signing_root@alice⁻¹` is
  the steady-state path, answered by any online holder (persists until one answers).
  Namespaced `nskey` privates `alice2` missed during its offline window arrive by the
  **push** primary path once a holder is online (`enroll:listns` + `__ssenv`),
  with `requestSecret` as the backstop. (Pull = `requestSecret` and push =
  `pushSecretToNamespaceMembers` are dual facets of one substrate — see `design.md`.)

### 12.2 UC-B5.2 — Reading legacy history after retrofit

- **Given:** `alice1` retrofitted; the old legacy enrollment aged out; the legacy
  *encryption* key is retained (the legacy APKAM is not separately deleted — there is
  no per-key delete).
- **When:** `alice1` reads pre-PQ data.
- **Then:** decrypts via the legacy provider (reads are universal); `providerId` routes
  per value. PQ retrofit never makes old data unreadable.

### 12.3 UC-B5.3 — Two enrollments race to create `pq_signing_root`

- **Given:** `alice1` and `alice3` both reach the create step with `pq_signing_root` absent.
- **When:** both attempt the immutable create.
- **Then:** exactly one wins; the other gets "already exists" and falls through to
  *request*, discarding the key material it generated rather than retrying the create.
  No orphaned data (readiness not yet flipped). The root never rotates, so a split
  root would be unrecoverable — immutability is what makes this a benign race rather
  than a permanent fork of the trust chain.

- **Cross-ref:** `design.md` (push/pull duality — substrate facts stated once there).
- **Impl/verify:** **RF-1** (`requestSecret` confirm) + **B-1** (provider routing).

---

## 13. Cross-cutting acceptance (applies to all flows)

These invariants are testable against **every** UC above:

- **Reads are universal.** A client decrypts anything ever written to it (all
  providers retained); upgrading only ever **adds** read-capability.
- **Writes gated by reader readiness.** A value/notification is only written in a
  scheme **every** required reader supports; otherwise legacy (3.x) or **refused**
  under `disallowLegacyEncryption = true`.
- **`appMetadata.providerId` is authoritative**, names every algorithm a reader needs
  code for ([`decisions.md`](decisions.md) section 16), and is present on **stored keys,
  notification frames and `lookup` responses alike**. The lookup clause is not
  redundant: it must survive every hop that *writes* a record to the atServer, and the
  sync push silently dropped it, so every cross-atSign read fell back to `legacy` for
  **every** provider ([`decisions.md`](decisions.md) section 17). Any hand-rolled
  serializer of the metadata wire fragment is a place this invariant can be lost without
  an error. Present on stored keys
  **and** notification frames (with the no-`ns` shapes: `at/nskey` →
  `{providerId, recipientKind, ckKid}`; `at/symmetric/AES/GCM` →
  `{providerId, ckKid, iv}`).
- **No RSA in any confidentiality path** for a fully-PQ interaction (auth, enrollment
  conveyance, self, shared, notification).
- **ML-DSA APKAM auth is record-authoritative.** PQ auth verifies against the
  enrollment record's single `apkamPublicKey` using the **record** `signingAlgo`
  (`rsa2048` | `mldsa65`) — `_getSigningAlgoType` reads the record, never the
  client-supplied wire value (at_chops `mldsa65` verify branch + at_commons pkam
  `signingAlgo` literal).
- **Immutability, and where it does *not* apply.** `pq_signing_root` is create-once: a
  second create is rejected, never an overwrite — it is the root and never rotates.
  `public:__nskey.<ns>@owner` is **mutable by design**, because nskey-keypair rotation
  has to overwrite it; what stops two of the owner's enrollments racing is the
  short-ttl immutable lock `_nskeylock.<ns>@owner`, and what stops substitution is the
  APKAM signature over the advertised envelope, not the write mode.
- **Published nskeys are fetchable but not enumerable.** `public:__nskey.<ns>@owner`
  resolves on an exact `plookup`, cross-atSign, and appears in **no** scan — with or
  without `showhidden`, authenticated or not. This is a guaranteed protocol property
  (`_apsk` already relies on it); the test is a regression guard, not a proof obligation.
- **Advertised recipient keys are signed and verified.** Every advertised
  encapsulation key — the per-enrollment key package (`metadata.keyPackage`) and the
  published `nskey` public half — is an **APKAM-signed
  envelope** produced by the generating enrollment (`wrapAndSign`). A fetcher verifies
  it against that enrollment's `_apsk` **the same way same-atSign and cross-atSign**
  (fetch `public:_apsk.<eid>.a.__e@owner`, verify using the envelope's `signingAlgo` /
  `hashingAlgo`) **before** encapsulating to it; a **tampered, unsigned, or
  wrong-signer** advertised key is **rejected**. The atServer keeps every approved
  enrollment's `_apsk` **present** (fetchable without a client publish) and
  **write-restricted** (a cross-enrollment overwrite is refused). *(Substrate work —
  sign SS-2/SS-4, verify SS-1c; target-not-built on the current substrate.)*
- **Performance is measured, not assumed.** The PQ primitives (ML-KEM / ML-DSA,
  X-Wing encap/decap, `pqSeal`) land on hot paths — PKAM auth and every put/get — that
  run on mobile/IoT hardware (the roadmap's NoPorts finish line). PKAM-auth latency and
  put/get latency deltas vs the legacy RSA/AES path are **measured on one reference
  low-end device** by a bench harness landed **with B-1** — the harness is the durable
  artefact, re-run on every later key-shape change (bench-before-redesign). The ceiling
  is **pinned when the harness lands**: a measured budget, not a guessed number.

- **Cross-ref:** `design.md` (at_chops primitives: X-Wing, pqSeal/pqOpen, ML-DSA; the
  record-authoritative `signingAlgo` verify); `decisions.md` (1:1:1 + verb-wire-shape rulings).

## 14. Test harness & impl/verify mapping

Every UC cluster runs against one or more of four test layers:

| Layer                              | Covers                                                                                   |
|------------------------------------|------------------------------------------------------------------------------------------|
| **at_chops vectors**               | KEM / seal / ML-DSA primitives (X-Wing encap/decap, pqSeal/pqOpen, `mldsa65` verify). Baseline already on trunk — see below. |
| **at_client `dart test`**          | data-path providers (`at/nskey`, `at/symmetric/AES/GCM`), CK cache, round-trip equality. Run with `--concurrency=1`. |
| **`tests/at_functional_test` runLocal.sh** | same-atSign self keys, enroll / `listns` round-trip, `__ssenv` delivery; `docker compose down` before each run; cap runs at 180000 ms. |
| **`tests/at_end2end_test`**        | cross-atSign shares/notifications, retrofit, readiness flip.                             |

**Baseline (already shipped, not pending work).** The primitive layer is published:
**#1930** (M0 crypto seam) and **#1993 / at_chops 3.3.0** (`pqSeal`/`pqOpen`), with
**PR #2035** (design fixes) merged. at_chops-vector coverage exercises this shipped base.
As of the **2026-07-17 release train** the baseline also includes **at_chops 3.4.0**
(ML-DSA-65 verify dispatch, AES-GCM FFI), **at_commons 5.13.0**, **at_client 3.14.0**
(carrying the SS-0 substrate, PR #2037) and **at_auth 3.3.0-rc1** (extended `AtKeys` +
`AtKeysIo.flush()`), so SS-0 / SS-1b / S-1 / S-2 acceptance is against shipped code.

**PQ-capable test image (harness gap).** Both `tests/at_functional_test` and
`tests/at_end2end_test` pin `atsigncompany/virtualenv:vip`, which refreshes only via
certs-on-trunk or a canary→prod promotion. The `enroll:listns` verb itself **has now
landed in at_server** (#2685, merged 2026-07-07, with functional coverage in #2698), so
the blocker is no longer "no server implements it" — it is **whether the pinned `:vip`
tag carries a build new enough**. Verify that before relying on any live `listns`
assertion from this repo's harnesses; a green local run against `at_virtual_env:local`
does not imply CI parity.

The underlying gap is unchanged: no work package delivers an image-override path. Close
it with a documented way to build a virtualenv image from an at_server branch, an
image-override env var (e.g. `VE_IMAGE`) honoured by **both** `runLocal.sh` harnesses,
and a stated policy for when CI switches its pinned tag. Until that exists, **SS-1c's
client-driven live round-trip must sequence after a `:vip` refresh that carries the
verb** — the client layer and at_chops vectors can land earlier, but the live assertion
cannot be trusted against an unverified `:vip`.

**UC → project coverage** (cross-ref only — the authoritative sequence / dependency
graph / effort lives in `implementation-plan.md`; this is the one place acceptance.md
restates project IDs, and only as a coverage map):

| UC cluster                                                                      | Project(s)                      |
|---------------------------------------------------------------------------------|---------------------------------|
| A1.1 (PQ-native onboard, [Decision #1](decisions.md#numbered-rulings-14), B4.2) | **ON-1**                        |
| A2.x / A3.x / A4.x / A5.x                                                       | **SS-2, SS-4, B-1, B-2, RF-2b** |
| B0.x / B1.x / B2.x / B3.x / B4.x / B5.x                                         | **RF-2c** (retrofit) + **R-1** (scheme negotiation) + **RF-SRV** (server auto-approve) |

Project names follow the `implementation-plan.md` scheme (RF-SRV / RF-2b /
RF-2c).

- **Cross-ref:** `implementation-plan.md` (full plan, dependency graph, waves,
  effort, critical path); `design.md` (harness mechanics).
