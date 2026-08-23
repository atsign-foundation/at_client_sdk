# acceptance.md — Acceptance tests (given / when / then) + impl/verify steps

**Status:** acceptance catalogue (current). Lives in `docs/`.
**Purpose:** the single ordered, testable burn-down target for the D1
post-quantum work — the full use-case list **A1.x–A5.x** (PQ-native greenfield),
**B0.x–B5.x** (retrofit / mixed) and **C1.x** (the rollout itself, driven by
flags), each as **Given / When / Then** with
concrete at-keys, the protocol **Steps**, and the **impl/verify** harness.

> **Reconciled with the 2026-08-03 ruling.** `pqpublickey` is gone: the
> atSign-level key is `public:pq_signing_root@<atSign>`, it signs and verifies
> only, and no scenario encapsulates to it. Cold-start has no PQ target and fails,
> so PQ sharing requires the recipient to have used or authorised the namespace.
> See [decisions.md section 18](detail/decisions.md#18-pqpublickey-becomes-the-user-owned-signing-root-2026-08-03).

## Table of contents

- [Use-case status](#use-case-status)
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
- [12. B5 · Edge cases](#12-b5--edge-cases)
- [13. Cross-cutting acceptance (applies to all flows)](#13-cross-cutting-acceptance-applies-to-all-flows)
- [14. Test harness & impl/verify mapping](#14-test-harness--implverify-mapping)
- [15. C1 · The rollout posture (capstone of `decisions.md` 56.4)](#15-c1--the-rollout-posture-capstone-of-decisionsmd-564)
- [16. G1 · Signature agility and the rollout matrix](#16-g1--signature-agility-and-the-rollout-matrix)

---

## Use-case status

**Generated from the scenarios, not written by hand.** A use case is:

- **PROVEN** — a scenario in `packages/at_client/test/acceptance/` asserts it
  and runs.
- **BLOCKED** — its scenario exists but is skipped against a named constant in
  `blockers.dart`, so something is recorded as owing it.
- **WITHDRAWN** — the catalogue withdrew the row and kept the heading, so the
  reason and every cross-reference to it survive.

There is no "in progress" state, because nothing in the tree can express one: a
scenario either runs or is skipped against a named blocker. Today that is
**68 PROVEN · 0 BLOCKED · 1 WITHDRAWN** across 69 use cases and 79 scenarios —
several rows carry more than one.

⚠️ **This sentence said `50 · 2 · 1` across 53 until 2026-08-18**, when a cold
read counted the table under it. The 16 missing rows are exactly the `UC-G1.x`
cluster, added the same day 14.17 landed: the table below is generated against
the scenarios and cannot drift, and this line is prose that nothing checked. It
is checked now — `docs_structure_test.dart` derives all four numbers from the
table and from `manifest.dart`, and fails when they disagree.

⚠️ The scenario figure is **79, not 70**: my first correction inferred it from
the old sentence's own arithmetic (`53 use cases and 53 scenarios — UC-A5.1 has
two`), which is the same mistake in the other direction. It comes from
`scenarioCount()`, which counts every registered file — including the ten
cross-cutting rows whose test names carry no `UC-` at all.

⚠️ **This table is an index. The `###` headings below are the definitions** —
`manifest.dart` parses them, and `catalogue_test.dart` fails when they and the
scenarios disagree. Do not collapse the headings into this table.

Re-derive rather than trusting the rows:

```bash
grep -rn "}, skip:" packages/at_client/test/acceptance/*_test.dart
grep -n "blocked:\|owed:" packages/at_client/test/acceptance/blockers.dart
cd packages/at_client && dart test test/acceptance --concurrency=1
```

| Use case | What it proves                                                                      | Status    | Proof                        |
|----------|-------------------------------------------------------------------------------------|-----------|------------------------------|
| UC-A1.1  | First-enrollment CRAM onboard is PQ-native                                          | PROVEN    | `a1_onboard_test.dart`       |
| UC-A2.1  | New enrollment, approved by an online enrollment (PQ-safe enroll/approve)           | PROVEN    | `a2_enrollment_test.dart`    |
| UC-A2.2  | Second host using the *same* keyfile (copied keyfile, E1)                           | PROVEN    | `a2_enrollment_test.dart`    |
| UC-A2.3  | Namespace-restricted enrollment                                                     | PROVEN    | `a2_enrollment_test.dart`    |
| UC-A2.4  | The key package advertises the KEM the deployment configured                        | PROVEN    | `a2_enrollment_test.dart`    |
| UC-A2.5  | An enrollment amends its own key package (`enroll:update`)                          | PROVEN    | `key_package_amendment_live_test.dart` |
| UC-A2.6  | Only the enrollment itself may amend its metadata                                   | PROVEN    | `key_package_amendment_live_test.dart` |
| UC-A3.1  | Self write/read, namespace key already exists                                       | PROVEN    | `a3_self_data_test.dart`     |
| UC-A3.2  | A client mints and publishes the nskey for each namespace it is authorised for      | PROVEN    | `a3_self_data_test.dart`     |
| UC-A3.3  | Self write with no namespace key has no PQ fallback                                 | PROVEN    | `a3_self_data_test.dart`     |
| UC-A3.4  | Self notification (encrypted value)                                                 | PROVEN    | `a3_self_data_test.dart`     |
| UC-A3.5  | The published nskey advertisement names its KEM and what it can open                | PROVEN    | `a3_self_data_test.dart`     |
| UC-A4.1  | alice → bob, both PQ-native, bob has the namespace key                              | PROVEN    | `a4_shared_data_test.dart`   |
| UC-A4.2  | alice → bob where bob has no namespace key → the share fails                        | PROVEN    | `a4_shared_data_test.dart`   |
| UC-A4.3  | Multi-enrollment both ends                                                          | PROVEN    | `a4_shared_data_test.dart`   |
| UC-A4.4  | Cross-atSign notification (encrypted value)                                         | PROVEN    | `a4_shared_data_test.dart`   |
| UC-A4.5  | A sender follows the recipient's advertised algorithm, not its own preference       | PROVEN    | `a4_shared_data_test.dart`   |
| UC-A4.6  | The construction is negotiated from `suites`, and no shared entry is a refusal | PROVEN    | `a4_shared_data_test.dart`   |
| UC-A4.7  | No mutually supported construction is a refusal, not a guess                        | PROVEN    | `a4_shared_data_test.dart`   |
| UC-A5.1  | Rotate a namespace key (post-compromise)                                            | PROVEN    | `a5_rotation_test.dart`      |
| UC-A5.2  | Per-enrollment auth revocation                                                      | PROVEN    | `a5_rotation_test.dart`      |
| UC-A5.3  | Enrollment revocation                                                               | PROVEN    | `a5_rotation_test.dart`      |
| UC-B0.1  | A PQ-capable client cannot PQ-upgrade against a legacy atServer                     | PROVEN    | `b0_server_prereq_test.dart` |
| UC-B1.1  | First client retrofit (`alice1`)                                                    | PROVEN    | `b1_retrofit_test.dart`      |
| UC-B1.2  | Second install on a copied keyfile (`alice1c`)                                      | PROVEN    | `b1_retrofit_test.dart`      |
| UC-B1.3  | Third client, different enrollment (`alice3`, E2)                                   | PROVEN    | `b1_retrofit_test.dart`      |
| UC-B2.1  | Un-upgraded copy is locked out after retirement                                     | PROVEN    | `b2_retirement_test.dart`    |
| UC-B2.2  | Grace-period variant                                                                | PROVEN    | `b2_retirement_test.dart`    |
| UC-B3.1  | A capability-stage enrollment reads PQ but still writes legacy                      | PROVEN    | `b3_mixed_intra_test.dart`   |
| UC-B3.2  | The app's active release flips self data to the nskey path                          | PROVEN    | `b3_mixed_intra_test.dart`   |
| UC-B4.1  | Active-PQ `alice` shares toward a `bob` with no namespace key                       | PROVEN    | `b4_mixed_cross_test.dart`   |
| UC-B4.2  | Legacy `@alice` receives from PQ `@bob` (the interop question)                      | PROVEN    | `b4_mixed_cross_test.dart`   |
| UC-B4.3  | Mid-rollout `@alice` (one install active, one still old) shares with `@bob`         | PROVEN    | `b4_mixed_cross_test.dart`   |
| UC-B4.4  | Bob's install reaches capability → alice's shares flip to PQ                        | PROVEN    | `b4_mixed_cross_test.dart`   |
| UC-B5.1  | Offline enrollment pulls `pq_signing_root` later                                    | PROVEN    | `b5_edge_cases_test.dart`    |
| UC-B5.2  | Reading legacy history after retrofit                                               | PROVEN    | `b5_edge_cases_test.dart`    |
| UC-B5.3  | Two enrollments race to create `pq_signing_root`                                    | PROVEN    | `b5_edge_cases_test.dart`    |
| UC-B5.4  | Two enrollments race to mint a namespace's nskey                                    | PROVEN    | `b5_edge_cases_test.dart`    |
| UC-B5.5  | The mint lock has no release but its ttl                                            | PROVEN    | `b5_edge_cases_test.dart`    |
| UC-B5.6  | A rotation inside the cooldown is refused, and succeeds after it                    | PROVEN    | `b5_edge_cases_test.dart`    |
| UC-B5.7  | A winner that overruns its lease publishes nothing                                  | PROVEN    | `b5_edge_cases_test.dart`    |
| UC-B5.8  | A client that configures nothing still takes part                                    | PROVEN    | `b5_edge_cases_test.dart`    |
| UC-B5.9  | A conveyed private is filed only if it is addressed here                            | PROVEN    | `b5_edge_cases_test.dart`    |
| UC-B5.10 | An enrollment not entitled to the root does not ask for it                          | PROVEN    | `b5_edge_cases_test.dart`    |
| UC-B5.11 | An enrollment that missed the mint heals from a holder                              | PROVEN    | `b5_edge_cases_test.dart`    |
| UC-B5.12 | The owner verifies her own advertisement as a peer would                            | PROVEN    | `b5_edge_cases_test.dart`    |
| UC-C1.1  | The era axis: a postured client writes PQ by default                                | PROVEN    | `c1_rollout_test.dart`       |
| UC-C1.2  | The refusal axis: the posture disallows legacy writes                               | PROVEN    | `c1_rollout_test.dart`       |
| UC-C1.3  | WITHDRAWN — there is no envelope axis                                               | WITHDRAWN | —                            |
| UC-C1.4  | The key-exchange axis: the posture names pq enrollment                              | PROVEN    | `c1_rollout_test.dart`       |
| UC-C1.5  | The retrofit axis: an argless retrofit follows the posture                          | PROVEN    | `c1_rollout_test.dart`       |
| UC-C1.6  | The grouped posture: one value moves all seven axes                                 | PROVEN    | `c1_rollout_test.dart`       |
| UC-C1.7  | The signing-set axis: which keys an enrollment holds                                | PROVEN    | `c1_rollout_test.dart`       |
| UC-G1.1   | The derivation is offered, not applied                                             | PROVEN    | `g1_keyfile_test.dart` |
| UC-G1.2   | A retrofit leaves one active auth key, touching nothing legacy                     | PROVEN    | `g1_keyfile_test.dart` |
| UC-G1.3   | Retirement frees the slot                                                          | PROVEN    | `g1_keyfile_test.dart` |
| UC-G1.4   | Opening a legacy keyfile does not upgrade it                                       | PROVEN    | `g1_keyfile_test.dart` |
| UC-G1.5   | A bare-string `_apsk` still verifies, and is still emitted                         | PROVEN    | `g1_wire_test.dart` |
| UC-G1.6   | An unversioned envelope is refused, and the refusal names why                      | PROVEN    | `g1_wire_test.dart` |
| UC-G1.7   | The verifier takes the strongest and does not fall back                            | PROVEN    | `g1_wire_test.dart` |
| UC-G1.8   | The rollout-1 signing key stays verifiable after rollout 2                         | PROVEN    | `g1_wire_test.dart` |
| UC-G1.9   | A retired algorithm still verifies history                                         | PROVEN    | `g1_wire_test.dart` |
| UC-G1.9a  | The client mints what the in-use set names, advertising first                      | PROVEN    | `g1_wire_test.dart` |
| UC-G1.10  | `enroll:update` rekey keeps the enrollment id                                      | PROVEN    | `g1_enroll_update_test.dart` |
| UC-G1.11  | Proof of possession is required                                                    | PROVEN    | `g1_enroll_update_test.dart` |
| UC-G1.12  | Namespaces stay out of reach                                                       | PROVEN    | `g1_enroll_update_test.dart` |
| UC-G1.13  | `enroll:update` is self-only                                                       | PROVEN    | `g1_enroll_update_test.dart` |
| UC-G1.14  | pqReady is invisible to a deployed peer                                            | PROVEN    | `g1_rollout_matrix_test.dart` |
| UC-G1.15  | Every rollout stage verifies every other stage's envelope                          | PROVEN    | `g1_rollout_matrix_test.dart` |

---

## 0. Purpose, scope & how to read this doc

Each use case carries **both** the given/when/then acceptance rows **and** the
step-sequence that produces them.

**Read order.** Part A (PQ-native greenfield, sections [2](#2-a1--onboard-a-new-atsign-pq-native)–[6](#6-a5--rotation--revocation-new-world))
is specified and built **before** Part B (retrofit / mixed,
sections [7](#7-b0--prerequisite--atserver-upgrade)–[12](#12-b5--edge-cases)). [Section 13](#13-cross-cutting-acceptance-applies-to-all-flows)
states invariants that hold across every flow; [section 14](#14-test-harness--implverify-mapping)
maps each UC cluster to its test layer and owning project.
[Section 15](#15-c1--the-rollout-posture-capstone-of-decisionsmd-564) (Part C)
comes last because it asserts the *mechanism that drives* Parts A and B into
production — each of the five rollout flag axes in isolation, and the grouped
`PqPosture` — rather than any crypto behaviour of its own.

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
| `pq_signing_root` | atSign-level user-owned **signing** root published (mutable, minted under `_rootlock@owner`)?     |
| `nskey.ns`    | namespace `ns` nskey state: `—` (never used, so no nskey) · `<kid>` (minted and published at `public:__nskey.<ns>@owner`; the kid names the current generation) |
| `stage`       | The **app's release stage** for the namespace ([`decisions.md` 36](detail/decisions.md#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05)): `legacy` (pre-capability build) · `cap` (capability build — reads everything, writes legacy) · `active` (writes PQ). Replaces the removed per-`(atSign, namespace)` readiness marker: there is no published readiness state, only what build each install runs. |

**Key objects** (shapes defined in `design.md`; named here for test wiring):

- `public:pq_signing_root@alice` — the atSign-level, **user-owned signing root**
  (ML-DSA-65); no namespace; **mutable**, with the short-ttl immutable lock
  `_rootlock@alice` — not the record — stopping two privileged enrollments minting
  two roots. It signs and verifies only, and never
  appears in a key-transport path. Value is
  `{"v": 1, "keys": [{"kid": "<hex>", "use": "sign", "alg": "mldsa65", "pub": "<base64>"}]}`
  — the `_apsk` advertisement vocabulary verbatim, because the root **is** an
  ordinary signing key ([`decisions.md` 101](detail/decisions.md#101-the-signing-root-becomes-an-ordinary-signing-key-and-rotatable-2026-08-15)
  requirement 1). A retired entry carries `"status": "retired"`, which is what
  keeps every root link it ever signed verifiable. Only an enrollment with `rw` on `*`
  and `__manage` may create it; the private rides that app's `.atKeys` and is
  conveyed to the other fully privileged enrollments over the substrate. Published
  plain (not `_`-hidden) because it is meant to be found and audited. See
  [`decisions.md` section 18](detail/decisions.md#18-pqpublickey-becomes-the-user-owned-signing-root-2026-08-03).
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
    `{v, createdAt, keys:[…], suites}`. The leading underscore keeps it out of every scan
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
  `providerId` defaults to **legacy**. `appMetadata` **states its record's namespace**
  ([decisions.md section 19](detail/decisions.md#19-nested-namespaces-the-nskey-is-resolved-by-walking-up-2026-08-03)),
  because `AtKey.fromString` splits at the last dot and a multi-segment namespace
  cannot be recovered from the wire string:
  - `at/nskey/XWING/AES/GCM` → `{providerId, recipientKind, ckKid, nskeyKid, ns}` — a
    CK-conveyance record: a CK X-Wing-sealed to the nskey. `recipientKind` is
    `nskey` and nothing else; self and inbound both seal to the one nskey. The
    `root-pqpublickey` variant is withdrawn along with the cold-start KEM. `ns` is the
    resolved namespace the conveyance lives at.
  - `at/symmetric/AES/GCM` → `{providerId, ckKid, iv, ns, ckNs}` — application data
    AES-256-GCM under a CK, cited by `ckKid`. `ns` is the value's own full namespace
    and is what the AAD binds; `ckNs` is where the CK lives, and differs from `ns`
    whenever resolution walked up.
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
  3. Mint the atSign-level **ML-DSA-65 signing root** under the `_rootlock@alice`
     mint lock; publish `public:pq_signing_root@alice` carrying
     `{"v": 1, "keys": [{"kid": "…", "use": "sign", "alg": "mldsa65", "pub": "…"}]}`;
     hold the private half locally. E1 is a first enrollment and so fully
     privileged, which is what entitles it to create the root at all.
  4. Mint E1's **X-Wing key package** and register it in E1's enrollment record
     (private half stays in the keyfile; **not** published).
  5. Persist AtKeys (PQ APKAM private + signing-root private + key-package private).
  6. **Verify**: re-authenticate using the PQ APKAM key (proves the server accepts PQ auth).
  7. **Legacy material is still cut and published, by default**
     ([`decisions.md` 37](detail/decisions.md#37-legacy-key-material-is-retained-until-the-ecosystem-is-pq-not-the-atsign-2026-08-05),
     reversing the original Decision #1 default): mint the legacy RSA encryption
     keypair + `selfEncryptionKey`, and publish `public:publickey@alice` — whether
     this atSign will need legacy is determined by the apps that adopt it, which is
     unknowable here. The legacy-interop flag is an early **opt-out** for a caller
     that knows better; a future release flips the default.
- **Then:**
  - `alice1.APKAM = pq` and it authenticates via PQ APKAM; no RSA APKAM key
    required *for auth*.
  - `public:pq_signing_root@alice` exists and is **mutable** — what prevents two
    privileged enrollments minting two roots is `_rootlock@alice`, whose second
    create the atServer rejects — and `alice1.root⁻¹ = ✓`.
  - The root is a **signing** key. Nothing encapsulates to it, at onboarding or
    ever.
  - `alice1.KP = ✓`, registered in E1's record (not published; discoverable only via
    `enroll:listns`).
  - `selfEncryptionKey` exists but the PQ data path never touches it — self data
    uses the nskey path. There is no cold-start fallback to an atSign-level key; a
    namespace with no nskey simply has no PQ path.
  - **Legacy `publickey@alice` is present by default** (a legacy peer's send works
    out of the box, see [UC-B4.2](#112-uc-b42--legacy-alice-receives-from-pq-bob-the-interop-question));
    with the opt-out flag set it is absent and a legacy peer's send is unsupported.

| enr | APKAM | root⁻¹ | nskey⁻¹ | KP |
|-----|-------|--------|---------|----|
| E1  | pq    | ✓      | —       | ✓  |

- **Cross-ref:** [`decisions.md` section 18](detail/decisions.md#18-pqpublickey-becomes-the-user-owned-signing-root-2026-08-03)
  (the signing root, and why there is no cold-start KEM);
  `decisions.md` ([Decision #1](detail/decisions.md#numbered-rulings-14), legacy-peer interop flag).
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
     the enrollment record — the **bare key value, exactly as today**
     ([`decisions.md` 39](detail/decisions.md#39-_apsk-rides-the-same-two-stage-ladder-2026-08-05)).
     What chains it to the root is the **approval-chain link** `alice1` signs and
     conveys, which E2 stamps onto its own `_apsk` metadata at first run — the
     value itself is untouched, because apps parse it.
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
  - E2's `_apsk` carries a chain link that `verifyChain` walks to the signing
    root, so a reader can chain an advertised key back to the atSign's own
    anchor rather than to whatever the atServer served — the `_apsk` **value**
    stays the bare key apps already parse.
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
- **Cross-ref:** `decisions.md` ([Decision #3](detail/decisions.md#numbered-rulings-14) PQ-APKAM copyable-keyfile placement,
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
- **Cross-ref:** `decisions.md` ([Decision #4](detail/decisions.md#numbered-rulings-14) push-at-approve + pull backstop);
  `design.md` (the substrate enroll flow, `__ssenv` envelope, `shareAllSecretsWithEnrollment`).

### 3.4 UC-A2.4 — The key package advertises the KEM the deployment configured

- **Given:** `@alice` pq-native; the deployment running `alice4` sets
  `AtClientPreference.keyEstablishmentAlgorithms = [ml-kem-1024]` (the default is
  `[x-wing]`, the hybrid). `enrollmentKeyPackageBuilder` takes the **first** of that list
  as an **explicit parameter** — it runs before the enrollment exists and has no client
  to read a preference from, and an enrollment is created holding one key.
- **When:** `alice4` requests an enrollment (as [UC-A2.1](#31-uc-a21--new-enrollment-approved-by-an-online-enrollment-pq-safe-enrollapprove)),
  minting the key package that rides `enroll:request`.
- **Then:**
  - the advertised key is a **1568-byte ML-KEM-1024** encapsulation key rather than a
    1216-byte X-Wing one — the two arms differ in **shape**, not only in a label, which
    is what makes the assertion worth making;
  - `keys[].alg = ml-kem-1024` and `suites = [ml-kem-1024-rfc9180-v1]` **only**. A
    package never claims a construction its own key cannot decapsulate; a sender acts on
    the claim, so an overstatement surfaces on the holder's side as an opaque AEAD error;
  - a peer sealing to it uses `pqSeal ver 0x03`;
  - the private is filed as its **64-byte seed** with the algorithm alongside, and
    re-derives the same kpid after a restart. Filing the 3168-byte expanded decapsulation
    key instead leaves the enrollment unopenable at the next start, with no error at the
    moment the mistake is made.
- **Then (an existing key keeps its own algorithm):** a client whose keyfile already
  holds a key package **does not re-mint** under a newly configured KEM. The kpid is the
  address peers seal to, and moving it takes a deliberate `enroll:update` that no
  client sends yet, so re-minting would move the client to an address nobody writes
  to — it would scan for envelopes being sent somewhere else. The mismatch is **logged**, not
  silently resolved, and the new preference takes effect on the next enrollment.
- **Then (an unimplemented algorithm fails the mint):** it does not quietly mint the
  other one. This is the only moment an enrollment's encapsulation target can be set
  without the enrollment later sending `enroll:update` for itself.
- **Cross-ref:** [`decisions.md` 50](detail/decisions.md#50-two-kems-by-configuration-one-construction-by-negotiation-2026-08-07)
  (why the knob is a preference and not a `CryptoConfig` field);
  [`implementation-plan.md` 14.6](detail/implementation-plan.md#146-the-enrollment-records-metadatakeypackage-is-a-one-way-door)
  (the door `enroll:update` opened; `AtEnrollment.update` can walk through it
  as of 2026-08-13, but nothing re-advertises a key package yet).

### 3.5 UC-A2.5 — An enrollment amends its own key package (`enroll:update`)

- **Given:** `@alice` pq-native; `alice4` enrolled (E4) with a key package advertising a
  **single** X-Wing key, and secrets already sealed to that kpid sitting unread at
  `<msgId>.<kpidOld>.__ssenv.app_1.my_apps@alice`.
- **When:** `alice4` mints a second KEM keypair (ML-KEM-1024), rebuilds and re-signs its key
  package with **both** keys, and sends `enroll:update` on its own
  APKAM-authenticated connection.
- **Then:**
  - `enroll:listns` returns the amended package: `keys[]` has two entries and `suites`
    covers both KEMs' constructions, still derived from the package's own keys and never
    from what the writing build supports;
  - the amended package still verifies against E4's `_apsk` — it is re-signed by the same
    APKAM private, and nothing about the update path relaxes the signature check;
  - a peer sealing to E4 now negotiates to whichever key its own `keyAlgos` order prefers,
    and stamps the matching `pqSeal` version;
  - **the pre-existing envelope at `kpidOld` still opens.** `alice4` retains the superseded
    private half and keeps answering at the old address. This is the row that fails if a
    replaced kpid is treated as retired, and the failure would otherwise be a silent,
    unattributable loss of a secret that was correctly sent;
  - nothing already sealed is re-sealed, and no conveyance fires: the updater is an
    enrollment that already holds the plaintext and re-files it locally.
- **Then (an unnamed metadata key survives):** setting `keyPackage` leaves any sibling
  top-level metadata key untouched. Whole-map replace is read-mutate-write against shared
  durable state, so a client that has never heard of a future field must not clobber it.

### 3.6 UC-A2.6 — Only the enrollment itself may amend its metadata

- **Given:** `@alice` pq-native; `alice1` (E1, fully privileged, `*`) and `alice4` (E4,
  namespace-scoped) both enrolled and online.
- **When:** E1 sends `enroll:update` naming **E4**; separately, a legacy-PKAM /
  owner connection (no enrollmentId) sends the same request.
- **Then:** both are refused — the second one **despite** carrying full permissions
  everywhere else. `isAuthorized` short-circuits a connection with no enrollment id to
  `true`, so this arm is the one that goes green for the wrong reason if the self-only
  check is written as an authorization lookup rather than an identity test.
- **Then (state gate):** the same request against a **revoked** E4 is refused, so a revoked
  enrollment cannot re-advertise an encapsulation target.
- **Then (the arms must differ):** the accepted arm — E4 updating E4 — has to run in the
  same session, or the two refusals prove only that the verb refuses everything.
- **Cross-ref:** [`decisions.md` 68](detail/decisions.md#68-the-enrollment-record-stops-being-a-one-way-door-enrollupdatemetadata-2026-08-10)
  rulings 2, 3 and 6.

- **Impl/verify (A2.x):** projects **SS-2 / SS-4** + **RF-2b**, and **KE-1** for
  UC-A2.4; **KE-2** for UC-A2.5 / UC-A2.6, which need the live verb and therefore
  `tests/at_functional_test` against the locally built virtualenv image; harness
  `tests/at_functional_test` runLocal.sh (enroll/approve round-trip, `__ssenv` delivery).
  UC-A2.4 is a unit row — the shapes it asserts are decided entirely client-side, before
  anything reaches an atServer.

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

### 4.2 UC-A3.2 — A client mints and publishes the nskey for each namespace it is authorised for

> **Amended 2026-08-04.** This use case previously read *"first self write in a namespace mints
> and publishes the nskey"*, with the mint triggered by `put`. That was never built and it
> contradicted [UC-A3.3](#43-uc-a33--self-write-with-no-namespace-key-has-no-pq-fallback), which
> requires a write to a keyless namespace to **fail** and is proven live. The ruling was that the
> code is right and this text was wrong: minting inside a `put` would hide a distributed lock, a
> keypair generation, a public record publish and a per-enrollment conveyance behind one write,
> all on the latency path of a user action. Minting is therefore a **start-time** step, and the
> write path stays honest about what it cannot do. See
> [decisions 29](detail/decisions.md#29-uc-a32-describes-a-mint-trigger-that-was-never-built-2026-08-04).

- **Given:** `@alice` pq-native; no `app_1.my_apps` nskey exists;
  `alice1`, `alice2` PQ, both with registered key packages.
- **When:** `alice1` starts and seeds its authorised namespaces
  (`AtClientImpl._init` → `NskeySeeding.seed()`, opt-in via
  `AtClientPreference.seedNamespaceKeys`). An APKAM client learns its namespaces from its own
  enrollment record; a legacy PKAM client has exactly one, its `preference.namespace`.
- **Steps:**
  1. `alice1` takes the `_nskeylock.app_1.my_apps@alice` lock (short-ttl, immutable
     create — so a concurrent enrollment loses and re-reads), **re-reads the
     advertisement under the lock** in case a sibling published while it was
     racing, mints the **one** `app_1.my_apps` nskey X-Wing keypair, publishes its
     public half **immediately** as the APKAM-signed
     `public:__nskey.app_1.my_apps@alice` carrying `{v, createdAt, keys:[…],
     suites}`, and holds the private. It does **not** release the lock: the ttl
     does, which is what makes it an election token with a cooldown rather than a
     mutex.
  2. Convey the CK once via the nskey data path (as A3.1): seal the CK to the nskey
     (`recipientKind: nskey`) in an `at/nskey` record; write the data under
     `at/symmetric/AES/GCM`.
  3. **Push** the nskey private per-enrollment to every ≥`r` member: call
     `enroll:listns:app_1.my_apps`, verify each member's advertised key package's
     APKAM signature against its `_apsk` ([section 13](#13-cross-cutting-acceptance-applies-to-all-flows)), `pqSeal` the private to each member's
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
  - Seeding is **idempotent**: a later start adopts the published advertisement rather than
    minting over it. Re-minting per start would rotate the namespace key on every launch and
    strand every peer that had already fetched the previous generation.
  - A subsequent `put` into the namespace uses the key that already exists; it does not mint,
    and a `put` into a namespace that was never seeded still fails per UC-A3.3.

### 4.3 UC-A3.3 — Self write with no namespace key has no PQ fallback

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
    them is an explicit migration (B-3's lazy re-encrypt), never a side effect of a `put`.
  - In practice this case is rare, because a client mints for its preference namespace
    and its `rw` namespaces at init — so a namespace it writes to normally has a key
    before the first write.
  - **Built, and green live** (spike branch): the exception is
    `NamespaceKeyUnavailableException(atSign, namespace)`, raised by the CK-manager
    pre-pass so nothing is in flight when it fires; the query is
    `CryptoRuntime.isReadyFor(atSign, namespace)`; the opt-in is
    `AtClientPreference.allowLegacyCryptoFallback`, applied per write, which is what
    makes the fallback forward-only. Driven by the cold-start group in
    `tests/at_functional_test/test/nskey_data_path_live_test.dart`.

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

### 4.5 UC-A3.5 — The published nskey advertisement names its KEM and what it can open

- **Given:** `@alice` pq-native; `alice1` authorised for `app_1.my_apps`; the deployment
  configured for one of the two key-establishment algorithms.
- **When:** `alice1` mints and publishes the namespace key (as
  [UC-A3.2](#42-uc-a32--a-client-mints-and-publishes-the-nskey-for-each-namespace-it-is-authorised-for)).
- **Then:**
  - the APKAM-signed advertisement carries **`suites`** beside each entry's
    **`alg`** in `{v, createdAt, keys:[{use, alg, pub, kid}], suites}`.
    `alg` is not decorative: a sender cannot tell an X-Wing
    encapsulation key from an ML-KEM one by looking — both are opaque byte strings — and
    encapsulating under the wrong KEM produces a conveyance the owner can never open;
  - a CK conveyance into that namespace is sealed under the KEM `alg` names and stamped
    with the matching provider id, `at/nskey/XWING/AES/GCM` or
    `at/nskey/MLKEM1024/AES/GCM`. **Both providers are registered on every client**
    whatever this atSign itself mints, because a *recipient's* KEM is the recipient's
    choice; writes route by the destination's advertised algorithm and reads route by the
    id the record already carries, so conveyances written under either keep opening and
    there is no flag day;
  - an advertisement with **no `alg`** reads as the hybrid — which is what every one
    published before the field existed was, by construction, since no other KEM existed.
    One naming an algorithm this build cannot encapsulate to is **refused, not guessed
    at**;
  - the correspondence check on an arriving private re-derives the public half **through
    the advertised KEM** rather than assuming X-Wing. A seed arrives as bare bytes, and 32
    or 64 of them are valid for one KEM or the other, so the bytes alone cannot say which.
- **Then (the version is negotiated, not fixed):** `suites` says which sealing
  constructions the owner can **open**, which `alg` does not determine — a KEM key opens
  every construction built on that KEM. An X-Wing owner therefore receives `ver 0x02`
  and an ML-KEM-1024 owner `ver 0x03`, while an owner advertising only the retired
  `x-wing-hpke-v1` shares no construction and is **refused**. ⚠️ This paragraph said such
  an owner "keeps receiving `ver 0x01`" until 2026-08-18, when that version was retired.
  An advertisement carrying **no** `suites` field is refused at the parse rather than
  defaulted: unlike a key package, an advertisement is fetched by *senders*, who act on
  the claim immediately, so nothing may be assumed on the owner's behalf.
- **Cross-ref:** [`decisions.md` 50.3](detail/decisions.md#503-the-kem-is-configured-the-construction-is-negotiated);
  [`seal-spec.md`](seal-spec.md) (the two remaining versions and what each is attested by).

- **Cross-ref:** `design.md` (nskey data path: 3 layers / 3 providers, CK model, the
  nskey + its eager publication).
- **Impl/verify (A3.x):** **SS-4** (mints) + **B-1** (data path), and **KE-1** for
  UC-A3.5; harness at_chops
  vectors (KEM/seal) + at_client `dart test` round-trip for the data path, **plus**
  `tests/at_functional_test` runLocal.sh for UC-A3.2's per-enrollment nskey push and
  its server-gated `__ssenv` refusal ("an `app_2.my_apps`-only client is refused the
  `app_1.my_apps` nskey private" is a live-atServer assertion, not a client-only one).

## 5. A4 · E2EE across atSigns (shared data) + cross-atSign notification

### 5.1 UC-A4.1 — alice → bob, both PQ-native, bob has the namespace key

- **Given:** `@alice`, `@bob` pq-native; `@bob` published
  `public:__nskey.app_1.my_apps@bob` when he first used the namespace;
  `bob1`, `bob2` hold its private; the app is at stage `active` on both sides.
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

- **Given:** `@alice`, `@bob` pq-native; `@bob` published
  `public:__nskey.app_1.my_apps@bob` (there is no root fallback — nothing
  encapsulates to the signing root); the app at stage `active` on both sides;
  `bob1` running a monitor.
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
  - The notification scheme is the sending **app's** decision, exactly as a put's
    ([UC-B4.1](#111-uc-b41--active-pq-alice-shares-toward-a-bob-with-no-namespace-key)):
    toward a bob with no published nskey the write fails cold start or takes the
    explicit legacy fallback — never a silent downgrade.
  - Offline-then-online bob still decrypts the queued notification (key held, or
    pulled if it arrived meanwhile).
  - `appMetadata` is present on the notification frame; signal-only notifications are unaffected.

### 5.5 UC-A4.5 — A sender follows the recipient's advertised algorithm, not its own preference

- **Given:** `@alice`'s deployment is configured for `ml-kem-1024`; `@bob` published an
  **X-Wing** nskey and advertises an X-Wing key package.
- **When:** `alice1` shares `@bob:<k>.app_1.my_apps@alice`.
- **Then:**
  - the CK is sealed **under X-Wing**, to bob's key, at the strongest construction both
    sides list. Alice's configuration decides what `@alice` is a *recipient* for and
    nothing about who she can send to;
  - symmetrically, a hybrid-configured `@bob` seals to an ML-KEM-1024 `@alice` at
    `ver 0x03`. Every build produces and opens both;
  - **refusing would protect nothing.** It would leave two atSigns unable to communicate
    while the peer's key stayed exactly as strong as it was — the peer's key is the
    peer's decision.
- **Then (the KEM is configured, never negotiated):** each atSign advertises **one** KEM
  per generation, and rotation is the only moment that can change. There is no
  per-message KEM negotiation to attack, which is what SP 800-227 section 4.6.3 warns
  about when a protocol introduces additional choices ("could also introduce
  vulnerabilities (e.g. in the form of downgrade attacks)"). What *is* negotiated is the
  construction over that KEM — [UC-A4.6](#56-uc-a46--the-construction-is-negotiated-from-suites-and-no-shared-entry-is-a-refusal).

### 5.6 UC-A4.6 — The construction is negotiated from `suites`, and no shared entry is a refusal

- **Given:** two recipients holding the **same X-Wing key**, differing only in what their
  advertised record claims: one lists `x-wing-rfc9180-v1`, the other lists only the
  retired `x-wing-hpke-v1`.
- **When:** `alice1` seals to each.
- **Then:**
  - the peer that lists RFC 9180 receives `pqSeal ver 0x02`; the peer that lists only
    the retired construction is **refused**, because the two share no entry and sealing
    this client's own preference anyway would hand that peer a record it cannot open.
    ⚠️ Until `0x01` was retired this arm received `ver 0x01` instead — the negotiation
    is unchanged, only its outcome for a narrow peer. An advertisement carrying **no**
    `suites` field at all is refused at the parse, and always has been on this branch;
  - the payload's declared suite and the envelope's version byte **agree**. Both matter,
    and separately — the declared suite is what a receiver accepts on, and the version
    byte is what the construction is read under. A disagreement between them opens as an
    AEAD failure that names neither side, which is why the receiver cannot be the only
    guard: `pqSeal` refuses to emit a version whose KEM is not the one it was handed,
    comparing the encapsulation against the suite's `Nenc`;
  - the candidate suites are narrowed to the **chosen key's own KEM** before the
    intersection, so a suite can never be selected that the key cannot decapsulate:
    `alg` and `suites` are separate fields and a holder may advertise more than one KEM;
  - on parse, entries this build does not recognise are **kept**. The list is the
    holder's statement about itself, and a newer holder may name a construction we do not
    implement yet.
- **Then (this is what moves the wire without a flag day):** two clients that both
  advertise RFC 9180 exchanged `0x02` where they had exchanged `0x01`, with no
  readers-upgrade-first migration — and that is what later made it safe to drop `0x01`
  outright. That is the whole reason the field exists.
- **Verification note:** both arms must be asserted against the **same** key, so the only
  thing differing between them is what the record claims. Two arms that differ in key
  *and* claim prove nothing about the claim.

### 5.7 UC-A4.7 — No mutually supported construction is a refusal, not a guess

- **Given:** a recipient whose advertised record names only constructions this build does
  not implement (or a key package with no key this build can encapsulate to).
- **When:** `alice1` tries to seal to it.
- **Then:**
  - the operation is **refused** and nothing is written. Sealing under the sender's own
    preference would hand the recipient an envelope it cannot unwrap, and the failure
    would land on **their** side as an opaque AEAD error with nothing to point at —
    every AEAD-level failure collapses to one outcome by design
    ([`seal-spec.md`](seal-spec.md)), so a guess is unattributable by construction;
  - the same rule holds one level up, where the choice is per member rather than per
    write: in a namespace fan-out a member with no mutually supported key is **skipped,
    not fatal**, and every other member still receives its copy. One unusable
    advertisement must not cost the rest of the roster theirs.

- **Cross-ref:** `design.md` (the nskey + its eager publication, bilateral
  inbound forward-secrecy); `decisions.md` (forward-secrecy rationale, and
  [50](detail/decisions.md#50-two-kems-by-configuration-one-construction-by-negotiation-2026-08-07)
  for the KEM/construction split).
- **Impl/verify (A4.x):** **B-1** + **SS-4**, and **KE-1** for UC-A4.5/A4.6/A4.7; harness
  `tests/at_end2end_test` (cross-atSign). The negotiation itself is unit-provable, but
  **that the negotiated version is the version on the wire is not** — a fixture backing
  local storage and the atServer with one map cannot show it. That assertion is live, in
  `tests/at_functional_test/test/secret_sharing_delivery_test.dart`, reading the envelope
  back off the atServer and looking at the first byte.

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
  APKAM-signed advertisement, pushes the successor private to the surviving
  enrollments — seal to each surviving key package via `__ssenv`, dropping the revoked
  one. The lock is left to expire rather than deleted, and a rotation that finds the
  lock held **fails** instead of adopting what is there: adopting would have rotated
  nothing while reporting success, leaving the revoked enrollment on the live
  generation.
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
- **Impl/verify (A5.x):** **B-2** — landed 2026-08-06
  ([decisions 47](detail/decisions.md#47-b-2-lands-two-levers-and-the-difference-between-excluding-and-revoking-2026-08-06)).
  A5.1(a) is proven live by `tests/at_functional_test/test/content_key_rotation_live_test.dart`
  (both positions of the retention knob); A5.1(b), A5.2 and A5.3 by
  `tests/at_functional_test/test/nskey_rotation_live_test.dart`.
  **One clarification the live run forced, and it belongs in this catalogue
  rather than only in the code:** "excluded at **both** discovery+push and the
  `requestSecret` pull serve" (UC-A5.2) is achieved by the **revocation**, not
  by `excludeEnrollmentIds`. A still-approved enrollment is still a member of
  the namespace, so it asks any holder for the generation it can see published
  and is answered — the exclusion set stops one client pushing and cannot bind
  a holder that has only the atServer's word to go on. That is why
  `revokeEnrollmentAndRotate` revokes first: `enroll:listns` returns approved
  enrollments only, so the revoke is what removes it from every roster and
  every serve at once.

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
- **Impl/verify:** **green live 2026-08-08** —
  `tests/at_end2end_test/test/pq/legacy_server_abort_test.dart`, against a
  **pinned** pre-PQ atServer (`atsigncompany/virtualenv:vip-p3.15.0`). The pin
  is the point: `vip` gains post-quantum support and stops being a legacy
  atServer, so a row aimed at it would go quietly meaningless. Tagged
  `legacy-server` so the ordinary PQ job excludes it, and run by its own CI job.
  Verified in both directions — green against the pin, red against a PQ-capable
  image, so it cannot rot into a no-op.
  Writing it found a defect: the abort was clean but left the enrollment
  request it had just created `pending`, one per retry. at_auth 4.0.0-rc1 denies it
  on the way out; where it cannot (a scoped parent has no `__manage`) the
  refusal says so, and the second test asserts that limit rather than hiding
  it.

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
  5. If this enrollment is **fully privileged** (`rw` on `*` and `__manage`), take
     `_rootlock@alice`, generate the ML-DSA-65 root keypair and publish
     `public:pq_signing_root@alice` → **wins** → hold the private and convey it to the
     other fully privileged enrollments. A namespace-scoped enrollment skips this step
     entirely and proceeds without a root ([UC-B5.3](#123-uc-b53--two-enrollments-race-to-create-pq_signing_root)).
  6. The enrollment now holds its key material. Writing PQ remains the **app's
     release decision** — there is no readiness state to flip
     ([`decisions.md` 36](detail/decisions.md#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05)).
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
  **All three green 2026-08-05** — `tests/at_end2end_test/test/pq/retrofit_e2e_test.dart`
  drives the signing-root step in-flow (privileged mint, clone request+verify,
  scoped skip) and the two clones reaching distinct enrollment ids; the submit
  half is `tests/at_functional_test/test/self_enrollment_retrofit_live_test.dart`.
  See [`decisions.md` 45](detail/decisions.md#45-the-retrofit-rows-and-the-five-defects-the-first-end-to-end-run-found-2026-08-05).

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
- **Impl/verify:** **RF-SRV** + **RF-2c**. **Both green 2026-08-05** —
  `tests/at_end2end_test/test/pq/retrofit_retirement_e2e_test.dart`, on the one
  atSign whose atServer `runLocal.sh` gives a zero-hour
  `apkamSelfEnrollmentGraceHours` (720h is the ratified default, and a row
  cannot wait a month). The un-upgraded copy is refused with `AT0028 …
  expired or invalid`; a sibling legacy enrollment that never retrofitted
  still authenticates in the same run, and the same test against the default
  grace shows the copy authenticating normally — so the window is what
  decides, not the retrofit alone.

## 10. B3 · Mixed-PQ within one atSign

> **Rewritten 2026-08-05** around the app-decides model
> ([`decisions.md` 36](detail/decisions.md#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05)):
> there is no readiness marker and no negotiation. "Mixed within one atSign" means
> different **apps** at different stages (which never interact — they cannot read
> each other's namespaces) or one app's **installs** mid-rollout (the developer's
> release-ordering discipline). What the SDK must guarantee is the two-release
> ladder itself: the capability build reads everything and writes legacy; the
> active build writes PQ; nothing ever changes scheme silently.

### 10.1 UC-B3.1 — A capability-stage enrollment reads PQ but still writes legacy

- **Given:** `alice1` runs the app's **capability** build (era default: registered
  PQ providers, holds/mints the nskey, `defaultProviderId` legacy); a sibling
  install may still be on the previous build.
- **When:** `alice1` puts or notifies a self key both must read.
- **Then:** `alice1` writes/notifies **legacy**. Writing PQ is the *active*
  release's decision, never the capability build's — which is exactly what makes
  the capability build safe to roll out everywhere first. (Applies to **put and
  notify** alike; a notification an old install cannot decrypt is as lost as a
  record it cannot read.)

### 10.2 UC-B3.2 — The app's active release flips self data to the nskey path

- **Given:** the app ships its **active** build (4.x default, or an explicit
  `AtClientPreference.crypto`); every install has run the capability build first
  (the developer's release-ordering discipline).
- **When:** `alice1` writes/notifies self data.
- **Then:** self data goes via the **nskey data path** — `at/nskey` conveys the CK
  sealed to the nskey (`recipientKind: nskey`) and `at/symmetric/AES/GCM` encrypts
  the data; the data is never encapsulated directly to the nskey. Capability-stage
  installs read it (reads are universal), so no install that followed the ladder
  loses access.

| install | stage  | data-reads               | data-writes          |
|---------|--------|--------------------------|----------------------|
| E1      | active | legacy + nskey data path | nskey data path      |
| E2      | cap    | legacy + nskey data path | legacy               |

- **Cross-ref:**
  [`decisions.md` 36](detail/decisions.md#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05)
  (the two-release model) and
  [27](detail/decisions.md#27-the-era-default-read-the-new-scheme-everywhere-write-it-once-2026-08-04)
  (the era default that *is* the capability stage);
  `design.md` [section 1.8](design.md#18-migration-rollout--the-disallowlegacyencryption-flag-d1-c--d1-d).
- **Impl/verify:** the era default + data path (**built**; unit
  `crypto_era_default_test`, e2e `era_default_read_test`) + **RF-2c**.

## 11. B4 · Mixed-PQ across atSigns

> **Rewritten 2026-08-05.** Within a namespace, cross-atSign traffic is between
> installs of the **same app** — there are no strangers — so "mixed across
> atSigns" means the same app at different stages on the two sides. The SDK's
> whole contribution is the **cold-start gate**: refuse by name when the
> destination has no key, take legacy only on explicit opt-in, never substitute a
> scheme silently
> ([`decisions.md` 36](detail/decisions.md#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05)).

### 11.1 UC-B4.1 — Active-PQ `alice` shares toward a `bob` with no namespace key

- **Given:** alice's install is at stage `active`; bob's install has never run the
  capability build, so `public:__nskey.app_1.my_apps@bob` does not exist. Bob's
  atSign holds a `public:publickey` (the retained-by-default legacy material,
  [`decisions.md` 37](detail/decisions.md#37-legacy-key-material-is-retained-until-the-ecosystem-is-pq-not-the-atsign-2026-08-05)).
- **When:** `alice1` shares or notifies `@bob:<k>.app_1.my_apps@alice`.
- **Then:** the write **fails cold start by name**
  (`NamespaceKeyUnavailableException(@bob, app_1.my_apps)`), unless the app opted
  into `allowLegacyCryptoFallback` — in which case it goes out **legacy** to bob's
  `publickey` (per-value symmetric key RSA-wrapped inline, the monolithic legacy
  model), and the *first write after bob's key appears* is PQ with no flag to
  flip. A PQ self-copy for alice's own scope proceeds **independently** either
  way. Never a silent downgrade: the app chose the fallback or the app sees the
  refusal.

### 11.2 UC-B4.2 — Legacy `@alice` receives from PQ `@bob` (the interop question)

- **Given:** `@alice` legacy (no `pq_signing_root`, no nskeys — a pre-PQ atSign);
  `@bob` PQ-native.
- **When:** `bob1`'s app shares with `@alice` (and, in the reverse direction, a
  legacy app on `@alice` shares with `@bob`).
- **Then:** **interop works by default in both directions**, because legacy
  material outlives the atSign's own migration
  ([`decisions.md` 37](detail/decisions.md#37-legacy-key-material-is-retained-until-the-ecosystem-is-pq-not-the-atsign-2026-08-05)):
  toward alice, bob's app uses the explicit legacy fallback to
  `public:publickey@alice`; toward bob, alice's legacy app finds
  `public:publickey@bob` because even a PQ-native onboard publishes it by
  default. **Test outcome (reversed from the original Decision #1):** a
  legacy-peer send is **supported by default**; only an atSign that set the
  legacy-interop **opt-out** refuses it — deliberately, and loudly.
- **Cross-ref:** [Decision #1](detail/decisions.md#numbered-rulings-14) (original ruling,
  default reversed by
  [37](detail/decisions.md#37-legacy-key-material-is-retained-until-the-ecosystem-is-pq-not-the-atsign-2026-08-05)).
- **Impl/verify:** **green live 2026-08-08** —
  `tests/at_functional_test/test/pq_legacy_interop_live_test.dart`, three atSigns
  the test CRAM-activates itself: a pre-PQ one (default signing algorithm, so no
  signing root — asserted against the PQ-native one as a control), a PQ-native
  one, and a PQ-native one activated with `mintLegacyMaterial: false`. Inbound,
  outbound (refused by name, then opted-in and stamped legacy, then read by the
  peer) and the opt-out all covered. It is in the **functional** pack, not
  `tests/at_end2end_test`: that pack runs in CI against long-lived cicd atSigns
  and can never CRAM-activate anything. Running it turned up
  [plan 14.12](implementation-plan.md#1412-a-mintlegacymaterialfalse-atsign-cannot-write-a-public-record)
  — the opt-out is not yet a usable configuration.

### 11.3 UC-B4.3 — Mid-rollout `@alice` (one install active, one still old) shares with `@bob`

- **Given:** alice's app is mid-rollout: `alice1` runs the active build, `alice2`
  an old pre-capability build; bob's side holds the namespace key.
- **When:** `alice1` shares/notifies `@bob`.
- **Then:** the write toward `@bob` takes the **nskey data path**, and alice's
  **self-copy** does too — which `alice2` cannot read. That is the
  release-ordering discipline violated (`active` shipped before the capability
  build reached every install), and it is the **app developer's** failure mode,
  not the SDK's to detect: the remedy is updating `alice2`, and everything
  written stays readable to it the moment it is
  ([`decisions.md` 36](detail/decisions.md#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05).2 item 4).
  What the SDK guarantees: `alice2`'s *own* writes still work (legacy), nothing
  it wrote becomes unreadable to anyone, and its upgrade is purely additive.

### 11.4 UC-B4.4 — Bob's install reaches capability → alice's shares flip to PQ

- **Given:** bob's install runs the capability build for the first time: it
  mints/publishes `public:__nskey.app_1.my_apps@bob` (or pulls the private if the
  key exists, [`decisions.md` 38](detail/decisions.md#38-key-material-self-heals-mint-if-absent-else-pull-2026-08-05)).
  Alice's install is at stage `active`.
- **When:** `alice1` next shares/notifies `@bob`.
- **Then:** alice's next `ensureCurrent` re-`plookup` finds bob's advertisement,
  and the write goes via the **nskey data path** — `at/nskey` conveys the CK
  sealed to bob's published nskey (`recipientKind: nskey`),
  `at/symmetric/AES/GCM` encrypts the data. Cold start (or the fallback, if
  opted-in) ends for bob **without any action from alice**: the recipient's key
  appearing is the whole trigger.

- **Cross-ref:** `design.md` [section 1.6](design.md#16-the-uniform-data-flow--cold-start--resolutionordering) (cold start), [section 1.8](design.md#18-migration-rollout--the-disallowlegacyencryption-flag-d1-c--d1-d) (the two-release model);
  `roadmap.md` (migration philosophy).
- **Impl/verify:** cold start + fallback (**built**; unit `cold_start_test`, e2e
  `nskey_recipient_not_ready_test`, `nskey_cross_atsign_test`) + **RF-2c** for
  the retrofit-driven live orchestration; harness `tests/at_end2end_test`.

## 12. B5 · Edge cases

### 12.1 UC-B5.1 — Offline enrollment pulls `pq_signing_root` later

- **Given:** `alice2` (an enrollment) was offline during the retrofit wave;
  `pq_signing_root` created by `alice1`.
- **When:** `alice2` next comes online and retrofits.
- **Then:** `pq_signing_root` is root (no namespace), so it has **no**
  `enroll:listns` push — its `requestSecret` for `pq_signing_root@alice⁻¹` is
  the steady-state path, answered by any online holder (persists until one answers).
  Namespaced `nskey` privates `alice2` missed while offline arrive by **its own
  pull at next start** ([`decisions.md` 38](detail/decisions.md#38-key-material-self-heals-mint-if-absent-else-pull-2026-08-05)
  — an enrollment created or offline after the mint missed the push, so pulling
  is its normal path, not a backstop), answered store-and-forward by any current
  holder whenever that holder next runs. (Pull = `requestSecret` and push =
  `pushSecretToNamespaceMembers` are dual facets of one substrate — see `design.md`.)

### 12.2 UC-B5.2 — Reading legacy history after retrofit

- **Given:** `alice1` retrofitted; the old legacy enrollment aged out; the legacy
  *encryption* key is retained (the legacy APKAM is not separately deleted — there is
  no per-key delete).
- **When:** `alice1` reads pre-PQ data.
- **Then:** decrypts via the legacy provider (reads are universal); `providerId` routes
  per value. PQ retrofit never makes old data unreadable.

### 12.3 UC-B5.3 — Two enrollments race to create `pq_signing_root`

- **Given:** `alice1` and `alice3` both reach the mint step with `pq_signing_root` absent.
- **When:** both attempt to take the `_rootlock@alice` mint lock.
- **Then:** exactly one takes it, re-reads the record under it and publishes. The loser
  is refused the lock and falls through to *request* — it generates no keypair and
  files nothing, so there is no orphaned data and nothing to discard. A split root
  would still be unrecoverable, since D1 builds the root's rotat*ability* and not a
  rotation that could reconcile one; what makes this a benign race is the lock, plus
  the reconciliation that retires a held private the record does not advertise.

- **Cross-ref:** `design.md` (push/pull duality — substrate facts stated once there).
- **Impl/verify:** **RF-1** (`requestSecret` confirm) + **B-1** (provider routing).

### 12.4 UC-B5.4 — Two enrollments race to mint a namespace's nskey

The nskey twin of [UC-B5.3](#123-uc-b53--two-enrollments-race-to-create-pq_signing_root),
and the property [decisions 105](detail/decisions.md#105-the-nskey-mint-elects-a-winner-2026-08-16)
exists to hold: *if enrollments A, B and C all decide they need to mint, only
one of them eventually does.*

- **Given:** `alice1` and `alice3` both decide namespace `n` needs an nskey.
  Each has already read and found none — **from the atServer**, not from local
  storage, because a sibling's publication is absent locally until sync catches
  up and reading that absence as a cold start is what mints a second key.
- **When:** both attempt the `_nskeylock.n@alice` lock, within a bounded window.
- **Then:** exactly one takes it. It **re-reads under the lock**, because a
  sibling may have published between its first read and the take, and **adopts**
  what it finds rather than overwriting it. The loser re-reads once: it adopts a
  published key if there is one, and otherwise **fails loudly** rather than
  minting or waiting — a `put` blocked on another device's crash must not hang,
  and the retry is the next client start, which is where minting is triggered
  from anyway.

- **Cross-ref:** `design.md` §  the nskey mint lock; `seal-spec.md` (kid addressing).
- **Impl/verify:** **SS-4** (mint) + **B-1** (provider routing).

### 12.5 UC-B5.5 — The mint lock has no release but its ttl

- **Given:** an enrollment holds `_nskeylock.n@alice` or `_rootlock@alice` and
  finishes minting.
- **When:** it completes, successfully or not.
- **Then:** it **does not delete the lock**. The ttl is the only release, which
  is what makes the record an *election token with a cooldown* rather than a
  mutex: holding it for the whole ttl says "an election happened recently, do
  not hold another one". A lock nobody deletes has no stolen-release window,
  so a holder that overruns cannot free a successor's lock. A lock key
  presented with **no ttl is refused outright** — with nothing deleting the
  record, a missing ttl would block minting permanently rather than late.

- **Cross-ref:** `design.md` (the two mint locks and what each guards).
- **Impl/verify:** **SS-4**.

### 12.6 UC-B5.6 — A rotation inside the cooldown is refused, and succeeds after it

The consequence of [12.5](#125-uc-b55--the-mint-lock-has-no-release-but-its-ttl)
that a caller can see. It is here because it changes an API's observable
behaviour, and because **no unit test can find it**: the interlock *is* the
atServer refusing a second create of an immutable record, and a mocked
`executeVerb` accepts the second take, so the mechanism's presence and its
absence are indistinguishable under mocks.

- **Given:** namespace `n` was minted or rotated within `mintLockTtl`, so the
  lock is still held by its own ttl.
- **When:** the same enrollment asks to rotate `n`.
- **Then:** the rotation is **refused**, with an error naming the cooldown and
  saying the retry must wait the ttl out — the one thing the caller can act on.
  Once the ttl lapses the same call from the same client for the same namespace
  is **accepted**, which is the control that makes the refusal mean something.
  ⚠️ `revokeEnrollmentAndRotate` revokes first, so a refusal here leaves the
  enrollment cut off from the atServer while still holding the live generation.
  It catches per namespace, logs `severe`, and carries on to the others rather
  than sleeping for the ttl inside a call that has already done the destructive
  half.

- **Cross-ref:** [decisions 105.6](detail/decisions.md#1056-built-the-cooldown-binds-rotation-too).
- **Impl/verify:** **SS-4** + **B-2** (revocation).

### 12.7 UC-B5.7 — A winner that overruns its lease publishes nothing

- **Given:** `alice1` takes the lock at T0 and is still minting at T0+ttl. The
  lock expires, `alice3` wins the next election, re-reads, finds nothing
  published, and mints.
- **When:** `alice1` finally reaches its publish.
- **Then:** it **abandons**. The holder carries a lease stamped *before* the
  take goes out — so "unspent by my clock" implies the atServer has not expired
  it either, and the client errs early rather than late — and refuses to publish
  once the lease is spent. That turns "two mints" into "one mint, by `alice3`",
  which is the requirement. The bounded window in the election covers when the
  three *attempt*, never how long the winner *takes*, so without this the
  property fails on any slow minter.

- **Cross-ref:** `design.md` (the mint lock's two windows).
- **Impl/verify:** **SS-4**.

### 12.8 UC-B5.8 — A client that configures nothing still takes part

The strongest product claim D1 makes, and it had live proofs on both sides and
no use case. An app that never mentions crypto is the common case; if it has to
name a `CryptoConfig` to interoperate, PQ is opt-in in practice however the
flags are set.

- **Given:** a client constructed with **no `CryptoConfig` at all** — not a
  default one, none.
- **When:** it resolves providers for a namespace, and separately, when a peer
  seals data to it.
- **Then:** the era default supplies the nskey providers, and the client opens
  what the peer sealed. Configuration selects *behaviour*, never *capability*.

- **Cross-ref:** `design.md` (the era default).
- **Impl/verify:** **B-1** (provider routing) + **RF-2c**.

### 12.9 UC-B5.9 — A conveyed private is filed only if it is addressed here

- **Given:** privates are conveyed to an enrollment over the envelope channel
  and swept off the atServer into the keyfile.
- **When:** the sweep encounters a private addressed to a **different** key
  package.
- **Then:** it is **not filed**. Sweeping is not the same as accepting: the
  channel is a shared surface, so "it arrived" can never be the test for "it is
  mine". The addressed-to-me check is what stops one enrollment collecting
  another's material by being first to look.

- **Cross-ref:** `design.md` (conveyance and the key package).
- **Impl/verify:** **SS-2**.

### 12.10 UC-B5.10 — An enrollment not entitled to the root does not ask for it

The refusal half of [UC-B5.1](#121-uc-b51--offline-enrollment-pulls-pq_signing_root-later),
which proves the positive. A pull path that asks unconditionally turns every
enrollment into a supplicant for material it may not hold, and the holder's
answer is the only thing standing between them.

- **Given:** an enrollment whose grants do not entitle it to the signing root.
- **When:** it reaches the point where an entitled enrollment would request the
  root private.
- **Then:** it **does not ask**. The check is on the seeker, before the
  request, not only on the holder answering it.

- **Cross-ref:** `design.md` (the signing chain and entitlement).
- **Impl/verify:** **SS-1c**.

### 12.11 UC-B5.11 — An enrollment that missed the mint heals from a holder

- **Given:** a namespace was minted while this enrollment was absent, so it
  holds no private for the advertised generation.
- **When:** it next starts.
- **Then:** it **requests the private from a holder** and files it, rather than
  minting a rival generation. This is what makes a losing or absent enrollment
  *inert* rather than divergent, and it is why the nskey path needs no retire:
  a generation nobody advertises is never selected, because selection is by the
  kid in the envelope being opened.

- **Cross-ref:** [decisions 104.2](detail/decisions.md#1042-both-paths-already-heal-a-loser--by-different-moves).
- **Impl/verify:** **SS-2** + **SS-4**.

### 12.12 UC-B5.12 — The owner verifies her own advertisement as a peer would

- **Given:** `alice` published an nskey advertisement for a namespace.
- **When:** `alice` herself resolves and verifies it.
- **Then:** she takes the **same verify path a peer takes** — no owner
  shortcut. One path means a defect in verification cannot hide behind the
  common case, and it is what makes "same-atSign and cross-atSign are the same
  code" a tested property rather than an aspiration. A namespace nobody minted
  for resolves to nothing rather than to an error or a guess.

- **Cross-ref:** [UC-A3.5](#45-uc-a35--the-published-nskey-advertisement-names-its-kem-and-what-it-can-open).
- **Impl/verify:** **SS-4** + **B-1**.

---

## 13. Cross-cutting acceptance (applies to all flows)

These invariants are testable against **every** UC above:

- **Reads are universal.** A client decrypts anything ever written to it (all
  providers retained); upgrading only ever **adds** read-capability.
- **No silent scheme substitution, in either direction.** The SDK never chooses
  post-quantum behind the app's back (writing PQ is the app's release decision —
  a capability-stage client writes legacy however much it can read), and never
  downgrades behind its back either: a PQ write to a keyless destination is
  refused **by name**, legacy is reachable only via the explicit
  `allowLegacyCryptoFallback` opt-in, an explicitly requested provider id is
  never substituted, and under `disallowLegacyEncryption = true` a legacy-only
  destination is **refused**, never quietly written legacy.
  *(Replaces "writes gated by reader readiness", 2026-08-05 —
  [`decisions.md` 36](detail/decisions.md#36-the-rollout-is-the-apps-decision-capability-markers-built-examined-and-removed-2026-08-05).)*
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
- **Immutability, and where it applies.** Neither key record is immutable, and both
  are minted behind one. `public:__nskey.<ns>@owner` is mutable because nskey-keypair
  rotation has to overwrite it; `public:pq_signing_root@owner` is mutable because
  advertising a successor beside a retired predecessor is the same rewrite
  ([`decisions.md` 101](detail/decisions.md#101-the-signing-root-becomes-an-ordinary-signing-key-and-rotatable-2026-08-15)).
  What stops two of the owner's enrollments racing is a short-ttl **immutable** lock
  key — `_nskeylock.<ns>@owner` and `_rootlock@owner` — and what stops substitution is
  the APKAM signature over the advertised envelope, not the write mode. A lock is a
  protocol with a window where a refused create was absolute, and what covers the
  difference is reconciliation on every start, not the write mode either.
- **A second signing root is representable, publishable and verifiable.** A
  keyfile and the record each carry two root entries — one active, one retired
  — a link signed under the **retired** one still verifies, and signing selects
  the active one. This is D1's boundary
  ([`decisions.md` 101](detail/decisions.md#101-the-signing-root-becomes-an-ordinary-signing-key-and-rotatable-2026-08-15)
  requirement 5): D1 builds the root's rotat*ability* and not the rotation, so
  the two-entry state is written by hand rather than reached by rotating.
- **Published nskeys are fetchable but not enumerable.** `public:__nskey.<ns>@owner`
  resolves on an exact `plookup`, cross-atSign, and appears in **no** scan — with or
  without `showhidden`, authenticated or not. This is a guaranteed protocol property
  (`_apsk` already relies on it); the test is a regression guard, not a proof obligation.
- **Advertised recipient keys are signed and verified.** Every advertised
  encapsulation key — the per-enrollment key package (`metadata.keyPackage`) and the
  published `nskey` public half — is an **APKAM-signed
  envelope** produced by the generating enrollment (`wrapAndSign`). A fetcher verifies
  it against that enrollment's `_apsk` **the same way same-atSign and cross-atSign**
  (fetch `public:_apsk.<eid>.a.__e@owner`, resolve the strongest algorithm the
  envelope and that `_apsk` share, and verify under the `typ` the reader expects) **before** encapsulating to it; a **tampered, unsigned, or
  wrong-signer** advertised key is **rejected**. The atServer keeps every approved
  enrollment's `_apsk` **present** (fetchable without a client publish) and
  **write-restricted** (a cross-enrollment overwrite is refused). *(Holds today for **both**: the
  published `nskey`, signed at mint and verified before sealing, proven cross-atSign on
  the live wire; and the **key package**, signed by
  `KeyPackageRegistration.signedKeyPackagePayload` and verified by
  `VerbEnrollmentDirectory` — unsigned, tampered, wrong-signer and forged-claim packages
  are all rejected. **The atServer's `_apsk` guarantee is now proven live too** (2026-08-04,
  `apsk_server_side_test.dart`): the record is fetchable without the enrolling client ever
  publishing it, a cross-enrollment overwrite is refused as an authorization decision naming
  both enrollments and leaves the record byte-identical, and the same connection *can* write
  its own — so the restriction is per-enrollment rather than a blanket ban. `enroll:listns` is
  driven live in the same file. All three needed two genuine APKAM enrollments, since the case
  that matters is one enrollment reaching for another's record.)*
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

How this catalogue gets proven, and where each row's proof lives. Ruled
2026-08-23 as
[decision 115](detail/decisions.md#115-the-acceptance-suite-is-4-arms-and-a-ledger-not-one-grid-2026-08-23).

gkc's framing, which is what the design answers: *"we have literally hundreds of
functional and end to end tests which cover the acceptance tests together. But
there is no definitive place where it is easy to see the entirety of the pq
project's acceptance tests being proven. The posture matrix test is the logical
place to build test out."* So the problem is legibility rather than coverage.

### The test layers, and the four live packs

| Layer | Covers |
|------------------------------------|------------------------------------------------------------------------------------------|
| **at_chops vectors** | KEM / seal / ML-DSA primitives (X-Wing encap/decap, pqSeal/pqOpen, `mldsa65` verify). |
| **at_client `dart test`** | data-path providers (`at/nskey`, `at/symmetric/AES/GCM`), CK cache, round-trip equality. Run with `--concurrency=1`. |
| **`tests/at_functional_test`** | same-atSign self keys, enroll / `listns` round-trip, `__ssenv` delivery, and the rollout matrix. `docker compose down` before each run; cap runs at 180000 ms. |
| **`tests/at_end2end_test`** | cross-atSign shares and notifications, retrofit, the capability→active transition. |
| **`tests/at_onboarding_cli_functional_tests`** | CRAM activation through the CLI, and the only place a client is built from a `PqPosture` in two arms. |
| **`tests/at_onboarding_cli_functional_tests_proxy`** | the CLI against a proxied atServer. |

**Baseline (already shipped, not pending work).** The primitive layer is
published: **#1930** (M0 crypto seam) and **#1993 / at_chops 3.3.0**
(`pqSeal`/`pqOpen`), with **PR #2035** (design fixes) merged. at_chops-vector
coverage exercises this shipped base. As of the **2026-07-17 release train** the
baseline also includes **at_chops 3.4.0** (ML-DSA-65 verify dispatch, AES-GCM
FFI), **at_commons 5.13.0**, **at_client 3.14.0** (carrying the SS-0 substrate,
PR #2037) and **at_auth 3.3.0-rc1** (extended `AtKeys` + `AtKeysIo.flush()`), so
SS-0 / SS-1b / S-1 / S-2 acceptance is against shipped code.

⚠️ **`tests/` holds 7 Dart packages, of which 4 are live test packs.** The
other 3 are `tests/pq_matrix/{current,published,scenario}` — the child processes
the pair grid spawns, which is why the `published` column can hold a released
at_client this tree cannot. Count them with `find tests -name pubspec.yaml`, not
`tests/*/`: a depth-2 glob returns 4 and reads as the whole answer.

⚠️ **The live corpus is 4 packs, and every earlier measurement here counted 2.**
No `provenIn` citation reaches either CLI pack, which is why the CLI pack's
two-arm posture differential — the best live evidence for UC-C1.6 and a second
live proof of UC-A1.1 — is invisible from this catalogue. Counted 2026-08-23,
the strict matcher gives **194** live `test()` declarations across all 4 and a
multi-line-aware one **247**; the gap is entirely declarations whose name sits
on the next line, since an any-position same-line matcher also returns 194.

```bash
grep -rhoE "^[[:space:]]*test\([[:space:]]*'" tests/ --include='*.dart' | wc -l   # 194
perl -0777 -ne 'while (/(?<![A-Za-z0-9_])test\(\s*[\x27"]/gs){$n++} END{print "$n\n"}' \
  $(find tests -name '*.dart')                                                    # 247
```

⚠️ **The image-override gap this section used to describe is closed.** It read
that both packs pin `atsigncompany/virtualenv:vip`, that "no work package
delivers an image-override path", and asked for "an image-override env var
(e.g. `VE_IMAGE`) honoured by **both** `runLocal.sh` harnesses". That env var
exists and is called `VIRTUALENV_IMAGE`: both harnesses read it and default to
the locally built `at_virtual_env:local`, and CI runs against
`atsigncompany/virtualenv:dev_env` rather than `:vip`. The advice that a green
local run does not imply CI parity still holds — check which image produced a
result before citing it.

### Where the catalogue actually stands

Coverage was never the gap. Of the 68 live use cases, 59 have live proof of some
kind and 9 have none:

| Verdict | Rows | Means |
|-----------------|-----:|--------------------------------------------------|
| LIVE_DIRECT | 12 | a live test's assertions establish the row |
| LIVE_PARTIAL | 43 | some clauses established, others not |
| LIVE_INCIDENTAL | 4 | the mechanism runs, nothing asserts the row |
| NO_LIVE_PROOF | 9 | nothing live exercises it |

What is missing is the ability to address that proof. There are 135
`provenIn(...)` citations, splitting **68 into a live pack** and **67 at
in-package unit tests**, so half of this catalogue's PROVEN rows rest on mocks
while the status table's `68 PROVEN · 0 BLOCKED` does not distinguish the two.

```bash
perl -0777 -ne 'while (/provenIn\(\s*'"'"'([^'"'"']+)'"'"'/gs) { print "$1\n" }' \
  packages/at_client/test/acceptance/*_test.dart | sort | uniq -c
```

⚠️ **Use that command rather than a single-line-anchored one.** `provenIn(` is
routinely formatted with its path on the next line, so a same-line matcher
reports 62 citations over 18 files — wrong, and it does not look wrong.

A citation also cannot be told from prose: `proven_elsewhere.dart:40` is
`expect(source.contains("'$testName"), isTrue)`, a bare substring anywhere in
the file, so a comment, a `group(` name or a line of doc text satisfies one.
Nothing has rotted through this yet — all 68 live citations currently
prefix-match a real test.

### Why a posture grid is the wrong default

`PqPosture` declares 9 axes and only 6 vary across the 3 stages.
`mintLegacyMaterial`, `sealsToKeyAlgorithms` and `keyEstablishmentAlgorithms`
are byte-identical at legacy, pqReady and pqActive, and the last one's dartdoc
calls it a deployment decision rather than a stage decision. Any row whose
clauses turn on those three is posture-invariant by construction.

A3 is the clearest case. The live proof in `nskey_data_path_live_test.dart`
builds its client from a bare `AtClientPreference` — therefore
`PqPosture.legacy` — and then sets `..crypto = CryptoConfig.nskey(...)`. Every
clause it asserts is already proven at the legacy stage and is identical at the
other two. What the posture decides is not what the data path guarantees, but
whether an app that configures nothing enters it. 3 of the 5 A3 rows do not vary
at all; the 2 that do are [UC-A3.2](#42-uc-a32--a-client-mints-and-publishes-the-nskey-for-each-namespace-it-is-authorised-for),
because `seedNamespaceKeys` is false at legacy so whether the mint fires is a
stage decision, and [UC-A3.3](#43-uc-a33--self-write-with-no-namespace-key-has-no-pq-fallback),
whose legacy escape hatch pqActive closes.

Sorting all 68 by the shape that could prove them:

| Kind | Rows | Shape that proves it | Arm |
|-----------------------|-----:|------------------------------------|--------|
| Axis rows | 6 | one client at a known stage | 1 |
| Consequence rows | 15 | one client at a known stage | 1 |
| Cross-stage rows | 3 | a sender × receiver cell | 2 |
| Transition rows | 3 | a client that moves stage | 3 |
| Stage-invariant | 38 | wherever they are proven now | ledger |
| Vacuous at legacy | 3 | a stage-aware Given, or excluded | — |

The existing 4×4 serves the 3 cross-stage rows and cannot express a transition.
Its own dartdoc says why: *"Minting happens ONCE, at enrolment time, never in
the cells"* (`pq_rollout_matrix_test.dart:94`), because a per-cell re-mint churns
the advertisement into a shape [UC-G1.14](#uc-g114--pqready-is-invisible-to-a-deployed-peer)'s
released reader cannot take. Growing the grid to carry the catalogue would run
38 rows as 16 identical copies of one assertion, and 3 more would pass vacuously
at legacy where their Given is unsatisfiable.

There is also an axis that is not the client's posture at all:
[UC-B0.1](#uc-b01--a-pq-capable-client-cannot-pq-upgrade-against-a-legacy-atserver)
varies by atServer version, and survives today as a tagged special case against
a pinned `virtualenv:vip-p3.15.0` in its own CI job.

### The four arms

**Arm 1, the stage arm.** 3 cells, one client per `PqPosture`, asserting the 21
axis and consequence rows. `TestUtils.getPreference(atSign, posture:)` already
takes a posture, so this is the cheapest arm to build, and it closes the highest
value empty row as a by-product: `disallowLegacyEncryption` has no setter and no
constructor argument, so a posture is the only way to reach it, and it has **0**
hits under `tests/` against a live refusal at `at_client_impl.dart:753`.
[UC-C1.2](#152-uc-c12--the-refusal-axis-the-posture-disallows-legacy-writes)
has never executed.

**Arm 2, the pair grid.** The existing 4×4 stays as it is, serving the 3 rows
that need two stages at once. The `published` column must stay an out-of-process
arm, since a released at_client and this tree cannot live in one process.
⚠️ The cells are **not** posture-faithful today —
`tests/pq_matrix/current/lib/arm.dart` takes only two axes from the posture, so
every cell runs at `PqPosture.legacy` on the era-default, seeding and
write-default axes. A pqActive cell that inherited `disallowLegacyEncryption`
would refuse writes to any unseeded peer and fail for a reason that is not the
thing under test.

**Arm 3, the transition arm.** A cell is a state, and this catalogue is full of
edges: the retrofit trio, the retirement pair, the capability flip, rotation and
revocation, heal-from-a-holder, and the rollout ladder rows UC-G1.7 to UC-G1.9.
This arm asserts the invariant *across* the change rather than at either end,
which no cell can do.

**Arm 4, the server-version arm.** Client posture crossed with atServer version,
built as ephemeral environments at named `at_server` refs. This retires the
`legacy-server` tag and the pinned image as special cases, and gives UC-B0.1 an
ordinary home.

### The generated ledger

38 rows will never sit in a matrix and still have to be visible, so the
definitive place is a generated page rather than a directory.

Each live test declares the clauses it proves. Each pack writes a results file
as it runs. One reporter merges them and renders this catalogue with every row
marked proven-by-what in that run. A row no pack exercised reports
`not-exercised-in-this-run` rather than green — a state the current design
cannot express at all, because a citation is satisfied whether or not anything
ran.

**Clause-level rather than row-level** is what makes it worth building. It turns
"UC-A2.5 has 3 unproven clauses" from a footnote somebody found by reading into
a computed fact, and it is the mechanism that closes those clauses structurally.
`tests/at_end2end_test/test/suite_manifest_test.dart` is the precedent for the
in-pack half: a rail that runs in the package owning the evidence, so a rename
reddens the pack that caused it.

### The two environments: VE and EE

gkc ruled 2026-08-23 that the suite is not constrained to the virtual
environment. That changes what arm 3 can be, because arm 3 is blocked on the VE
for a structural reason rather than an effort one: a transition has to re-mint,
`(appName, deviceName)` is one-shot server state, and CRAM activation is one-shot
per atSign per virtualenv. That is what the atSign ledger in
`tests/at_functional_test/config/config.yaml` records, and why the matrix forbids
re-minting in cells.

The ephemeral environment removes the constraint rather than working around it.
Read from `at_server` at `origin/trunk`:

- `tools/build_ephemeral_environment/ee_base/Dockerfile` does `COPY . .` and
  compiles `packages/at_secondary_server/bin/main.dart`, so an EE built at ref X
  **is** an atServer at ref X. That is arm 4, from any ref.
- The atSign list is a mounted file (`/tmp/setup/atsigns`), defaulting to 26
  phonetic-alphabet atSigns, so each arm gets atSigns named for their role and
  freshly CRAM-activatable rather than drawn from a shared one-shot pool.
- `runee.sh <name> <base-port>` runs several EEs side by side, each claiming a
  100-port range bound to 127.0.0.1.

The harness already fits. The EE serves the same `vip.ve.atsign.zone`
certificates as the VE, so the root domain does not change and the 42 files
carrying that literal are untouched. `TestUtils.rootServerPort` reads
`VIRTUALENV_BASE_PORT`, and its comment — *"a base-port virtualenv puts the root
server at the base port itself"* — describes the EE's `EPHEMERAL_BASE_PORT`
contract exactly. Pointing an arm at an EE is 2 environment variables.

⛔ **Build every EE from a named ref; never pull `ephemeral:latest`.**
`atsigncompany/ephemeral` is rebuilt **monthly** (newest tag 2026-08-15) while
the VE publishes per commit, so `:latest` walks straight back into "the
published image cannot verify ML-DSA PKAM". The VE stays as it is for the
existing functional pack.

### Prerequisites for the build

Each verified against the tree rather than assumed.

✅ **~~The functional pack has no test-selection machinery.~~ Built 2026-08-23.**
It read: "`tests/at_functional_test/dart_test.yaml` does not exist and no file
in that pack carries `@Tags(['pq'])` — 0 hits, against 9 in the e2e pack as a
control." That pack now declares the `pq` tag and **29** of its 49 test files
carry it, chosen by the mechanisms they drive rather than by their names — two
of the most important (`copied_keyfile_test`, `crypto_era_default_test`) have
no `pq` in their filename at all.

⛔ **It has no `paths:` allowlist, deliberately**, which is the difference from
`tests/at_end2end_test`. That pack allowlists because its atSigns are
long-lived and real, and it pays for that with the risk that an unlisted test
silently never runs. This pack's virtualenv is created and thrown away per run,
so an allowlist would carry the same risk with none of the benefit. A bare run
still executes every file.

`test/pq_tag_test.dart` is the rail that keeps the set honest: it re-derives
which files should carry the tag and fails naming any that do not, so a new PQ
test cannot quietly sit outside the set the stage and matrix arms select on. It
is mutation-proven — removing one tag reddens it with that filename — and it
carries both controls, a real PQ file and a real non-PQ one, so a broken
matcher is distinguishable from a clean pack.

**~~A posture-faithful pqActive cell cannot notify yet.~~ Measured 2026-08-23:
the monitor failure is real but is NOT posture-dependent.** A throwaway probe
ran the two postures as equal-length interleaved arms across 2 fresh
virtualenvs, waiting 45s on each client for any notification:

| Arm | Monitor received | Silent |
|-------------------------|-----------------:|-------:|
| `PqPosture.pqActive` | 16 of 18 | 2 |
| default (control) | 18 of 20 | 2 |

The arms genuinely differed in the thing varied — every pqActive client resolved
`SigningAlgoType.mldsa65`, every control client resolved null and fell back to
`rsa2048` — and the atServer's own log carries `signingAlgo:mldsa65`
authentications alongside `rsa2048` ones, so ML-DSA PKAM connections were made
and accepted. Both arms fail at the same rate, so **posture is not what
distinguishes them**, and a pqActive cell is no worse off than a legacy one.

The silent cases carry a signature worth keeping:
`Monitor|Failed to start notifications: Exception: The connection went away
before a response arrived` (`AT0014`). That is monitor-readiness flakiness of
the same family as
[14.34](implementation-plan.md#1434-an-unexplained-intermittent-in-self_enrollment_retrofit_live_testdart),
not an algorithm problem.

⚠️ **Read the residual rate as the rig's, not the product's.** Both runs aborted
on `AT0014` before finishing, which is why the denominators are 18 and 20 rather
than 20 and 20; and the probe builds 20 clients for one atSign in a single
process, which is not a shape production has. It also tested monitor
*readiness*, not end-to-end delivery. What the measurement supports is the
comparison between the arms, not the absolute number.

⛔ **An earlier version of this probe reported 6 of 30 pqActive monitors silent,
and that figure was entirely the rig's.** It held every client open, so the last
arms of each run hit the atServer's `inbound_max_limit` — the far-side log said
`Wrote stats to 12 monitor connections` — and it ran 3 control arms against 10
pqActive arms, so the control never reached the iterations where the failure
appeared. Releasing each listener and making the arms equal and interleaved
removed it; the fixed rig's far-side control reads
`Wrote stats to 1 monitor connection`.

⛔ **This paragraph carried a hypothesis that is now DISPROVEN, 2026-08-23.** It
said this and the unexplained intermittent in
`self_enrollment_retrofit_live_test.dart` were probably the same problem, "a
monitor's own authenticated socket disagreeing with the client's signing
algorithm". They are not. `NotificationServiceImpl` has built its Monitor with
`signingAlgoType: signingAlgoOf(atClient)` since **2026-08-10**, before both
observations — checked against the tree as it stood on 2026-08-17 and
2026-08-19. And that intermittent's `signingAlgo:rsa2048` monitor was the
**legacy** client's of the two live at the time, correctly RSA, so it is not a
plumbing fault either; its own narrowed question — which monitor the atServer
considered a subscriber — stands unchanged.

**A second candidate was raised and also disproven.** `signingAlgoOf` falls back
to `preference.signingAlgoType` (default `rsa2048`) whenever
`_resolveSigningAlgoFromKeyMaterial` (`at_client_impl.dart:1582`) records null,
and that path throws nothing and logs nothing — so it looked like a silent way
for a PQ client to authenticate RSA. The probe showed the fallback firing on the
**control** arm only, which is correct by design: a legacy enrollment holds no
typed authentication material, so a null resolution is what
`signingAlgorithmForEnrollment` should return. It is the documented legacy
fallback working, not a defect.

⚠️ **The probe's own output labelled that control-arm null "this is the
defect".** That label was the rig's, written before the run, and it was wrong —
worth recording because a rig that prints a verdict will have that verdict
quoted back as a finding.

Settling anything here needs the atServer's own log, which has no near-side
representation: copy it out with `docker cp test-virtualenv-1:/apps/logs <dir>`
**before** the teardown, since `runLocal.sh` ends in `docker compose down`.

**`manifest.dart` cannot be imported by the packs.** It lives under
`packages/at_client/test/`, which no other package can reach, so the in-pack
rails need it moved to `lib/` first.

**`provenIn`'s matcher needs to require a `test(` token**, and that cannot be a
naive substring check: 53 declarations put `test(` and the name on separate
lines, so a naive tightening would falsely redden about a fifth of the
citations.

### The build order, and what it leaves

Not ruled — this is the measured recommendation, and the decision is gkc's. Arm
1 and the ledger first, both on the VE, since neither needs a new environment,
arm 1 executes UC-C1.2 for the first time, and the ledger is what turns the
other 38 rows from a claim into a report. Arms 3 and 4 follow once the monitor
breakage is diagnosed, rather than beside it, since both introduce a new
environment and a new failure surface at the same moment.

Four residues this catalogue states rather than hides:

- **UC-B0.1** belongs to the `legacy_server_tests` job and cannot be a cell
  until arm 4 exists.
- **UC-B2.2** needs the grace-0 secondary that only
  `tests/at_end2end_test/runLocal.sh` provisions, so the functional pack cannot
  host it.
- **UC-C1.4**'s Given is unprovable live by an existing ruling.
- **The 3 vacuous-at-legacy rows** — UC-A4.3, UC-B5.4 and UC-B1.3 — have an
  invariant Then and a Given that legacy cannot satisfy, since
  `seedNamespaceKeys: false` means there is no nskey to convey. A legacy cell
  would pass while measuring nothing, which is the failure a matrix is worst at
  showing.

One thing remains open: the transition arm re-mints, and the matrix's recorded
constraint against re-minting was written for a shared-atSign world. A fresh
per-arm atSign is what makes the two compatible, and that reasoning has not yet
been proven by a run.

**UC → project coverage** (cross-ref only — the authoritative sequence / dependency
graph / effort lives in `implementation-plan.md`; this is the one place acceptance.md
restates project IDs, and only as a coverage map):

| UC cluster                                                                      | Project(s)                      |
|---------------------------------------------------------------------------------|---------------------------------|
| A1.1 (PQ-native onboard, [Decision #1](detail/decisions.md#numbered-rulings-14), B4.2) | **ON-1**                        |
| A2.x / A3.x / A4.x / A5.x                                                       | **SS-2, SS-4, B-1, B-2, RF-2b** |
| A2.4 / A3.5 / A4.5 / A4.6 / A4.7 (KEM selection + construction negotiation)      | **KE-1**                        |
| B0.x / B1.x / B2.x / B3.x / B4.x / B5.x                                         | **RF-2c** (retrofit) + **RF-SRV** (server self-enroll — on the GA critical path per [`decisions.md` 40](detail/decisions.md#40-rf-srv-is-the-mechanism-the-whole-model-stands-on-2026-08-05)); the B3.x/B4.x data-path halves are built (B-1 + the decisions-36 ladder; R-1's surviving scope is the `disallowLegacyEncryption` flag) |

| C1.x (the rollout driven by flags: era, refusal, envelope, key exchange, retrofit, grouped posture) | **Workstream A** (the rollout-posture capstone, [`decisions.md` 70](detail/decisions.md#70-workstream-a-capstone-pqposture-the-five-flags-as-one-value-2026-08-10)) — landed; the default-flip these rows will then guard is **R-2** |

Project names follow the `implementation-plan.md` scheme (RF-SRV / RF-2b /
RF-2c); Workstreams A and B are the cross-cutting strands of the "make it
right" pass rather than numbered projects.

- **Cross-ref:** `implementation-plan.md` (full plan, dependency graph, waves,
  effort, critical path); `design.md` (harness mechanics).


# Part C — The rollout, driven by flags

## 15. C1 · The rollout posture (capstone of `decisions.md` 56.4)

From the PQ project's view, at_client 4.0 is final-3.x code with different flag
defaults, so every stage of the rollout must be reachable from this codebase by
flag manipulation: each axis flipped in isolation, and all seven at once as
the grouped `PqPosture`. These rows assert the mechanism itself — the
posture reaching each flag's natural home, and every axis remaining
individually overridable — not the underlying crypto behaviours, which Parts A
and B already own.

### 15.1 UC-C1.1 — The era axis: a postured client writes PQ by default

- **Given:** a client built with `PqPosture.pqActive` and no
  app-named `crypto` config.
- **When:** its era `CryptoConfig` is adopted at construction.
- **Then:** new writes default to the nskey data path (the AES-GCM provider),
  while a migration-postured client's stay legacy; an app-named config beats
  both.

### 15.2 UC-C1.2 — The refusal axis: the posture disallows legacy writes

- **Given:** a preference built with `PqPosture.pqActive`.
- **When:** a write would fall back to the legacy provider.
- **Then:** it is refused (`LegacyEncryptionRefusedException`) because the
  posture set the flag.
- **And:** nothing but a posture can set it. There is no constructor argument
  and no setter, which is the deliberate exception to the per-axis override
  contract the other axes keep — a safety flag whose escape hatch defeats its
  purpose is not the same kind of thing as deployment policy.
- **And:** a posture asking for the refusal must also write post-quantum by
  default, or it is rejected at construction for refusing its own writes. So
  this axis never moves alone.

### 15.3 UC-C1.3 — WITHDRAWN: there is no envelope axis

**Withdrawn 2026-08-12** by [`decisions.md` 95](detail/decisions.md#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12)
ruling 1. Do not write this test: it asserts a mechanism that is being deleted.

It read: *given a client whose preference carries
`PqPosture.pqActive`, when any signer wraps a payload with no
per-signer version assigned, then the envelope goes out in the JWS (v2) shape*.
Every clause of it is void — `envelopeVersion` stops being a `PqPosture`
axis, there is one envelope shape rather than a postured choice between two,
and the trailing claim that a key package "freezes the threaded version in the
write-once `metadata.keyPackage`" was already false once `enroll:update`
reached `metadata` ([91](detail/decisions.md#91-signature-agility-the-apkam-auth-key-stops-being-the-enrollments-signing-key-2026-08-11)
ruling 13).

What replaces it belongs to the multi-signature rows in section 16, not here:
one shape, one or more signatures, strongest-understood verified and a refusal
on failure.

### 15.4 UC-C1.4 — The key-exchange axis: the posture names pq enrollment

- **Given:** a submitter composing an `AtEnrollmentRequest` under
  `PqPosture.pqActive`. Submission goes through `package:at_auth`,
  which cannot read a preference, so the posture's value is applied by
  whoever builds the request — together with the two things pq mode requires
  (the key-package builder and the symmetric-key resolver).
- **When:** the request is submitted as an `AtEnrollmentRequest.pq(...)`,
  which reports `keyExchangeMode = pq`.
- **Then:** no RSA-wrapped `apkamSymmetricKey` rides the wire; the approver
  mints and conveys instead; the bare-request default stays `legacy`, so the
  3.x wire is byte-identical until a posture or the at_auth major flips it.

### 15.5 UC-C1.5 — The retrofit axis: an argless retrofit follows the posture

- **Given:** a legacy atSign and a preference carrying
  `PqPosture.pqActive`.
- **When:** `selfRetrofit` runs with no `signingAlgo` argument.
- **Then:** the minted enrollment is ML-DSA. Under the legacy posture the
  same call mints RSA — the two postures resolve into different per-algorithm
  idempotence pools, which is what tells them apart live.

### 15.6 UC-C1.6 — The grouped posture: one value moves all seven axes

- **Given:** nothing but
  `AtClientPreference(posture: PqPosture.pqActive)`.
- **When:** a client, its signers, its enrollment submissions and its
  retrofits are built from that one preference.
- **Then:** all seven axes run the last stage's values — the pinned columns of the
  `decisions.md` 56.4 table — and each remains individually overridable
  (UC-C1.1, C1.2, C1.4, C1.5 and C1.7 prove the arms; C1.3 is withdrawn and
  its axis no longer exists). A bare preference runs the legacy posture,
  byte-identical to the pre-posture SDK.

### 15.7 UC-C1.7 — The signing-set axis: which keys an enrollment holds

- **Given:** a preference built with `PqPosture.pqActive` and no
  explicit `dataSigningKeyAlgorithms` argument.
- **When:** the set is read.
- **Then:** it is `{mldsa65}`, while a migration-postured preference's is
  empty — an enrollment that mints no signing key of its own keeps signing
  with its APKAM authentication key, whose public half is what stays
  published. An explicit argument beats the posture in both directions.
- **And:** an algorithm this build produces no envelope signature for
  (anything but `mldsa65` and `rsa2048`) is refused where it is named, at
  construction — not skipped at signing time, which would leave an app that
  asked for a post-quantum signature holding a classical one.
- **And:** the set is one of two independent posture axes,
  `dataSigningKeyAlgorithms` beside `authenticationKeyAlgorithm`, each carried
  by the posture and overridable per preference. They are two axes rather than
  one stage name because the keys have different audiences: only the atServer
  verifies the authentication key, while every peer verifies the signing key.

Covered by `packages/at_client/test/pq_posture_test.dart`.

## 16. G1 · Signature agility and the rollout matrix

⚠️ **The stages were redefined 2026-08-14 — [`decisions.md` 98](detail/decisions.md#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14).**
The middle stage moves the **authentication** key to ML-DSA-65 and mints a
fresh **RSA-2048 signing key** to be advertised in its place, because only the
atServer verifies the authentication key while every peer verifies the signing
key. Rows below written before that ruling may still describe it as "reader
capability only"; where they do, the ruling governs. The stages were renamed
`legacy`/`pqReady`/`pqActive` by
[ruling 113](detail/decisions.md#113-pqposture-three-postures-and-the-rollout-they-drive-2026-08-18),
which also split the one enum that named them into two posture axes.

| | auth key | signing key | `_apsk` |
|---|---|---|---|
| `legacy`   | `rsa2048` | none — the auth key signs | bare RSA (the auth key) |
| `pqReady`  | `mldsa65` | `rsa2048` | bare RSA (the signing key) |
| `pqActive` | `mldsa65` | `mldsa65` active, `rsa2048` retired | the array |

Acceptance for [`decisions.md` 91](detail/decisions.md#91-signature-agility-the-apkam-auth-key-stops-being-the-enrollments-signing-key-2026-08-11);
design in [`design.md` 9](design.md#9-subsystem-g--signature-agility-the-authsigning-key-split).

The rows below run in `tests/at_functional_test` against the locally built
`at_virtual_env:local`, using dedicated atSigns and run-unique
`appName`/`deviceName` — rekey and rotation mutate one-shot server state, so a
fixed identifier passes once and collides on the next run.

### 16.1 The harness

Two stage-parameterised executables, a sender and a receiver, each taking
`--stage published|legacy|pqReady|pqActive`, plus a driver that runs the
matrix.

**What the pair exercises** (ruled [`decisions.md` 93](detail/decisions.md#93-the-d1-remaining-work-sequence-and-the-rollout-axis-becomes-real-2026-08-11)
ruling 3) — the whole story, not the shapes:

- the signed-envelope exchange;
- a real notification and data path;
- **multiple puts and gets**, not a single notification — a shape that survives
  one exchange and breaks on the second is the failure this catches;
- enrollment followed by an **`enroll:update` APKAM rotation mid-run**, so the
  record-authoritative path is proven to survive a rotation in every posture.

**The `published` arm runs the last released at_client**, not a `--stage now`
build of this tree. This closes what was previously recorded here as an
un-mitigated known limit. One build simulating `legacy` exercises the stage logic
and nothing else: both arms run the same code, so a bug in what a build
predating this work does with a v1 envelope stays invisible to it. Simulating
both sides of a compatibility claim inside one build proves nothing about the
side nobody wrote — the published arm is the only thing that measures
"`legacy` behaves identically to current legacy" rather than asserting it.

It earned that keep before a single cell ran. The arm exists to answer
questions about the released build with a measurement, and the first one it
answered contradicted this document: 3.14.0 ships an envelope reader and writer
after all, and neither build can read the other's envelope
([16.5](#165-the-rollout-matrix)). **What the published arm proves is therefore
the data path** — a real notification, multiple puts and gets — which is what a
released peer and this tree genuinely share. The signed-envelope exchange is a
`legacy`/`pqReady`/`pqActive` question.

### 16.2 The keyfile rows

#### UC-G1.1 — the derivation is offered, not applied
  *Given* a keyfile holding exactly one active `privateAuthentication`
  material.
  *When* a caller asks `AtKeys.resolveAuthenticatingEnrollment()`.
  *Then* it returns that material's enrollment id; with two it throws naming
  both; with none it returns null.
  *And* authentication does **not** apply it: handed a request with no
  enrollment id, `AtAuthImpl.authenticate` uses the flat stored
  `AtKeys.enrollmentId` — on a retrofitted file deliberately the legacy
  enrollment, not the active typed material's.

  ⚠️ **This row read "the enrollment id is derived, not stored", and asserted
  that a client reading with no id supplied authenticates as the active
  material's enrollment. Both halves were false.** The implicit derivation it
  described (`AtKeys.activeEnrollmentId`) existed for three days — added
  2026-08-11, the day this row was written, and deleted 2026-08-14 by
  [`decisions.md` 100](detail/decisions.md#100-the-seven-shapes-ruling-99-left-open-2026-08-14)
  ruling 1, which replaced guessing with a resolver you invoke by name.
  `resolveAuthenticatingEnrollment()` has **zero production callers**, which is
  the point of it rather than a gap. Corrected 2026-08-18.

#### UC-G1.2 — a retrofit leaves exactly one active authentication key, and touches nothing legacy
  *Given* a legacy keyfile that then retrofits.
  *When* the retrofit completes.
  *Then* the new APKAM material is `active` under the new enrollment id and is
  the only active `privateAuthentication` in the document; the legacy APKAM
  keypair is left in the flat fields **byte-identical and statusless**; and
  UC-G1.1's resolver returns the new enrollment id.

  ⚠️ **This row said "the legacy APKAM material is `retired`", and there is no
  such material to retire.** The legacy keypair lives in the flat
  `apkamPublicKey`/`apkamPrivateKey` fields, which are `AtBytes?` with no
  status field at all; the retrofit leaves them untouched so the capped legacy
  enrollment goes on authenticating, and the legacy enrollment is capped by the
  atServer rather than by the client. The file-wide invariant does hold, but
  **vacuously** — `refuseSecondLiveEnrollment` only ever sees typed materials,
  so the flat key is invisible to it. A scenario written to the old wording
  would have gone red, or worse prompted someone to clear those fields, which
  is exactly what the byte-identical legacy round-trip forbids. Corrected
  2026-08-18.

#### UC-G1.3 — retirement frees the slot
  *Given* an active `privateAuthentication` for enrollment E.
  *When* it is retired and a replacement filed under the same enrollment.
  *Then* `addKey` accepts it under a **new** keyId, because the invariants
  count only `active` material. A replacement re-using the retired key's keyId
  is still refused — that check is status-blind. Contrast arm: without the
  retire, the add throws from `AtKeysAssurance.refuseSecondLiveEnrollment`.

  ⚠️ **This row said "— the arm that throws today", and that clause was false
  92 minutes after it was written**: `c7e2ccef4` made both invariants
  status-aware the same evening. [`decisions.md` 91](detail/decisions.md#913-the-rulings)
  ruling 4 still carried the same stale probe result and is amended in place.
  Corrected 2026-08-18.

#### UC-G1.4 — opening a legacy keyfile does not upgrade it
  *Given* a `.atKeys` file in the pure legacy shape.
  *When* a new build reads it, changes nothing, and flushes.
  *Then* the re-emitted document holds the same fields with the same values and
  **no `version`, `atsign`, `enrollments` or `atsignKeys` key** — every
  self-encrypted field's ciphertext unchanged, and only the key **order** may
  differ, because the emitter has one fixed order. A `version: 1` document
  carrying a top-level `keys` array is **refused by name**, not read as legacy.

  ⚠️ **Both of this row's sentences were wrong.** It promised the file comes
  back *byte-identical*, which a foreign-ordered legacy file does not — the
  guarantee is field-for-field. And it said "a `version: 1` file holding
  `keys: []` comes back as pure legacy", which is now the **opposite** of the
  code: since `cb3848b4d` (2026-08-14) `AtKeys.fromJson` throws on
  `containsKey('keys')`, empty array included, because reading it would file
  the material as legacy metadata and authenticate as the wrong enrollment.
  Corrected 2026-08-18.

### 16.3 The wire rows

#### UC-G1.5 — a bare-string `_apsk` still verifies
  *Given* an `_apsk` published by at_client **3.13.0** — a bare public-key
  string, from that release's `mixins/apkam_signing.dart`.
  *When* a current build verifies an envelope from that enrollment.
  *Then* it succeeds, reading the record as a single `rsa2048` entry. The
  writer arm must show the current build **still emits** that shape:
  `bareApskValueOf` spells a single active `rsa2048` entry as the bare string,
  which is what keeps `legacy` and `pqReady` readable by un-upgraded peers
  ([`decisions.md` 98.1](detail/decisions.md#981-the-stages)); only a second
  key, or a non-`rsa2048` key, forces the array.

  ⚠️ **The writer sentence read "never emits that shape" and was inverted.**
  The current build emits it deliberately, under the default posture, and
  ruling 98.1 requires it. A writer arm written to the old wording would have
  asserted the opposite of a property the rollout depends on. Corrected
  2026-08-18; the sentence it was copied from, in ruling 91.4's release table,
  is amended in the same sweep.

#### UC-G1.6 — an unversioned envelope is refused, and the refusal names why
  *Given* (a) the released 3.14.0 flat envelope — a bare `signature` sibling of
  the payload, no `v` — and (b) a current-shape envelope whose protected header
  omits `v`.
  *When* a current build reads (a) and verifies (b).
  *Then* (a) is refused at parse, and (b) is refused at verify naming the
  version it read. There is deliberately no tolerant reading.

  ⚠️ **This row said an unversioned envelope "still verifies", and the code
  refuses it twice over.** [`decisions.md` 95](detail/decisions.md#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12)
  deleted the predecessor shapes rather than carrying them, so
  `SignedEnvelope.fromJson` requires a non-empty top-level `signatures` array
  and a document whose signature is a flat sibling of the payload never
  parses. The tree already pins this row's exact opposite as an accepted break,
  in `released_envelope_incompatibility_test.dart`. Corrected 2026-08-18.

#### UC-G1.7 — the verifier takes the strongest and does not fall back
  *Given* an envelope carrying valid `rsa2048` and **corrupted** `mldsa65`
  signatures, against an `_apsk` advertising both.
  *When* a build that implements ML-DSA verifies it.
  *Then* it **refuses**, naming the ML-DSA failure — it must not fall through
  to the valid RSA signature. The control arm, both signatures valid, passes.

  ✅ **Covered 2026-08-13** — `test/jws_envelope_test.dart`, group `UC-G1.7`.
  Four rows: the control arm, the corrupt-ML-DSA refusal (asserted on a message
  naming `mldsa65`, since one naming RSA would mean the weaker entry was
  checked), the same verdict under either listing order — RSA is listed first,
  so a reader taking the last entry would pass a one-order pin — and an
  envelope whose entries claim two different signers, refused at parse. That
  last one is not in the row as written and belongs with it: without it the
  entry that verifies and the entry a caller reads `signerEnrollmentId` from
  can differ, so appending a signature under a stronger algorithm carrying
  another kid makes a caller act on a signer whose signature was never checked.

#### UC-G1.8 — the rollout-1 signing key stays verifiable after rollout 2, even under its own algorithm
  *Given* an envelope signed at rollout 1 by the enrollment's **RSA-2048
  signing key** — the one it holds from birth, minted before it submitted and
  advertised bare in place of the APKAM authentication key.
  *When* the enrollment moves to rollout 2: it mints ML-DSA-65, retires the RSA
  key and republishes `_apsk` as an array.
  *Then* the stored envelope still verifies, against the RSA key's `retired`
  entry.
  *And* this holds when a retained entry names the **same algorithm** as an
  active one — two generations of one algorithm, `sign:<algo>:1` retired beside
  `sign:<algo>:2` active. The verifier resolves the algorithm first and then
  tries every key advertised under it rather than the first, proven in
  `packages/at_client/test/jws_envelope_test.dart`, test "an envelope signed by
  the retained key still verifies".

  ⚠️ **This row named the APKAM authentication key, and no code path can put
  that key in `_apsk` as `retired`.** `apskEntries` adds the authentication key
  on exactly one condition — the entry list being empty — and adds it
  **active**; the only thing that carries a withdrawn status is fed from
  `AtKeys.withdrawnSigningKeysFor` (named `retiredSigningKeysFor` until
  2026-08-22), which selects `sign:` keyIds while the APKAM keypair is filed
  under `auth:`. The Given was impossible too: at rollout 1
  the enrollment holds its own signing key from birth, so the auth key never
  signs and there is no envelope of its to preserve — [`decisions.md` 98](detail/decisions.md#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14)
  ruling 2 reversed the retention this row was written against. The cited group
  was real but proved something else: two **ML-DSA signing** keys sharing an
  algorithm, not the auth key. Corrected 2026-08-18.

#### UC-G1.9 — a retired algorithm still verifies history
  *Given* an algorithm dropped from the in-use set.
  *Then* new envelopes carry no signature of it, its `_apsk` entry remains with
  `status: retired`, and an envelope signed with it before the drop still
  verifies.

  ✅ **Covered 2026-08-14** — `packages/at_client/test/signing_key_minting_test.dart`,
  group "a stage transition". Eight rows, of which the last is this one: an
  envelope signed while the in-use set was `{rsa2048}`, verified again after
  the move to `{mldsa65}` against the `_apsk` value the client published on
  the way. It runs on the **no-enrollment** arm deliberately, because that is
  the path where this client composes the `_apsk` *value* — on the enrolled
  path it hands entries to the atServer, and a test there would have to
  reconstruct the wire form and would then be pinning the reconstruction.
  The stage transition itself was covered nowhere before this: the rollout
  matrix copies a fresh keyfile per cell, so every cell measures a client born
  at its stage and none moves between two.

#### UC-G1.9a — the client mints what the in-use set names, advertising before filing
  *Given* an enrollment holding no signing key of its own and a preference
  whose in-use set names one.
  *When* the client starts.
  *Then* it mints that keypair, advertises it — by `enroll:update` where there
  is an enrollment record and by publishing `_apsk` directly where there is
  not — and **only then** files it, so no envelope is ever signed under a key
  the advertisement does not name. A second start mints nothing, and an empty
  in-use set mints nothing at all.
  Covered by `packages/at_client/test/signing_key_minting_test.dart`.

### 16.4 `enroll:update` rows

#### UC-G1.10 — rekey keeps the enrollment id
  *Given* an approved enrollment authenticated on its own connection.
  *When* it sends `enroll:update` with a new `apkamPublicKey`, `signingAlgo`
  and a valid `apkamPublicKeySignature`.
  *Then* the record's key is replaced, the id, appName, deviceName, namespaces
  and approval state are untouched, and the **new** key authenticates while the
  old one no longer does. `_apsk` is **not** rewritten: this request names three
  fields and `apsk` is not one of them, so the client sends none and the
  atServer leaves the record's own value alone.

  ⚠️ **This row claimed "`_apsk` is rewritten from the request's `apsk`"**,
  which its own *When* forbids — a rotation sends `apkamPublicKey`,
  `signingAlgo` and `apkamPublicKeySignature`, and nothing else. Corrected
  2026-08-18.

#### UC-G1.11 — proof of possession is required
  *Given* the same request with `apkamPublicKeySignature` absent, or signed by
  a key other than the one being installed.
  *Then* the atServer refuses and the record is unchanged. Both arms run: a
  missing signature and a wrong one must each be refused, and the valid arm
  must succeed, or the test is comparing a case with itself.

#### UC-G1.12 — namespaces stay out of reach, and approval state has no reach to stay out of
  *Given* an `enroll:update` naming `namespaces`.
  *Then* the atServer refuses it by its own named error, not by "it failed" —
  this is the privilege-escalation guard.
  *And* the client cannot name either one: the update request carries no field
  for namespaces or approval state at all.

  ⚠️ **This row paired the two as though they were the same guard.** They are
  not: there is **no approval-state field anywhere on the request**, so no
  request can name one and nothing refuses one. A scenario written literally
  against the old wording would have looked for a refusal that cannot exist.
  Corrected 2026-08-18.

#### UC-G1.13 — self-only
  *Given* an `enroll:update` for enrollment E sent on a connection
  authenticated as a different enrollment, and separately on one carrying no
  enrollment id at all.
  *Then* each is refused, by the self-only check.

  ⚠️ **This row promised two guards and its *Given* can only ever reach one.**
  The self-only check runs **before the target record is fetched**, so the
  target's approval state is never read on any path the row describes — the
  four repeats over pending, denied, revoked and expired targets are the same
  measurement four times, and none of them exercises an approved-only guard.
  Corrected 2026-08-18; the approved-only property belongs to the *caller's*
  own enrollment and is a different row.

### 16.5 The rollout matrix

Sender stage × receiver stage. Every cell runs. **No cell fails**, and the
sentence that used to stand here — "the failing cells are asserted by their
specific error" — described two cells that were measured out of existence; see
the note at the end of this section. The principle it states still governs the
incompatibility pins below, which is where the specific errors now live.

The matrix is over the **data path** — a real notification, multiple puts and
gets, the records a peer actually exchanges. All sixteen cells pass, and that
is the claim worth measuring: nothing in the auth/signing split changes what a
peer at any stage can send to or read from a peer at any other.

| Sender ↓ / Receiver → | published | now | rollout 1 | rollout 2 |
|-----------------------|-----------|-----|-----------|-----------|
| **published** | pass | pass | pass | pass |
| **now**       | pass | pass | pass | pass |
| **rollout 1** | pass | pass | pass | pass |
| **rollout 2** | pass | pass | pass | pass |

**The `published` row and column are the control.** They must behave
identically to the `legacy` row and column in every cell. If `published` and `legacy`
ever diverge on the data path, the `legacy` stage is not the faithful legacy
simulation it claims to be, and every other result in the matrix is measured
against the wrong baseline. That divergence is the finding, not a harness bug
to work around.

#### The signed-envelope exchange is a 3×3, and why

The envelope exchange is a `legacy`/`pqReady`/`pqActive` question, because **a
released client and this tree cannot exchange an envelope in either direction,
under any stage** — measured 2026-08-14 by cross-feeding each build's shape to
the other's reader:

| Direction | Result |
|-----------|--------|
| this tree → at_client 3.14.0 | `_TypeError: type 'Null' is not a subtype of type 'String' in type cast` |
| at_client 3.14.0 → this tree | `AtSigningVerificationException: an envelope must carry its payload as a string` |

This is not a rollout-2 effect and no stage avoids it. Step 3 replaced the
released envelope — a flat
`{payload, signature, hashingAlgo, signingAlgo, enrollmentId}` map — with RFC
7515 general serialization, and deleted the envelope as a `PqPosture`
axis, so `legacy` emits the new shape too.

**It is accepted rather than fixed**, on what the released reader actually is:
a same-atSign path only (both 3.14.0 call sites pass
`signerAtSign: getCurrentAtSign()`), reachable only through
`AtClientSecretSharing.forClient`, which nothing inside at_client 3.14.0
constructs, which is `@experimental`, and whose own dartdoc opens "⚠ Not yet
suitable for production secrets". 3.14.0's `AtClientImpl.start()` is a two-line
no-op, so no post-quantum path starts on its own there. The affected consumer
is an app that opted into an API documenting itself as unusable for the purpose.

Both errors are pinned as raw literals, in both directions, in
`packages/at_client/test/released_envelope_incompatibility_test.dart` — an
incompatibility that is accepted has to stay *visible*, and a break nobody
asserts is indistinguishable from a break that quietly changed shape.

⚠️ That sentence stood here for a day before the tests existed, asserting a
guard nothing provided. It was caught by a context-free reader auditing the
handoff, who grepped for the two literals and found them in prose only. A
"pinned" claim is checkable in one grep, and this one was false — which is
worth more as a recorded near-miss than as a silently corrected line, because
the accepted-break ruling in
[`decisions.md` 95](detail/decisions.md#95-the-envelope-keeps-one-shape-and-a-retained-key-says-so-2026-08-12)
rests on exactly this visibility.

**The `legacy`/`pqReady`/`pqActive` envelope grid is built** — UC-G1.15 below,
2026-08-18. ⚠️ **This paragraph read "is not built … owed rather than done"
until then**, and its reasoning was half wrong as well: it said the three
stages emit byte-identical envelopes because "nothing files per-algorithm
signing material until rollout 2 mints it". Rollout 2 *does* mint it, on this
harness, because the `current/` arm attaches with an `AtKeysIo` — which is the
one difference the README calls out as the reason the arms are not
interchangeable. Measured: a `pqActive` sender's envelope carries `ML-DSA-65`
and a `legacy` sender's carries `RS256`.

The grid rides the nine cells where both halves are this tree, and its value is
indeed in the rollout-2 row: under
[`decisions.md` 108](detail/decisions.md#108-the-signing-rollout-swaps-algorithms-it-never-overlaps-them-2026-08-18)
the ladder swaps algorithms rather than overlapping them, so `pqActive →
pqReady` — strongest signer, weakest verifier — is the cell an overlapping
ladder would have existed to rescue. It passes, which is what makes 108 a
measurement rather than a ruling.

⚠️ This section previously showed two failing cells,
`rollout 2 → published` and `rollout 2 → now`, both attributed to
`IllegalStateException`, `_apsk` value is not a String, with the note that they
were "the whole argument for capability-before-active". Both the cells and the
error were wrong: `apskValueOf` publishes the array as a JSON **string**, so
`getApkamPublicKey`'s `av.value is! String` guard never fires on it, and this
tree's reader is ungated (step 19: "the reader half needs no gate"), so a `legacy`
receiver reads the array as readily as a `pqReady` one. The argument for
capability-before-active is unaffected and lives in
[`decisions.md` 93](detail/decisions.md#93-the-d1-remaining-work-sequence-and-the-rollout-axis-becomes-real-2026-08-11);
what is gone is the claim that this matrix demonstrates it.

#### UC-G1.15 — every rollout stage verifies every other stage's envelope
  *Given* a sender and a receiver, each at one of `legacy`, `pqReady`,
  `pqActive` — nine cells, both halves this tree.
  *When* the sender signs an envelope at its stage, leaves it on the atServer,
  and the receiver fetches the sender's `_apsk` and verifies it with its own
  build.
  *Then* every cell verifies, and the algorithms the receiver saw are the ones
  the sender emitted.

  **The cell this exists for is `pqActive → pqReady`**: an ML-DSA-65 signature
  read by a client that signs RSA-2048. It passes, which is what
  [`decisions.md` 108](detail/decisions.md#108-the-signing-rollout-swaps-algorithms-it-never-overlaps-them-2026-08-18)
  rests on — a swap is safe precisely because verification is not staged.

  ⚠️ **Nine green cells do not on their own prove anything about the stages**,
  and that is not hypothetical here: mutating `pqActive` to resolve as
  `pqReady` leaves **all nine cells passing**, because a sender signing
  RSA-2048 verifies everywhere too. What catches it is the algorithm assertion
  — `pqActive → pqActive` must be exactly `['ML-DSA-65']` and `legacy →
  legacy` must
  not contain it. Measured 2026-08-18, both arms in one session: the mutation
  reddens on that assertion naming `['RS256']`, and the revert is green.
  Proven in `tests/at_functional_test/test/pq_rollout_matrix_test.dart`, test
  `UC-G1.15`.

#### UC-G1.14 — pqReady is invisible to a deployed peer
  *Given* a sender at rollout 1 — an ML-DSA-65 authentication key and a freshly
  minted RSA-2048 signing key.
  *When* a **published-arm** client (at_client 3.14.0, resolved from pub.dev)
  fetches that enrollment's `_apsk`.
  *Then* `getApkamPublicKey` returns a String which base64-decodes as an RSA
  public key, exactly as it does for a `legacy` sender — so the released reader
  cannot tell the two stages apart.

  ⚠️ **The invisibility is bounded: it ends when this enrollment re-mints or
  rotates its signing key.** Retired keys stay advertised, so the first re-mint
  takes the record out of the bare form permanently — it becomes the JSON array
  form, which the released reader cannot parse. From then on the stage is
  fail-closed visible: the deployed peer gets an error rather than a key it can
  misread. Observed when a per-cell-minting draft of the live matrix
  (`pq_rollout_matrix_test.dart`) failed this row's own cell; the fail-closed
  half rests on that observation and is not separately proven as a row.

  ⚠️ **This row used to read "rollout 1 changes nothing on the wire", asserting
  the envelopes and the `_apsk` were byte-identical to the `legacy`/`legacy` cell.**
  That is false under [`decisions.md` 98](detail/decisions.md#98-rollout-1-moves-the-authentication-key-not-the-signing-key-2026-08-14):
  rollout 1 publishes a *different key* from `legacy` — its own signing key rather
  than its authentication key — so the bytes differ by design. What must hold
  is the **form**, and only a released reader can settle that. Byte-identity
  was a claim about our own writer; this is a measurement against the reader
  that actually matters.
